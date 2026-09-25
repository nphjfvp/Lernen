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

  /// Session-Reihenfolge: fällige und neue Karten zusammengeführt und über
  /// [DailySchedulerService.interleaveByModule] fachübergreifend durchmischt
  /// (Interleaving statt Blockübung) statt strikt "erst alle Fälligen eines
  /// Fachs, dann die des nächsten". Beeinflusst nur die Reihenfolge INNERHALB
  /// der heutigen Session, nicht welche Karten überhaupt eingeplant sind.
  List<Flashcard> get allCards => DailySchedulerService.interleaveByModule([...dueCards, ...newCards]);
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

  /// Mindest-Boden für das Tagesbudget, solange rückständige ("notIntroduced")
  /// Karten vorhanden sind: die Klausurnähe-/Wissensstand-Pacing-Formel darf
  /// das Budget bei fernem Klausurdatum (z.B. Semesterbeginn) nicht unter
  /// diesen Wert drücken, sonst dauert es bei z.B. 90 Tagen bis zur Klausur
  /// und 20 neuen Karten gefühlt ewig, bis überhaupt neuer Stoff auftaucht.
  /// Greift NICHT im reinen Wiederholungs-Endspurt kurz vor der Klausur
  /// (dort ist `budget = 0` weiterhin bewusst gewollt, siehe unten).
  static const int minDailyNewCardsPerModule = 10;

  /// Mischt Karten aus verschiedenen Fächern per Round-Robin durch
  /// (Interleaving statt Blockübung, siehe Rohrer & Taylor 2007: Durchmischen
  /// unterschiedlicher Themen/Konzepte verbessert nachweislich die
  /// Unterscheidungsfähigkeit gegenüber reiner Blockübung eines einzelnen
  /// Themas). Die Reihenfolge INNERHALB eines Fachs (z.B. schon nach
  /// Fälligkeits-Priorität sortiert) bleibt dabei erhalten – nur ZWISCHEN
  /// den Fächern wird durchmischt. Fach-Reihenfolge = Reihenfolge des
  /// ersten Vorkommens in [cards] (deterministisch, kein Zufall nötig).
  static List<Flashcard> interleaveByModule(List<Flashcard> cards) {
    if (cards.isEmpty) return const [];
    final byModule = <String, List<Flashcard>>{};
    final moduleOrder = <String>[];
    for (final card in cards) {
      final list = byModule.putIfAbsent(card.moduleId, () {
        moduleOrder.add(card.moduleId);
        return [];
      });
      list.add(card);
    }
    final result = <Flashcard>[];
    var index = 0;
    while (result.length < cards.length) {
      for (final moduleId in moduleOrder) {
        final list = byModule[moduleId]!;
        if (index < list.length) result.add(list[index]);
      }
      index++;
    }
    return result;
  }

  /// [unitCoveredById] ordnet jede Vorlesungseinheit (LectureUnit.id) ihrem
  /// "behandelt"-Status zu. Eine Karte mit gesetzter [Flashcard.unitId]
  /// wird NUR eingeplant, wenn diese Einheit als behandelt markiert ist –
  /// so kann man ruhig den ganzen Semesterstoff im Voraus hochladen, ohne
  /// dass das Daily Quiz schon Karten aus zukünftigen Einheiten abfragt.
  /// Karten ohne Einheit (`unitId == null`, z.B. älterer Stand vor
  /// Einführung der Einheiten) bleiben wie bisher immer eingeplant. Fehlt
  /// eine Einheit-ID in der Map (z.B. Dateninkonsistenz), wird die Karte im
  /// Zweifel eingeplant statt sie stillschweigend zu verstecken.
  ///
  /// [introducedTodayByModule]: wie viele neue Karten je Fach heute schon im
  /// Daily Quiz eingeführt wurden (siehe DailySessionState) – wird vom
  /// Tagesbudget abgezogen, damit "Aktualisieren" nach einer fertigen
  /// Session oder ein App-Neustart nicht ein zweites volles Budget vergibt.
  /// Gezielt selbst erstellte Fragen ([Flashcard.priorityIntroduction])
  /// kommen trotzdem immer noch heute dran.
  DailyPlan buildPlan({
    required List<Module> modules,
    required List<Flashcard> allCards,
    Map<String, bool> unitCoveredById = const {},
    Map<String, int> introducedTodayByModule = const {},
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    bool isEligible(Flashcard c) {
      final unitId = c.unitId;
      if (unitId == null || c.priorityIntroduction) return true;
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
      final notIntroduced = moduleCards.where((c) => c.reps == 0).toList()
        ..sort((a, b) {
          // Gezielt JETZT selbst erstellte Fragen (siehe Flashcard.
          // priorityIntroduction) sollen nicht hinter einem großen, rein
          // chronologisch älteren Altbestand verschwinden.
          if (a.priorityIntroduction != b.priorityIntroduction) {
            return a.priorityIntroduction ? -1 : 1;
          }
          return a.createdAt.compareTo(b.createdAt);
        });
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
        final paced = adjusted.clamp(0, maxNewCardsPerModulePerDay);
        // Mindest-Boden statt reiner Pacing-Formel: bei fernem Klausurdatum
        // (z.B. Semesterbeginn) würde die Formel sonst auf ~1 Karte/Tag
        // einfrieren, obwohl reichlich Rückstand vorhanden ist.
        final floor = notIntroduced.length.clamp(0, minDailyNewCardsPerModule);
        budget = (paced < floor ? floor : paced).clamp(0, maxNewCardsPerModulePerDay);
      }

      newCardBudget[module.id] = budget;
      final remaining = budget - (introducedTodayByModule[module.id] ?? 0);
      final priority = notIntroduced.where((c) => c.priorityIntroduction).toList();
      final regularSlots = remaining - priority.length;
      newCards
        ..addAll(priority)
        ..addAll(notIntroduced.where((c) => !c.priorityIntroduction).take(regularSlots < 0 ? 0 : regularSlots));
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

  /// Rein FREIWILLIGE Zusatz-Charge über das Tagesbudget hinaus – für den
  /// "Trotzdem weiterlernen"-Button, nachdem der reguläre Tagesplan bereits
  /// abgeschlossen ist (siehe DailyQuizScreen). Ignoriert bewusst die
  /// Klausurnähe-/Wissensstand-Pacing-Formel aus [buildPlan] (die gilt nur
  /// für das REGULÄRE Tagesbudget) und mischt bei Bedarf noch nicht fällige,
  /// aber grundsätzlich eingeplante Wiederholungen mit ein, damit
  /// "weiterlernen" auch dann etwas anzubieten hat, wenn für heute bereits
  /// alle neuen Karten eingeführt wurden. [excludeIds] verhindert
  /// Überschneidungen mit bereits in der laufenden Session gezeigten Karten.
  DailyPlan buildExtraBatch({
    required List<Module> modules,
    required List<Flashcard> allCards,
    required Set<String> excludeIds,
    Map<String, bool> unitCoveredById = const {},
    DateTime? now,
    int batchSize = 10,
  }) {
    bool isEligible(Flashcard c) {
      final unitId = c.unitId;
      if (unitId == null || c.priorityIntroduction) return true;
      return unitCoveredById[unitId] ?? true;
    }

    final eligibleCards =
        allCards.where(isEligible).where((c) => !excludeIds.contains(c.id)).toList();

    final freshNew = eligibleCards.where((c) => c.reps == 0).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final newCards = freshNew.take(batchSize).toList();

    final remainingSlots = batchSize - newCards.length;
    var dueCards = <Flashcard>[];
    if (remainingSlots > 0) {
      dueCards = eligibleCards.where((c) => c.reps > 0).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
      dueCards = dueCards.take(remainingSlots).toList();
    }

    return DailyPlan(dueCards: dueCards, newCards: newCards, newCardBudgetByModule: const {});
  }
}
