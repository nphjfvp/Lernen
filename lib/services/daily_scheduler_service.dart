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

  /// [unitCoveredById] ordnet jede Vorlesungseinheit (LectureUnit.id) ihrem
  /// "behandelt"-Status zu. Eine Karte mit gesetzter [Flashcard.unitId]
  /// wird NUR eingeplant, wenn diese Einheit als behandelt markiert ist –
  /// so kann man ruhig den ganzen Semesterstoff im Voraus hochladen, ohne
  /// dass das Daily Quiz schon Karten aus zukünftigen Einheiten abfragt.
  /// Karten ohne Einheit (`unitId == null`, z.B. älterer Stand vor
  /// Einführung der Einheiten) bleiben wie bisher immer eingeplant. Fehlt
  /// eine Einheit-ID in der Map (z.B. Dateninkonsistenz), wird die Karte im
  /// Zweifel eingeplant statt sie stillschweigend zu verstecken.
  DailyPlan buildPlan({
    required List<Module> modules,
    required List<Flashcard> allCards,
    Map<String, bool> unitCoveredById = const {},
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    bool isEligible(Flashcard c) {
      final unitId = c.unitId;
      if (unitId == null) return true;
      return unitCoveredById[unitId] ?? true;
    }

    final eligibleCards = allCards.where(isEligible).toList();

    final endOfToday = todayDay.add(const Duration(days: 1));
    final dueCards = eligibleCards
        .where((c) => c.reps > 0 && c.due.isBefore(endOfToday))
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    final newCardBudget = <String, int>{};
    final newCards = <Flashcard>[];

    for (final module in modules) {
      final moduleCards = eligibleCards.where((c) => c.moduleId == module.id);
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

      // Bewusst relativ zu [todayDay] (dem ggf. für Tests injizierten `now`)
      // statt module.daysUntilExam zu nutzen: dieses rechnet immer gegen die
      // echte Systemzeit, was Tests mit simuliertem Datum unzuverlässig
      // machen würde.
      final examDate = module.examDate;
      final daysUntilExam = examDate == null
          ? null
          : DateTime(examDate.year, examDate.month, examDate.day).difference(todayDay).inDays;
      int introductionWindowDays;
      if (daysUntilExam == null || daysUntilExam < 0) {
        // Kein Klausurdatum ODER die Klausur liegt bereits in der
        // Vergangenheit (z.B. Testdatum, oder schlicht vergessen zu
        // aktualisieren): ohne diesen Fallback würde `budget` unten für
        // IMMER bei 0 einfrieren – die Klausurnähe-Logik ist nur für eine
        // TATSÄCHLICH bevorstehende Klausur sinnvoll, nicht als dauerhafte
        // Bremse nach ihr.
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
