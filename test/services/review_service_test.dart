import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/review_service.dart';

Flashcard _card({
  QuestionType type = QuestionType.singleChoice,
  List<QuestionType>? variantChain,
  int variantLevel = 0,
  int variantBox = 0,
  int masteryBox = 0,
  int reps = 0,
  DateTime? lastReview,
  List<VariantSnapshot>? pendingVariants,
}) {
  return Flashcard(
    id: 'c1',
    moduleId: 'm1',
    front: 'Frage',
    back: 'Antwort',
    createdAt: DateTime(2026, 1, 1),
    due: DateTime(2026, 1, 1),
    type: type,
    variantChain: variantChain,
    variantLevel: variantLevel,
    variantBox: variantBox,
    masteryBox: masteryBox,
    reps: reps,
    stability: reps == 0 ? 0 : 5,
    difficulty: reps == 0 ? 0 : 5,
    lastReview: lastReview,
    pendingVariants: pendingVariants,
  );
}

void main() {
  final now = DateTime(2026, 3, 10, 12);
  final service = ReviewService();

  group('ReviewService.evaluate – Grundverhalten', () {
    test('falsche Antwort zählt als falsch und als Lapse', () {
      final outcome = service.evaluate(_card(reps: 2, lastReview: DateTime(2026, 3, 1)), isCorrect: false, now: now);
      expect(outcome.wasWrong, isTrue);
      expect(outcome.card.lapses, 1);
      expect(outcome.levelChange, LevelChange.none);
      expect(outcome.levelChangeMessage, isNull);
    });

    test('richtige Antwort zählt nicht als falsch und erhöht reps', () {
      final outcome = service.evaluate(_card(), isCorrect: true, now: now);
      expect(outcome.wasWrong, isFalse);
      expect(outcome.card.reps, 1);
    });

    test('Selbstbewertung "Nochmal" zählt als falsch, "Schwer" nicht', () {
      final base = _card(type: QuestionType.flashcard);
      expect(service.evaluate(base, selfGrade: Grade.again, now: now).wasWrong, isTrue);
      expect(service.evaluate(base, selfGrade: Grade.hard, now: now).wasWrong, isFalse);
    });

    test('Selbstbewertung fasst die Eskalationskette nicht an', () {
      final card = _card(
        type: QuestionType.flashcard,
        variantChain: const [QuestionType.flashcard, QuestionType.freeText],
        variantBox: 2,
      );
      final outcome = service.evaluate(card, selfGrade: Grade.good, now: now);
      expect(outcome.card.variantBox, 2);
      expect(outcome.levelChange, LevelChange.none);
    });
  });

  group('ReviewService.evaluate – Stufenwechsel', () {
    test('Beförderung ohne vorbereiteten Inhalt meldet promotionPending', () {
      final card = _card(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        masteryBox: Flashcard.masteryBoxCap,
        reps: 3,
        lastReview: DateTime(2026, 3, 5),
      );
      final outcome = service.evaluate(card, isCorrect: true, now: now);
      expect(outcome.levelChange, LevelChange.promotionPending);
      expect(outcome.needsGeneration, isTrue);
      expect(outcome.targetType, QuestionType.fillBlank);
      expect(outcome.levelChangeMessage, contains('nächstes Mal'));
    });

    test('Beförderung mit vorbereitetem Inhalt passiert sofort', () {
      final card = _card(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        masteryBox: Flashcard.masteryBoxCap,
        reps: 3,
        lastReview: DateTime(2026, 3, 5),
        pendingVariants: const [
          VariantSnapshot(type: QuestionType.fillBlank, front: 'Lücke ___', back: '', blanks: ['x']),
        ],
      );
      final outcome = service.evaluate(card, isCorrect: true, now: now);
      expect(outcome.levelChange, LevelChange.promoted);
      expect(outcome.needsGeneration, isFalse);
      expect(outcome.card.type, QuestionType.fillBlank);
      expect(outcome.levelChangeMessage, contains('jetzt'));
      // Neue Stufe startet neu: morgen fällig, Ampel gelb statt grün.
      expect(outcome.card.due, DateTime(2026, 3, 11));
      expect(outcome.card.masteryBox, 1);
    });

    test('grün werden auf einer Stufe braucht verschiedene Tage, nicht 3 richtige in Folge', () {
      var card = _card(variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank]);
      for (var i = 0; i < 6; i++) {
        final outcome = service.evaluate(card, isCorrect: true, now: now.add(Duration(minutes: i)));
        expect(outcome.levelChange, LevelChange.none);
        card = outcome.card;
      }
      expect(card.masteryBox, 1);
    });

    test('Rückstufung nach wiederholten Fehlern wird gemeldet', () {
      final promoted = _card(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
        reps: 3,
        lastReview: DateTime(2026, 3, 5),
      ).copyWithPromotedVariant(newType: QuestionType.fillBlank, front: 'Lücke ___', blanks: const ['x']);
      final first = service.evaluate(promoted, isCorrect: false, now: now);
      expect(first.levelChange, LevelChange.none);
      final second = service.evaluate(first.card, isCorrect: false, now: now);
      expect(second.levelChange, LevelChange.demoted);
      expect(second.targetType, QuestionType.singleChoice);
      expect(second.levelChangeMessage, contains('Zurück'));
    });
  });
}
