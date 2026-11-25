import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/mastery_service.dart';
import 'package:lernen/services/placement_service.dart';
import 'package:lernen/services/stage_gate_service.dart';

Flashcard _card(String id, int level, {int reps = 0, int box = 0, String group = 'g'}) => Flashcard(
      id: id,
      moduleId: 'm1',
      front: 'Frage $id',
      back: 'Antwort',
      createdAt: DateTime(2026, 1, level + 1),
      due: DateTime(2026, 1, 1),
      type: QuestionType.flashcard,
      stageLevel: level,
      stageGroup: group,
      reps: reps,
      masteryBox: box,
      state: reps == 0 ? 'new' : 'review',
      stability: reps == 0 ? 0 : 5,
      lastReview: reps == 0 ? null : DateTime.now(),
    );

void main() {
  test('Kandidaten: schwerste Stufe zuerst, nur wenn die schwereren noch neu sind', () {
    final cards = [_card('l', 0), _card('m', 1), _card('s', 2), _card('x', 0, group: 'h'), _card('y', 1, reps: 1, box: 1, group: 'h')];
    final groups = PlacementService.candidates(cards);
    expect(groups, hasLength(1));
    expect(groups.single.probes.map((c) => c.id), ['s', 'm']);
    expect(groups.single.activeLevel, StageLevel.leicht);
  });

  test('Schwer sicher gewusst: leicht und mittel ruhen, schwer wird aktiv, Ampel zählt sie nicht grün', () {
    final cards = [_card('l', 0), _card('m', 1), _card('s', 2)];
    final group = PlacementService.candidates(cards).single;
    final changed = PlacementService.placeOutBelow(group, StageLevel.schwer);
    expect(changed.map((c) => c.id), ['l', 'm']);
    expect(changed.every((c) => c.placedOut), isTrue);

    final after = [...changed, cards[2]];
    final statuses = StageGate.statuses(after);
    expect(StageGate.statusOf(statuses, after[0]), StageStatus.done);
    expect(StageGate.statusOf(statuses, after[2]), StageStatus.active);
    final breakdown = MasteryService().breakdown(after);
    expect(breakdown[MasteryLevel.green], 0);
    expect(breakdown[MasteryLevel.neu], 1); // nur die schwere Stufe zählt
  });

  test('Rückfall holt übersprungene Stufen zurück und hebt die Markierung auf', () {
    final l = _card('l', 0).copyWithPlacedOut(true);
    final m = _card('m', 1).copyWithPlacedOut(true);
    final s = _card('s', 2, reps: 3, box: 0);
    final reopened = StageGate.reactivateEasier([l, m, s], s);
    expect(reopened.map((c) => c.id), ['m']);
    expect(reopened.single.placedOut, isFalse);
  });

  test('placedOut übersteht toMap/fromMap und Inhaltsänderungen', () {
    final card = _card('l', 0).copyWithPlacedOut(true);
    expect(Flashcard.fromMap(card.toMap()).placedOut, isTrue);
    expect(card.copyWithContent(front: 'Neu').placedOut, isTrue);
    expect(_card('z', 0).toMap().containsKey('placedOut'), isFalse);
  });
}
