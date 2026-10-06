/// Terminierungs-Aufgabe ([QuestionType.gantt] in flashcard.dart): Bauteile
/// und Baugruppen mit ihren Arbeitsgängen (Dauer in Tagen), Start- und
/// Liefertermin, Vorwärts- oder Rückwärtsterminierung. Die Lösung rechnet die
/// App selbst (siehe GanttScheduler) – die KI liest nur Tabelle und Fragen
/// ab. Gespeichert als Map in Flashcard.taskData (`kind: gantt`).
library;

/// Vorwärts (alles so früh wie möglich ab dem Starttermin) oder rückwärts
/// (alles so spät wie möglich bis zum Liefertermin).
enum GanttDirection {
  forward('Vorwärtsterminierung'),
  backward('Rückwärtsterminierung');

  const GanttDirection(this.label);
  final String label;
}

/// Wie gezählt wird: "Tage einschließlich" (ein Arbeitsgang mit 2 Tagen ab
/// Tag 1 endet an Tag 2, Ende = Start + Dauer − 1) oder "Zeitpunkte" (endet
/// zum Zeitpunkt 3, Ende = Start + Dauer).
enum GanttCounting {
  inclusive('Tage einschließlich'),
  points('Zeitpunkte');

  const GanttCounting(this.label);
  final String label;
}

/// Was zu einem Bauteil gefragt ist.
enum GanttAsk {
  start('Start'),
  end('Ende'),

  /// Liegezeit: wie lange ein fertiges Teil auf die Weiterverarbeitung
  /// wartet (bei der fertigen Baugruppe: bis zum Liefertermin).
  slack('Liegezeit'),

  /// Puffer: wie viel später ein Teil höchstens beginnen darf
  /// (spätester − frühester Start).
  buffer('Puffer');

  const GanttAsk(this.label);
  final String label;
}

GanttAsk? ganttAskFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase().trim();
  if (v.isEmpty) return null;
  if (v.contains('liege') || v.contains('slack') || v.contains('wait')) return GanttAsk.slack;
  if (v.contains('puffer') || v.contains('buffer') || v.contains('float')) return GanttAsk.buffer;
  if (v.contains('end') || v.contains('fertig') || v.contains('finish')) return GanttAsk.end;
  if (v.contains('start') || v.contains('beginn') || v.contains('anfang')) return GanttAsk.start;
  return null;
}

/// Ein Arbeitsgang (Drehen, 2 Tage).
class GanttOperation {
  const GanttOperation({required this.name, required this.duration, this.uncertain = false});

  final String name;

  /// Dauer in ganzen Tagen (≥ 1).
  final int duration;

  /// Beim Einlesen unsicher (schlecht lesbar) – bitte prüfen.
  final bool uncertain;

  GanttOperation copyWith({String? name, int? duration, bool? uncertain}) => GanttOperation(
        name: name ?? this.name,
        duration: duration ?? this.duration,
        uncertain: uncertain ?? this.uncertain,
      );

  Map<String, dynamic> toMap() => {'name': name, 'duration': duration, if (uncertain) 'uncertain': true};

  static GanttOperation? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final name = '${raw['name'] ?? raw['title'] ?? raw['arbeitsgang'] ?? raw['operation'] ?? ''}'.trim();
    final d = _int(raw['duration'] ?? raw['dauer'] ?? raw['days'] ?? raw['tage'] ?? raw['zeit']);
    if (name.isEmpty || d == null || d < 1) return null;
    return GanttOperation(name: name, duration: d.clamp(1, 365), uncertain: raw['uncertain'] == true || raw['unsicher'] == true);
  }
}

/// Ein Bauteil oder eine Baugruppe: Arbeitsgänge nacheinander, frühestens
/// nachdem alle [needs] fertig sind.
class GanttItem {
  const GanttItem({required this.id, required this.name, required this.operations, this.needs = const []});

  final String id;
  final String name;
  final List<GanttOperation> operations;

  /// Kennungen der Teile, die vorher fertig sein müssen (bei einer Baugruppe
  /// ihre Bauteile).
  final List<String> needs;

  int get duration => operations.fold(0, (sum, o) => sum + o.duration);
  bool get uncertain => operations.any((o) => o.uncertain);

  GanttItem copyWith({String? name, List<GanttOperation>? operations, List<String>? needs}) => GanttItem(
        id: id,
        name: name ?? this.name,
        operations: operations ?? this.operations,
        needs: needs ?? this.needs,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'operations': [for (final o in operations) o.toMap()],
        if (needs.isNotEmpty) 'needs': needs,
      };
}

/// Eine gefragte Antwort: [ask] zu Teil [itemId].
class GanttQuestion {
  const GanttQuestion({required this.itemId, required this.ask});

  final String itemId;
  final GanttAsk ask;

  String get key => '$itemId.${ask.name}';

  Map<String, dynamic> toMap() => {'item': itemId, 'ask': ask.name};

  @override
  bool operator ==(Object other) => other is GanttQuestion && other.itemId == itemId && other.ask == ask;

  @override
  int get hashCode => Object.hash(itemId, ask);
}

/// Die ganze Terminierungs-Aufgabe.
class GanttTask {
  const GanttTask({
    required this.items,
    this.start = 1,
    this.due,
    this.direction = GanttDirection.forward,
    this.counting = GanttCounting.inclusive,
    this.questions = const [],
    this.drawChart = true,
  });

  /// Teile in der Reihenfolge der Aufgabe; das fertige Erzeugnis (wird von
  /// keinem anderen gebraucht) steht üblicherweise am Ende.
  final List<GanttItem> items;

  /// Starttermin (Tag).
  final int start;

  /// Liefertermin (Tag); nötig für Rückwärtsterminierung, Liegezeit der
  /// fertigen Baugruppe und Puffer.
  final int? due;
  final GanttDirection direction;
  final GanttCounting counting;

  /// Gefragte Antworten. Leer = keine Zahlenfelder, nur das Diagramm.
  final List<GanttQuestion> questions;

  /// Ob das Diagramm gezeichnet (und geprüft) wird.
  final bool drawChart;

  static const kindName = 'gantt';

  GanttItem? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Teile, die von keinem anderen gebraucht werden (meist genau eins: die
  /// fertige Baugruppe).
  List<GanttItem> get finalItems {
    final needed = {for (final i in items) ...i.needs};
    return [
      for (final i in items)
        if (!needed.contains(i.id)) i,
    ];
  }

  /// Teile, die ein anderes Teil braucht.
  List<GanttItem> dependentsOf(String id) => [
        for (final i in items)
          if (i.needs.contains(id)) i,
      ];

  bool get hasUncertain => items.any((i) => i.uncertain);

  /// Gibt es eine gültige Reihenfolge (keine Kreise, alle Verweise bekannt)?
  bool get isValid {
    if (items.isEmpty || items.any((i) => i.operations.isEmpty)) return false;
    final ids = {for (final i in items) i.id};
    if (ids.length != items.length) return false;
    if (items.any((i) => i.needs.any((n) => !ids.contains(n) || n == i.id))) return false;
    return topologicalOrder != null;
  }

  /// Teile so, dass jedes nach allem kommt, was es braucht; `null` bei einem
  /// Kreis.
  List<GanttItem>? get topologicalOrder {
    final done = <String>{};
    final out = <GanttItem>[];
    var progress = true;
    while (out.length < items.length && progress) {
      progress = false;
      for (final i in items) {
        if (done.contains(i.id)) continue;
        if (i.needs.every(done.contains)) {
          done.add(i.id);
          out.add(i);
          progress = true;
        }
      }
    }
    return out.length == items.length ? out : null;
  }

  GanttTask copyWith({
    List<GanttItem>? items,
    int? start,
    int? due,
    bool clearDue = false,
    GanttDirection? direction,
    GanttCounting? counting,
    List<GanttQuestion>? questions,
    bool? drawChart,
  }) =>
      GanttTask(
        items: items ?? this.items,
        start: start ?? this.start,
        due: clearDue ? null : (due ?? this.due),
        direction: direction ?? this.direction,
        counting: counting ?? this.counting,
        questions: questions ?? this.questions,
        drawChart: drawChart ?? this.drawChart,
      );

  /// Alle Unsicher-Markierungen entfernen ("Stimmt so").
  GanttTask confirmed() => copyWith(items: [
        for (final i in items) i.copyWith(operations: [for (final o in i.operations) o.copyWith(uncertain: false)]),
      ]);

  Map<String, dynamic> toMap() => {
        'kind': kindName,
        'items': [for (final i in items) i.toMap()],
        'start': start,
        if (due != null) 'due': due,
        'direction': direction.name,
        'counting': counting.name,
        if (questions.isNotEmpty) 'questions': [for (final q in questions) q.toMap()],
        if (!drawChart) 'drawChart': false,
      };

  /// Die Aufgabe als Text (für KI-Hilfen und die Kartenliste).
  String describe() {
    final b = StringBuffer(direction.label)
      ..write(', Starttermin Tag $start')
      ..write(due == null ? '' : ', Liefertermin Tag $due')
      ..write(' (Zählweise: ${counting.label}).');
    for (final i in items) {
      final needs = [for (final n in i.needs) item(n)?.name ?? n];
      b.write('\n${i.name}${needs.isEmpty ? '' : ' (braucht ${needs.join(', ')})'}: ');
      b.write(i.operations.map((o) => '${o.name} ${o.duration} ${o.duration == 1 ? 'Tag' : 'Tage'}').join(', '));
    }
    if (questions.isNotEmpty) {
      b.write('\nGesucht: ');
      b.write(questions.map((q) => '${q.ask.label} ${item(q.itemId)?.name ?? q.itemId}').join(', '));
    }
    return b.toString();
  }

  /// Tolerant: gespeicherte Daten und KI-Antworten (deutsche Schlüssel,
  /// Teile ohne Kennung, Abhängigkeiten über Namen, Fragen als Text).
  /// `null`, wenn sich keine gültige Aufgabe ergibt.
  static GanttTask? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final rawItems = raw['items'] ?? raw['parts'] ?? raw['teile'] ?? raw['bauteile'];
    if (rawItems is! List) return null;
    final items = <GanttItem>[];
    final usedIds = <String>{};
    final rawNeeds = <List<String>>[];
    for (final (index, r) in rawItems.indexed) {
      if (r is! Map) continue;
      final name = '${r['name'] ?? r['title'] ?? r['bauteil'] ?? ''}'.trim();
      final opsRaw = r['operations'] ?? r['ops'] ?? r['arbeitsgaenge'] ?? r['arbeitsgänge'] ?? r['steps'];
      final ops = [
        for (final o in opsRaw is List ? opsRaw : const [])
          ?GanttOperation.fromMap(o),
      ];
      if (name.isEmpty || ops.isEmpty) continue;
      var id = '${r['id'] ?? ''}'.trim();
      if (id.isEmpty || usedIds.contains(id)) id = 't${index + 1}';
      while (usedIds.contains(id)) {
        id = '${id}x';
      }
      usedIds.add(id);
      final unsure = r['uncertain'] == true || r['unsicher'] == true;
      items.add(GanttItem(
        id: id,
        name: name,
        operations: unsure ? [for (final o in ops) o.copyWith(uncertain: true)] : ops,
      ));
      final needs = r['needs'] ?? r['children'] ?? r['components'] ?? r['braucht'] ?? r['bestandteile'];
      rawNeeds.add([
        for (final n in needs is List ? needs : (needs is String ? needs.split(RegExp(r'[,;+]')) : const []))
          if ('$n'.trim().isNotEmpty) '$n'.trim(),
      ]);
    }
    if (items.isEmpty) return null;
    // Abhängigkeiten über Kennung oder Namen auflösen.
    String? resolve(String ref) {
      for (final i in items) {
        if (i.id == ref) return i.id;
      }
      final lower = ref.toLowerCase();
      for (final i in items) {
        if (i.name.toLowerCase() == lower) return i.id;
      }
      return null;
    }

    final resolved = [
      for (final (k, i) in items.indexed)
        i.copyWith(needs: {
          for (final n in rawNeeds[k])
            if (resolve(n) case final id? when id != i.id) id,
        }.toList()),
    ];
    final start = _int(raw['start'] ?? raw['starttermin'] ?? raw['startDay']) ?? 1;
    final due = _int(raw['due'] ?? raw['liefertermin'] ?? raw['dueDay'] ?? raw['endtermin']);
    final dirText = '${raw['direction'] ?? raw['richtung'] ?? raw['verfahren'] ?? ''}'.toLowerCase();
    final countText = '${raw['counting'] ?? raw['zaehlweise'] ?? raw['zählweise'] ?? ''}'.toLowerCase();
    final questions = <GanttQuestion>[];
    for (final q in raw['questions'] is List ? raw['questions'] as List : const []) {
      if (q is! Map) continue;
      final ask = ganttAskFrom(q['ask'] ?? q['what'] ?? q['frage']);
      final ref = '${q['item'] ?? q['part'] ?? q['bauteil'] ?? ''}'.trim();
      final id = resolve(ref);
      if (ask == null || id == null) continue;
      final question = GanttQuestion(itemId: id, ask: ask);
      if (!questions.contains(question)) questions.add(question);
    }
    final task = GanttTask(
      items: resolved,
      start: start,
      due: due,
      direction: dirText.contains('back') || dirText.contains('rück') || dirText.contains('rueck')
          ? GanttDirection.backward
          : GanttDirection.forward,
      counting: countText.contains('point') || countText.contains('zeitpunkt') || countText.contains('exclusive')
          ? GanttCounting.points
          : GanttCounting.inclusive,
      questions: questions,
      drawChart: raw['drawChart'] != false,
    );
    if (!task.isValid) return null;
    if (task.direction == GanttDirection.backward && task.due == null) return null;
    return task;
  }
}

int? _int(Object? v) {
  if (v is num) return v.round();
  if (v == null) return null;
  final m = RegExp(r'-?\d+').firstMatch('$v');
  return m == null ? null : int.parse(m[0]!);
}
