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

    test('mehrere Varianten je Lücke (per ";") und Treffer je Lücke', () {
      final q = _question(type: QuestionType.fillBlank, blanks: const ['Mitochondrium; Mitochondrien', 'ATP']);
      expect(AnswerChecker.fillBlankHits(q, ['mitochondrien', 'ADP']), [true, false]);
      expect(AnswerChecker.fillBlankHits(q, ['Mitochondrium', 'ATP']), [true, true]);
      expect(AnswerChecker.fillBlankHits(q, ['Mitochondrium']), [true, false]);
      expect(AnswerChecker.checkFillBlank(q, ['Mitochondrien', 'atp']).isCorrect, isTrue);
      expect(AnswerChecker.checkFillBlank(q, ['x', 'ATP']).correctAnswerLabel, 'Mitochondrium / Mitochondrien | ATP');
    });

    test('fillBlankResult: richtig nur mit einem Treffer für jede Lücke', () {
      final q = _question(type: QuestionType.fillBlank, blanks: const ['A', 'B']);
      expect(AnswerChecker.fillBlankResult(q, [true, true]).isCorrect, isTrue);
      expect(AnswerChecker.fillBlankResult(q, [true, false]).isCorrect, isFalse);
      expect(AnswerChecker.fillBlankResult(q, [true]).isCorrect, isFalse);
      final empty = _question(type: QuestionType.fillBlank, blanks: const []);
      expect(AnswerChecker.fillBlankResult(empty, const []).isCorrect, isFalse);
    });

    test('solutionLabel und answerExactlyMatches', () {
      expect(AnswerChecker.solutionLabel(' a ;b; '), 'a / b');
      expect(AnswerChecker.answerExactlyMatches('  MITOCHONDRIEN ', 'Mitochondrium; Mitochondrien'), isTrue);
      expect(AnswerChecker.answerExactlyMatches('Mitochondrum', 'Mitochondrium'), isFalse); // nur Tippfehler-tolerant
      expect(AnswerChecker.answerExactlyMatches('', 'a'), isFalse);
    });
  });

  group('AnswerChecker.checkDragDrop', () {
    test('richtig nur wenn jedes Ziel den passenden Begriff hat (Indizes)', () {
      final q = _question(type: QuestionType.dragDrop, dragPairs: const [
        DragPair(source: 'Hund', target: 'Tier'),
        DragPair(source: 'Rose', target: 'Pflanze'),
      ]);
      expect(AnswerChecker.checkDragDrop(q, {0: 0, 1: 1}).isCorrect, isTrue);
      expect(AnswerChecker.checkDragDrop(q, {0: 1, 1: 0}).isCorrect, isFalse);
      expect(AnswerChecker.checkDragDrop(q, {0: 0}).isCorrect, isFalse);
    });

    test('gleich lautende Begriffe sind austauschbar', () {
      final q = _question(type: QuestionType.dragDrop, dragPairs: const [
        DragPair(source: 'Stahl', target: 'Brücke'),
        DragPair(source: 'Stahl', target: 'Schiene'),
        DragPair(source: 'Glas', target: 'Fenster'),
      ]);
      expect(AnswerChecker.checkDragDrop(q, {0: 1, 1: 0, 2: 2}).isCorrect, isTrue);
      expect(AnswerChecker.dragZoneCorrect(q, 2, 0), isFalse);
    });

    test('leere Paare zählen nicht mit', () {
      final q = _question(type: QuestionType.dragDrop, dragPairs: const [
        DragPair(source: 'Hund', target: 'Tier'),
        DragPair(source: ' ', target: 'Leer'),
      ]);
      expect(AnswerChecker.usableDragPairs(q), hasLength(1));
      expect(AnswerChecker.checkDragDrop(q, {0: 0}).isCorrect, isTrue);
    });
  });

  group('AnswerChecker.isCategoryDrag', () {
    test('Zuordnen mit mehrfach genanntem Ziel gilt als Kategorien-Frage', () {
      final duplicate = _question(type: QuestionType.dragDrop, dragPairs: const [
        DragPair(source: 'Turbinenschaufel', target: 'Metall'),
        DragPair(source: 'Fahrradrahmen', target: 'Metall'),
        DragPair(source: 'Zahnfüllung', target: 'Keramik'),
      ]);
      final distinct = _question(type: QuestionType.dragDrop, dragPairs: const [
        DragPair(source: 'Hund', target: 'Tier'),
        DragPair(source: 'Rose', target: 'Pflanze'),
      ]);
      expect(AnswerChecker.isCategoryDrag(duplicate), isTrue);
      expect(AnswerChecker.dragCategories(duplicate), ['Metall', 'Keramik']);
      expect(AnswerChecker.isCategoryDrag(distinct), isFalse);
      expect(AnswerChecker.isCategoryDrag(_question(type: QuestionType.dragCategory, dragPairs: const [])), isTrue);
    });
  });

  group('AnswerChecker.checkDragCategory', () {
    test('richtig nur wenn jeder Begriff seiner Kategorie zugeordnet ist', () {
      final q = _question(type: QuestionType.dragCategory, dragPairs: const [
        DragPair(source: 'Hund', target: 'Tier'),
        DragPair(source: 'Katze', target: 'Tier'),
        DragPair(source: 'Rose', target: 'Pflanze'),
      ]);
      expect(AnswerChecker.checkDragCategory(q, {0: 'Tier', 1: 'Tier', 2: 'Pflanze'}).isCorrect, isTrue);
      expect(AnswerChecker.checkDragCategory(q, {0: 'Pflanze', 1: 'Tier', 2: 'Pflanze'}).isCorrect, isFalse);
      expect(AnswerChecker.checkDragCategory(q, {0: 'Tier', 1: 'Tier'}).isCorrect, isFalse);
      expect(AnswerChecker.correctCategoryPlacements(q, {0: 'Pflanze', 1: 'Tier', 2: 'Pflanze'}), {1, 2});
    });

    test('gleich lautende Begriffe in verschiedenen Kategorien werden verrechnet', () {
      final q = _question(type: QuestionType.dragCategory, dragPairs: const [
        DragPair(source: 'Bank', target: 'Möbel'),
        DragPair(source: 'Bank', target: 'Geldinstitut'),
      ]);
      expect(AnswerChecker.checkDragCategory(q, {0: 'Geldinstitut', 1: 'Möbel'}).isCorrect, isTrue);
      final bothSame = AnswerChecker.correctCategoryPlacements(q, {0: 'Möbel', 1: 'Möbel'});
      expect(bothSame, hasLength(1));
      expect(AnswerChecker.checkDragCategory(q, {0: 'Möbel', 1: 'Möbel'}).isCorrect, isFalse);
    });
  });

  group('AnswerChecker – unbrauchbare Daten', () {
    test('leere Lücken-Lösungen zählen nicht als Lücke', () {
      final q = _question(type: QuestionType.fillBlank, blanks: const ['Paris', '  ']);
      expect(AnswerChecker.solvableBlanks(q), ['Paris']);
      expect(AnswerChecker.checkFillBlank(q, ['Paris']).isCorrect, isTrue);
    });

    test('isAnswerable erkennt kaputte Karten', () {
      expect(
        AnswerChecker.isAnswerable(_question(options: const [
          QuizOption(text: 'A', isCorrect: false),
          QuizOption(text: 'B', isCorrect: false),
        ])),
        isFalse,
      );
      expect(
        AnswerChecker.isAnswerable(_question(options: const [QuizOption(text: 'A', isCorrect: true)])),
        isFalse,
      );
      expect(
        AnswerChecker.isAnswerable(_question(options: const [
          QuizOption(text: 'A', isCorrect: true),
          QuizOption(text: 'B', isCorrect: false),
        ])),
        isTrue,
      );
      expect(AnswerChecker.isAnswerable(_question(type: QuestionType.freeText, correctText: ' ; ')), isFalse);
      expect(AnswerChecker.isAnswerable(_question(type: QuestionType.freeText, correctText: 'x')), isTrue);
      expect(AnswerChecker.isAnswerable(_question(type: QuestionType.fillBlank, blanks: const [''])), isFalse);
      expect(AnswerChecker.isAnswerable(_question(type: QuestionType.dragDrop, dragPairs: const [])), isFalse);
      expect(AnswerChecker.isAnswerable(_question(type: QuestionType.flashcard)), isTrue);
    });
  });
}
