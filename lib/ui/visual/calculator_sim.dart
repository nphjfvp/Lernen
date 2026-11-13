import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/worked_solution.dart';
import '../../services/pocket_calculator.dart';
import '../../theme/app_colors.dart';

/// Eine Taste: [id] (wie in WorkCalc.keys und PocketCalculator.press),
/// Aufdruck, gelbe SHIFT- und rote ALPHA-Belegung darüber.
class CalcKey {
  const CalcKey(this.id, this.label, {this.shift = '', this.alpha = '', this.kind = CalcKeyKind.function});

  final String id;
  final String label;
  final String shift;
  final String alpha;
  final CalcKeyKind kind;
}

enum CalcKeyKind { modifier, control, function, number, operator, action, equals }

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
    CalcKey('INT', '∫', shift: 'd/dx', kind: CalcKeyKind.control),
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
      CalcKey('FRAC', 'a/b'),
      CalcKey('SQRT', '√', shift: '∛'),
      CalcKey('SQ', 'x²', shift: 'x³'),
      CalcKey('POW', 'x^', shift: 'ⁿ√'),
      CalcKey('LOG', 'log', shift: '10^x'),
      CalcKey('LN', 'ln', shift: 'e^x'),
    ],
    [
      CalcKey('NEG', '(−)', shift: 'Abs', alpha: 'A'),
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
      CalcKey('RPAR', ')', shift: ',', alpha: 'X'),
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
      CalcKey('DOT', ',', kind: CalcKeyKind.number),
      CalcKey('EXP10', '×10ˣ', shift: 'π', alpha: 'e', kind: CalcKeyKind.number),
      CalcKey('ANS', 'Ans', kind: CalcKeyKind.number),
      CalcKey('EQ', '=', shift: '≈', kind: CalcKeyKind.equals),
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
      'ENTER': 'EQ',
    };
    final alias = aliases[k];
    if (alias != null) return alias;
    final upper = k.toUpperCase();
    if (byId.containsKey(upper)) return upper;
    return k;
  }

  /// Tastatur am PC → Taste.
  static String? fromKeyboard(KeyEvent e) {
    final ch = e.character;
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) return 'EQ';
    if (e.logicalKey == LogicalKeyboardKey.backspace) return 'DEL';
    if (e.logicalKey == LogicalKeyboardKey.escape || e.logicalKey == LogicalKeyboardKey.delete) return 'AC';
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) return 'LEFT';
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) return 'RIGHT';
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) return 'UP';
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) return 'DOWN';
    final numpad = {
      LogicalKeyboardKey.numpadAdd: 'ADD',
      LogicalKeyboardKey.numpadSubtract: 'SUB',
      LogicalKeyboardKey.numpadMultiply: 'MUL',
      LogicalKeyboardKey.numpadDivide: 'DIV',
      LogicalKeyboardKey.numpadDecimal: 'DOT',
      LogicalKeyboardKey.numpadComma: 'DOT',
    }[e.logicalKey];
    if (numpad != null) return numpad;
    if (ch == null || ch.isEmpty) return null;
    if (RegExp(r'^[0-9]$').hasMatch(ch)) return ch;
    return switch (ch) {
      '+' => 'ADD',
      '-' => 'SUB',
      '*' => 'MUL',
      '/' || ':' => 'DIV',
      '(' => 'LPAR',
      ')' => 'RPAR',
      '.' || ',' => 'DOT',
      '^' => 'POW',
      'x' => 'X',
      '=' => 'EQ',
      _ => null,
    };
  }
}

/// Funktionierender Taschenrechner (Tasten wie fx-991DE X) zum Selberrechnen
/// – mit Maus, Finger oder PC-Tastatur. Mit [calc] führt die App eine
/// Tastenfolge vor (Taste für Taste); danach rechnet man selbst weiter.
/// [onUseResult] übernimmt ein Ergebnis (z.B. in eine Rechenweg-Zeile).
class CalculatorSim extends StatefulWidget {
  const CalculatorSim({
    super.key,
    this.calc,
    this.autoplay = true,
    this.speed = const Duration(milliseconds: 750),
    this.onUseResult,
  });

  final WorkCalc? calc;
  final bool autoplay;
  final Duration speed;
  final void Function(String input)? onUseResult;

  @override
  State<CalculatorSim> createState() => _CalculatorSimState();
}

class _CalculatorSimState extends State<CalculatorSim> {
  PocketCalculator _engine = PocketCalculator();
  int _pressed = 0;
  Timer? _timer;
  Timer? _flashTimer;
  String? _flash;
  bool _playing = false;
  final _focus = FocusNode(debugLabel: 'calculator');

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
      _engine = PocketCalculator();
      _pressed = 0;
      if (widget.autoplay && _keys.isNotEmpty) _play();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flashTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  // -- Vorführen ---------------------------------------------------------------

  void _play() {
    _timer?.cancel();
    if (_pressed >= _keys.length) _restartDemo();
    _playing = true;
    _timer = Timer.periodic(widget.speed, (_) {
      if (!mounted) return;
      _demoStep();
      if (_pressed >= _keys.length) setState(_stop);
    });
    setState(() {});
  }

  void _demoStep() {
    final keys = _keys;
    if (_pressed >= keys.length) return;
    final k = keys[_pressed];
    setState(() {
      _engine.press(k);
      _pressed++;
      _flash = k;
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _playing = false;
  }

  void _restartDemo() {
    _engine = PocketCalculator();
    _pressed = 0;
    _flash = null;
  }

  // -- Selbst drücken ------------------------------------------------------------

  void _press(String id) {
    if (_playing) _stop();
    _focus.requestFocus();
    HapticFeedback.selectionClick();
    setState(() {
      _engine.press(id);
      _flash = id;
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 170), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final id = CalcKeys.fromKeyboard(e);
    if (id == null) return KeyEventResult.ignored;
    _press(id);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final calc = widget.calc;
    final keys = _keys;
    final engine = _engine;
    final demoError = calc != null && _pressed >= keys.length && keys.isNotEmpty && engine.error != null;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Column(
        key: const ValueKey('calc-sim'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(onTap: _focus.requestFocus, child: _body(engine)),
          const SizedBox(height: 8),
          if (widget.onUseResult != null && engine.result != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('calc-use'),
                onPressed: () => widget.onUseResult!(engine.resultInput()),
                icon: const Icon(Icons.input, size: 18),
                label: const Text('Ergebnis übernehmen'),
              ),
            ),
          if (calc != null && keys.isNotEmpty) ...[
            Text(
              'Tastenfolge',
              style: TextStyle(fontSize: 12, color: c.inkMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final (i, k) in keys.indexed)
                  AnimatedContainer(
                    key: ValueKey('calc-seq-$i'),
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
            if (demoError && calc.result.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Diese Tastenfolge ergibt auf dem Rechner einen Fehler – gemeint war: ${calc.result}',
                  key: const ValueKey('calc-mismatch'),
                  style: TextStyle(fontSize: 12.5, color: c.warn),
                ),
              ),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('calc-play'),
                  tooltip: _playing ? 'Anhalten' : 'Vorführen',
                  onPressed: _playing ? () => setState(_stop) : _play,
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  key: const ValueKey('calc-step'),
                  tooltip: 'Nächste Taste',
                  onPressed: _pressed >= keys.length
                      ? null
                      : () {
                          _stop();
                          _demoStep();
                        },
                  icon: const Icon(Icons.skip_next),
                ),
                IconButton(
                  key: const ValueKey('calc-restart'),
                  tooltip: 'Von vorn',
                  onPressed: _pressed == 0 ? null : () => setState(() => _restartDemo()),
                  icon: const Icon(Icons.replay),
                ),
                Expanded(
                  child: Text(
                    '$_pressed / ${keys.length} Tasten · danach selbst weiterrechnen',
                    style: TextStyle(fontSize: 12, color: c.inkMuted),
                  ),
                ),
              ],
            ),
          ] else if (calc == null && widget.onUseResult == null)
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  // -- Gehäuse -----------------------------------------------------------------

  Widget _body(PocketCalculator engine) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF434952), Color(0xFF2B2F35), Color(0xFF1F2226)],
        stops: [0, 0.35, 1],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: const Color(0xFF555C66), width: 1.2),
      boxShadow: [BoxShadow(color: Colors.black.withAlpha(70), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Rechner · Tasten wie fx-991DE X',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Color(0xFFC3C8D0), fontSize: 10.5, letterSpacing: 0.6),
              ),
            ),
            // Solarzelle
            Container(
              width: 64,
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF1A1512)),
                gradient: const LinearGradient(colors: [Color(0xFF3B2B22), Color(0xFF5A4232), Color(0xFF3B2B22)]),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Container(margin: const EdgeInsets.all(1.5), color: const Color(0xFF4A372B)),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        _display(engine),
        const SizedBox(height: 12),
        _topArea(),
        const SizedBox(height: 4),
        for (final row in CalcKeys.functions) _row(row, height: 40),
        const SizedBox(height: 6),
        for (final row in CalcKeys.numbers) _row(row, height: 46),
      ],
    ),
  );

  Widget _display(PocketCalculator engine) {
    const ink = Color(0xFF1D2318);
    Widget tex(String s, double size) => Math.tex(
      s,
      textStyle: TextStyle(fontSize: size, color: ink),
      onErrorFallback: (_) => Text(
        s.replaceAll(RegExp(r'\\[a-zA-Z]+'), ''),
        style: TextStyle(fontSize: size * 0.85, color: ink),
      ),
    );
    final result = engine.result;
    final status = <Widget>[
      if (engine.shift) const _Indicator('S', Color(0xFF8A6D00)),
      if (engine.alpha) const _Indicator('A', Color(0xFF9B1C1C)),
      if (engine.memory != 0) const _Indicator('M', ink),
      _Indicator(engine.angle == AngleUnit.deg ? 'D' : 'R', ink),
    ];
    return Container(
      key: const ValueKey('calc-display'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFF14171A), borderRadius: BorderRadius.circular(10)),
      child: Container(
        height: 104,
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD5DECA), Color(0xFFC3CDB6)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 13,
              child: Row(
                children: [
                  ...status,
                  const Spacer(),
                  if (engine.decimal) const Text('Dez ', style: TextStyle(fontSize: 9, color: ink)),
                  const Text(
                    'Math',
                    style: TextStyle(fontSize: 9, color: ink, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: KeyedSubtree(
                    key: const ValueKey('calc-input'),
                    child: engine.tokens.isEmpty && !engine.askingX
                        ? (engine.editing ? tex(engine.inputLatex(), 17) : const SizedBox.shrink())
                        : tex(engine.inputLatex(), 17),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 30,
              child: Row(
                children: [
                  if (engine.note.isNotEmpty)
                    Expanded(
                      child: Text(
                        engine.note,
                        key: const ValueKey('calc-note'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: ink),
                      ),
                    )
                  else
                    const Spacer(),
                  if (engine.error != null)
                    Text(
                      engine.error!,
                      key: const ValueKey('calc-error'),
                      style: const TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w700),
                    )
                  else if (result != null)
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: KeyedSubtree(key: const ValueKey('calc-result'), child: tex(engine.resultLatex(), 21)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topArea() {
    Widget small(String id) => Expanded(child: SizedBox(height: 38, child: _key(CalcKeys.byId[id]!, small: true)));
    Widget pair(String a, String b) => Row(children: [small(a), const SizedBox(width: 5), small(b)]);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Column(children: [pair('SHIFT', 'ALPHA'), const SizedBox(height: 3), pair('OPTN', 'CALC')])),
        const SizedBox(width: 8),
        _pad(),
        const SizedBox(width: 8),
        Expanded(child: Column(children: [pair('MENU', 'ON'), const SizedBox(height: 3), pair('INT', 'X')])),
      ],
    );
  }

  /// Runde Cursor-Wippe.
  Widget _pad() {
    Widget arrow(String id, IconData icon, Alignment a) => Align(
      alignment: a,
      child: _Pressable(
        key: ValueKey('calc-key-$id'),
        pressed: _flash == id,
        onTap: () => _press(id),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 22, color: _flash == id ? const Color(0xFFFFB74D) : const Color(0xFFE7EAEE)),
        ),
      ),
    );
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(colors: [Color(0xFF4C535C), Color(0xFF30353B)], radius: 0.9),
        border: Border.all(color: const Color(0xFF5D646E)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(90), offset: const Offset(0, 2), blurRadius: 3)],
      ),
      child: Stack(
        children: [
          arrow('UP', Icons.arrow_drop_up, Alignment.topCenter),
          arrow('DOWN', Icons.arrow_drop_down, Alignment.bottomCenter),
          arrow('LEFT', Icons.arrow_left, Alignment.centerLeft),
          arrow('RIGHT', Icons.arrow_right, Alignment.centerRight),
          Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF262A2F)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(List<CalcKey> keys, {required double height}) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        for (final (i, k) in keys.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: height,
              child: _key(k, small: height < 44),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _key(CalcKey k, {bool small = false}) {
    final pressed = _flash == k.id;
    final active = (k.id == 'SHIFT' && _engine.shift) || (k.id == 'ALPHA' && _engine.alpha);
    final (List<Color> colors, Color fg, double radius) = switch (k.kind) {
      CalcKeyKind.number ||
      CalcKeyKind.operator => (const [Color(0xFFF7F7F5), Color(0xFFDCDDDA)], const Color(0xFF1B1E23), 10.0),
      CalcKeyKind.action => (const [Color(0xFF6A93CF), Color(0xFF3F67A3)], Colors.white, 10.0),
      CalcKeyKind.equals => (const [Color(0xFFF7F7F5), Color(0xFFD0D2CE)], const Color(0xFF1B1E23), 10.0),
      CalcKeyKind.modifier => (
        const [Color(0xFF50565F), Color(0xFF363B42)],
        k.id == 'SHIFT' ? const Color(0xFFF2C94C) : const Color(0xFFFF7B72),
        19.0,
      ),
      _ => (const [Color(0xFF50565F), Color(0xFF363B42)], const Color(0xFFF1F3F6), small ? 19.0 : 12.0),
    };
    return Column(
      children: [
        SizedBox(
          height: 11,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (k.shift.isNotEmpty) _smallLabel(k.shift, const Color(0xFFF2C94C)),
                if (k.shift.isNotEmpty && k.alpha.isNotEmpty) const SizedBox(width: 4),
                if (k.alpha.isNotEmpty)
                  Text(k.alpha, style: const TextStyle(fontSize: 8.5, color: Color(0xFFFF7B72), height: 1)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 1),
        Expanded(
          child: _Pressable(
            key: ValueKey('calc-key-${k.id}'),
            pressed: pressed,
            onTap: () => _press(k.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: pressed
                      ? const [Color(0xFFFFC56B), Color(0xFFF5A23A)]
                      : (active ? [colors.first, const Color(0xFF6E5A1E)] : colors),
                ),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: Colors.black.withAlpha(60), width: 0.8),
                boxShadow: pressed
                    ? [BoxShadow(color: const Color(0xFFFFB74D).withAlpha(150), blurRadius: 10)]
                    : [BoxShadow(color: Colors.black.withAlpha(110), offset: const Offset(0, 2.5), blurRadius: 1.5)],
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _label(k, pressed ? Colors.black : fg, small),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Kleine Zweitbelegung über der Taste; „⁻¹“ und „∛“ gezeichnet statt als
  /// Sonderzeichen (nicht jede Schrift hat sie).
  static Widget _smallLabel(String text, Color color) {
    const size = 8.5;
    final style = TextStyle(fontSize: size, color: color, height: 1);
    if (text.endsWith('⁻¹')) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(text.substring(0, text.length - 2), style: style),
          ),
          Text('-1', style: style.copyWith(fontSize: size * 0.7)),
        ],
      );
    }
    if (text == '∛') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('3', style: style.copyWith(fontSize: size * 0.7)),
          Text('√', style: style),
        ],
      );
    }
    return Text(text, style: style);
  }

  /// Aufdruck – Bruch, Wurzel und Potenzen gezeichnet statt als Sonderzeichen.
  Widget _label(CalcKey k, Color fg, bool small) {
    final size = k.kind == CalcKeyKind.number || k.kind == CalcKeyKind.operator || k.kind == CalcKeyKind.equals
        ? 20.0
        : (small ? 13.0 : 15.0);
    final style = TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: fg, height: 1.05);
    Widget box([double s = 7]) => Container(
      width: s,
      height: s,
      decoration: BoxDecoration(border: Border.all(color: fg, width: 1.1)),
    );
    switch (k.id) {
      case 'FRAC':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            box(),
            Container(width: 14, height: 1.4, margin: const EdgeInsets.symmetric(vertical: 2), color: fg),
            box(),
          ],
        );
      case 'SQRT':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('√', style: style),
            box(9),
          ],
        );
      case 'POW':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('x', style: style),
            Padding(padding: const EdgeInsets.only(left: 1), child: box(6)),
          ],
        );
      case 'SQ' || 'INV':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('x', style: style),
            Text(k.id == 'SQ' ? '2' : '-1', style: style.copyWith(fontSize: size * 0.6)),
          ],
        );
      case 'EXP10':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('×10', style: style.copyWith(fontSize: size * 0.75)),
            Text('x', style: style.copyWith(fontSize: size * 0.5)),
          ],
        );
      case 'SD':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('S', style: style),
            Icon(Icons.swap_horiz, size: size, color: fg),
            Text('D', style: style),
          ],
        );
      case 'INT':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('∫', style: style),
            box(8),
          ],
        );
    }
    return Text(k.label, style: style);
  }
}

/// Taste mit Druck-Effekt (sinkt ein).
class _Pressable extends StatefulWidget {
  const _Pressable({super.key, required this.child, required this.onTap, this.pressed = false});

  final Widget child;
  final VoidCallback onTap;
  final bool pressed;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final down = _down || widget.pressed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: down ? 0.92 : 1,
        duration: const Duration(milliseconds: 90),
        child: AnimatedSlide(
          offset: down ? const Offset(0, 0.03) : Offset.zero,
          duration: const Duration(milliseconds: 90),
          child: widget.child,
        ),
      ),
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
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
    child: Text(
      text,
      style: const TextStyle(fontSize: 9, color: Color(0xFFD5DECA), fontWeight: FontWeight.w700, height: 1.3),
    ),
  );
}
