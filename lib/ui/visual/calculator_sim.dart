import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/worked_solution.dart';
import '../../services/math_input.dart';
import '../../theme/app_colors.dart';

/// Eine Taste: [id] wie in WorkCalc.keys, Aufdruck, gelbe SHIFT- und rote
/// ALPHA-Belegung darüber.
class CalcKey {
  const CalcKey(this.id, this.label, {this.shift = '', this.alpha = '', this.kind = CalcKeyKind.function});

  final String id;
  final String label;
  final String shift;
  final String alpha;
  final CalcKeyKind kind;
}

enum CalcKeyKind { modifier, control, function, number, operator, action }

/// Tastenfeld nach dem Vorbild des fx-991DE X (vereinfacht: die Lage
/// einzelner Tasten kann abweichen, Namen und Zweitbelegungen passen).
class CalcKeys {
  CalcKeys._();

  static const top = [
    CalcKey('SHIFT', 'SHIFT', kind: CalcKeyKind.modifier),
    CalcKey('ALPHA', 'ALPHA', kind: CalcKeyKind.modifier),
    CalcKey('MENU', 'MENU', shift: 'SETUP', kind: CalcKeyKind.control),
    CalcKey('ON', 'ON', kind: CalcKeyKind.control),
    CalcKey('OPTN', 'OPTN', kind: CalcKeyKind.control),
    CalcKey('CALC', 'CALC', shift: 'SOLVE', alpha: '=', kind: CalcKeyKind.control),
    CalcKey('INT', '∫□', shift: 'd/dx', kind: CalcKeyKind.control),
    CalcKey('X', 'x', kind: CalcKeyKind.control),
  ];

  static const pad = [
    CalcKey('UP', '▲', kind: CalcKeyKind.control),
    CalcKey('LEFT', '◀', kind: CalcKeyKind.control),
    CalcKey('RIGHT', '▶', kind: CalcKeyKind.control),
    CalcKey('DOWN', '▼', kind: CalcKeyKind.control),
  ];

  static const functions = [
    [
      CalcKey('FRAC', '□/□', shift: '□□/□'),
      CalcKey('SQRT', '√□', shift: '∛□'),
      CalcKey('SQ', 'x²', shift: 'x³'),
      CalcKey('POW', 'x^□', shift: '□√□'),
      CalcKey('LOG', 'log', shift: '10^□'),
      CalcKey('LN', 'ln', shift: 'e^□'),
    ],
    [
      CalcKey('NEG', '(−)', alpha: 'A'),
      CalcKey('DMS', "°'\"", alpha: 'B'),
      CalcKey('INV', 'x⁻¹', shift: 'x!', alpha: 'C'),
      CalcKey('SIN', 'sin', shift: 'sin⁻¹', alpha: 'D'),
      CalcKey('COS', 'cos', shift: 'cos⁻¹', alpha: 'E'),
      CalcKey('TAN', 'tan', shift: 'tan⁻¹', alpha: 'F'),
    ],
    [
      CalcKey('STO', 'STO', shift: 'RECALL'),
      CalcKey('ENG', 'ENG'),
      CalcKey('LPAR', '('),
      CalcKey('RPAR', ')', alpha: 'X'),
      CalcKey('SD', 'S⇔D'),
      CalcKey('MPLUS', 'M+', shift: 'M−'),
    ],
  ];

  static const numbers = [
    [
      CalcKey('7', '7', kind: CalcKeyKind.number),
      CalcKey('8', '8', kind: CalcKeyKind.number),
      CalcKey('9', '9', kind: CalcKeyKind.number),
      CalcKey('DEL', 'DEL', shift: 'INS', kind: CalcKeyKind.action),
      CalcKey('AC', 'AC', shift: 'OFF', kind: CalcKeyKind.action),
    ],
    [
      CalcKey('4', '4', kind: CalcKeyKind.number),
      CalcKey('5', '5', kind: CalcKeyKind.number),
      CalcKey('6', '6', kind: CalcKeyKind.number),
      CalcKey('MUL', '×', kind: CalcKeyKind.operator),
      CalcKey('DIV', '÷', kind: CalcKeyKind.operator),
    ],
    [
      CalcKey('1', '1', kind: CalcKeyKind.number),
      CalcKey('2', '2', kind: CalcKeyKind.number),
      CalcKey('3', '3', kind: CalcKeyKind.number),
      CalcKey('ADD', '+', kind: CalcKeyKind.operator),
      CalcKey('SUB', '−', kind: CalcKeyKind.operator),
    ],
    [
      CalcKey('0', '0', kind: CalcKeyKind.number),
      CalcKey('DOT', '.', kind: CalcKeyKind.number),
      CalcKey('EXP10', '×10ˣ', shift: 'π', alpha: 'e', kind: CalcKeyKind.number),
      CalcKey('ANS', 'Ans', kind: CalcKeyKind.number),
      CalcKey('EQ', '=', shift: '≈', kind: CalcKeyKind.number),
    ],
  ];

  static final Map<String, CalcKey> byId = {
    for (final k in [...top, ...pad, for (final r in functions) ...r, for (final r in numbers) ...r]) k.id: k,
  };

  /// Schreibweisen der KI auf die Tasten-Namen bringen („×“ → MUL, „ln“ → LN).
  static String normalize(String raw) {
    final k = raw.trim();
    const aliases = {
      '×': 'MUL',
      '*': 'MUL',
      'x*': 'MUL',
      '÷': 'DIV',
      '/': 'DIV',
      '+': 'ADD',
      '-': 'SUB',
      '−': 'SUB',
      '(': 'LPAR',
      ')': 'RPAR',
      '=': 'EQ',
      '.': 'DOT',
      ',': 'DOT',
      'X²': 'SQ',
      'x²': 'SQ',
      'x^2': 'SQ',
      '(-)': 'NEG',
      '(−)': 'NEG',
      '√': 'SQRT',
      'ln': 'LN',
      'log': 'LOG',
      'sin': 'SIN',
      'cos': 'COS',
      'tan': 'TAN',
      'x': 'X',
      'Ans': 'ANS',
      '^': 'POW',
      'x^': 'POW',
      '∫': 'INT',
      'S<=>D': 'SD',
      'S⇔D': 'SD',
      '▶': 'RIGHT',
      '◀': 'LEFT',
      '▲': 'UP',
      '▼': 'DOWN',
      'x⁻¹': 'INV',
      'x^-1': 'INV',
      'FRACTION': 'FRAC',
      'BRUCH': 'FRAC',
    };
    final alias = aliases[k];
    if (alias != null) return alias;
    final upper = k.toUpperCase();
    if (byId.containsKey(upper)) return upper;
    return k;
  }
}

/// Was nach den ersten [pressed] Tasten im Display steht.
class CalcDisplay {
  const CalcDisplay({
    this.input = '',
    this.shift = false,
    this.alpha = false,
    this.done = false,
    this.screen = '',
    this.decimal = false,
  });

  /// Eingabezeile (so wie getippt).
  final String input;
  final bool shift;
  final bool alpha;

  /// „=“ gedrückt – Ergebnis zeigen.
  final bool done;

  /// Besonderer Bildschirm (Menü, SOLVE …).
  final String screen;

  /// Ergebnis als Dezimalzahl (SHIFT = bzw. S⇔D).
  final bool decimal;

  static CalcDisplay after(List<String> keys, int pressed) {
    final tokens = <String>[];
    var shift = false, alpha = false, done = false, decimal = false;
    var screen = '';
    for (final raw in keys.take(pressed)) {
      final k = CalcKeys.normalize(raw);
      if (done && k != 'SD' && k != 'SHIFT' && k != 'EQ') {
        tokens.clear();
        done = false;
        decimal = false;
      }
      if (k == 'SHIFT') {
        shift = !shift;
        alpha = false;
        continue;
      }
      if (k == 'ALPHA') {
        alpha = !alpha;
        shift = false;
        continue;
      }
      final s = shift, a = alpha;
      shift = false;
      alpha = false;
      switch (k) {
        case 'AC':
          tokens.clear();
          screen = '';
          done = false;
        case 'DEL':
          if (tokens.isNotEmpty) tokens.removeLast();
        case 'EQ':
          done = true;
          decimal = s;
        case 'SD':
          decimal = !decimal;
        case 'MENU':
          screen = s ? 'SETUP' : 'MENU';
        case 'ON':
          tokens.clear();
          screen = '';
        case 'CALC':
          if (s) {
            screen = 'SOLVE';
            done = true;
          } else if (a) {
            tokens.add('=');
          } else {
            screen = 'CALC';
          }
        case 'LEFT' || 'UP' || 'DOWN' || 'OPTN' || 'STO' || 'ENG' || 'MPLUS':
          break;
        case 'RIGHT':
          // aus einer Vorlage (Bruch, Hochzahl) heraus
          if (tokens.isNotEmpty && tokens.last != ')' && _openTemplates(tokens) > 0) tokens.add('⟩');
        default:
          tokens.add(_token(k, shift: s, alpha: a));
      }
    }
    return CalcDisplay(
      input: tokens.join().replaceAll('⟩', ''),
      shift: shift,
      alpha: alpha,
      done: done,
      screen: screen,
      decimal: decimal,
    );
  }

  static int _openTemplates(List<String> tokens) =>
      tokens.where((t) => t == '^' || t == '/').length - tokens.where((t) => t == '⟩').length;

  static String _token(String k, {bool shift = false, bool alpha = false}) {
    if (RegExp(r'^[0-9]$').hasMatch(k)) return k;
    if (alpha) {
      return switch (k) {
        'NEG' => 'A',
        'DMS' => 'B',
        'INV' => 'C',
        'SIN' => 'D',
        'COS' => 'E',
        'TAN' => 'F',
        'RPAR' => 'X',
        'EXP10' => 'e',
        _ => CalcKeys.byId[k]?.alpha ?? '',
      };
    }
    if (shift) {
      return switch (k) {
        'LN' => 'e^',
        'LOG' => '10^',
        'SQRT' => '∛(',
        'SQ' => '³',
        'POW' => '√',
        'INV' => '!',
        'SIN' => 'sin⁻¹(',
        'COS' => 'cos⁻¹(',
        'TAN' => 'tan⁻¹(',
        'EXP10' => 'π',
        'INT' => 'd/dx(',
        _ => CalcKeys.byId[k]?.shift ?? '',
      };
    }
    return switch (k) {
      'DOT' => '.',
      'ADD' => '+',
      'SUB' => '−',
      'MUL' => '×',
      'DIV' => '÷',
      'NEG' => '−',
      'LPAR' => '(',
      'RPAR' => ')',
      'SQ' => '²',
      'POW' => '^',
      'FRAC' => '/',
      'SQRT' => '√(',
      'LN' => 'ln(',
      'LOG' => 'log(',
      'SIN' => 'sin(',
      'COS' => 'cos(',
      'TAN' => 'tan(',
      'INV' => '⁻¹',
      'X' => 'x',
      'ANS' => 'Ans',
      'EXP10' => '×10^',
      'INT' => '∫(',
      'DMS' => '°',
      _ => CalcKeys.byId[k]?.label ?? k,
    };
  }
}

/// Ergebnis für das Display – die App rechnet mit [WorkCalc.expr] nach und
/// zeigt bei Abweichung ihren eigenen Wert.
class CalcOutcome {
  const CalcOutcome({required this.result, this.decimal = '', this.mismatch = false});

  /// LaTeX.
  final String result;

  /// Dezimalwert (für S⇔D), leer wenn unbekannt.
  final String decimal;
  final bool mismatch;

  static CalcOutcome of(WorkCalc calc) {
    final value = calc.expr.trim().isEmpty ? null : MathExpression.tryParse(calc.expr)?.evaluate();
    final shown = calc.result.trim();
    final shownValue = shown.isEmpty ? null : MathExpression.tryParse(shown)?.evaluate();
    final valueOk = value != null && value.isFinite;
    String fmt(double v) => MathExpression.formatNumber(double.parse(v.toStringAsPrecision(10)));
    if (!valueOk) {
      return CalcOutcome(result: shown, decimal: shownValue != null && shownValue.isFinite ? fmt(shownValue) : '');
    }
    final close = shownValue != null && (shownValue - value).abs() <= 1e-6 * (value.abs() > 1 ? value.abs() : 1);
    if (shown.isNotEmpty && (close || shownValue == null)) return CalcOutcome(result: shown, decimal: fmt(value));
    return CalcOutcome(result: fmt(value), decimal: fmt(value), mismatch: shown.isNotEmpty);
  }
}

/// Simulierter Taschenrechner: die App drückt die Tasten aus [calc] eine nach
/// der anderen, das Display zeigt mit. Darunter die Tastenfolge zum
/// Mitlesen; Abspielen, Schritt, Wiederholen.
class CalculatorSim extends StatefulWidget {
  const CalculatorSim({super.key, this.calc, this.autoplay = true, this.speed = const Duration(milliseconds: 750)});

  final WorkCalc? calc;
  final bool autoplay;
  final Duration speed;

  @override
  State<CalculatorSim> createState() => _CalculatorSimState();
}

class _CalculatorSimState extends State<CalculatorSim> {
  int _pressed = 0;
  Timer? _timer;
  bool _playing = false;

  List<String> get _keys => [for (final k in widget.calc?.keys ?? const <String>[]) CalcKeys.normalize(k)];

  @override
  void initState() {
    super.initState();
    if (widget.autoplay && _keys.isNotEmpty) _play();
  }

  @override
  void didUpdateWidget(CalculatorSim old) {
    super.didUpdateWidget(old);
    if (old.calc != widget.calc) {
      _stop();
      _pressed = 0;
      if (widget.autoplay && _keys.isNotEmpty) _play();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    _timer?.cancel();
    if (_pressed >= _keys.length) _pressed = 0;
    _playing = true;
    _timer = Timer.periodic(widget.speed, (_) {
      if (!mounted) return;
      setState(() {
        _pressed++;
        if (_pressed >= _keys.length) _stop();
      });
    });
    setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _playing = false;
  }

  void _step() {
    _stop();
    setState(() => _pressed = (_pressed + 1).clamp(0, _keys.length));
  }

  void _restart() {
    _stop();
    setState(() => _pressed = 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final calc = widget.calc;
    final keys = _keys;
    final display = CalcDisplay.after(keys, _pressed);
    final current = _pressed > 0 && _pressed <= keys.length ? keys[_pressed - 1] : null;
    final outcome = calc == null ? null : CalcOutcome.of(calc);
    return Column(
      key: const ValueKey('calc-sim'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF3A3F47), Color(0xFF23262B)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Tasten wie fx-991DE X',
                    style: TextStyle(color: Color(0xFFB8BEC8), fontSize: 10.5, letterSpacing: 0.4),
                  ),
                  const Spacer(),
                  Container(width: 46, height: 12, color: const Color(0xFF4A3A2A)),
                ],
              ),
              const SizedBox(height: 8),
              _display(display, calc, outcome),
              const SizedBox(height: 10),
              _topArea(current),
              const SizedBox(height: 6),
              for (final row in CalcKeys.functions) _row(row, current, small: true),
              const SizedBox(height: 4),
              for (final row in CalcKeys.numbers) _row(row, current),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (calc == null || keys.isEmpty)
          Text(
            'In diesem Schritt braucht es keinen Taschenrechner.',
            key: const ValueKey('calc-none'),
            style: TextStyle(fontSize: 12.5, color: c.inkMuted),
          )
        else ...[
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final (i, k) in keys.indexed)
                Container(
                  key: ValueKey('calc-seq-$i'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: i == _pressed - 1 ? c.accent : (i < _pressed ? c.accentSoft : c.surfaceAlt),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    CalcKeys.byId[k]?.label ?? k,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: i == _pressed - 1 ? Colors.white : c.ink,
                    ),
                  ),
                ),
            ],
          ),
          if (calc.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(calc.note, style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35)),
            ),
          if (outcome != null && outcome.mismatch && display.done)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Die App hat nachgerechnet – der Taschenrechner zeigt ${outcome.result}.',
                key: const ValueKey('calc-mismatch'),
                style: TextStyle(fontSize: 12.5, color: c.warn),
              ),
            ),
          Row(
            children: [
              IconButton(
                key: const ValueKey('calc-play'),
                tooltip: _playing ? 'Anhalten' : 'Abspielen',
                onPressed: _playing ? () => setState(_stop) : _play,
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                key: const ValueKey('calc-step'),
                tooltip: 'Nächste Taste',
                onPressed: _pressed >= keys.length ? null : _step,
                icon: const Icon(Icons.skip_next),
              ),
              IconButton(
                key: const ValueKey('calc-restart'),
                tooltip: 'Von vorn',
                onPressed: _pressed == 0 ? null : _restart,
                icon: const Icon(Icons.replay),
              ),
              Text('$_pressed / ${keys.length} Tasten', style: TextStyle(fontSize: 12, color: c.inkMuted)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _display(CalcDisplay d, WorkCalc? calc, CalcOutcome? outcome) {
    const ink = Color(0xFF1D2318);
    const lcd = Color(0xFFC7D1BD);
    Widget mathOr(String tex, double size, {TextAlign align = TextAlign.left}) => Math.tex(
      tex,
      textStyle: TextStyle(fontSize: size, color: ink),
      onErrorFallback: (_) => Text(
        tex,
        textAlign: align,
        style: TextStyle(fontSize: size, color: ink),
      ),
    );
    final input = d.done && calc != null && calc.input.trim().isNotEmpty ? calc.input : null;
    final result = d.done && outcome != null
        ? (d.decimal && outcome.decimal.isNotEmpty ? outcome.decimal : outcome.result)
        : '';
    return Container(
      key: const ValueKey('calc-display'),
      height: 96,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: lcd,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8E9984), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (d.shift) const _Indicator('S', Color(0xFF8A6D00)),
              if (d.alpha) const _Indicator('A', Color(0xFF9B1C1C)),
              if (d.screen.isNotEmpty) _Indicator(d.screen, ink),
              const Spacer(),
              const Text('Math ▲', style: TextStyle(fontSize: 9, color: ink)),
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: input != null
                    ? mathOr(input, 17)
                    : Text(
                        d.input.isEmpty ? '' : '${d.input}▏',
                        key: const ValueKey('calc-input'),
                        style: const TextStyle(fontSize: 17, color: ink, fontFamily: 'monospace'),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.centerRight,
              child: result.isEmpty
                  ? const SizedBox.shrink()
                  : KeyedSubtree(
                      key: const ValueKey('calc-result'),
                      child: mathOr(result, 20, align: TextAlign.right),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topArea(String? current) {
    Widget small(String id) =>
        Expanded(child: SizedBox(height: 34, child: _key(CalcKeys.byId[id]!, current, small: true)));
    Widget pair(String a, String b) => Row(children: [small(a), const SizedBox(width: 4), small(b)]);
    return Row(
      children: [
        Expanded(child: Column(children: [pair('SHIFT', 'ALPHA'), const SizedBox(height: 4), pair('OPTN', 'CALC')])),
        const SizedBox(width: 6),
        SizedBox(
          width: 82,
          height: 74,
          child: Stack(
            children: [
              Positioned(
                left: 25,
                top: 0,
                width: 32,
                height: 24,
                child: _key(CalcKeys.byId['UP']!, current, small: true),
              ),
              Positioned(
                left: 0,
                top: 25,
                width: 32,
                height: 24,
                child: _key(CalcKeys.byId['LEFT']!, current, small: true),
              ),
              Positioned(
                left: 50,
                top: 25,
                width: 32,
                height: 24,
                child: _key(CalcKeys.byId['RIGHT']!, current, small: true),
              ),
              Positioned(
                left: 25,
                top: 50,
                width: 32,
                height: 24,
                child: _key(CalcKeys.byId['DOWN']!, current, small: true),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: Column(children: [pair('MENU', 'ON'), const SizedBox(height: 4), pair('INT', 'X')])),
      ],
    );
  }

  Widget _row(List<CalcKey> keys, String? current, {bool small = false}) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        for (final (i, k) in keys.indexed) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: SizedBox(
              height: small ? 40 : 44,
              child: _key(k, current, small: small),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _key(CalcKey k, String? current, {bool small = false}) {
    final pressed = current == k.id;
    final (bg, fg) = switch (k.kind) {
      CalcKeyKind.number || CalcKeyKind.operator => (const Color(0xFFE6E8EC), const Color(0xFF1B1E23)),
      CalcKeyKind.action => (const Color(0xFF3D6FB6), Colors.white),
      CalcKeyKind.modifier => (
        const Color(0xFF2B2E33),
        k.id == 'SHIFT' ? const Color(0xFFF2C94C) : const Color(0xFFFF6B6B),
      ),
      _ => (const Color(0xFF2B2E33), const Color(0xFFF1F3F6)),
    };
    return Column(
      key: ValueKey('calc-key-${k.id}'),
      children: [
        SizedBox(
          height: small ? 11 : 12,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (k.shift.isNotEmpty)
                  Text(k.shift, maxLines: 1, style: const TextStyle(fontSize: 8, color: Color(0xFFF2C94C), height: 1)),
                if (k.shift.isNotEmpty && k.alpha.isNotEmpty) const SizedBox(width: 3),
                if (k.alpha.isNotEmpty)
                  Text(k.alpha, style: const TextStyle(fontSize: 8, color: Color(0xFFFF6B6B), height: 1)),
              ],
            ),
          ),
        ),
        Expanded(
          child: AnimatedScale(
            scale: pressed ? 0.88 : 1,
            duration: const Duration(milliseconds: 120),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: pressed ? const Color(0xFFFFB74D) : bg,
                borderRadius: BorderRadius.circular(
                  k.kind == CalcKeyKind.control || k.kind == CalcKeyKind.modifier ? 10 : 7,
                ),
                boxShadow: pressed
                    ? [BoxShadow(color: const Color(0xFFFFB74D).withAlpha(160), blurRadius: 10)]
                    : [BoxShadow(color: Colors.black.withAlpha(70), offset: const Offset(0, 2), blurRadius: 1)],
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text(
                    k.label,
                    style: TextStyle(
                      fontSize: small ? 12 : 15,
                      fontWeight: FontWeight.w600,
                      color: pressed ? Colors.black : fg,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 3),
    color: color,
    child: Text(
      text,
      style: const TextStyle(fontSize: 9, color: Color(0xFFC7D1BD), fontWeight: FontWeight.w700),
    ),
  );
}
