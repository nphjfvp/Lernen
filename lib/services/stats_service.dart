import '../models/flashcard.dart';
import '../models/module.dart';
import 'fsrs_service.dart';
import 'mastery_service.dart';

/// Fortschritts-Kennzahlen für ein einzelnes Fach.
class ModuleStats {
  const ModuleStats({
    required this.module,
    required this.totalCards,
    required this.newCards,
    required this.reviewedCards,
    required this.averageRetrievability,
    required this.masteryBreakdown,
  });

  final Module module;
  final int totalCards;
  final int newCards;
  final int reviewedCards;

  /// Durchschnittliche geschätzte Erinnerungswahrscheinlichkeit (0-1) der
  /// bereits mindestens einmal wiederholten Karten dieses Fachs, oder null
  /// wenn noch keine Karte wiederholt wurde.
  final double? averageRetrievability;

  /// Ampel-Aufschlüsselung (siehe MasteryService) der Karten dieses Fachs.
  final Map<MasteryLevel, int> masteryBreakdown;
}

/// Fortschritts-Kennzahlen über alle Fächer hinweg.
class OverallStats {
  const OverallStats({
    required this.streakDays,
    required this.totalReviews,
    required this.averageRetrievability,
    required this.moduleStats,
  });

  final int streakDays;
  final int totalReviews;
  final double? averageRetrievability;
  final List<ModuleStats> moduleStats;
}

/// Berechnet Fortschritts-Kennzahlen rein aus vorhandenen Daten (Module +
/// Karteikarten) – bewusst ohne eigenes Session-Log: jede Bewertung im
/// Daily Quiz aktualisiert bereits `Flashcard.lastReview`, das reicht als
/// Grundlage für Streak/Retention, ohne einen zusätzlichen Datenspeicher.
class StatsService {
  StatsService({FsrsService? fsrs, MasteryService? mastery})
      : _fsrs = fsrs ?? FsrsService(),
        _mastery = mastery ?? MasteryService();

  final FsrsService _fsrs;
  final MasteryService _mastery;

  OverallStats compute({
    required List<Module> modules,
    required List<Flashcard> allCards,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();

    final streak = _computeStreak(allCards, today);
    final totalReviews = allCards.fold<int>(0, (sum, c) => sum + c.reps);
    final overallAverage = _averageRetrievability(allCards, today);

    final moduleStats = modules
        .map((m) => _computeModuleStats(m, allCards.where((c) => c.moduleId == m.id).toList(), today))
        .toList();

    return OverallStats(
      streakDays: streak,
      totalReviews: totalReviews,
      averageRetrievability: overallAverage,
      moduleStats: moduleStats,
    );
  }

  ModuleStats _computeModuleStats(Module module, List<Flashcard> cards, DateTime today) {
    return ModuleStats(
      module: module,
      totalCards: cards.length,
      newCards: cards.where((c) => c.reps == 0).length,
      reviewedCards: cards.where((c) => c.reps > 0).length,
      averageRetrievability: _averageRetrievability(cards, today),
      masteryBreakdown: _mastery.breakdown(cards, now: today),
    );
  }

  double? _averageRetrievability(List<Flashcard> cards, DateTime today) {
    final reviewed = cards.where((c) => c.reps > 0).toList();
    if (reviewed.isEmpty) return null;
    final sum = reviewed.fold<double>(0, (acc, c) => acc + _fsrs.currentRetrievability(c, now: today));
    return sum / reviewed.length;
  }

  /// Anzahl aufeinanderfolgender Tage (bis inkl. heute ODER gestern, falls
  /// heute noch nicht gelernt wurde) mit mindestens einer Karteikarten-
  /// Wiederholung. Ein noch nicht begonnener heutiger Tag zählt nicht als
  /// gerissener Streak - der bleibt bestehen, bis der Tag vorbei ist.
  int _computeStreak(List<Flashcard> allCards, DateTime today) {
    final reviewDays = <DateTime>{};
    for (final card in allCards) {
      final lr = card.lastReview;
      if (lr != null) reviewDays.add(DateTime(lr.year, lr.month, lr.day));
    }

    final todayDate = DateTime(today.year, today.month, today.day);
    var cursor = reviewDays.contains(todayDate) ? todayDate : todayDate.subtract(const Duration(days: 1));
    var streak = 0;
    while (reviewDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
