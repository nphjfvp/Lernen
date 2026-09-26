import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/fsrs_service.dart';

Flashcard _newCard() {
  final now = DateTime(2026, 1, 1);
  return Flashcard(
    id: 'c1',
    moduleId: 'm1',
    front: 'Frage',
    back: 'Antwort',
    createdAt: now,
    due: now,
  );
}

void main() {
  final fsrs = FsrsService();

  group('FsrsService – erste Bewertung einer neuen Karte', () {
    test('höhere Bewertung ergibt höhere Anfangs-Stability', () {
      final card = _newCard();
      final again = fsrs.review(card, Grade.again, now: DateTime(2026, 1, 1));
      final hard = fsrs.review(card, Grade.hard, now: DateTime(2026, 1, 1));
      final good = fsrs.review(card, Grade.good, now: DateTime(2026, 1, 1));
      final easy = fsrs.review(card, Grade.easy, now: DateTime(2026, 1, 1));

      expect(again.stability, lessThan(hard.stability));
      expect(hard.stability, lessThan(good.stability));
      expect(good.stability, lessThan(easy.stability));
    });

    test('setzt reps auf 1 und speichert lastReview', () {
      final now = DateTime(2026, 1, 1);
      final reviewed = fsrs.review(_newCard(), Grade.good, now: now);
      expect(reviewed.reps, 1);
      expect(reviewed.lastReview, now);
    });

    test('Fälligkeitsdatum liegt mindestens einen Tag in der Zukunft', () {
      final now = DateTime(2026, 1, 1);
      final reviewed = fsrs.review(_newCard(), Grade.again, now: now);
      expect(reviewed.due.isAfter(now), isTrue);
      expect(reviewed.scheduledDays, greaterThanOrEqualTo(1));
    });
  });

  group('FsrsService – wiederholte Bewertungen', () {
    test('wiederholtes "Gut" lässt das Intervall wachsen', () {
      var card = _newCard();
      var now = DateTime(2026, 1, 1);
      final intervals = <int>[];

      for (var i = 0; i < 4; i++) {
        card = fsrs.review(card, Grade.good, now: now);
        intervals.add(card.scheduledDays);
        now = card.due;
      }

      for (var i = 1; i < intervals.length; i++) {
        expect(intervals[i], greaterThanOrEqualTo(intervals[i - 1]));
      }
    });

    test('"Nochmal" nach einer erfolgreichen Wiederholung zählt als Lapse', () {
      final now = DateTime(2026, 1, 1);
      var card = fsrs.review(_newCard(), Grade.good, now: now);
      expect(card.lapses, 0);

      card = fsrs.review(card, Grade.again, now: card.due);
      expect(card.lapses, 1);
      expect(card.state, 'relearning');
    });
  });

  test('currentRetrievability sinkt mit der Zeit', () {
    final now = DateTime(2026, 1, 1);
    final card = fsrs.review(_newCard(), Grade.good, now: now);

    final soon = fsrs.currentRetrievability(card, now: now.add(const Duration(days: 1)));
    final later = fsrs.currentRetrievability(card, now: now.add(const Duration(days: 30)));

    expect(soon, greaterThan(later));
    expect(soon, lessThanOrEqualTo(1.0));
    expect(later, greaterThanOrEqualTo(0.0));
  });

  group('FsrsService.review – masteryBox (Grundlage der Ampel)', () {
    test('steigt bei "Gut"/"Leicht", bleibt bei "Schwer", sinkt bei "Nochmal"', () {
      var card = _newCard();
      var now = DateTime(2026, 1, 1);

      card = fsrs.review(card, Grade.good, now: now);
      expect(card.masteryBox, 1);
      now = card.due;

      card = fsrs.review(card, Grade.easy, now: now);
      expect(card.masteryBox, 2);
      now = card.due;

      card = fsrs.review(card, Grade.hard, now: now);
      expect(card.masteryBox, 2);
      now = card.due;

      card = fsrs.review(card, Grade.again, now: now);
      expect(card.masteryBox, 1);
    });

    test('sinkt nicht unter 0 und steigt nicht über Flashcard.masteryBoxCap', () {
      var card = _newCard();
      var now = DateTime(2026, 1, 1);

      card = fsrs.review(card, Grade.again, now: now);
      expect(card.masteryBox, 0);

      for (var i = 0; i < 10; i++) {
        card = fsrs.review(card, Grade.easy, now: now);
        now = card.due;
      }
      expect(card.masteryBox, Flashcard.masteryBoxCap);
    });

    test('steigt höchstens einmal pro Kalendertag (kein Grün durch Wiederholen in Minuten)', () {
      var card = _newCard();
      final morning = DateTime(2026, 1, 1, 9);

      card = fsrs.review(card, Grade.good, now: morning);
      expect(card.masteryBox, 1);
      for (var i = 1; i <= 5; i++) {
        card = fsrs.review(card, Grade.good, now: morning.add(Duration(minutes: i)));
      }
      expect(card.masteryBox, 1);

      card = fsrs.review(card, Grade.good, now: DateTime(2026, 1, 2, 9));
      expect(card.masteryBox, 2);
    });

    test('erneuter Fehlversuch am selben Tag: kein weiterer Lapse, Ampel sinkt nicht weiter', () {
      // Gelernte Karte (masteryBox 3) – im Daily Quiz falsch, in der
      // Wiederholungsrunde noch dreimal falsch.
      var card = _newCard();
      for (var day = 1; day <= 3; day++) {
        card = fsrs.review(card, Grade.good, now: DateTime(2026, 1, day, 9));
      }
      expect(card.masteryBox, 3);
      final morning = DateTime(2026, 1, 10, 9);
      card = fsrs.review(card, Grade.again, now: morning);
      final afterFirst = card;
      expect(card.masteryBox, 2);
      expect(card.lapses, 1);
      for (var i = 1; i <= 3; i++) {
        card = fsrs.review(card, Grade.again, now: morning.add(Duration(minutes: i)));
      }
      expect(card.masteryBox, 2);
      expect(card.lapses, 1);
      expect(card.stability, afterFirst.stability);
      expect(card.difficulty, afterFirst.difficulty);
      expect(card.state, 'relearning');
      expect(card.reps, afterFirst.reps + 3);

      // Am nächsten Tag wieder falsch: das zählt erneut.
      card = fsrs.review(card, Grade.again, now: DateTime(2026, 1, 11, 9));
      expect(card.masteryBox, 1);
      expect(card.lapses, 2);
    });

    test('neue Karte zweimal falsch am selben Tag bleibt "learning" ohne Lapse', () {
      var card = fsrs.review(_newCard(), Grade.again, now: DateTime(2026, 1, 1, 9));
      card = fsrs.review(card, Grade.again, now: DateTime(2026, 1, 1, 9, 5));
      expect(card.state, 'learning');
      expect(card.lapses, 0);
      expect(card.masteryBox, 0);
    });

    test('sinkt auch am selben Tag bei einer falschen Antwort', () {
      var card = fsrs.review(_newCard(), Grade.good, now: DateTime(2026, 1, 1, 9));
      card = fsrs.review(card, Grade.good, now: DateTime(2026, 1, 2, 9));
      expect(card.masteryBox, 2);

      card = fsrs.review(card, Grade.again, now: DateTime(2026, 1, 2, 10));
      expect(card.masteryBox, 1);
    });
  });

  group('FsrsService.gradeFromResult', () {
    test('richtige Antwort ergibt Good', () {
      expect(fsrs.gradeFromResult(true), Grade.good);
    });

    test('falsche Antwort ergibt Again', () {
      expect(fsrs.gradeFromResult(false), Grade.again);
    });

    test('eine falsch beantwortete Wiederholung kommt FRÜHER wieder, nicht später', () {
      var card = fsrs.review(_newCard(), fsrs.gradeFromResult(true), now: DateTime(2026, 1, 1));
      card = fsrs.review(card, fsrs.gradeFromResult(true), now: card.due);
      final intervalBefore = card.scheduledDays;

      final afterWrong = fsrs.review(card, fsrs.gradeFromResult(false), now: card.due);
      expect(afterWrong.scheduledDays, lessThan(intervalBefore));
      expect(afterWrong.lapses, card.lapses + 1);
    });

    test('eine einzelne richtige Antwort auf eine neue Karte führt nicht zu wochenlanger Pause', () {
      final card = fsrs.review(_newCard(), fsrs.gradeFromResult(true), now: DateTime(2026, 1, 1));
      expect(card.scheduledDays, lessThanOrEqualTo(4));
    });
  });

  group('FsrsService – Eskalationsstufen', () {
    Flashcard chainCard({required int level}) => Flashcard(
          id: 'c1',
          moduleId: 'm1',
          front: 'F',
          back: 'B',
          createdAt: DateTime(2026, 1, 1),
          due: DateTime(2026, 1, 1),
          type: QuestionType.singleChoice,
          variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
          variantLevel: level,
        );

    test('leichte/mittlere Stufe: Abstand höchstens transitStageMaxIntervalDays', () {
      var card = chainCard(level: 0);
      var now = DateTime(2026, 1, 1);
      for (var i = 0; i < 6; i++) {
        card = fsrs.review(card, Grade.good, now: now);
        expect(card.scheduledDays, lessThanOrEqualTo(FsrsService.transitStageMaxIntervalDays));
        now = card.due;
      }
    });

    test('schwerste Stufe: volle Spaced-Repetition-Abstände', () {
      var card = chainCard(level: 2);
      var now = DateTime(2026, 1, 1);
      for (var i = 0; i < 4; i++) {
        card = fsrs.review(card, Grade.good, now: now);
        now = card.due;
      }
      expect(card.scheduledDays, greaterThan(FsrsService.transitStageMaxIntervalDays));
    });

    test('restartForNewStage: morgen fällig, Ampel gelb, Wiederholungszahl bleibt', () {
      var card = chainCard(level: 1);
      var now = DateTime(2026, 1, 1);
      for (var i = 0; i < 4; i++) {
        card = fsrs.review(card, Grade.good, now: now);
        now = card.due;
      }
      final restarted = fsrs.restartForNewStage(card, now: DateTime(2026, 2, 1, 15));
      expect(restarted.due, DateTime(2026, 2, 2));
      expect(restarted.masteryBox, 1);
      expect(restarted.reps, card.reps);
      expect(restarted.stability, lessThan(card.stability));
    });
  });

  group('FsrsService – Kalendertage', () {
    test('abends gelernt, am nächsten Morgen wiederholt: zählt als ein Tag Abstand', () {
      final evening = DateTime(2026, 5, 4, 20);
      final first = fsrs.review(_newCard(), Grade.good, now: evening);
      final nextMorning = fsrs.review(first, Grade.good, now: DateTime(2026, 5, 5, 8));
      final sameDay = fsrs.review(first, Grade.good, now: DateTime(2026, 5, 4, 23));
      expect(nextMorning.elapsedDays, 1);
      expect(nextMorning.stability, greaterThan(sameDay.stability));
      expect(FsrsService.calendarDaysBetween(evening, DateTime(2026, 5, 5, 8)), 1);
      expect(FsrsService.calendarDaysBetween(DateTime(2026, 5, 5, 8), evening), 0);
    });

    test('Fälligkeit ist immer Mitternacht des Zieltags', () {
      final card = fsrs.review(_newCard(), Grade.good, now: DateTime(2026, 3, 28, 22, 30));
      expect(card.due.hour, 0);
      expect(card.due.minute, 0);
      expect(card.due.isAfter(DateTime(2026, 3, 28, 23, 59)), isTrue);
    });

    test('neue Karte beim ersten Versuch falsch ist kein Lapse', () {
      final card = fsrs.review(_newCard(), Grade.again, now: DateTime(2026, 1, 1));
      expect(card.lapses, 0);
      expect(card.state, 'learning');
    });
  });
}
