/// „Vorrechnen“: eine Aufgabe Schritt für Schritt an der Tafel gelöst –
/// jede Umformung sichtbar (was dazukommt grün, was wegfällt rot, woran
/// gearbeitet wird blau), Regeln benannt, auf Wunsch mit simuliertem
/// Taschenrechner. Erzeugt von AiService.solveWorked, gespeichert im Store
/// `worked_solutions` (nur lokal).
library;

/// Wie fein vorgerechnet wird.
enum WorkDetail {
  coarse('Grob', 'nur die Hauptschritte'),
  normal('Regulär', 'jede Umformung ein Schritt'),
  fine('Fein', 'jede Kleinigkeit, Regeln benannt');

  const WorkDetail(this.label, this.hint);

  final String label;
  final String hint;

  static WorkDetail from(Object? raw) {
    final v = '${raw ?? ''}'.toLowerCase();
    for (final d in values) {
      if (d.name == v || d.label.toLowerCase() == v) return d;
    }
    if (v.contains('grob')) return coarse;
    if (v.contains('fein')) return fine;
    return normal;
  }
}

/// Eine benutzte Regel („Logarithmusgesetz: ln(aᵇ) = b·ln(a)“).
class WorkRule {
  const WorkRule({required this.name, this.formula = ''});

  final String name;

  /// LaTeX ohne `$`.
  final String formula;

  Map<String, dynamic> toMap() => {'name': name, if (formula.isNotEmpty) 'formula': formula};

  static WorkRule? fromMap(Object? raw) {
    if (raw is String) return raw.trim().isEmpty ? null : WorkRule(name: raw.trim());
    if (raw is! Map) return null;
    final name = _text(raw['name'] ?? raw['title'] ?? raw['regel']);
    final formula = _latex(raw['formula'] ?? raw['formel'] ?? raw['tex']);
    if (name.isEmpty && formula.isEmpty) return null;
    return WorkRule(name: name.isEmpty ? 'Regel' : name, formula: formula);
  }
}

/// Taschenrechner-Einsatz in einem Schritt: Tastenfolge (Namen siehe
/// CalcKeys), was im Display steht und was herauskommt.
class WorkCalc {
  const WorkCalc({required this.keys, this.input = '', this.expr = '', this.result = '', this.note = ''});

  final List<String> keys;

  /// Eingabe wie im Display (LaTeX).
  final String input;

  /// Dieselbe Rechnung in Eingabe-Schreibweise der App (`2*ln(102)`) – die
  /// App rechnet damit nach.
  final String expr;

  /// Ergebnis wie im Display (LaTeX oder Zahl).
  final String result;
  final String note;

  Map<String, dynamic> toMap() => {
    'keys': keys,
    if (input.isNotEmpty) 'input': input,
    if (expr.isNotEmpty) 'expr': expr,
    if (result.isNotEmpty) 'result': result,
    if (note.isNotEmpty) 'note': note,
  };

  static WorkCalc? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final keysRaw = raw['keys'] ?? raw['tasten'];
    final parts = keysRaw is List
        ? [for (final k in keysRaw) '$k']
        : (keysRaw is String ? keysRaw.split(RegExp(r'[\s,]+')) : const <String>[]);
    final keys = [
      for (final k in parts)
        if (k.trim().isNotEmpty) k.trim(),
    ];
    if (keys.isEmpty) return null;
    return WorkCalc(
      keys: keys,
      input: _latex(raw['input'] ?? raw['display']),
      expr: _text(raw['expr'] ?? raw['expression']),
      result: _latex(raw['result'] ?? raw['ergebnis']),
      note: _text(raw['note'] ?? raw['hinweis']),
    );
  }
}

/// Ein Schritt an der Tafel. Die Zeilen sind LaTeX (ohne `$`); [work] darf
/// `\add{…}` (kommt dazu, grün), `\del{…}` (fällt weg, rot) und `\focus{…}`
/// (wird bearbeitet, blau) enthalten, [to] `\focus{…}`.
class WorkStep {
  const WorkStep({
    required this.title,
    this.say = '',
    this.from = '',
    this.op = '',
    this.work = '',
    this.to = '',
    this.rule,
    this.calc,
  });

  final String title;

  /// Erklärung (Du-Form, Formeln in `$…$`).
  final String say;

  /// Zeile vor dem Schritt – leer = das [to] des vorigen Schritts.
  final String from;

  /// Umformung rechts neben der Gleichung („-5x“ → „| −5x“).
  final String op;
  final String work;
  final String to;
  final WorkRule? rule;
  final WorkCalc? calc;

  /// Hat der Schritt eine eigene Zeile an der Tafel?
  bool get hasLine => to.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
    'title': title,
    if (say.isNotEmpty) 'say': say,
    if (from.isNotEmpty) 'from': from,
    if (op.isNotEmpty) 'op': op,
    if (work.isNotEmpty) 'work': work,
    if (to.isNotEmpty) 'to': to,
    if (rule != null) 'rule': rule!.toMap(),
    if (calc != null) 'calc': calc!.toMap(),
  };

  static WorkStep? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final step = WorkStep(
      title: _text(raw['title'] ?? raw['titel'] ?? raw['name']),
      say: _text(raw['say'] ?? raw['explain'] ?? raw['text'] ?? raw['erklaerung'] ?? raw['erklärung']),
      from: _latex(raw['from'] ?? raw['before'] ?? raw['vorher']),
      op: _latex(raw['op'] ?? raw['operation'] ?? raw['umformung']),
      work: _latex(raw['work'] ?? raw['during'] ?? raw['markiert']),
      to: _latex(raw['to'] ?? raw['after'] ?? raw['nachher'] ?? raw['result']),
      rule: WorkRule.fromMap(raw['rule'] ?? raw['regel']),
      calc: WorkCalc.fromMap(raw['calc'] ?? raw['taschenrechner']),
    );
    if (step.title.isEmpty && step.say.isEmpty && step.to.isEmpty && step.from.isEmpty) return null;
    return step;
  }
}

class WorkedSolution {
  const WorkedSolution({
    required this.id,
    required this.moduleId,
    required this.problem,
    required this.detail,
    required this.steps,
    required this.createdAt,
    this.title = '',
    this.answer = '',
    this.cardId,
    this.withCalculator = true,
  });

  final String id;
  final String moduleId;

  /// Die Aufgabe, wie sie gestellt wurde (Text mit `$…$`).
  final String problem;
  final WorkDetail detail;
  final List<WorkStep> steps;
  final DateTime createdAt;
  final String title;

  /// Endergebnis (LaTeX).
  final String answer;

  /// Aus einer Rechenweg-Karte vorgerechnet.
  final String? cardId;
  final bool withCalculator;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final p = problem.replaceAll(RegExp(r'\s+'), ' ').trim();
    return p.length > 70 ? '${p.substring(0, 69)}…' : p;
  }

  WorkedSolution copyWith({List<WorkStep>? steps}) => WorkedSolution(
    id: id,
    moduleId: moduleId,
    problem: problem,
    detail: detail,
    steps: steps ?? this.steps,
    createdAt: createdAt,
    title: title,
    answer: answer,
    cardId: cardId,
    withCalculator: withCalculator,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'moduleId': moduleId,
    'problem': problem,
    'detail': detail.name,
    'steps': [for (final s in steps) s.toMap()],
    'createdAt': createdAt.toIso8601String(),
    if (title.isNotEmpty) 'title': title,
    if (answer.isNotEmpty) 'answer': answer,
    if (cardId != null) 'cardId': cardId,
    'withCalculator': withCalculator,
  };

  static WorkedSolution? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = _text(raw['id']);
    if (id.isEmpty) return null;
    return WorkedSolution(
      id: id,
      moduleId: _text(raw['moduleId']),
      problem: '${raw['problem'] ?? ''}',
      detail: WorkDetail.from(raw['detail']),
      steps: [for (final s in (raw['steps'] is List ? raw['steps'] as List : const [])) ?WorkStep.fromMap(s)],
      createdAt: DateTime.tryParse('${raw['createdAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      title: _text(raw['title']),
      answer: _latex(raw['answer']),
      cardId: raw['cardId'] == null ? null : '${raw['cardId']}',
      withCalculator: raw['withCalculator'] != false,
    );
  }

  /// Antwort der KI ({"title", "steps", "answer"}) → Lösung. Fehlt "from" im
  /// ersten Schritt, bleibt die Tafel bis zum ersten Ergebnis leer.
  static WorkedSolution fromAi(
    Map<String, dynamic> json, {
    required String id,
    required String moduleId,
    required String problem,
    required WorkDetail detail,
    required DateTime now,
    String? cardId,
    bool withCalculator = true,
  }) {
    final rawSteps = json['steps'] ?? json['schritte'];
    return WorkedSolution(
      id: id,
      moduleId: moduleId,
      problem: problem,
      detail: detail,
      steps: [for (final s in (rawSteps is List ? rawSteps : const [])) ?WorkStep.fromMap(s)],
      createdAt: now,
      title: _text(json['title'] ?? json['titel']),
      answer: _latex(json['answer'] ?? json['ergebnis']),
      cardId: cardId,
      withCalculator: withCalculator,
    );
  }
}

String _text(Object? raw) => raw == null ? '' : '$raw'.trim();

/// LaTeX ohne umschließende `$` / `$$` / `\(…\)`.
String _latex(Object? raw) {
  var s = _text(raw);
  if (s.startsWith(r'$$') && s.endsWith(r'$$') && s.length > 4) s = s.substring(2, s.length - 2);
  if (s.startsWith(r'$') && s.endsWith(r'$') && s.length > 2) s = s.substring(1, s.length - 1);
  if (s.startsWith(r'\(') && s.endsWith(r'\)')) s = s.substring(2, s.length - 2);
  return s.trim();
}
