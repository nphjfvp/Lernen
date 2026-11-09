import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/paper_review.dart';
import '../../theme/app_colors.dart';

/// Schrift für das Rechenblatt (Patrick Hand, OFL – siehe pubspec.yaml).
const handwritingFont = 'Handwriting';

// ---------------------------------------------------------------------------
// Parser: getippte Zeile („Mb = KA * F/2 * a = 1,25*6000N*175mm“) → Baum
// ---------------------------------------------------------------------------

sealed class HandNode {}

class HandText extends HandNode {
  HandText(this.text, {this.op = false, this.space = false});
  final String text;

  /// Operator wie = + − · ⇒ – bekommt Abstand.
  final bool op;

  /// Leerzeichen aus der Eingabe (z.B. zwischen Zahl und Einheit).
  final bool space;
}

class HandGroup extends HandNode {
  HandGroup(this.items, {this.parens = true});
  final List<HandNode> items;
  final bool parens;
}

class HandFrac extends HandNode {
  HandFrac(this.num, this.den);
  final HandNode num;
  final HandNode den;
}

class HandSup extends HandNode {
  HandSup(this.base, this.exp);
  final HandNode base;
  final HandNode exp;
}

class HandSub extends HandNode {
  HandSub(this.base, this.sub);
  final HandNode base;
  final HandNode sub;
}

class HandSqrt extends HandNode {
  HandSqrt(this.body);
  final HandNode body;
}

/// Liest eine getippte Rechenweg-Zeile tolerant: Brüche (a/b, (…)/(…),
/// dy/dx), Hoch- und Tiefstellung (^, _, ², ³), Wurzel (√( ), sqrt( )),
/// Klammern; * wird ·, - wird −, <= ≤, => ⇒, Namen wie alpha α. Alles
/// andere bleibt als Text stehen – eine Zeile lässt sich immer zeigen.
class HandMathParser {
  HandMathParser(String input) : _tokens = _tokenize(input);

  final List<String> _tokens;
  int _pos = 0;

  static const _greek = {
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'delta': 'δ',
    'Delta': 'Δ',
    'epsilon': 'ε',
    'eta': 'η',
    'theta': 'θ',
    'lambda': 'λ',
    'mu': 'μ',
    'nu': 'ν',
    'pi': 'π',
    'rho': 'ρ',
    'sigma': 'σ',
    'Sigma': 'Σ',
    'tau': 'τ',
    'phi': 'φ',
    'omega': 'ω',
    'Omega': 'Ω',
    'inf': '∞',
    'infinity': '∞',
  };

  static const _multi = {'<=': '≤', '>=': '≥', '!=': '≠', '=>': '⇒', '->': '→', '==': '='};
  static const _ops = {'=', '+', '−', '·', '⇒', '→', '≤', '≥', '≠', '<', '>', '≈', '±', '⇔', '<=>'};

  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    final letter = RegExp(r'[A-Za-zÄÖÜäöüßα-ωΑ-Ω]');
    var i = 0;
    while (i < input.length) {
      final ch = input[i];
      if (ch.trim().isEmpty) {
        while (i < input.length && input[i].trim().isEmpty) {
          i++;
        }
        tokens.add(' ');
        continue;
      }
      if (i + 1 < input.length && _multi.containsKey(input.substring(i, i + 2))) {
        tokens.add(_multi[input.substring(i, i + 2)]!);
        i += 2;
        continue;
      }
      if (RegExp(r'\d').hasMatch(ch)) {
        final start = i;
        while (i < input.length &&
            (RegExp(r'\d').hasMatch(input[i]) ||
                ((input[i] == ',' || input[i] == '.') &&
                    i + 1 < input.length &&
                    RegExp(r'\d').hasMatch(input[i + 1])))) {
          i++;
        }
        tokens.add(input.substring(start, i));
        continue;
      }
      if (letter.hasMatch(ch)) {
        final start = i;
        while (i < input.length && letter.hasMatch(input[i])) {
          i++;
        }
        tokens.add(input.substring(start, i));
        continue;
      }
      tokens.add(switch (ch) {
        '*' || '×' => '·',
        '-' => '−',
        "'" => '′',
        _ => ch,
      });
      i++;
    }
    return tokens;
  }

  String? get _peek => _pos < _tokens.length ? _tokens[_pos] : null;

  List<HandNode> parse() {
    final items = _sequence(top: true);
    return items;
  }

  List<HandNode> _sequence({bool top = false}) {
    final items = <HandNode>[];
    while (_peek != null) {
      if (_peek == ')') {
        if (!top) break;
        _pos++;
        items.add(HandText(')'));
        continue;
      }
      items.add(_postfix());
    }
    return _foldFractions(items);
  }

  static bool _isSpace(HandNode n) => n is HandText && n.space;

  /// a / b → Bruch mit den direkten Nachbarn (Leerzeichen dazwischen erlaubt).
  static List<HandNode> _foldFractions(List<HandNode> items) {
    final out = <HandNode>[];
    var i = 0;
    while (i < items.length) {
      final n = items[i];
      if (n is HandText && n.text == '/' && out.isNotEmpty) {
        var j = i + 1;
        while (j < items.length && _isSpace(items[j])) {
          j++;
        }
        while (out.isNotEmpty && _isSpace(out.last)) {
          out.removeLast();
        }
        final left = out.isEmpty ? null : out.last;
        final right = j < items.length ? items[j] : null;
        if (left != null && right != null && !(left is HandText && left.op) && !(right is HandText && right.op)) {
          out[out.length - 1] = HandFrac(_unwrap(left), _unwrap(right));
          i = j + 1;
          continue;
        }
      }
      out.add(n);
      i++;
    }
    return out;
  }

  /// Klammern um Zähler, Nenner, Exponent oder Wurzel fallen weg.
  static HandNode _unwrap(HandNode n) => n is HandGroup && n.parens ? HandGroup(n.items, parens: false) : n;

  HandNode _postfix() {
    var base = _primary();
    while (true) {
      final t = _peek;
      if (t == '^' || t == '_') {
        _pos++;
        if (_peek == null) {
          base = HandGroup([base, HandText(t!)], parens: false);
          break;
        }
        final arg = _unwrap(_peek == '{' ? _braced() : _primary());
        base = t == '^' ? HandSup(base, arg) : HandSub(base, arg);
      } else if (t == '²' || t == '³') {
        _pos++;
        base = HandSup(base, HandText(t == '²' ? '2' : '3'));
      } else {
        break;
      }
    }
    return base;
  }

  HandNode _braced() {
    _pos++; // {
    final items = <HandNode>[];
    while (_peek != null && _peek != '}') {
      items.add(_postfix());
    }
    if (_peek == '}') _pos++;
    return HandGroup(_foldFractions(items), parens: false);
  }

  HandNode _primary() {
    final t = _tokens[_pos++];
    if (t == ' ') return HandText(' ', space: true);
    if (t == '(') {
      final items = _sequence();
      if (_peek == ')') _pos++;
      return HandGroup(items);
    }
    if (t == '{') {
      _pos--;
      return _braced();
    }
    if (t == '√' || t == 'sqrt' || t == 'wurzel') {
      if (_peek == '(') {
        _pos++;
        final items = _sequence();
        if (_peek == ')') _pos++;
        return HandSqrt(HandGroup(items, parens: false));
      }
      if (_peek != null && _peek != ' ') return HandSqrt(_postfix());
      return HandText('√');
    }
    final greek = _greek[t];
    if (greek != null) return HandText(greek);
    return HandText(t, op: _ops.contains(t));
  }
}

// ---------------------------------------------------------------------------
// Darstellung
// ---------------------------------------------------------------------------

/// Eine getippte Zeile in Handschrift mit echten Brüchen, Exponenten, Indizes
/// und Wurzeln – wie auf einem Lösungsblatt.
class HandMath extends StatelessWidget {
  const HandMath(this.text, {super.key, this.fontSize = 22, this.color});

  final String text;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    List<HandNode> nodes;
    try {
      nodes = HandMathParser(text).parse();
    } catch (_) {
      nodes = [HandText(text)];
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: fontSize * 0.25,
      children: [for (final n in nodes) _build(n, fontSize, ink)],
    );
  }

  static TextStyle _style(double size, Color ink) =>
      TextStyle(fontFamily: handwritingFont, fontSize: size, color: ink, height: 1.05);

  /// Zeichen, die die Handschrift nicht hat – sie kommen aus den
  /// Formel-Schriften, die ohnehin in der App sind (griechisch kursiv wie in
  /// Formeln, Pfeile/∂/′ aus der Grundschrift).
  static const _mathItalic = 'αβγδεζηθικνξορςστυφχψω';
  static const _mathMain = 'ΔΣΘΛΞΠΦΨΩΓ⇒→⇔∂′←↔∑';

  static Widget _text(String text, double size, Color ink) {
    final t = text.replaceAll('″', '′′');
    if (!t.split('').any((ch) => _mathItalic.contains(ch) || _mathMain.contains(ch))) {
      return Text(t, style: _style(size, ink));
    }
    final spans = <TextSpan>[];
    for (final ch in t.split('')) {
      final style = _mathItalic.contains(ch)
          ? TextStyle(
              fontFamily: 'packages/flutter_math_fork/KaTeX_Math',
              fontStyle: FontStyle.italic,
              fontSize: size * 0.95,
            )
          : _mathMain.contains(ch)
          ? TextStyle(fontFamily: 'packages/flutter_math_fork/KaTeX_Main', fontSize: size * 0.9)
          : null;
      spans.add(TextSpan(text: ch, style: style));
    }
    return Text.rich(TextSpan(style: _style(size, ink), children: spans));
  }

  static bool _tall(HandNode n) => switch (n) {
    HandFrac() => true,
    HandGroup(:final items) => items.any(_tall),
    HandSup(:final base) => _tall(base),
    HandSub(:final base) => _tall(base),
    HandSqrt(:final body) => _tall(body),
    HandText() => false,
  };

  static Widget _build(HandNode n, double size, Color ink) {
    switch (n) {
      case HandText(:final text, :final op, :final space):
        if (space) return SizedBox(width: size * 0.28);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: op ? size * 0.2 : (text == '∫' ? size * 0.08 : 0.5)),
          child: _text(text, text == '∫' ? size * 1.45 : size, ink),
        );
      case HandGroup(:final items, :final parens):
        final tall = items.any(_tall);
        final paren = tall ? size * 1.6 : size;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (parens) Text('(', style: _style(paren, ink)),
            for (final i in items) _build(i, size, ink),
            if (parens) Text(')', style: _style(paren, ink)),
          ],
        );
      case HandFrac(:final num, :final den):
        final inner = size * 0.82;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: size * 0.12),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _build(num, inner, ink)),
                Container(
                  height: math.max(1.3, size * 0.06),
                  margin: EdgeInsets.symmetric(vertical: size * 0.06),
                  decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(1)),
                ),
                Center(child: _build(den, inner, ink)),
              ],
            ),
          ),
        );
      case HandSup(:final base, :final exp):
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _build(base, size, ink),
            Padding(
              padding: EdgeInsets.only(bottom: size * 0.48, left: 1),
              child: _build(exp, size * 0.62, ink),
            ),
          ],
        );
      case HandSub(:final base, :final sub):
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _build(base, size, ink),
            Padding(
              padding: EdgeInsets.only(top: size * 0.5, left: 1),
              child: _build(sub, size * 0.62, ink),
            ),
          ],
        );
      case HandSqrt(:final body):
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('√', style: _style(size * (_tall(body) ? 1.6 : 1.15), ink)),
            Container(
              padding: EdgeInsets.only(top: size * 0.08, left: 2, right: 2),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: ink, width: math.max(1.3, size * 0.06)),
                ),
              ),
              child: _build(body, size, ink),
            ),
          ],
        );
    }
  }
}

/// Das Rechenblatt: der ganze getippte Rechenweg live in Handschrift – blau
/// wie ein Lösungsblatt, geprüfte Zeilen mit rotem ✓ bzw. ✗, ein bestätigtes
/// Ergebnis doppelt unterstrichen.
class HandwrittenSheet extends StatelessWidget {
  const HandwrittenSheet({
    super.key,
    required this.lines,
    this.title = 'Rechenweg',
    this.statuses = const {},
    this.resultLine,
    this.onExpand,
    this.fontSize = 22,
  });

  final List<String> lines;
  final String title;

  /// Prüfergebnis je Zeilenindex.
  final Map<int, PaperLineStatus> statuses;

  /// Diese Zeile ist das bestätigte Ergebnis (doppelt unterstrichen).
  final int? resultLine;
  final VoidCallback? onExpand;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFF9DB8FF) : const Color(0xFF1F3A93);
    final red = dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828);
    final paper = dark ? c.surface : const Color(0xFFFFFEF9);
    final written = [
      for (final (i, l) in lines.indexed)
        if (l.trim().isNotEmpty) (i: i, text: l.trim()),
    ];
    return Container(
      key: const ValueKey('hand-sheet'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
        boxShadow: dark
            ? null
            : [BoxShadow(color: Colors.black.withAlpha(14), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: ink, width: 1.4)),
                    ),
                    child: Text(
                      title,
                      style: TextStyle(fontFamily: handwritingFont, fontSize: fontSize * 0.95, color: ink),
                    ),
                  ),
                ),
              ),
              if (onExpand != null)
                IconButton(
                  key: const ValueKey('hand-sheet-expand'),
                  tooltip: 'Groß ansehen',
                  visualDensity: VisualDensity.compact,
                  onPressed: onExpand,
                  icon: Icon(Icons.open_in_full, size: 18, color: c.inkMuted),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (written.isEmpty)
            Text(
              'Hier erscheint dein Rechenweg in Handschrift, während du tippst.',
              style: TextStyle(fontFamily: handwritingFont, fontSize: fontSize * 0.75, color: c.inkMuted),
            ),
          for (final w in written)
            Padding(
              key: ValueKey('hand-line-${w.i}'),
              padding: EdgeInsets.only(bottom: fontSize * 0.45),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: fontSize * 1.1,
                    child: Text(
                      '${w.i + 1})',
                      style: TextStyle(fontFamily: handwritingFont, fontSize: fontSize * 0.6, color: c.inkMuted),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: w.i == resultLine
                          ? Container(
                              padding: const EdgeInsets.only(bottom: 3),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: ink, width: 1.3)),
                              ),
                              child: Container(
                                padding: const EdgeInsets.only(bottom: 2),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: ink, width: 1.3)),
                                ),
                                child: HandMath(w.text, fontSize: fontSize, color: ink),
                              ),
                            )
                          : HandMath(w.text, fontSize: fontSize, color: ink),
                    ),
                  ),
                  if (statuses[w.i] case final s?)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(
                        switch (s) {
                          PaperLineStatus.ok => Icons.check_rounded,
                          PaperLineStatus.error => Icons.close_rounded,
                          PaperLineStatus.follow => Icons.subdirectory_arrow_right_rounded,
                          PaperLineStatus.unclear => Icons.question_mark_rounded,
                        },
                        key: ValueKey('hand-mark-${w.i}'),
                        semanticLabel: s.label,
                        size: fontSize * 1.1,
                        color: red,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Rechenblatt bildschirmfüllend, zoombar.
Future<void> showHandwrittenSheet(
  BuildContext context, {
  required List<String> lines,
  Map<int, PaperLineStatus> statuses = const {},
  int? resultLine,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (ctx) => Scaffold(
      appBar: AppBar(title: const Text('Dein Rechenweg')),
      body: InteractiveViewer(
        minScale: 0.6,
        maxScale: 4,
        constrained: false,
        child: SizedBox(
          width: math.max(MediaQuery.sizeOf(ctx).width, 700),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: HandwrittenSheet(lines: lines, statuses: statuses, resultLine: resultLine, fontSize: 28),
          ),
        ),
      ),
    ),
  ),
);
