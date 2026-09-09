import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/daily_scheduler_service.dart';

Module _module(String id, {DateTime? examDate}) => Module(
      id: id,
      name: id,
      colorValue: 0xFF000000,
      icon: '📘',
      examDate: examDate,
      createdAt: DateTime(2026, 1, 1),
    );

Flashcard _newFlashcard(String id, String moduleId, {DateTime? createdAt}) => Flashcard(
      id: id,
      moduleId: moduleId,
      front: 'F$id',
      back: 'B$id',
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
    );

Flashcard _dueFlashcard(String id, String moduleId, DateTime due) => Flashcard(
      id: id,
      moduleId: moduleId,
      front: 'F$id',
      back: 'B$id',
      createdAt: DateTime(2026, 1, 1),
      due: due,
      reps: 3,
      stability: 5,
      lastReview: due.subtract(const Duration(days: 5)),
    );

void main() {
  final scheduler = DailySchedulerService();
  final now = DateTime(2026, 6, 1);

  test('Modul ohne Klausurdatum verteilt neue Karten über den Standard-Horizont', () {
    final module = _module('m1');
    final cards = List.generate(28, (i) => _newFlashcard('n$i', 'm1'));

    final plan = scheduler.buildPlan(modules: [module], allCards: cards, now: now);

    // 28 Karten / 14 Tage Standard-Horizont, volles Wissen (keine bisherigen
    // Reviews) => voller Takt = ceil(28/14) = 2.
    expect(plan.newCardBudgetByModule['m1'], 2);
    expect(plan.newCards.length, 2);
  });

  test('kurz vor der Klausur werden keine neuen Karten mehr eingeführt', () {
    final module = _module('m1', examDate: now.add(const Duration(days: 2)));
    final cards = List.generate(10, (i) => _newFlashcard('n$i', 'm1'));

    final plan = scheduler.buildPlan(modules: [module], allCards: cards, now: now);

    expect(plan.newCardBudgetByModule['m1'], 0);
    expect(plan.newCards, isEmpty);
  });

  test('fällige Wiederholungen erscheinen unabhängig vom Neu-Karten-Budget, sortiert nach Fälligkeit', () {
    final module = _module('m1', examDate: now.add(const Duration(days: 2)));
    final cards = [
      _dueFlashcard('d1', 'm1', now.subtract(const Duration(days: 1))),
      _dueFlashcard('d2', 'm1', now.subtract(const Duration(days: 3))),
      _dueFlashcard('d3', 'm1', now), // heute fällig
    ];

    final plan = scheduler.buildPlan(modules: [module], allCards: cards, now: now);

    expect(plan.dueCards.map((c) => c.id).toList(), ['d2', 'd1', 'd3']);
  });

  test('noch nicht fällige Karten (due in der Zukunft) tauchen nicht auf', () {
    final module = _module('m1');
    final cards = [
      _dueFlashcard('future', 'm1', now.add(const Duration(days: 5))),
    ];

    final plan = scheduler.buildPlan(modules: [module], allCards: cards, now: now);

    expect(plan.dueCards, isEmpty);
  });

  test('Gesamtsession wird bei Überschreiten des Limits gekappt, fällige Karten haben Vorrang', () {
    final module = _module('m1');
    final dueCards = List.generate(
      50,
      (i) => _dueFlashcard('d$i', 'm1', now.subtract(Duration(days: i + 1))),
    );
    // Genug Kandidaten, damit das Neu-Karten-Budget in jedem Fall am
    // Pro-Modul-Limit (15/Tag) deckelt, unabhängig vom Wissensstand.
    final newCards = List.generate(450, (i) => _newFlashcard('n$i', 'm1'));

    final plan = scheduler.buildPlan(modules: [module], allCards: [...dueCards, ...newCards], now: now);

    expect(plan.newCardBudgetByModule['m1'], DailySchedulerService.maxNewCardsPerModulePerDay);
    expect(plan.dueCards.length, 50);
    expect(plan.total, DailySchedulerService.maxSessionSize);
    expect(plan.newCards.length, DailySchedulerService.maxSessionSize - 50);
  });

  test('schwacher Wissensstand bremst das Tempo neuer Karten', () {
    final now2 = DateTime(2026, 6, 1);
    final module = _module('m2');
    // 42 neue Karten / 14 Tage Standard-Horizont => Basis-Takt ceil(42/14)=3.
    final newCards = List.generate(42, (i) => _newFlashcard('n$i', 'm2'));

    final baselinePlan = scheduler.buildPlan(modules: [module], allCards: newCards, now: now2);
    expect(baselinePlan.newCardBudgetByModule['m2'], 3,
        reason: 'Baseline ohne bisherige Reviews (volles Wissen angenommen)');

    final weakReviewed = Flashcard(
      id: 'weak',
      moduleId: 'm2',
      front: 'f',
      back: 'b',
      createdAt: DateTime(2026, 1, 1),
      due: now2.subtract(const Duration(days: 190)),
      reps: 5,
      stability: 0.5, // sehr niedrig -> Retrievability nach 200 Tagen ~ 10%
      lastReview: now2.subtract(const Duration(days: 200)),
    );

    final weakPlan = scheduler.buildPlan(
      modules: [module],
      allCards: [weakReviewed, ...newCards],
      now: now2,
    );

    // Bei schlechtem Wissensstand (niedrige Retrievability) wird das Tempo
    // auf 50%-100% gebremst -> spürbar weniger neue Karten als die Baseline.
    expect(weakPlan.newCardBudgetByModule['m2'], lessThan(3));
  });
}
