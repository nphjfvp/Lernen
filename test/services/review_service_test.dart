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

  group('ReviewService.evaluate – richtig mit Tipp', () {
    test('zählt als "Schwer": nicht falsch, Ampel steigt nicht, keine Beförderung', () {
      final card = _card(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        masteryBox: Flashcard.masteryBoxCap,
        reps: 3,
        lastReview: DateTime(2026, 3, 5),
      );
      final outcome = service.evaluate(card, isCorrect: true, selfGrade: Grade.hard, now: now);
      expect(outcome.wasWrong, isFalse);
      expect(outcome.levelChange, LevelChange.none);
      expect(outcome.card.variantLevel, 0);
      expect(outcome.card.masteryBox, Flashcard.masteryBoxCap);

      final fresh = service.evaluate(_card(), isCorrect: true, selfGrade: Grade.hard, now: now);
      expect(fresh.card.masteryBox, 0);
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
      // Fehlversuch an einem weiteren Tag: jetzt wird zurückgestuft.
      final second = service.evaluate(first.card, isCorrect: false, now: now.add(const Duration(days: 1)));
      expect(second.levelChange, LevelChange.demoted);
      expect(second.targetType, QuestionType.singleChoice);
      expect(second.levelChangeMessage, contains('Zurück'));
    });

    test('ein erneuter Fehlversuch am selben Tag stuft nicht zurück (Wiederholungsrunde)', () {
      final promoted = _card(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
        reps: 3,
        masteryBox: 2,
        lastReview: DateTime(2026, 3, 5),
      ).copyWithPromotedVariant(newType: QuestionType.fillBlank, front: 'Lücke ___', blanks: const ['x']);
      var outcome = service.evaluate(promoted, isCorrect: false, now: now);
      for (var i = 1; i <= 3; i++) {
        outcome = service.evaluate(outcome.card, isCorrect: false, now: now.add(Duration(minutes: i)));
        expect(outcome.levelChange, LevelChange.none);
        expect(outcome.wasWrong, isTrue);
      }
      expect(outcome.card.type, QuestionType.fillBlank);
      expect(outcome.card.variantMissStreak, 1);
    });
  });

  group('ReviewService.evaluate – allowLevelChange', () {
    test('ohne Stufenwechsel-Erlaubnis zählt die Antwort nur für FSRS/Ampel', () {
      final green = _card(
        variantChain: const [QuestionType.singleChoice, QuestionType.freeText],
        masteryBox: Flashcard.masteryBoxCap,
        reps: 5,
        lastReview: DateTime(2026, 3, 1),
      );
      final outcome = service.evaluate(green, isCorrect: true, now: now, allowLevelChange: false);
      expect(outcome.levelChange, LevelChange.none);
      expect(outcome.card.variantLevel, 0);
      expect(outcome.card.reps, 6);
    });
  });

  group('ReviewService.applyPromotion', () {
    final base = Flashcard(
      id: 'c1',
      moduleId: 'm1',
      front: 'Hauptstadt von Frankreich?',
      back: '',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      type: QuestionType.singleChoice,
      options: const [QuizOption(text: 'Paris', isCorrect: true), QuizOption(text: 'Rom', isCorrect: false)],
      variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
      masteryBox: Flashcard.masteryBoxCap,
      imageBase64: 'BILD',
    );

    test('übernimmt eine vollständige Stufe samt Bild der Karte', () {
      final promoted = ReviewService.applyPromotion(
        base,
        QuestionType.fillBlank,
        {'front': 'Die Hauptstadt von Frankreich ist ___.', 'blanks': ['Paris']},
        now: now,
      );
      expect(promoted.type, QuestionType.fillBlank);
      expect(promoted.variantLevel, 1);
      expect(promoted.blanks, ['Paris']);
      expect(promoted.imageBase64, 'BILD');
      expect(promoted.variantHistory!.single.type, QuestionType.singleChoice);
    });

    test('unvollständige KI-Stufe wirft, statt eine unlösbare Stufe zu speichern', () {
      expect(
        () => ReviewService.applyPromotion(base, QuestionType.fillBlank, {'front': 'Lücke ___'}, now: now),
        throwsFormatException,
      );
      // Nur noch als Karteikarte rettbar: keine echte nächste Stufe.
      expect(
        () => ReviewService.applyPromotion(
          base,
          QuestionType.freeText,
          {'front': 'Hauptstadt?', 'back': 'Paris'},
          now: now,
        ),
        throwsFormatException,
      );
    });

    test('Zuordnen mit doppeltem Ziel wird zur Kategorien-Stufe', () {
      final promoted = ReviewService.applyPromotion(
        base,
        QuestionType.dragDrop,
        {
          'front': 'Ordne zu',
          'dragPairs': [
            {'source': 'Paris', 'target': 'Frankreich'},
            {'source': 'Lyon', 'target': 'Frankreich'},
          ],
        },
        now: now,
      );
      expect(promoted.type, QuestionType.dragCategory);
    });
  });
}
