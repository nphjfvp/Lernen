import 'dart:math' as math;

/// Fehler beim Lesen einer Formel-Eingabe – die Meldung ist für die Anzeige
/// gedacht (deutsch, ohne Parser-Fachbegriffe).
class MathInputException implements Exception {
  MathInputException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Knoten einer gelesenen Formel (siehe [MathExpression]).
sealed class MathNode {
  const MathNode();
}

class MathNumber extends MathNode {
  const MathNumber(this.value);
  final double value;
}

/// Eine Größe (Variable, Konstante wie C) oder `pi`/`e`.
class MathSymbol extends MathNode {
  const MathSymbol(this.name);
  final String name;
}

/// Vorzeichen-Minus.
class MathNegate extends MathNode {
  const MathNegate(this.operand);
  final MathNode operand;
}

/// `+ - * / ^`.
class MathBinary extends MathNode {
  const MathBinary(this.op, this.left, this.right);
  final String op;
  final MathNode left;
  final MathNode right;
}

/// Funktion mit einem Argument (`sqrt`, `sin`, `ln`, `abs` …).
class MathCall extends MathNode {
  const MathCall(this.function, this.argument);
  final String function;
  final MathNode argument;
}

/// Integral `∫ f dx` (unbestimmt) bzw. `∫_a^b f dx` (bestimmt) – nur im
/// Rechenweg-Modus (siehe [MathExpression.parse], `calculus`).
class MathIntegral extends MathNode {
  const MathIntegral(this.integrand, this.variable, {this.lower, this.upper});
  final MathNode integrand;
  final String variable;
  final MathNode? lower;
  final MathNode? upper;

  bool get isDefinite => lower != null && upper != null;
}

/// Differential `dx`, `du` außerhalb eines Integrals (`du = 2 dx`, `du/dx`):
/// gerechnet als Ableitung der Größe nach der Grundvariablen
/// ([MathScope.differentialVariable]).
class MathDifferential extends MathNode {
  const MathDifferential(this.variable);
  final String variable;
}

/// Ableitung `d/dx (…)`.
class MathDerivative extends MathNode {
  const MathDerivative(this.body, this.variable);
  final MathNode body;
  final String variable;
}

/// Grenzen einsetzen: `[F]_a^b` = F(b) − F(a).
class MathBoundsEval extends MathNode {
  const MathBoundsEval(this.body, this.lower, this.upper);
  final MathNode body;
  final MathNode lower;
  final MathNode upper;
}

/// Eine selbst definierte Funktion an einer Stelle: `u(1)` bei `u = 2x + 1`.
class MathApply extends MathNode {
  const MathApply(this.name, this.argument);
  final String name;
  final MathNode argument;
}

/// Was eine Größe bedeutet, z.B. die Substitution `u = 2x + 1`
/// ([parameter] x; null = die Grundvariable).
class MathDefinition {
  const MathDefinition(this.body, {this.parameter});
  final MathNode body;
  final String? parameter;
}

/// Umgebung zum Auswerten im Rechenweg-Modus: Substitutionen/Definitionen,
/// die Grundvariable für Differentiale und – für unbestimmte Integrale – die
/// Stelle, ab der integriert wird ([anchor]; ohne sie hat ein unbestimmtes
/// Integral keinen Wert).
class MathScope {
  const MathScope({this.definitions = const {}, this.differentialVariable, this.anchor, this.constantNames = const {}});

  final Map<String, MathDefinition> definitions;
  final String? differentialVariable;
  final Map<String, double>? anchor;

  /// Frei wählbare Konstanten (C) – nie die Variable beim Grenzen-Einsetzen.
  final Set<String> constantNames;

  MathScope withAnchor(Map<String, double>? anchor) => MathScope(
        definitions: definitions,
        differentialVariable: differentialVariable,
        anchor: anchor,
        constantNames: constantNames,
      );

  /// Sieht wie eine Integrationskonstante aus (C, K, C_1, C2).
  static bool looksLikeConstant(String name) => RegExp(r'^[CK](_?\d+)?$').hasMatch(name);
}

/// Eine Formel, wie Lernende sie tippen – für Rechenweg-Aufgaben, bei denen
/// die App Antworten selbst nachrechnet (siehe StepChecker): `2x`, `2(x+1)`,
/// `x sqrt(x)` (unsichtbares Malzeichen), `1,5` (Komma), `√(12-2x)`, `x²`,
/// `π`, `|x|`, `e^x`, `u' = -1/u` (alles vor dem letzten `=` fällt weg) und
/// einfache LaTeX-Schreibweisen (`\frac{1}{u}`, `\sqrt{x}`). Kein `eval`:
/// nur Zahlen, Größen, `+ - * / ^` und die Funktionen in [functions].
///
/// Größen sind einzelne Buchstaben (auch griechische), optional mit Index
/// (`C_1`, `x_0`) oder Strich (`y'`); mehrbuchstabige Namen nur, wenn sie in
/// `names` angegeben sind. `e` ist die Eulersche Zahl, außer `e` steht in
/// `names`. `log` ist der Zehnerlogarithmus (wie auf dem Taschenrechner),
/// `ln` der natürliche.
class MathExpression {
  MathExpression._(this.root, this.source, this.names, {this.calculus = false});

  final MathNode root;
  final String source;

  /// Beim Lesen angegebene Namen (siehe [parse]) – ein angegebenes `e` ist
  /// eine Größe, nicht die Eulersche Zahl.
  final Set<String> names;

  /// Im Rechenweg-Modus gelesen (Integrale, Differentiale, d/dx).
  final bool calculus;

  /// Enthält Integral, Ableitung, Differential oder Grenzen-Einsetzen.
  bool get hasCalculus => _any(root, (n) => n is MathIntegral || n is MathDifferential || n is MathDerivative || n is MathBoundsEval);

  /// Enthält ein unbestimmtes Integral.
  bool get hasIndefiniteIntegral => _any(root, (n) => n is MathIntegral && !n.isDefinite);

  /// Integrationsvariablen der unbestimmten Integrale.
  Set<String> get indefiniteVariables {
    final out = <String>{};
    _any(root, (n) {
      if (n is MathIntegral && !n.isDefinite) out.add(n.variable);
      return false;
    });
    return out;
  }

  /// Variablen der Differentiale (`du`, `dx`).
  Set<String> get differentialVariables {
    final out = <String>{};
    _any(root, (n) {
      if (n is MathDifferential) out.add(n.variable);
      return false;
    });
    return out;
  }

  /// Namen, die als Funktion aufgerufen werden (`u(1)`).
  Set<String> get appliedNames {
    final out = <String>{};
    _any(root, (n) {
      if (n is MathApply) out.add(n.name);
      return false;
    });
    return out;
  }

  static bool _any(MathNode n, bool Function(MathNode) test) {
    if (test(n)) return true;
    return switch (n) {
      MathNumber() || MathSymbol() || MathDifferential() => false,
      MathNegate(:final operand) => _any(operand, test),
      MathBinary(:final left, :final right) => _any(left, test) || _any(right, test),
      MathCall(:final argument) => _any(argument, test),
      MathIntegral(:final integrand, :final lower, :final upper) =>
        _any(integrand, test) || (lower != null && _any(lower, test)) || (upper != null && _any(upper, test)),
      MathDerivative(:final body) => _any(body, test),
      MathBoundsEval(:final body, :final lower, :final upper) =>
        _any(body, test) || _any(lower, test) || _any(upper, test),
      MathApply(:final argument) => _any(argument, test),
    };
  }

  /// Funktionsnamen (Eingabe-Schreibweise → interner Name).
  static const functions = <String, String>{
    'sqrt': 'sqrt',
    'wurzel': 'sqrt',
    'cbrt': 'cbrt',
    'exp': 'exp',
    'ln': 'ln',
    'log': 'log',
    'lg': 'log',
    'sin': 'sin',
    'cos': 'cos',
    'tan': 'tan',
    'cot': 'cot',
    'arcsin': 'asin',
    'asin': 'asin',
    'arccos': 'acos',
    'acos': 'acos',
    'arctan': 'atan',
    'atan': 'atan',
    'sinh': 'sinh',
    'cosh': 'cosh',
    'tanh': 'tanh',
    'abs': 'abs',
    'betrag': 'abs',
    'sgn': 'sgn',
  };

  /// Eingebaute Konstanten.
  static const constants = <String, double>{'pi': math.pi, 'e': math.e};

  /// Liest [input]. Wirft [MathInputException] mit einer verständlichen
  /// Meldung, wenn sich die Eingabe nicht lesen lässt.
  ///
  /// [calculus] (Rechenweg-Modus, siehe LineChain): zusätzlich Integrale
  /// (`∫ x² dx`, `∫_0^1 …`, `\int_{0}^{1}`), Differentiale (`du = 2 dx`,
  /// `du/dx`), Ableitungen (`d/dx (…)`), Grenzen einsetzen (`[F]_0^1`) und
  /// Aufrufe der Namen in [callables] (`u(1)`). Ohne [calculus] bleibt alles
  /// wie bisher (∫ ist dann kein gültiges Zeichen).
  static MathExpression parse(
    String input, {
    Set<String> names = const {},
    bool calculus = false,
    Set<String> callables = const {},
  }) {
    final root = _parseNode(input, names, calculus, callables);
    return MathExpression._(root, input, names, calculus: calculus);
  }

  /// Ein schon gelesener Baum als Ausdruck (z.B. eine Substitution).
  static MathExpression fromNode(MathNode root, {Set<String> names = const {}}) =>
      MathExpression._(root, '', names, calculus: true);

  static MathNode _parseNode(String input, Set<String> names, bool calculus, Set<String> callables) {
    var source = normalize(input);
    if (calculus) source = _normalizeCalculus(source);
    if (source.trim().isEmpty) throw MathInputException('Die Eingabe ist leer.');
    final tokens = _Lexer(source, names, calculus: calculus).run();
    final parser = _Parser(
      tokens,
      calculus: calculus,
      callables: callables,
      subParse: (text) => _parseNode(text, names, calculus, callables),
    );
    return parser.parseAll();
  }

  /// `((d)/(dx))` (aus `\frac{d}{dx}`) → `d/dx`.
  static String _normalizeCalculus(String s) => s
      .replaceAllMapped(RegExp(r'\(\(d\)/\(d\s*([A-Za-zα-ω])\)\)'), (m) => 'd/d${m[1]}')
      .replaceAllMapped(RegExp(r'\(d/d([A-Za-zα-ω])\)'), (m) => 'd/d${m[1]}');

  /// Wie [parse], aber `null` statt einer Ausnahme.
  static MathExpression? tryParse(
    String input, {
    Set<String> names = const {},
    bool calculus = false,
    Set<String> callables = const {},
  }) {
    try {
      return parse(input, names: names, calculus: calculus, callables: callables);
    } on MathInputException {
      return null;
    }
  }

  /// Alle vorkommenden Größen (ohne Funktionen; `pi`/`e` nur, wenn sie in
  /// [MathSymbol]s stehen – siehe [freeSymbols] für die unbekannten).
  Set<String> get symbols {
    final out = <String>{};
    void walk(MathNode n) {
      switch (n) {
        case MathNumber():
          break;
        case MathSymbol(:final name):
          out.add(name);
        case MathNegate(:final operand):
          walk(operand);
        case MathBinary(:final left, :final right):
          walk(left);
          walk(right);
        case MathCall(:final argument):
          walk(argument);
        case MathIntegral(:final integrand, :final variable, :final lower, :final upper):
          if (lower != null && upper != null) {
            final inner = <String>{};
            final saved = {...out};
            out.clear();
            walk(integrand);
            inner.addAll(out..remove(variable));
            out
              ..clear()
              ..addAll(saved)
              ..addAll(inner);
            walk(lower);
            walk(upper);
          } else {
            walk(integrand);
            out.add(variable);
          }
        case MathDifferential(:final variable):
          out.add(variable);
        case MathDerivative(:final body):
          walk(body);
        case MathBoundsEval(:final body, :final lower, :final upper):
          walk(body);
          walk(lower);
          walk(upper);
        case MathApply(:final argument):
          walk(argument);
      }
    }

    walk(root);
    return out;
  }

  /// Größen, die nicht `pi`/`e` sind – müssen beim Auswerten belegt werden.
  Set<String> get freeSymbols => symbols.difference(constants.keys.toSet().difference(names));

  /// Rechnet mit den Belegungen [values]. Außerhalb des Definitionsbereichs
  /// (Wurzel aus Negativem, Division durch 0 …) kommt `NaN` bzw. ±∞ heraus.
  /// Eine nicht belegte Größe ergibt `NaN`.
  double evaluate([Map<String, double> values = const {}]) => _Evaluator(const MathScope()).eval(root, values);

  /// Wie [evaluate], mit Substitutionen, Grundvariable und Integrations-
  /// Anfang aus [scope] (Rechenweg-Modus).
  double evaluateIn(Map<String, double> values, MathScope scope) => _Evaluator(scope).eval(root, values);

  static double pow(double a, double b) => _pow(a, b);

  static double _pow(double a, double b) {
    // Ungerade Wurzeln aus negativen Zahlen (x^(1/3)) wie auf dem Papier.
    if (a < 0 && b.isFinite && b != b.roundToDouble()) {
      final inverse = 1 / b;
      if ((inverse - inverse.roundToDouble()).abs() < 1e-9 && inverse.round().isOdd) {
        return -math.pow(-a, b).toDouble();
      }
    }
    return math.pow(a, b).toDouble();
  }

  static double call(String f, double x) => _call(f, x);

  static double _call(String f, double x) => switch (f) {
        'sqrt' => math.sqrt(x),
        'cbrt' => x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble(),
        'exp' => math.exp(x),
        'ln' => math.log(x),
        'log' => math.log(x) / math.ln10,
        'sin' => math.sin(x),
        'cos' => math.cos(x),
        'tan' => math.tan(x),
        'cot' => 1 / math.tan(x),
        'asin' => math.asin(x),
        'acos' => math.acos(x),
        'atan' => math.atan(x),
        'sinh' => (math.exp(x) - math.exp(-x)) / 2,
        'cosh' => (math.exp(x) + math.exp(-x)) / 2,
        'tanh' => _tanh(x),
        'abs' => x.abs(),
        'sgn' => x.isNaN ? x : (x > 0 ? 1.0 : (x < 0 ? -1.0 : 0.0)),
        _ => double.nan,
      };

  static double _tanh(double x) {
    if (x > 20) return 1;
    if (x < -20) return -1;
    final a = math.exp(x), b = math.exp(-x);
    return (a - b) / (a + b);
  }

  /// Die Formel als LaTeX (für die Vorschau "So verstehe ich deine Eingabe").
  String toLatex() => _latex(root);

  static const _greek = {
    'α': r'\alpha', 'β': r'\beta', 'γ': r'\gamma', 'δ': r'\delta', 'ε': r'\varepsilon', 'ζ': r'\zeta',
    'η': r'\eta', 'θ': r'\theta', 'ϑ': r'\vartheta', 'ι': r'\iota', 'κ': r'\kappa', 'λ': r'\lambda',
    'μ': r'\mu', 'ν': r'\nu', 'ξ': r'\xi', 'ρ': r'\rho', 'σ': r'\sigma', 'τ': r'\tau', 'φ': r'\varphi',
    'ϕ': r'\phi', 'χ': r'\chi', 'ψ': r'\psi', 'ω': r'\omega', 'Γ': r'\Gamma', 'Δ': r'\Delta',
    'Θ': r'\Theta', 'Λ': r'\Lambda', 'Ξ': r'\Xi', 'Σ': r'\Sigma', 'Φ': r'\Phi', 'Ψ': r'\Psi', 'Ω': r'\Omega',
  };

  static int _prec(MathNode n) => switch (n) {
        MathBinary(op: '+' || '-') => 1,
        MathBinary(op: '*' || '/') => 2,
        MathNegate() => 3,
        MathBinary(op: '^') => 4,
        _ => 5,
      };

  static String _paren(String s) => r'\left(' + s + r'\right)';

  static String symbolLatex(String name) {
    if (name == 'pi') return r'\pi';
    var base = name, sub = '', primes = '';
    final p = base.indexOf("'");
    if (p >= 0) {
      primes = base.substring(p);
      base = base.substring(0, p);
    }
    final u = base.indexOf('_');
    if (u >= 0) {
      sub = base.substring(u + 1);
      base = base.substring(0, u);
    }
    final b = _greek[base] ?? (base.length > 1 ? '\\mathrm{$base}' : base);
    return '$b${sub.isEmpty ? '' : '_{$sub}'}$primes';
  }

  static String numberLatex(double v) => formatNumber(v).replaceAll(',', '{,}');

  /// Zahl mit Komma, ohne überflüssige Nachkommastellen (höchstens 10
  /// gültige Ziffern).
  static String formatNumber(double v) {
    if (v.isNaN) return 'nicht definiert';
    if (v.isInfinite) return v > 0 ? '∞' : '−∞';
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    var s = v.toStringAsPrecision(10);
    if (s.contains('e')) return s.replaceAll('.', ',');
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s.replaceAll('.', ',');
  }

  static bool _startsWithLetter(String latex) => RegExp(r'^(\\[a-zA-Z]|[a-zA-Z(]|\\left)').hasMatch(latex);

  static String _latex(MathNode n) {
    switch (n) {
      case MathNumber(:final value):
        return numberLatex(value);
      case MathSymbol(:final name):
        return symbolLatex(name);
      case MathNegate(:final operand):
        final inner = _latex(operand);
        return '-${_prec(operand) <= 1 ? _paren(inner) : inner}';
      case MathCall(:final function, :final argument):
        final arg = _latex(argument);
        return switch (function) {
          'sqrt' => '\\sqrt{$arg}',
          'cbrt' => '\\sqrt[3]{$arg}',
          'abs' => '\\left|$arg\\right|',
          'exp' => 'e^{$arg}',
          'ln' => r'\ln' + _paren(arg),
          'log' => r'\log' + _paren(arg),
          'asin' => r'\arcsin' + _paren(arg),
          'acos' => r'\arccos' + _paren(arg),
          'atan' => r'\arctan' + _paren(arg),
          'sgn' => r'\operatorname{sgn}' + _paren(arg),
          _ => '\\$function${_paren(arg)}',
        };
      case MathIntegral(:final integrand, :final variable, :final lower, :final upper):
        final bounds = lower != null && upper != null ? '_{${_latex(lower)}}^{${_latex(upper)}}' : '';
        return '\\int$bounds ${_latex(integrand)} \\,\\mathrm{d}${symbolLatex(variable)}';
      case MathDifferential(:final variable):
        return '\\mathrm{d}${symbolLatex(variable)}';
      case MathDerivative(:final body, :final variable):
        return '\\frac{\\mathrm{d}}{\\mathrm{d}${symbolLatex(variable)}}${_paren(_latex(body))}';
      case MathBoundsEval(:final body, :final lower, :final upper):
        return '\\left[${_latex(body)}\\right]_{${_latex(lower)}}^{${_latex(upper)}}';
      case MathApply(:final name, :final argument):
        return '${symbolLatex(name)}${_paren(_latex(argument))}';
      case MathBinary(:final op, :final left, :final right):
        final l = _latex(left), r = _latex(right);
        switch (op) {
          case '+':
            return '$l + ${right is MathNegate ? _paren(r) : r}';
          case '-':
            return '$l - ${_prec(right) <= 1 || right is MathNegate ? _paren(r) : r}';
          case '/':
            // -1/u als -\frac{1}{u} (gleicher Wert, gewohnte Schreibweise).
            if (left is MathNegate) return '-\\frac{${_latex(left.operand)}}{$r}';
            return '\\frac{$l}{$r}';
          case '^':
            final base = left is MathSymbol || (left is MathNumber && left.value >= 0) ? l : _paren(l);
            return '$base^{$r}';
          default:
            final ll = _prec(left) < 2 ? _paren(l) : l;
            final rr = _prec(right) < 2 || right is MathNegate ? _paren(r) : r;
            final juxtapose = left is MathNumber && right is! MathNumber && _startsWithLetter(rr);
            return juxtapose ? '$ll$rr' : '$ll \\cdot $rr';
        }
    }
  }

  // ---------------------------------------------------------------------
  // Vorbereitung der Eingabe
  // ---------------------------------------------------------------------

  static const _superscripts = {
    '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9',
    '⁻': '-', '⁺': '+', 'ⁿ': 'n', 'ˣ': 'x',
  };

  /// Vereinheitlicht Schreibweisen (Unicode-Zeichen, LaTeX, Dezimalkomma,
  /// Hochzahlen) und schneidet alles vor dem letzten `=` ab.
  static String normalize(String input) {
    var s = input.trim().replaceAll(r'$', '');
    if (s.contains(r'\')) s = latexToInput(s);
    final eq = s.lastIndexOf(RegExp(r'[=≈]'));
    if (eq >= 0) s = s.substring(eq + 1);
    s = s
        .replaceAll(RegExp('[−–—]'), '-')
        .replaceAll('**', '^')
        .replaceAll(RegExp('[·×⋅∙•]'), '*')
        .replaceAll(RegExp('[÷:]'), '/')
        .replaceAll(RegExp('[′’´`]'), "'")
        .replaceAll('π', 'pi')
        .replaceAll('∛', 'cbrt')
        .replaceAll('½', '(1/2)')
        .replaceAll(RegExp(r'[\[{]'), '(')
        .replaceAll(RegExp(r'[\]}]'), ')');
    // Dezimalkomma zwischen Ziffern (1,5) – andere Kommas bleiben und fallen
    // später als Fehler auf.
    s = s.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
    // Hochgestellte Zeichenfolgen (x², x⁻¹) → ^(…).
    final b = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (_superscripts.containsKey(ch)) {
        final sup = StringBuffer();
        while (i < s.length && _superscripts.containsKey(s[i])) {
          sup.write(_superscripts[s[i]]);
          i++;
        }
        b.write('^($sup)');
        continue;
      }
      b.write(ch);
      i++;
    }
    return b.toString();
  }

  /// Einfache LaTeX-Formeln in Eingabe-Schreibweise: `\frac{a}{b}`,
  /// `\sqrt{x}`, `\sqrt[3]{x}`, `x^{2}`, `\cdot`, `\left( … \right)`,
  /// `\ln`, `\pi`, griechische Buchstaben. Unbekanntes verliert den
  /// Backslash.
  static String latexToInput(String s) => _LatexConverter(s).run();
}

/// Rechnet einen Formelbaum aus – im Rechenweg-Modus mit Substitutionen,
/// numerischem Integrieren (Gauß-Legendre) und Ableiten (zentrale
/// Differenzen).
class _Evaluator {
  _Evaluator(this.scope);

  final MathScope scope;
  final _active = <String>{};

  double symbol(String name, Map<String, double> v) {
    final direct = v[name];
    if (direct != null) return direct;
    final def = scope.definitions[name];
    if (def != null && !_active.contains(name)) {
      _active.add(name);
      try {
        return eval(def.body, v);
      } finally {
        _active.remove(name);
      }
    }
    return MathExpression.constants[name] ?? double.nan;
  }

  double eval(MathNode n, Map<String, double> v) {
    switch (n) {
      case MathNumber(:final value):
        return value;
      case MathSymbol(:final name):
        return symbol(name, v);
      case MathNegate(:final operand):
        return -eval(operand, v);
      case MathBinary(:final op, :final left, :final right):
        final a = eval(left, v), b = eval(right, v);
        return switch (op) {
          '+' => a + b,
          '-' => a - b,
          '*' => a * b,
          '/' => a / b,
          _ => MathExpression.pow(a, b),
        };
      case MathCall(:final function, :final argument):
        return MathExpression.call(function, eval(argument, v));
      case MathIntegral(:final integrand, :final variable, :final lower, :final upper):
        double a, b;
        if (lower != null && upper != null) {
          a = eval(lower, v);
          b = eval(upper, v);
        } else {
          final anchor = scope.anchor;
          if (anchor == null) return double.nan;
          a = symbol(variable, anchor);
          b = symbol(variable, v);
        }
        return integrate((t) => eval(integrand, {...v, variable: t}), a, b);
      case MathDifferential(:final variable):
        final base = scope.differentialVariable;
        if (base == null) return double.nan;
        if (variable == base) return 1;
        if (!scope.definitions.containsKey(variable)) return double.nan;
        return _derivative((x) => symbol(variable, {...v, base: x}), symbol(base, v));
      case MathDerivative(:final body, :final variable):
        return _derivative((x) => eval(body, {...v, variable: x}), symbol(variable, v));
      case MathBoundsEval(:final body, :final lower, :final upper):
        final variable = _boundsVariable(body);
        if (variable == null) return double.nan;
        return eval(body, {...v, variable: eval(upper, v)}) - eval(body, {...v, variable: eval(lower, v)});
      case MathApply(:final name, :final argument):
        final def = scope.definitions[name];
        final parameter = def?.parameter ?? scope.differentialVariable;
        if (def == null || parameter == null) return double.nan;
        return eval(def.body, {...v, parameter: eval(argument, v)});
    }
  }

  /// Welche Größe beim Grenzen-Einsetzen ersetzt wird: die einzige Variable
  /// (ohne Konstanten wie C), sonst die Grundvariable.
  String? _boundsVariable(MathNode body) {
    final vars = MathExpression._(body, '', const {}).freeSymbols.where(
      (s) => !scope.constantNames.contains(s) && !MathScope.looksLikeConstant(s),
    ).toSet();
    if (vars.length == 1) return vars.single;
    final base = scope.differentialVariable;
    if (base != null && vars.contains(base)) return base;
    return null;
  }

  static double _derivative(double Function(double) f, double x) {
    if (!x.isFinite) return double.nan;
    final h = 1e-5 * math.max(1, x.abs());
    return (f(x + h) - f(x - h)) / (2 * h);
  }

  static const _gaussNodes = [0.0, -0.5384693101056831, 0.5384693101056831, -0.9061798459386640, 0.9061798459386640];
  static const _gaussWeights = [
    0.5688888888888889,
    0.4786286704993665,
    0.4786286704993665,
    0.2369268850561891,
    0.2369268850561891,
  ];

  static double _gauss(double Function(double) f, double a, double b, int n) {
    final h = (b - a) / n;
    var sum = 0.0;
    for (var k = 0; k < n; k++) {
      final mid = a + (k + 0.5) * h;
      for (var j = 0; j < _gaussNodes.length; j++) {
        sum += _gaussWeights[j] * f(mid + _gaussNodes[j] * h / 2);
      }
    }
    return sum * h / 2;
  }

  /// ∫_a^b f – `NaN`, wenn es nicht verlässlich geht (Polstelle, uneigentlich,
  /// zwei Genauigkeiten weichen voneinander ab).
  static double integrate(double Function(double) f, double a, double b) {
    if (!a.isFinite || !b.isFinite) return double.nan;
    if (a == b) return 0;
    final small = (b - a).abs() < 0.05;
    final coarse = _gauss(f, a, b, small ? 1 : 48);
    final fine = _gauss(f, a, b, small ? 2 : 96);
    if (!coarse.isFinite || !fine.isFinite) return double.nan;
    if ((coarse - fine).abs() > 1e-8 * math.max(1, fine.abs())) return double.nan;
    return fine;
  }
}

class _LatexConverter {
  _LatexConverter(this.s);

  final String s;
  int i = 0;

  static final _greekByCommand = {for (final e in MathExpression._greek.entries) e.value.substring(1): e.key};

  String run() {
    final out = StringBuffer();
    while (i < s.length) {
      final ch = s[i];
      if (ch == r'\') {
        final m = RegExp(r'\\([a-zA-Z]+)').matchAsPrefix(s, i);
        if (m != null) {
          i = m.end;
          out.write(_command(m[1]!));
          continue;
        }
        // \, \; \! (Abstände), \{ \}
        i += 2;
        continue;
      }
      if (ch == '^' || ch == '_') {
        i++;
        final g = _group();
        out.write(ch == '^' ? '^($g)' : (g.length > 1 ? '_($g)' : '_$g'));
        continue;
      }
      out.write(ch == '{' ? '(' : (ch == '}' ? ')' : ch));
      i++;
    }
    return out.toString();
  }

  /// Eine {…}-Gruppe (rekursiv umgewandelt) oder ein einzelnes Zeichen bzw.
  /// ein einzelner Befehl.
  String _group() {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
    if (i >= s.length) return '';
    if (s[i] != '{') {
      if (s[i] == r'\') {
        final m = RegExp(r'\\([a-zA-Z]+)').matchAsPrefix(s, i);
        if (m != null) {
          i = m.end;
          return _command(m[1]!);
        }
      }
      return s[i++];
    }
    var depth = 0;
    final start = ++i;
    while (i < s.length) {
      if (s[i] == '{') depth++;
      if (s[i] == '}') {
        if (depth == 0) break;
        depth--;
      }
      i++;
    }
    final inner = s.substring(start, i < s.length ? i : s.length);
    if (i < s.length) i++;
    return _LatexConverter(inner).run();
  }

  String _command(String name) {
    switch (name) {
      case 'frac':
      case 'dfrac':
      case 'tfrac':
        final a = _group(), b = _group();
        return '(($a)/($b))';
      case 'sqrt':
        if (i < s.length && s[i] == '[') {
          final close = s.indexOf(']', i);
          final n = close < 0 ? '2' : s.substring(i + 1, close).trim();
          i = close < 0 ? s.length : close + 1;
          final a = _group();
          return n == '3' ? 'cbrt($a)' : '(($a)^(1/($n)))';
        }
        return 'sqrt(${_group()})';
      case 'int':
        return '∫';
      case 'mathrm':
        // \mathrm{d}x → dx
        return _group();
      case 'cdot':
      case 'times':
        return '*';
      case 'div':
        return '/';
      case 'left':
      case 'right':
      case 'big':
      case 'Big':
      case 'bigl':
      case 'bigr':
      case 'Bigl':
      case 'Bigr':
        return '';
      case 'text':
      case 'operatorname':
      case 'mathit':
        return _group();
      default:
        return _greekByCommand[name] ?? name;
    }
  }
}

enum _K { number, symbol, function, op, open, close, bar, sqrtSign, integral, bounds, end }

class _Tok {
  const _Tok(this.kind, this.text, this.at, {this.value = 0, this.lower, this.upper});
  final _K kind;
  final String text;

  /// Beginn des Worts im Text – Teile eines Worts ("dx") haben dasselbe.
  final int at;
  final double value;

  /// Grenzen bei [_K.integral] und [_K.bounds].
  final String? lower;
  final String? upper;
}

class _Lexer {
  _Lexer(this.s, Set<String> names, {this.calculus = false})
      : names = {for (final n in names) if (n.trim().isNotEmpty) n.trim()},
        multi = [
          ...MathExpression.functions.keys,
          'pi',
          ...{for (final n in names) if (n.trim().length > 1) n.trim()},
        ]..sort((a, b) => b.length.compareTo(a.length));

  final String s;
  final Set<String> names;
  final bool calculus;

  /// Mehrbuchstabige Namen, die längsten zuerst.
  final List<String> multi;

  static final _letter = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿα-ωΑ-Ωϑϕ]');
  static final _digit = RegExp(r'[0-9]');

  final out = <_Tok>[];

  List<_Tok> run() {
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch.trim().isEmpty) {
        i++;
        continue;
      }
      if (_digit.hasMatch(ch) || (ch == '.' && i + 1 < s.length && _digit.hasMatch(s[i + 1]))) {
        final m = RegExp(r'\d*\.?\d*(?:[eE][+-]?\d+)?').matchAsPrefix(s, i)!;
        var text = m[0]!;
        // "2e" ohne Ziffern dahinter ist 2·e, kein Exponent.
        if (RegExp(r'[eE]').hasMatch(text) && !RegExp(r'[eE][+-]?\d+$').hasMatch(text)) {
          text = text.replaceFirst(RegExp(r'[eE].*$'), '');
        }
        final value = double.tryParse(text);
        if (value == null) throw MathInputException('Die Zahl „$text“ lässt sich nicht lesen.');
        out.add(_Tok(_K.number, text, i, value: value));
        i += text.length;
        continue;
      }
      if (_letter.hasMatch(ch)) {
        i = _word(i);
        continue;
      }
      switch (ch) {
        case '+':
        case '-':
        case '*':
        case '/':
        case '^':
          out.add(_Tok(_K.op, ch, i));
        case '(':
          out.add(_Tok(_K.open, ch, i));
        case ')':
          out.add(_Tok(_K.close, ch, i));
        case '|':
          out.add(_Tok(_K.bar, ch, i));
        case '√':
          out.add(_Tok(_K.sqrtSign, ch, i));
        case '∫' when calculus:
          final (lower, upper, end) = _bounds(i + 1);
          out.add(_Tok(_K.integral, ch, i, lower: lower, upper: upper));
          i = end;
          continue;
        case '_' when calculus && out.isNotEmpty && out.last.kind == _K.close:
          final (lower, upper, end) = _bounds(i);
          if (lower == null || upper == null) throw MathInputException('Beim Einsetzen fehlen die Grenzen, z.B. [F]_0^1.');
          out.add(_Tok(_K.bounds, '_', i, lower: lower, upper: upper));
          i = end;
          continue;
        case ',':
        case ';':
          throw MathInputException('Ein Komma geht nur als Dezimalzeichen (z.B. 1,5).');
        case "'":
          throw MathInputException('Der Strich (Ableitung) gehört an eine Größe, z.B. y\'.');
        default:
          throw MathInputException('Das Zeichen „$ch“ kann ich nicht verwenden.');
      }
      i++;
    }
    out.add(_Tok(_K.end, '', s.length));
    return out;
  }

  /// Grenzen `_a^b` bzw. `^b_a` ab [start] (jeweils eine Klammer, eine Zahl
  /// oder ein Name) – (untere, obere, Ende).
  (String?, String?, int) _bounds(int start) {
    String? lower, upper;
    var i = start;
    for (var round = 0; round < 2; round++) {
      var j = i;
      while (j < s.length && s[j] == ' ') {
        j++;
      }
      if (j >= s.length || (s[j] != '_' && s[j] != '^')) break;
      final which = s[j];
      j++;
      while (j < s.length && s[j] == ' ') {
        j++;
      }
      if (j >= s.length) throw MathInputException('Nach „$which“ fehlt die Grenze.');
      String text;
      if (s[j] == '(') {
        var depth = 0;
        final from = j;
        while (j < s.length) {
          if (s[j] == '(') depth++;
          if (s[j] == ')') {
            depth--;
            if (depth == 0) break;
          }
          j++;
        }
        if (j >= s.length) throw MathInputException('Eine Klammer an der Grenze wird nicht geschlossen.');
        text = s.substring(from + 1, j);
        j++;
      } else {
        final m = RegExp(r'-?(\d+\.?\d*|\.\d+)|-?pi|-?[A-Za-zα-ω]').matchAsPrefix(s, j);
        if (m == null) throw MathInputException('Die Grenze nach „$which“ kann ich nicht lesen.');
        text = m[0]!;
        j = m.end;
      }
      if (which == '_') {
        lower = text;
      } else {
        upper = text;
      }
      i = j;
    }
    return (lower, upper, i);
  }

  /// Liest eine Buchstabenfolge und zerlegt sie in Funktionen, Konstanten,
  /// angegebene Namen und einzelne Buchstaben. Index (`_1`) und Striche
  /// gehören zum letzten Namen.
  int _word(int start) {
    var end = start;
    while (end < s.length && _letter.hasMatch(s[end])) {
      end++;
    }
    final run = s.substring(start, end);
    final parts = <String>[];
    var i = 0;
    while (i < run.length) {
      String? hit;
      for (final name in multi) {
        if (run.length - i >= name.length) {
          final piece = run.substring(i, i + name.length);
          final isFunction = MathExpression.functions.containsKey(name);
          if (piece == name || (isFunction && piece.toLowerCase() == name)) {
            hit = name;
            break;
          }
        }
      }
      if (hit != null) {
        parts.add(hit);
        i += hit.length;
      } else {
        parts.add(run[i]);
        i++;
      }
    }
    // Index und Striche an den letzten Namen.
    var suffix = '';
    var j = end;
    if (j < s.length && s[j] == '_') {
      final m = RegExp(r'_\(?([A-Za-z0-9]+)\)?').matchAsPrefix(s, j);
      if (m != null) {
        suffix += '_${m[1]}';
        j = m.end;
      }
    }
    // Ziffern direkt hinter dem Namen gehören nur dazu, wenn es den Namen so
    // gibt (x0, C1); sonst ist es ein Faktor (x2 = x·2).
    final digits = RegExp(r'\d+').matchAsPrefix(s, j);
    if (suffix.isEmpty && digits != null && names.contains('${parts.last}${digits[0]}')) {
      suffix = digits[0]!;
      j = digits.end;
    }
    while (j < s.length && s[j] == "'") {
      suffix += "'";
      j++;
    }
    for (var k = 0; k < parts.length; k++) {
      var name = parts[k];
      if (k == parts.length - 1) name += suffix;
      final at = start;
      if (MathExpression.functions.containsKey(name.toLowerCase()) &&
          !names.contains(name) &&
          (suffix.isEmpty || k < parts.length - 1)) {
        out.add(_Tok(_K.function, MathExpression.functions[name.toLowerCase()]!, at));
      } else if (name == 'e' && names.contains('e')) {
        out.add(_Tok(_K.symbol, 'e', at));
      } else {
        out.add(_Tok(_K.symbol, name, at));
      }
    }
    return j;
  }
}

class _Parser {
  _Parser(this.tokens, {this.calculus = false, this.callables = const {}, required this.subParse});

  final List<_Tok> tokens;
  final bool calculus;
  final Set<String> callables;
  final MathNode Function(String text) subParse;
  int _i = 0;
  int _barDepth = 0;
  int _integralDepth = 0;

  static final _singleLetter = RegExp(r'^[A-Za-zα-ωΑ-Ωϑϕ]$');

  /// Steht bei [i] ein Differential (`dx`: „d“ und ein Buchstabe im selben
  /// Wort)?
  bool _differentialAt(int i) {
    if (!calculus || i + 1 >= tokens.length) return false;
    final d = tokens[i], v = tokens[i + 1];
    return d.kind == _K.symbol &&
        d.text == 'd' &&
        v.kind == _K.symbol &&
        v.at == d.at &&
        _singleLetter.hasMatch(v.text);
  }

  _Tok get _peek => tokens[_i];
  _Tok _next() => tokens[_i++];

  MathNode parseAll() {
    final node = _expr();
    if (_peek.kind != _K.end) {
      final t = _peek;
      if (t.kind == _K.close) throw MathInputException('Eine Klammer „)“ ist zu viel.');
      throw MathInputException('Nach „${tokens[_i - 1].text}“ kann ich „${t.text}“ nicht lesen.');
    }
    return node;
  }

  MathNode _expr() {
    var left = _term();
    while (_peek.kind == _K.op && (_peek.text == '+' || _peek.text == '-')) {
      final op = _next().text;
      left = MathBinary(op, left, _term());
    }
    return left;
  }

  bool get _startsFactor {
    final t = _peek;
    return switch (t.kind) {
      _K.number || _K.symbol || _K.function || _K.open || _K.sqrtSign || _K.integral => true,
      _K.bar => _barDepth == 0,
      _ => false,
    };
  }

  MathNode _term() {
    var left = _unary();
    while (true) {
      final t = _peek;
      if (t.kind == _K.op && (t.text == '*' || t.text == '/')) {
        _next();
        left = MathBinary(t.text, left, _unary());
      } else if (_integralDepth > 0 && _differentialAt(_i)) {
        // Das dx am Ende des Integranden.
        return left;
      } else if (_startsFactor) {
        // Unsichtbares Malzeichen: 2x, 2(x+1), x sqrt(x), (x+1)(x-1).
        if (t.kind == _K.number && left is MathNumber) {
          throw MathInputException('Zwischen zwei Zahlen fehlt ein Rechenzeichen.');
        }
        left = MathBinary('*', left, _power());
      } else {
        return left;
      }
    }
  }

  MathNode _unary() {
    final t = _peek;
    if (t.kind == _K.op && (t.text == '-' || t.text == '+')) {
      _next();
      final operand = _unary();
      return t.text == '-' ? MathNegate(operand) : operand;
    }
    return _power();
  }

  MathNode _power() {
    final base = _primary();
    if (_peek.kind == _K.op && _peek.text == '^') {
      _next();
      if (_peek.kind == _K.end) throw MathInputException('Nach „^“ fehlt die Hochzahl.');
      return MathBinary('^', base, _unary());
    }
    return base;
  }

  MathNode _primary() {
    final t = _next();
    switch (t.kind) {
      case _K.number:
        return MathNumber(t.value);
      case _K.symbol:
        if (calculus && t.text == 'd') {
          // dx, du (Differential)
          if (_differentialAt(_i - 1)) return MathDifferential(_next().text);
          // d/dx (…)
          if (_peek.kind == _K.op && _peek.text == '/' && _differentialAt(_i + 1)) {
            _next();
            _next();
            final variable = _next().text;
            return MathDerivative(_argument('d/d$variable'), variable);
          }
        }
        if (callables.contains(t.text) && _peek.kind == _K.open) return MathApply(t.text, _primary());
        return MathSymbol(t.text);
      case _K.integral:
        return _integral(t);
      case _K.bounds:
        throw MathInputException('Vor den Grenzen fehlt die Klammer, z.B. [F]_0^1.');
      case _K.open:
        if (_peek.kind == _K.close) throw MathInputException('Die Klammer ist leer.');
        final inner = _expr();
        if (_peek.kind != _K.close) throw MathInputException('Eine Klammer wird nicht geschlossen.');
        _next();
        if (_peek.kind == _K.bounds) {
          final b = _next();
          return MathBoundsEval(inner, subParse(b.lower!), subParse(b.upper!));
        }
        return inner;
      case _K.bar:
        _barDepth++;
        final inner = _expr();
        _barDepth--;
        if (_peek.kind != _K.bar) throw MathInputException('Der Betrag |…| wird nicht geschlossen.');
        _next();
        return MathCall('abs', inner);
      case _K.sqrtSign:
        return MathCall('sqrt', _argument('√'));
      case _K.function:
        // sin^2(x) = (sin x)^2
        if (_peek.kind == _K.op && _peek.text == '^') {
          _next();
          final exponent = _primary();
          return MathBinary('^', MathCall(t.text, _argument(t.text)), exponent);
        }
        return MathCall(t.text, _argument(t.text));
      case _K.end:
        throw MathInputException(_i <= 1 ? 'Die Eingabe ist leer.' : 'Am Ende fehlt noch etwas.');
      case _K.close:
        throw MathInputException('Vor „)“ fehlt etwas.');
      case _K.op:
        throw MathInputException('Vor „${t.text}“ fehlt etwas.');
    }
  }

  /// `∫ f dx`, `∫_a^b f dx`, `∫ dx/x`.
  MathNode _integral(_Tok t) {
    if ((t.lower == null) != (t.upper == null)) {
      throw MathInputException('Beim Integral fehlt eine Grenze (unten mit _, oben mit ^).');
    }
    final lower = t.lower == null ? null : subParse(t.lower!);
    final upper = t.upper == null ? null : subParse(t.upper!);
    _integralDepth++;
    try {
      MathNode integrand;
      String variable;
      if (_differentialAt(_i)) {
        // ∫ dx/x
        _next();
        variable = _next().text;
        integrand = const MathNumber(1);
        while (_peek.kind == _K.op && (_peek.text == '*' || _peek.text == '/')) {
          final op = _next().text;
          integrand = MathBinary(op, integrand, _unary());
        }
      } else {
        if (_peek.kind == _K.end) throw MathInputException('Nach ∫ fehlt, was integriert wird.');
        integrand = _expr();
        if (!_differentialAt(_i)) throw MathInputException('Am Ende des Integrals fehlt das dx (bzw. du, dt …).');
        _next();
        variable = _next().text;
      }
      return MathIntegral(integrand, variable, lower: lower, upper: upper);
    } finally {
      _integralDepth--;
    }
  }

  /// Argument einer Funktion: `(…)`, sonst der nächste Faktor (`sin x`, `√2`).
  /// Eine Klammer ist genau das Argument – `sin(x)^2` ist `(sin x)²`.
  MathNode _argument(String name) {
    if (_peek.kind == _K.end) throw MathInputException('Nach „$name“ fehlt das Argument.');
    if (_peek.kind == _K.open) return _primary();
    return _power();
  }
}
