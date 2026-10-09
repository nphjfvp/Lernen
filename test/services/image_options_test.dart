import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/answer_checker.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/pdf_question_import_service.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/flashcards/card_edit_screen.dart';

/// Seitenbild 400×600: links rot, rechts blau.
Future<Uint8List> _pagePng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawRect(const ui.Rect.fromLTWH(0, 0, 200, 600), ui.Paint()..color = const ui.Color(0xFFFF0000))
    ..drawRect(const ui.Rect.fromLTWH(200, 0, 200, 600), ui.Paint()..color = const ui.Color(0xFF0000FF));
  final image = await recorder.endRecording().toImage(400, 600);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// RGBA-Farbe der Mitte eines PNG.
Future<int> _center(String base64Png) async {
  final image = (await (await ui.instantiateImageCodec(base64Decode(base64Png))).getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return data.getUint32(((image.height ~/ 2) * image.width + image.width ~/ 2) * 4);
}

const _tinyPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

Flashcard _imageChoice() => Flashcard(
  id: 'c1',
  moduleId: 'm1',
  front: 'Welches Gefügebild zeigt ein kaltgewalztes Blech?',
  back: '',
  createdAt: DateTime(2026, 1, 1),
  due: DateTime(2026, 1, 1),
  type: QuestionType.singleChoice,
  options: const [
    QuizOption(text: '', isCorrect: false, imageBase64: _tinyPng),
    QuizOption(text: 'Bild b – gestreckte Körner', isCorrect: true, imageBase64: _tinyPng),
    QuizOption(text: 'keins davon', isCorrect: false),
  ],
);

void main() {
  test('QuizOption: Bild wird gespeichert und gelesen, Beschriftung fällt auf "Bild a" zurück', () {
    const o = QuizOption(text: '', isCorrect: true, imageBase64: 'abc');
    expect(o.toMap(), {'text': '', 'isCorrect': true, 'image': 'abc'});
    expect(QuizOption.fromMap({'text': 'x', 'isCorrect': 1, 'imageBase64': 'abc'}).imageBase64, 'abc');
    expect(QuizOption.fromMap({'text': 'x', 'isCorrect': false}).toMap().containsKey('image'), isFalse);
    expect(o.labelAt(0), 'Bild a');
    expect(o.copyWith(clearImage: true).hasImage, isFalse);

    final card = _imageChoice();
    expect(AnswerChecker.checkSingleChoice(card, 1).isCorrect, isTrue);
    expect(AnswerChecker.checkSingleChoice(card, 0).correctAnswerLabel, 'Bild b – gestreckte Körner');
    final back = Flashcard.fromMap(card.toMap());
    expect(back.options![0].imageBase64, _tinyPng);
    expect(
      QuestionParsing.parseOptions([
        {'image': 'abc', 'isCorrect': true},
      ])!.single.hasImage,
      isTrue,
    );
  });

  test('KI-Eintrag: Optionen mit Bild-Bereich behalten "imageBox", auch wenn umgebaut', () {
    final entry = QuestionParsing.normalizeGeneratedFlashcard({
      'type': 'single_choice',
      'front': 'Welches Bild zeigt Perlit?',
      'choices': [
        {
          'label': 'Bild a',
          'correct': true,
          'imageBox': [0, 0, 0.5, 0.5],
        },
        {
          'label': 'Bild b',
          'correct': false,
          'imageBox': [0.5, 0, 1, 0.5],
        },
      ],
    })!;
    final options = entry['options'] as List;
    expect(options, hasLength(2));
    expect((options[0] as Map)['imageBox'], [0, 0, 0.5, 0.5]);
  });

  test('Import: Bild je Option aus dem Seitenbild ausgeschnitten', () async {
    final page = await _pagePng();
    final data = <String, dynamic>{
      'type': 'single_choice',
      'front': 'Welche Farbe ist blau?',
      'options': [
        {
          'text': 'Bild a',
          'isCorrect': false,
          'imageBox': [0.0, 0.0, 0.4, 0.4],
        },
        {
          'text': 'Bild b',
          'isCorrect': true,
          'imageBox': [0.6, 0.0, 1.0, 0.4],
        },
        {'text': 'keins', 'isCorrect': false},
      ],
    };
    await PdfQuestionImportService.attachOptionImages(data, page);
    final options = QuestionParsing.parseOptions(data['options'])!;
    expect(options[0].hasImage && options[1].hasImage, isTrue);
    expect(options[2].hasImage, isFalse);
    expect((data['options'] as List).any((o) => (o as Map).containsKey('imageBox')), isFalse);
    expect(await _center(options[0].imageBase64!), 0xFF0000FF, reason: 'rot (RGBA)');
    expect(await _center(options[1].imageBase64!), 0x0000FFFF, reason: 'blau (RGBA)');
  });

  testWidgets('Quiz: Bilder als Antworten, Auswahl und Auflösung mit Beschriftung', (tester) async {
    tester.view.physicalSize = const Size(700, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final results = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: QuestionAnswerView(
                  card: _imageChoice(),
                  isNew: false,
                  onComplete: ({Grade? selfGrade, bool? isCorrect}) => results.add(isCorrect),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('question-option-image-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('question-option-image-1')), findsOneWidget);
    expect(find.text('Bild a'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('question-option-zoom-0')));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bild b – gestreckte Körner'));
    await tester.pump();
    await tester.tap(find.text('Prüfen').first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsWidgets);
  });

  testWidgets('Editor: Bild als Antwortoption hinzufügen und entfernen', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    CardEditScreen.pickImageHook = () async => base64Decode(_tinyPng);
    addTearDown(() => CardEditScreen.pickImageHook = null);
    final card = _imageChoice();
    Flashcard? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await showCardEditor(context, card),
            child: const Text('öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('card-edit-option-thumb-0')), findsOneWidget);
    // Bild der zweiten Option entfernen, der dritten eins geben.
    await tester.ensureVisible(find.byKey(const ValueKey('card-edit-option-image-1')));
    await tester.tap(find.byKey(const ValueKey('card-edit-option-image-1')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('card-edit-option-image-2')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('card-edit-option-image-2')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('card-edit-option-thumb-2')), findsOneWidget);
    await tester.tap(find.text('Speichern').first);
    await tester.pumpAndSettle();
    final options = saved!.options!;
    expect(options, hasLength(3), reason: 'Bild-Option ohne Text bleibt erhalten');
    expect([for (final o in options) o.hasImage], [true, false, true]);
  });
}
