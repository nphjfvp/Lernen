import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/image_edit.dart';
import 'package:lernen/models/flashcard.dart';
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

    test('Koordinatenraster für die KI: Linien bei jedem Zehntel, Bildgröße bleibt', () async {
      final png = await _bluePng(200, 100);
      final gridded = (await drawCoordinateGrid(png))!;
      final image = (await (await ui.instantiateImageCodec(gridded)).getNextFrame()).image;
      expect(image.width, 200);
      expect(image.height, 100);
      // Auf der senkrechten 0.5-Linie (Mitte unten) liegt Farbe, abseits bleibt es blau.
      final onLine = await _pixel(gridded, 100, 75);
      expect(onLine, isNot(0x0000FFFF));
      expect(await _pixel(gridded, 105, 75), 0x0000FFFF);
    });

    test('Randskala: Striche nur am Rand, die Seitenmitte bleibt frei', () async {
      final png = await _bluePng(400, 600);
      final ruled = (await drawEdgeRuler(png))!;
      final image = (await (await ui.instantiateImageCodec(ruled)).getNextFrame()).image;
      expect(image.width, 400);
      expect(image.height, 600);
      // Strich bei 0.5 am oberen und linken Rand.
      expect(await _pixel(ruled, 200, 2), isNot(0x0000FFFF));
      expect(await _pixel(ruled, 2, 300), isNot(0x0000FFFF));
      // Innen bleibt alles unverändert, auch auf Höhe der Striche.
      expect(await _pixel(ruled, 200, 300), 0x0000FFFF);
      expect(await _pixel(ruled, 200, 150), 0x0000FFFF);
      expect(await drawEdgeRuler(Uint8List.fromList([1, 2, 3])), isNull);
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
        await tester.enterText(find.byKey(const ValueKey('editor-label-field')), label);
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

    Future<void> openEditor(WidgetTester tester, Future<void> Function(BuildContext) open) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(onPressed: () => open(context), child: const Text('Öffnen')),
        ),
      ));
      await tester.tap(find.text('Öffnen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Seitenübergang
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
    }

    testWidgets('Stellen verschieben und als austauschbare Gruppe markieren', (tester) async {
      final png = (await tester.runAsync(() => _bluePng(200, 100)))!;
      ImageEditResult? result;
      await openEditor(
        tester,
        (context) async => result = await showImageEditor(
          context,
          png,
          targetMode: ImageTargetMode.labels,
          targets: const [ImageTarget(x: 0.2, y: 0.5, label: 'Arbeit')],
        ),
      );

      final box = canvas(tester);
      // Die KI lag daneben: Stelle an die richtige Position ziehen.
      await tester.dragFrom(Offset(box.left + box.width * 0.2, box.top + box.height * 0.5),
          Offset(box.width * 0.4, -box.height * 0.2));
      await tester.pumpAndSettle();

      // Antippen öffnet die Stelle: Gruppe setzen.
      await tester.tapAt(Offset(box.left + box.width * 0.6, box.top + box.height * 0.3));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('editor-group-field')), 'Input');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('1 · Arbeit [Input]'), findsOneWidget);

      await tester.tap(find.text('Übernehmen'));
      await _settleImageWork(tester);
      final target = result!.targets.single;
      expect(target.x, closeTo(0.6, 0.03));
      expect(target.y, closeTo(0.3, 0.03));
      expect(target.group, 'Input');
      expect(result!.imageChanged, isFalse);
    });

    testWidgets('Text: Schriftgröße ändern und verschieben', (tester) async {
      final png = (await tester.runAsync(() => _bluePng(200, 100)))!;
      ImageEditResult? result;
      await openEditor(tester, (context) async => result = await showImageEditor(context, png));

      await tester.tap(find.text('Text'));
      await tester.pumpAndSettle();
      final box = canvas(tester);
      await tester.tapAt(Offset(box.left + box.width * 0.3, box.top + box.height * 0.3));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('editor-text-field')), 'ATP');
      // Regler ganz nach rechts = größte Schrift.
      await tester.drag(find.byKey(const ValueKey('editor-text-size')), const Offset(400, 0));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.dragFrom(Offset(box.left + box.width * 0.3, box.top + box.height * 0.3),
          Offset(box.width * 0.4, box.height * 0.4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await _settleImageWork(tester);

      final text = result!.edits.whereType<TextEdit>().single;
      expect(text.text, 'ATP');
      expect(text.size, closeTo(ImageEditorScreen.maxTextSize, 0.001));
      expect(text.position.dx, closeTo(0.7, 0.03));
      expect(text.position.dy, closeTo(0.7, 0.03));
    });

    testWidgets('vorgegebene Abdeckung (z.B. von der KI) verschieben, vergrößern, entfernen', (tester) async {
      final png = (await tester.runAsync(() => _bluePng(200, 100)))!;
      ImageEditResult? result;
      await openEditor(
        tester,
        (context) async => result = await showImageEditor(
          context,
          png,
          edits: const [
            CoverEdit(ui.Rect.fromLTRB(0.1, 0.1, 0.3, 0.3)),
            CoverEdit(ui.Rect.fromLTRB(0.6, 0.6, 0.8, 0.8)),
          ],
        ),
      );
      final box = canvas(tester);
      Offset at(double fx, double fy) => Offset(box.left + box.width * fx, box.top + box.height * fy);

      // Erste Abdeckung verschieben …
      await tester.dragFrom(at(0.2, 0.2), Offset(box.width * 0.2, box.height * 0.2));
      await tester.pumpAndSettle();
      // … und an der Ecke (jetzt bei 0.5/0.5) vergrößern.
      await tester.dragFrom(at(0.5, 0.5), Offset(box.width * 0.05, box.height * 0.1));
      await tester.pumpAndSettle();
      // Zweite antippen und entfernen.
      await tester.tapAt(at(0.7, 0.7));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-delete-selected')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Übernehmen'));
      await _settleImageWork(tester);
      final cover = result!.edits.whereType<CoverEdit>().single;
      expect(cover.rect.left, closeTo(0.3, 0.03));
      expect(cover.rect.top, closeTo(0.3, 0.03));
      expect(cover.rect.right, closeTo(0.55, 0.03));
      expect(cover.rect.bottom, closeTo(0.6, 0.03));
      expect(result!.imageChanged, isTrue);
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
