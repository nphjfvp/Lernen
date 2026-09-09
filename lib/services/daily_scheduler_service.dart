import '../models/flashcard.dart';
import '../models/module.dart';
import 'fsrs_service.dart';

/// Der Tagesplan für das Daily Quiz: fällige Wiederholungen + eine
/// modulweise dosierte Menge neuer Karten.
class DailyPlan {
  final List<Flashcard> dueCards;
  final List<Flashcard> newCards;
  final Map<String, int> newCardBudgetByModule;

  const DailyPlan({
    required this.dueCards,
    required this.newCards,
    required this.newCardBudgetByModule,
  });

  List<Flashcard> get allCards => [...dueCards, ...newCards];
  int get total => dueCards.length + newCards.length;
}

/// Exam-Scheduler: bestimmt, wie viele fällige und neue Karten heute pro
/// Modul anstehen. Das Pensum wird an zwei Faktoren angepasst:
///  1. Wissensstand – wie gut die bisher gelernten Karten des Moduls gerade
///     sitzen (durchschnittliche FSRS-Retrievability). Schwache Module
///     bekommen weniger neue Karten, damit der Rückstand nicht wächst.
///  2. Klausurnähe – neue Karten werden so über die verbleibenden Tage bis
///     zur Klausur verteilt, dass am Ende noch ein reiner Wiederholungs-
///     Puffer übrig bleibt statt am letzten Tag noch unbekannten Stoff
///     einzuführen.
class DailySchedulerService {
  DailySchedulerService({FsrsService? fsrs}) : _fsrs = fsrs ?? FsrsService();

  final FsrsService _fsrs;

  /// Tage unmittelbar vor der Klausur, die ausschließlich der Wiederholung
  /// vorbehalten sind (keine neuen Karten mehr).
  static const int reviewBufferDays = 3;

  /// Fallback-Horizont für Module ohne Klausurdatum: neue Karten werden so
  /// verteilt, als läge die "Klausur" in dieser Anzahl Tage.
  static const int defaultPacingHorizonDays = 14;

  static const int maxNewCardsPerModulePerDay = 15;
  static const int maxSessionSize = 60;

  DailyPlan buildPlan({
    required List<Module> modules,
    required List<Flashcard> allCards,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    final endOfToday = todayDay.add(const Duration(days: 1));
    final dueCards = allCards
        .where((c) => c.reps > 0 && c.due.isBefore(endOfToday))
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    final newCardBudget = <String, int>{};
    final newCards = <Flashcard>[];

    for (final module in modules) {
      final moduleCards = allCards.where((c) => c.moduleId == module.id);
      final notIntroduced =
          moduleCards.where((c) => c.reps == 0).toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (notIntroduced.isEmpty) {
        newCardBudget[module.id] = 0;
        continue;
      }

      final reviewed = moduleCards.where((c) => c.reps > 0).toList();
      final knowledgeLevel = reviewed.isEmpty
          ? 1.0
          : reviewed
                  .map((c) => _fsrs.currentRetrievability(c, now: today))
                  .reduce((a, b) => a + b) /
              reviewed.length;

      final daysUntilExam = module.daysUntilExam;
      int introductionWindowDays;
      if (daysUntilExam == null) {
        introductionWindowDays = defaultPacingHorizonDays;
      } else if (daysUntilExam <= reviewBufferDays) {
        introductionWindowDays = 0; // reiner Wiederholungs-Endspurt
      } else {
        introductionWindowDays = daysUntilExam - reviewBufferDays;
      }

      int budget;
      if (introductionWindowDays <= 0) {
        budget = 0;
      } else {
        final basePace = (notIntroduced.length / introductionWindowDays).ceil();
        // Wissensstand 0..1 -> Tempo 50%..100%: bei Schwäche wird gebremst,
        // damit nicht noch mehr unverstandener Stoff nachgeschoben wird.
        final adjusted = (basePace * (0.5 + 0.5 * knowledgeLevel)).ceil();
        budget = adjusted.clamp(0, maxNewCardsPerModulePerDay);
      }

      newCardBudget[module.id] = budget;
      newCards.addAll(notIntroduced.take(budget));
    }

    // Fällige Wiederholungen sind zeitkritisch (sonst sinkt die
    // Erinnerungswahrscheinlichkeit weiter) und gehen daher bei Bedarf vor
    // neuen Karten, wenn die Session sonst zu groß würde.
    var trimmedNew = newCards;
    if (dueCards.length + newCards.length > maxSessionSize) {
      final remainingSlots = (maxSessionSize - dueCards.length).clamp(0, maxSessionSize);
      trimmedNew = newCards.take(remainingSlots).toList();
    }

    return DailyPlan(
      dueCards: dueCards,
      newCards: trimmedNew,
      newCardBudgetByModule: newCardBudget,
    );
  }
}
