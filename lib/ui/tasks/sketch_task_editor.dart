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
            '• ${f.kind == SketchFeatureKind.mark ? '${f.label}: ${f.anchor.label}' : f.kind.isComparison ? '„${task.resolve(f.curve)}“ ${f.kind.label} „${task.resolve(f.other)}“' : '${task.isMulti ? '${task.resolve(f.curve)}: ' : ''}${f.kind.label}'}'
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
  /// Musterkurve je Kurve als Text ("x; y" je Zeile).
  late final List<TextEditingController> _references = [
    for (final c in widget.task.curves) TextEditingController(text: SketchTask.referenceText(c.reference)),
  ];
  final Map<int, String> _referenceErrors = {};

  /// Neu aufgebaute Merkmal-Zeilen nach Hinzufügen/Entfernen.
  int _revision = 0;

  @override
  void dispose() {
    for (final r in _references) {
      r.dispose();
    }
    super.dispose();
  }

  void _setCurve(int i, SketchNamedCurve curve) => _emit(_task.copyWith(curves: [..._task.curves]..[i] = curve));

  /// Kurve umbenennen – Merkmale, die sie meinen, ziehen mit.
  void _renameCurve(int i, String name) {
    final old = _task.curves[i].name;
    _emit(
      _task.copyWith(
        curves: [..._task.curves]..[i] = _task.curves[i].copyWith(name: name),
        features: [
          for (final f in _task.features)
            f.copyWith(curve: f.curve == old ? name : f.curve, other: f.other == old ? name : f.other),
        ],
      ),
    );
  }

  void _addCurve() {
    final t = _task;
    final first = t.curves.first.name.isEmpty ? t.curves.first.copyWith(name: 'Kurve 1') : t.curves.first;
    final curves = [first, ...t.curves.skip(1)];
    var n = curves.length + 1;
    while (curves.any((c) => c.name == 'Kurve $n')) {
      n++;
    }
    setState(() {
      _references.add(TextEditingController(text: SketchTask.referenceText(first.reference)));
      _revision++;
    });
    _emit(
      t.copyWith(
        curves: [...curves, SketchNamedCurve(name: 'Kurve $n', reference: first.reference)],
        features: [for (final f in t.features) f.curve.isEmpty && t.curves.first.name.isEmpty ? f.copyWith(curve: first.name) : f],
      ),
    );
  }

  void _removeCurve(int i) {
    final name = _task.curves[i].name;
    setState(() {
      _references.removeAt(i).dispose();
      _referenceErrors.clear();
      _revision++;
    });
    _emit(
      _task.copyWith(
        curves: [..._task.curves]..removeAt(i),
        features: [for (final f in _task.features) if (f.curve != name && f.other != name) f],
      ),
    );
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
        Text(task.isMulti ? 'Musterkurven' : 'Musterkurve', style: head),
        const SizedBox(height: 6),
        for (final (i, curve) in task.curves.indexed) ...[
          if (task.isMulti)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _field(
                      'sketch-edit-curve-$i-name-$_revision',
                      'Name der Kurve ${i + 1}',
                      curve.name,
                      width: double.infinity,
                      (v) => _renameCurve(i, v.trim()),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('sketch-edit-curve-$i-remove'),
                    tooltip: 'Kurve entfernen',
                    icon: Icon(Icons.close, size: 18, color: c.inkMuted),
                    onPressed: () => _removeCurve(i),
                  ),
                ],
              ),
            ),
          TextField(
            key: ValueKey(i == 0 ? 'sketch-edit-reference' : 'sketch-edit-reference-$i'),
            controller: _references[i],
            minLines: 3,
            maxLines: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              helperText: i == 0
                  ? 'Ein Punkt je Zeile „x; y“ – Leerzeile beginnt einen neuen Strich (z.B. nach einem Sprung).'
                  : null,
              helperMaxLines: 2,
              errorText: _referenceErrors[i],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (text) {
              final parsed = SketchTask.parseReference(text);
              setState(() {
                if (parsed.error == null) {
                  _referenceErrors.remove(i);
                } else {
                  _referenceErrors[i] = parsed.error!;
                }
              });
              if (parsed.error == null) _setCurve(i, _task.curves[i].copyWith(reference: parsed.strokes));
            },
          ),
          const SizedBox(height: 10),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('sketch-edit-add-curve'),
            onPressed: _addCurve,
            icon: const Icon(Icons.stacked_line_chart, size: 18),
            label: const Text('Weitere Kurve im selben Diagramm'),
          ),
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
    final task = _task;
    // Bereich von–bis (bei Haltepunkt und Vergleichen optional).
    final range = f.kind.isRange || f.kind == SketchFeatureKind.plateau || f.kind.isComparison;
    final needsX =
        f.kind != SketchFeatureKind.approaches &&
        !(f.kind == SketchFeatureKind.mark &&
            !{SketchAnchor.point, SketchAnchor.x, SketchAnchor.curve}.contains(f.anchor));
    final needsY =
        f.kind == SketchFeatureKind.approaches ||
        f.kind == SketchFeatureKind.min ||
        f.kind == SketchFeatureKind.max ||
        f.kind == SketchFeatureKind.plateau ||
        f.kind == SketchFeatureKind.kink ||
        (f.kind == SketchFeatureKind.mark && f.anchor == SketchAnchor.point);
    String curveOf(String name) => task.resolve(name);
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
          if (task.isMulti)
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  key: ValueKey('$k-curve'),
                  value: task.curveNames.contains(curveOf(f.curve)) ? curveOf(f.curve) : task.curveNames.first,
                  items: [for (final n in task.curveNames) DropdownMenuItem(value: n, child: Text(n))],
                  onChanged: (n) => n == null ? null : _setFeature(i, f.copyWith(curve: n)),
                ),
                if (f.kind.isComparison) ...[
                  Text(f.kind.label, style: TextStyle(fontSize: 13, color: c.inkMuted)),
                  DropdownButton<String>(
                    key: ValueKey('$k-other'),
                    value: task.curveNames.contains(f.other) ? f.other : null,
                    hint: const Text('Kurve wählen'),
                    items: [for (final n in task.curveNames) DropdownMenuItem(value: n, child: Text(n))],
                    onChanged: (n) => n == null ? null : _setFeature(i, f.copyWith(other: n)),
                  ),
                ],
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
                  range ? 'von x' : 'bei x',
                  _fmt(f.x),
                  (v) => _setFeature(i, f.copyWith(x: _num(v), clearX: _num(v) == null)),
                ),
              if (range)
                _field(
                  '$k-x2',
                  'bis x',
                  _fmt(f.x2),
                  (v) => _setFeature(i, f.copyWith(x2: _num(v), clearX2: _num(v) == null)),
                ),
              if (needsY)
                _field(
                  '$k-y',
                  switch (f.kind) {
                    SketchFeatureKind.min => 'unter y',
                    SketchFeatureKind.max => 'über y',
                    SketchFeatureKind.plateau || SketchFeatureKind.kink => 'bei y',
                    _ => 'y',
                  },
                  _fmt(f.y),
                  (v) => _setFeature(i, f.copyWith(y: _num(v), clearY: _num(v) == null)),
                ),
              if (!f.kind.isRange && !f.kind.isComparison)
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
