import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/answer_checker.dart';

Flashcard _question({
  QuestionType type = QuestionType.singleChoice,
  List<QuizOption>? options,
  String? correctText,
  List<String>? blanks,
  List<DragPair>? dragPairs,
}) {
  return Flashcard(
    id: 'q1',
    moduleId: 'm1',
    front: 'Frage?',
    back: '',
    createdAt: DateTime(2026, 1, 1),
    due: DateTime(2026, 1, 1),
    type: type,
    options: options,
    correctText: correctText,
    blanks: blanks,
    dragPairs: dragPairs,
  );
}

void main() {
  group('AnswerChecker.checkSingleChoice', () {
    test('richtig, wenn der richtige Index gewählt wurde', () {
      final q = _question(options: const [
        QuizOption(text: 'A', isCorrect: false),
        QuizOption(text: 'B', isCorrect: true),
      ]);
      final result = AnswerChecker.checkSingleChoice(q, 1);
      expect(result.isCorrect, isTrue);
      expect(result.correctAnswerLabel, 'B');
    });

    test('falsch bei falschem Index oder keiner Auswahl', () {
      final q = _question(options: const [
        QuizOption(text: 'A', isCorrect: false),
        QuizOption(text: 'B', isCorrect: true),
      ]);
      expect(AnswerChecker.checkSingleChoice(q, 0).isCorrect, isFalse);
      expect(AnswerChecker.checkSingleChoice(q, null).isCorrect, isFalse);
    });

    test('mehrere als richtig markierte Optionen: jede davon zählt (UI zeigt alle grün)', () {
      final q = _question(options: const [
        QuizOption(text: 'A', isCorrect: true),
        QuizOption(text: 'B', isCorrect: false),
        QuizOption(text: 'C', isCorrect: true),
      ]);
      expect(AnswerChecker.checkSingleChoice(q, 0).isCorrect, isTrue);
      expect(AnswerChecker.checkSingleChoice(q, 2).isCorrect, isTrue);
      expect(AnswerChecker.checkSingleChoice(q, 1).isCorrect, isFalse);
      expect(AnswerChecker.checkSingleChoice(q, 1).correctAnswerLabel, 'A, C');
    });
  });

  group('AnswerChecker.checkMultipleChoice', () {
    test('richtig nur bei exakter Übereinstimmung der Menge', () {
      final q = _question(type: QuestionType.multipleChoice, options: const [
        QuizOption(text: 'A', isCorrect: true),
        QuizOption(text: 'B', isCorrect: false),
        QuizOption(text: 'C', isCorrect: true),
      ]);
      expect(AnswerChecker.checkMultipleChoice(q, {0, 2}).isCorrect, isTrue);
      expect(AnswerChecker.checkMultipleChoice(q, {0}).isCorrect, isFalse);
      expect(AnswerChecker.checkMultipleChoice(q, {0, 1, 2}).isCorrect, isFalse);
    });
  });

  group('AnswerChecker.checkFreeText / answerMatches', () {
    test('exakte Übereinstimmung ist richtig', () {
      final q = _question(type: QuestionType.freeText, correctText: 'Photosynthese');
      expect(AnswerChecker.checkFreeText(q, 'Photosynthese').isCorrect, isTrue);
    });

    test('Groß-/Kleinschreibung und Leerzeichen spielen keine Rolle', () {
      final q = _question(type: QuestionType.freeText, correctText: 'Photosynthese');
      expect(AnswerChecker.checkFreeText(q, '  PHOTOSYNTHESE  ').isCorrect, isTrue);
    });

    test('kleine Tippfehler werden toleriert', () {
      final q = _question(type: QuestionType.freeText, correctText: 'Photosynthese');
      expect(AnswerChecker.checkFreeText(q, 'Photosyntese').isCorrect, isTrue); // 1 Zeichen fehlt
    });

    test('zu große Abweichungen zählen als falsch', () {
      final q = _question(type: QuestionType.freeText, correctText: 'Photosynthese');
      expect(AnswerChecker.checkFreeText(q, 'Zellatmung').isCorrect, isFalse);
    });

    test('mehrere durch ; getrennte Lösungen werden akzeptiert', () {
      final q = _question(type: QuestionType.freeText, correctText: 'U = R * I; Spannung gleich Widerstand mal Strom');
      expect(AnswerChecker.checkFreeText(q, 'Spannung gleich Widerstand mal Strom').isCorrect, isTrue);
      expect(AnswerChecker.checkFreeText(q, 'U = R * I').isCorrect, isTrue);
    });

    test('leere Antwort ist immer falsch', () {
      final q = _question(type: QuestionType.freeText, correctText: 'Photosynthese');
      expect(AnswerChecker.checkFreeText(q, '').isCorrect, isFalse);
      expect(AnswerChecker.checkFreeText(q, '   ').isCorrect, isFalse);
    });
  });

  group('AnswerChecker.checkFillBlank', () {
    test('richtig nur wenn alle Lücken stimmen', () {
      final q = _question(type: QuestionType.fillBlank, blanks: const ['Frankreich', 'Paris']);
      expect(AnswerChecker.checkFillBlank(q, ['Frankreich', 'Paris']).isCorrect, isTrue);
      expect(AnswerChecker.checkFillBlank(q, ['Frankreich', 'Lyon']).isCorrect, isFalse);
    });

    test('fehlende Antworten zählen als falsch, nicht als Fehler', () {
      final q = _question(type: QuestionType.fillBlank, blanks: const ['A', 'B']);
      expect(AnswerChecker.checkFillBlank(q, ['A']).isCorrect, isFalse);
    });
  });

  group('AnswerChecker.checkDragDrop', () {
    test('richtig nur wenn jedes Ziel den passenden Begriff hat', () {
      final q = _question(type: QuestionType.dragDrop, dragPairs: const [
        DragPair(source: 'Hund', target: 'Tier'),
        DragPair(source: 'Rose', target: 'Pflanze'),
      ]);
      expect(
        AnswerChecker.checkDragDrop(q, {'Tier': 'Hund', 'Pflanze': 'Rose'}).isCorrect,
        isTrue,
      );
      expect(
        AnswerChecker.checkDragDrop(q, {'Tier': 'Rose', 'Pflanze': 'Hund'}).isCorrect,
        isFalse,
      );
    });
  });

  group('AnswerChecker.checkDragCategory', () {
    test('richtig nur wenn jeder Begriff seiner Kategorie zugeordnet ist', () {
      final q = _question(type: QuestionType.dragCategory, dragPairs: const [
        DragPair(source: 'Hund', target: 'Tier'),
        DragPair(source: 'Katze', target: 'Tier'),
        DragPair(source: 'Rose', target: 'Pflanze'),
      ]);
      expect(
        AnswerChecker.checkDragCategory(q, {'Hund': 'Tier', 'Katze': 'Tier', 'Rose': 'Pflanze'}).isCorrect,
        isTrue,
      );
      expect(
        AnswerChecker.checkDragCategory(q, {'Hund': 'Pflanze', 'Katze': 'Tier', 'Rose': 'Pflanze'}).isCorrect,
        isFalse,
      );
    });
  });
}
