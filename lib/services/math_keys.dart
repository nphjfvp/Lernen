import '../models/step_task.dart';

/// Sonderzeichen-Tasten für einen getippten Rechenweg („Selbst rechnen“):
/// aus der Aufgabe abgeleitet – Größen und Funktionen der Aufgabe (y(x),
/// dy/dx, y′, dx …) und alles, was beim Aufgabentyp vorkommen kann
/// (Integral, Grenzwert, Summe, Winkelfunktionen, griechische Buchstaben …).
/// Zahlen bleiben auf der normalen Tastatur.
class MathKeys {
  const MathKeys._();

  static const _base = ['=', '⇒', '+', '−', '·', '/', '^', '²', '(', ')', '√('];

  static const _greek = {
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'delta': 'δ',
    'epsilon': 'ε',
    'eta': 'η',
    'theta': 'θ',
    'lambda': 'λ',
    'mu': 'μ',
    'nu': 'ν',
    'rho': 'ρ',
    'sigma': 'σ',
    'tau': 'τ',
    'phi': 'φ',
    'omega': 'ω',
  };

  /// Tasten für [task]; [text] = Aufgabentext (und Lösung), damit z.B. ein
  /// Grenzwert in der Aufgabenstellung erkannt wird.
  static List<String> forTask(StepTask task, {String text = ''}) {
    final fields = [for (final s in task.steps) ...s.fields];
    final corpus = [
      text,
      for (final s in task.steps) ...[s.title, s.prompt, s.result, s.explanation, ...s.hints],
      for (final f in fields) ...[f.label, f.answer],
    ].join('\n');
    final lower = corpus.toLowerCase();
    bool has(List<String> words) => words.any(lower.contains);
    bool word(String pattern) => RegExp('\\b(?:$pattern)\\b').hasMatch(lower);

    final variables = <String>{for (final f in fields) ...f.variables};
    final constants = <String>{for (final f in fields) ...f.constants};

    // Funktionen wie „y(x) =“, „v(t)“, „f(x)“ aus Beschriftungen und Text.
    final functions = <({String f, String v})>{};
    for (final m in RegExp(r'\b([A-Za-z])(?:_\{?\w+\}?)?\s*\(\s*([a-z])\s*\)').allMatches(corpus)) {
      final f = m.group(1)!;
      final v = m.group(2)!;
      if (f != v && !const {'d', 'e'}.contains(f)) functions.add((f: f, v: v));
    }
    if (variables.isEmpty) variables.addAll(functions.map((x) => x.v));

    final keys = <String>[..._base];
    void add(Iterable<String> more) => keys.addAll(more);

    add([for (final x in functions) '${x.f}(${x.v})']);
    add(variables);
    add(constants);

    final derivative =
        has(["'", '′', 'ableit', 'deriv', 'd/d', 'dgl', 'differential', 'tangente', 'steigung', 'extrem']) ||
        RegExp(r'\bd[a-z]\s*/\s*d[a-z]\b').hasMatch(lower);
    if (derivative) {
      for (final x in functions) {
        add(['d${x.f}/d${x.v}', '${x.f}′', '${x.f}″']);
      }
      add([for (final v in variables) 'd/d$v']);
      if (functions.isEmpty && variables.isEmpty) add(['d/dx', '′']);
    }
    if (has(['∫', 'integr', 'stammfunktion', 'fläche', r'\int'])) {
      add(['∫', for (final v in variables) 'd$v', if (!constants.contains('C')) 'C', '[ ]']);
    }
    if (has(['∂', 'partiell', r'\partial'])) add(['∂']);
    if (has(['lim', 'grenzwert', 'konverg', '→', r'\to', 'gegen unendlich'])) add(['lim', '→', '∞']);
    if (has(['∞', 'unendlich', 'infty'])) add(['∞']);
    if (has(['summe', 'reihe', r'\sum']) || corpus.contains('Σ')) add(['Σ']);
    if (word(r'sin|cos|tan') || has(['winkel', 'schwingung', 'trigonom'])) add(['sin(', 'cos(', 'tan(']);
    if (has(['arcsin', 'arccos', 'arctan'])) add(['arcsin(', 'arccos(', 'arctan(']);
    if (word('exp') || has(['e^', 'exponential', 'wachstum', 'zerfall'])) add(['e^(']);
    if (word(r'ln|log|lg') || has(['logarithm'])) add(['ln(', 'log(']);
    if (has(['ungleich', '≤', '≥', r'\le', r'\ge', '<', '>'])) add(['≤', '≥', '≠']);
    if (has(['±', 'pq', 'p-q', 'mitternacht', 'quadratisch', r'\pm'])) add(['±']);
    if (has(['betrag', '|'])) add(['|']);
    // „Δ“ steht im Original groß – im kleingeschriebenen Text wäre es „δ“.
    if (corpus.contains('Δ') || has([r'\delta', 'differenz', 'änderung'])) add(['Δ']);
    if (word('pi') || has(['π', r'\pi', 'kreis'])) add(['π']);
    if (corpus.contains('_')) add(['_']);
    for (final e in _greek.entries) {
      if (e.key != 'delta' && (lower.contains('\\${e.key}') || corpus.contains(e.value))) add([e.value]);
    }
    if (lower.contains(r'\delta') || corpus.contains('δ')) add(['δ']);

    // Doppelte raus, Reihenfolge behalten.
    final seen = <String>{};
    return [
      for (final k in keys)
        if (k.trim().isNotEmpty && seen.add(k)) k,
    ];
  }
}
