import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/mastery_service.dart';

Flashcard _card({
  required int reps,
  double stability = 0,
  DateTime? lastReview,
  int lapses = 0,
  int masteryBox = 0,
}) =>
    Flashcard(
      id: 'c',
      moduleId: 'm',
      front: 'f',
      back: 'b',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      reps: reps,
      stability: stability,
      lastReview: lastReview,
      lapses: lapses,
      masteryBox: masteryBox,
    );

void main() {
  final service = MasteryService();
  final now = DateTime(2026, 6, 1);

  test('nie wiederholte Karte gilt als neu', () {
    expect(service.levelFor(_card(reps: 0), now: now), MasteryLevel.neu);
  });

  test('hohe Stabilität kurz nach Review OHNE ausreichenden masteryBox gilt nur als gelb', () {
    // Regression: früher reichte allein eine hohe momentane Retrievability
    // (die direkt nach jeder Wiederholung per Definition ~100% beträgt) für
    // "grün" – zwei schnell hintereinander (ggf. geratene) richtige
    // Antworten hätten das schon ausgelöst.
    final card = _card(reps: 3, stability: 20, lastReview: now.subtract(const Duration(days: 1)));
    expect(service.levelFor(card, now: now), MasteryLevel.yellow);
  });

  test('hohe Stabilität UND ausreichender masteryBox gilt als grün', () {
    final card = _card(
      reps: 3,
      stability: 20,
      lastReview: now.subtract(const Duration(days: 1)),
      masteryBox: Flashcard.masteryBoxCap,
    );
    expect(service.levelFor(card, now: now), MasteryLevel.green);
  });

  test('stark verfallene Retrievability gilt als rot', () {
    final card = _card(reps: 5, stability: 1, lastReview: now.subtract(const Duration(days: 60)));
    expect(service.levelFor(card, now: now), MasteryLevel.red);
  });

  test('mittlere Retrievability gilt als gelb', () {
    // elapsed/stability = 2 -> Retrievability ≈ 0.825, zwischen den beiden
    // Schwellen (0.7 und 0.9).
    final card = _card(reps: 3, stability: 10, lastReview: now.subtract(const Duration(days: 20)));
    final level = service.levelFor(card, now: now);
    expect(level, MasteryLevel.yellow);
  });

  test('breakdown zählt jede Stufe korrekt', () {
    final cards = [
      _card(reps: 0),
      _card(
        reps: 3,
        stability: 20,
        lastReview: now.subtract(const Duration(days: 1)),
        masteryBox: Flashcard.masteryBoxCap,
      ),
      _card(reps: 5, stability: 1, lastReview: now.subtract(const Duration(days: 60))),
    ];
    final breakdown = service.breakdown(cards, now: now);
    expect(breakdown[MasteryLevel.neu], 1);
    expect(breakdown[MasteryLevel.green], 1);
    expect(breakdown[MasteryLevel.red], 1);
    expect(breakdown[MasteryLevel.yellow], 0);
  });
}
