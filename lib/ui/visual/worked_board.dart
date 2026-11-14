import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/worked_solution.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';

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

/// Zerlegt eine Tafel-Zeile in antippbare Teile (sokratischer Modus):
/// Zeichen wie =, +, − einzeln, sonst Bausteine samt Hochzahl/Index/Strich
/// (`y'`, `y^2`, `\sin(x)`, `\frac{dy}{dx}`, Klammern als Ganzes).
class LatexChunks {
  LatexChunks._();

  static const _functions = {
    'sin',
    'cos',
    'tan',
    'ln',
    'log',
    'exp',
    'arcsin',
    'arccos',
    'arctan',
    'sinh',
    'cosh',
    'tanh',
    'lim',
    'max',
    'min',
  };
  static const _twoArgs = {'frac', 'dfrac', 'tfrac', 'binom'};
  static const _oneArg = {'sqrt', 'vec', 'overline', 'bar', 'hat', 'mathrm', 'text', 'operatorname', 'mathbf'};
  static const _operators = {
    'cdot',
    'times',
    'div',
    'pm',
    'mp',
    'le',
    'leq',
    'ge',
    'geq',
    'neq',
    'approx',
    'Rightarrow',
    'Leftrightarrow',
    'iff',
    'to',
    'quad',
    'qquad',
  };

  static List<({String tex, bool op})> split(String line) {
    final s = WorkMarkup.toTex(line, colored: false);
    final out = <({String tex, bool op})>[];
    var i = 0;

    int group(int at, String open, String close) {
      var depth = 0;
      for (var j = at; j < s.length; j++) {
        if (s[j] == r'\' && j + 1 < s.length) {
          j++;
          continue;
        }
        if (s[j] == open) depth++;
        if (s[j] == close) {
          depth--;
          if (depth == 0) return j + 1;
        }
      }
      return s.length;
    }

    int skipSpace(int at) {
      var j = at;
      while (j < s.length && s[j] == ' ') {
        j++;
      }
      return j;
    }

    // Hochzahl, Index, Striche an einen Baustein hängen.
    int scripts(int at) {
      var j = at;
      while (true) {
        final k = skipSpace(j);
        if (k >= s.length) return j;
        if (s[k] == "'") {
          j = k + 1;
          continue;
        }
        if (s[k] == '^' || s[k] == '_') {
          var m = skipSpace(k + 1);
          if (m >= s.length) return s.length;
          if (s[m] == '{') {
            j = group(m, '{', '}');
          } else if (s[m] == r'\') {
            final cmd = RegExp(r'\\[A-Za-z]+').matchAsPrefix(s, m);
            j = cmd?.end ?? m + 2;
          } else {
            j = m + 1;
          }
          continue;
        }
        return j;
      }
    }

    void add(int from, int to, {bool op = false}) {
      final t = s.substring(from, to).trim();
      if (t.isNotEmpty) out.add((tex: t, op: op));
    }

    while (i < s.length) {
      i = skipSpace(i);
      if (i >= s.length) break;
      final ch = s[i];
      final start = i;
      if (ch == '=' || ch == '+' || ch == '-' || ch == '<' || ch == '>' || ch == ',' || ch == '/' || ch == ':') {
        add(i, i + 1, op: true);
        i++;
        continue;
      }
      if (ch == r'\') {
        final m = RegExp(r'\\([A-Za-z]+)').matchAsPrefix(s, i);
        if (m == null) {
          // \, \; \! usw.
          i += 2;
          continue;
        }
        final name = m[1]!;
        var j = m.end;
        if (_operators.contains(name)) {
          add(start, j, op: true);
          i = j;
          continue;
        }
        if (name == 'left') {
          // bis zum passenden \right und dessen Zeichen
          var depth = 0;
          var k = i;
          while (k < s.length) {
            if (s.startsWith(r'\left', k)) depth++;
            if (s.startsWith(r'\right', k)) {
              depth--;
              if (depth == 0) {
                k += 6;
                if (k < s.length && s[k] == r'\') {
                  k = (RegExp(r'\\[A-Za-z]+|\\.').matchAsPrefix(s, k)?.end) ?? k + 1;
                } else if (k < s.length) {
                  k++;
                }
                break;
              }
            }
            k++;
          }
          j = scripts(k);
          add(start, j);
          i = j;
          continue;
        }
        if (_twoArgs.contains(name)) {
          j = skipSpace(j);
          if (j < s.length && s[j] == '{') j = group(j, '{', '}');
          j = skipSpace(j);
          if (j < s.length && s[j] == '{') j = group(j, '{', '}');
        } else if (_oneArg.contains(name)) {
          j = skipSpace(j);
          if (j < s.length && s[j] == '[') j = group(j, '[', ']');
          j = skipSpace(j);
          if (j < s.length && s[j] == '{') j = group(j, '{', '}');
        } else if (_functions.contains(name)) {
          j = scripts(j);
          // Funktion samt Argument in Klammern als ein Teil.
          final k = skipSpace(j);
          if (k < s.length && s[k] == '(') {
            j = group(k, '(', ')');
          } else if (s.startsWith(r'\left', k)) {
            var depth = 0;
            var m2 = k;
            while (m2 < s.length) {
              if (s.startsWith(r'\left', m2)) depth++;
              if (s.startsWith(r'\right', m2)) {
                depth--;
                if (depth == 0) {
                  m2 += 7;
                  break;
                }
              }
              m2++;
            }
            j = m2.clamp(0, s.length);
          }
        }
        j = scripts(j);
        add(start, j);
        i = j;
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') {
        final close = ch == '(' ? ')' : (ch == '[' ? ']' : '}');
        final j = scripts(group(i, ch, close));
        add(start, j);
        i = j;
        continue;
      }
      if (RegExp(r'[0-9]').hasMatch(ch)) {
        var j = i;
        while (j < s.length &&
            RegExp(r'[0-9.,{}]').hasMatch(s[j]) &&
            !(s[j] == ',' && (j + 1 >= s.length || !RegExp(r'[0-9}]').hasMatch(s[j + 1])))) {
          j++;
        }
        j = scripts(j);
        add(start, j);
        i = j;
        continue;
      }
      final j = scripts(i + 1);
      add(start, j);
      i = j;
    }
    return out;
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

/// Ein Abschnitt der Tafel.
sealed class BoardBlock {
  const BoardBlock();
}

/// Rechenzeilen, am Gleichheitszeichen ausgerichtet.
class MathBlock extends BoardBlock {
  MathBlock(this.lines);
  final List<BoardLine> lines;
}

/// Aufgabe verstehen: gegeben, gesucht, zu beachten.
class FocusBlock extends BoardBlock {
  const FocusBlock(this.marks, {this.isNew = false});
  final List<WorkMark> marks;
  final bool isNew;
}

/// Ein Stück der Antwort.
class TextBlock extends BoardBlock {
  const TextBlock(this.text, {this.title = '', this.isNew = false});
  final String text;
  final String title;
  final bool isNew;
}

/// Tabelle (Stand nach dem letzten Tabellen-Schritt).
class TableBlock extends BoardBlock {
  const TableBlock(this.table, {this.isNew = false});
  final WorkTable table;
  final bool isNew;
}

/// Ablauf des Vorrechnens: Schritt [step], Phase [phase] (0 = Ansatz mit
/// Umformung bzw. Erklärung, 1 = markiert, 2 = Ergebnis). Baut daraus die
/// Tafel – Rechenzeilen, Aufgaben-Analyse, Antworttext und Tabellen.
class WorkPlayback {
  const WorkPlayback(this.steps);

  final List<WorkStep> steps;

  /// Phasen, die Schritt [i] hat (immer 0; 1 bei Markierungen; 2 bei
  /// eigener Ergebniszeile bzw. neuem Inhalt).
  List<int> phasesOf(int i) {
    final s = steps[i];
    return [0, if (s.kind == WorkKind.math && s.work.trim().isNotEmpty) 1, if (s.hasLine) 2];
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

  /// Nur die Rechenzeilen der Tafel (für Fragen an die KI und Tests).
  List<BoardLine> board(int step, int phase) => [
    for (final b in blocks(step, phase))
      if (b is MathBlock) ...b.lines,
  ];

  /// Die Tafel bei Schritt [step], Phase [phase].
  List<BoardBlock> blocks(int step, int phase) {
    final out = <BoardBlock>[];
    BoardLine? lastLine() {
      for (final b in out.reversed) {
        if (b is MathBlock && b.lines.isNotEmpty) return b.lines.last;
      }
      return null;
    }

    List<BoardLine> mathLines() {
      if (out.isEmpty || out.last is! MathBlock) out.add(MathBlock([]));
      return (out.last as MathBlock).lines;
    }

    void addOther(WorkStep s, {bool isNew = false}) {
      switch (s.kind) {
        case WorkKind.focus:
          out.add(FocusBlock(s.marks, isNew: isNew));
        case WorkKind.text:
          out.add(TextBlock(s.content, title: s.title, isNew: isNew));
        case WorkKind.table:
          // Die Tabelle wächst an derselben Stelle.
          if (out.isNotEmpty && out.last is TableBlock) out.removeLast();
          out.add(TableBlock(s.table!, isNew: isNew));
        case WorkKind.math:
          break;
      }
    }

    for (var k = 0; k < step && k < steps.length; k++) {
      final s = steps[k];
      if (s.kind != WorkKind.math) {
        if (s.hasLine) addOther(s);
        continue;
      }
      final last = lastLine();
      if (s.from.trim().isNotEmpty && (last == null || _plain(last.tex) != _plain(s.from))) {
        mathLines().add(BoardLine(tex: s.from));
      }
      if (s.hasLine) mathLines().add(BoardLine(tex: s.to));
    }
    if (step >= steps.length) return out;
    final s = steps[step];
    if (s.kind != WorkKind.math) {
      if (phase >= 2 && s.hasLine) addOther(s, isNew: true);
      return out;
    }
    // Ausgangszeile dieses Schritts: eigene oder die letzte der Tafel.
    final last = lastLine();
    final fromNew = s.from.trim().isNotEmpty && (last == null || _plain(last.tex) != _plain(s.from));
    String base;
    if (fromNew) {
      base = s.from;
    } else if (out.isNotEmpty && out.last is MathBlock && (out.last as MathBlock).lines.isNotEmpty) {
      base = (out.last as MathBlock).lines.removeLast().tex;
    } else {
      base = last?.tex ?? '';
    }
    if (phase < 0) {
      // Sokratisch: nur die Ausgangszeile, noch ohne Umformung.
      if (base.isNotEmpty) mathLines().add(BoardLine(tex: base, isCurrent: true));
      return out;
    }
    if (base.isNotEmpty || s.work.trim().isNotEmpty) {
      final showWork = phase >= 1 && s.work.trim().isNotEmpty;
      mathLines().add(
        BoardLine(
          tex: showWork ? s.work : base,
          op: s.op,
          colored: showWork,
          isCurrent: phase < 2,
          isNew: fromNew && phase == 0,
        ),
      );
    }
    if (phase >= 2 && s.hasLine) mathLines().add(BoardLine(tex: s.to, colored: true, isNew: true, isCurrent: true));
    return out;
  }
}

/// Die Tafel: Rechenzeilen untereinander, am Gleichheitszeichen
/// ausgerichtet, Umformungen rechts („| −5x“), neue Zeilen blenden ein; dazu
/// Aufgaben-Analyse, Antwort-Absätze und Tabellen.
class WorkBoard extends StatefulWidget {
  const WorkBoard({super.key, required this.blocks, this.fontSize = 22});

  /// Nur Rechenzeilen (ein einziger Rechenblock).
  WorkBoard.lines({Key? key, required List<BoardLine> lines, double fontSize = 22})
    : this(key: key, blocks: [MathBlock(lines)], fontSize: fontSize);

  final List<BoardBlock> blocks;
  final double fontSize;

  @override
  State<WorkBoard> createState() => _WorkBoardState();
}

class _WorkBoardState extends State<WorkBoard> {
  final _scroll = ScrollController();

  int _size(List<BoardBlock> blocks) => blocks.fold(
    0,
    (n, b) =>
        n +
        switch (b) {
          MathBlock(:final lines) => lines.length,
          TableBlock(:final table) => 1 + table.rows.length,
          _ => 1,
        },
  );

  @override
  void didUpdateWidget(WorkBoard old) {
    super.didUpdateWidget(old);
    if (_size(widget.blocks) != _size(old.blocks)) {
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
    final empty = widget.blocks.every((b) => b is MathBlock && b.lines.isEmpty);
    return Container(
      key: const ValueKey('work-board'),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E2A26) : const Color(0xFFFBFBF6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(14),
      child: empty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Die Tafel ist noch leer.', style: TextStyle(color: c.inkMuted)),
            )
          : Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, b) in widget.blocks.indexed) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _block(context, b, i),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  /// Neues blendet von unten ein.
  static Widget _appear(Widget child, Object key, bool isNew) => !isNew
      ? child
      : TweenAnimationBuilder<double>(
          key: ValueKey(key),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeOut,
          builder: (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
          ),
          child: child,
        );

  Widget _block(BuildContext context, BoardBlock b, int index) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final newColor = dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    switch (b) {
      case MathBlock(:final lines):
        return SingleChildScrollView(scrollDirection: Axis.horizontal, child: _mathLines(context, lines, index));
      case FocusBlock(:final marks, :final isNew):
        final groups = <String, List<WorkMark>>{};
        for (final m in marks) {
          groups.putIfAbsent(m.role, () => []).add(m);
        }
        (String, Color) style(String role) => switch (role) {
          'gegeben' => ('Gegeben', dark ? const Color(0xFF82B1FF) : const Color(0xFF1565C0)),
          'gesucht' => ('Gesucht', newColor),
          _ => ('Zu beachten', dark ? const Color(0xFFFFCC80) : const Color(0xFF8D5A00)),
        };
        return _appear(
          Column(
            key: ValueKey('board-focus-$index'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final role in const ['gesucht', 'gegeben', 'hinweis'])
                if (groups[role] case final list?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${style(role).$1}:',
                          style: TextStyle(fontWeight: FontWeight.w700, color: style(role).$2, fontSize: 14),
                        ),
                        for (final m in list)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: style(role).$2.withAlpha(dark ? 50 : 28),
                              border: Border.all(color: style(role).$2.withAlpha(120)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: MathText(m.text, style: const TextStyle(fontSize: 14.5, height: 1.3)),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
          'focus-$index-${marks.length}',
          isNew,
        );
      case TextBlock(:final text, :final title, :final isNew):
        return _appear(
          Container(
            key: ValueKey('board-text-$index'),
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            decoration: BoxDecoration(
              color: isNew ? newColor.withAlpha(dark ? 40 : 22) : null,
              border: Border(left: BorderSide(color: isNew ? newColor : c.border, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted),
                  ),
                MathText(text, style: const TextStyle(fontSize: 16, height: 1.5)),
              ],
            ),
          ),
          'text-$index-$text',
          isNew,
        );
      case TableBlock(:final table, :final isNew):
        final cols = table.columns.isNotEmpty
            ? table.columns.length
            : table.rows.fold(0, (n, r) => r.length > n ? r.length : n);
        final cells = <Widget>[];
        final backgrounds = <Color?>[];
        Widget cell(String t, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: MathText(
            t,
            style: TextStyle(fontSize: 14.5, fontWeight: head ? FontWeight.w700 : FontWeight.w400, height: 1.3),
          ),
        );
        if (table.columns.isNotEmpty) {
          for (var col = 0; col < cols; col++) {
            cells.add(cell(col < table.columns.length ? table.columns[col] : '', head: true));
            backgrounds.add(c.surfaceAlt);
          }
        }
        for (final (r, row) in table.rows.indexed) {
          for (var col = 0; col < cols; col++) {
            cells.add(cell(col < row.length ? row[col] : ''));
            backgrounds.add(isNew && table.fresh.contains((r, col)) ? newColor.withAlpha(dark ? 70 : 45) : null);
          }
        }
        return SingleChildScrollView(
          key: ValueKey('board-table-$index'),
          scrollDirection: Axis.horizontal,
          child: _GridRows(
            columns: cols,
            aligns: List.filled(cols, 0),
            cellBackgrounds: backgrounds,
            gridColor: c.border,
            rowGap: 0,
            maxCellWidth: 280,
            children: cells,
          ),
        );
    }
  }

  Widget _mathLines(BuildContext context, List<BoardLine> lines, int block) {
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
    for (final (i, line) in lines.indexed) {
      final (left, rel, right) = WorkMarkup.split(line.tex);
      final dim = !line.isCurrent && i < lines.length - 1;
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
        w = _appear(w, 'new-$block-$i-$col-${line.tex}', line.isNew);
        final key = block == 0 ? 'board-$i-$col' : 'board-$block-$i-$col';
        cells.add(KeyedSubtree(key: ValueKey(key), child: w));
      }
      backgrounds.add(line.isCurrent ? c.accentSoft.withAlpha(dark ? 60 : 110) : null);
    }
    return _GridRows(
      columns: 4,
      aligns: const [2, 1, 0, 0],
      rowBackgrounds: backgrounds,
      rowGap: widget.fontSize * 0.5,
      children: cells,
    );
  }
}

/// Zeilen aus je [columns] Teilen – die Spalten so breit wie ihr breitester
/// Teil; [aligns] je Spalte: 0 links, 1 Mitte, 2 rechts (bei Rechenzeilen
/// links rechtsbündig, so dass die Gleichheitszeichen untereinander stehen).
/// Eigenes Layout, weil Formeln keine Eigenbreite liefern, die eine Table
/// bräuchte.
class _GridRows extends MultiChildRenderObjectWidget {
  const _GridRows({
    required super.children,
    required this.columns,
    required this.aligns,
    this.rowBackgrounds = const [],
    this.cellBackgrounds = const [],
    this.gridColor,
    this.rowGap = 10,
    this.maxCellWidth = double.infinity,
  });

  /// Breite Zellen brechen um (Tabellen).
  final double maxCellWidth;
  final int columns;
  final List<int> aligns;
  final List<Color?> rowBackgrounds;
  final List<Color?> cellBackgrounds;
  final Color? gridColor;
  final double rowGap;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGridRows()..update(this);

  @override
  void updateRenderObject(BuildContext context, _RenderGridRows renderObject) => renderObject.update(this);
}

class _GridParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderGridRows extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  int _columns = 1;
  List<int> _aligns = const [];
  List<Color?> _rowBackgrounds = const [];
  List<Color?> _cellBackgrounds = const [];
  Color? _gridColor;
  double _rowGap = 10;
  double _maxCellWidth = double.infinity;

  void update(_GridRows w) {
    final relayout =
        w.columns != _columns ||
        w.rowGap != _rowGap ||
        w.aligns.join() != _aligns.join() ||
        w.maxCellWidth != _maxCellWidth;
    _maxCellWidth = w.maxCellWidth;
    _columns = w.columns < 1 ? 1 : w.columns;
    _aligns = w.aligns;
    _rowBackgrounds = w.rowBackgrounds;
    _cellBackgrounds = w.cellBackgrounds;
    _gridColor = w.gridColor;
    _rowGap = w.rowGap;
    if (relayout) markNeedsLayout();
    markNeedsPaint();
  }

  final List<Rect> _rowRects = [];
  final List<Rect> _cellRects = [];

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) child.parentData = _GridParentData();
  }

  @override
  void performLayout() {
    final children = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      children.add(child);
      child = childAfter(child);
    }
    final widths = List.filled(_columns, 0.0);
    final rows = (children.length / _columns).ceil();
    final heights = List.filled(rows, 0.0);
    for (final (i, ch) in children.indexed) {
      ch.layout(BoxConstraints(maxWidth: _maxCellWidth), parentUsesSize: true);
      final col = i % _columns;
      if (ch.size.width > widths[col]) widths[col] = ch.size.width;
      if (ch.size.height > heights[i ~/ _columns]) heights[i ~/ _columns] = ch.size.height;
    }
    final padX = _gridColor == null ? 8.0 : 0.0;
    final total = widths.fold(0.0, (a, b) => a + b) + 2 * padX;
    _rowRects.clear();
    _cellRects.clear();
    var y = 0.0;
    for (var r = 0; r < rows; r++) {
      final h = heights[r] + _rowGap;
      var x = padX;
      for (var col = 0; col < _columns; col++) {
        final i = r * _columns + col;
        if (i >= children.length) break;
        final ch = children[i];
        final align = col < _aligns.length ? _aligns[col] : 0;
        final dx = switch (align) {
          2 => x + widths[col] - ch.size.width,
          1 => x + (widths[col] - ch.size.width) / 2,
          _ => x,
        };
        (ch.parentData! as _GridParentData).offset = Offset(dx, y + (h - ch.size.height) / 2);
        _cellRects.add(Rect.fromLTWH(x, y, widths[col], h));
        x += widths[col];
      }
      _rowRects.add(Rect.fromLTWH(0, y + (_gridColor == null ? 2 : 0), total, h - (_gridColor == null ? 4 : 0)));
      y += h;
    }
    size = constraints.constrain(Size(total, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    for (final (r, rect) in _rowRects.indexed) {
      final color = r < _rowBackgrounds.length ? _rowBackgrounds[r] : null;
      if (color == null) continue;
      canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(offset), const Radius.circular(8)), Paint()..color = color);
    }
    for (final (i, rect) in _cellRects.indexed) {
      final color = i < _cellBackgrounds.length ? _cellBackgrounds[i] : null;
      if (color != null) canvas.drawRect(rect.shift(offset), Paint()..color = color);
    }
    final grid = _gridColor;
    if (grid != null) {
      final paint = Paint()
        ..color = grid
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (final rect in _cellRects) {
        canvas.drawRect(rect.shift(offset), paint);
      }
    }
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
