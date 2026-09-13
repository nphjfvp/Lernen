import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/question_parsing.dart';

void main() {
  group('QuestionParsing.parseOptions', () {
    test('parst eine Liste von Optionen', () {
      final options = QuestionParsing.parseOptions([
        {'text': 'Paris', 'isCorrect': true},
        {'text': 'Lyon', 'isCorrect': false},
      ]);
      expect(options, isNotNull);
      expect(options!.length, 2);
      expect(options.first.text, 'Paris');
      expect(options.first.isCorrect, isTrue);
    });

    test('gibt null zurück, wenn kein Feld vorhanden ist', () {
      expect(QuestionParsing.parseOptions(null), isNull);
    });
  });

  group('QuestionParsing.parseBlanks', () {
    test('parst eine Liste von Strings', () {
      expect(QuestionParsing.parseBlanks(['Frankreich', 'Paris']), ['Frankreich', 'Paris']);
    });

    test('gibt null zurück, wenn kein Feld vorhanden ist', () {
      expect(QuestionParsing.parseBlanks(null), isNull);
    });
  });

  group('QuestionParsing.parseDragPairs', () {
    test('parst eine Liste von Zuordnungspaaren', () {
      final pairs = QuestionParsing.parseDragPairs([
        {'source': 'Hund', 'target': 'Tier'},
      ]);
      expect(pairs, isNotNull);
      expect(pairs!.single.source, 'Hund');
      expect(pairs.single.target, 'Tier');
    });

    test('gibt null zurück, wenn kein Feld vorhanden ist', () {
      expect(QuestionParsing.parseDragPairs(null), isNull);
    });
  });

  test('escalationChain ist single_choice -> fill_blank -> free_text', () {
    expect(QuestionParsing.escalationChain,
        [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText]);
  });
}
