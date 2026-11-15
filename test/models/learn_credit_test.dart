import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/learn_credit.dart';
import 'package:lernen/services/fsrs_service.dart';

void main() {
  const rules = LearnCreditRules(enabled: true);

  group('Lerntag', () {
    test('beginnt um 4:00 – vorher zählt noch der Vortag', () {
      expect(LearnCredit.dayKey(DateTime(2026, 11, 14, 3, 59), 4), '2026-11-13');
      expect(LearnCredit.dayKey(DateTime(2026, 11, 14, 4), 4), '2026-11-14');
      expect(LearnCredit.dayKey(DateTime(2026, 11, 14, 23, 30), 4), '2026-11-14');
      expect(LearnCredit.dayKey(DateTime(2026, 3, 1, 1), 4), '2026-02-28');
      expect(LearnCredit.dayStart(DateTime(2026, 11, 14, 2), 4), DateTime(2026, 11, 13, 4));
      expect(LearnCredit.dayStart(DateTime(2026, 11, 14, 9), 4), DateTime(2026, 11, 14, 4));
    });
  });

  group('fehlerfrei', () {
    test('geprüfte Aufgaben: richtig ohne Hilfe; selbst bewertet: gewusst', () {
      expect(LearnCredit.isClean(isCorrect: true, selfGrade: Grade.good), isTrue);
      expect(LearnCredit.isClean(isCorrect: true), isTrue);
      expect(LearnCredit.isClean(isCorrect: true, selfGrade: Grade.hard), isFalse, reason: 'mit Hilfe/Fehlversuch');
      expect(LearnCredit.isClean(isCorrect: false, selfGrade: Grade.good), isFalse);
      expect(LearnCredit.isClean(selfGrade: Grade.hard), isTrue);
      expect(LearnCredit.isClean(selfGrade: Grade.again), isFalse);
      expect(LearnCredit.isClean(), isFalse);
    });
  });

  group('Thema lernen', () {
    final t0 = DateTime(2026, 11, 14, 10);

    test('2 fehlerfrei hintereinander → gelernt, ein Fehler setzt zurück', () {
      var credit = const LearnCredit();
      String? learned;
      (credit, learned) = credit.withAnswer(
        topic: 'concept:dgl-trennen',
        title: 'Variablen trennen',
        clean: true,
        now: t0,
        rules: rules,
      );
      expect(learned, isNull);
      (credit, learned) = credit.withAnswer(
        topic: 'concept:dgl-trennen',
        title: 'Variablen trennen',
        clean: false,
        now: t0,
        rules: rules,
      );
      expect(learned, isNull);
      (credit, learned) = credit.withAnswer(
        topic: 'concept:dgl-trennen',
        title: 'Variablen trennen',
        clean: true,
        now: t0,
        rules: rules,
      );
      expect(learned, isNull, reason: 'nach dem Fehler beginnt die Serie neu');
      (credit, learned) = credit.withAnswer(
        topic: 'concept:dgl-trennen',
        title: 'Variablen trennen',
        clean: true,
        now: t0,
        rules: rules,
      );
      expect(learned, 'Variablen trennen');
      expect(credit.topicsOn('2026-11-14'), ['Variablen trennen']);

      // Jedes Thema zählt nur einmal.
      (credit, learned) = credit.withAnswer(
        topic: 'concept:dgl-trennen',
        title: 'Variablen trennen',
        clean: true,
        now: t0,
        rules: rules,
      );
      expect(learned, isNull);
      expect(credit.earned, hasLength(1));
    });

    test('Themen getrennt: Variablen trennen und Substitution zählen einzeln', () {
      var credit = const LearnCredit();
      for (final topic in ['a', 'b', 'a', 'b']) {
        (credit, _) = credit.withAnswer(topic: topic, title: topic.toUpperCase(), clean: true, now: t0, rules: rules);
      }
      expect(credit.topicsOn('2026-11-14'), ['A', 'B']);
    });

    test('Serien enden mit dem Lerntag', () {
      var credit = const LearnCredit();
      String? learned;
      (credit, _) = credit.withAnswer(
        topic: 'x',
        title: 'X',
        clean: true,
        now: DateTime(2026, 11, 14, 3),
        rules: rules,
      );
      (credit, learned) = credit.withAnswer(
        topic: 'x',
        title: 'X',
        clean: true,
        now: DateTime(2026, 11, 14, 5),
        rules: rules,
      );
      expect(learned, isNull, reason: 'um 4:00 begann ein neuer Lerntag');
    });

    test('Serienlänge einstellbar', () {
      final (credit, learned) = const LearnCredit().withAnswer(
        topic: 'x',
        title: 'X',
        clean: true,
        now: t0,
        rules: rules.copyWith(correctInRow: 1),
      );
      expect(learned, 'X');
      expect(credit.earned.keys, ['x']);
    });
  });

  group('Erlaubte Zeit', () {
    final now = DateTime(2026, 11, 14, 12);

    test('30 frei, +30 je Thema, unbegrenzt mit Thema und Daily Quiz', () {
      var credit = const LearnCredit();
      var a = LearnAllowance.of(credit, rules, now);
      expect(a.minutes, 30);
      expect(a.unlimited, isFalse);
      expect(a.nextStep, contains('+30 Minuten'));
      expect(a.nextStep, contains('Daily Quiz'));

      for (var i = 0; i < 2; i++) {
        (credit, _) = credit.withAnswer(topic: 'subst', title: 'Substitution', clean: true, now: now, rules: rules);
      }
      a = LearnAllowance.of(credit, rules, now);
      expect(a.minutes, 60);
      expect(a.topicsToday, ['Substitution']);
      expect(a.unlimited, isFalse, reason: 'Daily Quiz fehlt noch');

      credit = credit.withDailyDone(now, 4);
      a = LearnAllowance.of(credit, rules, now);
      expect(a.unlimited, isTrue);
      expect(a.dailyDone, isTrue);
      expect(a.nextStep, isEmpty);

      // Am nächsten Lerntag beginnt alles von vorn.
      a = LearnAllowance.of(credit, rules, DateTime(2026, 11, 15, 4, 1));
      expect(a.unlimited, isFalse);
      expect(a.minutes, 30);
    });

    test('0 Themen für unbegrenzt = nie unbegrenzt; Daily Quiz abschaltbar', () {
      var credit = const LearnCredit().withDailyDone(now, 4);
      for (var i = 0; i < 2; i++) {
        (credit, _) = credit.withAnswer(topic: 't', title: 'T', clean: true, now: now, rules: rules);
      }
      expect(LearnAllowance.of(credit, rules.copyWith(topicsForUnlimited: 0), now).unlimited, isFalse);
      final noDaily = rules.copyWith(dailyForUnlimited: false);
      expect(LearnAllowance.of(const LearnCredit(), noDaily, now).nextStep, isNot(contains('Daily Quiz')));
    });
  });

  group('Festlegung für eine Woche', () {
    final now = DateTime(2026, 11, 15, 10);
    final locked = rules.copyWith(
      packages: ['com.instagram.android', 'com.zhiliaoapp.musically'],
      topicsForUnlimited: 2,
      lockedUntil: now.add(LearnCreditRules.lockDuration),
    );

    test('solange festgelegt: nicht abschaltbar, nur strenger', () {
      expect(locked.isLocked(now), isTrue);
      final loose = LearnCreditRules(
        packages: const ['com.zhiliaoapp.musically', 'com.reddit.frontpage'],
        freeMinutes: 120,
        minutesPerTopic: 60,
        topicsForUnlimited: 1,
        dailyForUnlimited: false,
        correctInRow: 1,
        dayStartHour: 8,
        updatedAt: now,
      );
      final g = locked.guard(loose, now);
      expect(g.enabled, isTrue);
      expect(g.packages, ['com.zhiliaoapp.musically', 'com.reddit.frontpage', 'com.instagram.android']);
      expect(g.freeMinutes, 30);
      expect(g.minutesPerTopic, 30);
      expect(g.topicsForUnlimited, 2);
      expect(g.dailyForUnlimited, isTrue);
      expect(g.correctInRow, 2);
      expect(g.dayStartHour, 4);
      expect(g.lockedUntil, locked.lockedUntil, reason: 'die Festlegung bleibt');
      expect(g.updatedAt, now);

      // Strenger geht: weniger Minuten, längere Serie, nie unbegrenzt.
      final strict = locked.guard(
        locked.copyWith(freeMinutes: 10, correctInRow: 4, topicsForUnlimited: 0, minutesPerTopic: 15),
        now,
      );
      expect(strict.freeMinutes, 10);
      expect(strict.correctInRow, 4);
      expect(strict.topicsForUnlimited, 0);
      expect(strict.minutesPerTopic, 15);
      // Und von „nie“ zurück zu „unbegrenzt ab 3“ wäre lockerer.
      expect(strict.guard(strict.copyWith(topicsForUnlimited: 3), now).topicsForUnlimited, 0);

      // Verlängern geht, verkürzen nicht.
      final later = now.add(const Duration(days: 10));
      expect(locked.guard(locked.copyWith(lockedUntil: later), now).lockedUntil, later);
    });

    test('nach einer Woche wieder frei', () {
      final after = now.add(const Duration(days: 7, minutes: 1));
      expect(locked.isLocked(after), isFalse);
      expect(locked.guard(locked.copyWith(enabled: false), after).enabled, isFalse);
      expect(LearnCreditRules.fromMap(locked.toMap()).lockedUntil, locked.lockedUntil);
    });

    test('Abgleich: neuere, aber lockerere Regeln eines anderen Geräts lockern nichts', () {
      final windows = const LearnCreditRules(freeMinutes: 90).copyWith(updatedAt: now.add(const Duration(hours: 1)));
      final merged = LearnCreditRules.fromMap(
        LearnCreditRules.newer(locked.copyWith(updatedAt: now).toMap(), windows.toMap(), now: now),
      );
      expect(merged.enabled, isTrue);
      expect(merged.freeMinutes, 30);
      expect(merged.isLocked(now), isTrue);
    });
  });

  group('PC: Regeln und gemeinsames Zeitkonto', () {
    final now = DateTime(2026, 11, 18, 12);

    test('festgelegt: Webseiten und Spiele nur dazu, Ausnahmen nur weg, Spielzeit nur weniger', () {
      final locked = rules.copyWith(lockedUntil: now.add(LearnCreditRules.lockDuration));
      final g = locked.guard(
        locked.copyWith(
          pcSites: ['Twitch'],
          pcExceptions: ['YouTube Music', 'YouTube'],
          pcGames: ['Fortnite'],
          weeklyGameMinutes: 600,
          gameMinutesPerTopic: 90,
        ),
        now,
      );
      expect(g.pcSites, ['Twitch', 'YouTube', 'Instagram']);
      expect(g.pcExceptions, ['YouTube Music'], reason: 'neue Ausnahme „YouTube“ würde lockern');
      expect(g.pcGames, ['Fortnite', 'Minecraft', 'VALORANT']);
      expect(g.weeklyGameMinutes, 240);
      expect(g.gameMinutesPerTopic, 30);
      final stricter = locked.guard(locked.copyWith(pcExceptions: const [], weeklyGameMinutes: 120), now);
      expect(stricter.pcExceptions, isEmpty);
      expect(stricter.weeklyGameMinutes, 120);

      final back = LearnCreditRules.fromMap(g.toMap());
      expect(back.pcSites, g.pcSites);
      expect(back.pcGames, g.pcGames);
      expect(LearnCreditRules.fromMap(const {}).pcExceptions, ['YouTube Music', 'Minecraft Launcher']);
    });

    test('Nutzung je Gerät: zusammenführen, summieren, alte Tage fallen weg', () {
      final day = LearnCredit.dayKey(now, 4);
      final key = LearnCredit.dailyUsageKey(day);
      var phone = const LearnCredit().withUsage('handy', key, 600, now);
      phone = phone.withUsage('handy', key, 300, now);
      expect(phone.used['handy']![key], 600, reason: 'nie weniger als schon verbucht');
      phone = phone.withUsage('handy', 'd:2026-10-01', 999, now.subtract(const Duration(days: 40)));
      phone = phone.withUsage('handy', key, 660, now);
      expect(phone.used['handy']!.containsKey('d:2026-10-01'), isFalse);

      final pc = const LearnCredit()
          .withUsage('pc', key, 900, now)
          .withUsage('pc', LearnCredit.gameUsageKey(LearnCredit.weekKey(now, 4)), 3600, now);
      final merged = phone.mergedWith(LearnCredit.fromMap(pc.toSyncMap()));
      expect(merged.usedSeconds(key), 1560);
      expect(merged.usedSeconds(key, exceptDevice: 'pc'), 660);
      // Ein älterer Stand desselben Geräts senkt nichts.
      final again = merged.mergedWith(const LearnCredit().withUsage('pc', key, 100, now));
      expect(again.usedSeconds(key), 1560);
    });

    test('Spielzeit: frei pro Woche plus je in der Woche gelerntem Thema', () {
      final credit = LearnCredit(
        earned: {
          'a': EarnedTopic(day: '2026-11-16', title: 'A', at: DateTime(2026, 11, 16, 9)),
          'b': EarnedTopic(day: '2026-11-18', title: 'B', at: DateTime(2026, 11, 18, 9)),
          'c': EarnedTopic(day: '2026-11-15', title: 'C', at: DateTime(2026, 11, 15, 9)),
        },
      );
      final a = GameAllowance.of(credit, rules, now);
      expect(a.week, '2026-11-16');
      expect(a.topicsThisWeek, 2, reason: 'C war in der Vorwoche');
      expect(a.minutes, 240 + 2 * 30);
    });
  });

  group('Geräte zusammenführen', () {
    test('Themen und Daily-Tage beider Geräte zählen, das frühere gewinnt', () {
      final phone = LearnCredit(
        earned: {'a': EarnedTopic(day: '2026-11-14', title: 'A', at: DateTime(2026, 11, 14, 12))},
        dailyDays: const {'2026-11-13'},
        streaks: const {'z': 1},
        streakDay: '2026-11-14',
      );
      final windows = LearnCredit(
        earned: {
          'a': EarnedTopic(day: '2026-11-14', title: 'A', at: DateTime(2026, 11, 14, 9)),
          'b': EarnedTopic(day: '2026-11-14', title: 'B', at: DateTime(2026, 11, 14, 10)),
        },
        dailyDays: const {'2026-11-14'},
      );
      final merged = phone.mergedWith(LearnCredit.fromMap(windows.toSyncMap()));
      expect(merged.earned['a']!.at, DateTime(2026, 11, 14, 9));
      expect(merged.topicsOn('2026-11-14'), ['A', 'B']);
      expect(merged.dailyDays, {'2026-11-13', '2026-11-14'});
      expect(merged.streaks, {'z': 1}, reason: 'Serien bleiben auf dem Gerät');
      expect(windows.toSyncMap().containsKey('streaks'), isFalse);
    });

    test('Speichern und Laden', () {
      final credit = LearnCredit(
        earned: {'a': EarnedTopic(day: '2026-11-14', title: 'A', at: DateTime(2026, 11, 14, 9))},
        dailyDays: const {'2026-11-14'},
        streaks: const {'b': 1},
        streakDay: '2026-11-14',
      );
      final back = LearnCredit.fromMap(credit.toMap());
      expect(back.earned['a']!.title, 'A');
      expect(back.dailyDays, {'2026-11-14'});
      expect(back.streaks, {'b': 1});
      expect(back.streakDay, '2026-11-14');

      final r = LearnCreditRules.fromMap(
        rules.copyWith(packages: ['com.instagram.android', 'com.zhiliaoapp.musically'], freeMinutes: 15).toMap(),
      );
      expect(r.enabled, isTrue);
      expect(r.packages, hasLength(2));
      expect(r.freeMinutes, 15);
      expect(LearnCreditRules.fromMap(null).packages, ['com.instagram.android']);
      expect(LearnCreditRules.fromMap({'dayStartHour': 99}).dayStartHour, 23);
    });
  });
}
