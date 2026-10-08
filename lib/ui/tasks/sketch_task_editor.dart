import 'package:flutter/material.dart';

import '../../models/sketch_task.dart';
import '../../services/sketch_checker.dart';
import '../../theme/app_colors.dart';
import 'sketch_canvas.dart';

/// Vorschau: Achsen mit Musterkurve und Markierungen, dazu, ob die
/// Musterkurve ihre eigenen Merkmale erfüllt.
class SketchTaskPreview extends StatelessWidget {
  const SketchTaskPreview({super.key, required this.task, this.height = 220});

  final SketchTask task;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final problems = SketchChecker.selfCheck(task);
    return Column(
      key: const ValueKey('sketch-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SketchCanvas(
          task: task,
          height: height,
          showReference: true,
          referenceMarks: SketchChecker.referenceMarks(task),
        ),
        const SizedBox(height: 6),
        for (final f in task.features)
          Text(
            '• ${f.kind == SketchFeatureKind.mark ? '${f.label}: ${f.anchor.label}' : f.kind.label}'
            '${f.text.isEmpty ? '' : ' – ${f.text}'}',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
          ),
        for (final p in problems)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('⚠ $p', style: TextStyle(fontSize: 12.5, color: c.warn)),
          ),
      ],
    );
  }
}

/// Diagramm-Skizze bearbeiten: Achsen, Musterkurve (als Punkte), Merkmale.
class SketchTaskEditor extends StatefulWidget {
  const SketchTaskEditor({super.key, required this.task, required this.onChanged});

  final SketchTask task;
  final ValueChanged<SketchTask> onChanged;

  @override
  State<SketchTaskEditor> createState() => _SketchTaskEditorState();
}

class _SketchTaskEditorState extends State<SketchTaskEditor> {
  late final _reference = TextEditingController(text: SketchTask.referenceText(widget.task.reference));
  String? _referenceError;

  /// Neu aufgebaute Merkmal-Zeilen nach Hinzufügen/Entfernen.
  int _revision = 0;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  SketchTask get _task => widget.task;
  void _emit(SketchTask t) => widget.onChanged(t);

  void _setFeature(int i, SketchFeature f) => _emit(_task.copyWith(features: [..._task.features]..[i] = f));

  static double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  static String _fmt(double? v) {
    if (v == null) return '';
    if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
    return '$v';
  }

  Widget _field(String key, String label, String initial, ValueChanged<String> onChanged, {double width = 90}) =>
      SizedBox(
        width: width,
        child: TextFormField(
          key: ValueKey(key),
          initialValue: initial,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
          onChanged: onChanged,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final task = _task;
    final head = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (task.uncertain)
          Container(
            key: const ValueKey('sketch-edit-uncertain'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Achsen oder Merkmale waren unklar – bitte mit dem Blatt vergleichen.',
                    style: TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
                TextButton(
                  key: const ValueKey('sketch-edit-confirm'),
                  onPressed: () => _emit(task.confirmed()),
                  child: const Text('Stimmt'),
                ),
              ],
            ),
          ),
        Text('Achsen', style: head),
        const SizedBox(height: 8),
        for (final (name, axis) in [('x', task.xAxis), ('y', task.yAxis)]) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _field('sketch-edit-$name-label', '$name-Achse', axis.label, width: 180, (v) {
                final a = axis.copyWith(label: v.trim());
                _emit(name == 'x' ? task.copyWith(xAxis: a) : task.copyWith(yAxis: a));
              }),
              _field('sketch-edit-$name-min', 'von', _fmt(axis.min), (v) {
                final n = _num(v);
                if (n == null) return;
                final a = axis.copyWith(min: n);
                _emit(name == 'x' ? task.copyWith(xAxis: a) : task.copyWith(yAxis: a));
              }),
              _field('sketch-edit-$name-max', 'bis', _fmt(axis.max), (v) {
                final n = _num(v);
                if (n == null) return;
                final a = axis.copyWith(max: n);
                _emit(name == 'x' ? task.copyWith(xAxis: a) : task.copyWith(yAxis: a));
              }),
            ],
          ),
          const SizedBox(height: 8),
        ],
        SwitchListTile(
          key: const ValueKey('sketch-edit-numbers'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Zahlen an den Achsen'),
          subtitle: const Text('Aus bei rein qualitativen Skizzen'),
          value: task.xAxis.showNumbers || task.yAxis.showNumbers,
          onChanged: (v) => _emit(
            task.copyWith(
              xAxis: task.xAxis.copyWith(showNumbers: v),
              yAxis: task.yAxis.copyWith(showNumbers: v),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Musterkurve', style: head),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('sketch-edit-reference'),
          controller: _reference,
          minLines: 3,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            helperText: 'Ein Punkt je Zeile „x; y“ – Leerzeile beginnt einen neuen Strich (z.B. nach einem Sprung).',
            helperMaxLines: 2,
            errorText: _referenceError,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (text) {
            final parsed = SketchTask.parseReference(text);
            setState(() => _referenceError = parsed.error);
            if (parsed.error == null) _emit(task.copyWith(reference: parsed.strokes));
          },
        ),
        const SizedBox(height: 12),
        Text('Merkmale (darauf prüft die App)', style: head),
        const SizedBox(height: 6),
        for (final (i, f) in task.features.indexed) _featureRow(c, i, f),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('sketch-edit-add'),
            onPressed: () {
              setState(() => _revision++);
              _emit(
                task.copyWith(
                  features: [
                    ...task.features,
                    SketchFeature(kind: SketchFeatureKind.rising, x: task.xAxis.min, x2: task.xAxis.max),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Merkmal hinzufügen'),
          ),
        ),
        const SizedBox(height: 8),
        if (task.isUsable) SketchTaskPreview(task: task),
      ],
    );
  }

  Widget _featureRow(AppColors c, int i, SketchFeature f) {
    final k = 'sketch-edit-$i-$_revision';
    final needsX =
        f.kind != SketchFeatureKind.approaches &&
        !(f.kind == SketchFeatureKind.mark &&
            !{SketchAnchor.point, SketchAnchor.x, SketchAnchor.curve}.contains(f.anchor));
    final needsY =
        f.kind == SketchFeatureKind.approaches ||
        f.kind == SketchFeatureKind.min ||
        f.kind == SketchFeatureKind.max ||
        (f.kind == SketchFeatureKind.mark && f.anchor == SketchAnchor.point);
    return Container(
      key: ValueKey('sketch-edit-feature-$i'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: f.isValid ? null : Border.all(color: c.danger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<SketchFeatureKind>(
                  key: ValueKey('$k-kind'),
                  isExpanded: true,
                  value: f.kind,
                  items: [
                    for (final kind in SketchFeatureKind.values) DropdownMenuItem(value: kind, child: Text(kind.label)),
                  ],
                  onChanged: (kind) {
                    if (kind == null) return;
                    setState(() => _revision++);
                    _setFeature(i, f.copyWith(kind: kind));
                  },
                ),
              ),
              IconButton(
                key: ValueKey('sketch-edit-remove-$i'),
                tooltip: 'Merkmal entfernen',
                icon: Icon(Icons.close, size: 18, color: c.inkMuted),
                onPressed: () {
                  setState(() => _revision++);
                  _emit(_task.copyWith(features: [..._task.features]..removeAt(i)));
                },
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (f.kind == SketchFeatureKind.mark) ...[
                _field('$k-label', 'Name', f.label, (v) => _setFeature(i, f.copyWith(label: v.trim()))),
                DropdownButton<SketchAnchor>(
                  key: ValueKey('$k-anchor'),
                  value: f.anchor,
                  items: [for (final a in SketchAnchor.values) DropdownMenuItem(value: a, child: Text(a.label))],
                  onChanged: (a) {
                    if (a == null) return;
                    setState(() => _revision++);
                    _setFeature(i, f.copyWith(anchor: a));
                  },
                ),
              ],
              if (needsX)
                _field(
                  '$k-x',
                  f.kind.isRange ? 'von x' : 'bei x',
                  _fmt(f.x),
                  (v) => _setFeature(i, f.copyWith(x: _num(v), clearX: _num(v) == null)),
                ),
              if (f.kind.isRange)
                _field(
                  '$k-x2',
                  'bis x',
                  _fmt(f.x2),
                  (v) => _setFeature(i, f.copyWith(x2: _num(v), clearX2: _num(v) == null)),
                ),
              if (needsY)
                _field(
                  '$k-y',
                  f.kind == SketchFeatureKind.min ? 'unter y' : (f.kind == SketchFeatureKind.max ? 'über y' : 'y'),
                  _fmt(f.y),
                  (v) => _setFeature(i, f.copyWith(y: _num(v), clearY: _num(v) == null)),
                ),
              if (!f.kind.isRange)
                _field('$k-tol', 'Toleranz %', _fmt((f.tol * 100).roundToDouble()), (v) {
                  final n = _num(v);
                  if (n != null && n > 0) _setFeature(i, f.copyWith(tol: (n / 100).clamp(0.01, 0.5)));
                }),
            ],
          ),
          const SizedBox(height: 8),
          _field(
            '$k-text',
            'Rückmeldung / Bedeutung',
            f.text,
            width: double.infinity,
            (v) => _setFeature(i, f.copyWith(text: v.trim())),
          ),
        ],
      ),
    );
  }
}
