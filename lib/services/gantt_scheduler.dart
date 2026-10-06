import 'dart:math' as math;

import '../models/gantt_task.dart';

/// Schlüssel eines Arbeitsgangs: Teil + Nummer.
String ganttOpKey(String itemId, int index) => '$itemId#$index';

/// Lage eines Teils im Plan (Tageszellen, beide einschließlich).
class GanttItemResult {
  const GanttItemResult({required this.first, required this.last, this.slack, this.buffer});

  /// Erster belegter Tag (= Starttermin in beiden Zählweisen).
  final int first;

  /// Letzter belegter Tag.
  final int last;

  /// Liegezeit in Tagen (null ohne Liefertermin bei der fertigen Baugruppe).
  final int? slack;

  /// Puffer in Tagen (spätester − frühester Start; null ohne Liefertermin).
  final int? buffer;
}

/// Ergebnis der Terminierung: Start jedes Arbeitsgangs (Tageszelle) und je
/// Teil Anfang, Ende, Liegezeit und Puffer. Ein Arbeitsgang mit Start s und
/// Dauer d belegt die Tage s … s+d−1; bei der Zählweise "Zeitpunkte" ist sein
/// Ende der Zeitpunkt s+d.
class GanttPlan {
  const GanttPlan({
    required this.task,
    required this.direction,
    required this.opStarts,
    required this.items,
    this.problems = const [],
  });

  final GanttTask task;
  final GanttDirection direction;

  /// [ganttOpKey] → erster belegter Tag.
  final Map<String, int> opStarts;
  final Map<String, GanttItemResult> items;

  /// Was am Plan nicht aufgeht (Liefertermin nicht zu halten …).
  final List<String> problems;

  int get _shift => task.counting == GanttCounting.points ? 1 : 0;

  /// Angezeigtes Ende zu einem letzten belegten Tag.
  int displayEnd(int lastCell) => lastCell + _shift;

  /// Letzter Tag, an dem die fertige Baugruppe noch arbeiten darf.
  int? get dueCell => task.due == null ? null : task.due! - _shift;

  /// Die Antwort auf [q] laut diesem Plan.
  int? answer(GanttQuestion q) {
    final r = items[q.itemId];
    if (r == null) return null;
    return switch (q.ask) {
      GanttAsk.start => r.first,
      GanttAsk.end => displayEnd(r.last),
      GanttAsk.slack => r.slack,
      GanttAsk.buffer => r.buffer,
    };
  }

  /// Erster und letzter Tag aller Arbeitsgänge (für die Achse).
  (int, int) get span {
    var lo = task.start, hi = task.start;
    for (final i in task.items) {
      for (var k = 0; k < i.operations.length; k++) {
        final s = opStarts[ganttOpKey(i.id, k)];
        if (s == null) continue;
        lo = math.min(lo, s);
        hi = math.max(hi, s + i.operations[k].duration - 1);
      }
    }
    return (lo, hi);
  }
}

enum BarStatus { ok, follow, bad, missing }

class BarVerdict {
  const BarVerdict(this.status, this.text);

  final BarStatus status;

  /// Begründung (ohne Teil-/Arbeitsgangnamen am Anfang).
  final String text;
}

enum AnswerStatus { ok, follow, bad, empty }

class AnswerVerdict {
  const AnswerVerdict(this.status, {required this.expected, this.own});

  final AnswerStatus status;
  final int? expected;

  /// Was aus dem eigenen Diagramm folgen würde (für Folgefehler).
  final int? own;
}

/// Vorwärts-/Rückwärtsterminierung und Prüfung eines selbst gezeichneten
/// Gantt-Diagramms. Rein und deterministisch – die App rechnet die Lösung
/// selbst, die KI liest nur die Aufgabe ein.
class GanttScheduler {
  GanttScheduler._();

  /// Start je Arbeitsgang und erster/letzter Tag je Teil in [dir].
  static ({Map<String, int> starts, Map<String, (int, int)> spans}) _schedule(GanttTask task, GanttDirection dir) {
    final order = task.topologicalOrder ?? task.items;
    final shift = task.counting == GanttCounting.points ? 1 : 0;
    final dueCell = task.due == null ? null : task.due! - shift;
    final starts = <String, int>{};
    final spans = <String, (int, int)>{};
    if (dir == GanttDirection.forward || dueCell == null) {
      for (final item in order) {
        var t = item.needs.isEmpty ? task.start : item.needs.map((n) => spans[n]!.$2).reduce(math.max) + 1;
        final first = t;
        for (final (k, op) in item.operations.indexed) {
          starts[ganttOpKey(item.id, k)] = t;
          t += op.duration;
        }
        spans[item.id] = (first, t - 1);
      }
    } else {
      for (final item in order.reversed) {
        final dependents = task.dependentsOf(item.id);
        var t = dependents.isEmpty ? dueCell : dependents.map((d) => spans[d.id]!.$1).reduce(math.min) - 1;
        final last = t;
        for (var k = item.operations.length - 1; k >= 0; k--) {
          final s = t - item.operations[k].duration + 1;
          starts[ganttOpKey(item.id, k)] = s;
          t = s - 1;
        }
        spans[item.id] = (t + 1, last);
      }
    }
    return (starts: starts, spans: spans);
  }

  /// Plan in [direction] (Standard: die der Aufgabe). Ohne Liefertermin wird
  /// immer vorwärts geplant.
  static GanttPlan plan(GanttTask task, {GanttDirection? direction}) {
    final shift = task.counting == GanttCounting.points ? 1 : 0;
    final dueCell = task.due == null ? null : task.due! - shift;
    final dir = dueCell == null ? GanttDirection.forward : (direction ?? task.direction);
    final main = _schedule(task, dir);
    final starts = main.starts, spans = main.spans;
    // Puffer = spätester − frühester Start (braucht beide Pläne).
    final other = dueCell == null
        ? null
        : _schedule(task, dir == GanttDirection.forward ? GanttDirection.backward : GanttDirection.forward).spans;
    final items = <String, GanttItemResult>{};
    for (final item in task.items) {
      final (first, last) = spans[item.id]!;
      final dependents = task.dependentsOf(item.id);
      final slack = dependents.isEmpty
          ? (dueCell == null ? null : dueCell - last)
          : dependents.map((d) => spans[d.id]!.$1).reduce(math.min) - last - 1;
      int? buffer;
      if (other != null) {
        final earliest = dir == GanttDirection.forward ? first : other[item.id]!.$1;
        final latest = dir == GanttDirection.forward ? other[item.id]!.$1 : first;
        buffer = latest - earliest;
      }
      items[item.id] = GanttItemResult(first: first, last: last, slack: slack, buffer: buffer);
    }
    final problems = <String>[];
    if (dir == GanttDirection.forward && dueCell != null) {
      for (final f in task.finalItems) {
        final last = spans[f.id]!.$2;
        if (last > dueCell) {
          final late = last - dueCell;
          problems.add('Liefertermin nicht zu halten: ${f.name} ist erst an Tag ${last + shift} fertig, '
              '$late ${late == 1 ? 'Tag' : 'Tage'} zu spät.');
        }
      }
    }
    if (dir == GanttDirection.backward) {
      final early = [
        for (final i in task.items)
          if (spans[i.id]!.$1 < task.start) i,
      ];
      if (early.isNotEmpty) {
        problems.add('Der Starttermin reicht nicht: '
            '${early.map((i) => '${i.name} müsste an Tag ${spans[i.id]!.$1} beginnen').join(', ')}.');
      }
    }
    return GanttPlan(task: task, direction: dir, opStarts: starts, items: items, problems: problems);
  }

  // -------------------------------------------------------------------------
  // Eigenes Diagramm prüfen
  // -------------------------------------------------------------------------

  static int? _userEnd(GanttTask task, Map<String, int?> user, String itemId, int k) {
    final s = user[ganttOpKey(itemId, k)];
    final item = task.item(itemId);
    if (s == null || item == null) return null;
    return s + item.operations[k].duration - 1;
  }

  /// Letzter belegter Tag eines Teils im eigenen Diagramm (alle Arbeitsgänge
  /// gesetzt), sonst null.
  static int? _userLast(GanttTask task, Map<String, int?> user, String itemId) {
    final item = task.item(itemId);
    if (item == null) return null;
    int? last;
    for (var k = 0; k < item.operations.length; k++) {
      final e = _userEnd(task, user, itemId, k);
      if (e == null) return null;
      last = last == null ? e : math.max(last, e);
    }
    return last;
  }

  static int? _userFirst(GanttTask task, Map<String, int?> user, String itemId) {
    final item = task.item(itemId);
    if (item == null) return null;
    int? first;
    for (var k = 0; k < item.operations.length; k++) {
      final s = user[ganttOpKey(itemId, k)];
      if (s == null) return null;
      first = first == null ? s : math.min(first, s);
    }
    return first;
  }

  static String _join(List<String> names) =>
      names.length <= 1 ? names.join() : '${names.sublist(0, names.length - 1).join(', ')} und ${names.last}';

  /// Urteil je Arbeitsgang ([ganttOpKey] → Urteil) für das eigene Diagramm
  /// [user] (Start je Arbeitsgang, null = nicht gesetzt). Ein Balken, der zu
  /// einem eigenen Fehler davor passt, ist ein Folgefehler.
  static Map<String, BarVerdict> judgeBars(GanttTask task, GanttPlan ref, Map<String, int?> user) {
    final shift = task.counting == GanttCounting.points ? 1 : 0;
    final out = <String, BarVerdict>{};
    for (final item in task.items) {
      for (var k = 0; k < item.operations.length; k++) {
        final key = ganttOpKey(item.id, k);
        final p = user[key];
        if (p == null) {
          out[key] = const BarVerdict(BarStatus.missing, 'fehlt noch.');
          continue;
        }
        if (p == ref.opStarts[key]) {
          out[key] = const BarVerdict(BarStatus.ok, 'stimmt.');
          continue;
        }
        out[key] = ref.direction == GanttDirection.forward
            ? _judgeForward(task, user, item, k, p, shift)
            : _judgeBackward(task, ref, user, item, k, p, shift);
      }
    }
    return out;
  }

  static BarVerdict _judgeForward(GanttTask task, Map<String, int?> user, GanttItem item, int k, int p, int shift) {
    if (k == 0 && item.needs.isEmpty) {
      return BarVerdict(BarStatus.bad,
          'beginnt an Tag $p. Vorwärts beginnt jedes Teil ohne Vorgänger am Starttermin, Tag ${task.start}.');
    }
    int? prevEnd;
    String prevName;
    if (k > 0) {
      prevEnd = _userEnd(task, user, item.id, k - 1);
      prevName = item.operations[k - 1].name;
    } else {
      final ends = [for (final n in item.needs) _userLast(task, user, n)];
      prevEnd = ends.contains(null) ? null : ends.whereType<int>().reduce(math.max);
      final latest = prevEnd == null
          ? null
          : item.needs.firstWhere((n) => _userLast(task, user, n) == prevEnd, orElse: () => item.needs.first);
      prevName = latest == null ? _join([for (final n in item.needs) task.item(n)?.name ?? n]) : task.item(latest)?.name ?? latest;
    }
    if (prevEnd == null) {
      return BarVerdict(BarStatus.bad, 'liegt falsch. Plane zuerst ${k > 0 ? prevName : 'alle benötigten Teile'} ein.');
    }
    if (p == prevEnd + 1) {
      return const BarVerdict(BarStatus.follow, 'Folgefehler: schließt richtig an deinen vorherigen Balken an.');
    }
    if (p <= prevEnd) {
      return BarVerdict(
        BarStatus.bad,
        k > 0
            ? 'beginnt an Tag $p, aber $prevName läuft bei dir bis Tag ${prevEnd + shift}.'
            : 'beginnt an Tag $p, aber $prevName ist bei dir erst an Tag ${prevEnd + shift} fertig.',
      );
    }
    return BarVerdict(BarStatus.bad, 'beginnt erst an Tag $p. Vorwärts geht es ohne Lücke weiter, also an Tag ${prevEnd + 1}.');
  }

  static BarVerdict _judgeBackward(
      GanttTask task, GanttPlan ref, Map<String, int?> user, GanttItem item, int k, int p, int shift) {
    final end = p + item.operations[k].duration - 1;
    final last = k == item.operations.length - 1;
    final dependents = task.dependentsOf(item.id);
    if (last && dependents.isEmpty) {
      return BarVerdict(BarStatus.bad,
          'endet an Tag ${end + shift}. Rückwärts endet das fertige Teil genau am Liefertermin, Tag ${task.due}.');
    }
    int? succStart;
    String succName;
    if (!last) {
      succStart = user[ganttOpKey(item.id, k + 1)];
      succName = item.operations[k + 1].name;
    } else {
      final firsts = [for (final d in dependents) _userFirst(task, user, d.id)].whereType<int>().toList();
      succStart = firsts.isEmpty ? null : firsts.reduce(math.min);
      succName = _join([for (final d in dependents) d.name]);
    }
    if (succStart == null) {
      return BarVerdict(BarStatus.bad, 'liegt falsch. Plane zuerst $succName ein – rückwärts geht es von hinten nach vorn.');
    }
    if (end == succStart - 1) {
      return const BarVerdict(BarStatus.follow, 'Folgefehler: endet richtig vor deinem nächsten Balken.');
    }
    if (end >= succStart) {
      return BarVerdict(BarStatus.bad, 'endet an Tag ${end + shift}, aber $succName beginnt bei dir schon an Tag $succStart.');
    }
    return BarVerdict(BarStatus.bad,
        'endet schon an Tag ${end + shift}. Rückwärts endet es direkt vor $succName, also an Tag ${succStart - 1 + shift}.');
  }

  /// Was aus dem eigenen Diagramm für [q] folgt (null, wenn die nötigen
  /// Balken fehlen; Puffer lässt sich aus einem Diagramm nicht ablesen).
  static int? ownAnswer(GanttTask task, Map<String, int?> user, GanttQuestion q) {
    final shift = task.counting == GanttCounting.points ? 1 : 0;
    final first = _userFirst(task, user, q.itemId), last = _userLast(task, user, q.itemId);
    switch (q.ask) {
      case GanttAsk.start:
        return first;
      case GanttAsk.end:
        return last == null ? null : last + shift;
      case GanttAsk.slack:
        if (last == null) return null;
        final dependents = task.dependentsOf(q.itemId);
        if (dependents.isEmpty) return task.due == null ? null : task.due! - shift - last;
        final firsts = [for (final d in dependents) _userFirst(task, user, d.id)];
        if (firsts.contains(null)) return null;
        return firsts.whereType<int>().reduce(math.min) - last - 1;
      case GanttAsk.buffer:
        return null;
    }
  }

  static int? parseAnswer(String? input) {
    final m = RegExp(r'-?\d+').firstMatch(input ?? '');
    return m == null ? null : int.parse(m[0]!);
  }

  /// Urteil je gefragter Antwort ([GanttQuestion.key] → Urteil).
  static Map<String, AnswerVerdict> judgeAnswers(
      GanttTask task, GanttPlan ref, Map<String, int?> user, Map<String, String> answers) {
    return {
      for (final q in task.questions)
        q.key: () {
          final expected = ref.answer(q);
          final own = ownAnswer(task, user, q);
          final value = parseAnswer(answers[q.key]);
          final status = value == null
              ? AnswerStatus.empty
              : value == expected
                  ? AnswerStatus.ok
                  : (own != null && value == own ? AnswerStatus.follow : AnswerStatus.bad);
          return AnswerVerdict(status, expected: expected, own: own);
        }(),
    };
  }

  /// Ein Tipp zum ersten Problem (Balken vor Antworten), ohne gleich die
  /// ganze Lösung zu verraten.
  static String hint(GanttTask task, GanttPlan ref, Map<String, int?> user, Map<String, String> answers) {
    final shift = task.counting == GanttCounting.points ? 1 : 0;
    if (task.drawChart) {
      final bars = judgeBars(task, ref, user);
      final order = ref.direction == GanttDirection.forward
          ? (task.topologicalOrder ?? task.items)
          : (task.topologicalOrder ?? task.items).reversed.toList();
      for (final item in order) {
        final indices = List.generate(item.operations.length, (k) => k);
        for (final k in ref.direction == GanttDirection.forward ? indices : indices.reversed) {
          final v = bars[ganttOpKey(item.id, k)]!;
          if (v.status == BarStatus.ok) continue;
          final op = item.operations[k];
          if (ref.direction == GanttDirection.forward) {
            if (k == 0 && item.needs.isEmpty) {
              return 'Vorwärts beginnt jedes Teil ohne Vorgänger am Starttermin – hier Tag ${task.start}. '
                  'Fang mit ${item.name} · ${op.name} an.';
            }
            if (k > 0) {
              final prevEnd = _userEnd(task, user, item.id, k - 1);
              final prev = item.operations[k - 1].name;
              return prevEnd == null
                  ? 'Plane zuerst $prev ein – ${op.name} schließt direkt daran an.'
                  : '${op.name} (${item.name}) beginnt am Tag nach $prev. $prev endet bei dir an Tag ${prevEnd + shift}.';
            }
            final ends = [
              for (final n in item.needs)
                if (_userLast(task, user, n) case final e?) '${task.item(n)?.name ?? n} an Tag ${e + shift}',
            ];
            return ends.length < item.needs.length
                ? '${item.name} braucht ${_join([for (final n in item.needs) task.item(n)?.name ?? n])}. '
                    'Plane zuerst deren Arbeitsgänge ein.'
                : '${item.name} braucht alle Teile. Bei dir sind fertig: ${_join(ends)} – '
                    '${op.name} beginnt am Tag nach dem spätesten.';
          } else {
            final last = k == item.operations.length - 1;
            final dependents = task.dependentsOf(item.id);
            if (last && dependents.isEmpty) {
              return 'Rückwärts endet das fertige Teil genau am Liefertermin – hier Tag ${task.due}. '
                  'Fang hinten mit ${item.name} · ${op.name} an.';
            }
            if (!last) {
              final next = item.operations[k + 1].name;
              final s = user[ganttOpKey(item.id, k + 1)];
              return s == null
                  ? 'Plane zuerst $next ein – rückwärts geht es von hinten nach vorn.'
                  : '${op.name} (${item.name}) endet direkt vor $next. $next beginnt bei dir an Tag $s.';
            }
            return '${item.name} muss fertig sein, bevor ${_join([for (final d in dependents) d.name])} beginnt – '
                'rückwärts endet es am Tag davor.';
          }
        }
      }
    }
    for (final q in task.questions) {
      final v = judgeAnswers(task, ref, user, answers)[q.key]!;
      if (v.status == AnswerStatus.ok) continue;
      return switch (q.ask) {
        GanttAsk.start || GanttAsk.end => task.drawChart
            ? 'Start und Ende liest du aus deinem Diagramm ab: Beginn des ersten und Ende des letzten Balkens.'
            : 'Rechne die Arbeitsgänge der Reihe nach zusammen: Ende = Start + Dauer${shift == 0 ? ' − 1' : ''}.',
        GanttAsk.slack => task.dependentsOf(q.itemId).isEmpty
            ? 'Liegezeit des fertigen Teils: Wie viele Tage wartet es bis zum Liefertermin? Liefertermin − Ende.'
            : 'Liegezeit eines Teils: Wie viele Tage liegt es fertig herum, bis es weiterverarbeitet wird? '
                'Beginn des nächsten Teils − Ende${shift == 0 ? ' − 1' : ''}.',
        GanttAsk.buffer => 'Puffer: Wie viele Tage später als frühestmöglich darf das Teil beginnen? '
            'Spätester Start (rückwärts) − frühester Start (vorwärts).',
      };
    }
    return 'Alles eingetragen – jetzt prüfen.';
  }

  /// Der Rechenweg in Sätzen ("So rechnet man").
  static List<String> explain(GanttTask task, GanttPlan plan) {
    final shift = task.counting == GanttCounting.points ? 1 : 0;
    String days(int n) => n == 1 ? '1 Tag' : '$n Tage';
    String span(int first, int last) =>
        shift == 0 ? (first == last ? 'Tag $first' : 'Tag $first–$last') : 'Tag $first–${last + 1}';
    final lines = <String>[];
    final order = task.topologicalOrder ?? task.items;
    if (plan.direction == GanttDirection.forward) {
      lines.add('Vorwärts: Teile ohne Vorgänger beginnen am Starttermin, Tag ${task.start}, und alles läuft so früh wie möglich.');
      lines.add(shift == 0
          ? 'Ein Arbeitsgang endet am Tag Start + Dauer − 1, der nächste beginnt am Tag danach.'
          : 'Ein Arbeitsgang endet zum Zeitpunkt Start + Dauer, der nächste beginnt genau dann.');
    } else {
      lines.add('Rückwärts: das fertige Teil endet genau am Liefertermin, Tag ${task.due}, und alles läuft so spät wie möglich.');
      lines.add(shift == 0
          ? 'Ein Arbeitsgang beginnt am Tag Ende − Dauer + 1, der vorige endet am Tag davor.'
          : 'Ein Arbeitsgang beginnt zum Zeitpunkt Ende − Dauer, der vorige endet genau dann.');
    }
    for (final item in plan.direction == GanttDirection.forward ? order : order.reversed) {
      final parts = [
        for (final (k, op) in item.operations.indexed)
          '${op.name} ${span(plan.opStarts[ganttOpKey(item.id, k)]!, plan.opStarts[ganttOpKey(item.id, k)]! + op.duration - 1)}',
      ];
      final r = plan.items[item.id]!;
      final needs = item.needs.isEmpty
          ? ''
          : (plan.direction == GanttDirection.forward
              ? ' (braucht ${_join([for (final n in item.needs) task.item(n)?.name ?? n])}, beginnt nach dem späteren Ende)'
              : '');
      lines.add('${item.name}$needs: ${parts.join(', ')} – von Tag ${r.first} bis Tag ${r.last + shift}.');
    }
    final slackItems = [
      for (final item in task.items)
        if (plan.items[item.id]!.slack != null) item,
    ];
    if (slackItems.isNotEmpty) {
      final parts = <String>[];
      for (final item in slackItems) {
        final r = plan.items[item.id]!;
        final dependents = task.dependentsOf(item.id);
        if (dependents.isEmpty) {
          parts.add('${item.name}: ${task.due} − ${r.last + shift} = ${days(r.slack!)} bis zum Liefertermin');
        } else {
          final next = dependents.map((d) => plan.items[d.id]!.first).reduce(math.min);
          parts.add(shift == 0
              ? '${item.name}: $next − ${r.last} − 1 = ${days(r.slack!)}'
              : '${item.name}: $next − ${r.last + 1} = ${days(r.slack!)}');
        }
      }
      lines.add('Liegezeiten (fertig, aber noch nicht weiterverarbeitet): ${parts.join('; ')}.');
    }
    final buffers = [
      for (final item in task.items)
        if ((plan.items[item.id]!.buffer ?? 0) > 0) '${item.name} ${days(plan.items[item.id]!.buffer!)}',
    ];
    if (task.questions.any((q) => q.ask == GanttAsk.buffer) && buffers.isNotEmpty) {
      lines.add('Puffer (so viel später darf ein Teil beginnen): ${buffers.join(', ')}.');
    }
    return lines;
  }

  /// Die Lösung als lesbarer Text (Rückseite der Karte, KI-Hilfen).
  static String solutionText(GanttTask task) {
    final plan = GanttScheduler.plan(task);
    final b = StringBuffer();
    for (final line in explain(task, plan)) {
      b.writeln(line);
    }
    if (task.questions.isNotEmpty) {
      b.writeln();
      b.write('Antworten: ');
      b.write(task.questions
          .map((q) => '${q.ask.label} ${task.item(q.itemId)?.name ?? q.itemId} = ${plan.answer(q) ?? '–'}')
          .join('; '));
    }
    for (final p in plan.problems) {
      b.writeln();
      b.write('Hinweis: $p');
    }
    return b.toString().trim();
  }

  /// Dieselbe Aufgabe mit anderen Dauern (zum Üben); der Liefertermin wird
  /// bei Bedarf so verschoben, dass er erreichbar bleibt.
  static GanttTask variant(GanttTask task, math.Random random) {
    final items = [
      for (final i in task.items)
        i.copyWith(operations: [
          for (final o in i.operations)
            o.copyWith(duration: math.max(1, o.duration + random.nextInt(5) - 2), uncertain: false),
        ]),
    ];
    var varied = task.copyWith(items: items);
    if (task.due != null) {
      final forward = plan(varied.copyWith(direction: GanttDirection.forward), direction: GanttDirection.forward);
      final shift = task.counting == GanttCounting.points ? 1 : 0;
      final latest = task.finalItems.map((f) => forward.items[f.id]!.last).fold(task.start, math.max) + shift;
      if (task.due! < latest) varied = varied.copyWith(due: latest + 1 + random.nextInt(6));
    }
    return varied;
  }
}
