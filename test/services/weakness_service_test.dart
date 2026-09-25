import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/mastery_service.dart';
import 'package:lernen/services/weakness_service.dart';

Flashcard _card(
  String id, {
  int reps = 3,
  int lapses = 0,
  int masteryBox = 2,
  String state = 'review',
  int variantMissStreak = 0,
  DateTime? lastReview,
}) {
  return Flashcard(
    id: id,
    moduleId: 'm1',
    front: 'F$id',
    back: 'B$id',
    createdAt: DateTime(2026, 1, 1),
    due: DateTime(2026, 3, 11),
    reps: reps,
    lapses: lapses,
    masteryBox: masteryBox,
    state: state,
    variantMissStreak: variantMissStreak,
    stability: reps == 0 ? 0 : 10,
    difficulty: 5,
    lastReview: lastReview ?? DateTime(2026, 3, 9),
  );
}

void main() {
  final now = DateTime(2026, 3, 10);
  final service = WeaknessService();

  test('neue und unauffällige Karten stehen nicht im Fehlertagebuch', () {
    final result = service.rank([
      _card('neu', reps: 0, masteryBox: 0),
      _card('ok'),
    ], now: now);
    expect(result, isEmpty);
  });

  test('sortiert nach Dringlichkeit: oft vergessen vor einmal vergessen', () {
    final result = service.rank([
      _card('einmal', lapses: 1),
      _card('oft', lapses: 4),
      _card('rot', masteryBox: 0),
    ], now: now);
    expect(result.map((w) => w.card.id).toList(), ['oft', 'rot', 'einmal']);
    expect(result.first.reasons, contains('4× vergessen'));
  });

  test('zuletzt falsch und rot wird als Grund genannt', () {
    final result = service.rank([_card('x', masteryBox: 0, state: 'relearning', lapses: 1)], now: now);
    final weak = result.single;
    expect(weak.level, MasteryLevel.red);
    expect(weak.reasons, containsAll(['1× vergessen', 'zuletzt falsch']));
  });

  test('limit begrenzt die Liste', () {
    final cards = List.generate(10, (i) => _card('c$i', lapses: i + 1));
    expect(service.rank(cards, now: now, limit: 3), hasLength(3));
  });
}
