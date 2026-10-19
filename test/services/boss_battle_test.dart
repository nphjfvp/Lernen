import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/boss_battle.dart';

Flashcard _card(String id, {int reps = 2, int box = 0}) => Flashcard(
  id: id,
  moduleId: 'm',
  front: 'Frage $id',
  back: 'Antwort $id',
  createdAt: DateTime(2026, 9, 1),
  due: DateTime(2026, 9, 1),
  reps: reps,
  masteryBox: box,
  stability: 30,
  state: 'review',
  lastReview: DateTime.now(),
);

void main() {
  test('Richtig trifft, falsch kostet ein Herz und kommt drei Karten später wieder', () {
    final battle = BossBattle([_card('a'), _card('b'), _card('c'), _card('d'), _card('e')]);
    expect(battle.hp, 5);
    expect(battle.answer(correct: false), BossHit.miss); // a falsch
    expect(battle.hearts, BossBattle.defaultHearts - 1);
    expect(battle.hp, 5);
    expect([for (var i = 0; i < 3; i++) (battle.current!.id, battle.answer(correct: true)).$1], ['b', 'c', 'd']);
    expect(battle.current!.id, 'a', reason: 'nach drei Karten wieder dran');
    expect(battle.combo, 3);
    battle.answer(correct: true); // a sitzt jetzt
    battle.answer(correct: true); // e
    expect(battle.won, isTrue);
    expect(battle.over, isTrue);
    expect(battle.current, isNull);
    expect(battle.bestCombo, 5);
    expect(battle.toReview.map((c) => c.id), ['a']);
  });

  test('Ohne Herzen entkommt der Boss; Fehler am Ende kommen sofort wieder', () {
    final battle = BossBattle([_card('a'), _card('b')], hearts: 2);
    battle.answer(correct: true); // a
    battle.answer(correct: false); // b → wieder vorne, weil sonst keine mehr
    expect(battle.current!.id, 'b');
    battle.answer(correct: false);
    expect(battle.lost, isTrue);
    expect(battle.won, isFalse);
    expect(battle.missesOf('b'), 2);
    expect(battle.toReview.map((c) => c.id), ['b']);
    expect(() => battle.answer(correct: true), throwsStateError);
  });

  test('Überspringen schiebt ans Ende, ohne Treffer oder Fehler', () {
    final battle = BossBattle([_card('a'), _card('b')]);
    battle.skip();
    expect(battle.current!.id, 'b');
    expect(battle.hearts, BossBattle.defaultHearts);
    expect(battle.hp, 2);
    final single = BossBattle([_card('x')])..skip();
    expect(single.current!.id, 'x');
  });

  test('Auswahl: schwächste zuerst, ohne neue Karten, höchstens zehn', () {
    final red = [for (var i = 0; i < 4; i++) _card('r$i')];
    final neu = [for (var i = 0; i < 4; i++) _card('n$i', reps: 0)];
    final green = [for (var i = 0; i < 9; i++) _card('g$i', box: Flashcard.masteryBoxCap)];
    final picked = BossBattle.pickCards([...green, ...neu, ...red], shuffle: (_) {});
    expect(picked, hasLength(BossBattle.maxCards));
    expect(picked.take(4).map((c) => c.id), ['r0', 'r1', 'r2', 'r3']);
    expect(picked.any((c) => c.id.startsWith('n')), isFalse);
  });
}
