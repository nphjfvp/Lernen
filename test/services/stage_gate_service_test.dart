import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/daily_scheduler_service.dart';
import 'package:lernen/services/mastery_service.dart';
import 'package:lernen/services/stage_gate_service.dart';

Flashcard _card(
  String id, {
  QuestionType type = QuestionType.singleChoice,
  String? conceptId = 'k1',
  String moduleId = 'm1',
  int? stageLevel,
  String? stageGroup,
  int masteryBox = 0,
  int reps = 0,
  DateTime? due,
  List<QuestionType>? variantChain,
}) =>
    Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: 'Frage $id',
      back: 'Antwort',
      createdAt: DateTime(2026, 1, 1),
      due: due ?? DateTime(2026, 1, 1),
      type: type,
      stageLevel: stageLevel,
      stageGroup: stageGroup,
      masteryBox: masteryBox,
      reps: reps,
      stability: reps == 0 ? 0 : 5,
      difficulty: reps == 0 ? 0 : 5,
      lastReview: reps == 0 ? null : DateTime(2026, 3, 1),
      variantChain: variantChain,
    );

const _green = Flashcard.masteryBoxCap;

void main() {
  group('Stufe einer Karte', () {
    test('aus dem Fragetyp: Auswahl leicht, Lücke/Zuordnen mittel, Freitext schwer', () {
      expect(StageGate.levelOfType(QuestionType.singleChoice), StageLevel.leicht);
      expect(StageGate.levelOfType(QuestionType.multipleChoice), StageLevel.leicht);
      expect(StageGate.levelOfType(QuestionType.fillBlank), StageLevel.mittel);
      expect(StageGate.levelOfType(QuestionType.dragDrop), StageLevel.mittel);
      expect(StageGate.levelOfType(QuestionType.freeText), StageLevel.schwer);
      expect(StageGate.levelOfType(QuestionType.html), StageLevel.schwer);
    });

    test('eine gesetzte Stufe gewinnt über den Typ', () {
      expect(StageGate.levelOf(_card('a', type: QuestionType.singleChoice, stageLevel: 2)), StageLevel.schwer);
    });
  });

  group('StageGate.statuses', () {
    test('erst leicht: mittel und schwer warten, solange leicht nicht sitzt', () {
      final cards = [
        _card('l', type: QuestionType.singleChoice),
        _card('m', type: QuestionType.fillBlank),
        _card('s', type: QuestionType.freeText),
      ];
      final s = StageGate.statuses(cards);
      expect(s['l'], isNull); // aktiv
      expect(s['m'], StageStatus.locked);
      expect(s['s'], StageStatus.locked);
      expect(StageGate.learnable(cards).map((c) => c.id), ['l']);
    });

    test('leicht grün: leicht ruht, mittel ist dran, schwer wartet', () {
      final s = StageGate.statuses([
        _card('l', masteryBox: _green, reps: 4),
        _card('m', type: QuestionType.fillBlank),
        _card('s', type: QuestionType.freeText),
      ]);
      expect(s['l'], StageStatus.done);
      expect(s['m'], isNull);
      expect(s['s'], StageStatus.locked);
    });

    test('alles grün: nur die schwerste Stufe bleibt in der Wiederholung', () {
      final s = StageGate.statuses([
        _card('l', masteryBox: _green, reps: 4),
        _card('m', type: QuestionType.fillBlank, masteryBox: _green, reps: 4),
        _card('s', type: QuestionType.freeText, masteryBox: _green, reps: 4),
      ]);
      expect(s['l'], StageStatus.done);
      expect(s['m'], StageStatus.done);
      expect(s['s'], isNull);
    });

    test('fehlt leicht, ist mittel direkt dran; fehlt schwer, bleibt mittel in der Wiederholung', () {
      final withoutEasy = StageGate.statuses([
        _card('m', type: QuestionType.fillBlank),
        _card('s', type: QuestionType.freeText),
      ]);
      expect(withoutEasy['m'], isNull);
      expect(withoutEasy['s'], StageStatus.locked);

      final withoutHard = StageGate.statuses([
        _card('l', masteryBox: _green, reps: 4),
        _card('m', type: QuestionType.fillBlank, masteryBox: _green, reps: 4),
      ]);
      expect(withoutHard['l'], StageStatus.done);
      expect(withoutHard['m'], isNull);
    });

    test('alle Karten einer Stufe müssen sitzen, bevor die nächste dran ist', () {
      final s = StageGate.statuses([
        _card('l1', masteryBox: _green, reps: 4),
        _card('l2', masteryBox: 2, reps: 2),
        _card('m', type: QuestionType.fillBlank),
      ]);
      expect(s['l1'], isNull);
      expect(s['l2'], isNull);
      expect(s['m'], StageStatus.locked);
    });

    test('Karten ohne Konzept/Gruppe, allein in ihrer Gruppe oder mit Stufenkette laufen normal', () {
      final s = StageGate.statuses([
        _card('ohne', conceptId: null, type: QuestionType.freeText),
        _card('allein', conceptId: 'k9', type: QuestionType.freeText),
        _card('kette',
            type: QuestionType.freeText, variantChain: const [QuestionType.singleChoice, QuestionType.freeText]),
        _card('leicht'),
      ]);
      expect(s, isEmpty);
    });

    test('Gruppen sind je Fach getrennt, stageGroup geht vor dem Konzept', () {
      final s = StageGate.statuses([
        _card('a', moduleId: 'm1'),
        _card('b', moduleId: 'm2', type: QuestionType.freeText),
        _card('c', conceptId: 'k1', stageGroup: 'andere', type: QuestionType.freeText),
      ]);
      expect(s, isEmpty);
    });
  });

  group('Tagesplan und Ampel', () {
    test('das Daily Quiz führt nur die freigeschaltete Stufe ein', () {
      final module = Module(
        id: 'm1',
        name: 'Technik',
        colorValue: 0,
        icon: '⚙️',
        examDate: null,
        createdAt: DateTime(2026, 1, 1),
      );
      final plan = DailySchedulerService().buildPlan(
        modules: [module],
        allCards: [
          _card('l'),
          _card('m', type: QuestionType.fillBlank),
          _card('s', type: QuestionType.freeText),
          // Schon mal gelernt, aber jetzt wartend: auch nicht fällig.
          _card('s2', type: QuestionType.freeText, reps: 2, masteryBox: 1, due: DateTime(2026, 3, 1)),
        ],
        now: DateTime(2026, 3, 10),
      );
      expect(plan.allCards.map((c) => c.id), ['l']);
    });

    test('Ampel: ruhende Stufe zählt grün, wartende als noch nicht dran', () {
      final breakdown = MasteryService().breakdown([
        _card('l', masteryBox: _green, reps: 4, due: DateTime(2020, 1, 1)),
        _card('m', type: QuestionType.fillBlank, masteryBox: 1, reps: 1),
        _card('s', type: QuestionType.freeText, masteryBox: 1, reps: 1),
      ], now: DateTime(2026, 3, 10));
      expect(breakdown[MasteryLevel.green], 1);
      expect(breakdown[MasteryLevel.yellow], 1);
      expect(breakdown[MasteryLevel.neu], 1);
    });
  });

  group('Rückfall auf die leichtere Stufe', () {
    test('holt die nächstleichtere Stufe zurück (knapp unter grün, heute fällig)', () {
      final cards = [
        _card('l', masteryBox: _green, reps: 4, due: DateTime(2026, 6, 1)),
        _card('m', type: QuestionType.fillBlank, masteryBox: _green, reps: 4, due: DateTime(2026, 6, 1)),
        _card('s', type: QuestionType.freeText, masteryBox: 0, reps: 4),
      ];
      final reopened = StageGate.reactivateEasier(cards, cards[2], now: DateTime(2026, 3, 10, 15));
      expect(reopened.map((c) => c.id), ['m']);
      expect(reopened.single.masteryBox, _green - 1);
      expect(reopened.single.due, DateTime(2026, 3, 10));

      // Danach ist mittel wieder dran, schwer wartet.
      final after = [cards[0], reopened.single, cards[2]];
      final s = StageGate.statuses(after);
      expect(s['m'], isNull);
      expect(s['s'], StageStatus.locked);
    });

    test('ohne leichtere Stufe passiert nichts', () {
      final cards = [_card('l'), _card('l2')];
      expect(StageGate.reactivateEasier(cards, cards[0]), isEmpty);
      expect(StageGate.reactivateEasier([_card('x', conceptId: null)], _card('x', conceptId: null)), isEmpty);
    });
  });

  group('KI-Zuordnung', () {
    test('assignable: ohne Stufenketten, Zusammengehöriges beieinander', () {
      final list = StageGate.assignable([
        _card('b', conceptId: 'k2'),
        _card('kette', variantChain: const [QuestionType.singleChoice, QuestionType.freeText]),
        _card('a', conceptId: 'k1'),
      ]);
      expect(list.map((c) => c.id), ['a', 'b']);
    });

    test('applyAssignments setzt Stufe und Gruppe (mit Lauf-Kennung), lässt Unbekanntes stehen', () {
      final cards = [_card('a'), _card('b'), _card('c')];
      final updated = StageGate.applyAssignments(cards, {
        1: (level: 0, group: 'Stücklisten'),
        2: (level: 2, group: 'Stücklisten'),
        9: (level: 1, group: 'x'),
      }, runTag: 'r1');
      expect(updated.map((c) => c.id), ['a', 'b']);
      expect(updated[0].stageLevel, 0);
      expect(updated[1].stageLevel, 2);
      expect(updated[0].stageGroup, 'Stücklisten#r1');
      expect(StageGate.groupOf(updated[0]), StageGate.groupOf(updated[1]));
    });
  });
}
