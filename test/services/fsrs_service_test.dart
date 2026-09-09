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
}
