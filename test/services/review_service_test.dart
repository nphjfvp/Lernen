import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
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

    test('Selbstbewertung befördert nur, wenn die Stufe grün ist', () {
      final card = _card(
        type: QuestionType.flashcard,
        variantChain: const [QuestionType.flashcard, QuestionType.freeText],
        variantBox: 2,
      );
      final outcome = service.evaluate(card, selfGrade: Grade.good, now: now);
      expect(outcome.levelChange, LevelChange.none);
      expect(outcome.card.variantLevel, 0);
    });

    test('Selbstbewertung "Nochmal" zählt für die Fehler-Leiter', () {
      final outcome = service.evaluate(_card(type: QuestionType.flashcard), selfGrade: Grade.again, now: now);
      expect(outcome.card.variantMissStreak, 1);
    });
  });

  group('Fehler-Leiter', () {
    test('jede falsche Antwort zählt (auch am selben Tag), eine richtige setzt zurück', () {
      var card = _card();
      for (var i = 1; i <= 3; i++) {
        card = service.evaluate(card, isCorrect: false, now: now.add(Duration(minutes: i))).card;
        expect(card.variantMissStreak, i);
      }
      card = service.evaluate(card, isCorrect: true, now: now.add(const Duration(minutes: 5))).card;
      expect(card.variantMissStreak, 0);
    });

    test('richtig mit Tipp ("Schwer") zählt nicht als Fehler', () {
      final card = _card(reps: 2, lastReview: DateTime(2026, 3, 1));
      final outcome = service.evaluate(card, isCorrect: true, selfGrade: Grade.hard, now: now);
      expect(outcome.wasWrong, isFalse);
      expect(outcome.card.variantMissStreak, 0);
    });

    test('Karte ohne Stufenkette: beim ${Flashcard.fallbackMissStreak}. Fehler wird der Rückfall angefordert', () {
      var outcome = service.evaluate(_card(), isCorrect: false, now: now);
      for (var i = 2; i < Flashcard.fallbackMissStreak; i++) {
        outcome = service.evaluate(outcome.card, isCorrect: false, now: now.add(Duration(minutes: i)));
        expect(outcome.fallbackRequested, isFalse);
      }
      outcome = service.evaluate(outcome.card, isCorrect: false, now: now.add(const Duration(minutes: 9)));
      expect(outcome.fallbackRequested, isTrue);
    });

    test('Stufenkette auf der ersten Stufe fordert keinen Gruppen-Rückfall an', () {
      var card = _card(variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank]);
      late ReviewOutcome outcome;
      for (var i = 0; i < Flashcard.fallbackMissStreak; i++) {
        outcome = service.evaluate(card, isCorrect: false, now: now.add(Duration(minutes: i)));
        card = outcome.card;
      }
      expect(outcome.fallbackRequested, isFalse);
      expect(outcome.levelChange, LevelChange.none);
    });
  });

  group('Gewichtung beim Verbuchen', () {
    Module module(double weight) => Module(
          id: 'm1',
          name: 'Technik',
          colorValue: 0,
          icon: '⚙️',
          examDate: null,
          createdAt: DateTime(2026, 1, 1),
          weight: weight,
        );

    test('effectiveWeight = Karten-Gewicht × Fach-Gewicht, ohne Fach nur die Karte', () {
      final card = _card().copyWithWeight(1.5);
      expect(effectiveWeight(card, null), 1.5);
      expect(effectiveWeight(card, module(2.0)), 3.0);
      expect(effectiveWeight(_card(), module(1.0)), 1.0);
    });

    test('evaluate gibt das Gewicht ans Intervall weiter: höher gewichtet = früher wieder fällig', () {
      final card = _card(reps: 4, lastReview: DateTime(2026, 2, 20));
      final normal = service.evaluate(card, isCorrect: true, now: now);
      final heavy = service.evaluate(card, isCorrect: true, now: now, weight: 2.0);
      expect(heavy.card.scheduledDays, lessThanOrEqualTo(normal.card.scheduledDays));
      expect(heavy.card.scheduledDays, FsrsService.weightedIntervalDays(normal.card.scheduledDays, 2.0));
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

    test('Rückstufung erst beim ${Flashcard.fallbackMissStreak}. Fehler in Folge (auch in der Wiederholungsrunde)',
        () {
      final promoted = _card(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
        reps: 3,
        masteryBox: 2,
        lastReview: DateTime(2026, 3, 5),
      ).copyWithPromotedVariant(newType: QuestionType.fillBlank, front: 'Lücke ___', blanks: const ['x']);
      var outcome = service.evaluate(promoted, isCorrect: false, now: now);
      for (var i = 2; i < Flashcard.fallbackMissStreak; i++) {
        outcome = service.evaluate(outcome.card, isCorrect: false, now: now.add(Duration(minutes: i)));
        expect(outcome.levelChange, LevelChange.none);
        expect(outcome.card.type, QuestionType.fillBlank);
      }
      outcome = service.evaluate(outcome.card, isCorrect: false, now: now.add(const Duration(minutes: 9)));
      expect(outcome.levelChange, LevelChange.demoted);
      expect(outcome.targetType, QuestionType.singleChoice);
      expect(outcome.levelChangeMessage, contains('Zurück'));
      expect(outcome.fallbackRequested, isFalse);
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
            {'source': 'Rom', 'target': 'Italien'},
          ],
        },
        now: now,
      );
      expect(promoted.type, QuestionType.dragCategory);
    });
  });
}
