import 'dart:math';

/// Fortschritt des heutigen Daily Quiz – damit ein App-Neustart (oder
/// "Aktualisieren") mitten am Tag nicht wieder bei Null anfängt: die
/// Wiederholungsrunde für falsch beantwortete Karten bleibt erhalten, der
/// Zähler "X Karten wiederholt" läuft weiter, und bereits eingeführte neue
/// Karten zählen weiter gegen das Tagesbudget (siehe
/// DailySchedulerService.buildPlan). Gilt nur für [day] – an einem neuen
/// Tag beginnt ein leerer Stand.
class DailySessionState {
  const DailySessionState({
    required this.day,
    this.reviewedCount = 0,
    this.introducedIds = const {},
    this.wrongIds = const [],
    this.wrongAttempts = const {},
    this.missedIds = const [],
    this.lessonsDone = false,
  });

  factory DailySessionState.empty(DateTime now) => DailySessionState(day: dayOf(now));

  /// Kalendertag (ohne Uhrzeit), für den dieser Stand gilt.
  final DateTime day;
  final int reviewedCount;

  /// Heute im Daily Quiz zum ersten Mal beantwortete (neue) Karten.
  final Set<String> introducedIds;

  /// Wiederholungsrunde in Reihenfolge (erstes Element kommt als Nächstes).
  final List<String> wrongIds;

  /// Wie oft eine Karte in der Wiederholungsrunde schon drankam.
  final Map<String, int> wrongAttempts;

  /// Heute mindestens einmal falsch beantwortete Karten (in Reihenfolge) –
  /// Grundlage für die Lerneinheiten nach dem Daily Quiz.
  final List<String> missedIds;

  /// Die Lerneinheiten nach dem Daily Quiz sind für heute erledigt
  /// (durchgegangen oder abgelehnt) – das Angebot erscheint nicht erneut.
  final bool lessonsDone;

  static DateTime dayOf(DateTime when) => DateTime(when.year, when.month, when.day);

  bool isFor(DateTime when) => day == dayOf(when);

  /// Neue Karten je Fach, die heute schon eingeführt wurden – für
  /// DailySchedulerService.buildPlan. [moduleIdByCardId] löst die IDs auf;
  /// inzwischen gelöschte Karten zählen nicht mehr.
  Map<String, int> introducedByModule(Map<String, String> moduleIdByCardId) {
    final counts = <String, int>{};
    for (final id in introducedIds) {
      final moduleId = moduleIdByCardId[id];
      if (moduleId != null) counts[moduleId] = (counts[moduleId] ?? 0) + 1;
    }
    return counts;
  }

  /// Führt den Stand eines anderen Geräts vom selben Tag ein (Cloud-Sync):
  /// dort eingeführte neue Karten zählen auch hier gegen das Tagesbudget –
  /// sonst gäbe es mit zwei Geräten doppelt so viele neue Karten am Tag. Ein
  /// Stand von einem anderen Tag ändert nichts.
  DailySessionState mergedWith(DailySessionState other) {
    if (other.day != day) return this;
    return DailySessionState(
      day: day,
      reviewedCount: max(reviewedCount, other.reviewedCount),
      introducedIds: {...introducedIds, ...other.introducedIds},
      wrongIds: [...wrongIds, ...other.wrongIds.where((id) => !wrongIds.contains(id))],
      wrongAttempts: {
        ...other.wrongAttempts,
        for (final e in wrongAttempts.entries) e.key: max(e.value, other.wrongAttempts[e.key] ?? 0),
      },
      missedIds: [...missedIds, ...other.missedIds.where((id) => !missedIds.contains(id))],
      lessonsDone: lessonsDone || other.lessonsDone,
    );
  }

  DailySessionState copyWith({
    int? reviewedCount,
    Set<String>? introducedIds,
    List<String>? wrongIds,
    Map<String, int>? wrongAttempts,
    List<String>? missedIds,
    bool? lessonsDone,
  }) {
    return DailySessionState(
      day: day,
      reviewedCount: reviewedCount ?? this.reviewedCount,
      introducedIds: introducedIds ?? this.introducedIds,
      wrongIds: wrongIds ?? this.wrongIds,
      wrongAttempts: wrongAttempts ?? this.wrongAttempts,
      missedIds: missedIds ?? this.missedIds,
      lessonsDone: lessonsDone ?? this.lessonsDone,
    );
  }

  Map<String, dynamic> toMap() => {
        'day': day.toIso8601String(),
        'reviewedCount': reviewedCount,
        'introducedIds': introducedIds.toList(),
        'wrongIds': wrongIds,
        'wrongAttempts': wrongAttempts,
        if (missedIds.isNotEmpty) 'missedIds': missedIds,
        if (lessonsDone) 'lessonsDone': true,
      };

  factory DailySessionState.fromMap(Map<String, dynamic> map) => DailySessionState(
        day: dayOf(DateTime.tryParse(map['day']?.toString() ?? '') ?? DateTime(1970)),
        reviewedCount: (map['reviewedCount'] as num?)?.toInt() ?? 0,
        introducedIds: {...?(map['introducedIds'] as List?)?.map((e) => e.toString())},
        wrongIds: [...?(map['wrongIds'] as List?)?.map((e) => e.toString())],
        wrongAttempts: {
          for (final e in ((map['wrongAttempts'] as Map?) ?? const {}).entries)
            e.key.toString(): (e.value as num?)?.toInt() ?? 0,
        },
        missedIds: [...?(map['missedIds'] as List?)?.map((e) => e.toString())],
        lessonsDone: map['lessonsDone'] == true,
      );
}
