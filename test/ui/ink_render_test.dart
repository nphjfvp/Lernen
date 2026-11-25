import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/tasks/ink_sheet.dart';

/// Zählt Zeichenbefehle.
class _CountingCanvas implements Canvas {
  int paths = 0;
  int lines = 0;
  int circles = 0;

  @override
  void drawPath(Path path, Paint paint) => paths++;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines++;

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<Offset> _stroke(int n, {double x0 = 10, double y0 = 10}) =>
    [for (var i = 0; i < n; i++) Offset(x0 + i * 1.5, y0 + (i % 7) * 1.2)];

void main() {
  test('ein Strich mit wechselnder Stärke braucht nur wenige Pfade, keine Einzellinien', () {
    final canvas = _CountingCanvas();
    final points = _stroke(41);
    paintInk(canvas, points, [for (var i = 0; i < 41; i++) 2.4 + (i % 5) * 0.05], Colors.black);
    expect(canvas.lines, 0);
    expect(canvas.paths, lessThanOrEqualTo((40 / inkChunkSegments).ceil() + 1));
    expect(canvas.paths, greaterThan(0));
  });

  test('stark wechselnde Stärke teilt öfter, bleibt aber weit unter einem Befehl je Punkt', () {
    final canvas = _CountingCanvas();
    paintInk(canvas, _stroke(41), [for (var i = 0; i < 41; i++) i.isEven ? 1.5 : 3.5], Colors.black);
    expect(canvas.paths, lessThanOrEqualTo(40));
    expect(canvas.lines, 0);
  });

  testWidgets('im Browser-Modus werden fertige Striche als Bild zwischengespeichert', (tester) async {
    final oldCache = InkSheet.cacheStrokes;
    final oldDelay = InkSheet.cacheDelay;
    addTearDown(() {
      InkSheet.cacheStrokes = oldCache;
      InkSheet.cacheDelay = oldDelay;
    });
    InkSheet.cacheStrokes = true;
    InkSheet.cacheDelay = const Duration(milliseconds: 10);
    final ctrl = InkSheetController();
    for (var k = 0; k < 3; k++) {
      ctrl.add(_stroke(20, x0: 40.0 + k * 50, y0: 20), 600, widths: List.filled(20, 2.6));
    }
    final before = InkSheet.debugCacheBuilds;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 600, child: InkSheet(controller: ctrl, onCellsChanged: (_) {})),
        ),
      ),
    ));
    Future<void> settleCache() async {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    await settleCache();
    expect(InkSheet.debugCacheBuilds, before + 1, reason: 'vorhandene Striche gleich als Bild');

    // Ein neuer Strich: sofort sichtbar (gezeichnet), das Bild folgt kurz danach.
    ctrl.add(_stroke(20, x0: 300, y0: 20), 600, widths: List.filled(20, 2.6));
    await tester.pump();
    await settleCache();
    expect(InkSheet.debugCacheBuilds, before + 2);

    // Rückgängig/Radieren: das alte Bild passt nicht mehr und wird erneuert.
    ctrl.undo();
    await tester.pump();
    await settleCache();
    expect(InkSheet.debugCacheBuilds, before + 3);
    expect(tester.takeException(), isNull);
    // Beim Schließen wird das Bild freigegeben – ohne Fehler.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
