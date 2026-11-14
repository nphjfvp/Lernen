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
