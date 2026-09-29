import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/answer_checker.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';

Flashcard _drag(List<DragPair> pairs, {QuestionType type = QuestionType.dragDrop}) => Flashcard(
      id: 'd1',
      moduleId: 'm1',
      front: 'Ordnen Sie die Aufgabe der entsprechenden Abteilung zu.',
      back: '',
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      type: type,
      dragPairs: pairs,
    );

void main() {
  group('KI-Antworten: geschenkte Zuordnungen', () {
    test('ein einziges Paar wird zur Freitextfrage mit dem Begriff in der Frage', () {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'drag_drop',
        'front': 'Ordnen Sie die Aufgabe der Produktions-Programm-Planung der entsprechenden Abteilung zu.',
        'dragPairs': [
          {'source': 'Festlegung der zu produzierenden Mengen und Termine', 'target': 'Produktionsplanung'},
        ],
        'level': 'mittel',
      })!;
      expect(fixed['type'], 'free_text');
      expect(fixed['front'], contains('„Festlegung der zu produzierenden Mengen und Termine“'));
      expect(fixed['correctText'], 'Produktionsplanung');
      expect(fixed['level'], 'mittel');
      expect(fixed.containsKey('dragPairs'), isFalse);
    });

    test('alles in dieselbe Kategorie wird ebenfalls Freitext', () {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'drag_category',
        'front': 'Sortiere ein',
        'dragPairs': [
          {'source': 'Stahl', 'target': 'Metall'},
          {'source': 'Kupfer', 'target': 'Metall'},
        ],
      })!;
      expect(fixed['type'], 'free_text');
      expect(fixed['front'], contains('„Stahl“, „Kupfer“'));
      expect(fixed['correctText'], 'Metall');
    });

    test('echte Zuordnung mit mehreren Zielen bleibt', () {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'drag_drop',
        'front': 'Ordne zu',
        'dragPairs': [
          {'source': 'A', 'target': '1'},
          {'source': 'B', 'target': '2'},
          {'source': 'C', 'target': '3'},
        ],
      })!;
      expect(fixed['type'], 'drag_drop');
    });
  });

  group('Gespeicherte geschenkte Zuordnungen', () {
    test('werden erkannt und nicht als Zuordnen abgefragt', () {
      final single = _drag(const [DragPair(source: 'Festlegung', target: 'Produktionsplanung')]);
      expect(AnswerChecker.isTrivialDrag(single), isTrue);
      expect(AnswerChecker.isAnswerable(single), isFalse);

      final oneCategory = _drag(const [
        DragPair(source: 'Stahl', target: 'Metall'),
        DragPair(source: 'Kupfer', target: 'metall'),
      ], type: QuestionType.dragCategory);
      expect(AnswerChecker.isTrivialDrag(oneCategory), isTrue);

      final real = _drag(const [
        DragPair(source: 'A', target: '1'),
        DragPair(source: 'B', target: '2'),
      ]);
      expect(AnswerChecker.isTrivialDrag(real), isFalse);
      expect(AnswerChecker.isAnswerable(real), isTrue);
    });

    testWidgets('erscheinen als Karteikarte: Begriff in der Frage, Zuordnung auf der Rückseite', (tester) async {
      final card = _drag(const [DragPair(source: 'Festlegung der Mengen', target: 'Produktionsplanung')]);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: QuestionAnswerView(card: card, isNew: false, onComplete: ({selfGrade, isCorrect}) {}),
        ),
      ));
      expect(find.textContaining('Begriffe: Festlegung der Mengen'), findsOneWidget);
      expect(find.text('Prüfen'), findsNothing);
      await tester.tap(find.text('Zum Umdrehen tippen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Festlegung der Mengen -> Produktionsplanung'), findsOneWidget);
    });
  });
}
