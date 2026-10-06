/// Rechenweg-Aufgabe ([QuestionType.steps] in flashcard.dart): eine Aufgabe
/// aus dem Übungsblatt (Text in Flashcard.front), zerlegt in Schritte mit
/// erwarteten Antworten. Die App prüft jede Antwort selbst (siehe
/// StepChecker): Formeln durch Einsetzen an Stützstellen, Zahlen mit
/// Toleranz, Auswahl direkt – die KI liefert nur Struktur, Lösung und typische
/// Fehler. Gespeichert als Map in Flashcard.taskData (`kind: steps`).
library;

/// Was in ein Feld eingegeben wird.
enum StepFieldKind {
  /// Ein Term mit Größen (`-1/u`, `x - sqrt(12 - 2x)`).
  formula,

  /// Eine Zahl (auch als Rechnung: `24/2`, `pi*sqrt(3)/8`).
  number,
}

StepFieldKind stepFieldKindFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase();
  if (v.contains('num') || v.contains('zahl') || v.contains('wert') || v == 'value') return StepFieldKind.number;
  return StepFieldKind.formula;
}

/// Ein typischer Fehler mit eigener Rückmeldung ("Vorzeichen in der Klammer
/// vergessen").
class StepMistake {
  const StepMistake({required this.answer, required this.feedback});

  final String answer;
  final String feedback;

  Map<String, dynamic> toMap() => {'answer': answer, 'feedback': feedback};

  static StepMistake? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final answer = _text(raw['answer'] ?? raw['wrong'] ?? raw['input'] ?? raw['falsch'] ?? raw['eingabe']);
    final feedback = _text(raw['feedback'] ?? raw['hint'] ?? raw['message'] ?? raw['rueckmeldung'] ?? raw['rückmeldung']);
    if (answer.isEmpty) return null;
    return StepMistake(answer: answer, feedback: feedback.isEmpty ? 'Das ist ein typischer Fehler – prüf den Schritt noch einmal.' : feedback);
  }
}

/// Ein Eingabefeld eines Schritts, z.B. "u′ =" mit erwarteter Antwort `-1/u`.
class StepField {
  const StepField({
    required this.label,
    required this.answer,
    this.kind = StepFieldKind.formula,
    this.variables = const [],
    this.constants = const [],
    this.tolerance,
    this.mistakes = const [],
    this.domain = const {},
  });

  /// Was vor dem Feld steht ("$u' =$", "C ="); LaTeX erlaubt.
  final String label;
  final StepFieldKind kind;

  /// Erwartete Antwort in Eingabe-Schreibweise (`-1/u`) – LaTeX wird auch
  /// gelesen (siehe MathExpression).
  final String answer;

  /// Größen, die in der Antwort vorkommen dürfen (leer = die der erwarteten
  /// Antwort ohne [constants]).
  final List<String> variables;

  /// Frei wählbare Konstanten (Integrationskonstante C): jede Schreibweise
  /// derselben Lösungsschar zählt (C − 2x, 2(K − x) …).
  final List<String> constants;

  /// Relative Toleranz bei Zahlen (0.01 = 1 %); null = exakt bzw. richtig
  /// gerundet.
  final double? tolerance;
  final List<StepMistake> mistakes;

  /// Bereich je Größe, in dem eingesetzt wird (z.B. x < 6 bei √(12 − 2x)).
  final Map<String, (double, double)> domain;

  Set<String> get declaredNames => {...variables, ...constants};

  StepField copyWith({String? label, String? answer, StepFieldKind? kind, List<StepMistake>? mistakes}) => StepField(
        label: label ?? this.label,
        answer: answer ?? this.answer,
        kind: kind ?? this.kind,
        variables: variables,
        constants: constants,
        tolerance: tolerance,
        mistakes: mistakes ?? this.mistakes,
        domain: domain,
      );

  Map<String, dynamic> toMap() => {
        'label': label,
        'kind': kind.name,
        'answer': answer,
        if (variables.isNotEmpty) 'variables': variables,
        if (constants.isNotEmpty) 'constants': constants,
        if (tolerance != null) 'tolerance': tolerance,
        if (mistakes.isNotEmpty) 'mistakes': [for (final m in mistakes) m.toMap()],
        if (domain.isNotEmpty) 'domain': {for (final e in domain.entries) e.key: [e.value.$1, e.value.$2]},
      };

  static StepField? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final answer = _text(raw['answer'] ?? raw['expected'] ?? raw['solution'] ?? raw['loesung'] ?? raw['lösung'] ?? raw['value']);
    if (answer.isEmpty) return null;
    final tolerance = _number(raw['tolerance'] ?? raw['tol']);
    return StepField(
      label: _text(raw['label'] ?? raw['name'] ?? raw['prefix']),
      kind: stepFieldKindFrom(raw['kind'] ?? raw['type']),
      answer: answer,
      variables: _names(raw['variables'] ?? raw['vars']),
      constants: _names(raw['constants'] ?? raw['konstanten']),
      tolerance: tolerance == null || tolerance <= 0 ? null : tolerance,
      mistakes: [
        for (final m in _list(raw['mistakes'] ?? raw['typicalMistakes'] ?? raw['fehler']))
          ?StepMistake.fromMap(m),
      ],
      domain: _domain(raw['domain'] ?? raw['bereich']),
    );
  }
}

/// Eine Antwortmöglichkeit eines Auswahl-Schritts.
class StepOption {
  const StepOption({required this.text, this.correct = false, this.feedback = ''});

  final String text;
  final bool correct;
  final String feedback;

  Map<String, dynamic> toMap() => {'text': text, 'correct': correct, if (feedback.isNotEmpty) 'feedback': feedback};

  static StepOption? fromMap(Object? raw) {
    if (raw is String) return raw.trim().isEmpty ? null : StepOption(text: raw.trim());
    if (raw is! Map) return null;
    final text = _text(raw['text'] ?? raw['option'] ?? raw['label']);
    if (text.isEmpty) return null;
    final c = raw['correct'] ?? raw['isCorrect'] ?? raw['richtig'];
    return StepOption(
      text: text,
      correct: c == true || c == 1 || '$c'.toLowerCase() == 'true',
      feedback: _text(raw['feedback'] ?? raw['why'] ?? raw['hint']),
    );
  }
}

/// Ein Schritt: entweder eine Auswahl ([options]) oder ein oder mehrere
/// Eingabefelder ([fields]).
class TaskStep {
  const TaskStep({
    required this.title,
    this.prompt = '',
    this.fields = const [],
    this.options = const [],
    this.hints = const [],
    this.result = '',
    this.explanation = '',
  });

  final String title;

  /// Die Frage dieses Schritts ("Leite u = x − y ab und setze die DGL ein.").
  final String prompt;
  final List<StepField> fields;
  final List<StepOption> options;

  /// Bis zu zwei gestufte Tipps, danach "Schritt zeigen".
  final List<String> hints;

  /// Das Ergebnis des Schritts zum Anzeigen ("$u' = -\frac{1}{u}$").
  final String result;

  /// Wie man darauf kommt – nach "Schritt zeigen" bzw. dem Lösen.
  final String explanation;

  bool get isChoice => options.isNotEmpty;

  /// Ergebnis zum Anzeigen: [result], sonst die Felder mit ihren Antworten.
  String get resultText {
    if (result.trim().isNotEmpty) return result;
    if (isChoice) return options.where((o) => o.correct).map((o) => o.text).join(' / ');
    return fields.map((f) => '${f.label} ${f.answer}'.trim()).join(',  ');
  }

  TaskStep copyWith({
    String? title,
    String? prompt,
    List<StepField>? fields,
    List<StepOption>? options,
    List<String>? hints,
    String? result,
    String? explanation,
  }) =>
      TaskStep(
        title: title ?? this.title,
        prompt: prompt ?? this.prompt,
        fields: fields ?? this.fields,
        options: options ?? this.options,
        hints: hints ?? this.hints,
        result: result ?? this.result,
        explanation: explanation ?? this.explanation,
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        if (prompt.isNotEmpty) 'prompt': prompt,
        if (fields.isNotEmpty) 'fields': [for (final f in fields) f.toMap()],
        if (options.isNotEmpty) 'options': [for (final o in options) o.toMap()],
        if (hints.isNotEmpty) 'hints': hints,
        if (result.isNotEmpty) 'result': result,
        if (explanation.isNotEmpty) 'explanation': explanation,
      };

  static TaskStep? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final fields = [
      for (final f in _list(raw['fields'] ?? raw['inputs'] ?? raw['felder']))
        ?StepField.fromMap(f),
    ];
    // Ein einzelnes Feld direkt am Schritt (answer/label/kind).
    if (fields.isEmpty && raw['answer'] != null && raw['options'] == null && raw['choices'] == null) {
      if (StepField.fromMap(raw) case final field?) fields.add(field);
    }
    final rawOptions = _list(raw['options'] ?? raw['choices'] ?? raw['auswahl']);
    var options = [
      for (final o in rawOptions)
        ?StepOption.fromMap(o),
    ];
    // Richtige Option als Index/Text statt als Markierung an der Option.
    final correct = raw['correctIndex'] ?? raw['answerIndex'] ?? raw['correctOption'];
    if (options.isNotEmpty && !options.any((o) => o.correct) && correct != null) {
      final index = correct is num ? correct.toInt() : int.tryParse('$correct');
      options = [
        for (final (i, o) in options.indexed)
          StepOption(text: o.text, feedback: o.feedback, correct: index != null ? i == index : o.text == '$correct'),
      ];
    }
    final title = _text(raw['title'] ?? raw['titel'] ?? raw['name']);
    final prompt = _text(raw['prompt'] ?? raw['question'] ?? raw['frage'] ?? raw['aufgabe']);
    if (fields.isEmpty && options.isEmpty) return null;
    return TaskStep(
      title: title.isEmpty ? (prompt.isEmpty ? 'Schritt' : prompt) : title,
      prompt: prompt,
      fields: options.isEmpty ? fields : const [],
      options: options,
      hints: [
        for (final h in _list(raw['hints'] ?? raw['tipps'] ?? raw['hint'] ?? raw['tipp']))
          if (_text(h).isNotEmpty) _text(h),
      ].take(3).toList(),
      result: _text(raw['result'] ?? raw['ergebnis']),
      explanation: _text(raw['explanation'] ?? raw['erklaerung'] ?? raw['erklärung'] ?? raw['loesungsweg'] ?? raw['lösungsweg']),
    );
  }
}

/// Wie das Endergebnis unabhängig von der Musterlösung geprüft wird.
enum StepProbeKind {
  /// Gewöhnliche DGL: y' = f(x, y) (bzw. y'' = f(x, y, y')) plus
  /// Anfangsbedingungen – die App setzt das Ergebnis ein.
  ode,

  /// Stammfunktion: F' = f.
  antiderivative,
}

/// Eine Anfangsbedingung y(x) = value bzw. y'(x) = value.
class ProbeCondition {
  const ProbeCondition({required this.x, required this.value, this.derivative = 0});

  final double x;
  final double value;
  final int derivative;

  Map<String, dynamic> toMap() => {'x': x, 'value': value, if (derivative > 0) 'derivative': derivative};

  static ProbeCondition? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final x = _number(raw['x'] ?? raw['at'] ?? raw['stelle']);
    final value = _number(raw['value'] ?? raw['y'] ?? raw['wert']);
    if (x == null || value == null) return null;
    final d = _number(raw['derivative'] ?? raw['ableitung'] ?? raw['order']);
    return ProbeCondition(x: x, value: value, derivative: (d ?? 0).clamp(0, 1).toInt());
  }
}

/// Probe des Endergebnisses (siehe [StepProbeKind]).
class StepProbe {
  const StepProbe({
    required this.kind,
    required this.equation,
    this.variable = 'x',
    this.function = 'y',
    this.order = 1,
    this.conditions = const [],
    this.domain,
  });

  final StepProbeKind kind;

  /// Rechte Seite der DGL in [variable], [function] (und `y'` bei 2. Ordnung)
  /// bzw. der Integrand.
  final String equation;
  final String variable;
  final String function;
  final int order;
  final List<ProbeCondition> conditions;

  /// Wo eingesetzt wird (z.B. (-10, 5.9) bei x < 6).
  final (double, double)? domain;

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'equation': equation,
        'variable': variable,
        'function': function,
        if (order != 1) 'order': order,
        if (conditions.isNotEmpty) 'conditions': [for (final c in conditions) c.toMap()],
        if (domain != null) 'domain': [domain!.$1, domain!.$2],
      };

  static StepProbe? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final equation = _text(raw['equation'] ?? raw['rhs'] ?? raw['f'] ?? raw['integrand'] ?? raw['dgl']);
    if (equation.isEmpty) return null;
    final kindText = _text(raw['kind'] ?? raw['type']).toLowerCase();
    final kind = kindText.contains('anti') || kindText.contains('stamm') || kindText.contains('integr')
        ? StepProbeKind.antiderivative
        : StepProbeKind.ode;
    final rawConditions = raw['conditions'] ?? raw['initial'] ?? raw['anfangswerte'] ?? raw['anfangsbedingung'];
    final domain = _range(raw['domain'] ?? raw['bereich']);
    final variable = _text(raw['variable'] ?? raw['var']);
    final function = _text(raw['function'] ?? raw['funktion']);
    final order = _number(raw['order'] ?? raw['ordnung'])?.toInt() ?? 1;
    final conditions = [
      for (final c in rawConditions is Map ? [rawConditions] : _list(rawConditions))
        ?ProbeCondition.fromMap(c),
    ];
    // Anfangswert flach an der Probe: {"x0": 4, "y0": 2}.
    final x0 = _number(raw['x0']), y0 = _number(raw['y0']);
    if (conditions.isEmpty && x0 != null && y0 != null) conditions.add(ProbeCondition(x: x0, value: y0));
    return StepProbe(
      kind: kind,
      equation: equation,
      variable: variable.isEmpty ? 'x' : variable,
      function: function.isEmpty ? 'y' : function,
      order: order.clamp(1, 2),
      conditions: conditions,
      domain: domain,
    );
  }
}

/// Die ganze Rechenweg-Aufgabe.
class StepTask {
  const StepTask({required this.steps, this.probe, this.domainNote = '', this.finalLabel = ''});

  final List<TaskStep> steps;
  final StepProbe? probe;

  /// Wo die Lösung gilt ("für x < 6").
  final String domainNote;

  /// Beschriftung des Ergebnisfelds im Modus "Nur Ergebnis" (leer = die des
  /// letzten Felds).
  final String finalLabel;

  static const kindName = 'steps';

  /// Das Endergebnis: das letzte Eingabefeld des letzten Schritts mit Feldern.
  StepField? get finalField {
    for (final step in steps.reversed) {
      if (step.fields.isNotEmpty) return step.fields.last;
    }
    return null;
  }

  /// Hat die Aufgabe etwas Prüfbares? Jeder Auswahl-Schritt braucht eine
  /// richtige Option.
  bool get isUsable =>
      steps.isNotEmpty && steps.every((s) => s.isChoice ? s.options.any((o) => o.correct) : s.fields.isNotEmpty);

  StepTask copyWith({List<TaskStep>? steps, String? domainNote}) =>
      StepTask(steps: steps ?? this.steps, probe: probe, domainNote: domainNote ?? this.domainNote, finalLabel: finalLabel);

  Map<String, dynamic> toMap() => {
        'kind': kindName,
        'steps': [for (final s in steps) s.toMap()],
        if (probe != null) 'probe': probe!.toMap(),
        if (domainNote.isNotEmpty) 'domainNote': domainNote,
        if (finalLabel.isNotEmpty) 'finalLabel': finalLabel,
      };

  /// Tolerant: gespeicherte Daten und KI-Antworten (fehlende Felder,
  /// deutsche Schlüssel, einzelnes Feld am Schritt). `null`, wenn kein
  /// einziger Schritt brauchbar ist.
  static StepTask? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final steps = [
      for (final s in _list(raw['steps'] ?? raw['schritte']))
        ?TaskStep.fromMap(s),
    ];
    if (steps.isEmpty) return null;
    return StepTask(
      steps: steps,
      probe: StepProbe.fromMap(raw['probe'] ?? raw['check']),
      domainNote: _text(raw['domainNote'] ?? raw['definitionsbereich'] ?? raw['gueltigkeit']),
      finalLabel: _text(raw['finalLabel']),
    );
  }
}

// ---------------------------------------------------------------------------
// Tolerantes Lesen
// ---------------------------------------------------------------------------

String _text(Object? v) {
  if (v == null) return '';
  if (v is List) return v.map(_text).where((s) => s.isNotEmpty).join(' ');
  return '$v'.trim();
}

double? _number(Object? v) {
  if (v is num) return v.toDouble();
  if (v == null) return null;
  return double.tryParse('$v'.trim().replaceAll(',', '.'));
}

List<Object?> _list(Object? v) {
  if (v is List) return v;
  if (v == null) return const [];
  if (v is String && v.trim().isNotEmpty) return [v];
  return const [];
}

List<String> _names(Object? v) {
  final items = v is String ? v.split(RegExp(r'[,;\s]+')) : _list(v).map(_text);
  return [
    for (final n in items)
      if (n.trim().isNotEmpty) n.trim().replaceAll(r'$', ''),
  ];
}

(double, double)? _range(Object? v) {
  if (v is List && v.length >= 2) {
    final a = _number(v[0]), b = _number(v[1]);
    if (a != null && b != null && a != b) return a < b ? (a, b) : (b, a);
  }
  if (v is Map) {
    final a = _number(v['min'] ?? v['from'] ?? v['von']), b = _number(v['max'] ?? v['to'] ?? v['bis']);
    if (a != null && b != null && a != b) return a < b ? (a, b) : (b, a);
  }
  return null;
}

Map<String, (double, double)> _domain(Object? v) {
  if (v is! Map) return const {};
  return {
    for (final e in v.entries)
      '${e.key}': ?_range(e.value),
  };
}
