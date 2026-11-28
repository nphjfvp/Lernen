import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/review_log_repository.dart';
import 'package:lernen/services/answer_signals.dart';
import 'package:lernen/services/calendar_days.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/panik_planner.dart';

/// 16 Pflichtkern- und 13 Ausbau-Typen wie im echten Inhalt, mit Voraussetzungen.
List<PlanType> types() => [
      for (var i = 0; i < 29; i++)
        PlanType(
          id: 'T$i',
          title: 'Typ $i',
          core: i < 16,
          weight: ['H', 'M', 'N'][i % 3],
          area: 'G${i % 5}',
          prerequisites: i == 5 ? ['T4'] : (i == 20 ? ['T6'] : const []),
        ),
    ];

/// Spielt einen Lernzeitraum durch: jeden Tag (außer [missed]) werden die neuen
/// Typen eingeführt, die fälligen geübt, Probeklausuren geschrieben.
({Map<String, List<int>> practiceDays, Map<int, DayPlan> plans, Map<String, int> introDay}) simulate(
  int days, {
  double hours = 4,
  Set<int> missed = const {},
}) {
  final start = DateTime(2026, 12, 1);
  final exam = DateTime(2026, 12, 1 + days);
  final progress = <String, TypeProgress>{};
  final practiceDays = <String, List<int>>{};
  final introDay = <String, int>{};
  final plans = <int, DayPlan>{};
  var mocks = 0;
  for (var day = 0; day <= days; day++) {
    final today = DateTime(2026, 12, 1 + day);
    final plan = PanikPlanner.plan(
        today: today, start: start, exam: exam, hoursPerDay: hours, types: types(), progress: progress, mocksDone: mocks);
    plans[day] = plan;
    if (missed.contains(day) || plan.phase == PlanPhase.examDay) continue;
    for (final id in plan.newTypes) {
      progress[id] = TypeProgress(introducedOn: today, lastPracticed: today);
      introDay[id] = day;
    }
    for (final id in plan.dueTypes) {
      final p = progress[id]!;
      progress[id] = TypeProgress(introducedOn: p.introducedOn, lastPracticed: today, reviewDays: p.reviewDays + 1);
      practiceDays.putIfAbsent(id, () => []).add(day);
    }
    if (plan.mockDue) mocks++;
  }
  return (practiceDays: practiceDays, plans: plans, introDay: introDay);
}

void main() {
  for (final days in [14, 21, 42]) {
    group('$days Tage, 6 h/Tag', () {
      final sim = simulate(days, hours: 6);
      final half = (days / 2).ceil();

      test('neuer Stoff nur in der ersten Hälfte, Pflichtkern zuerst', () {
        for (final MapEntry(key: day, value: plan) in sim.plans.entries) {
          if (days - day <= half) expect(plan.newTypes.where((id) => int.parse(id.substring(1)) >= 16), isEmpty);
        }
        final coreIntro = [for (var i = 0; i < 16; i++) sim.introDay['T$i']];
        expect(coreIntro, everyElement(isNotNull), reason: 'jeder Pflichtkern-Typ wird eingeführt');
        expect(coreIntro.whereType<int>().every((d) => d < days - half), isTrue);
      });

      test('Voraussetzungen vor Folgetyp', () {
        expect(sim.introDay['T4']!, lessThanOrEqualTo(sim.introDay['T5']!));
      });

      test('Wiederholung nach 1–3, dann 4–7 Tagen und in den letzten 2–4 Tagen', () {
        for (final MapEntry(key: id, value: intro) in sim.introDay.entries) {
          final after = [for (final d in sim.practiceDays[id] ?? const <int>[]) d - intro];
          final left = days - intro;
          if (left > 3) expect(after.first, inInclusiveRange(1, 3), reason: '$id: erste Wiederholung');
          if (after.length > 1 && left > 9) expect(after[1] - after[0], inInclusiveRange(4, 7), reason: '$id: zweite');
          expect((sim.practiceDays[id] ?? const []).any((d) => days - d >= 2 && days - d <= 4), isTrue, reason: '$id: Schlussphase');
        }
      });

      test('zwei Probeklausuren 2–7 Tage vorher, letzter Tag leicht', () {
        final mockDays = [for (final e in sim.plans.entries) if (e.value.mockDue) days - e.key];
        expect(mockDays, [5, 2]);
        final last = sim.plans[days - 1]!;
        expect(last.phase, PlanPhase.finalDay);
        expect(last.newTypes, isEmpty);
        expect(last.studyMinutes, lessThanOrEqualTo(120));
        expect(sim.plans[days]!.phase, PlanPhase.examDay);
      });

      test('Blöcke 50 min mit Pausen, lange Pause nach zwei Blöcken', () {
        final blocks = sim.plans[0]!.blocks;
        expect(blocks.where((b) => b.kind == PlanBlockKind.newType || b.kind == PlanBlockKind.mixed).every((b) => b.minutes == 50), isTrue);
        expect(blocks[1].pauseAfter, 20);
        expect(blocks.first.pauseAfter, 10);
        expect(blocks.last.kind, PlanBlockKind.formulas);
      });
    });
  }

  test('wenig Zeit: Ausbau wird zuerst gestrichen und offen angezeigt', () {
    final plan = PanikPlanner.plan(
      today: DateTime(2026, 12, 1),
      start: DateTime(2026, 12, 1),
      exam: DateTime(2026, 12, 15),
      hoursPerDay: 2,
      types: types(),
      progress: const {},
    );
    expect(plan.dropped, isNotEmpty);
    final droppedCore = plan.dropped.where((id) => int.parse(id.substring(1)) < 16);
    if (droppedCore.isNotEmpty) {
      // Pflichtkern wird nur gestrichen, wenn schon der ganze Ausbau gestrichen ist.
      expect(plan.dropped.where((id) => int.parse(id.substring(1)) >= 16), hasLength(13));
    }
  });

  test('verpasste Tage: neu planen statt aufstauen, Pflichtkern kommt trotzdem', () {
    final sim = simulate(21, hours: 6, missed: {1, 2, 3, 4});
    for (var i = 0; i < 16; i++) {
      expect(sim.introDay['T$i'], isNotNull, reason: 'T$i');
    }
    final dayAfter = sim.plans[5]!;
    expect(dayAfter.newTypes.length, lessThanOrEqualTo(3), reason: 'nicht alles auf einmal nachholen');
    expect(dayAfter.dueTypes, isNotEmpty, reason: 'Liegengebliebenes wird wiederholt');
  });

  test('Fehler: Typ nach 2 Tagen wieder fällig', () {
    final day0 = DateTime(2026, 12, 1);
    final plan = PanikPlanner.plan(
      today: DateTime(2026, 12, 3),
      start: day0,
      exam: DateTime(2026, 12, 30),
      hoursPerDay: 4,
      types: types(),
      progress: {'T0': TypeProgress(introducedOn: day0, lastPracticed: DateTime(2026, 12, 1, 15), reviewDays: 2, lastErrorOn: DateTime(2026, 12, 1, 15))},
    );
    expect(plan.dueTypes, contains('T0'));
  });

  group('aus dem Antwort-Protokoll', () {
    Flashcard card(String id, String type, String kind) => Flashcard(
          id: id,
          moduleId: 'm',
          front: 'f',
          back: 'b',
          createdAt: DateTime(2026, 12, 1),
          due: DateTime(2026, 12, 1),
          taskData: {
            'panik': {'item': id, 'type': type, 'kind': kind, 'core': true, 'weight': 'H', 'verified': true}
          },
        );
    final cards = [card('a1', 'A', 'task'), card('a2', 'A', 'task'), card('ar', 'A', 'recognize'), card('b1', 'B', 'task'), card('ae', 'A', 'example')];
    ReviewLogEntry e(String id, int day, bool ok, {AnswerConfidence? conf}) =>
        ReviewLogEntry(cardId: id, moduleId: 'm', at: DateTime(2026, 12, day, 10), grade: ok ? Grade.good : Grade.again, correct: ok, confidence: conf);

    test('Einführung, Wiederholungstage, Fehler, Wechselkriterium, Sicherheit', () {
      final p = PanikPlanner.progressFrom(cards: cards, log: [
        e('a1', 1, true), // Einführungstag – zählt nicht für die Sicherheit
        e('a2', 3, false),
        e('ar', 3, true),
        e('a1', 6, true, conf: AnswerConfidence.sure),
      ]);
      final a = p['A']!;
      expect(a.introducedOn, DateTime(2026, 12, 1, 10));
      expect(a.reviewDays, 2);
      expect(a.lastErrorOn, DateTime(2026, 12, 3, 10));
      expect(a.mastered, isTrue);
      expect(a.delayed, [false, true, true]);
      expect(a.confidence, closeTo(2 / 3, 1e-9));
      expect(p['B']!.introduced, isFalse);
    });

    test('Eingangstest bestanden: eingeführt und beherrscht ab Start', () {
      final p = PanikPlanner.progressFrom(cards: cards, log: const [], placedOut: {'B'}, start: DateTime(2026, 12, 1));
      expect((p['B']!.introduced, p['B']!.mastered), (true, true));
    });
  });

  test('gemischter Satz: ab Woche 2 höchstens ⅓ aus jungen Typen, ohne Reserve/Beispiele, Typen abwechselnd', () {
    final start = DateTime(2026, 12, 1);
    final today = DateTime(2026, 12, 12);
    final cards = <Flashcard>[];
    for (final t in ['A', 'B', 'C', 'N']) {
      for (var i = 0; i < 4; i++) {
        for (final kind in ['task', 'reserve', 'example', 'recognize']) {
          cards.add(Flashcard(
            id: '$t$i$kind',
            moduleId: 'm',
            front: 'f',
            back: 'b',
            createdAt: start,
            due: start,
            weight: kind == 'reserve' ? 0 : 1,
            taskData: {
              'panik': {'item': '$t$i', 'type': t, 'kind': kind, 'core': true, 'weight': 'H', 'verified': true}
            },
          ));
        }
      }
    }
    final progress = {
      'A': TypeProgress(introducedOn: start),
      'B': TypeProgress(introducedOn: start),
      'C': TypeProgress(introducedOn: DateTime(2026, 12, 2)),
      'N': TypeProgress(introducedOn: DateTime(2026, 12, 10)), // jung
    };
    for (var seed = 0; seed < 20; seed++) {
      final set = PanikPlanner.mixedSet(
          cards: cards, progress: progress, dueTypes: const ['N', 'A'], today: today, start: start, size: 6, random: Random(seed));
      expect(set, hasLength(6));
      final kinds = set.map((c) => c.taskData!['panik']['kind']).toSet();
      expect(kinds.difference({'task', 'recognize'}), isEmpty);
      final young = set.where((c) => c.taskData!['panik']['type'] == 'N').length;
      expect(young * 3, lessThanOrEqualTo(6));
      expect(calendarDaysBetween(start, today), greaterThanOrEqualTo(7));
    }
  });
}
