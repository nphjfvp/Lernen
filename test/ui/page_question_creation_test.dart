import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/services/image_crop.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/widgets/page_question_creation_sheet.dart';
import 'package:lernen/ui/widgets/page_region_picker.dart';

/// PNG mit linker Hälfte rot, rechter Hälfte blau.
Future<Uint8List> _twoColorPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, width / 2, height.toDouble()), ui.Paint()..color = const ui.Color(0xFFFF0000));
  canvas.drawRect(
      ui.Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()), ui.Paint()..color = const ui.Color(0xFF0000FF));
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<(int, int, int)> _sizeAndFirstPixel(Uint8List png) async {
  final image = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (image.width, image.height, rgba.getUint32(0));
}

void main() {
  group('buildPageQuestionCards', () {
    final now = DateTime(2026, 9, 26);

    test('schneidet auf bestellte Fragen/Stufen zu und verwirft unbrauchbare Karten', () {
      final groups = [
        [
          {'type': 'flashcard', 'front': 'F1', 'back': 'A1', 'needsImage': true},
          {'type': 'free_text', 'front': 'F1 schwer', 'correctText': 'A1'},
          {'type': 'flashcard', 'front': 'zu viel', 'back': 'x'},
        ],
        [
          // Ohne jede Antwort nicht zu retten -> Frage fällt weg.
          {'type': 'flashcard', 'front': 'F2'},
        ],
        [
          {'type': 'flashcard', 'front': 'F3', 'back': 'A3'},
        ],
        [
          {'type': 'flashcard', 'front': 'nicht bestellt', 'back': 'x'},
        ],
      ];

      final result = buildPageQuestionCards(
        groups,
        moduleId: 'm1',
        unitId: 'u1',
        questionCount: 3,
        tierCount: 2,
        attachImageBase64: 'BILD',
        now: now,
      );

      expect(result.map((q) => q.map((c) => c.front).toList()).toList(), [
        ['F1', 'F1 schwer'],
        ['F3'],
      ]);
      final first = result.first.first;
      expect(first.imageBase64, 'BILD');
      expect(result.first[1].imageBase64, isNull);
      expect(result.first[1].type, QuestionType.freeText);
      expect(first.moduleId, 'm1');
      expect(first.unitId, 'u1');
      expect(first.priorityIntroduction, isTrue);
    });
  });

  group('mergeTiersIntoChain', () {
    Flashcard card(String id, QuestionType type, String front) => Flashcard(
          id: id,
          moduleId: 'm1',
          front: front,
          back: 'Antwort',
          createdAt: DateTime(2026, 9, 26),
          due: DateTime(2026, 9, 26),
          type: type,
          priorityIntroduction: true,
        );

    test('mehrere Stufen werden eine Karte mit vorbereiteten Folgestufen', () {
      final merged = mergeTiersIntoChain([
        card('a', QuestionType.singleChoice, 'Leicht'),
        card('b', QuestionType.fillBlank, 'Mittel'),
        card('c', QuestionType.freeText, 'Schwer'),
      ]);
      expect(merged.id, 'a');
      expect(merged.front, 'Leicht');
      expect(merged.variantChain, [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText]);
      expect(merged.pendingVariants!.map((v) => v.front), ['Mittel', 'Schwer']);
      expect(merged.priorityIntroduction, isTrue);
    });

    test('eine Stufe bleibt unverändert', () {
      final single = card('a', QuestionType.flashcard, 'Nur eine');
      expect(identical(mergeTiersIntoChain([single]), single), isTrue);
    });
  });

  group('cropImageRelative', () {
    test('schneidet den relativen Ausschnitt pixelgenau aus', () async {
      final png = await _twoColorPng(100, 50);
      final crop = await cropImageRelative(png, const ui.Rect.fromLTRB(0.5, 0, 1, 1));
      final (width, height, firstPixel) = await _sizeAndFirstPixel(crop!);
      expect(width, 50);
      expect(height, 50);
      expect(firstPixel, 0x0000FFFF); // RGBA: blau
    });

    test('leerer Ausschnitt und kaputte Bilder liefern null', () async {
      final png = await _twoColorPng(10, 10);
      expect(await cropImageRelative(png, const ui.Rect.fromLTRB(0.5, 0.5, 0.5, 0.9)), isNull);
      expect(await cropImageRelative(Uint8List.fromList([1, 2, 3]), const ui.Rect.fromLTRB(0, 0, 1, 1)), isNull);
    });
  });

  group('downscaleImage', () {
    test('verkleinert auf die längere Seite, kleine Bilder bleiben', () async {
      final big = await _twoColorPng(2000, 1000);
      final (w, h, _) = await _sizeAndFirstPixel((await downscaleImage(big, maxSide: 1280))!);
      expect(w, 1280);
      expect(h, 640);
      final small = await _twoColorPng(300, 200);
      expect(identical(await downscaleImage(small, maxSide: 1280), small), isTrue);
    });
  });

  testWidgets('Bereich markieren: Rahmen ziehen und übernehmen', (tester) async {
    final png = (await tester.runAsync(() => _twoColorPng(200, 100)))!;
    Rect? picked;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showPageRegionPicker(context, png),
            child: const Text('öffnen'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Bildgröße wird echt asynchron gelesen.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    final canvas = find.byKey(const ValueKey('region-canvas'));
    expect(canvas, findsOneWidget);
    final box = tester.getRect(canvas);
    // Seitenverhältnis des Bildes (2:1) bleibt erhalten.
    expect(box.width / box.height, closeTo(2, 0.01));

    await tester.dragFrom(
      box.topLeft + Offset(box.width * 0.25, box.height * 0.2),
      Offset(box.width * 0.5, box.height * 0.6),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Übernehmen'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.left, closeTo(0.25, 0.005));
    expect(picked!.top, closeTo(0.2, 0.005));
    expect(picked!.right, closeTo(0.75, 0.02));
    expect(picked!.bottom, closeTo(0.8, 0.02));
  });

  testWidgets('Einstellungen: Stufen stehen auf "KI entscheidet", bis zu 5 Fragen wählbar', (tester) async {
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(
        body: PageQuestionCreationSheet(
          material: MaterialItem(
            id: 'mat1',
            moduleId: 'm1',
            fileName: 'Folien.pdf',
            kind: MaterialKind.slide,
            extractedText: 'Text',
            createdAt: DateTime(2026, 9, 26),
          ),
          pageNumber: 3,
          pageText: 'Seitentext',
          pageImageBytes: Uint8List.fromList([1]),
          highlightsOnPage: const [],
          initialQuestionText: 'Markierter Satz',
        ),
      ),
    ));

    expect(find.text('Frage aus Seite 3'), findsOneWidget);
    expect(find.text('Markierter Satz'), findsOneWidget);
    expect(find.text('KI entscheidet'), findsNWidgets(3));
    expect(find.text('Bereich markieren'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Frage erstellen'), findsOneWidget);

    await tester.tap(find.text('5'));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, '5 Fragen erstellen'), findsOneWidget);

    // "Interaktiv" ist als fester Typ wählbar.
    await tester.tap(find.text('KI entscheidet').first);
    await tester.pumpAndSettle();
    expect(find.text('Interaktiv').last, findsOneWidget);
  });
}
