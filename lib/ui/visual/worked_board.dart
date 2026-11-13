import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/worked_solution.dart';
import '../../theme/app_colors.dart';

/// Markierungen in Tafel-Zeilen (`\add{…}`, `\del{…}`, `\focus{…}`) → LaTeX.
class WorkMarkup {
  WorkMarkup._();

  static const _macros = ['add', 'del', 'focus'];

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Ersetzt die Markierungen: [colored] = farbig (dazu grün, weg rot und
  /// durchgestrichen, bearbeitet blau), sonst nur der Inhalt.
  static String toTex(String s, {bool colored = true, Color? add, Color? del, Color? focus}) {
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      String? hit;
      if (s[i] == r'\') {
        for (final m in _macros) {
          if (s.startsWith('\\$m{', i)) {
            hit = m;
            break;
          }
        }
      }
      if (hit == null) {
        out.write(s[i]);
        i++;
        continue;
      }
      final open = i + hit.length + 1;
      final close = _matching(s, open);
      if (close < 0) {
        out.write(s.substring(i));
        break;
      }
      final inner = toTex(s.substring(open + 1, close), colored: colored, add: add, del: del, focus: focus);
      if (!colored) {
        out.write('{$inner}');
      } else {
        switch (hit) {
          case 'add':
            out.write('\\textcolor{${_hex(add ?? const Color(0xFF2E7D32))}}{$inner}');
          case 'del':
            out.write('\\textcolor{${_hex(del ?? const Color(0xFFC62828))}}{\\cancel{$inner}}');
          default:
            out.write('\\textcolor{${_hex(focus ?? const Color(0xFF1565C0))}}{$inner}');
        }
      }
      i = close + 1;
    }
    return out.toString();
  }

  static int _matching(String s, int open) {
    var depth = 0;
    for (var j = open; j < s.length; j++) {
      if (s[j] == r'\' && j + 1 < s.length && (s[j + 1] == '{' || s[j + 1] == '}')) {
        j++;
        continue;
      }
      if (s[j] == '{') depth++;
      if (s[j] == '}') {
        depth--;
        if (depth == 0) return j;
      }
    }
    return -1;
  }

  static bool hasMarks(String s) => _macros.any((m) => s.contains('\\$m{'));

  static final _relations = [r'\Leftrightarrow', r'\iff', r'\Rightarrow', r'\approx', r'\neq', r'\le', r'\ge', '='];

  /// Teilt eine Zeile am ersten Gleichheitszeichen (bzw. ⇔, ≈ …) außerhalb
  /// von Klammern: (links, Zeichen, rechts). Ohne Zeichen: ('', '', Zeile).
  static (String, String, String) split(String tex) {
    var depth = 0;
    for (var i = 0; i < tex.length; i++) {
      final ch = tex[i];
      if (ch == r'\') {
        // \{ \} und \left( \right) überspringen bzw. zählen
        if (tex.startsWith(r'\left', i)) {
          depth++;
          i += 4;
          continue;
        }
        if (tex.startsWith(r'\right', i)) {
          depth--;
          i += 5;
          continue;
        }
        if (depth == 0) {
          for (final r in _relations.where((r) => r.startsWith(r'\'))) {
            if (tex.startsWith(r, i) &&
                !RegExp('[A-Za-z]').hasMatch(tex.length > i + r.length ? tex[i + r.length] : ' ')) {
              return (tex.substring(0, i).trim(), r, tex.substring(i + r.length).trim());
            }
          }
        }
        if (i + 1 < tex.length && !RegExp('[A-Za-z]').hasMatch(tex[i + 1])) i++;
        continue;
      }
      if (ch == '{' || ch == '(' || ch == '[') depth++;
      if (ch == '}' || ch == ')' || ch == ']') depth--;
      if (ch == '=' && depth == 0) return (tex.substring(0, i).trim(), '=', tex.substring(i + 1).trim());
    }
    return ('', '', tex.trim());
  }
}

/// Eine Zeile an der Tafel.
class BoardLine {
  const BoardLine({required this.tex, this.op = '', this.colored = false, this.isNew = false, this.isCurrent = false});

  final String tex;

  /// Umformung rechts („-5x“).
  final String op;

  /// Markierungen farbig zeigen.
  final bool colored;

  /// Gerade entstanden (blendet ein).
  final bool isNew;

  /// Daran wird gerade gearbeitet.
  final bool isCurrent;
}

/// Ablauf des Vorrechnens: Schritt [step], Phase [phase] (0 = Ansatz mit
/// Umformung, 1 = markiert, 2 = Ergebnis). Baut daraus die Tafel.
class WorkPlayback {
  const WorkPlayback(this.steps);

  final List<WorkStep> steps;

  /// Phasen, die Schritt [i] hat (immer 0; 1 bei Markierungen; 2 bei
  /// eigener Ergebniszeile).
  List<int> phasesOf(int i) {
    final s = steps[i];
    return [0, if (s.work.trim().isNotEmpty) 1, if (s.hasLine) 2];
  }

  /// Gesamtzahl der Takte (für Fortschritt und „Weiter“).
  int get length => [for (var i = 0; i < steps.length; i++) phasesOf(i).length].fold(0, (a, b) => a + b);

  /// Takt [t] → (Schritt, Phase).
  (int, int) at(int t) {
    var rest = t;
    for (var i = 0; i < steps.length; i++) {
      final p = phasesOf(i);
      if (rest < p.length) return (i, p[rest]);
      rest -= p.length;
    }
    final last = steps.length - 1;
    return (last, phasesOf(last).last);
  }

  /// Erster Takt von Schritt [i].
  int startOf(int i) {
    var t = 0;
    for (var k = 0; k < i && k < steps.length; k++) {
      t += phasesOf(k).length;
    }
    return t;
  }

  static String _plain(String s) => WorkMarkup.toTex(s, colored: false).replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Die Tafel bei Schritt [step], Phase [phase].
  List<BoardLine> board(int step, int phase) {
    final lines = <BoardLine>[];
    void addHistory(int k) {
      final s = steps[k];
      if (s.from.trim().isNotEmpty && (lines.isEmpty || _plain(lines.last.tex) != _plain(s.from))) {
        lines.add(BoardLine(tex: s.from));
      }
      if (s.hasLine) lines.add(BoardLine(tex: s.to));
    }

    for (var k = 0; k < step && k < steps.length; k++) {
      addHistory(k);
    }
    if (step >= steps.length) return lines;
    final s = steps[step];
    // Ausgangszeile dieses Schritts: eigene oder die letzte der Tafel.
    final fromNew = s.from.trim().isNotEmpty && (lines.isEmpty || _plain(lines.last.tex) != _plain(s.from));
    final base = fromNew ? s.from : (lines.isEmpty ? '' : lines.removeLast().tex);
    if (base.isNotEmpty || s.work.trim().isNotEmpty) {
      final showWork = phase >= 1 && s.work.trim().isNotEmpty;
      lines.add(
        BoardLine(
          tex: showWork ? s.work : base,
          op: s.op,
          colored: showWork,
          isCurrent: phase < 2,
          isNew: fromNew && phase == 0,
        ),
      );
    }
    if (phase >= 2 && s.hasLine) lines.add(BoardLine(tex: s.to, colored: true, isNew: true, isCurrent: true));
    return lines;
  }
}

/// Die Tafel: Zeilen untereinander, am Gleichheitszeichen ausgerichtet,
/// Umformungen rechts („| −5x“), neue Zeilen blenden ein.
class WorkBoard extends StatefulWidget {
  const WorkBoard({super.key, required this.lines, this.fontSize = 22});

  final List<BoardLine> lines;
  final double fontSize;

  @override
  State<WorkBoard> createState() => _WorkBoardState();
}

class _WorkBoardState extends State<WorkBoard> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(WorkBoard old) {
    super.didUpdateWidget(old);
    if (widget.lines.length != old.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chalk = dark ? const Color(0xFFE8EAF0) : const Color(0xFF1B2333);
    final add = dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    final del = dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828);
    final focus = dark ? const Color(0xFF82B1FF) : const Color(0xFF1565C0);
    final opColor = dark ? const Color(0xFFFFCC80) : const Color(0xFF8D5A00);
    final style = TextStyle(fontSize: widget.fontSize, color: chalk);

    Widget math(String tex, {required bool colored, Color? color}) {
      if (tex.trim().isEmpty) return const SizedBox.shrink();
      final source = WorkMarkup.toTex(tex, colored: colored, add: add, del: del, focus: focus);
      return Math.tex(
        source,
        textStyle: color == null ? style : style.copyWith(color: color),
        mathStyle: MathStyle.display,
        onErrorFallback: (_) => Text(tex, style: style.copyWith(fontSize: widget.fontSize * 0.7)),
      );
    }

    Widget fade(Widget child, Object key) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(key: ValueKey(key), child: child),
    );

    final cells = <Widget>[];
    final backgrounds = <Color?>[];
    for (final (i, line) in widget.lines.indexed) {
      final (left, rel, right) = WorkMarkup.split(line.tex);
      final dim = !line.isCurrent && i < widget.lines.length - 1;
      final content = '${line.tex}|${line.colored}';
      final row = <Widget>[
        fade(math(left, colored: line.colored), 'l$content'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.fontSize * 0.3),
          child: math(rel, colored: false),
        ),
        fade(math(right, colored: line.colored), 'r$content'),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (child, anim) => SlideTransition(
            position: Tween(begin: const Offset(0.6, 0), end: Offset.zero).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: line.op.trim().isEmpty
              ? const SizedBox(key: ValueKey('no-op'), width: 8)
              : Padding(
                  key: ValueKey('op-${line.op}'),
                  padding: EdgeInsets.only(left: widget.fontSize * 0.8),
                  child: math('|\\;${line.op}', colored: false, color: opColor),
                ),
        ),
      ];
      for (final (col, cell) in row.indexed) {
        Widget w = cell;
        // ältere Zeilen etwas zurücknehmen
        if (dim) w = Opacity(opacity: 0.62, child: w);
        if (line.isNew) {
          w = TweenAnimationBuilder<double>(
            key: ValueKey('new-$i-$col-${line.tex}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeOut,
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
            ),
            child: w,
          );
        }
        cells.add(KeyedSubtree(key: ValueKey('board-$i-$col'), child: w));
      }
      backgrounds.add(line.isCurrent ? c.accentSoft.withAlpha(dark ? 60 : 110) : null);
    }

    return Container(
      key: const ValueKey('work-board'),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E2A26) : const Color(0xFFFBFBF6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(14),
      child: widget.lines.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Die Tafel ist noch leer.', style: TextStyle(color: c.inkMuted)),
            )
          : Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _AlignedRows(rowGap: widget.fontSize * 0.5, backgrounds: backgrounds, children: cells),
                ),
              ),
            ),
    );
  }
}

/// Zeilen aus je vier Teilen (links, Zeichen, rechts, Umformung) – die
/// Spalten so breit wie ihr breitester Teil, links rechtsbündig, so dass die
/// Gleichheitszeichen untereinander stehen. (Eigenes Layout, weil Formeln
/// keine Eigenbreite liefern, die eine Table bräuchte.)
class _AlignedRows extends MultiChildRenderObjectWidget {
  const _AlignedRows({required super.children, required this.backgrounds, this.rowGap = 10});

  final List<Color?> backgrounds;
  final double rowGap;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderAlignedRows(backgrounds, rowGap);

  @override
  void updateRenderObject(BuildContext context, _RenderAlignedRows renderObject) {
    renderObject
      ..backgrounds = backgrounds
      ..rowGap = rowGap;
  }
}

class _AlignedParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAlignedRows extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AlignedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AlignedParentData> {
  _RenderAlignedRows(this._backgrounds, this._rowGap);

  List<Color?> _backgrounds;
  set backgrounds(List<Color?> v) {
    _backgrounds = v;
    markNeedsPaint();
  }

  double _rowGap;
  set rowGap(double v) {
    if (v == _rowGap) return;
    _rowGap = v;
    markNeedsLayout();
  }

  final List<Rect> _rowRects = [];

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AlignedParentData) child.parentData = _AlignedParentData();
  }

  @override
  void performLayout() {
    final children = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      children.add(child);
      child = childAfter(child);
    }
    final widths = [0.0, 0.0, 0.0, 0.0];
    final rows = (children.length / 4).ceil();
    final heights = List.filled(rows, 0.0);
    for (final (i, ch) in children.indexed) {
      ch.layout(const BoxConstraints(), parentUsesSize: true);
      final col = i % 4;
      if (ch.size.width > widths[col]) widths[col] = ch.size.width;
      if (ch.size.height > heights[i ~/ 4]) heights[i ~/ 4] = ch.size.height;
    }
    const padX = 8.0;
    final total = widths.fold(0.0, (a, b) => a + b) + 2 * padX;
    _rowRects.clear();
    var y = 0.0;
    for (var r = 0; r < rows; r++) {
      final h = heights[r] + _rowGap;
      var x = padX;
      for (var col = 0; col < 4; col++) {
        final i = r * 4 + col;
        if (i >= children.length) break;
        final ch = children[i];
        final dx = switch (col) {
          0 => x + widths[0] - ch.size.width,
          1 => x + (widths[1] - ch.size.width) / 2,
          _ => x,
        };
        (ch.parentData! as _AlignedParentData).offset = Offset(dx, y + (h - ch.size.height) / 2);
        x += widths[col];
      }
      _rowRects.add(Rect.fromLTWH(0, y + 2, total, h - 4));
      y += h;
    }
    size = constraints.constrain(Size(total, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final (r, rect) in _rowRects.indexed) {
      final color = r < _backgrounds.length ? _backgrounds[r] : null;
      if (color == null) continue;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(rect.shift(offset), const Radius.circular(8)),
        Paint()..color = color,
      );
    }
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
