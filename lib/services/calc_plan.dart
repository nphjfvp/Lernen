import 'calc_engine.dart';

/// Eine gegebene Größe der Rechnung: aus dem Aufgabentext, einer Tabelle oder
/// einem Bild gelesen, oder eine Konstante.
class CalcGiven {
  const CalcGiven({
    required this.symbol,
    required this.values,
    this.name = '',
    this.raw = '',
    this.unit = '',
    this.uncertain = false,
    this.isConstant = false,
  });

  final String symbol;
  final String name;

  /// So, wie es im Bild bzw. Text stand ("4,7 kΩ") – zum Nachprüfen.
  final String raw;

  /// Der Wert in der Grundeinheit ([unit]); eine Reihe bei mehreren Messungen.
  final CalcVec values;
  final String unit;

  /// Die KI war beim Lesen unsicher (schlecht lesbar, Schätzung).
  final bool uncertain;
  final bool isConstant;

  CalcGiven withValues(CalcVec next) => CalcGiven(
        symbol: symbol,
        name: name,
        raw: raw,
        values: next,
        unit: unit,
        // Wer den Wert selbst eingibt, hat ihn geprüft.
        uncertain: false,
        isConstant: isConstant,
      );

  /// Als Text zum Bearbeiten: ein Wert, oder mehrere mit `; ` getrennt.
  String get valuesText => values.map((v) => CalcEngine.format(v, sig: 7)).join('; ');
}

/// Ein Rechenschritt: eine Größe, die sich aus den gegebenen und früheren
/// Größen ergibt.
class CalcStep {
  const CalcStep({
    required this.symbol,
    required this.expression,
    this.name = '',
    this.latex = '',
    this.unit = '',
    this.explanation = '',
  });

  final String symbol;
  final String name;

  /// Die Formel für die Anzeige (LaTeX ohne Dollarzeichen).
  final String latex;

  /// Die Formel zum Rechnen (siehe [CalcEngine]).
  final String expression;
  final String unit;
  final String explanation;
}

/// Das Ergebnis eines Schritts nach dem Auswerten.
class CalcStepResult {
  const CalcStepResult({
    required this.step,
    this.values,
    this.error,
    this.substitution,
    this.inputs = const {},
  });

  final CalcStep step;
  final CalcVec? values;
  final String? error;

  /// Der Ausdruck mit eingesetzten Werten – nur bei Schritten, in denen alle
  /// Größen einzelne Werte sind.
  final String? substitution;

  /// Die Größen, die der Schritt verwendet (Name → Werte), für die Tabelle bei
  /// Messreihen.
  final Map<String, CalcVec> inputs;

  bool get ok => error == null && values != null;

  String get valueText => values == null ? '' : _valueText(values!, step.unit);

  static String _valueText(CalcVec v, String unit) {
    final u = unit.trim().isEmpty ? '' : ' ${unit.trim()}';
    if (v.length == 1) return '${CalcEngine.format(v.first)}$u';
    return '[${v.map(CalcEngine.format).join('; ')}]$u';
  }
}

/// Der Rechenplan, den die KI aus Werten, Text und Bildern aufstellt (siehe
/// AiService.planCalculation): gegebene Größen, Schritte mit Formeln, Annahmen.
/// Gerechnet wird NICHT von der KI, sondern hier ([evaluate]) – so stimmen die
/// Zahlen, und ein korrigierter Eingabewert rechnet sofort neu.
class CalcPlan {
  const CalcPlan({
    this.title = '',
    this.given = const [],
    this.steps = const [],
    this.finals = const [],
    this.assumptions = const [],
    this.notes = const [],
    this.missing = const [],
    this.problems = const [],
  });

  final String title;
  final List<CalcGiven> given;
  final List<CalcStep> steps;

  /// Die Größen, die das Endergebnis sind (Reihenfolge wie angezeigt). Leer =
  /// der letzte Schritt.
  final List<String> finals;
  final List<String> assumptions;
  final List<String> notes;

  /// Was fehlt, um die Aufgabe ganz zu lösen.
  final List<String> missing;

  /// Was beim Einlesen der KI-Antwort nicht brauchbar war.
  final List<String> problems;

  bool get isEmpty => given.isEmpty && steps.isEmpty;

  CalcPlan withGiven(String symbol, CalcVec values) => CalcPlan(
        title: title,
        given: [for (final g in given) g.symbol == symbol ? g.withValues(values) : g],
        steps: steps,
        finals: finals,
        assumptions: assumptions,
        notes: notes,
        missing: missing,
        problems: problems,
      );

  /// Die Größen der Endergebnisse (bei leerer Angabe der letzte Schritt).
  List<String> get finalSymbols =>
      finals.isNotEmpty ? finals : (steps.isEmpty ? const [] : [steps.last.symbol]);

  /// Rechnet alle Schritte durch. Ein fehlgeschlagener Schritt steht mit
  /// Fehlermeldung im Ergebnis; Schritte, die ihn brauchen, scheitern mit dem
  /// Hinweis darauf.
  List<CalcStepResult> evaluate() {
    final vars = <String, CalcVec>{for (final g in given) g.symbol: g.values};
    final units = <String, String>{for (final g in given) g.symbol: g.unit};
    final failed = <String>{};
    final results = <CalcStepResult>[];
    for (final step in steps) {
      try {
        if (!CalcEngine.isValidSymbol(step.symbol)) {
          throw CalcException('„${step.symbol}“ ist kein gültiger Name für eine Größe.');
        }
        final used = CalcEngine.variablesOf(step.expression, known: vars.keys.toSet());
        final broken = used.where(failed.contains).toList();
        if (broken.isNotEmpty) {
          throw CalcException('Hängt von ${broken.map((b) => '„$b“').join(', ')} ab – dort ging etwas schief.');
        }
        final values = CalcEngine.evaluate(step.expression, vars);
        final inputs = {
          for (final name in used)
            if (vars[name] != null) name: vars[name]!,
        };
        String? substitution;
        if (inputs.values.every((v) => v.length == 1)) {
          substitution = CalcEngine.substitute(step.expression, {
            for (final e in inputs.entries) e.key: _withUnit(e.value.first, units[e.key] ?? ''),
          });
        }
        vars[step.symbol] = values;
        units[step.symbol] = step.unit;
        failed.remove(step.symbol);
        results.add(CalcStepResult(step: step, values: values, substitution: substitution, inputs: inputs));
      } on CalcException catch (e) {
        failed.add(step.symbol);
        results.add(CalcStepResult(step: step, error: e.message));
      } catch (_) {
        // Darf nie die ganze Rechnung kosten – nur diesen Schritt.
        failed.add(step.symbol);
        results.add(CalcStepResult(step: step, error: 'Dieser Schritt lässt sich nicht berechnen.'));
      }
    }
    return results;
  }

  static String _withUnit(double v, String unit) {
    final text = CalcEngine.format(v);
    final u = unit.trim();
    return u.isEmpty ? text : '$text $u';
  }

  /// Der Rechenweg als reiner Text (Kopieren, Notizen, Berichtsentwurf).
  String asText(List<CalcStepResult> results) {
    final b = StringBuffer();
    if (title.trim().isNotEmpty) b.writeln('Rechnung: ${title.trim()}');
    if (given.isNotEmpty) {
      b.writeln('Gegeben:');
      for (final g in given) {
        final unit = g.unit.trim().isEmpty ? '' : ' ${g.unit.trim()}';
        final value = g.values.length == 1
            ? CalcEngine.format(g.values.first)
            : '[${g.values.map(CalcEngine.format).join('; ')}]';
        b.writeln('  ${g.symbol} = $value$unit${g.name.trim().isEmpty ? '' : ' (${g.name.trim()})'}');
      }
    }
    if (results.isNotEmpty) b.writeln('Rechenweg:');
    var n = 1;
    for (final r in results) {
      final head = '  ${n++}) ${r.step.name.trim().isEmpty ? r.step.symbol : r.step.name.trim()}: ';
      final formula = '${r.step.symbol} = ${CalcEngine.substitute(r.step.expression, const {})}';
      if (!r.ok) {
        b.writeln('$head$formula – nicht berechenbar (${r.error})');
        continue;
      }
      final sub = r.substitution == null ? '' : ' = ${r.substitution}';
      b.writeln('$head$formula$sub = ${r.valueText}');
    }
    final byId = {for (final r in results) r.step.symbol: r};
    final finalResults = [
      for (final s in finalSymbols)
        if (byId[s] case final r? when r.ok) r,
    ];
    if (finalResults.isNotEmpty) {
      b.writeln('Ergebnis:');
      for (final r in finalResults) {
        b.writeln('  ${r.step.symbol} = ${r.valueText}');
      }
    }
    if (assumptions.isNotEmpty) {
      b.writeln('Annahmen:');
      for (final a in assumptions) {
        b.writeln('  - $a');
      }
    }
    if (missing.isNotEmpty) {
      b.writeln('Es fehlt noch:');
      for (final m in missing) {
        b.writeln('  - $m');
      }
    }
    return b.toString().trimRight();
  }

  /// Der Plan als JSON im Format der KI-Antwort (für eine Überarbeitung, siehe
  /// AiService.planCalculation).
  Map<String, dynamic> toJson() => {
        'title': title,
        'given': [
          for (final g in given)
            {
              'symbol': g.symbol,
              'name': g.name,
              'raw': g.raw,
              'values': g.values,
              'unit': g.unit,
              'kind': g.isConstant ? 'constant' : 'given',
              'uncertain': g.uncertain,
            },
        ],
        'steps': [
          for (final s in steps)
            {
              'symbol': s.symbol,
              'name': s.name,
              'latex': s.latex,
              'expression': s.expression,
              'unit': s.unit,
              'explanation': s.explanation,
            },
        ],
        'result': finalSymbols,
        'assumptions': assumptions,
        'notes': notes,
        'missing': missing,
      };

  // -- Aus der KI-Antwort ---------------------------------------------------------

  /// Ein einfacher Backslash in JSON ("\\frac") wird beim Lesen zum
  /// Steuerzeichen (Seitenvorschub + "rac") – zurück in den Backslash.
  static String _repairLatex(String s) => s
      .replaceAll('\u0008', r'\b')
      .replaceAll('\u000C', r'\f')
      .replaceAll('\u000A', r'\n')
      .replaceAll('\u000D', r'\r')
      .replaceAll('\u0009', r'\t');

  /// Liest den Plan aus der JSON-Antwort der KI (siehe AiService.planCalculation).
  /// Tolerant: Unbrauchbares fällt weg und steht in [problems], statt alles
  /// zu verwerfen.
  factory CalcPlan.fromJson(Map<String, dynamic> json) {
    final problems = <String>[];
    String text(Object? v) => (v ?? '').toString().trim();
    List<String> texts(Object? v) => [
          if (v is List)
            for (final e in v)
              if (text(e).isNotEmpty) text(e),
          if (v is String && v.trim().isNotEmpty) v.trim(),
        ];
    Map<String, dynamic>? asMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

    final given = <CalcGiven>[];
    final seen = <String>{};
    final rawGiven = json['given'] ?? json['gegeben'] ?? json['inputs'];
    for (final entry in (rawGiven is List ? rawGiven : const [])) {
      final map = asMap(entry);
      if (map == null) continue;
      final symbol = text(map['symbol']);
      if (!CalcEngine.isValidSymbol(symbol)) {
        problems.add('Ungültiger Name für eine gegebene Größe: „$symbol“ – übersprungen.');
        continue;
      }
      final rawValues = map['values'] ?? map['value'] ?? map['wert'];
      final list = rawValues is List ? rawValues : [rawValues];
      final values = <double>[];
      var ok = list.isNotEmpty;
      for (final v in list) {
        final parsed = CalcEngine.parseNumber(v);
        if (parsed == null) {
          ok = false;
          problems.add('Der Wert von „$symbol“ ist keine Zahl: „${text(v)}“ – übersprungen.');
          break;
        }
        values.add(parsed);
      }
      if (!ok || values.isEmpty) continue;
      if (!seen.add(symbol)) {
        problems.add('„$symbol“ kommt mehrfach als gegebene Größe vor – nur die erste gilt.');
        continue;
      }
      given.add(CalcGiven(
        symbol: symbol,
        name: text(map['name']),
        raw: text(map['raw']),
        values: values,
        unit: text(map['unit'] ?? map['einheit']),
        uncertain: map['uncertain'] == true || map['unsicher'] == true,
        isConstant: text(map['kind']).toLowerCase() == 'constant' || map['constant'] == true,
      ));
    }

    final steps = <CalcStep>[];
    final rawSteps = json['steps'] ?? json['schritte'];
    for (final entry in (rawSteps is List ? rawSteps : const [])) {
      final map = asMap(entry);
      if (map == null) continue;
      final symbol = text(map['symbol']);
      final expression = text(map['expression'] ?? map['formula'] ?? map['ausdruck']);
      if (symbol.isEmpty || expression.isEmpty) {
        problems.add('Ein Rechenschritt ohne Namen oder Formel wurde übersprungen.');
        continue;
      }
      steps.add(CalcStep(
        symbol: symbol,
        name: text(map['name']),
        latex: _repairLatex('${map['latex'] ?? ''}').replaceAll(RegExp(r'^\s*\$+|\$+\s*$'), '').trim(),
        expression: expression,
        unit: text(map['unit'] ?? map['einheit']),
        explanation: text(map['explanation'] ?? map['erklaerung'] ?? map['erklärung']),
      ));
    }

    final known = {for (final s in steps) s.symbol};
    final finals = [
      for (final s in texts(json['result'] ?? json['results'] ?? json['final'] ?? json['ergebnis']))
        if (known.contains(s)) s,
    ];

    return CalcPlan(
      title: text(json['title'] ?? json['titel']),
      given: given,
      steps: steps,
      finals: finals,
      assumptions: texts(json['assumptions'] ?? json['annahmen']),
      notes: texts(json['notes'] ?? json['hinweise']),
      missing: texts(json['missing'] ?? json['fehlt']),
      problems: problems,
    );
  }
}
