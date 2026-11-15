import 'dart:math' as math;

import '../services/fsrs_service.dart';

/// Regeln der Lernzeit-Sperre. Reisen mit dem Cloud-Abgleich (die zuletzt
/// geänderten gelten, siehe [newer]), damit jedes Gerät dasselbe Guthaben
/// anzeigt; sperren kann nur die Android-App.
class LearnCreditRules {
  const LearnCreditRules({
    this.enabled = false,
    this.packages = const ['com.instagram.android'],
    this.freeMinutes = 30,
    this.minutesPerTopic = 30,
    this.topicsForUnlimited = 1,
    this.dailyForUnlimited = true,
    this.correctInRow = 2,
    this.dayStartHour = 4,
    this.updatedAt,
    this.lockedUntil,
  });

  /// So lange ist eine eingeschaltete Sperre festgelegt.
  static const lockDuration = Duration(days: 7);

  final bool enabled;

  /// Gesperrte Apps (Android-Paketnamen).
  final List<String> packages;

  /// So viele Minuten am Tag gibt es ohne Lernen.
  final int freeMinutes;

  /// Je neu gelerntem Thema kommen so viele Minuten dazu.
  final int minutesPerTopic;

  /// Ab so vielen neuen Themen (und – wenn [dailyForUnlimited] – erledigtem
  /// Daily Quiz) ist die Zeit unbegrenzt; 0 = nie unbegrenzt.
  final int topicsForUnlimited;
  final bool dailyForUnlimited;

  /// So viele fehlerfreie Antworten hintereinander zu einem Thema, bis es als
  /// gelernt zählt.
  final int correctInRow;

  /// Der Lerntag beginnt um diese Stunde (4 = 4:00 bis 4:00).
  final int dayStartHour;

  /// Wann die Regeln zuletzt geändert wurden (null = nie, Standardwerte).
  final DateTime? updatedAt;

  /// Bis dahin lässt sich die Sperre nicht ausschalten und nur strenger
  /// stellen (siehe [guard]).
  final DateTime? lockedUntil;

  bool isLocked(DateTime now) => lockedUntil != null && now.isBefore(lockedUntil!);

  /// [next] soll gelten – solange diese Regeln festgelegt sind, aber nur so
  /// weit, wie es strenger ist: eingeschaltet bleiben, keine App weniger,
  /// nicht mehr Minuten, keine kürzere Serie, Lerntag und Daily-Pflicht
  /// bleiben. Die Festlegung selbst kann nur länger werden.
  LearnCreditRules guard(LearnCreditRules next, DateTime now) {
    if (!isLocked(now)) return next;
    final until = next.lockedUntil != null && next.lockedUntil!.isAfter(lockedUntil!) ? next.lockedUntil : lockedUntil;
    return LearnCreditRules(
      enabled: true,
      packages: [
        ...next.packages,
        for (final p in packages)
          if (!next.packages.contains(p)) p,
      ],
      freeMinutes: math.min(freeMinutes, next.freeMinutes),
      minutesPerTopic: math.min(minutesPerTopic, next.minutesPerTopic),
      // 0 = nie unbegrenzt ist das Strengste, sonst gilt: mehr Themen = strenger.
      topicsForUnlimited: topicsForUnlimited == 0 || next.topicsForUnlimited == 0
          ? 0
          : math.max(topicsForUnlimited, next.topicsForUnlimited),
      dailyForUnlimited: dailyForUnlimited || next.dailyForUnlimited,
      correctInRow: math.max(correctInRow, next.correctInRow),
      dayStartHour: dayStartHour,
      updatedAt: next.updatedAt,
      lockedUntil: until,
    );
  }

  LearnCreditRules copyWith({
    bool? enabled,
    List<String>? packages,
    int? freeMinutes,
    int? minutesPerTopic,
    int? topicsForUnlimited,
    bool? dailyForUnlimited,
    int? correctInRow,
    int? dayStartHour,
    DateTime? updatedAt,
    DateTime? lockedUntil,
  }) => LearnCreditRules(
    enabled: enabled ?? this.enabled,
    packages: packages ?? this.packages,
    freeMinutes: freeMinutes ?? this.freeMinutes,
    minutesPerTopic: minutesPerTopic ?? this.minutesPerTopic,
    topicsForUnlimited: topicsForUnlimited ?? this.topicsForUnlimited,
    dailyForUnlimited: dailyForUnlimited ?? this.dailyForUnlimited,
    correctInRow: correctInRow ?? this.correctInRow,
    dayStartHour: dayStartHour ?? this.dayStartHour,
    updatedAt: updatedAt ?? this.updatedAt,
    lockedUntil: lockedUntil ?? this.lockedUntil,
  );

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'packages': packages,
    'freeMinutes': freeMinutes,
    'minutesPerTopic': minutesPerTopic,
    'topicsForUnlimited': topicsForUnlimited,
    'dailyForUnlimited': dailyForUnlimited,
    'correctInRow': correctInRow,
    'dayStartHour': dayStartHour,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (lockedUntil != null) 'lockedUntil': lockedUntil!.toIso8601String(),
  };

  static LearnCreditRules fromMap(Object? raw) {
    if (raw is! Map) return const LearnCreditRules();
    int number(Object? v, int fallback, int min, int max) => (v is num ? v.toInt() : fallback).clamp(min, max);
    final packages = raw['packages'];
    return LearnCreditRules(
      enabled: raw['enabled'] == true,
      packages: packages is List ? [for (final p in packages) '$p'] : const ['com.instagram.android'],
      freeMinutes: number(raw['freeMinutes'], 30, 0, 600),
      minutesPerTopic: number(raw['minutesPerTopic'], 30, 0, 600),
      topicsForUnlimited: number(raw['topicsForUnlimited'], 1, 0, 50),
      dailyForUnlimited: raw['dailyForUnlimited'] != false,
      correctInRow: number(raw['correctInRow'], 2, 1, 10),
      dayStartHour: number(raw['dayStartHour'], 4, 0, 23),
      updatedAt: DateTime.tryParse('${raw['updatedAt'] ?? ''}'),
      lockedUntil: DateTime.tryParse('${raw['lockedUntil'] ?? ''}'),
    );
  }

  /// Von zwei gespeicherten Regeln (Maps) die zuletzt geänderten – eine
  /// festgelegte Sperre der anderen Seite lockern sie aber nicht (siehe
  /// [guard]).
  static Map<String, dynamic>? newer(Object? a, Object? b, {DateTime? now}) {
    final ra = a is Map ? fromMap(a) : null;
    final rb = b is Map ? fromMap(b) : null;
    if (ra == null) return rb?.toMap();
    if (rb == null) return ra.toMap();
    final ta = ra.updatedAt;
    final tb = rb.updatedAt;
    final bWins = tb != null && (ta == null || tb.isAfter(ta));
    final when = now ?? DateTime.now();
    return (bWins ? ra.guard(rb, when) : rb.guard(ra, when)).toMap();
  }
}

/// Ein gelerntes Thema: wann (Lerntag) und wie es heißt.
class EarnedTopic {
  const EarnedTopic({required this.day, required this.title, required this.at});

  /// Lerntag als „JJJJ-MM-TT“ (siehe [LearnCredit.dayKey]).
  final String day;
  final String title;
  final DateTime at;

  Map<String, dynamic> toMap() => {'day': day, 'title': title, 'at': at.toIso8601String()};

  static EarnedTopic? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final day = '${raw['day'] ?? ''}';
    if (day.isEmpty) return null;
    return EarnedTopic(
      day: day,
      title: '${raw['title'] ?? ''}',
      at: DateTime.tryParse('${raw['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Lernguthaben: welche Themen wann neu gelernt wurden und an welchen
/// Lerntagen das Daily Quiz fertig war. Reist mit dem Cloud-Abgleich (alle
/// Geräte zählen), die laufenden Serien bleiben auf dem Gerät.
class LearnCredit {
  const LearnCredit({this.earned = const {}, this.dailyDays = const {}, this.streaks = const {}, this.streakDay = ''});

  /// Thema (Schlüssel, z.B. `concept:<id>`) → wann gelernt. Jedes Thema zählt
  /// nur einmal – beim ersten Mal.
  final Map<String, EarnedTopic> earned;

  /// Lerntage, an denen das Daily Quiz fertig war.
  final Set<String> dailyDays;

  /// Fehlerfreie Antworten hintereinander je Thema – nur am [streakDay].
  final Map<String, int> streaks;
  final String streakDay;

  /// Der Lerntag zu [now]: beginnt um [startHour] (vorher zählt noch der
  /// Vortag).
  static String dayKey(DateTime now, int startHour) {
    final shifted = now.hour < startHour ? now.subtract(const Duration(days: 1)) : now;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${shifted.year}-${two(shifted.month)}-${two(shifted.day)}';
  }

  /// Beginn des Lerntags zu [now].
  static DateTime dayStart(DateTime now, int startHour) {
    final today = DateTime(now.year, now.month, now.day, startHour);
    return now.isBefore(today) ? today.subtract(const Duration(days: 1)) : today;
  }

  /// Zählt die Antwort als fehlerfrei? Bei geprüften Aufgaben: richtig und
  /// ohne Hilfe/Fehlversuch (dann käme „Schwer“ mit); bei selbst bewerteten
  /// Karten: gewusst (Schwer, Gut, Leicht).
  static bool isClean({Grade? selfGrade, bool? isCorrect}) {
    if (isCorrect != null) return isCorrect && selfGrade != Grade.hard && selfGrade != Grade.again;
    return selfGrade != null && selfGrade != Grade.again;
  }

  /// Eine Antwort zu Thema [topic] verbuchen. Liefert den neuen Stand und –
  /// falls das Thema dadurch gelernt ist – seinen Titel.
  (LearnCredit, String?) withAnswer({
    required String topic,
    required String title,
    required bool clean,
    required DateTime now,
    required LearnCreditRules rules,
  }) {
    final day = dayKey(now, rules.dayStartHour);
    final streaks = day == streakDay ? {...this.streaks} : <String, int>{};
    if (!clean) {
      streaks[topic] = 0;
      return (LearnCredit(earned: earned, dailyDays: dailyDays, streaks: streaks, streakDay: day), null);
    }
    final count = (streaks[topic] ?? 0) + 1;
    streaks[topic] = count;
    if (count >= rules.correctInRow && !earned.containsKey(topic)) {
      return (
        LearnCredit(
          earned: {
            ...earned,
            topic: EarnedTopic(day: day, title: title, at: now),
          },
          dailyDays: dailyDays,
          streaks: streaks,
          streakDay: day,
        ),
        title,
      );
    }
    return (LearnCredit(earned: earned, dailyDays: dailyDays, streaks: streaks, streakDay: day), null);
  }

  LearnCredit withDailyDone(DateTime now, int startHour) => LearnCredit(
    earned: earned,
    dailyDays: {...dailyDays, dayKey(now, startHour)},
    streaks: streaks,
    streakDay: streakDay,
  );

  /// Mit dem Stand eines anderen Geräts zusammenführen: Themen und Daily-Tage
  /// vereinigen (bei doppelt gelernten Themen zählt das frühere).
  LearnCredit mergedWith(LearnCredit other) {
    final merged = {...earned};
    for (final e in other.earned.entries) {
      final mine = merged[e.key];
      if (mine == null || e.value.at.isBefore(mine.at)) merged[e.key] = e.value;
    }
    return LearnCredit(
      earned: merged,
      dailyDays: {...dailyDays, ...other.dailyDays},
      streaks: streaks,
      streakDay: streakDay,
    );
  }

  /// Heute neu gelernte Themen (Titel, in Reihenfolge).
  List<String> topicsOn(String day) {
    final list = [
      for (final e in earned.values)
        if (e.day == day) e,
    ]..sort((a, b) => a.at.compareTo(b.at));
    return [for (final e in list) e.title];
  }

  /// Für den Cloud-Abgleich (ohne die laufenden Serien).
  Map<String, dynamic> toSyncMap() => {
    'earned': {for (final e in earned.entries) e.key: e.value.toMap()},
    'dailyDays': (dailyDays.toList()..sort()),
  };

  Map<String, dynamic> toMap() => {...toSyncMap(), 'streaks': streaks, 'streakDay': streakDay};

  static LearnCredit fromMap(Object? raw) {
    if (raw is! Map) return const LearnCredit();
    final earned = raw['earned'];
    final days = raw['dailyDays'];
    final streaks = raw['streaks'];
    return LearnCredit(
      earned: {
        if (earned is Map)
          for (final e in earned.entries) '${e.key}': ?EarnedTopic.fromMap(e.value),
      },
      dailyDays: {
        if (days is List)
          for (final d in days) '$d',
      },
      streaks: {
        if (streaks is Map)
          for (final e in streaks.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
      streakDay: '${raw['streakDay'] ?? ''}',
    );
  }
}

/// Was heute erlaubt ist.
class LearnAllowance {
  const LearnAllowance({
    required this.day,
    required this.unlimited,
    required this.minutes,
    required this.topicsToday,
    required this.dailyDone,
    required this.nextStep,
  });

  final String day;
  final bool unlimited;

  /// Erlaubte Minuten (bei [unlimited] ohne Bedeutung).
  final int minutes;
  final List<String> topicsToday;
  final bool dailyDone;

  /// Was als Nächstes mehr Zeit bringt (für den Sperrbildschirm).
  final String nextStep;

  static LearnAllowance of(LearnCredit credit, LearnCreditRules rules, DateTime now) {
    final day = LearnCredit.dayKey(now, rules.dayStartHour);
    final topics = credit.topicsOn(day);
    final daily = credit.dailyDays.contains(day);
    final unlimited =
        rules.topicsForUnlimited > 0 &&
        topics.length >= rules.topicsForUnlimited &&
        (!rules.dailyForUnlimited || daily);
    final minutes = rules.freeMinutes + topics.length * rules.minutesPerTopic;
    final missingTopics = rules.topicsForUnlimited - topics.length;
    final unlimitedNeeds = [
      if (missingTopics > 0) missingTopics == 1 ? 'einem weiteren neuen Thema' : '$missingTopics weiteren neuen Themen',
      if (rules.dailyForUnlimited && !daily) 'fertigem Daily Quiz',
    ];
    final steps = <String>[
      if (rules.minutesPerTopic > 0)
        'Lerne ein neues Thema (${rules.correctInRow} Aufgaben bzw. Fragen dazu hintereinander fehlerfrei) für '
            '+${rules.minutesPerTopic} Minuten.',
      if (rules.topicsForUnlimited > 0 && unlimitedNeeds.isNotEmpty) 'Unbegrenzt mit ${unlimitedNeeds.join(' und ')}.',
    ];
    return LearnAllowance(
      day: day,
      unlimited: unlimited,
      minutes: minutes,
      topicsToday: topics,
      dailyDone: daily,
      nextStep: unlimited ? '' : steps.join(' '),
    );
  }
}
