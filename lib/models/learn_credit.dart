import 'dart:math' as math;

import '../services/fsrs_service.dart';

/// Regeln der Lernzeit-Sperre. Reisen mit dem Cloud-Abgleich (die zuletzt
/// geänderten gelten, siehe [newer]), damit jedes Gerät dasselbe Guthaben
/// anzeigt. Sperren können die Android-App ([packages]) und die Windows-App
/// ([pcSites], [pcGames]); die Tageszeit teilen sich Handy und PC.
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
    this.pcSites = defaultPcSites,
    this.pcExceptions = defaultPcExceptions,
    this.pcGames = defaultPcGames,
    this.weeklyGameMinutes = 240,
    this.gameMinutesPerTopic = 30,
    this.blockMinutes = 30,
    this.practiceMinutes = 5,
  });

  static const defaultPcSites = ['YouTube', 'Instagram'];
  static const defaultPcExceptions = ['YouTube Music', 'Minecraft Launcher'];
  static const defaultPcGames = ['Minecraft', 'VALORANT'];

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

  /// Am PC (Tageszeit, mit dem Handy geteilt): Webseiten, erkannt am Titel
  /// des Browser-Tabs – gezählt nur, solange sie vorn zu sehen sind.
  final List<String> pcSites;

  /// Fenstertitel, die nie zählen (z.B. „YouTube Music“ zum Hören).
  final List<String> pcExceptions;

  /// Am PC (Wochenzeit): Spiele/Programme, erkannt am Programmnamen
  /// („…​.exe“) oder Fenstertitel – nicht in Browsern.
  final List<String> pcGames;

  /// Spielzeit je Woche (Mo ab [dayStartHour] Uhr) ohne Lernen …
  final int weeklyGameMinutes;

  /// … und je in der Woche neu gelerntem Thema zusätzlich.
  final int gameMinutesPerTopic;

  /// Entsperr-Block (2 Aufgaben ohne Hilfe gelöst) bringt so viele Minuten …
  final int blockMinutes;

  /// … eine abgeschlossene Übungseinheit davon schon so viele vorab.
  final int practiceMinutes;

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
      pcSites: _union(next.pcSites, pcSites),
      // Ausnahmen lockern – während der Festlegung nur weniger.
      pcExceptions: [
        for (final e in next.pcExceptions)
          if (pcExceptions.contains(e)) e,
      ],
      pcGames: _union(next.pcGames, pcGames),
      weeklyGameMinutes: math.min(weeklyGameMinutes, next.weeklyGameMinutes),
      gameMinutesPerTopic: math.min(gameMinutesPerTopic, next.gameMinutesPerTopic),
      blockMinutes: math.min(blockMinutes, next.blockMinutes),
      practiceMinutes: math.min(practiceMinutes, next.practiceMinutes),
    );
  }

  static List<String> _union(List<String> first, List<String> rest) => [
    ...first,
    for (final p in rest)
      if (!first.contains(p)) p,
  ];

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
    List<String>? pcSites,
    List<String>? pcExceptions,
    List<String>? pcGames,
    int? weeklyGameMinutes,
    int? gameMinutesPerTopic,
    int? blockMinutes,
    int? practiceMinutes,
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
    pcSites: pcSites ?? this.pcSites,
    pcExceptions: pcExceptions ?? this.pcExceptions,
    pcGames: pcGames ?? this.pcGames,
    weeklyGameMinutes: weeklyGameMinutes ?? this.weeklyGameMinutes,
    gameMinutesPerTopic: gameMinutesPerTopic ?? this.gameMinutesPerTopic,
    blockMinutes: blockMinutes ?? this.blockMinutes,
    practiceMinutes: practiceMinutes ?? this.practiceMinutes,
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
    'pcSites': pcSites,
    'pcExceptions': pcExceptions,
    'pcGames': pcGames,
    'weeklyGameMinutes': weeklyGameMinutes,
    'gameMinutesPerTopic': gameMinutesPerTopic,
    'blockMinutes': blockMinutes,
    'practiceMinutes': practiceMinutes,
  };

  static LearnCreditRules fromMap(Object? raw) {
    if (raw is! Map) return const LearnCreditRules();
    int number(Object? v, int fallback, int min, int max) => (v is num ? v.toInt() : fallback).clamp(min, max);
    final packages = raw['packages'];
    List<String> list(Object? v, List<String> fallback) => v is List
        ? [
            for (final e in v)
              if ('$e'.trim().isNotEmpty) '$e'.trim(),
          ]
        : fallback;
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
      pcSites: list(raw['pcSites'], defaultPcSites),
      pcExceptions: list(raw['pcExceptions'], defaultPcExceptions),
      pcGames: list(raw['pcGames'], defaultPcGames),
      weeklyGameMinutes: number(raw['weeklyGameMinutes'], 240, 0, 10080),
      gameMinutesPerTopic: number(raw['gameMinutesPerTopic'], 30, 0, 600),
      blockMinutes: number(raw['blockMinutes'], 30, 0, 600),
      practiceMinutes: number(raw['practiceMinutes'], 5, 0, 600),
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

/// Lernguthaben: welche Themen wann neu gelernt wurden, an welchen Lerntagen
/// das Daily Quiz fertig war und wie viel Zeit jedes Gerät in gesperrten Apps
/// verbracht hat. Reist mit dem Cloud-Abgleich (alle Geräte zählen), die
/// laufenden Serien bleiben auf dem Gerät.
class LearnCredit {
  const LearnCredit({
    this.earned = const {},
    this.dailyDays = const {},
    this.streaks = const {},
    this.streakDay = '',
    this.used = const {},
    this.bonus = const {},
  });

  /// Thema (Schlüssel, z.B. `concept:<id>`) → wann gelernt. Jedes Thema zählt
  /// nur einmal – beim ersten Mal.
  final Map<String, EarnedTopic> earned;

  /// Lerntage, an denen das Daily Quiz fertig war.
  final Set<String> dailyDays;

  /// Fehlerfreie Antworten hintereinander je Thema – nur am [streakDay].
  final Map<String, int> streaks;
  final String streakDay;

  /// Genutzte Sekunden je Gerät: Gerät → Schlüssel → Sekunden. Schlüssel
  /// [dailyUsageKey] (Tageszeit, Handy und PC zusammen) und [gameUsageKey]
  /// (Spielzeit der Woche).
  final Map<String, Map<String, int>> used;

  /// Extra-Minuten (z.B. aus Entsperr-Blöcken): Kennung → Lerntag und Minuten.
  /// Jede Kennung zählt nur einmal – auch über mehrere Geräte.
  final Map<String, ({String day, int minutes})> bonus;

  /// So lange bleiben Nutzungszahlen erhalten.
  static const usageKeepDays = 21;

  static String dailyUsageKey(String day) => 'd:$day';
  static String gameUsageKey(String week) => 'g:$week';

  /// Der Lerntag zu [now]: beginnt um [startHour] (vorher zählt noch der
  /// Vortag).
  static String dayKey(DateTime now, int startHour) => _format(dayStart(now, startHour));

  /// Die Lernwoche zu [now]: der Montag, an dem sie (um [startHour]) begann.
  static String weekKey(DateTime now, int startHour) {
    final start = dayStart(now, startHour);
    return _format(DateTime(start.year, start.month, start.day - (start.weekday - 1)));
  }

  /// Die Lernwoche eines Lerntags („JJJJ-MM-TT“).
  static String weekOfDay(String day) {
    final d = DateTime.tryParse(day);
    if (d == null) return '';
    return _format(DateTime(d.year, d.month, d.day - (d.weekday - 1)));
  }

  static String _format(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// Beginn des Lerntags zu [now].
  static DateTime dayStart(DateTime now, int startHour) {
    final today = DateTime(now.year, now.month, now.day, startHour);
    return now.isBefore(today) ? DateTime(now.year, now.month, now.day - 1, startHour) : today;
  }

  /// Zählt die Antwort als fehlerfrei? Bei geprüften Aufgaben: richtig und
  /// ohne Hilfe/Fehlversuch (dann käme „Schwer“ mit); bei selbst bewerteten
  /// Karten: gewusst (Schwer, Gut, Leicht).
  static bool isClean({Grade? selfGrade, bool? isCorrect}) {
    if (isCorrect != null) return isCorrect && selfGrade != Grade.hard && selfGrade != Grade.again;
    return selfGrade != null && selfGrade != Grade.again;
  }

  LearnCredit _with({
    Map<String, EarnedTopic>? earned,
    Set<String>? dailyDays,
    Map<String, int>? streaks,
    String? streakDay,
    Map<String, Map<String, int>>? used,
    Map<String, ({String day, int minutes})>? bonus,
  }) => LearnCredit(
    earned: earned ?? this.earned,
    dailyDays: dailyDays ?? this.dailyDays,
    streaks: streaks ?? this.streaks,
    streakDay: streakDay ?? this.streakDay,
    used: used ?? this.used,
    bonus: bonus ?? this.bonus,
  );

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
      return (_with(streaks: streaks, streakDay: day), null);
    }
    final count = (streaks[topic] ?? 0) + 1;
    streaks[topic] = count;
    if (count >= rules.correctInRow && !earned.containsKey(topic)) {
      return (
        _with(
          earned: {
            ...earned,
            topic: EarnedTopic(day: day, title: title, at: now),
          },
          streaks: streaks,
          streakDay: day,
        ),
        title,
      );
    }
    return (_with(streaks: streaks, streakDay: day), null);
  }

  LearnCredit withDailyDone(DateTime now, int startHour) => _with(dailyDays: {...dailyDays, dayKey(now, startHour)});

  /// Die Nutzung dieses Geräts ([device]) für [key] setzen – nie kleiner als
  /// schon verbucht. Alte Zahlen (älter als [usageKeepDays]) fallen weg.
  LearnCredit withUsage(String device, String key, int seconds, DateTime now) {
    final cutoff = _format(now.subtract(const Duration(days: usageKeepDays)));
    Map<String, int> prune(Map<String, int> m) => {
      for (final e in m.entries)
        if (e.key.length < 3 || e.key.substring(2).compareTo(cutoff) >= 0) e.key: e.value,
    };
    final mine = prune({...?used[device]});
    mine[key] = math.max(mine[key] ?? 0, seconds);
    return _with(used: {...used, device: mine});
  }

  /// Extra-Minuten [minutes] unter [id] für den Lerntag von [now] – nur
  /// einmal je Kennung.
  LearnCredit withBonus(String id, int minutes, DateTime now, int startHour) {
    if (bonus.containsKey(id) || minutes <= 0) return this;
    return _with(bonus: {...bonus, id: (day: dayKey(now, startHour), minutes: minutes)});
  }

  /// Extra-Minuten am Lerntag [day].
  int bonusOn(String day) => bonus.values.where((b) => b.day == day).fold(0, (sum, b) => sum + b.minutes);

  /// Genutzte Sekunden für [key] auf allen Geräten (außer [exceptDevice]).
  int usedSeconds(String key, {String? exceptDevice}) {
    var total = 0;
    for (final e in used.entries) {
      if (e.key != exceptDevice) total += e.value[key] ?? 0;
    }
    return total;
  }

  /// Mit dem Stand eines anderen Geräts zusammenführen: Themen und Daily-Tage
  /// vereinigen (bei doppelt gelernten Themen zählt das frühere), Nutzung je
  /// Gerät das Größere.
  LearnCredit mergedWith(LearnCredit other) {
    final merged = {...earned};
    for (final e in other.earned.entries) {
      final mine = merged[e.key];
      if (mine == null || e.value.at.isBefore(mine.at)) merged[e.key] = e.value;
    }
    final usage = {
      for (final e in used.entries) e.key: {...e.value},
    };
    for (final device in other.used.entries) {
      final target = usage.putIfAbsent(device.key, () => {});
      for (final e in device.value.entries) {
        target[e.key] = math.max(target[e.key] ?? 0, e.value);
      }
    }
    return _with(
      earned: merged,
      dailyDays: {...dailyDays, ...other.dailyDays},
      used: usage,
      bonus: {...other.bonus, ...bonus},
    );
  }

  /// Heute neu gelernte Themen (Titel, in Reihenfolge).
  List<String> topicsOn(String day) => _titles((e) => e.day == day);

  /// In der Lernwoche [week] neu gelernte Themen.
  List<String> topicsInWeek(String week) => _titles((e) => weekOfDay(e.day) == week);

  List<String> _titles(bool Function(EarnedTopic) test) {
    final list = [
      for (final e in earned.values)
        if (test(e)) e,
    ]..sort((a, b) => a.at.compareTo(b.at));
    return [for (final e in list) e.title];
  }

  /// Für den Cloud-Abgleich (ohne die laufenden Serien).
  Map<String, dynamic> toSyncMap() => {
    'earned': {for (final e in earned.entries) e.key: e.value.toMap()},
    'dailyDays': (dailyDays.toList()..sort()),
    'used': used,
    'bonus': {
      for (final e in bonus.entries) e.key: {'day': e.value.day, 'minutes': e.value.minutes},
    },
  };

  Map<String, dynamic> toMap() => {...toSyncMap(), 'streaks': streaks, 'streakDay': streakDay};

  static LearnCredit fromMap(Object? raw) {
    if (raw is! Map) return const LearnCredit();
    final earned = raw['earned'];
    final days = raw['dailyDays'];
    final streaks = raw['streaks'];
    final used = raw['used'];
    final bonus = raw['bonus'];
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
      used: {
        if (used is Map)
          for (final d in used.entries)
            if (d.value is Map)
              '${d.key}': {
                for (final e in (d.value as Map).entries)
                  if (e.value is num) '${e.key}': (e.value as num).toInt(),
              },
      },
      bonus: {
        if (bonus is Map)
          for (final e in bonus.entries)
            if (e.value case {'day': final Object day, 'minutes': final num minutes})
              '${e.key}': (day: '$day', minutes: minutes.toInt()),
      },
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
    final minutes = rules.freeMinutes + topics.length * rules.minutesPerTopic + credit.bonusOn(day);
    final missingTopics = rules.topicsForUnlimited - topics.length;
    final unlimitedNeeds = [
      if (missingTopics > 0) missingTopics == 1 ? 'einem weiteren neuen Thema' : '$missingTopics weiteren neuen Themen',
      if (rules.dailyForUnlimited && !daily) 'fertigem Daily Quiz',
    ];
    final steps = <String>[
      if (rules.minutesPerTopic > 0)
        'Lerne ein neues Thema (${rules.correctInRow} Aufgaben bzw. Fragen dazu hintereinander fehlerfrei) für '
            '+${rules.minutesPerTopic} Minuten.',
      if (rules.blockMinutes > 0) 'Oder löse einen Entsperr-Block (2 Aufgaben) für +${rules.blockMinutes} Minuten.',
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

/// Spielzeit am PC in dieser Lernwoche: [LearnCreditRules.weeklyGameMinutes]
/// frei, je in der Woche neu gelerntem Thema mehr.
class GameAllowance {
  const GameAllowance({required this.week, required this.minutes, required this.topicsThisWeek});

  final String week;
  final int minutes;
  final int topicsThisWeek;

  static GameAllowance of(LearnCredit credit, LearnCreditRules rules, DateTime now) {
    final week = LearnCredit.weekKey(now, rules.dayStartHour);
    final topics = credit.topicsInWeek(week).length;
    return GameAllowance(
      week: week,
      minutes: rules.weeklyGameMinutes + topics * rules.gameMinutesPerTopic,
      topicsThisWeek: topics,
    );
  }
}
