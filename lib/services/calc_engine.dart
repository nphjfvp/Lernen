import 'dart:math' as math;

/// Fehler beim Auswerten eines Ausdrucks – die Meldung ist für die Anzeige
/// gedacht (deutsch, ohne Fachbegriffe des Parsers).
class CalcException implements Exception {
  CalcException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Eine Größe: ein Wert oder eine Reihe von Werten (z.B. eine Messreihe). Ein
/// einzelner Wert ist eine Reihe der Länge 1 und passt sich jeder anderen
/// Länge an (Broadcasting).
typedef CalcVec = List<double>;

enum _Kind { number, ident, op, open, close, comma, end }

class _Token {
  const _Token(this.kind, this.text, {this.value, required this.at});

  final _Kind kind;
  final String text;
  final double? value;
  final int at;
}

/// Sicherer Ausdrucks-Auswerter für die Rechenhilfe. Die KI schlägt Formeln
/// vor, die App rechnet – Sprachmodelle verrechnen sich, ein Auswerter nicht.
/// Kein `eval`: nur Zahlen, Größen aus [evaluate]s `vars`, `+ - * / ^`,
/// Klammern und die Funktionen in [functionNames].
///
/// Dezimalzahlen mit Punkt, Argumente mit `,` oder `;` getrennt. Als
/// Malzeichen gelten auch `·`, `×`, `⋅`; `÷` als Geteilt, `−` als Minus, `**`
/// als Potenz. Es gibt KEIN unsichtbares Malzeichen (`2x` ist ein Fehler).
class CalcEngine {
  CalcEngine._();

  static const constants = {'pi': math.pi, 'e': math.e};

  static const _elementwise1 = <String, double Function(double)>{
    'sqrt': math.sqrt,
    'cbrt': _cbrt,
    'abs': _abs,
    'sin': math.sin,
    'cos': math.cos,
    'tan': math.tan,
    'asin': math.asin,
    'acos': math.acos,
    'atan': math.atan,
    'sinh': _sinh,
    'cosh': _cosh,
    'tanh': _tanh,
    'ln': math.log,
    'lg': _log10,
    'log10': _log10,
    'log2': _log2,
    'exp': math.exp,
    'sign': _sign,
    'floor': _floor,
    'ceil': _ceil,
    'rad': _rad,
    'deg': _deg,
  };

  static const _elementwise2 = <String, double Function(double, double)>{
    'pow': _pow,
    'atan2': math.atan2,
    'hypot': _hypot,
    'mod': _mod,
  };

  static const _aggregates = {
    'sum',
    'mean',
    'avg',
    'median',
    'stdev',
    'stdevp',
    'var',
    'count',
    'n',
    'rms',
    'prod',
    'first',
    'last',
  };

  static const _regressions = {'slope', 'intercept', 'r2', 'corr'};

  /// Alle Namen, die als Funktion oder Konstante belegt sind (keine Größe darf
  /// so heißen).
  static final Set<String> reservedNames = {
    ...constants.keys,
    ..._elementwise1.keys,
    ..._elementwise2.keys,
    ..._aggregates,
    ..._regressions,
    'min',
    'max',
    'round',
    'log',
  };

  /// Für die Aufgabenbeschreibung an die KI.
  static const functionNames =
      'sqrt, cbrt, abs, sin, cos, tan, asin, acos, atan, atan2, sinh, cosh, tanh, ln, lg (=log10), log2, exp, '
      'log(x; Basis), pow, hypot, mod, sign, floor, ceil, round(x; Stellen), rad (Grad→Bogenmaß), deg, '
      'Konstanten pi und e; über eine Reihe: sum, mean, median, min, max, stdev (Stichprobe), stdevp, var, '
      'count, rms, prod, first, last; über zwei Reihen: slope, intercept, r2, corr';

  static final _identStart = RegExp(r'[\p{L}_]', unicode: true);
  static final _identPart = RegExp(r'[\p{L}\p{N}_]', unicode: true);
  static final _digit = RegExp(r'[0-9]');

  // -- Zerlegen -----------------------------------------------------------------

  static List<_Token> _tokenize(String src) {
    final tokens = <_Token>[];
    var i = 0;
    while (i < src.length) {
      final ch = src[i];
      if (ch.trim().isEmpty) {
        i++;
        continue;
      }
      if (_digit.hasMatch(ch) || (ch == '.' && i + 1 < src.length && _digit.hasMatch(src[i + 1]))) {
        final start = i;
        while (i < src.length && _digit.hasMatch(src[i])) {
          i++;
        }
        if (i < src.length && src[i] == '.') {
          i++;
          while (i < src.length && _digit.hasMatch(src[i])) {
            i++;
          }
        }
        // Exponent nur, wenn Ziffern folgen – sonst ist "2e" Zahl mal Konstante.
        if (i < src.length && (src[i] == 'e' || src[i] == 'E')) {
          var j = i + 1;
          if (j < src.length && (src[j] == '+' || src[j] == '-')) j++;
          if (j < src.length && _digit.hasMatch(src[j])) {
            while (j < src.length && _digit.hasMatch(src[j])) {
              j++;
            }
            i = j;
          }
        }
        final text = src.substring(start, i);
        final value = double.tryParse(text);
        if (value == null) throw CalcException('Ungültige Zahl „$text“.');
        tokens.add(_Token(_Kind.number, text, value: value, at: start));
        continue;
      }
      if (_identStart.hasMatch(ch)) {
        final start = i;
        while (i < src.length && _identPart.hasMatch(src[i])) {
          i++;
        }
        tokens.add(_Token(_Kind.ident, src.substring(start, i), at: start));
        continue;
      }
      switch (ch) {
        case '+':
          tokens.add(_Token(_Kind.op, '+', at: i));
        case '-' || '−' || '–':
          tokens.add(_Token(_Kind.op, '-', at: i));
        case '*' || '·' || '×' || '⋅' || '∙':
          if (ch == '*' && i + 1 < src.length && src[i + 1] == '*') {
            tokens.add(_Token(_Kind.op, '^', at: i));
            i++;
          } else {
            tokens.add(_Token(_Kind.op, '*', at: i));
          }
        case '/' || '÷':
          tokens.add(_Token(_Kind.op, '/', at: i));
        case '^':
          tokens.add(_Token(_Kind.op, '^', at: i));
        case '(':
          tokens.add(_Token(_Kind.open, '(', at: i));
        case ')':
          tokens.add(_Token(_Kind.close, ')', at: i));
        case ',' || ';':
          tokens.add(_Token(_Kind.comma, ',', at: i));
        default:
          throw CalcException('Unerwartetes Zeichen „$ch“ im Ausdruck „$src“.');
      }
      i++;
    }
    tokens.add(_Token(_Kind.end, '', at: src.length));
    return tokens;
  }

  /// Die Größen, die [expression] verwendet (ohne Funktionen und Konstanten,
  /// die nicht überschrieben sind).
  static Set<String> variablesOf(String expression, {Set<String> known = const {}}) {
    final tokens = _tokenize(expression);
    final result = <String>{};
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.kind != _Kind.ident) continue;
      final isCall = i + 1 < tokens.length && tokens[i + 1].kind == _Kind.open;
      if (isCall) continue;
      if (constants.containsKey(t.text) && !known.contains(t.text)) continue;
      result.add(t.text);
    }
    return result;
  }

  /// Der Ausdruck mit Zahlen statt Größen, z.B. `U / I` → `12,3 V / 0,45 A`
  /// ([replacements] nennt je Größe den Text) – für den Rechenweg. Malzeichen
  /// werden als `·` gesetzt.
  static String substitute(String expression, Map<String, String> replacements) {
    final tokens = _tokenize(expression);
    final out = StringBuffer();
    _Token? previous;
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.kind == _Kind.end) break;
      switch (t.kind) {
        case _Kind.ident:
          final isCall = i + 1 < tokens.length && tokens[i + 1].kind == _Kind.open;
          out.write(!isCall && replacements.containsKey(t.text) ? replacements[t.text] : t.text);
        case _Kind.number:
          out.write(t.text.replaceAll('.', ','));
        case _Kind.op:
          final unary = previous == null ||
              previous.kind == _Kind.op ||
              previous.kind == _Kind.open ||
              previous.kind == _Kind.comma;
          if (unary) {
            out.write(t.text == '-' ? '-' : '');
          } else if (t.text == '^') {
            out.write('^');
          } else {
            out.write(' ${t.text == '*' ? '·' : t.text} ');
          }
        case _Kind.open:
          out.write('(');
        case _Kind.close:
          out.write(')');
        case _Kind.comma:
          out.write('; ');
        case _Kind.end:
          break;
      }
      previous = t;
    }
    return out.toString();
  }

  // -- Auswerten ------------------------------------------------------------------

  /// Wertet [expression] mit den Größen [vars] aus. Wirft [CalcException].
  static CalcVec evaluate(String expression, Map<String, CalcVec> vars) {
    if (expression.trim().isEmpty) throw CalcException('Der Ausdruck ist leer.');
    final parser = _Parser(_tokenize(expression), vars, expression);
    final result = parser.parse();
    for (final v in result) {
      if (v.isNaN || v.isInfinite) {
        throw CalcException(
          'Das Ergebnis ist nicht definiert (Division durch 0, Wurzel oder Logarithmus einer unzulässigen Zahl?).',
        );
      }
    }
    return result;
  }

  /// Ob [name] als Größe erlaubt ist.
  static bool isValidSymbol(String name) =>
      name.isNotEmpty &&
      _identStart.hasMatch(name[0]) &&
      name.split('').every(_identPart.hasMatch) &&
      !reservedNames.contains(name);

  // -- Zahlen einlesen und anzeigen -------------------------------------------------

  static const _superscript = {
    '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9', //
    '⁻': '-', '⁺': '+',
  };

  /// Liest eine Zahl, wie Menschen sie schreiben: `1,5`, `1.5`, `-3`, `1e-3`,
  /// `1,5·10^-3`, `2,2 × 10⁻⁶`, `1.234,5`, `1,234.5`. `null`, wenn es keine
  /// Zahl ist (Einheiten bleiben draußen).
  static double? parseNumber(Object? raw) {
    if (raw is num) return raw.isFinite ? raw.toDouble() : null;
    if (raw == null) return null;
    var s = raw.toString().trim();
    if (s.isEmpty) return null;
    s = s.split('').map((c) => _superscript[c] ?? c).join();
    s = s.replaceAll(RegExp(r'[\s   ]'), '').replaceAll('−', '-').replaceAll('–', '-');
    final power = RegExp(r'^([+-]?[\d.,]+)(?:[·×x*⋅]10\^?\(?([+-]?\d+)\)?)$', caseSensitive: false).firstMatch(s);
    double? mantissa;
    var exponent = 0;
    if (power != null) {
      mantissa = _plainNumber(power.group(1)!);
      exponent = int.tryParse(power.group(2)!) ?? 0;
    } else {
      final sci = RegExp(r'^([+-]?[\d.,]+)[eE]([+-]?\d+)$').firstMatch(s);
      if (sci != null) {
        mantissa = _plainNumber(sci.group(1)!);
        exponent = int.tryParse(sci.group(2)!) ?? 0;
      } else {
        mantissa = _plainNumber(s);
      }
    }
    if (mantissa == null) return null;
    final value = exponent == 0 ? mantissa : mantissa * math.pow(10, exponent);
    return value.isFinite ? value : null;
  }

  static double? _plainNumber(String s) {
    final sign = s.startsWith('-') ? -1 : 1;
    var body = s.replaceFirst(RegExp(r'^[+-]'), '');
    if (body.isEmpty || !RegExp(r'^[\d.,]+$').hasMatch(body)) return null;
    final lastComma = body.lastIndexOf(',');
    final lastDot = body.lastIndexOf('.');
    if (lastComma >= 0 && lastDot >= 0) {
      // Das spätere Zeichen ist das Dezimalzeichen, das andere trennt Tausender.
      final decimal = lastComma > lastDot ? ',' : '.';
      final group = decimal == ',' ? '.' : ',';
      body = body.replaceAll(group, '').replaceAll(decimal, '.');
    } else if (lastComma >= 0) {
      if (','.allMatches(body).length > 1) return null;
      body = body.replaceAll(',', '.');
    } else if ('.'.allMatches(body).length > 1) {
      return null;
    }
    final value = double.tryParse(body);
    return value == null ? null : sign * value;
  }

  static const _superscriptDigits = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];

  static String _superscriptOf(int n) => [
        if (n < 0) '⁻',
        for (final d in n.abs().toString().split('')) _superscriptDigits[int.parse(d)],
      ].join();

  /// Zahl für die Anzeige: deutsches Komma, [sig] gültige Ziffern, sehr große
  /// und sehr kleine Werte als Zehnerpotenz (`1,234 · 10⁻⁶`).
  static String format(double v, {int sig = 4}) {
    if (v.isNaN) return '–';
    if (v.isInfinite) return v > 0 ? '∞' : '-∞';
    if (v == 0) return '0';
    final exp = int.parse(v.toStringAsExponential(sig - 1).split('e')[1]);
    if (exp >= 6 || exp < -3) {
      final parts = v.toStringAsExponential(sig - 1).split('e');
      return '${_trimZeros(parts[0]).replaceAll('.', ',')} · 10${_superscriptOf(int.parse(parts[1]))}';
    }
    final decimals = (sig - 1 - exp).clamp(0, 12);
    return _trimZeros(v.toStringAsFixed(decimals)).replaceAll('.', ',');
  }

  static String _trimZeros(String s) {
    if (!s.contains('.')) return s;
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  // -- Kleine Rechenfunktionen ------------------------------------------------------

  static double _cbrt(double x) => x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();
  static double _abs(double x) => x.abs();
  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
  static double _tanh(double x) {
    if (x > 20) return 1;
    if (x < -20) return -1;
    final a = math.exp(x), b = math.exp(-x);
    return (a - b) / (a + b);
  }

  static double _log10(double x) => math.log(x) / math.ln10;
  static double _log2(double x) => math.log(x) / math.ln2;
  static double _sign(double x) => x.isNaN ? x : (x > 0 ? 1 : (x < 0 ? -1 : 0));
  static double _floor(double x) => x.floorToDouble();
  static double _ceil(double x) => x.ceilToDouble();
  static double _rad(double x) => x * math.pi / 180;
  static double _deg(double x) => x * 180 / math.pi;
  static double _pow(double a, double b) => math.pow(a, b).toDouble();
  static double _hypot(double a, double b) => math.sqrt(a * a + b * b);
  static double _mod(double a, double b) => b == 0 ? double.nan : a - b * (a / b).floorToDouble();
}

class _Parser {
  _Parser(this._tokens, this._vars, this._source);

  final List<_Token> _tokens;
  final Map<String, CalcVec> _vars;
  final String _source;
  var _pos = 0;

  _Token get _peek => _tokens[_pos];

  CalcVec parse() {
    final result = _expression();
    if (_peek.kind != _Kind.end) {
      throw CalcException('Unerwartetes „${_peek.text}“ im Ausdruck „$_source“.');
    }
    return result;
  }

  bool _isOp(String op) => _peek.kind == _Kind.op && _peek.text == op;

  CalcVec _expression() {
    var left = _term();
    while (_isOp('+') || _isOp('-')) {
      final op = _tokens[_pos++].text;
      final right = _term();
      left = _zip(left, right, op == '+' ? (a, b) => a + b : (a, b) => a - b);
    }
    return left;
  }

  CalcVec _term() {
    var left = _unary();
    while (_isOp('*') || _isOp('/')) {
      final op = _tokens[_pos++].text;
      final right = _unary();
      left = _zip(left, right, op == '*' ? (a, b) => a * b : (a, b) => a / b);
    }
    return left;
  }

  CalcVec _unary() {
    if (_isOp('-')) {
      _pos++;
      return [for (final v in _unary()) -v];
    }
    if (_isOp('+')) {
      _pos++;
      return _unary();
    }
    return _power();
  }

  CalcVec _power() {
    final base = _primary();
    if (_isOp('^')) {
      _pos++;
      final exponent = _unary(); // rechtsassoziativ: 2^3^2 = 2^(3^2)
      return _zip(base, exponent, (a, b) => math.pow(a, b).toDouble());
    }
    return base;
  }

  CalcVec _primary() {
    final t = _peek;
    switch (t.kind) {
      case _Kind.number:
        _pos++;
        return [t.value!];
      case _Kind.open:
        _pos++;
        final inner = _expression();
        _expectClose();
        return inner;
      case _Kind.ident:
        _pos++;
        if (_peek.kind == _Kind.open) {
          _pos++;
          final args = <CalcVec>[];
          if (_peek.kind != _Kind.close) {
            args.add(_expression());
            while (_peek.kind == _Kind.comma) {
              _pos++;
              args.add(_expression());
            }
          }
          _expectClose();
          return _call(t.text, args);
        }
        final variable = _vars[t.text];
        if (variable != null) return variable;
        final constant = CalcEngine.constants[t.text];
        if (constant != null) return [constant];
        throw CalcException('Unbekannte Größe „${t.text}“.');
      case _Kind.end:
        throw CalcException('Der Ausdruck „$_source“ endet unerwartet.');
      default:
        throw CalcException('Unerwartetes „${t.text}“ im Ausdruck „$_source“.');
    }
  }

  void _expectClose() {
    if (_peek.kind != _Kind.close) throw CalcException('Eine Klammer im Ausdruck „$_source“ wird nicht geschlossen.');
    _pos++;
  }

  static CalcVec _zip(CalcVec a, CalcVec b, double Function(double, double) f) {
    if (a.length == b.length) return [for (var i = 0; i < a.length; i++) f(a[i], b[i])];
    if (a.length == 1) return [for (final y in b) f(a[0], y)];
    if (b.length == 1) return [for (final x in a) f(x, b[0])];
    throw CalcException('Die Wertreihen haben unterschiedlich viele Werte (${a.length} und ${b.length}).');
  }

  CalcVec _call(String name, List<CalcVec> args) {
    void arity(int n) {
      if (args.length != n) throw CalcException('„$name“ braucht $n Wert${n == 1 ? '' : 'e'}, nicht ${args.length}.');
    }

    final one = CalcEngine._elementwise1[name];
    if (one != null) {
      arity(1);
      return [for (final v in args[0]) one(v)];
    }
    final two = CalcEngine._elementwise2[name];
    if (two != null) {
      arity(2);
      return _zip(args[0], args[1], two);
    }
    switch (name) {
      case 'log':
        if (args.length == 1) return [for (final v in args[0]) CalcEngine._log10(v)];
        arity(2);
        return _zip(args[0], args[1], (x, base) => math.log(x) / math.log(base));
      case 'round':
        if (args.length == 1) return [for (final v in args[0]) v.roundToDouble()];
        arity(2);
        return _zip(args[0], args[1], (x, digits) {
          final f = math.pow(10, digits.round()).toDouble();
          return (x * f).roundToDouble() / f;
        });
      case 'min' || 'max':
        final isMin = name == 'min';
        if (args.length == 1) {
          if (args[0].isEmpty) throw CalcException('„$name“ braucht mindestens einen Wert.');
          return [args[0].reduce((a, b) => (isMin ? b < a : b > a) ? b : a)];
        }
        var result = args[0];
        for (final next in args.skip(1)) {
          result = _zip(result, next, (a, b) => isMin ? math.min(a, b) : math.max(a, b));
        }
        return result;
    }
    if (CalcEngine._aggregates.contains(name)) {
      arity(1);
      return [_aggregate(name, args[0])];
    }
    if (CalcEngine._regressions.contains(name)) {
      arity(2);
      return [_regression(name, args[0], args[1])];
    }
    throw CalcException('Unbekannte Funktion „$name“.');
  }

  static double _aggregate(String name, CalcVec v) {
    if (v.isEmpty) throw CalcException('„$name“ braucht mindestens einen Wert.');
    final n = v.length;
    final sum = v.fold<double>(0, (a, b) => a + b);
    final mean = sum / n;
    double squares() => v.fold<double>(0, (a, b) => a + (b - mean) * (b - mean));
    switch (name) {
      case 'sum':
        return sum;
      case 'mean' || 'avg':
        return mean;
      case 'count' || 'n':
        return n.toDouble();
      case 'prod':
        return v.fold<double>(1, (a, b) => a * b);
      case 'first':
        return v.first;
      case 'last':
        return v.last;
      case 'rms':
        return math.sqrt(v.fold<double>(0, (a, b) => a + b * b) / n);
      case 'median':
        final sorted = [...v]..sort();
        return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
      case 'var':
        if (n < 2) throw CalcException('Für die Varianz braucht es mindestens zwei Werte.');
        return squares() / (n - 1);
      case 'stdev':
        if (n < 2) throw CalcException('Für die Standardabweichung braucht es mindestens zwei Werte.');
        return math.sqrt(squares() / (n - 1));
      case 'stdevp':
        return math.sqrt(squares() / n);
    }
    throw CalcException('Unbekannte Funktion „$name“.');
  }

  static double _regression(String name, CalcVec x, CalcVec y) {
    if (x.length != y.length) {
      throw CalcException('„$name“ braucht gleich viele Werte für x und y (${x.length} und ${y.length}).');
    }
    if (x.length < 2) throw CalcException('„$name“ braucht mindestens zwei Wertepaare.');
    final n = x.length;
    final mx = x.fold<double>(0, (a, b) => a + b) / n;
    final my = y.fold<double>(0, (a, b) => a + b) / n;
    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (var i = 0; i < n; i++) {
      sxx += (x[i] - mx) * (x[i] - mx);
      sxy += (x[i] - mx) * (y[i] - my);
      syy += (y[i] - my) * (y[i] - my);
    }
    if (sxx == 0) throw CalcException('Alle x-Werte sind gleich – eine Gerade ist nicht bestimmt.');
    switch (name) {
      case 'slope':
        return sxy / sxx;
      case 'intercept':
        return my - sxy / sxx * mx;
      case 'corr':
        if (syy == 0) throw CalcException('Alle y-Werte sind gleich – die Korrelation ist nicht bestimmt.');
        return sxy / math.sqrt(sxx * syy);
      case 'r2':
        if (syy == 0) throw CalcException('Alle y-Werte sind gleich – das Bestimmtheitsmaß ist nicht bestimmt.');
        return sxy * sxy / (sxx * syy);
    }
    throw CalcException('Unbekannte Funktion „$name“.');
  }
}
