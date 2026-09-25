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
    test('steigt bei "Gut"/"Leicht", sinkt bei "Nochmal"/"Schwer"', () {
      var card = _newCard();
      var now = DateTime(2026, 1, 1);

      card = fsrs.review(card, Grade.good, now: now);
      expect(card.masteryBox, 1);
      now = card.due;

      card = fsrs.review(card, Grade.easy, now: now);
      expect(card.masteryBox, 2);
      now = card.due;

      card = fsrs.review(card, Grade.hard, now: now);
      expect(card.masteryBox, 1);
      now = card.due;

      card = fsrs.review(card, Grade.again, now: now);
      expect(card.masteryBox, 0);
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
}
