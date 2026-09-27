import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/image_edit.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/widgets/image_editor_screen.dart';

Future<Uint8List> _bluePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), ui.Paint()..color = const ui.Color(0xFF0000FF));
  final image = await recorder.endRecording().toImage(width, height);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// RGBA des Pixels an (x, y).
Future<int> _pixel(Uint8List png, int x, int y) async {
  final image = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return rgba.getUint32((y * image.width + x) * 4);
}

/// Lässt echte Bildverarbeitung (Dekodieren, Rendern, PNG) laufen – jede
/// Stufe braucht eine echte Async-Lücke plus einen Frame.
Future<void> _settleImageWork(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  group('applyImageEdits', () {
    test('Abdecken füllt den Bereich in Originalauflösung, der Rest bleibt', () async {
      final png = await _bluePng(200, 100);
      final edited = (await applyImageEdits(png, const [
        CoverEdit(ui.Rect.fromLTRB(0.5, 0.0, 1.0, 0.5)),
        CoverEdit(ui.Rect.fromLTRB(0.0, 0.5, 0.25, 1.0), dark: true),
      ]))!;
      expect(await _pixel(edited, 150, 20), 0xFFFFFFFF); // weiß abgedeckt
      expect(await _pixel(edited, 20, 80), 0x111111FF); // schwarz abgedeckt
      expect(await _pixel(edited, 100, 80), 0x0000FFFF); // unverändert blau
    });

    test('Beschriften legt einen hellen Kasten um den Text', () async {
      final png = await _bluePng(200, 100);
      final edited = (await applyImageEdits(png, const [TextEdit(ui.Offset(0.5, 0.5), 'A', size: 0.2)]))!;
      // Rand des Kastens (Padding links vom Buchstaben) ist hell, weit weg bleibt blau.
      final left = await _pixel(edited, 86, 50);
      expect(left & 0xFF000000, greaterThan(0xC0000000)); // Rotanteil hoch = hell
      expect(await _pixel(edited, 5, 5), 0x0000FFFF);
    });

    test('ohne Bearbeitung unverändert, kaputtes Bild -> null', () async {
      final png = await _bluePng(10, 10);
      expect(identical(await applyImageEdits(png, const []), png), isTrue);
      expect(await applyImageEdits(Uint8List.fromList([1, 2, 3]), const [CoverEdit(ui.Rect.fromLTRB(0, 0, 1, 1))]),
          isNull);
    });
  });

  group('ImageEditorScreen', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(800, 1200);
      binding.platformDispatcher.views.first.devicePixelRatio = 1;
    });
    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });

    Rect canvas(WidgetTester tester) => tester.getRect(find.descendant(
          of: find.byKey(const ValueKey('image-editor-canvas')),
          matching: find.byType(Stack),
        ).first);

    testWidgets('Abdecken per Rahmen ziehen und übernehmen', (tester) async {
      final png = (await tester.runAsync(() => _bluePng(200, 100)))!;
      ImageEditResult? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showImageEditor(context, png),
            child: const Text('Öffnen'),
          ),
        ),
      ));
      await tester.tap(find.text('Öffnen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Seitenübergang
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      final box = canvas(tester);
      await tester.dragFrom(Offset(box.left + box.width * 0.1, box.top + box.height * 0.1),
          Offset(box.width * 0.3, box.height * 0.4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await _settleImageWork(tester);

      expect(result, isNotNull);
      expect(result!.imageChanged, isTrue);
      final covered = (await tester.runAsync(() => _pixel(result!.bytes, 40, 25)))!;
      expect(covered, 0xFFFFFFFF);
      final untouched = (await tester.runAsync(() => _pixel(result!.bytes, 180, 90)))!;
      expect(untouched, 0x0000FFFF);
    });

    testWidgets('Stellen setzen: antippen, Beschriftung eingeben, Rückgängig', (tester) async {
      final png = (await tester.runAsync(() => _bluePng(200, 100)))!;
      ImageEditResult? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showImageEditor(context, png, targetMode: ImageTargetMode.labels),
            child: const Text('Öffnen'),
          ),
        ),
      ));
      await tester.tap(find.text('Öffnen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Seitenübergang
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      // Ohne Stelle lässt sich nicht übernehmen.
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(find.text('Setz mindestens eine Stelle mit Beschriftung.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // Hinweis ausblenden lassen
      await tester.pumpAndSettle();

      final box = canvas(tester);
      for (final (fx, label) in [(0.25, 'Zellkern'), (0.75, 'Mitochondrium')]) {
        await tester.tapAt(Offset(box.left + box.width * fx, box.top + box.height * 0.5));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), label);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      expect(find.text('1 · Zellkern'), findsOneWidget);
      expect(find.text('2 · Mitochondrium'), findsOneWidget);

      await tester.tap(find.byTooltip('Rückgängig'));
      await tester.pumpAndSettle();
      expect(find.text('2 · Mitochondrium'), findsNothing);

      await tester.tap(find.text('Übernehmen'));
      await _settleImageWork(tester);
      expect(result!.imageChanged, isFalse);
      expect(result!.targets.single.label, 'Zellkern');
      expect(result!.targets.single.x, closeTo(0.25, 0.02));
      expect(result!.targets.single.y, closeTo(0.5, 0.02));
    });

    testWidgets('Bereich für Bild markieren aufziehen', (tester) async {
      final png = (await tester.runAsync(() => _bluePng(200, 100)))!;
      ImageEditResult? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showImageEditor(context, png, targetMode: ImageTargetMode.regions),
            child: const Text('Öffnen'),
          ),
        ),
      ));
      await tester.tap(find.text('Öffnen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Seitenübergang
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      final box = canvas(tester);
      await tester.dragFrom(Offset(box.left + box.width * 0.4, box.top + box.height * 0.3),
          Offset(box.width * 0.2, box.height * 0.4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await _settleImageWork(tester);

      final region = result!.targets.single;
      expect(region.x, closeTo(0.5, 0.03));
      expect(region.y, closeTo(0.5, 0.03));
      expect(region.w, closeTo(0.2, 0.03));
      expect(region.h, closeTo(0.4, 0.03));
    });
  });
}
