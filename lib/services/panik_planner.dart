import 'dart:math';

import '../models/flashcard.dart';
import '../models/panik_content.dart';
import '../repositories/review_log_repository.dart';
import 'calendar_days.dart';
import 'panik_import.dart';

/// Ein Aufgabentyp aus Sicht des Plans (aus den Karten des Panik-Fachs).
class PlanType {
  const PlanType({
    required this.id,
    required this.title,
    required this.core,
    required this.weight,
    this.area = '',
    this.prerequisites = const [],
  });

  final String id;
  final String title;

  /// Pflichtkern (true) oder Ausbau (false).
  final bool core;

  /// Geschätztes Prüfungsgewicht H/M/N.
  final String weight;
  final String area;
  final List<String> prerequisites;
}

/// Was man bei einem Typ schon gemacht hat – abgeleitet aus dem
/// Antwort-Protokoll (siehe [PanikPlanner.progressFrom]).
class TypeProgress {
  const TypeProgress({
    this.introducedOn,
    this.lastPracticed,
    this.reviewDays = 0,
    this.lastErrorOn,
    this.mastered = false,
    this.delayed = const [],
  });

  /// Tag der ersten Aufgabe dieses Typs (oder Eingangstest bestanden).
  final DateTime? introducedOn;
  final DateTime? lastPracticed;

  /// An wie vielen Tagen NACH der Einführung geübt wurde.
  final int reviewDays;
  final DateTime? lastErrorOn;

  /// Wechselkriterium: eine Aufgabe ohne Hilfe richtig und „ging leicht“ –
  /// ab dann keine Lösungsbeispiele mehr.
  final bool mastered;

  /// Ergebnisse verzögerter Abfragen (mindestens einen Tag nach der
  /// Einführung), älteste zuerst – Grundlage der Sicherheit.
  final List<bool> delayed;

  bool get introduced => introducedOn != null;

  /// Sicherheit 0…1 aus den letzten bis zu 5 verzögerten Ergebnissen
  /// (null = noch keine verzögerte Abfrage).
  double? get confidence {
    if (delayed.isEmpty) return null;
    final recent = delayed.length > 5 ? delayed.sublist(delayed.length - 5) : delayed;
    return recent.where((r) => r).length / recent.length;
  }
}

enum PlanBlockKind {
  /// Neuer Typ: Beispiel → Fading → ähnliche Aufgaben.
  newType,

  /// Gemischter, unbeschrifteter Satz aus bisherigen Typen.
  mixed,

  /// Probeklausur unter Zeitdruck.
  mock,

  /// Formelabruf am Ende des Tages.
  formulas,
}

class PlanBlock {
  const PlanBlock(this.kind, this.minutes, {this.typeId, this.pauseAfter = 0});
  final PlanBlockKind kind;
  final int minutes;
  final String? typeId;

  /// Pause danach in Minuten (nach jedem zweiten Block eine lange).
  final int pauseAfter;
}

enum PlanPhase { learn, consolidate, finalDay, examDay, over }

class DayPlan {
  const DayPlan({
    required this.daysLeft,
    required this.phase,
    this.newTypes = const [],
    this.dueTypes = const [],
    this.dropped = const [],
    this.blocks = const [],
    this.mockDue = false,
    this.behind = 0,
  });

  /// Tage bis zur Klausur (0 = heute ist Klausur).
  final int daysLeft;
  final PlanPhase phase;
  final List<String> newTypes;

  /// Typen, die heute im gemischten Satz wiederholt werden müssen.
  final List<String> dueTypes;

  /// Typen, für die die Zeit nicht mehr reicht (offen angezeigt).
  final List<String> dropped;
  final List<PlanBlock> blocks;
  final bool mockDue;

  /// Wie viele Typen gegenüber einem gleichmäßigen Plan im Rückstand sind.
  final int behind;

  int get studyMinutes => blocks.fold(0, (s, b) => s + b.minutes);
}

/// Der Tagesplan des Panik-Modus – reine Logik, jeden Tag NEU aus dem Stand
/// berechnet (nichts wird gespeichert). Verpasste Tage verteilen sich so von
/// selbst auf die restlichen Tage, statt sich aufzustauen.
///
/// Regeln (nach der Forschung im Prompt):
/// - neuer Stoff nur in der ersten Hälfte der Zeit, Pflichtkern zuerst,
///   innerhalb nach Gewicht × Grundlage für andere Typen, Voraussetzungen vorher;
/// - Wiederholung je Typ nach 2, dann 5, dann 10 Tagen und in den letzten
///   2–4 Tagen noch einmal; Fehler-Typen nach 2 Tagen;
/// - Probeklausuren 5 und 2 Tage vorher; letzter Tag leicht und kurz;
/// - Blöcke à 50 Minuten mit 10 Minuten Pause, nach zwei Blöcken 20 Minuten.
class PanikPlanner {
  static const blockMinutes = 50;
  static const formulaMinutes = 15;
  static const mockMinutes = 90;
  static const reviewGaps = [2, 5, 10];

  static DayPlan plan({
    required DateTime today,
    required DateTime start,
    required DateTime exam,
    required double hoursPerDay,
    required List<PlanType> types,
    required Map<String, TypeProgress> progress,
    int mocksDone = 0,
  }) {
    final d = calendarDaysBetween(today, exam);
    if (d < 0) return const DayPlan(daysLeft: -1, phase: PlanPhase.over);
    if (d == 0) return const DayPlan(daysLeft: 0, phase: PlanPhase.examDay);
    final total = max(1, calendarDaysBetween(start, exam));
    final half = (total / 2).ceil();
    TypeProgress p(String id) => progress[id] ?? const TypeProgress();

    // --- neuer Stoff
    final open = _priorityOrder(types).where((t) => !p(t.id).introduced).toList();
    final newDaysLeft = max(0, d - half);
    final perDay = max(1, (hoursPerDay * 60 * 0.5 / blockMinutes).floor());
    final newTypes = <String>[];
    final dropped = <String>[];
    var behind = 0;
    if (d > 1) {
      if (newDaysLeft > 0) {
        final capacity = newDaysLeft * perDay;
        // Reicht die Zeit nicht, fällt zuerst der Ausbau weg (Liste ist Kern zuerst).
        final keep = open.take(capacity).toList();
        dropped.addAll(open.skip(capacity).map((t) => t.id));
        final today_ = min(perDay, (keep.length / newDaysLeft).ceil());
        newTypes.addAll(_introducible(keep, types, p).take(today_).map((t) => t.id));
        // Rückstand gegenüber gleichmäßiger Einführung über die Lernhälfte.
        final elapsed = total - d;
        final expected = (types.length * min(1.0, elapsed / max(1, total - half))).floor();
        behind = max(0, expected - (types.length - open.length));
      } else {
        // Zeit für neuen Stoff ist um: Pflichtkern wird trotzdem noch
        // eingeführt (bis 2 Tage vorher), Ausbau gestrichen.
        final core = open.where((t) => t.core).toList();
        dropped.addAll(open.where((t) => !t.core).map((t) => t.id));
        if (d > 2) newTypes.addAll(_introducible(core, types, p).take(perDay).map((t) => t.id));
        if (d <= 2) dropped.addAll(core.map((t) => t.id));
        behind = core.length;
      }
    } else {
      dropped.addAll(open.map((t) => t.id));
    }

    // --- Wiederholungen
    final due = <String>[];
    for (final (i, t) in types.indexed) {
      final pr = p(t.id);
      if (!pr.introduced) continue;
      final last = pr.lastPracticed ?? pr.introducedOn!;
      final gap = reviewGaps[min(pr.reviewDays, reviewGaps.length - 1)];
      final spacedDue = calendarDaysBetween(last, today) >= gap;
      // Schlusswiederholung in den letzten 2–4 Tagen, auf die Tage verteilt.
      final finalSlot = 4 - i % 3;
      final finalWindow = d <= finalSlot && calendarDaysBetween(last, exam) > 4;
      // Fehler: nach 2 Tagen eine ähnliche Aufgabe – solange seitdem nicht geübt.
      final errorDue = pr.lastErrorOn != null &&
          calendarDaysBetween(pr.lastErrorOn!, today) >= 2 &&
          calendarDaysBetween(pr.lastErrorOn!, last) == 0;
      if (spacedDue || finalWindow || errorDue) due.add(t.id);
    }

    final mockDue = d >= 2 && ((d <= 5 && mocksDone < 1) || (d <= 2 && mocksDone < 2));

    // --- Blöcke
    final finalDay = d == 1;
    var minutes = (hoursPerDay * 60).round();
    if (finalDay) minutes = min(minutes, 120);
    final blocks = <PlanBlock>[];
    for (final id in newTypes) {
      blocks.add(PlanBlock(PlanBlockKind.newType, blockMinutes, typeId: id));
    }
    if (mockDue) blocks.add(const PlanBlock(PlanBlockKind.mock, mockMinutes));
    final used = blocks.fold(0, (s, b) => s + b.minutes);
    final anyIntroduced = types.any((t) => p(t.id).introduced) || newTypes.isNotEmpty;
    final mixedCount = anyIntroduced ? max(1, (minutes - used - formulaMinutes) ~/ blockMinutes) : 0;
    for (var i = 0; i < mixedCount; i++) {
      blocks.add(PlanBlock(PlanBlockKind.mixed, finalDay ? 40 : blockMinutes));
    }
    if (anyIntroduced) blocks.add(const PlanBlock(PlanBlockKind.formulas, formulaMinutes));
    final withPauses = [
      for (final (i, b) in blocks.indexed)
        PlanBlock(b.kind, b.minutes, typeId: b.typeId, pauseAfter: i == blocks.length - 1 ? 0 : ((i + 1) % 2 == 0 ? 20 : 10)),
    ];

    return DayPlan(
      daysLeft: d,
      phase: finalDay ? PlanPhase.finalDay : (newDaysLeft > 0 ? PlanPhase.learn : PlanPhase.consolidate),
      newTypes: newTypes,
      dueTypes: due,
      dropped: dropped,
      blocks: withPauses,
      mockDue: mockDue,
      behind: behind,
    );
  }

  /// Pflichtkern vor Ausbau, innerhalb nach Gewicht × (1 + Anzahl Typen, die
  /// darauf aufbauen); Voraussetzungen stehen immer vor ihren Folgetypen.
  static List<PlanType> _priorityOrder(List<PlanType> types) {
    int w(String g) => switch (g) { 'H' => 3, 'M' => 2, _ => 1 };
    final dependents = {for (final t in types) t.id: types.where((o) => o.prerequisites.contains(t.id)).length};
    final sorted = [...types]
      ..sort((a, b) {
        if (a.core != b.core) return a.core ? -1 : 1;
        return (w(b.weight) * (1 + dependents[b.id]!)).compareTo(w(a.weight) * (1 + dependents[a.id]!));
      });
    // Voraussetzungen nach vorne ziehen (stabil).
    final out = <PlanType>[];
    void add(PlanType t, Set<String> visiting) {
      if (out.contains(t) || !visiting.add(t.id)) return;
      for (final pre in t.prerequisites) {
        final pt = types.where((x) => x.id == pre).firstOrNull;
        if (pt != null) add(pt, visiting);
      }
      out.add(t);
    }

    for (final t in sorted) {
      add(t, {});
    }
    return out;
  }

  /// Typen, deren Voraussetzungen schon eingeführt sind oder vorher in der Liste stehen.
  static Iterable<PlanType> _introducible(List<PlanType> ordered, List<PlanType> all, TypeProgress Function(String) p) sync* {
    final ready = {for (final t in all) if (p(t.id).introduced) t.id};
    for (final t in ordered) {
      if (t.prerequisites.every(ready.contains)) {
        ready.add(t.id);
        yield t;
      }
    }
  }

  /// Fortschritt je Typ aus dem Antwort-Protokoll und den Panik-Karten.
  /// [placedOut] = im Eingangstest bestanden (gilt ab [start] als eingeführt
  /// und beherrscht).
  static Map<String, TypeProgress> progressFrom({
    required List<Flashcard> cards,
    required List<ReviewLogEntry> log,
    Set<String> placedOut = const {},
    DateTime? start,
  }) {
    final infoById = {for (final c in cards) c.id: PanikCardInfo.of(c)};
    final byType = <String, List<(ReviewLogEntry, PanikCardInfo)>>{};
    for (final e in [...log]..sort((a, b) => a.at.compareTo(b.at))) {
      final info = infoById[e.cardId];
      if (info == null || info.kind == PanikItemKind.formula || info.kind == PanikItemKind.example) continue;
      byType.putIfAbsent(info.typeId, () => []).add((e, info));
    }
    final typeIds = {for (final i in infoById.values) if (i != null) i.typeId};
    final result = <String, TypeProgress>{};
    for (final id in typeIds) {
      final entries = byType[id] ?? const [];
      final placed = placedOut.contains(id);
      final intro = placed ? start : entries.firstOrNull?.$1.at;
      if (intro == null) {
        result[id] = const TypeProgress();
        continue;
      }
      final days = <int>{};
      DateTime? lastError;
      final delayed = <bool>[];
      var mastered = placed;
      for (final (e, info) in entries) {
        final right = e.correct == true && !e.dontKnow;
        final after = calendarDaysBetween(intro, e.at);
        if (after > 0) {
          days.add(after);
          delayed.add(right);
        }
        if (!right) lastError = e.at;
        if (right && e.confidence?.name == 'sure' && info.kind != PanikItemKind.recognize) mastered = true;
      }
      result[id] = TypeProgress(
        introducedOn: intro,
        lastPracticed: entries.lastOrNull?.$1.at ?? intro,
        reviewDays: days.length,
        lastErrorOn: lastError,
        mastered: mastered,
        delayed: delayed,
      );
    }
    return result;
  }

  /// Karten für einen gemischten Satz: je fälligem Typ eine Rechenaufgabe
  /// (am längsten nicht gesehen zuerst), dazu „Verfahren erkennen“ und
  /// Auffüllen aus älteren Typen. Ab Tag 8 stammen höchstens ⅓ aus Typen der
  /// letzten 7 Tage. Ohne Überschrift, Typen abwechselnd.
  static List<Flashcard> mixedSet({
    required List<Flashcard> cards,
    required Map<String, TypeProgress> progress,
    required List<String> dueTypes,
    required DateTime today,
    required DateTime start,
    int size = 6,
    Random? random,
  }) {
    final rnd = random ?? Random();
    final introduced = {for (final e in progress.entries) if (e.value.introduced) e.key};
    final recent = {
      for (final id in introduced)
        if (calendarDaysBetween(progress[id]!.introducedOn!, today) < 7) id,
    };
    final limitRecent = calendarDaysBetween(start, today) >= 7;
    final pool = <String, List<Flashcard>>{};
    for (final c in cards) {
      final info = PanikCardInfo.of(c);
      if (info == null || !introduced.contains(info.typeId) || c.isMuted) continue;
      if (info.kind != PanikItemKind.task && info.kind != PanikItemKind.recognize) continue;
      pool.putIfAbsent(info.typeId, () => []).add(c);
    }
    for (final list in pool.values) {
      list.sort((a, b) => (a.lastReview ?? DateTime(2000)).compareTo(b.lastReview ?? DateTime(2000)));
    }
    final picked = <Flashcard>[];
    var recentCount = 0;
    bool take(String typeId, {bool recognize = false}) {
      final list = pool[typeId];
      if (list == null) return false;
      final i = list.indexWhere((c) => (PanikCardInfo.of(c)!.kind == PanikItemKind.recognize) == recognize);
      if (i < 0) return false;
      if (limitRecent && recent.contains(typeId) && (recentCount + 1) * 3 > size) return false;
      picked.add(list.removeAt(i));
      if (recent.contains(typeId)) recentCount++;
      return true;
    }

    for (final id in [...dueTypes]..shuffle(rnd)) {
      if (picked.length >= size) break;
      take(id);
    }
    final others = [...introduced]..shuffle(rnd);
    // Mindestens eine „Verfahren erkennen“-Frage, wenn mehrere Typen da sind.
    if (others.length > 1 && picked.length < size) {
      for (final id in others) {
        if (take(id, recognize: true)) break;
      }
    }
    var guard = 0;
    while (picked.length < size && guard++ < 200) {
      var added = false;
      for (final id in others) {
        if (picked.length >= size) break;
        if (take(id)) added = true;
      }
      if (!added) break;
    }
    // Typen abwechseln: gleiche Typen nicht direkt hintereinander.
    picked.shuffle(rnd);
    for (var i = 1; i < picked.length; i++) {
      final same = PanikCardInfo.of(picked[i])!.typeId == PanikCardInfo.of(picked[i - 1])!.typeId;
      if (!same) continue;
      final j = picked.indexWhere((c) => PanikCardInfo.of(c)!.typeId != PanikCardInfo.of(picked[i])!.typeId, i + 1);
      if (j > 0) {
        final tmp = picked[i];
        picked[i] = picked[j];
        picked[j] = tmp;
      }
    }
    return picked;
  }
}
