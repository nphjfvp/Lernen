import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/gantt_task.dart';
import '../../services/gantt_scheduler.dart';
import '../../theme/app_colors.dart';
import 'gantt_task_view.dart';

/// Musterlösung einer Terminierungs-Aufgabe, von der App berechnet: kleines
/// Gantt-Diagramm (mit Liegezeiten bzw. Puffern), Termine je Teil und was am
/// Plan nicht aufgeht.
class GanttSolutionPreview extends StatelessWidget {
  const GanttSolutionPreview({super.key, required this.task});

  final GanttTask task;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final plan = GanttScheduler.plan(task);
    final palette = ganttPalette(Theme.of(context).brightness);
    final shift = task.counting == GanttCounting.points ? 1 : 0;
    final forward = plan.direction == GanttDirection.forward;
    return Container(
      key: const ValueKey('gantt-preview'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_outlined, size: 18, color: c.good),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Musterlösung – von der App berechnet',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.good)),
              ),
            ],
          ),
          for (final p in plan.problems)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(p, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.danger)),
            ),
          const SizedBox(height: 10),
          SizedBox(
            height: 18.0 * task.items.fold(0, (n, i) => n + i.operations.length) + 18,
            child: CustomPaint(
              painter: _MiniGanttPainter(
                task: task,
                plan: plan,
                palette: palette,
                grid: c.border,
                text: c.inkMuted,
                start: c.accent,
                due: c.danger,
                hatch: c.inkMuted.withValues(alpha: 0.45),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1.3)},
            children: [
              TableRow(children: [
                _cell(c, 'Teil', head: true),
                _cell(c, 'Start', head: true, right: true),
                _cell(c, 'Ende', head: true, right: true),
                _cell(c, forward ? 'Liegezeit' : 'Puffer', head: true, right: true),
              ]),
              for (final item in task.items)
                TableRow(children: [
                  _cell(c, item.name),
                  _cell(c, '${plan.items[item.id]!.first}', right: true),
                  _cell(c, '${plan.items[item.id]!.last + shift}', right: true),
                  _cell(
                    c,
                    () {
                      final r = plan.items[item.id]!;
                      final v = forward ? r.slack : r.buffer;
                      return v == null ? '–' : '$v ${v == 1 ? 'Tag' : 'Tage'}';
                    }(),
                    right: true,
                  ),
                ]),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Die KI liest nur Struktur, Tabelle und Fragen ab – die Lösung rechnet die App. '
              'Ändere oben einen Wert, und sie rechnet sofort neu.',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(AppColors c, String text, {bool head = false, bool right = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          text,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: head ? FontWeight.w600 : FontWeight.w500,
            color: head ? c.inkMuted : c.ink,
          ),
        ),
      );
}

class _MiniGanttPainter extends CustomPainter {
  _MiniGanttPainter({
    required this.task,
    required this.plan,
    required this.palette,
    required this.grid,
    required this.text,
    required this.start,
    required this.due,
    required this.hatch,
  });

  final GanttTask task;
  final GanttPlan plan;
  final List<Color> palette;
  final Color grid;
  final Color text;
  final Color start;
  final Color due;
  final Color hatch;

  @override
  void paint(Canvas canvas, Size size) {
    const labelW = 86.0, rowH = 18.0, axisH = 18.0;
    final (lo0, hi0) = plan.span;
    final lo = math.min(lo0, task.start);
    final hi = math.max(hi0, plan.dueCell ?? hi0) + 1;
    final days = hi - lo + 1;
    final cw = (size.width - labelW) / days;
    double x(int day) => labelW + (day - lo) * cw;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.6;
    for (var d = lo; d <= hi + 1; d++) {
      canvas.drawLine(Offset(x(d), axisH), Offset(x(d), size.height), gridPaint);
    }
    for (final n in [for (var d = lo; d <= hi; d++) if (d == lo || d % 5 == 0) d]) {
      _label(canvas, '$n', Offset(x(n) + cw / 2, 2), center: true, size: 9.5);
    }
    var row = 0;
    for (final (ii, item) in task.items.indexed) {
      final color = palette[ii % palette.length];
      for (var k = 0; k < item.operations.length; k++) {
        final top = axisH + row * rowH;
        _label(canvas, item.operations[k].name, Offset(0, top + 3), maxWidth: labelW - 4, size: 10);
        final s = plan.opStarts[ganttOpKey(item.id, k)]!;
        final rect = Rect.fromLTWH(x(s), top + 4, item.operations[k].duration * cw - 1, rowH - 8);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), Paint()..color = color);
        if (k == item.operations.length - 1 && plan.direction == GanttDirection.forward) {
          final slack = plan.items[item.id]!.slack ?? 0;
          if (slack > 0) _hatch(canvas, Rect.fromLTWH(x(s + item.operations[k].duration), top + 4, slack * cw, rowH - 8));
        }
        if (k == 0 && plan.direction == GanttDirection.backward && item.needs.isEmpty) {
          final buffer = s - task.start;
          if (buffer > 0) _hatch(canvas, Rect.fromLTWH(x(task.start), top + 4, buffer * cw, rowH - 8));
        }
        row++;
      }
    }
    canvas.drawLine(Offset(x(task.start), axisH), Offset(x(task.start), size.height), Paint()
      ..color = start
      ..strokeWidth = 1.5);
    final dueCell = plan.dueCell;
    if (dueCell != null) {
      final dx = x(dueCell + 1);
      for (var y = axisH; y < size.height; y += 6) {
        canvas.drawLine(Offset(dx, y), Offset(dx, math.min(y + 3, size.height)), Paint()
          ..color = due
          ..strokeWidth = 1.5);
      }
    }
  }

  void _hatch(Canvas canvas, Rect rect) {
    canvas.save();
    canvas.clipRect(rect);
    final p = Paint()
      ..color = hatch
      ..strokeWidth = 1;
    for (var dx = rect.left - rect.height; dx < rect.right; dx += 4) {
      canvas.drawLine(Offset(dx, rect.bottom), Offset(dx + rect.height, rect.top), p);
    }
    canvas.restore();
  }

  void _label(Canvas canvas, String s, Offset at, {bool center = false, double maxWidth = 60, double size = 10}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: text)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, center ? at - Offset(tp.width / 2, 0) : at);
  }

  @override
  bool shouldRepaint(covariant _MiniGanttPainter old) => true;
}

/// Terminierungs-Aufgabe bearbeiten: Verfahren, Zählweise, Termine, Teile mit
/// Arbeitsgängen (Dauern per −/+), Abhängigkeiten und gefragte Antworten. Die
/// Musterlösung rechnet bei jeder Änderung neu (GanttSolutionPreview).
class GanttTaskEditor extends StatefulWidget {
  const GanttTaskEditor({super.key, required this.task, required this.onChanged});

  final GanttTask task;
  final ValueChanged<GanttTask> onChanged;

  @override
  State<GanttTaskEditor> createState() => _GanttTaskEditorState();
}

class _GanttTaskEditorState extends State<GanttTaskEditor> {
  late GanttTask _task = widget.task;
  final Map<String, TextEditingController> _names = {};

  @override
  void dispose() {
    for (final c in _names.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _nameController(String key, String initial) =>
      _names.putIfAbsent(key, () => TextEditingController(text: initial));

  void _set(GanttTask task) {
    setState(() => _task = task);
    widget.onChanged(task);
  }

  void _setItem(int index, GanttItem item) => _set(_task.copyWith(items: [..._task.items]..[index] = item));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final palette = ganttPalette(Theme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('VERFAHREN', style: _caption(c)),
        const SizedBox(height: 6),
        SegmentedButton<GanttDirection>(
          key: const ValueKey('gantt-edit-direction'),
          segments: const [
            ButtonSegment(value: GanttDirection.forward, label: Text('Vorwärts')),
            ButtonSegment(value: GanttDirection.backward, label: Text('Rückwärts')),
          ],
          selected: {_task.direction},
          showSelectedIcon: false,
          onSelectionChanged: (s) => _set(_task.copyWith(
            direction: s.first,
            // Rückwärts braucht einen Liefertermin.
            due: s.first == GanttDirection.backward && _task.due == null
                ? GanttScheduler.plan(_task).items.values.map((r) => r.last).fold(_task.start, math.max) + 1
                : null,
          )),
        ),
        const SizedBox(height: 6),
        Text(
          _task.direction == GanttDirection.forward
              ? 'Alle Teile starten am Starttermin und laufen so früh wie möglich. Wer früher fertig ist, liegt bis zur Weiterverarbeitung – das ist die Liegezeit.'
              : 'Vom Liefertermin aus rückwärts: alles so spät wie möglich. Liegezeiten entfallen, dafür gibt es Puffer bis zum Starttermin.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
        ),
        if (_task.hasUncertain)
          Container(
            key: const ValueKey('gantt-edit-uncertain'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.help_outline, color: c.warn, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Manche Werte waren schlecht lesbar (markiert) – bitte mit dem Blatt vergleichen.',
                      style: TextStyle(fontSize: 12.5, color: c.ink)),
                ),
                TextButton(
                  key: const ValueKey('gantt-edit-confirm'),
                  onPressed: () => _set(_task.confirmed()),
                  child: const Text('Stimmt so'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text('TEILE UND ARBEITSGÄNGE (DAUER IN TAGEN)', style: _caption(c)),
        for (final (i, item) in _task.items.indexed) _itemCard(c, i, item, palette[i % palette.length]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('gantt-edit-add-item'),
            onPressed: () {
              var n = _task.items.length + 1;
              while (_task.item('t$n') != null) {
                n++;
              }
              _set(_task.copyWith(items: [
                ..._task.items,
                GanttItem(id: 't$n', name: 'Teil $n', operations: const [GanttOperation(name: 'Arbeitsgang', duration: 1)]),
              ]));
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Teil hinzufügen'),
          ),
        ),
        const SizedBox(height: 10),
        Text('TERMINE', style: _caption(c)),
        _stepper(c, 'Starttermin', 'Tag ${_task.start}', () => _set(_task.copyWith(start: _task.start - 1)),
            () => _set(_task.copyWith(start: _task.start + 1)),
            key: 'start'),
        Row(
          children: [
            Expanded(
              child: _stepper(
                c,
                'Liefertermin',
                _task.due == null ? 'keiner' : 'Tag ${_task.due}',
                _task.due == null ? null : () => _set(_task.copyWith(due: _task.due! - 1)),
                () => _set(_task.copyWith(due: (_task.due ?? _task.start) + 1)),
                key: 'due',
              ),
            ),
            if (_task.due != null && _task.direction == GanttDirection.forward)
              IconButton(
                tooltip: 'Ohne Liefertermin',
                onPressed: () => _set(_task.copyWith(clearDue: true)),
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Zählweise wie im Skript', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
        RadioGroup<GanttCounting>(
          groupValue: _task.counting,
          onChanged: (v) => _set(_task.copyWith(counting: v)),
          child: Column(
            children: [
              for (final counting in GanttCounting.values)
                RadioListTile<GanttCounting>(
                  key: ValueKey('gantt-edit-counting-${counting.name}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: counting,
                  title: Text(counting.label),
                  subtitle: Text(counting == GanttCounting.inclusive
                      ? 'Ende = Start + Dauer − 1 (2 Tage ab Tag 1 enden an Tag 2)'
                      : 'Ende = Start + Dauer (2 Tage ab Tag 1 enden zum Zeitpunkt 3)'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text('GESUCHT – PRÜFT DIE APP', style: _caption(c)),
        const SizedBox(height: 6),
        _questions(c),
        SwitchListTile(
          key: const ValueKey('gantt-edit-draw'),
          contentPadding: EdgeInsets.zero,
          value: _task.drawChart,
          onChanged: (v) => _set(_task.copyWith(drawChart: v)),
          title: const Text('Gantt-Diagramm mitzeichnen'),
          subtitle: const Text('Jeder Balken wird geprüft, Folgefehler werden erkannt.'),
        ),
        const SizedBox(height: 10),
        if (_task.isValid) GanttSolutionPreview(task: _task),
      ],
    );
  }

  TextStyle _caption(AppColors c) => TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.inkMuted);

  Widget _stepper(AppColors c, String label, String value, VoidCallback? dec, VoidCallback? inc, {required String key}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
            IconButton(key: ValueKey('gantt-edit-$key-dec'), onPressed: dec, icon: const Icon(Icons.remove, size: 18)),
            SizedBox(width: 64, child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(key: ValueKey('gantt-edit-$key-inc'), onPressed: inc, icon: const Icon(Icons.add, size: 18)),
          ],
        ),
      );

  Widget _itemCard(AppColors c, int i, GanttItem item, Color color) {
    final others = [for (final o in _task.items) if (o.id != item.id) o];
    return Container(
      key: ValueKey('gantt-edit-item-${item.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _nameController('item-${item.id}', item.name),
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'Name'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  onChanged: (v) => _setItem(i, item.copyWith(name: v.trim().isEmpty ? item.name : v.trim())),
                ),
              ),
              IconButton(
                tooltip: 'Teil entfernen',
                onPressed: _task.items.length <= 1
                    ? null
                    : () {
                        final rest = [
                          for (final o in _task.items)
                            if (o.id != item.id) o.copyWith(needs: [for (final n in o.needs) if (n != item.id) n]),
                        ];
                        _set(_task.copyWith(
                          items: rest,
                          questions: [for (final q in _task.questions) if (q.itemId != item.id) q],
                        ));
                      },
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          if (others.isNotEmpty)
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('braucht:', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                for (final o in others)
                  FilterChip(
                    label: Text(o.name, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    selected: item.needs.contains(o.id),
                    onSelected: (v) {
                      final needs = v ? [...item.needs, o.id] : [for (final n in item.needs) if (n != o.id) n];
                      final candidate = _task.copyWith(items: [..._task.items]..[i] = item.copyWith(needs: needs));
                      if (candidate.isValid) _set(candidate);
                    },
                  ),
              ],
            ),
          for (final (k, op) in item.operations.indexed)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController('op-${item.id}-$k', op.name),
                    decoration: const InputDecoration(isDense: true, hintText: 'Arbeitsgang'),
                    style: const TextStyle(fontSize: 13.5),
                    onChanged: (v) => _setItem(i, item.copyWith(operations: [...item.operations]..[k] = op.copyWith(name: v.trim().isEmpty ? op.name : v.trim()))),
                  ),
                ),
                if (op.uncertain)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text('unsicher', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.warn)),
                  ),
                IconButton(
                  key: ValueKey('gantt-edit-dec-${item.id}-$k'),
                  tooltip: 'Einen Tag kürzer',
                  onPressed: op.duration <= 1
                      ? null
                      : () => _setItem(i, item.copyWith(operations: [...item.operations]..[k] = op.copyWith(duration: op.duration - 1, uncertain: false))),
                  icon: const Icon(Icons.remove, size: 18),
                ),
                SizedBox(
                  width: 52,
                  child: Text('${op.duration} ${op.duration == 1 ? 'Tag' : 'Tage'}',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  key: ValueKey('gantt-edit-inc-${item.id}-$k'),
                  tooltip: 'Einen Tag länger',
                  onPressed: () => _setItem(i, item.copyWith(operations: [...item.operations]..[k] = op.copyWith(duration: op.duration + 1, uncertain: false))),
                  icon: const Icon(Icons.add, size: 18),
                ),
                IconButton(
                  tooltip: 'Arbeitsgang entfernen',
                  onPressed: item.operations.length <= 1
                      ? null
                      : () {
                          _names.remove('op-${item.id}-$k')?.dispose();
                          // Folgende Namensfelder neu aufbauen (Index verschiebt sich).
                          for (var j = k + 1; j < item.operations.length; j++) {
                            _names.remove('op-${item.id}-$j')?.dispose();
                          }
                          _setItem(i, item.copyWith(operations: [...item.operations]..removeAt(k)));
                        },
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _setItem(i, item.copyWith(operations: [...item.operations, const GanttOperation(name: 'Arbeitsgang', duration: 1)])),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Arbeitsgang'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _questions(AppColors c) {
    final asks = _task.direction == GanttDirection.forward
        ? const [GanttAsk.start, GanttAsk.end, GanttAsk.slack, GanttAsk.buffer]
        : const [GanttAsk.start, GanttAsk.end, GanttAsk.buffer, GanttAsk.slack];
    return Table(
      columnWidths: {0: const FlexColumnWidth(2), for (var i = 1; i <= asks.length; i++) i: const FlexColumnWidth(1)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          const SizedBox.shrink(),
          for (final a in asks)
            Text(a.label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
        ]),
        for (final item in _task.items)
          TableRow(children: [
            Text(item.name, style: const TextStyle(fontSize: 13)),
            for (final a in asks)
              Checkbox(
                key: ValueKey('gantt-edit-q-${item.id}-${a.name}'),
                value: _task.questions.contains(GanttQuestion(itemId: item.id, ask: a)),
                onChanged: (v) {
                  final q = GanttQuestion(itemId: item.id, ask: a);
                  final questions = v == true ? [..._task.questions, q] : [for (final x in _task.questions) if (x != q) x];
                  _set(_task.copyWith(questions: questions));
                },
              ),
          ]),
      ],
    );
  }
}
