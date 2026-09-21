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

Flashcard _newFlashcard(
  String id,
  String moduleId, {
  DateTime? createdAt,
  String? unitId,
  bool priorityIntroduction = false,
}) =>
    Flashcard(
      id: id,
      moduleId: moduleId,
      front: 'F$id',
      back: 'B$id',
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
    );

Flashcard _dueFlashcard(String id, String moduleId, DateTime due, {String? unitId}) => Flashcard(
      id: id,
      moduleId: moduleId,
      front: 'F$id',
      back: 'B$id',
      createdAt: DateTime(2026, 1, 1),
      due: due,
      reps: 3,
      stability: 5,
      lastReview: due.subtract(const Duration(days: 5)),
      unitId: unitId,
    );

void main() {
  final scheduler = DailySchedulerService();
  final now = DateTime(2026, 6, 1);

  test('Modul ohne Klausurdatum verteilt neue Karten über den Standard-Horizont', () {
    final module = _module('m1');
    final cards = List.generate(28, (i) => _newFlashcard('n$i', 'm1'));

    final plan = scheduler.buildPlan(modules: [module], allCards: cards, now: now);

    // 28 Karten / 14 Tage Standard-Horizont, volles Wissen (keine bisherigen
    // Reviews) => voller Takt = ceil(28/14) = 2 – liegt aber unter dem
    // Mindestbudget-Boden (minDailyNewCardsPerModule = 10), der bei
    // vorhandenem Rückstand IMMER greift, damit eine Session trotz fernem
    // Standard-Horizont nicht auf 1-2 Karten/Tag einfriert.
    expect(plan.newCardBudgetByModule['m1'], DailySchedulerService.minDailyNewCardsPerModule);
    expect(plan.newCards.length, DailySchedulerService.minDailyNewCardsPerModule);
  });

  test('reicht der Rückstand über den Mindestboden hinaus, greift wieder die reine Pacing-Formel', () {
    final module = _module('m1');
    // 154 Karten / 14 Tage Standard-Horizont => ceil(154/14) = 11, klar über
    // dem Mindestboden von 10 – hier soll also die Formel selbst zählen,
    // nicht der Boden.
    final cards = List.generate(154, (i) => _newFlashcard('n$i', 'm1'));

    final plan = scheduler.buildPlan(modules: [module], allCards: cards, now: now);

    expect(plan.newCardBudgetByModule['m1'], 11);
  });

  test('Klausurdatum in der Vergangenheit bremst neue Karten nicht dauerhaft ein', () {
    // Regression: ohne Fallback bliebe introductionWindowDays für ein
    // abgelaufenes Klausurdatum für immer bei 0 -> das Daily Quiz würde nie
    // wieder neue Karten dieses Moduls einplanen.
    final module = _module('m1', examDate: now.subtract(const Duration(days: 30)));
    final cards = List.generate(28, (i) => _newFlashcard('n$i', 'm1'));

    final plan = scheduler.buildPlan(modules: [module], allCards: cards, now: now);

    expect(plan.newCardBudgetByModule['m1'], DailySchedulerService.minDailyNewCardsPerModule);
    expect(plan.newCards.length, DailySchedulerService.minDailyNewCardsPerModule);
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
    // 154 neue Karten / 14 Tage Standard-Horizont => Basis-Takt ceil(154/14)
    // = 11 – bewusst über dem Mindestbudget-Boden (10), sonst würde dieser
    // die Wissensstand-Bremse für beide Fälle gleichermaßen überdecken.
    final newCards = List.generate(154, (i) => _newFlashcard('n$i', 'm2'));

    final baselinePlan = scheduler.buildPlan(modules: [module], allCards: newCards, now: now2);
    expect(baselinePlan.newCardBudgetByModule['m2'], 11,
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
    expect(weakPlan.newCardBudgetByModule['m2'], lessThan(baselinePlan.newCardBudgetByModule['m2']!));
  });

  group('unitCoveredById – Einheiten-Gate', () {
    test('Karten ohne unitId bleiben immer eingeplant, unabhängig von unitCoveredById', () {
      final module = _module('m1');
      final due = _dueFlashcard('d1', 'm1', now.subtract(const Duration(days: 1)));

      final plan = scheduler.buildPlan(
        modules: [module],
        allCards: [due],
        unitCoveredById: const {'irgendeine-andere-einheit': false},
        now: now,
      );

      expect(plan.dueCards.map((c) => c.id), contains('d1'));
    });

    test('fällige Karte einer NICHT behandelten Einheit wird nicht eingeplant', () {
      final module = _module('m1');
      final due = _dueFlashcard('d1', 'm1', now.subtract(const Duration(days: 1)), unitId: 'u1');

      final plan = scheduler.buildPlan(
        modules: [module],
        allCards: [due],
        unitCoveredById: const {'u1': false},
        now: now,
      );

      expect(plan.dueCards, isEmpty);
    });

    test('fällige Karte einer behandelten Einheit wird eingeplant', () {
      final module = _module('m1');
      final due = _dueFlashcard('d1', 'm1', now.subtract(const Duration(days: 1)), unitId: 'u1');

      final plan = scheduler.buildPlan(
        modules: [module],
        allCards: [due],
        unitCoveredById: const {'u1': true},
        now: now,
      );

      expect(plan.dueCards.map((c) => c.id), contains('d1'));
    });

    test('neue Karten aus nicht behandelter Einheit zählen nicht ins Budget/die Auswahl', () {
      final module = _module('m1');
      final coveredCards = List.generate(5, (i) => _newFlashcard('c$i', 'm1', unitId: 'u1'));
      final uncoveredCards = List.generate(20, (i) => _newFlashcard('n$i', 'm1', unitId: 'u2'));

      final plan = scheduler.buildPlan(
        modules: [module],
        allCards: [...coveredCards, ...uncoveredCards],
        unitCoveredById: const {'u1': true, 'u2': false},
        now: now,
      );

      expect(plan.newCards.every((c) => c.unitId != 'u2'), isTrue);
      // 5 Karten / 14 Tage Standard-Horizont => ceil(5/14) = 1, liegt aber
      // unter dem Mindestbudget-Boden – der greift hier nur bis zur Anzahl
      // tatsächlich vorhandener (behandelter) Karten, also 5 statt 10.
      expect(plan.newCardBudgetByModule['m1'], 5);
    });

    test('fehlt eine Einheit-ID in der Map, bleibt die Karte im Zweifel eingeplant', () {
      final module = _module('m1');
      final due = _dueFlashcard('d1', 'm1', now.subtract(const Duration(days: 1)), unitId: 'u-unbekannt');

      final plan = scheduler.buildPlan(
        modules: [module],
        allCards: [due],
        now: now,
      );

      expect(plan.dueCards.map((c) => c.id), contains('d1'));
    });

    test('priorityIntroduction umgeht das Gate auch bei nicht behandelter Einheit', () {
      final module = _module('m1');
      final card = _newFlashcard('n1', 'm1', unitId: 'u1', priorityIntroduction: true);

      final plan = scheduler.buildPlan(
        modules: [module],
        allCards: [card],
        unitCoveredById: const {'u1': false},
        now: now,
      );

      expect(plan.newCards.map((c) => c.id), contains('n1'));
    });
  });

  group('priorityIntroduction – Vorrang vor Altbestand', () {
    test('eine gerade erstellte priorisierte Karte kommt vor älteren, nicht priorisierten Karten dran', () {
      final module = _module('m1');
      // 20 ältere, nicht priorisierte Karten (Altbestand) + 1 ganz frisch
      // erstellte, priorisierte Karte – trotz neuestem createdAt soll sie
      // NICHT hinter dem Budget-Limit verschwinden.
      final backlog = List.generate(
        20,
        (i) => _newFlashcard('old$i', 'm1', createdAt: DateTime(2026, 1, 1 + i)),
      );
      final justCreated = _newFlashcard(
        'fresh',
        'm1',
        createdAt: DateTime(2026, 6, 1),
        priorityIntroduction: true,
      );

      final plan = scheduler.buildPlan(
        modules: [module],
        allCards: [...backlog, justCreated],
        now: now,
      );

      expect(plan.newCards.first.id, 'fresh');
      expect(plan.newCards.map((c) => c.id), contains('fresh'));
    });
  });

  group('DailySchedulerService.interleaveByModule – Interleaving statt Blockübung', () {
    test('mischt zwei Fächer per Round-Robin durch', () {
      final cards = [
        _newFlashcard('a1', 'A'),
        _newFlashcard('a2', 'A'),
        _newFlashcard('a3', 'A'),
        _newFlashcard('b1', 'B'),
        _newFlashcard('b2', 'B'),
      ];
      final interleaved = DailySchedulerService.interleaveByModule(cards);
      expect(interleaved.map((c) => c.id).toList(), ['a1', 'b1', 'a2', 'b2', 'a3']);
    });

    test('behält die Reihenfolge INNERHALB eines Fachs bei', () {
      final cards = [
        _dueFlashcard('a-spaet', 'A', now),
        _dueFlashcard('a-frueh', 'A', now.subtract(const Duration(days: 2))),
        _newFlashcard('b1', 'B'),
      ];
      // Reihenfolge wie übergeben (hier bewusst NICHT nach Fälligkeit
      // vorsortiert) - interleaveByModule sortiert nicht selbst um,
      // sondern übernimmt genau die Fach-interne Reihenfolge des Aufrufers.
      final interleaved = DailySchedulerService.interleaveByModule(cards);
      final aOrder = interleaved.where((c) => c.moduleId == 'A').map((c) => c.id).toList();
      expect(aOrder, ['a-spaet', 'a-frueh']);
    });

    test('ein einzelnes Fach bleibt unverändert', () {
      final cards = List.generate(4, (i) => _newFlashcard('c$i', 'A'));
      expect(DailySchedulerService.interleaveByModule(cards).map((c) => c.id).toList(),
          cards.map((c) => c.id).toList());
    });

    test('leere Liste bleibt leer', () {
      expect(DailySchedulerService.interleaveByModule(const []), isEmpty);
    });

    test('DailyPlan.allCards liefert alle Karten durchmischt, ohne welche zu verlieren', () {
      final plan = DailyPlan(
        dueCards: [
          _dueFlashcard('a1', 'A', now),
          _dueFlashcard('b1', 'B', now),
        ],
        newCards: [_newFlashcard('a2', 'A'), _newFlashcard('b2', 'B')],
        newCardBudgetByModule: const {},
      );
      expect(plan.allCards.map((c) => c.id).toSet(), {'a1', 'b1', 'a2', 'b2'});
      expect(plan.allCards.length, plan.total);
    });
  });

  group('DailySchedulerService.buildExtraBatch – freiwillige Zusatzrunde', () {
    test('ignoriert das Klausur-Pacing-Budget und liefert trotzdem neue Karten', () {
      // Klausur weit in der Zukunft => reguläres buildPlan würde hier nur den
      // Mindestboden (10) einplanen, obwohl 30 Karten rückständig sind.
      final module = _module('m1', examDate: DateTime(2027, 1, 1));
      final cards = List.generate(30, (i) => _newFlashcard('n$i', 'm1', createdAt: DateTime(2026, 1, 1 + i)));

      final extra = scheduler.buildExtraBatch(
        modules: [module],
        allCards: cards,
        excludeIds: const {},
        now: now,
      );

      expect(extra.newCards.length, 10); // Standard-batchSize
      // Älteste (zuerst erstellte) Karten zuerst, wie beim regulären Budget.
      expect(extra.newCards.first.id, 'n0');
    });

    test('excludeIds verhindert Überschneidungen mit der laufenden Session', () {
      final module = _module('m1');
      final cards = List.generate(5, (i) => _newFlashcard('n$i', 'm1', createdAt: DateTime(2026, 1, 1 + i)));

      final extra = scheduler.buildExtraBatch(
        modules: [module],
        allCards: cards,
        excludeIds: {'n0', 'n1'},
        now: now,
      );

      expect(extra.newCards.map((c) => c.id), ['n2', 'n3', 'n4']);
    });

    test('füllt mit noch nicht fälligen Wiederholungen auf, wenn keine neuen Karten mehr da sind', () {
      final module = _module('m1');
      final dueCards = [
        _dueFlashcard('d1', 'm1', now.add(const Duration(days: 3))),
        _dueFlashcard('d2', 'm1', now.add(const Duration(days: 1))),
      ];

      final extra = scheduler.buildExtraBatch(
        modules: [module],
        allCards: dueCards,
        excludeIds: const {},
        now: now,
      );

      expect(extra.newCards, isEmpty);
      // Nächstfällige zuerst.
      expect(extra.dueCards.map((c) => c.id), ['d2', 'd1']);
    });

    test('respektiert unitCoveredById genau wie das reguläre Budget', () {
      final module = _module('m1');
      final cards = [
        _newFlashcard('covered', 'm1', unitId: 'u1'),
        _newFlashcard('notCovered', 'm1', unitId: 'u2'),
      ];

      final extra = scheduler.buildExtraBatch(
        modules: [module],
        allCards: cards,
        excludeIds: const {},
        unitCoveredById: const {'u1': true, 'u2': false},
        now: now,
      );

      expect(extra.newCards.map((c) => c.id), ['covered']);
    });

    test('liefert eine leere Charge, wenn nichts mehr verfügbar ist', () {
      final module = _module('m1');
      final extra = scheduler.buildExtraBatch(modules: [module], allCards: const [], excludeIds: const {}, now: now);
      expect(extra.total, 0);
    });
  });
}
