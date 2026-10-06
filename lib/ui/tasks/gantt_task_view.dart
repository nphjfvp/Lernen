import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/flashcard.dart';
import '../../models/gantt_task.dart';
import '../../services/fsrs_service.dart';
import '../../services/gantt_scheduler.dart';
import '../../theme/app_colors.dart';
import '../study/study_aids.dart';
import '../widgets/math_text.dart';

/// Farben der Teile im Diagramm (unterscheiden sich auch in der Helligkeit).
List<Color> ganttPalette(Brightness b) => b == Brightness.dark
    ? const [Color(0xFF7D9BF0), Color(0xFFC9A2E6), Color(0xFF7FC8B8), Color(0xFFE8B86B), Color(0xFFEEECE6)]
    : const [Color(0xFF23449A), Color(0xFF8E5BB5), Color(0xFF2A7A6A), Color(0xFF9A6A12), Color(0xFF211E1A)];

Color ganttOnColor(Color c) => ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : const Color(0xFF15141A);

/// Terminierungs-Aufgabe beantworten ([QuestionType.gantt]): Balken ins
/// Gantt-Diagramm setzen (Antippen des Starttags, Verschieben per ◀ ▶,
/// Ziehen oder Pfeiltasten), Termine und Liegezeiten eintragen. Die App
/// rechnet die Lösung selbst (GanttScheduler) und erkennt Folgefehler.
///
/// Bewertung: beim ersten Prüfen alles richtig und ohne Tipp = Gut, später
/// bzw. mit Tipp richtig = Schwer, Lösung angesehen/aufgelöst = Nochmal.
class GanttTaskView extends StatefulWidget {
  const GanttTaskView({
    super.key,
    required this.card,
    required this.task,
    required this.isNew,
    required this.onComplete,
    this.examMode = false,
    this.onSkip,
    this.canGiveUp = false,
  });

  final Flashcard card;
  final GanttTask task;
  final bool isNew;
  final bool examMode;
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;
  final VoidCallback? onSkip;
  final bool canGiveUp;

  @override
  State<GanttTaskView> createState() => _GanttTaskViewState();
}

class _GanttTaskViewState extends State<GanttTaskView> {
  late GanttTask _task = widget.task;
  late GanttPlan _ref = GanttScheduler.plan(_task);
  final Map<String, int?> _pos = {};
  String? _sel;
  final Map<String, TextEditingController> _answers = {};
  late bool _live = !widget.examMode;
  bool _checked = false;
  int _attempts = 0;
  int _tips = 0;
  String? _tip;
  bool _revealed = false;
  bool _solved = false;
  bool _submitted = false;
  final _focus = FocusNode();

  /// Bewertung des ersten (gewerteten) Durchgangs, wenn danach mit anderen
  /// Zahlen geübt wird.
  ({Grade? grade, bool? isCorrect})? _firstResult;
  double _dragDx = 0;

  @override
  void initState() {
    super.initState();
    _initAnswers();
  }

  void _initAnswers() {
    for (final c in _answers.values) {
      c.dispose();
    }
    _answers
      ..clear()
      ..addAll({for (final q in _task.questions) q.key: TextEditingController()});
  }

  @override
  void dispose() {
    for (final c in _answers.values) {
      c.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  Map<String, String> get _answerTexts => {for (final e in _answers.entries) e.key: e.value.text};

  Map<String, BarVerdict> get _bars => GanttScheduler.judgeBars(_task, _ref, _pos);
  Map<String, AnswerVerdict> get _answerVerdicts => GanttScheduler.judgeAnswers(_task, _ref, _pos, _answerTexts);

  int get _opCount => _task.items.fold(0, (n, i) => n + i.operations.length);
  int get _placed => _pos.values.whereType<int>().length;

  bool get _allCorrect {
    final barsOk = !_task.drawChart || _bars.values.every((v) => v.status == BarStatus.ok);
    final answersOk = _answerVerdicts.values.every((v) => v.status == AnswerStatus.ok);
    return barsOk && answersOk;
  }

  bool get _finished => _solved || _revealed;

  bool _marksFor(String key) => _checked || _revealed || (_live && _pos[key] != null);

  void _changed() {
    _checked = false;
  }

  void _place(String key, int day) {
    final op = _opOf(key);
    if (op == null || _finished) return;
    final (lo, hi) = _axis;
    setState(() {
      _pos[key] = day.clamp(lo, math.max(lo, hi - op.duration + 1));
      _sel = key;
      _changed();
    });
    _focus.requestFocus();
  }

  void _move(int delta) {
    final key = _sel;
    if (key == null || _pos[key] == null || _finished) return;
    final op = _opOf(key)!;
    final (lo, hi) = _axis;
    setState(() {
      _pos[key] = (_pos[key]! + delta).clamp(lo, math.max(lo, hi - op.duration + 1));
      _changed();
    });
  }

  void _remove() {
    final key = _sel;
    if (key == null || _finished) return;
    setState(() {
      _pos.remove(key);
      _sel = null;
      _changed();
    });
  }

  GanttOperation? _opOf(String key) {
    final hash = key.lastIndexOf('#');
    final item = _task.item(key.substring(0, hash));
    final index = int.tryParse(key.substring(hash + 1));
    if (item == null || index == null || index >= item.operations.length) return null;
    return item.operations[index];
  }

  /// Sichtbare Tage: vom Starttermin bis kurz nach dem Liefertermin bzw. dem
  /// Ende der Lösung.
  (int, int) get _axis {
    final (lo, hi) = _ref.span;
    final due = _task.due ?? hi;
    return (math.min(_task.start, lo), math.max(hi, due) + 2);
  }

  void _check() {
    if (widget.examMode) {
      final answersOk = _answerVerdicts.values.every((v) => v.status == AnswerStatus.ok);
      final barsOk = _bars.values.every((v) => v.status == BarStatus.ok);
      _submit(isCorrect: _task.questions.isEmpty ? barsOk : answersOk);
      return;
    }
    setState(() {
      _checked = true;
      _attempts++;
      _tip = null;
      if (_allCorrect) _solved = true;
    });
  }

  void _hint() {
    setState(() {
      _tips++;
      _tip = GanttScheduler.hint(_task, _ref, _pos, _answerTexts);
    });
  }

  void _reveal() {
    setState(() {
      _revealed = true;
      _checked = true;
      _tip = null;
    });
  }

  void _fillFromChart() {
    setState(() {
      for (final q in _task.questions) {
        if (q.ask != GanttAsk.start && q.ask != GanttAsk.end) continue;
        final own = GanttScheduler.ownAnswer(_task, _pos, q);
        if (own != null) _answers[q.key]!.text = '$own';
      }
      _changed();
    });
  }

  void _reset() {
    setState(() {
      _pos.clear();
      _sel = null;
      for (final c in _answers.values) {
        c.clear();
      }
      _checked = false;
      _tip = null;
    });
  }

  void _submit({Grade? selfGrade, bool? isCorrect}) {
    if (_submitted) return;
    _submitted = true;
    widget.onComplete(selfGrade: selfGrade, isCorrect: isCorrect);
  }

  ({Grade? grade, bool? isCorrect}) get _result {
    if (_revealed) return (grade: null, isCorrect: false);
    if (_attempts <= 1 && _tips == 0) return (grade: null, isCorrect: true);
    return (grade: Grade.hard, isCorrect: true);
  }

  void _next() {
    final r = _firstResult ?? _result;
    _submit(selfGrade: r.grade, isCorrect: r.isCorrect);
  }

  void _practiceVariant() {
    _firstResult ??= _result;
    setState(() {
      _task = GanttScheduler.variant(_task, math.Random());
      _ref = GanttScheduler.plan(_task);
      _pos.clear();
      _sel = null;
      _checked = false;
      _attempts = 0;
      _tips = 0;
      _tip = null;
      _revealed = false;
      _solved = false;
      _initAnswers();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_sel == null) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
      _remove();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // -------------------------------------------------------------------------
  // Anzeige
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 980;
      final taskCard = _taskCard(c);
      final chart = _task.drawChart ? _chartCard(c, constraints.maxWidth - (wide ? 380 : 40)) : const SizedBox.shrink();
      final answers = _task.questions.isEmpty ? const SizedBox.shrink() : _answersCard(c);
      final lower = [
        if (_tip != null) Padding(padding: const EdgeInsets.only(top: 10), child: _tipBox(c)),
        if (_checked && !widget.examMode) Padding(padding: const EdgeInsets.only(top: 10), child: _resultCard(c)),
        if (_revealed || _solved) Padding(padding: const EdgeInsets.only(top: 10), child: _howCard(c)),
        Padding(padding: const EdgeInsets.only(top: 12), child: _buttons(c)),
      ];
      final body = wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 340, child: Column(children: [taskCard, const SizedBox(height: 12), answers])),
                const SizedBox(width: 20),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [chart, ...lower])),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                taskCard,
                if (!widget.examMode) Padding(padding: const EdgeInsets.only(top: 10), child: _modeSwitch(c)),
                const SizedBox(height: 10),
                chart,
                const SizedBox(height: 12),
                answers,
                ...lower,
              ],
            );
      return Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (widget.isNew)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(20)),
                  child: Text('NEU', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.warn)),
                ),
              ),
            if (wide && !widget.examMode) Padding(padding: const EdgeInsets.only(bottom: 10), child: _modeSwitch(c)),
            body,
          ],
        ),
      );
    });
  }

  Widget _modeSwitch(AppColors c) => Row(
        children: [
          Text('Rückmeldung', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
          const SizedBox(width: 10),
          Expanded(
            child: SegmentedButton<bool>(
              key: const ValueKey('gantt-mode'),
              segments: const [
                ButtonSegment(value: true, label: Text('Sofort')),
                ButtonSegment(value: false, label: Text('Erst am Ende')),
              ],
              selected: {_live},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _live = s.first;
                _checked = false;
              }),
            ),
          ),
        ],
      );

  Widget _taskCard(AppColors c) {
    final palette = ganttPalette(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                  child: Text('${QuestionType.gantt.label} · ${_task.direction.label}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
                ),
              ),
              const Spacer(),
              if (!widget.examMode) SourceLinkButton(card: widget.card),
            ],
          ),
          const SizedBox(height: 10),
          MathText(widget.card.front, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 10),
          Text(
            'Start Tag ${_task.start}${_task.due == null ? '' : ' · Liefertermin Tag ${_task.due}'} · ${_task.counting.label}',
            style: TextStyle(fontSize: 12.5, color: c.inkMuted),
          ),
          const SizedBox(height: 8),
          for (final (i, item) in _task.items.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: palette[i % palette.length], borderRadius: BorderRadius.circular(3)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(item.name,
                            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                      if (item.needs.isNotEmpty)
                        Flexible(
                          child: Text(
                            '  braucht ${item.needs.map((n) => _task.item(n)?.name ?? n).join(', ')}',
                            style: TextStyle(fontSize: 12, color: c.inkMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final op in item.operations)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                          child: Text('${op.name} ${op.duration}', style: const TextStyle(fontSize: 12.5)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // -- Diagramm --------------------------------------------------------------

  static const _labelW = 128.0;
  static const _rowH = 40.0;
  static const _headH = 26.0;

  Widget _chartCard(AppColors c, double width) {
    final (lo, hi) = _axis;
    final days = hi - lo + 1;
    final cw = ((width - _labelW - 2) / days).clamp(24.0, 44.0);
    final palette = ganttPalette(Theme.of(context).brightness);
    final bars = _bars;
    final rows = <Widget>[];
    final labels = <Widget>[];
    final hatches = <({int row, double top, int from, int to, String text})>[];
    var y = 0.0;
    final rowTops = <String, double>{};
    for (final (ii, item) in _task.items.indexed) {
      labels.add(_headLabel(c, item.name, palette[ii % palette.length]));
      rows.add(Container(height: _headH, color: c.surfaceAlt));
      y += _headH;
      for (var k = 0; k < item.operations.length; k++) {
        final key = ganttOpKey(item.id, k);
        rowTops[key] = y;
        labels.add(_opLabel(c, key, item.operations[k], bars[key]!));
        rows.add(_track(c, key, item.operations[k], cw, lo, days, palette[ii % palette.length], bars[key]!));
        y += _rowH;
      }
      // Liegezeit hinter dem letzten Arbeitsgang.
      final lastKey = ganttOpKey(item.id, item.operations.length - 1);
      final gap = _slackGap(item);
      if (gap != null) {
        hatches.add((row: 0, top: rowTops[lastKey]!, from: gap.$1, to: gap.$2, text: gap.$3));
      }
    }
    final selKey = _sel;
    final selOp = selKey == null ? null : _opOf(selKey);
    final selStart = selKey == null ? null : _pos[selKey];
    final selVerdict = selKey == null ? null : bars[selKey];
    return Container(
      key: const ValueKey('gantt-chart'),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Auswahl-Leiste
          Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: selOp == null || selStart == null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _finished
                          ? 'Fertig – unten findest du die Auswertung.'
                          : 'Tippe in einer Zeile auf den Tag, an dem der Arbeitsgang beginnt – die Länge kommt aus der Tabelle. '
                              'Balken antippen zum Verschieben (◀ ▶, Ziehen, Pfeiltasten).',
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: c.inkMuted),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${selOp.name} · ${_itemNameOf(selKey!)}',
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                            Text(
                              _marksFor(selKey) && selVerdict != null && selVerdict.status != BarStatus.ok
                                  ? _capitalize(selVerdict.text)
                                  : '${selOp.duration} ${selOp.duration == 1 ? 'Tag' : 'Tage'} · ${_span(selStart, selOp.duration)}'
                                      '${_marksFor(selKey) && selVerdict?.status == BarStatus.ok ? ' · stimmt' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: _marksFor(selKey) && selVerdict != null
                                    ? switch (selVerdict.status) {
                                        BarStatus.ok => c.good,
                                        BarStatus.follow => c.warn,
                                        _ => c.danger,
                                      }
                                    : c.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('gantt-left'),
                        tooltip: 'Einen Tag früher',
                        onPressed: _finished ? null : () => _move(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        key: const ValueKey('gantt-right'),
                        tooltip: 'Einen Tag später',
                        onPressed: _finished ? null : () => _move(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                      IconButton(
                        key: const ValueKey('gantt-remove'),
                        tooltip: 'Balken entfernen',
                        onPressed: _finished ? null : _remove,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _labelW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 18 + 26, child: Align(alignment: Alignment.bottomLeft, child: _dayHeaderLabel(c))),
                    ...labels,
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: cw * days,
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _markerRow(c, cw, lo, days),
                            _dayHeader(c, cw, lo, days),
                            ...rows,
                          ],
                        ),
                        // Liegezeiten (schraffiert)
                        for (final h in hatches)
                          Positioned(
                            left: (h.from - lo) * cw,
                            top: 18 + 26 + h.top + 9,
                            width: (h.to - h.from + 1) * cw,
                            height: _rowH - 18,
                            child: IgnorePointer(child: _Hatch(text: h.text)),
                          ),
                        // Start- und Liefertermin
                        Positioned(
                          left: (_task.start - lo) * cw,
                          top: 18,
                          bottom: 0,
                          width: 2,
                          child: IgnorePointer(child: Container(color: c.accent)),
                        ),
                        if (_ref.dueCell != null)
                          Positioned(
                            left: (_ref.dueCell! - lo + 1) * cw - 1,
                            top: 18,
                            bottom: 0,
                            width: 2,
                            child: IgnorePointer(child: CustomPaint(painter: _DashedLinePainter(c.danger))),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final (ii, item) in _task.items.indexed) _legend(c, item.name, palette[ii % palette.length]),
                _legendHatch(c),
                if (_revealed) _legendGhost(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _itemNameOf(String key) => _task.item(key.substring(0, key.lastIndexOf('#')))?.name ?? '';

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _span(int start, int duration) {
    final shift = _task.counting == GanttCounting.points ? 1 : 0;
    final end = start + duration - 1 + shift;
    return start == end ? 'Tag $start' : 'Tag $start–$end';
  }

  /// Liegezeit hinter dem Teil (eigene Balken bzw. nach "Lösung zeigen" die
  /// Lösung): (erster Tag, letzter Tag, Beschriftung) oder null.
  (int, int, String)? _slackGap(GanttItem item) {
    final dependents = _task.dependentsOf(item.id);
    final dueCell = _ref.dueCell;
    int? end;
    int? next;
    if (_revealed) {
      final r = _ref.items[item.id]!;
      end = r.last;
      next = dependents.isEmpty
          ? (dueCell == null ? null : dueCell + 1)
          : dependents.map((d) => _ref.items[d.id]!.first).reduce(math.min);
    } else {
      final own = GanttScheduler.ownAnswer(_task, _pos, GanttQuestion(itemId: item.id, ask: GanttAsk.end));
      if (own == null) return null;
      end = own - (_task.counting == GanttCounting.points ? 1 : 0);
      if (dependents.isEmpty) {
        next = dueCell == null ? null : dueCell + 1;
      } else {
        final firsts = [
          for (final d in dependents) GanttScheduler.ownAnswer(_task, _pos, GanttQuestion(itemId: d.id, ask: GanttAsk.start)),
        ];
        if (firsts.contains(null)) return null;
        next = firsts.whereType<int>().reduce(math.min);
      }
    }
    if (next == null || next - end - 1 <= 0) return null;
    final n = next - end - 1;
    return (end + 1, next - 1, _revealed ? 'Liegezeit $n T' : (n >= 3 ? 'Liegezeit' : ''));
  }

  Widget _headLabel(AppColors c, String name, Color color) => Container(
        height: _headH,
        color: c.surfaceAlt,
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Expanded(
              child: Text(name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: c.inkMuted)),
            ),
          ],
        ),
      );

  Widget _opLabel(AppColors c, String key, GanttOperation op, BarVerdict verdict) {
    final marks = _marksFor(key) && (_pos[key] != null || _checked || _revealed);
    return Container(
      height: _rowH,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: _sel == key ? c.accentSoft : null,
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5)), right: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(op.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          if (marks)
            _statusDot(c, verdict.status)
          else
            Text('${op.duration} T', style: TextStyle(fontSize: 11, color: c.inkMuted)),
        ],
      ),
    );
  }

  Widget _statusDot(AppColors c, BarStatus status) {
    final (icon, color) = switch (status) {
      BarStatus.ok => (Icons.check_circle, c.good),
      BarStatus.follow => (Icons.arrow_circle_right, c.warn),
      BarStatus.bad => (Icons.cancel, c.danger),
      BarStatus.missing => (Icons.remove_circle_outline, c.inkMuted),
    };
    return Icon(icon, size: 18, color: color);
  }

  Widget _dayHeaderLabel(AppColors c) => Container(
        height: 26,
        padding: const EdgeInsets.only(left: 14),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border), right: BorderSide(color: c.border))),
        child: Text('Tag', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.inkMuted)),
      );

  Widget _markerRow(AppColors c, double cw, int lo, int days) => SizedBox(
        height: 18,
        width: cw * days,
        child: Stack(
          children: [
            Positioned(
              left: (_task.start - lo) * cw + 4,
              top: 3,
              child: Text('Start', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accent)),
            ),
            if (_ref.dueCell != null)
              Positioned(
                left: math.max(0, (_ref.dueCell! - lo + 1) * cw - 74),
                top: 3,
                child: SizedBox(
                  width: 70,
                  child: Text('Liefertermin',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.danger)),
                ),
              ),
          ],
        ),
      );

  Widget _dayHeader(AppColors c, double cw, int lo, int days) => Container(
        height: 26,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: Row(
          children: [
            for (var d = lo; d < lo + days; d++)
              Container(
                width: cw,
                alignment: Alignment.center,
                color: d == _task.start ? c.accentSoft : (_ref.dueCell != null && d == _ref.dueCell ? c.dangerSoft : null),
                child: Text(
                  '$d',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: d == _task.start || d == _ref.dueCell ? FontWeight.w700 : FontWeight.w500,
                    color: d == _task.start ? c.accent : (d == _ref.dueCell ? c.danger : c.inkMuted),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _track(AppColors c, String key, GanttOperation op, double cw, int lo, int days, Color color, BarVerdict verdict) {
    final start = _pos[key];
    final refStart = _ref.opStarts[key]!;
    final marks = _marksFor(key) && start != null;
    final ringColor = switch (verdict.status) {
      BarStatus.ok => c.good,
      BarStatus.follow => c.warn,
      _ => c.danger,
    };
    final selected = _sel == key;
    return Container(
      height: _rowH,
      width: cw * days,
      decoration: BoxDecoration(
        color: selected ? c.accentSoft.withValues(alpha: 0.45) : null,
        border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
      ),
      child: Stack(
        children: [
          // Raster + Antippen = hier beginnen
          Positioned.fill(
            child: GestureDetector(
              key: ValueKey('gantt-track-$key'),
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _place(key, lo + (d.localPosition.dx / cw).floor()),
              child: CustomPaint(painter: _GridPainter(cw: cw, color: c.border.withValues(alpha: 0.45))),
            ),
          ),
          if (_revealed && verdict.status != BarStatus.ok)
            Positioned(
              left: (refStart - lo) * cw + 1,
              top: 6,
              width: op.duration * cw - 2,
              height: _rowH - 12,
              child: IgnorePointer(child: CustomPaint(painter: _DashedRectPainter(c.good))),
            ),
          if (start != null)
            Positioned(
              left: (start - lo) * cw + 1,
              top: 8,
              width: op.duration * cw - 2,
              height: _rowH - 16,
              child: GestureDetector(
                key: ValueKey('gantt-bar-$key'),
                onTap: () {
                  setState(() => _sel = key);
                  _focus.requestFocus();
                },
                onHorizontalDragStart: _finished
                    ? null
                    : (_) {
                        _dragDx = 0;
                        setState(() => _sel = key);
                      },
                onHorizontalDragUpdate: _finished
                    ? null
                    : (d) {
                        _dragDx += d.delta.dx;
                        final steps = (_dragDx / cw).truncate();
                        if (steps != 0) {
                          _dragDx -= steps * cw;
                          _move(steps);
                        }
                      },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      if (marks) BoxShadow(color: ringColor, spreadRadius: 2.5),
                      if (!marks && selected) BoxShadow(color: c.ink, spreadRadius: 2),
                    ],
                  ),
                  child: Text(
                    _span(start, op.duration).replaceFirst('Tag ', ''),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: ganttOnColor(color)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legend(AppColors c, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 16, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
        ],
      );

  Widget _legendHatch(AppColors c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 16, height: 10, child: _Hatch(text: '')),
          const SizedBox(width: 6),
          Text('Liegezeit', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
        ],
      );

  Widget _legendGhost(AppColors c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 16, height: 10, child: CustomPaint(painter: _DashedRectPainter(c.good))),
          const SizedBox(width: 6),
          Text('richtige Lage', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
        ],
      );

  // -- Antworten ------------------------------------------------------------

  Widget _answersCard(AppColors c) {
    final asks = [
      for (final a in GanttAsk.values)
        if (_task.questions.any((q) => q.ask == a)) a,
    ];
    final itemIds = [
      for (final i in _task.items)
        if (_task.questions.any((q) => q.itemId == i.id)) i.id,
    ];
    final verdicts = _answerVerdicts;
    final show = _checked || _revealed;
    return Container(
      key: const ValueKey('gantt-answers'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('DEINE ANTWORTEN',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.inkMuted)),
              ),
              if (_task.drawChart && asks.any((a) => a == GanttAsk.start || a == GanttAsk.end) && !_finished)
                Flexible(
                  flex: 2,
                  child: TextButton(
                    key: const ValueKey('gantt-fill'),
                    onPressed: _fillFromChart,
                    child: const Text('Start/Ende aus Diagramm', overflow: TextOverflow.ellipsis),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Table(
            columnWidths: {0: const FlexColumnWidth(1.3), for (var i = 1; i <= asks.length; i++) i: const FlexColumnWidth(1)},
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              TableRow(children: [
                const SizedBox.shrink(),
                for (final a in asks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(a == GanttAsk.start || a == GanttAsk.end ? '${a.label} (Tag)' : '${a.label} (Tage)',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                  ),
              ]),
              for (final id in itemIds)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, right: 6),
                    child: Text(_task.item(id)!.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  for (final a in asks) _answerCell(c, GanttQuestion(itemId: id, ask: a), verdicts, show),
                ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _answerCell(AppColors c, GanttQuestion q, Map<String, AnswerVerdict> verdicts, bool show) {
    final controller = _answers[q.key];
    if (controller == null) return const SizedBox.shrink();
    final v = verdicts[q.key]!;
    final visible = !widget.examMode && (show || (_live && v.status != AnswerStatus.empty));
    final (border, fill) = !visible
        ? (c.border, c.surfaceAlt)
        : switch (v.status) {
            AnswerStatus.ok => (c.good, c.goodSoft),
            AnswerStatus.follow => (c.warn, c.warnSoft),
            AnswerStatus.bad => (c.danger, c.dangerSoft),
            AnswerStatus.empty => (c.border, c.surfaceAlt),
          };
    final note = _revealed && v.status != AnswerStatus.ok
        ? 'richtig: ${v.expected ?? '–'}'
        : (visible && v.status == AnswerStatus.follow ? 'Folgefehler' : null);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Column(
        children: [
          TextField(
            key: ValueKey('gantt-answer-${q.key}'),
            controller: controller,
            enabled: !_finished,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              hintText: q.ask == GanttAsk.start || q.ask == GanttAsk.end ? 'Tag' : 'Tage',
              filled: true,
              fillColor: fill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border, width: 1.4)),
              disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border, width: 1.4)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.accent, width: 1.6)),
            ),
            onChanged: (_) => setState(_changed),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(note,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _revealed ? c.good : c.warn)),
            ),
        ],
      ),
    );
  }

  // -- Auswertung -------------------------------------------------------------

  Widget _tipBox(AppColors c) => Container(
        key: const ValueKey('gantt-tip'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, size: 18, color: c.accentOnSoft),
            const SizedBox(width: 8),
            Expanded(child: Text(_tip!, style: const TextStyle(fontSize: 13.5, height: 1.45))),
          ],
        ),
      );

  Widget _resultCard(AppColors c) {
    final bars = _bars;
    final verdicts = _answerVerdicts;
    final barsOk = bars.values.where((v) => v.status == BarStatus.ok).length;
    final answersOk = verdicts.values.where((v) => v.status == AnswerStatus.ok).length;
    final issues = <(BarStatus, String, String)>[];
    final missing = <String>[];
    if (_task.drawChart) {
      for (final item in _task.items) {
        for (var k = 0; k < item.operations.length; k++) {
          final v = bars[ganttOpKey(item.id, k)]!;
          if (v.status == BarStatus.ok) continue;
          if (v.status == BarStatus.missing) {
            missing.add('${item.name} · ${item.operations[k].name}');
          } else {
            issues.add((v.status, '${item.name} · ${item.operations[k].name}:', v.text));
          }
        }
      }
    }
    if (missing.isNotEmpty) issues.add((BarStatus.missing, 'Noch nicht eingeplant:', '${missing.join(', ')}.'));
    String name(AnswerVerdict v, String key) {
      final q = _task.questions.firstWhere((q) => q.key == key);
      return '${_task.item(q.itemId)?.name ?? q.itemId} · ${q.ask.label}';
    }

    final wrong = [for (final e in verdicts.entries) if (e.value.status == AnswerStatus.bad) name(e.value, e.key)];
    final follow = [for (final e in verdicts.entries) if (e.value.status == AnswerStatus.follow) name(e.value, e.key)];
    final empty = [for (final e in verdicts.entries) if (e.value.status == AnswerStatus.empty) name(e.value, e.key)];
    if (wrong.isNotEmpty) issues.add((BarStatus.bad, 'Antworten falsch:', '${wrong.join(', ')}.'));
    if (follow.isNotEmpty) issues.add((BarStatus.follow, 'Folgefehler:', '${follow.join(', ')} – passt zu deinem Diagramm.'));
    if (empty.isNotEmpty) issues.add((BarStatus.missing, 'Noch leer:', '${empty.join(', ')}.'));
    final allOk = _allCorrect;
    final title = allOk
        ? 'Alles richtig'
        : [
            if (_task.drawChart) '$barsOk von ${bars.length} Balken richtig',
            if (verdicts.isNotEmpty) '$answersOk von ${verdicts.length} Antworten richtig',
          ].join(' · ');
    return Container(
      key: const ValueKey('gantt-result'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: allOk ? c.goodSoft : c.surface,
        border: allOk ? null : Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: allOk ? c.good : c.ink)),
          if (!allOk && !_revealed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Korrigiere die markierten Stellen und prüf noch einmal.',
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ),
          if (_ref.problems.isNotEmpty)
            for (final p in _ref.problems)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(p, style: TextStyle(fontSize: 12.5, color: c.danger)),
              ),
          if (!allOk)
            for (final (status, where, text) in issues)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statusDot(c, status),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '$where ', style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: text),
                      ])),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _howCard(AppColors c) {
    final lines = GanttScheduler.explain(_task, _ref);
    return Container(
      key: const ValueKey('gantt-how'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SO RECHNET MAN',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.inkMuted)),
          for (final (i, line) in lines.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: c.accentSoft,
                    child: Text('${i + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(line, style: const TextStyle(fontSize: 13.5, height: 1.45))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buttons(AppColors c) {
    if (widget.examMode) {
      return FilledButton(
        key: const ValueKey('gantt-submit'),
        onPressed: _check,
        child: const Text('Antwort abgeben'),
      );
    }
    if (_finished) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_solved)
            Text(
              _attempts <= 1 && _tips == 0
                  ? 'Auf Anhieb richtig – zählt als „Gut“.'
                  : 'Richtig – mit ${_tips > 0 ? 'Tipp' : 'zweitem Anlauf'}, zählt als „Schwer“.',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            )
          else
            Text('Lösung angesehen – zählt als „Nochmal“.', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('gantt-variant'),
            onPressed: _practiceVariant,
            icon: const Icon(Icons.casino_outlined, size: 18),
            label: const Text('Mit anderen Zahlen üben'),
          ),
          const SizedBox(height: 8),
          FilledButton(key: const ValueKey('gantt-next'), onPressed: _next, child: const Text('Weiter')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('gantt-hint'),
                onPressed: _hint,
                icon: const Icon(Icons.lightbulb_outline, size: 18),
                label: const Text('Tipp'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const ValueKey('gantt-check'),
                onPressed: _check,
                child: Text(_checked ? 'Erneut prüfen' : 'Prüfen'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(key: const ValueKey('gantt-reveal'), onPressed: _reveal, child: const Text('Lösung zeigen')),
            TextButton(key: const ValueKey('gantt-reset'), onPressed: _reset, child: const Text('Zurücksetzen')),
            if (widget.onSkip != null)
              TextButton(
                key: const ValueKey('question-skip'),
                onPressed: () {
                  if (_submitted) return;
                  _submitted = true;
                  widget.onSkip!();
                },
                child: const Text('Überspringen'),
              ),
            if (widget.canGiveUp)
              TextButton(key: const ValueKey('question-give-up'), onPressed: _reveal, child: const Text('Auflösen')),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('$_placed von $_opCount Arbeitsgängen eingeplant',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
        ),
      ],
    );
  }
}

class _Hatch extends StatelessWidget {
  const _Hatch({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      painter: _HatchPainter(c.inkMuted.withValues(alpha: 0.45), c.inkMuted),
      child: Center(
        child: text.isEmpty
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: c.surface,
                child: Text(text, maxLines: 1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.ink)),
              ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter(this.line, this.border);

  final Color line;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.save();
    canvas.clipRRect(r);
    final p = Paint()
      ..color = line
      ..strokeWidth = 1.5;
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
    _dashRect(canvas, rect, border, 1);
  }

  @override
  bool shouldRepaint(covariant _HatchPainter old) => old.line != line || old.border != border;
}

void _dashRect(Canvas canvas, Rect rect, Color color, double width) {
  final p = Paint()
    ..color = color
    ..strokeWidth = width
    ..style = PaintingStyle.stroke;
  void dashLine(Offset a, Offset b) {
    final total = (b - a).distance;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += 6) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + 3.5, total), p);
    }
  }

  dashLine(rect.topLeft, rect.topRight);
  dashLine(rect.topRight, rect.bottomRight);
  dashLine(rect.bottomRight, rect.bottomLeft);
  dashLine(rect.bottomLeft, rect.topLeft);
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => _dashRect(canvas, Offset.zero & size, color, 2);

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) => old.color != color;
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = size.width;
    for (var y = 0.0; y < size.height; y += 7) {
      canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, math.min(y + 4, size.height)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.cw, required this.color});

  final double cw;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = cw; x < size.width; x += cw) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.cw != cw || old.color != color;
}
