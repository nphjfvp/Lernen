import 'dart:math' as math;

import 'math_input.dart';

/// Eine Zeile eines selbst gerechneten Rechenwegs – [side] = Nebenrechnung
/// (gehört zur Hauptzeile davor, z.B. `u = 2x + 1`, `du = 2 dx`).
class ChainLine {
  const ChainLine(this.text, {this.side = false});

  final String text;
  final bool side;
}

enum ChainStatus {
  /// Die App hat nachgerechnet: die Umformung stimmt.
  ok,

  /// Die App hat nachgerechnet: hier ändert sich der Wert.
  wrong,

  /// Eine Substitution/Definition (`u = 2x + 1`) – wird in den anderen Zeilen
  /// eingesetzt, ist selbst aber keine Umformung.
  definition,

  /// Nicht selbst nachrechenbar (Gleichung umgestellt, unlesbar …).
  unknown,
}

class ChainVerdict {
  const ChainVerdict(this.status, [this.message = '']);

  final ChainStatus status;

  /// Für die Anzeige (deutsch, Formeln in `$…$`).
  final String message;

  static const unknown = ChainVerdict(ChainStatus.unknown);
}

/// Rechnet einen getippten oder handschriftlich erkannten Rechenweg Zeile für
/// Zeile nach – ohne KI, durch Einsetzen an Stützstellen:
///
/// - Gleichheitsketten (`∫ … dx = ∫ … du = … + C`, Zeilen, die mit `=`
///   beginnen) – jede Seite muss denselben Wert haben; Stammfunktionen und
///   unbestimmte Integrale werden über ihre Ableitung verglichen (bis auf
///   eine Konstante gleich).
/// - Substitutionen aus (Neben-)Rechnungen (`u = 2x + 1`) werden eingesetzt,
///   `du = 2 dx`, `du/dx = 2`, `u(0) = 1` und neue Grenzen nachgerechnet.
/// - Gleichungen (`2x + 4 = 10` → `x = 3`) gelten als richtig umgeformt,
///   wenn beide dieselbe Lösungsmenge haben (Differenz der Seiten bis auf
///   einen festen Faktor gleich); sonst keine Aussage.
///
/// Sagt nur „falsch“, wenn es sicher ist – im Zweifel [ChainStatus.unknown].
class LineChain {
  LineChain._(this.names, this.constants);

  final Set<String> names;
  final Set<String> constants;

  static List<ChainVerdict> check(
    List<ChainLine> lines, {
    Set<String> names = const {},
    Set<String> constants = const {},
  }) => LineChain._(names, constants)._run(lines);

  // ---------------------------------------------------------------------------
  // Zerlegen
  // ---------------------------------------------------------------------------

  static final _separators = RegExp(r'⇔|<=>|⟺|⟹|⇒|=>|→|->|;|,\s+(?=\D)|\bund\b');
  static final _prefix = RegExp(r'^\s*[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß. ]{2,}:\s*');
  static final _inequality = RegExp(r'[<>≤≥≠]');
  static const _name = r'[A-Za-zα-ωΑ-Ωϑϕ](?:_\(?[A-Za-z0-9]+\)?)?';
  static final _definitionLeft = RegExp('^\\s*($_name)\\s*(?:\\(\\s*($_name)\\s*\\))?\\s*\$');
  static final _labelLeft = RegExp("^\\s*($_name)('*)\\s*(?:\\([^()]*\\))?\\s*\$");

  List<_Statement> _split(String text, int line, bool side) {
    final out = <_Statement>[];
    for (var raw in text.split(_separators)) {
      raw = raw.replaceFirst(_prefix, '').trim();
      if (raw.isEmpty) continue;
      final approx = raw.contains('≈');
      final sides = raw.split(RegExp('[=≈]')).map((s) => s.trim()).toList();
      out.add(_Statement(line: line, side: side, raw: raw, sides: sides, approx: approx));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Ablauf
  // ---------------------------------------------------------------------------

  final _definitions = <String, MathDefinition>{};
  final _labels = <String>{};
  late MathScope _scope;

  List<ChainVerdict> _run(List<ChainLine> lines) {
    final statements = [
      for (final (i, l) in lines.indexed) ..._split(l.text, i, l.side),
    ];

    // 1. Substitutionen/Definitionen: u = 2x + 1, F(x) = x², x = u − 1.
    for (final st in statements) {
      if (st.sides.length != 2 || st.sides[0].isEmpty || _inequality.hasMatch(st.raw)) continue;
      final m = _definitionLeft.firstMatch(st.sides[0]);
      if (m == null) continue;
      final head = MathExpression.tryParse(m[1]!, names: names, calculus: true);
      if (head == null || head.root is! MathSymbol) continue;
      final name = (head.root as MathSymbol).name;
      if (constants.contains(name) || MathScope.looksLikeConstant(name)) continue;
      final body = MathExpression.tryParse(st.sides[1], names: names, calculus: true);
      if (body == null || body.hasCalculus) continue;
      final free = body.freeSymbols.where((s) => !_isConstant(s)).toSet();
      if (free.isEmpty || free.contains(name)) continue;
      String? parameter;
      if (m[2] != null) {
        final p = MathExpression.tryParse(m[2]!, names: names, calculus: true);
        if (p?.root case MathSymbol(:final name)) parameter = name;
      } else if (free.length == 1) {
        parameter = free.single;
      }
      st.definition = name;
      _definitions.putIfAbsent(name, () => MathDefinition(body.root, parameter: parameter));
    }

    // 2. Seiten lesen (Aufrufe wie u(1) nur für definierte Namen).
    final callables = _definitions.keys.toSet();
    for (final st in statements) {
      if (st.definition != null) continue;
      st.parsed = [
        for (final s in st.sides)
          s.isEmpty ? null : MathExpression.tryParse(s, names: names, calculus: true, callables: callables),
      ];
    }

    // 3. Bezeichnungen links („A =“, „F(x) =“, „y' =“): Namen, die sonst
    // nirgends vorkommen.
    final candidates = <_Statement, String>{};
    for (final st in statements) {
      if (st.definition != null || st.sides.length < 2 || st.sides[0].isEmpty) continue;
      final m = _labelLeft.firstMatch(st.sides[0]);
      if (m == null) continue;
      final head = MathExpression.tryParse(m[1]!, names: names, calculus: true);
      if (head?.root case MathSymbol(:final name)) {
        if (_definitions.containsKey(name) && m[2]!.isEmpty) continue;
        candidates[st] = '$name${m[2]}';
      }
    }
    final usedElsewhere = <String>{};
    for (final st in statements) {
      if (st.definition != null) continue;
      for (final (k, e) in (st.parsed ?? const <MathExpression?>[]).indexed) {
        if (e == null || (k == 0 && candidates.containsKey(st))) continue;
        usedElsewhere.addAll(e.symbols);
      }
    }
    for (final MapEntry(key: st, value: label) in candidates.entries) {
      final bare = label.replaceAll("'", '');
      if (label.contains("'") || !usedElsewhere.contains(bare)) {
        st.label = label;
        _labels.add(label);
      }
    }

    // 4. Grundvariable (für dx, du): x, sonst die häufigste freie Größe.
    final counts = <String, int>{};
    for (final st in statements) {
      for (final (k, e) in (st.parsed ?? const <MathExpression?>[]).indexed) {
        if (e == null || (k == 0 && st.label != null)) continue;
        for (final s in _baseOf(e.root, {})) {
          counts[s] = (counts[s] ?? 0) + 1;
        }
      }
    }
    for (final d in _definitions.values) {
      for (final s in _symbolsOf(d.body)) {
        if (!_definitions.containsKey(s) && !_isConstant(s)) counts[s] = (counts[s] ?? 0) + 5;
      }
    }
    String? base;
    if (counts.containsKey('x')) {
      base = 'x';
    } else if (counts.isNotEmpty) {
      base = (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    }
    _scope = MathScope(definitions: _definitions, differentialVariable: base, constantNames: constants);

    // 5. Vergleichen – Hauptzeilen und Nebenrechnungen je als eigene Kette.
    final results = [for (final _ in lines) <_Result>[]];
    _Link? mainPrev, sidePrev;
    var lastMainLine = -1;
    for (final st in statements) {
      if (!st.side && st.line != lastMainLine) {
        lastMainLine = st.line;
        sidePrev = null;
      }
      final prev = st.side ? sidePrev : mainPrev;
      final (result, link) = _statement(st, prev);
      results[st.line].add(result);
      if (st.side) {
        sidePrev = link;
      } else {
        mainPrev = link;
      }
    }
    return [for (final r in results) _combine(r)];
  }

  // ---------------------------------------------------------------------------
  // Eine Aussage
  // ---------------------------------------------------------------------------

  (_Result, _Link?) _statement(_Statement st, _Link? prev) {
    if (st.definition != null) {
      final d = _definitions[st.definition];
      final latex = MathExpression.tryParse(st.sides[1], names: names, calculus: true)?.toLatex() ?? st.sides[1];
      final kind = d?.parameter != null && st.sides[0].contains('(') ? 'Definition' : 'Substitution';
      return (
        _Result(
          ChainStatus.definition,
          '$kind $_dollar${MathExpression.symbolLatex(st.definition!)} = $latex$_dollar – die App setzt sie in den '
          'anderen Zeilen ein.',
        ),
        prev,
      );
    }
    if (_inequality.hasMatch(st.raw)) return (const _Result(ChainStatus.unknown), null);
    final parsed = st.parsed ?? const <MathExpression?>[];
    final continuation = st.sides.first.isEmpty;
    final start = st.label != null ? 1 : 0;
    var terms = parsed.sublist(math.min(start, parsed.length));
    if (continuation && terms.isNotEmpty) terms = terms.sublist(1);
    if (terms.isEmpty || terms.any((t) => t == null)) {
      return (const _Result(ChainStatus.unknown, 'Diese Zeile kann die App nicht selbst lesen.'), null);
    }
    final values = [for (final t in terms) ?t];

    final results = <_Result>[];
    // Anschluss an die Zeile davor.
    if (prev != null && prev.value != null) {
      final first = values.first;
      final definite = continuation || (st.label != null && st.label == prev.label);
      final cmp = _compare(prev.value!, first, approx: st.approx);
      if (cmp.kind == _CmpKind.equal) {
        results.add(_Result(ChainStatus.ok, _okMessage(prev.value!, first, cmp)));
      } else if (cmp.kind == _CmpKind.differ && definite) {
        results.add(_Result(ChainStatus.wrong, _wrongMessage(prev.value!, first, cmp)));
      }
    }

    // Innerhalb der Zeile.
    final equationLike = values.length == 2 && !continuation && st.label == null && !values.any((v) => v.hasCalculus);
    for (var k = 0; k + 1 < values.length; k++) {
      final a = values[k], b = values[k + 1];
      final cmp = _compare(a, b, approx: st.approx);
      if (cmp.kind == _CmpKind.equal) {
        results.add(_Result(ChainStatus.ok, _okMessage(a, b, cmp)));
        continue;
      }
      if (equationLike && !(cmp.kind == _CmpKind.differ && cmp.constantOnly)) {
        // Gleichung: gleiche Lösungen wie die Gleichung davor?
        final eq = prev?.equation;
        if (eq != null) {
          final ratio = _sameSolutions(eq, (a, b));
          if (ratio) {
            results.add(const _Result(ChainStatus.ok, 'Äquivalent umgeformt – gleiche Lösungen wie die Gleichung davor.'));
          }
        }
        return (_combineResults(results), _Link(equation: (a, b)));
      }
      if (cmp.kind == _CmpKind.differ) results.add(_Result(ChainStatus.wrong, _wrongMessage(a, b, cmp)));
    }
    return (_combineResults(results), _Link(value: values.last, label: st.label));
  }

  _Result _combineResults(List<_Result> results) {
    final wrong = results.where((r) => r.status == ChainStatus.wrong).toList();
    if (wrong.isNotEmpty) return wrong.first;
    final ok = results.where((r) => r.status == ChainStatus.ok).toList();
    if (ok.isNotEmpty) return ok.last;
    return const _Result(ChainStatus.unknown);
  }

  ChainVerdict _combine(List<_Result> results) {
    if (results.isEmpty) return ChainVerdict.unknown;
    final wrong = results.where((r) => r.status == ChainStatus.wrong).toList();
    if (wrong.isNotEmpty) return ChainVerdict(ChainStatus.wrong, wrong.first.message);
    final ok = results.where((r) => r.status == ChainStatus.ok).toList();
    if (ok.isNotEmpty) {
      return ChainVerdict(ChainStatus.ok, ok.map((r) => r.message).toSet().take(2).join(' '));
    }
    final defs = results.where((r) => r.status == ChainStatus.definition).toList();
    if (defs.isNotEmpty) return ChainVerdict(ChainStatus.definition, defs.map((r) => r.message).join(' '));
    final note = results.map((r) => r.message).firstWhere((m) => m.isNotEmpty, orElse: () => '');
    return ChainVerdict(ChainStatus.unknown, note);
  }

  // ---------------------------------------------------------------------------
  // Vergleichen
  // ---------------------------------------------------------------------------

  bool _isConstant(String s) => constants.contains(s) || MathScope.looksLikeConstant(s);

  Set<String> _symbolsOf(MathNode n) => MathExpression.fromNode(n).freeSymbols;

  /// Grundvariablen eines Ausdrucks: freie Größen, Definitionen aufgelöst,
  /// ohne Konstanten und Bezeichnungen.
  Set<String> _baseOf(MathNode n, Set<String> seen) {
    final out = <String>{};
    for (final s in _symbolsOf(n)) {
      final d = _definitions[s];
      if (d != null) {
        if (seen.add(s)) out.addAll(_baseOf(d.body, seen));
      } else if (!_isConstant(s) && !_labels.contains(s)) {
        out.add(s);
      }
    }
    return out;
  }

  Set<String> _baseOfExpression(MathExpression e) {
    final out = _baseOf(e.root, {});
    if (e.differentialVariables.isNotEmpty && _scope.differentialVariable != null) {
      out.add(_scope.differentialVariable!);
    }
    return out;
  }

  bool _hasConstant(MathExpression e) => e.symbols.any(_isConstant);

  /// Stützstellen: je Grundvariable andere, positive, "krumme" Werte.
  List<Map<String, double>> _points(Set<String> vars) {
    const pool = [0.37, 1.23, 0.81, 1.71, 2.29, 0.53, 1.07, 2.71, 0.19, 1.49, 0.66, 1.93];
    final sorted = vars.toList()..sort();
    final constantValues = {for (final c in constants) c: 0.7317};
    return [
      for (var p = 0; p < 10; p++)
        {
          ...constantValues,
          for (final (k, v) in sorted.indexed) v: pool[(p + 3 * k) % pool.length] * (1 + 0.013 * k),
        },
    ];
  }

  double _value(MathExpression e, Map<String, double> point, {Map<String, double>? anchor}) {
    final withConstants = {
      ...point,
      for (final c in e.symbols)
        if (_isConstant(c) && !point.containsKey(c)) c: 0.7317,
    };
    return e.evaluateIn(withConstants, anchor == null ? _scope : _scope.withAnchor(anchor));
  }

  static bool _close(double a, double b, double tol) => (a - b).abs() <= tol * math.max(1, math.max(a.abs(), b.abs()));

  _Cmp _compare(MathExpression a, MathExpression b, {bool approx = false}) {
    final vars = {..._baseOfExpression(a), ..._baseOfExpression(b)};
    final viaDerivative = a.hasIndefiniteIntegral || b.hasIndefiniteIntegral || _hasConstant(a) || _hasConstant(b);
    final points = _points(vars);
    if (!viaDerivative) {
      final tol = approx ? 5e-3 : (a.hasCalculus || b.hasCalculus ? 1e-5 : 1e-7);
      return _tally([
        for (final p in points) (point: p, a: _value(a, p), b: _value(b, p), variable: null),
      ], tol, vars);
    }
    // Bis auf eine Konstante gleich: Ableitungen vergleichen.
    final integrationVars = <String>{
      for (final v in {...a.indefiniteVariables, ...b.indefiniteVariables})
        ...(_definitions.containsKey(v) ? _baseOf(_definitions[v]!.body, {}) : {v}),
    };
    final along = (integrationVars.isNotEmpty ? integrationVars : vars).intersection(vars);
    if (along.isEmpty) return const _Cmp(_CmpKind.unknown);
    final samples = <({Map<String, double> point, double a, double b, String? variable})>[];
    for (final p in points) {
      for (final v in along) {
        final x = p[v]!;
        final h = 1e-3 * math.max(1, x.abs());
        double d(MathExpression e) =>
            (_value(e, {...p, v: x + h}, anchor: p) - _value(e, {...p, v: x - h}, anchor: p)) / (2 * h);
        samples.add((point: p, a: d(a), b: d(b), variable: v));
      }
    }
    final result = _tally(samples, approx ? 5e-3 : 1e-4, vars);
    // Werte gleich, Ableitungen auch: dann stimmt es ohnehin.
    return _Cmp(result.kind, viaDerivative: true, example: result.example);
  }

  _Cmp _tally(
    List<({Map<String, double> point, double a, double b, String? variable})> samples,
    double tol,
    Set<String> vars,
  ) {
    var equal = 0, differ = 0;
    String example = '';
    var constantOnly = vars.isEmpty;
    for (final s in samples) {
      if (!s.a.isFinite || !s.b.isFinite) continue;
      if (_close(s.a, s.b, tol)) {
        equal++;
      } else {
        differ++;
        if (example.isEmpty) {
          final at = [
            for (final v in vars.toList()..sort()) '${MathExpression.symbolLatex(v)} = ${_fmt(s.point[v]!)}',
          ].join(',\\ ');
          example = '${at.isEmpty ? '' : 'für $_dollar$at$_dollar '}links ${_fmt(s.a)}, rechts ${_fmt(s.b)}';
        }
      }
    }
    final valid = equal + differ;
    if (valid == 0) return const _Cmp(_CmpKind.unknown);
    if (constantOnly) {
      return differ == 0 ? const _Cmp(_CmpKind.equal) : _Cmp(_CmpKind.differ, example: example, constantOnly: true);
    }
    if (differ == 0 && equal >= 3) return const _Cmp(_CmpKind.equal);
    if (differ >= 2 && differ * 3 >= valid * 2) return _Cmp(_CmpKind.differ, example: example);
    return const _Cmp(_CmpKind.unknown);
  }

  /// Haben die Gleichungen [a] und [b] dieselben Lösungen? (Differenz der
  /// Seiten bis auf einen festen Faktor ≠ 0 gleich.)
  bool _sameSolutions((MathExpression, MathExpression) a, (MathExpression, MathExpression) b) {
    final vars = {
      ..._baseOfExpression(a.$1),
      ..._baseOfExpression(a.$2),
      ..._baseOfExpression(b.$1),
      ..._baseOfExpression(b.$2),
    };
    if (vars.isEmpty) return false;
    double? ratio;
    var n = 0;
    for (final p in _points(vars)) {
      final ra = _value(a.$1, p) - _value(a.$2, p);
      final rb = _value(b.$1, p) - _value(b.$2, p);
      if (!ra.isFinite || !rb.isFinite || ra.abs() < 1e-9) continue;
      final r = rb / ra;
      if (r.abs() < 1e-12) return false;
      if (ratio == null) {
        ratio = r;
      } else if (!_close(r, ratio, 1e-6)) {
        return false;
      }
      n++;
    }
    return n >= 3;
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e9) return MathExpression.formatNumber(v);
    return MathExpression.formatNumber(double.parse(v.toStringAsPrecision(4)));
  }

  static const _dollar = r'$';

  static String _tex(MathExpression e) {
    final t = e.toLatex();
    return '$_dollar$t$_dollar';
  }

  String _okMessage(MathExpression a, MathExpression b, _Cmp cmp) {
    if (cmp.viaDerivative && (a.hasIndefiniteIntegral || b.hasIndefiniteIntegral)) {
      return 'Stimmt – abgeleitet passt ${_tex(b)} zu ${_tex(a)} (bis auf eine Konstante gleich).';
    }
    return 'Stimmt – ${_tex(b)} hat denselben Wert wie ${_tex(a)}.';
  }

  String _wrongMessage(MathExpression a, MathExpression b, _Cmp cmp) {
    final example = cmp.example.isEmpty ? '' : ' (${cmp.viaDerivative ? 'Ableitungen ' : ''}${cmp.example})';
    final both = '$_dollar${a.toLatex()} \\neq ${b.toLatex()}$_dollar';
    if (cmp.viaDerivative) {
      return 'Das passt nicht: $both – auch bis auf eine Konstante verschieden, die Ableitungen unterscheiden sich$example.';
    }
    return 'Das stimmt nicht: $both – der Wert ändert sich$example.';
  }
}

class _Statement {
  _Statement({required this.line, required this.side, required this.raw, required this.sides, required this.approx});

  final int line;
  final bool side;
  final String raw;
  final List<String> sides;
  final bool approx;
  String? definition;
  String? label;
  List<MathExpression?>? parsed;
}

/// Was die nächste Aussage fortsetzt: ein Wert (Gleichheitskette) oder eine
/// Gleichung.
class _Link {
  _Link({this.value, this.label, this.equation});

  final MathExpression? value;
  final String? label;
  final (MathExpression, MathExpression)? equation;
}

class _Result {
  const _Result(this.status, [this.message = '']);

  final ChainStatus status;
  final String message;
}

enum _CmpKind { equal, differ, unknown }

class _Cmp {
  const _Cmp(this.kind, {this.viaDerivative = false, this.example = '', this.constantOnly = false});

  final _CmpKind kind;
  final bool viaDerivative;
  final String example;

  /// Beide Seiten ohne Variablen (reine Zahlen) – dann ist ein Unterschied
  /// sicher ein Fehler, keine Gleichung.
  final bool constantOnly;
}
