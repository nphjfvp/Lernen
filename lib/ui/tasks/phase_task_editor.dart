import 'package:flutter/material.dart';

import '../../models/phase_task.dart';
import '../../services/phase_calculator.dart';
import '../../theme/app_colors.dart';
import 'phase_diagram_canvas.dart';

/// Vorschau: das Diagramm aus den Eckdaten und die Musterlösung je
/// Teilaufgabe (rechnet die App).
class PhaseTaskPreview extends StatelessWidget {
  const PhaseTaskPreview({super.key, required this.task, this.height = 240});

  final PhaseTask task;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final calc = PhaseCalculator(task);
    final problems = calc.problems();
    return Column(
      key: const ValueKey('phase-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (task.system.isValid) PhaseDiagramCanvas(calc: calc, height: height),
        const SizedBox(height: 6),
        if (task.isUsable)
          for (final (i, p) in task.parts.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${String.fromCharCode(97 + i)}) ${calc.solutionText(p)}',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
              ),
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

/// Zustandsdiagramm bearbeiten: Eckdaten des Systems und Teilaufgaben.
class PhaseTaskEditor extends StatefulWidget {
  const PhaseTaskEditor({super.key, required this.task, required this.onChanged});

  final PhaseTask task;
  final ValueChanged<PhaseTask> onChanged;

  @override
  State<PhaseTaskEditor> createState() => _PhaseTaskEditorState();
}

class _PhaseTaskEditorState extends State<PhaseTaskEditor> {
  /// Neu aufgebaute Zeilen nach Hinzufügen/Entfernen.
  int _revision = 0;

  PhaseTask get _task => widget.task;
  PhaseSystem get _s => _task.system;
  void _emit(PhaseTask t) => widget.onChanged(t);
  void _system(PhaseSystem s) => _emit(_task.copyWith(system: s));
  void _setPart(int i, PhasePart p) => _emit(_task.copyWith(parts: [..._task.parts]..[i] = p));

  static double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
  static String _fmt(double? v) => v == null ? '' : PhaseCalculator.fmt(v, digits: 3);

  Widget _field(String key, String label, String initial, ValueChanged<String> onChanged, {double width = 110}) =>
      SizedBox(
        width: width,
        child: TextFormField(
          key: ValueKey(key),
          initialValue: initial,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
          onChanged: onChanged,
        ),
      );

  Widget _numField(String key, String label, double value, PhaseSystem Function(double) apply, {double width = 110}) =>
      _field(key, label, _fmt(value), width: width, (v) {
        final n = _num(v);
        if (n != null) _system(apply(n));
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = _s;
    final head = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_task.uncertain)
          Container(
            key: const ValueKey('phase-edit-uncertain'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Manche Werte waren schlecht ablesbar – bitte mit dem Diagramm vergleichen.',
                    style: TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
                TextButton(
                  key: const ValueKey('phase-edit-confirm'),
                  onPressed: () => _emit(_task.confirmed()),
                  child: const Text('Stimmt'),
                ),
              ],
            ),
          ),
        Text('System', style: head),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _field('phase-edit-a', 'Komponente A', s.a, (v) => _system(s.copyWith(a: v.trim()))),
            _field('phase-edit-b', 'Komponente B', s.b, (v) => _system(s.copyWith(b: v.trim()))),
            _field('phase-edit-unit', 'Einheit', s.unit, (v) => _system(s.copyWith(unit: v.trim()))),
            _numField('phase-edit-cmax', 'Achse bis (%)', s.cMax, (n) => s.copyWith(cMax: n)),
            _numField('phase-edit-tmin', 'T von (°C)', s.tMin, (n) => s.copyWith(tMin: n)),
            _numField('phase-edit-tmax', 'T bis (°C)', s.tMax, (n) => s.copyWith(tMax: n)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _field('phase-edit-liquid', 'oberes Gebiet', s.liquid, (v) => _system(s.copyWith(liquid: v.trim()))),
            _field('phase-edit-alpha', 'Phase links', s.alpha, (v) => _system(s.copyWith(alpha: v.trim()))),
            _field('phase-edit-beta', 'Phase rechts', s.beta, (v) => _system(s.copyWith(beta: v.trim()))),
            _field(
              'phase-edit-eutectic-name',
              'Gefüge',
              s.eutecticName,
              (v) => _system(s.copyWith(eutecticName: v.trim())),
            ),
          ],
        ),
        SwitchListTile(
          key: const ValueKey('phase-edit-eutectoid'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Eutektoid (Umwandlung im festen Zustand)'),
          subtitle: const Text('z.B. Stahlecke: γ → α + Fe₃C'),
          value: s.eutectoid,
          onChanged: (v) => _system(s.copyWith(eutectoid: v)),
        ),
        const SizedBox(height: 4),
        Text('Eckdaten', style: head),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _numField('phase-edit-melt-a', 'T Schmelze A', s.meltA, (n) => s.copyWith(meltA: n)),
            _numField('phase-edit-ec', 'eutekt. c', s.eutecticC, (n) => s.copyWith(eutecticC: n)),
            _numField('phase-edit-et', 'eutekt. T', s.eutecticT, (n) => s.copyWith(eutecticT: n)),
            _numField('phase-edit-rc', 'rechtes Ende c', s.rightC, (n) => s.copyWith(rightC: n)),
            _numField('phase-edit-rt', 'rechtes Ende T', s.rightT, (n) => s.copyWith(rightT: n)),
            _numField('phase-edit-amax', 'α max. (c)', s.alphaMax, (n) => s.copyWith(alphaMax: n)),
            _numField('phase-edit-alow', 'α bei T min', s.alphaLow, (n) => s.copyWith(alphaLow: n)),
            _numField('phase-edit-bmax', 'β bei eutekt. T', s.betaMax, (n) => s.copyWith(betaMax: n)),
            _numField('phase-edit-blow', 'β bei T min', s.betaLow, (n) => s.copyWith(betaLow: n)),
          ],
        ),
        if (s.lines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Gekrümmte Linien mit Zwischenpunkten: ${[for (final l in s.lines.keys) l.label].join(', ')}.',
                    style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                  ),
                ),
                TextButton(
                  key: const ValueKey('phase-edit-straight'),
                  onPressed: () => _system(s.copyWith(lines: const {})),
                  child: const Text('Als Geraden'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text('Teilaufgaben (die Lösung rechnet die App)', style: head),
        const SizedBox(height: 6),
        for (final (i, p) in _task.parts.indexed) _partRow(c, i, p),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('phase-edit-add'),
            onPressed: () {
              setState(() => _revision++);
              _emit(
                _task.copyWith(
                  parts: [
                    ..._task.parts,
                    PhasePart(kind: PhasePartKind.lever, c: s.eutecticC / 2, t: (s.eutecticT + s.meltA) / 2),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Teilaufgabe hinzufügen'),
          ),
        ),
        const SizedBox(height: 8),
        PhaseTaskPreview(task: _task),
      ],
    );
  }

  Widget _partRow(AppColors c, int i, PhasePart p) {
    final k = 'phase-edit-$i-$_revision';
    final needsC = {PhasePartKind.phases, PhasePartKind.lever, PhasePartKind.structure}.contains(p.kind);
    final needsT = {PhasePartKind.phases, PhasePartKind.lever, PhasePartKind.composition}.contains(p.kind);
    return Container(
      key: ValueKey('phase-edit-part-$i'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: p.isValid ? null : Border.all(color: c.danger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${String.fromCharCode(97 + i)})  ', style: const TextStyle(fontWeight: FontWeight.w700)),
              Expanded(
                child: DropdownButton<PhasePartKind>(
                  key: ValueKey('$k-kind'),
                  isExpanded: true,
                  value: p.kind,
                  items: [
                    for (final kind in PhasePartKind.values) DropdownMenuItem(value: kind, child: Text(kind.label)),
                  ],
                  onChanged: (kind) {
                    if (kind == null) return;
                    setState(() => _revision++);
                    _setPart(
                      i,
                      p.copyWith(
                        kind: kind,
                        compositions: kind == PhasePartKind.cooling && p.compositions.isEmpty
                            ? [0, _s.eutecticC]
                            : null,
                        region: kind == PhasePartKind.pickRegion ? (p.region ?? PhaseRegion.alpha) : null,
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                key: ValueKey('phase-edit-remove-$i'),
                tooltip: 'Teilaufgabe entfernen',
                icon: Icon(Icons.close, size: 18, color: c.inkMuted),
                onPressed: () {
                  setState(() => _revision++);
                  _emit(_task.copyWith(parts: [..._task.parts]..removeAt(i)));
                },
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (needsC)
                _field(
                  '$k-c',
                  'c (% ${_s.b})',
                  _fmt(p.c),
                  (v) => _setPart(i, p.copyWith(c: _num(v), clearC: _num(v) == null)),
                ),
              if (needsT)
                _field(
                  '$k-t',
                  'T (°C)',
                  _fmt(p.t),
                  (v) => _setPart(i, p.copyWith(t: _num(v), clearT: _num(v) == null)),
                ),
              if (p.kind == PhasePartKind.cooling)
                _field(
                  '$k-comps',
                  'Legierungen (% ${_s.b}, mit ; getrennt)',
                  p.compositions.map(PhaseCalculator.fmt).join('; '),
                  width: 260,
                  (v) => _setPart(
                    i,
                    p.copyWith(compositions: [for (final part in v.split(RegExp(r'[;\s]+'))) ?_num(part)]),
                  ),
                ),
              if (p.kind == PhasePartKind.solubility)
                DropdownButton<String>(
                  key: ValueKey('$k-side'),
                  value: p.side,
                  items: [
                    DropdownMenuItem(value: 'b', child: Text('${_s.b} in ${_s.alpha}')),
                    DropdownMenuItem(value: 'a', child: Text('${_s.a} in ${_s.beta}')),
                  ],
                  onChanged: (v) => v == null ? null : _setPart(i, p.copyWith(side: v)),
                ),
              if (p.kind == PhasePartKind.pickRegion)
                DropdownButton<PhaseRegion>(
                  key: ValueKey('$k-region'),
                  value: p.region,
                  items: [
                    for (final r in PhaseRegion.values) DropdownMenuItem(value: r, child: Text(_s.regionName(r))),
                  ],
                  onChanged: (r) => r == null ? null : _setPart(i, p.copyWith(region: r)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _field(
            '$k-prompt',
            'Aufgabentext (optional, sonst schreibt ihn die App)',
            p.prompt,
            width: double.infinity,
            (v) => _setPart(i, p.copyWith(prompt: v)),
          ),
        ],
      ),
    );
  }
}
