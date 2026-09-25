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

  DailySessionState copyWith({
    int? reviewedCount,
    Set<String>? introducedIds,
    List<String>? wrongIds,
    Map<String, int>? wrongAttempts,
  }) {
    return DailySessionState(
      day: day,
      reviewedCount: reviewedCount ?? this.reviewedCount,
      introducedIds: introducedIds ?? this.introducedIds,
      wrongIds: wrongIds ?? this.wrongIds,
      wrongAttempts: wrongAttempts ?? this.wrongAttempts,
    );
  }

  Map<String, dynamic> toMap() => {
        'day': day.toIso8601String(),
        'reviewedCount': reviewedCount,
        'introducedIds': introducedIds.toList(),
        'wrongIds': wrongIds,
        'wrongAttempts': wrongAttempts,
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
      );
}
