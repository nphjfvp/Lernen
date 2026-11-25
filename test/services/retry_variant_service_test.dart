import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/retry_variant_service.dart';

Flashcard _card({QuestionType type = QuestionType.singleChoice, String? image}) => Flashcard(
      id: 'c1',
      moduleId: 'm1',
      front: 'Ein Körper hat 2 kg. Gewichtskraft (g = 10)?',
      back: '',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      type: type,
      options: const [QuizOption(text: '20 N', isCorrect: true), QuizOption(text: '2 N', isCorrect: false)],
      correctText: type == QuestionType.freeText ? '20 N' : null,
      imageBase64: image,
      reps: 3,
      masteryBox: 2,
      stability: 4,
    );

void main() {
  test('neue Fassung: gleiche ID und Lernstand, neuer Inhalt', () {
    final original = _card();
    final variant = RetryVariantService.apply(original, {
      'front': 'Ein Koffer wiegt 5 kg. Welche Gewichtskraft wirkt (g = 10)?',
      'options': [
        {'text': '50 N', 'isCorrect': true},
        {'text': '5 N', 'isCorrect': false, 'why': 'Masse mit Kraft verwechselt'},
        {'text': '0,5 N', 'isCorrect': false},
      ],
    })!;
    expect(variant.id, original.id);
    expect(variant.reps, 3);
    expect(variant.masteryBox, 2);
    expect(variant.type, QuestionType.singleChoice);
    expect(variant.front, contains('Koffer'));
    expect(variant.options!.first.text, '50 N');
  });

  test('wortgleich, anderer Typ oder unbeantwortbar → keine Fassung', () {
    final original = _card();
    expect(RetryVariantService.apply(original, {'front': original.front, 'options': [
      {'text': 'a', 'isCorrect': true}, {'text': 'b', 'isCorrect': false},
    ]}), isNull);
    expect(RetryVariantService.apply(original, {'front': 'Neu?', 'options': [
      {'text': 'a', 'isCorrect': false}, {'text': 'b', 'isCorrect': false},
    ]}), isNull);
  });

  test('Bildfragen und Rechenwege werden nicht neu eingekleidet', () {
    expect(RetryVariantService.supports(_card()), isTrue);
    expect(RetryVariantService.supports(_card(image: 'abc')), isFalse);
    expect(RetryVariantService.supports(_card(type: QuestionType.steps)), isFalse);
  });
}
