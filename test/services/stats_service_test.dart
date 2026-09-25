import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/stats_service.dart';

Module _module(String id, {String name = 'Fach'}) => Module(
      id: id,
      name: name,
      colorValue: 0xFF000000,
      icon: '📘',
      examDate: null,
      createdAt: DateTime(2026, 1, 1),
    );

Flashcard _card({
  required String moduleId,
  int reps = 0,
  DateTime? lastReview,
  double stability = 5,
}) {
  return Flashcard(
    id: '${moduleId}_${lastReview?.toIso8601String()}_$reps${stability}_${DateTime.now().microsecondsSinceEpoch}',
    moduleId: moduleId,
    front: 'F',
    back: 'B',
    createdAt: DateTime(2026, 1, 1),
    due: DateTime(2026, 1, 2),
    reps: reps,
    stability: stability,
    lastReview: lastReview,
  );
}

void main() {
  final today = DateTime(2026, 3, 10);

  group('StatsService – Streak', () {
    test('0 Tage Streak ohne jede Wiederholung', () {
      final stats = StatsService().compute(modules: [], allCards: [], now: today);
      expect(stats.streakDays, 0);
    });

    test('zählt aufeinanderfolgende Tage inkl. heute', () {
      final cards = [
        _card(moduleId: 'm1', reps: 1, lastReview: today),
        _card(moduleId: 'm1', reps: 1, lastReview: today.subtract(const Duration(days: 1))),
        _card(moduleId: 'm1', reps: 1, lastReview: today.subtract(const Duration(days: 2))),
      ];
      final stats = StatsService().compute(modules: [], allCards: cards, now: today);
      expect(stats.streakDays, 3);
    });

    test('Streak bleibt bestehen, wenn heute noch nicht gelernt wurde, aber gestern schon', () {
      final cards = [
        _card(moduleId: 'm1', reps: 1, lastReview: today.subtract(const Duration(days: 1))),
        _card(moduleId: 'm1', reps: 1, lastReview: today.subtract(const Duration(days: 2))),
      ];
      final stats = StatsService().compute(modules: [], allCards: cards, now: today);
      expect(stats.streakDays, 2);
    });

    test('Streak ist 0, wenn eine Lücke besteht (weder heute noch gestern gelernt)', () {
      final cards = [
        _card(moduleId: 'm1', reps: 1, lastReview: today.subtract(const Duration(days: 3))),
      ];
      final stats = StatsService().compute(modules: [], allCards: cards, now: today);
      expect(stats.streakDays, 0);
    });

    test('protokollierte Lerntage zählen mit, auch wenn deren Karten inzwischen erneut wiederholt wurden', () {
      // Alle Karten wurden heute zuletzt wiederholt – ihr lastReview kennt
      // die Vortage nicht mehr, das Lerntage-Protokoll schon.
      final cards = [_card(moduleId: 'm1', reps: 3, lastReview: today)];
      final stats = StatsService().compute(
        modules: [],
        allCards: cards,
        studyDays: {
          today.subtract(const Duration(days: 1)),
          DateTime(today.year, today.month, today.day - 2, 18, 30),
        },
        now: today,
      );
      expect(stats.streakDays, 3);
    });

    test('mehrere Karten am selben Tag zählen nur als ein Streak-Tag', () {
      final cards = [
        _card(moduleId: 'm1', reps: 1, lastReview: today),
        _card(moduleId: 'm2', reps: 1, lastReview: today),
      ];
      final stats = StatsService().compute(modules: [], allCards: cards, now: today);
      expect(stats.streakDays, 1);
    });
  });

  group('StatsService – totalReviews', () {
    test('summiert reps über alle Karten hinweg', () {
      final cards = [
        _card(moduleId: 'm1', reps: 3),
        _card(moduleId: 'm2', reps: 5),
      ];
      final stats = StatsService().compute(modules: [], allCards: cards, now: today);
      expect(stats.totalReviews, 8);
    });
  });

  group('StatsService – averageRetrievability', () {
    test('ist null, wenn keine Karte je wiederholt wurde', () {
      final cards = [_card(moduleId: 'm1', reps: 0)];
      final stats = StatsService().compute(modules: [], allCards: cards, now: today);
      expect(stats.averageRetrievability, isNull);
    });

    test('ist nicht-null und zwischen 0 und 1, wenn Karten wiederholt wurden', () {
      final cards = [
        _card(moduleId: 'm1', reps: 2, lastReview: today.subtract(const Duration(days: 1)), stability: 10),
      ];
      final stats = StatsService().compute(modules: [], allCards: cards, now: today);
      expect(stats.averageRetrievability, isNotNull);
      expect(stats.averageRetrievability, greaterThan(0));
      expect(stats.averageRetrievability, lessThanOrEqualTo(1));
    });
  });

  group('StatsService – moduleStats', () {
    test('gruppiert Karten korrekt nach Fach und zählt neu/wiederholt getrennt', () {
      final modules = [_module('m1'), _module('m2')];
      final cards = [
        _card(moduleId: 'm1', reps: 0),
        _card(moduleId: 'm1', reps: 2, lastReview: today),
        _card(moduleId: 'm2', reps: 0),
      ];
      final stats = StatsService().compute(modules: modules, allCards: cards, now: today);

      final m1 = stats.moduleStats.firstWhere((s) => s.module.id == 'm1');
      final m2 = stats.moduleStats.firstWhere((s) => s.module.id == 'm2');

      expect(m1.totalCards, 2);
      expect(m1.newCards, 1);
      expect(m1.reviewedCards, 1);
      expect(m1.averageRetrievability, isNotNull);

      expect(m2.totalCards, 1);
      expect(m2.newCards, 1);
      expect(m2.reviewedCards, 0);
      expect(m2.averageRetrievability, isNull);
    });

    test('ein Fach ohne Karten hat totalCards 0 und averageRetrievability null', () {
      final modules = [_module('empty')];
      final stats = StatsService().compute(modules: modules, allCards: [], now: today);
      final s = stats.moduleStats.single;
      expect(s.totalCards, 0);
      expect(s.averageRetrievability, isNull);
    });
  });
}
