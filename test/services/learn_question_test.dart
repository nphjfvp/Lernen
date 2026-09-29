import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/answer_checker.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/mock_exam_service.dart';
import 'package:lernen/services/pdf_question_import_service.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/services/stage_gate_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';

Flashcard _learn({String id = 'l1', String? conceptId, String back = 'Schritt 1 … Schritt 2 …'}) => Flashcard(
      id: id,
      moduleId: 'm1',
      conceptId: conceptId,
      front: 'Zeichnen Sie das Gantt-Diagramm für die Aufträge A bis D.',
      back: back,
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      type: QuestionType.learn,
    );

void main() {
  group('KI-Antworten: Typ "learn"', () {
    test('Erklärung/Lösungsweg landet in "back", der Typ bleibt', () {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'learn',
        'front': 'Zeichnen Sie das Gantt-Diagramm.',
        'explanation': 'Schritt 1: Dauern eintragen …',
      })!;
      expect(fixed['type'], 'learn');
      expect(fixed['back'], 'Schritt 1: Dauern eintragen …');
    });

    test('Schreibweisen: lernaufgabe, task, aufgabe; Lösungsweg als Liste', () {
      for (final name in ['lernaufgabe', 'task', 'Aufgabe', 'exercise', 'Lernen']) {
        expect(QuestionParsing.parseType(name), QuestionType.learn, reason: name);
      }
      final fixed = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'learn',
        'front': 'Beweisen Sie …',
        'lösungsweg': ['Ansatz wählen', 'Umformen', 'Fertig'],
      })!;
      expect(fixed['back'], 'Ansatz wählen\nUmformen\nFertig');
    });

    test('ohne Erklärung nicht zu retten (sonst eine Lernaufgabe ohne Lernstoff)', () {
      expect(QuestionParsing.normalizeGeneratedFlashcard({'type': 'learn', 'front': 'Beweisen Sie …'}), isNull);
    });

    test('Import: die Aufgabe wird als Karte mit Erklärung angelegt', () {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'learn',
        'front': 'Aufgabe 1 (a–c) wörtlich',
        'back': 'So geht es …',
      })!;
      final cards = PdfQuestionImportService.toFlashcards(
        [ScannedQuestion(page: 4, data: fixed, solutionByAi: true)],
        moduleId: 'm1',
        sourceMaterialId: 'blatt',
        now: DateTime(2026, 9, 29),
      );
      expect(cards.single.type, QuestionType.learn);
      expect(cards.single.front, 'Aufgabe 1 (a–c) wörtlich');
      expect(cards.single.back, 'So geht es …');
      expect(cards.single.sourcePage, 4);
    });
  });

  group('Karte vom Typ learn', () {
    test('Bezeichnung, Zusammenfassung und Speichern', () {
      final card = _learn();
      expect(QuestionType.learn.label, 'Lernen');
      expect(card.answerSummary, card.back);
      expect(Flashcard.fromMap(card.toMap()).type, QuestionType.learn);
      expect(AnswerChecker.isAnswerable(card), isTrue);
    });

    test('steht für sich: keine Stufen-Gruppe, auch nicht mit gleichem Konzept', () {
      final learn = _learn(conceptId: 'k1');
      final easy = Flashcard(
        id: 'e',
        moduleId: 'm1',
        conceptId: 'k1',
        front: 'Leicht?',
        back: '',
        createdAt: DateTime(2026, 9, 1),
        due: DateTime(2026, 9, 1),
        type: QuestionType.singleChoice,
        options: const [QuizOption(text: 'A', isCorrect: true), QuizOption(text: 'B', isCorrect: false)],
      );
      expect(StageGate.groupOf(learn), isNull);
      expect(StageGate.statuses([easy, learn]), isEmpty);
      expect(StageGate.assignable([easy, learn]).map((c) => c.id), ['e']);
    });

    test('kommt in keiner Probeklausur dran', () {
      final pool = MockExamService.eligible([_learn(), _learn(id: 'l2')]);
      expect(pool, isEmpty);
    });
  });

  group('Anzeige', () {
    Future<Grade?> rate(WidgetTester tester, String label) async {
      Grade? grade;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: QuestionAnswerView(
            card: _learn(),
            isNew: false,
            onComplete: ({selfGrade, isCorrect}) => grade = selfGrade,
          ),
        ),
      ));
      expect(find.text('Aufgabe zum Verstehen'), findsOneWidget);
      expect(find.textContaining('Gantt-Diagramm'), findsOneWidget);
      expect(find.text('Erklärung / Lösungsweg'), findsNothing);
      expect(find.text('Prüfen'), findsNothing);

      await tester.tap(find.text('Zur Erklärung tippen'));
      await tester.pumpAndSettle();
      expect(find.text('Erklärung / Lösungsweg'), findsOneWidget);
      expect(find.textContaining('Schritt 1'), findsOneWidget);
      expect(find.text('Wie gut hast du die Aufgabe verstanden?'), findsOneWidget);

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      return grade;
    }

    testWidgets('Selbstbewertung: Unklar / Teilweise / Verstanden / Sicher', (tester) async {
      expect(await rate(tester, 'Verstanden'), Grade.good);
    });

    testWidgets('"Unklar" zählt wie "Nochmal"', (tester) async {
      expect(await rate(tester, 'Unklar'), Grade.again);
    });

    testWidgets('"Teilweise" ist "Schwer", "Sicher" ist "Leicht"', (tester) async {
      expect(await rate(tester, 'Teilweise'), Grade.hard);
      await tester.pumpWidget(const SizedBox());
      expect(await rate(tester, 'Sicher'), Grade.easy);
    });
  });
}
