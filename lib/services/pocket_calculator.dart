import 'dart:math' as math;

import 'math_input.dart';

/// Winkelmaß für sin/cos/tan.
enum AngleUnit { deg, rad }

/// Was nach „=“ im Display steht.
class PocketResult {
  const PocketResult({required this.value, this.label = '', this.second = ''});

  final double value;

  /// Vor dem Wert, z.B. „x =“ bei SOLVE.
  final String label;

  /// Zweite Zeile (SOLVE: „L−R = 0“).
  final String second;
}

/// Ein funktionierender Taschenrechner mit Tastenbelegung wie der fx-991DE X
/// (Rechnen-Modus): Eingabe als Token mit Cursor, Vorlagen für Bruch,
/// Potenz und Wurzel, Zweitbelegungen über SHIFT/ALPHA, Ergebnis exakt
/// (Bruch, Wurzel, π) oder dezimal (S⇔D). Gerechnet wird mit MathExpression
/// (inklusive ∫ und d/dx im Rechenweg-Modus).
class PocketCalculator {
  // Vorlagen: Anfang, (Trenner,) Ende.
  static const fracOpen = '⟦F', fracMid = '⟧F⟦', fracClose = 'F⟧';
  static const powOpen = '⟦P', powClose = 'P⟧';
  static const sqrtOpen = '⟦R', sqrtClose = 'R⟧';
  static const _structOpen = {fracOpen, powOpen, sqrtOpen};
  static const _structClose = {fracClose, powClose, sqrtClose};

  /// Funktionen, die eine Klammer öffnen (mit „)“ geschlossen).
  static const functionTokens = {
    'sin(', 'cos(', 'tan(', 'asin(', 'acos(', 'atan(', 'ln(', 'log(', '∛(', '∫(', 'd/dx(', 'abs(',
  };

  final List<String> tokens = [];
  int cursor = 0;
  bool shift = false;
  bool alpha = false;
  AngleUnit angle = AngleUnit.deg;
  double ans = 0;
  double memory = 0;
  double xValue = 0;

  /// Ergebnis der letzten Rechnung (null = Eingabe läuft).
  PocketResult? result;
  String? error;

  /// Ergebnis dezimal statt exakt (S⇔D).
  bool decimal = false;

  /// ENG-Darstellung (Exponent in Dreierschritten).
  bool engineering = false;

  /// CALC: fragt nach dem Wert von x.
  bool askingX = false;
  final List<String> xTokens = [];

  /// Kurzer Hinweis im Display (z.B. „Bogenmaß“).
  String note = '';

  bool get editing => result == null && error == null;

  // ---------------------------------------------------------------------------
  // Tasten
  // ---------------------------------------------------------------------------

  void press(String key) {
    note = '';
    if (key == 'SHIFT') {
      shift = !shift;
      alpha = false;
      return;
    }
    if (key == 'ALPHA') {
      alpha = !alpha;
      shift = false;
      return;
    }
    final s = shift, a = alpha;
    shift = false;
    alpha = false;

    if (askingX) return _pressAskingX(key);

    switch (key) {
      case 'AC':
        if (s) {
          note = 'Ausschalten gibt es hier nicht';
          return;
        }
        _clear();
        return;
      case 'ON':
        _clear();
        error = null;
        return;
      case 'DEL':
        _edit();
        _delete();
        return;
      case 'LEFT':
        _edit(atEnd: true);
        if (cursor > 0) cursor--;
        return;
      case 'RIGHT':
        _edit(atStart: true);
        if (cursor < tokens.length) cursor++;
        return;
      case 'DOWN':
        _edit();
        _down();
        return;
      case 'UP':
        _edit();
        _up();
        return;
      case 'EQ':
        if (s) {
          // SHIFT = : Ergebnis dezimal
          _evaluate();
          decimal = true;
          return;
        }
        _evaluate();
        return;
      case 'SD':
        if (result != null) decimal = !decimal;
        return;
      case 'ENG':
        if (result != null) engineering = !engineering;
        return;
      case 'MENU':
        if (s) {
          angle = angle == AngleUnit.deg ? AngleUnit.rad : AngleUnit.deg;
          note = angle == AngleUnit.deg ? 'Winkel: Grad (D)' : 'Winkel: Bogenmaß (R)';
        } else {
          note = 'Nur der Rechnen-Modus wird simuliert';
        }
        return;
      case 'MPLUS':
        if (result != null || _evaluate()) {
          memory += s ? -result!.value : result!.value;
          note = s ? 'M− ' : 'M+';
        }
        return;
      case 'CALC':
        if (s) {
          _solve();
          return;
        }
        if (a) {
          _insert(['=']);
          return;
        }
        _edit();
        if (!tokens.contains('x')) {
          note = 'CALC fragt nach x – in der Rechnung steht kein x';
          return;
        }
        askingX = true;
        xTokens.clear();
        return;
      case 'OPTN' || 'DMS' || 'STO':
        note = 'Diese Funktion simuliert die App nicht';
        return;
    }

    final insert = _tokensFor(key, shift: s, alpha: a);
    if (insert == null) {
      note = 'Diese Funktion simuliert die App nicht';
      return;
    }
    if (insert.isEmpty) return;
    // Nach einem Ergebnis: Rechenzeichen rechnen mit Ans weiter, alles andere
    // beginnt eine neue Rechnung.
    if (!editing) {
      final continues = const {'+', '−', '×', '÷', '²', '³', '⁻¹', '!', powOpen}.contains(insert.first);
      _clearInput();
      if (continues) {
        tokens.add('Ans');
        cursor = 1;
      }
    }
    _insert(insert);
  }

  void _pressAskingX(String key) {
    switch (key) {
      case 'AC':
        askingX = false;
        return;
      case 'DEL':
        if (xTokens.isNotEmpty) xTokens.removeLast();
        return;
      case 'EQ':
        if (xTokens.isNotEmpty) {
          final v = _value(xTokens);
          if (v == null || !v.isFinite) {
            error = 'Syntax ERROR';
            askingX = false;
            return;
          }
          xValue = v;
        }
        askingX = false;
        _evaluate();
        return;
    }
    final t = _tokensFor(key);
    if (t != null && t.length == 1 && RegExp(r'^[0-9.−]$').hasMatch(t.first)) xTokens.add(t.first);
  }

  /// Welche Token eine Taste einfügt (null = nicht simuliert).
  List<String>? _tokensFor(String key, {bool shift = false, bool alpha = false}) {
    if (RegExp(r'^[0-9]$').hasMatch(key)) return [key];
    if (alpha) {
      return switch (key) {
        'EXP10' => ['e'],
        'RPAR' || 'X' => ['x'],
        'CALC' => ['='],
        _ => null,
      };
    }
    if (shift) {
      return switch (key) {
        'LN' => ['e', powOpen, powClose],
        'LOG' => ['1', '0', powOpen, powClose],
        'SQRT' => ['∛('],
        'SQ' => ['³'],
        'INV' => ['!'],
        'SIN' => ['asin('],
        'COS' => ['acos('],
        'TAN' => ['atan('],
        'EXP10' => ['π'],
        'RPAR' => [','],
        'INT' => ['d/dx('],
        'NEG' => ['abs('],
        'FRAC' => [fracOpen, fracMid, fracClose],
        'POW' => [sqrtOpen, sqrtClose],
        _ => null,
      };
    }
    return switch (key) {
      'DOT' => ['.'],
      'ADD' => ['+'],
      'SUB' || 'NEG' => ['−'],
      'MUL' => ['×'],
      'DIV' => ['÷'],
      'LPAR' => ['('],
      'RPAR' => [')'],
      'SQ' => ['²'],
      'INV' => ['⁻¹'],
      'POW' => [powOpen, powClose],
      'FRAC' => [fracOpen, fracMid, fracClose],
      'SQRT' => [sqrtOpen, sqrtClose],
      'LN' => ['ln('],
      'LOG' => ['log('],
      'SIN' => ['sin('],
      'COS' => ['cos('],
      'TAN' => ['tan('],
      'X' => ['x'],
      'ANS' => ['Ans'],
      'EXP10' => ['×10', powOpen, powClose],
      'INT' => ['∫('],
      'ENG' => [],
      _ => null,
    };
  }

  void _clear() {
    _clearInput();
    askingX = false;
    decimal = false;
    engineering = false;
  }

  void _clearInput() {
    tokens.clear();
    cursor = 0;
    result = null;
    error = null;
    decimal = false;
    engineering = false;
  }

  /// Zurück in die Eingabe (nach Ergebnis oder Fehler).
  void _edit({bool atEnd = false, bool atStart = false}) {
    if (editing) return;
    result = null;
    error = null;
    decimal = false;
    engineering = false;
    if (atStart) cursor = 0;
    if (atEnd) cursor = tokens.length;
  }

  void _insert(List<String> insert) {
    // Bruch nach einer Zahl: die Zahl wird zum Zähler.
    if (insert.first == fracOpen && cursor > 0 && _isNumberToken(tokens[cursor - 1])) {
      var start = cursor;
      while (start > 0 && _isNumberToken(tokens[start - 1])) {
        start--;
      }
      final number = tokens.sublist(start, cursor);
      tokens.replaceRange(start, cursor, [fracOpen, ...number, fracMid, fracClose]);
      cursor = start + number.length + 2;
      return;
    }
    tokens.insertAll(cursor, insert);
    // In die erste Lücke einer Vorlage, sonst dahinter.
    final open = insert.indexWhere(_structOpen.contains);
    cursor += open >= 0 ? open + 1 : insert.length;
  }

  static bool _isNumberToken(String t) => RegExp(r'^[0-9.]$').hasMatch(t);

  void _delete() {
    if (cursor == 0) return;
    final t = tokens[cursor - 1];
    if (_structClose.contains(t) || t == fracMid) {
      cursor--;
      return;
    }
    if (_structOpen.contains(t)) {
      // Vorlage auflösen, Inhalt bleibt.
      final end = _matchingClose(cursor - 1);
      final kind = t;
      tokens.removeAt(end);
      if (kind == fracOpen) {
        final mid = tokens.indexOf(fracMid, cursor - 1);
        if (mid >= 0 && mid < end) tokens[mid] = '÷';
      }
      tokens.removeAt(cursor - 1);
      cursor--;
      return;
    }
    tokens.removeAt(cursor - 1);
    cursor--;
  }

  int _matchingClose(int open) {
    var depth = 0;
    for (var i = open; i < tokens.length; i++) {
      if (_structOpen.contains(tokens[i])) depth++;
      if (_structClose.contains(tokens[i])) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return tokens.length - 1;
  }

  /// Innerste Vorlage um den Cursor: Index ihres Anfangs.
  int? _enclosing() {
    var depth = 0;
    for (var i = cursor - 1; i >= 0; i--) {
      final t = tokens[i];
      if (_structClose.contains(t)) depth++;
      if (_structOpen.contains(t)) {
        if (depth == 0) return i;
        depth--;
      }
    }
    return null;
  }

  void _down() {
    final open = _enclosing();
    if (open == null || tokens[open] != fracOpen) return;
    // Im Zähler? Dann in den Nenner.
    var depth = 0;
    for (var i = open + 1; i < tokens.length; i++) {
      final t = tokens[i];
      if (_structOpen.contains(t)) depth++;
      if (_structClose.contains(t)) depth--;
      if (t == fracMid && depth == 0) {
        if (cursor <= i) cursor = i + 1;
        return;
      }
    }
  }

  void _up() {
    final open = _enclosing();
    if (open == null || tokens[open] != fracOpen) return;
    var depth = 0;
    for (var i = open + 1; i < tokens.length; i++) {
      final t = tokens[i];
      if (_structOpen.contains(t)) depth++;
      if (_structClose.contains(t)) depth--;
      if (t == fracMid && depth == 0) {
        if (cursor > i) cursor = i;
        return;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Rechnen
  // ---------------------------------------------------------------------------

  bool _evaluate() {
    if (tokens.isEmpty) return false;
    if (tokens.contains('=')) {
      error = null;
      note = 'Gleichung: mit SHIFT CALC (SOLVE) lösen';
      return false;
    }
    final v = _value(tokens);
    if (v == null) {
      error = 'Syntax ERROR';
      result = null;
      return false;
    }
    if (!v.isFinite) {
      error = 'Math ERROR';
      result = null;
      return false;
    }
    result = PocketResult(value: _clean(v));
    error = null;
    decimal = false;
    engineering = false;
    ans = result!.value;
    return true;
  }

  /// SHIFT CALC: Gleichung (oder Term = 0) nach x lösen.
  void _solve() {
    _edit();
    if (!tokens.contains('x')) {
      note = 'SOLVE braucht ein x in der Gleichung';
      return;
    }
    final eq = tokens.indexOf('=');
    final left = eq < 0 ? tokens : tokens.sublist(0, eq);
    final right = eq < 0 ? const ['0'] : tokens.sublist(eq + 1);
    final l = _expression(left), r = _expression(right);
    if (l == null || r == null) {
      error = 'Syntax ERROR';
      return;
    }
    double f(double x) => l.evaluate({'x': x}) - r.evaluate({'x': x});
    final root = _findRoot(f, xValue);
    if (root == null) {
      error = 'Keine Lösung gefunden';
      return;
    }
    xValue = _clean(root);
    result = PocketResult(value: xValue, label: 'x=', second: 'L−R = 0');
    error = null;
    decimal = false;
  }

  static double? _findRoot(double Function(double) f, double start) {
    double? newton(double x0) {
      var x = x0;
      for (var i = 0; i < 80; i++) {
        final y = f(x);
        if (!y.isFinite) return null;
        if (y.abs() < 1e-13) return x;
        final h = 1e-6 * math.max(1, x.abs());
        final d = (f(x + h) - f(x - h)) / (2 * h);
        if (!d.isFinite || d == 0) return null;
        final next = x - y / d;
        if ((next - x).abs() < 1e-14 * math.max(1, x.abs())) return next;
        x = next;
      }
      return f(x).abs() < 1e-9 ? x : null;
    }

    final direct = newton(start);
    if (direct != null) return direct;
    // Vorzeichenwechsel suchen, nahe am Startwert zuerst.
    for (final range in [1.0, 10.0, 100.0, 1000.0]) {
      const n = 400;
      double? prevX, prevY;
      for (var i = 0; i <= n; i++) {
        final x = start - range + 2 * range * i / n;
        final y = f(x);
        if (!y.isFinite) {
          prevX = null;
          continue;
        }
        if (y == 0) return x;
        if (prevX != null && prevY != null && (prevY < 0) != (y < 0)) {
          var a = prevX, b = x, fa = prevY;
          for (var k = 0; k < 200; k++) {
            final m = (a + b) / 2, fm = f(m);
            if ((fa < 0) == (fm < 0)) {
              a = m;
              fa = fm;
            } else {
              b = m;
            }
          }
          final r = (a + b) / 2;
          return newton(r) ?? r;
        }
        prevX = x;
        prevY = y;
      }
    }
    return null;
  }

  /// Rundungsrauschen weg (0,1 + 0,2 → 0,3; sin 180° → 0).
  static double _clean(double v) {
    if (v.abs() < 1e-13) return 0;
    final r = double.parse(v.toStringAsPrecision(14));
    return r;
  }

  double? _value(List<String> t) {
    final e = _expression(t);
    if (e == null) return null;
    try {
      return e.evaluate({'x': xValue});
    } catch (_) {
      return null;
    }
  }

  MathExpression? _expression(List<String> t) {
    try {
      final source = toInput(t);
      if (source == null || source.trim().isEmpty) return null;
      return MathExpression.parse(source, calculus: true);
    } on MathInputException {
      return null;
    } on _CalcError {
      return null;
    }
  }

  /// Token → Eingabe-Schreibweise der App (null = unvollständig).
  String? toInput(List<String> t) {
    final out = StringBuffer();
    final closers = <String>[];
    var i = 0;
    while (i < t.length) {
      final tok = t[i];
      switch (tok) {
        case '+':
          out.write('+');
        case '−':
          out.write('-');
        case '×':
          out.write('*');
        case '÷':
          out.write('/');
        case '×10':
          out.write('*10');
        case '(':
          out.write('(');
          closers.add(')');
        case ')':
          if (closers.isEmpty) throw _CalcError();
          out.write(closers.removeLast());
        case 'π':
          out.write('(pi)');
        case 'e':
          out.write('(e)');
        case 'x':
          out.write('x');
        case 'Ans':
          out.write('(${_literal(ans)})');
        case '²':
          out.write('^2');
        case '³':
          out.write('^3');
        case '⁻¹':
          out.write('^(-1)');
        case '!':
          final text = out.toString();
          final m = RegExp(r'(\d+)$').firstMatch(text);
          if (m == null) throw _CalcError();
          final n = int.parse(m[1]!);
          if (n > 170) throw _CalcError();
          var f = 1.0;
          for (var k = 2; k <= n; k++) {
            f *= k;
          }
          out
            ..clear()
            ..write(text.substring(0, m.start))
            ..write('(${_literal(f)})');
        case ',' || '=':
          throw _CalcError();
        case fracOpen:
          final mid = _find(t, i, fracMid), end = _findClose(t, i);
          final num = t.sublist(i + 1, mid), den = t.sublist(mid + 1, end);
          if (num.isEmpty || den.isEmpty) throw _CalcError();
          out.write('((${toInput(num)})/(${toInput(den)}))');
          i = end + 1;
          continue;
        case powOpen:
          final end = _findClose(t, i);
          final inner = t.sublist(i + 1, end);
          if (inner.isEmpty) throw _CalcError();
          out.write('^(${toInput(inner)})');
          i = end + 1;
          continue;
        case sqrtOpen:
          final end = _findClose(t, i);
          final inner = t.sublist(i + 1, end);
          if (inner.isEmpty) throw _CalcError();
          out.write('sqrt(${toInput(inner)})');
          i = end + 1;
          continue;
        case '∫(' || 'd/dx(':
          final end = _findParen(t, i);
          final args = _splitArgs(t.sublist(i + 1, end));
          out.write('(${_literal(_calculus(tok, args))})');
          i = end + 1;
          continue;
        case 'sin(' || 'cos(' || 'tan(':
          final f = tok.substring(0, 3);
          if (angle == AngleUnit.deg) {
            out.write('$f((pi/180)*(');
            closers.add('))');
          } else {
            out.write('$f(');
            closers.add(')');
          }
        case 'asin(' || 'acos(' || 'atan(':
          if (angle == AngleUnit.deg) out.write('(180/pi)*');
          out.write(tok);
          closers.add(')');
        case '∛(':
          out.write('cbrt(');
          closers.add(')');
        case 'ln(' || 'log(' || 'abs(':
          out.write(tok);
          closers.add(')');
        default:
          if (RegExp(r'^[0-9.]$').hasMatch(tok)) {
            out.write(tok);
          } else if (_structClose.contains(tok) || tok == fracMid) {
            throw _CalcError();
          } else {
            out.write(tok);
          }
      }
      i++;
    }
    // Offene Klammern am Ende schließt der Rechner selbst.
    while (closers.isNotEmpty) {
      out.write(closers.removeLast());
    }
    return out.toString();
  }

  static int _find(List<String> t, int from, String what) {
    var depth = 0;
    for (var i = from; i < t.length; i++) {
      if (_structOpen.contains(t[i])) depth++;
      if (_structClose.contains(t[i])) depth--;
      if (t[i] == what && depth == 1) return i;
    }
    throw _CalcError();
  }

  static int _findClose(List<String> t, int open) {
    var depth = 0;
    for (var i = open; i < t.length; i++) {
      if (_structOpen.contains(t[i])) depth++;
      if (_structClose.contains(t[i])) {
        depth--;
        if (depth == 0) return i;
      }
    }
    throw _CalcError();
  }

  /// Passende „)“ zu einer Funktions-Klammer (fehlt sie: Ende).
  static int _findParen(List<String> t, int open) {
    var depth = 0;
    for (var i = open; i < t.length; i++) {
      if (t[i] == '(' || functionTokens.contains(t[i])) depth++;
      if (t[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return t.length;
  }

  static List<List<String>> _splitArgs(List<String> t) {
    final args = <List<String>>[[]];
    var depth = 0;
    for (final tok in t) {
      if (tok == '(' || functionTokens.contains(tok) || _structOpen.contains(tok)) depth++;
      if (tok == ')' || _structClose.contains(tok)) depth--;
      if (tok == ',' && depth == 0) {
        args.add([]);
      } else {
        args.last.add(tok);
      }
    }
    return args;
  }

  /// ∫(f, a, b) bzw. d/dx(f, a) ausrechnen.
  double _calculus(String kind, List<List<String>> args) {
    if (kind == '∫(') {
      if (args.length != 3 || args.any((a) => a.isEmpty)) throw _CalcError();
      final f = toInput(args[0]), a = _value(args[1]), b = _value(args[2]);
      if (f == null || a == null || b == null) throw _CalcError();
      final e = MathExpression.parse('∫_($a)^($b) ($f) dx', calculus: true);
      return e.evaluate();
    }
    if (args.length != 2 || args.any((a) => a.isEmpty)) throw _CalcError();
    final f = toInput(args[0]), at = _value(args[1]);
    if (f == null || at == null) throw _CalcError();
    return MathExpression.parse('d/dx ($f)', calculus: true).evaluate({'x': at});
  }

  static String _literal(double v) => v.toStringAsPrecision(17);

  // ---------------------------------------------------------------------------
  // Anzeige
  // ---------------------------------------------------------------------------

  /// Die Eingabe als LaTeX (natürliche Darstellung), mit Cursor wenn
  /// [withCursor].
  String inputLatex({bool withCursor = true, String cursorColor = '#1D2318'}) {
    final source = askingX ? xTokens : tokens;
    final cur = askingX ? xTokens.length : cursor;
    final mark = '\\textcolor{$cursorColor}{\\vert}';
    final body = _latex(source, 0, source.length, withCursor && editing ? cur : -1, mark);
    return askingX ? 'x? \\; $body' : body;
  }

  String _latex(List<String> t, int from, int to, int cursorAt, String mark) {
    final out = StringBuffer();
    var i = from;
    String group(int a, int b) {
      final inner = _latex(t, a, b, cursorAt, mark);
      return inner.isEmpty ? '\\square' : inner;
    }

    while (i < to) {
      if (i == cursorAt) out.write(mark);
      final tok = t[i];
      switch (tok) {
        case fracOpen:
          final mid = _safeFind(t, i, fracMid), end = _safeClose(t, i);
          out.write('\\frac{${group(i + 1, mid)}}{${group(mid + 1, end)}}');
          i = end + 1;
          continue;
        case powOpen:
          final end = _safeClose(t, i);
          out.write('^{${group(i + 1, end)}}');
          i = end + 1;
          continue;
        case sqrtOpen:
          final end = _safeClose(t, i);
          out.write('\\sqrt{${group(i + 1, end)}}');
          i = end + 1;
          continue;
      }
      out.write(_tokenLatex(tok));
      i++;
    }
    if (cursorAt == to) out.write(mark);
    return out.toString();
  }

  /// Wie [_find]/[_findClose], aber ohne Fehler (Anzeige darf nie scheitern).
  static int _safeFind(List<String> t, int from, String what) {
    try {
      return _find(t, from, what);
    } on _CalcError {
      return t.length;
    }
  }

  static int _safeClose(List<String> t, int open) {
    try {
      return _findClose(t, open);
    } on _CalcError {
      return t.length;
    }
  }

  static String _tokenLatex(String tok) => switch (tok) {
    '.' => '{,}',
    '−' => '-',
    '×' => '\\times ',
    '÷' => '\\div ',
    '×10' => '\\times 10',
    'π' => '\\pi ',
    'Ans' => '\\mathrm{Ans}',
    '²' => '^{2}',
    '³' => '^{3}',
    '⁻¹' => '^{-1}',
    'sin(' => '\\sin(',
    'cos(' => '\\cos(',
    'tan(' => '\\tan(',
    'asin(' => '\\sin^{-1}(',
    'acos(' => '\\cos^{-1}(',
    'atan(' => '\\tan^{-1}(',
    'ln(' => '\\ln(',
    'log(' => '\\log(',
    '∛(' => '\\sqrt[3]{\\,}(',
    '∫(' => '\\int(',
    'd/dx(' => '\\tfrac{d}{dx}(',
    'abs(' => '\\mathrm{Abs}(',
    _ => tok,
  };

  /// Das Ergebnis als LaTeX: exakt (Bruch, Wurzel, π), sonst bzw. mit S⇔D
  /// dezimal.
  String resultLatex() {
    final r = result;
    if (r == null) return '';
    final value = decimal || engineering ? formatDecimal(r.value, engineering: engineering) : exactLatex(r.value);
    return r.label.isEmpty ? value : '${r.label.replaceAll('=', '')} = $value';
  }

  /// Das Ergebnis zum Übernehmen in eine Eingabezeile (Eingabe-Schreibweise).
  String resultInput() {
    final r = result;
    if (r == null) return '';
    if (!decimal) {
      final f = _fraction(r.value);
      if (f != null && f.$2 != 1) return '${f.$1}/${f.$2}';
    }
    return formatDecimal(r.value).replaceAll('{,}', ',').replaceAll(r'\times 10^{', 'e').replaceAll('}', '');
  }

  static String formatDecimal(double v, {bool engineering = false}) {
    if (v == 0) return '0';
    if (engineering) {
      final exp = (math.log(v.abs()) / math.ln10).floor();
      final eng = (exp / 3).floor() * 3;
      final mant = v / math.pow(10, eng);
      return '${_digits(mant)}\\times 10^{$eng}';
    }
    final abs = v.abs();
    if (abs >= 1e10 || abs < 1e-9) {
      final exp = (math.log(abs) / math.ln10).floor();
      final mant = v / math.pow(10, exp);
      return '${_digits(mant)}\\times 10^{$exp}';
    }
    return _digits(v);
  }

  static String _digits(double v) {
    var s = v.toStringAsPrecision(10);
    if (s.contains('e')) return MathExpression.formatNumber(v);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s.replaceAll('.', '{,}');
  }

  static (int, int)? _fraction(double v, {int maxDen = 9999}) {
    if (!v.isFinite || v.abs() > 1e12) return null;
    // Kettenbruch
    var h0 = 0, h1 = 1, k0 = 1, k1 = 0;
    var x = v.abs();
    for (var i = 0; i < 40; i++) {
      final a = x.floor();
      final h2 = a * h1 + h0, k2 = a * k1 + k0;
      if (k2 > maxDen) break;
      h0 = h1;
      h1 = h2;
      k0 = k1;
      k1 = k2;
      if ((h1 / k1 - v.abs()).abs() <= 1e-11 * math.max(1, v.abs())) {
        return (v < 0 ? -h1 : h1, k1);
      }
      final frac = x - a;
      if (frac < 1e-15) break;
      x = 1 / frac;
    }
    return null;
  }

  static String _fracLatex(int p, int q, [String factor = '']) {
    final sign = p < 0 ? '-' : '';
    final n = p.abs();
    if (q == 1) return '$sign${n == 1 && factor.isNotEmpty ? '' : '$n'}$factor';
    return '$sign\\frac{${n == 1 && factor.isNotEmpty ? '' : '$n'}$factor}{$q}';
  }

  static const _squareFree = [2, 3, 5, 6, 7, 10, 11, 13, 14, 15, 17, 19, 21, 22, 23, 26, 29, 30, 31, 33, 34, 35, 37, 38, 39];

  /// Exakte Darstellung, wenn erkennbar: ganze Zahl, Bruch, a·√k/b, a·π/b.
  static String exactLatex(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e10) return MathExpression.formatNumber(v);
    final f = _fraction(v);
    if (f != null) return _fracLatex(f.$1, f.$2);
    for (final k in _squareFree) {
      final g = _fraction(v / math.sqrt(k), maxDen: 999);
      if (g != null && g.$1.abs() < 10000) return _fracLatex(g.$1, g.$2, '\\sqrt{$k}');
    }
    final p = _fraction(v / math.pi, maxDen: 99);
    if (p != null && p.$1.abs() < 1000) return _fracLatex(p.$1, p.$2, '\\pi');
    return formatDecimal(v);
  }
}

class _CalcError implements Exception {}
