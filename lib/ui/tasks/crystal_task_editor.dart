import 'package:flutter/material.dart';

import '../../models/crystal_task.dart';
import '../../services/crystal_geometry.dart';
import '../../theme/app_colors.dart';
import 'crystal_cube.dart';

/// Musterlösung einer Teilaufgabe im Würfel – von der App gezeichnet.
class CrystalSolutionPreview extends StatelessWidget {
  const CrystalSolutionPreview({super.key, required this.part, required this.lattice, this.height = 230});

  final CrystalPart part;
  final CrystalLattice lattice;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final arrows = <CubeArrow>[];
    final polys = <CubePolygon>[];
    final v = part.indices;
    final valid = v.length == 3 && v.any((k) => k != 0);
    final inPlane = <List<int>>[];
    if (valid) {
      switch (part.kind) {
        case CrystalPartKind.direction:
        case CrystalPartKind.readDirection:
          final (a, b) = CrystalGeometry.segment(part.kind == CrystalPartKind.direction ? CrystalGeometry.reduce(v) : v);
          arrows.add(CubeArrow(a, b, c.good));
        case CrystalPartKind.family:
          if (CrystalGeometry.familyMembers(v).length <= 12) {
            for (final m in CrystalGeometry.familyMembers(v)) {
              final (a, b) = CrystalGeometry.segment(m);
              arrows.add(CubeArrow(a, b, c.good));
            }
          }
        case CrystalPartKind.plane:
        case CrystalPartKind.readPlane:
        case CrystalPartKind.planeAtoms:
          final plane = CrystalGeometry.standardPlane(v);
          final pts = CrystalGeometry.section(plane);
          if (pts.length >= 3) polys.add(CubePolygon(pts, stroke: c.good, fill: c.good.withValues(alpha: 0.18)));
          inPlane.addAll(CrystalGeometry.sites(lattice).where(plane.contains));
      }
    }
    final dots = [
      if (part.kind.isPlane || lattice != CrystalLattice.sc)
        for (final p in CrystalGeometry.sites(lattice))
          CubeDot(
            half: p,
            atom: true,
            fill: inPlane.any((q) => CrystalGeometry.same(q, p)) ? c.goodSoft : null,
            ring: inPlane.any((q) => CrystalGeometry.same(q, p)) ? c.good : null,
            ringWidth: inPlane.any((q) => CrystalGeometry.same(q, p)) ? 1.8 : 1.2,
          ),
    ];
    return Column(
      key: const ValueKey('crystal-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CrystalCube(height: height, arrows: arrows, polygons: polys, dots: dots, compact: true),
        const SizedBox(height: 6),
        Text(
          _caption(part, lattice),
          style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
        ),
      ],
    );
  }

  static String _caption(CrystalPart part, CrystalLattice lattice) {
    final v = part.indices;
    if (v.length != 3 || v.every((k) => k == 0)) return 'Indizes fehlen.';
    switch (part.kind) {
      case CrystalPartKind.direction:
      case CrystalPartKind.readDirection:
        final seg = CrystalGeometry.gridSegment(part.kind == CrystalPartKind.direction ? CrystalGeometry.reduce(v) : v);
        return seg == null
            ? 'Die App zeichnet ${part.notation} vom Rand der Zelle aus.'
            : 'Die App zeichnet ${part.notation} von ${CrystalGeometry.pointText(seg.$1)} nach ${CrystalGeometry.pointText(seg.$2)}.';
      case CrystalPartKind.family:
        final n = CrystalGeometry.familyMembers(v).length;
        return 'Zur Familie ${part.notation} gehören $n Richtungen – die App bildet sie selbst.';
      case CrystalPartKind.plane:
      case CrystalPartKind.readPlane:
      case CrystalPartKind.planeAtoms:
        final o = CrystalGeometry.standardOrigin(v);
        final plane = CrystalGeometry.standardPlane(v);
        final atoms = CrystalGeometry.sites(lattice).where(plane.contains).toList();
        return 'Achsenabschnitte ${plane.interceptsFrom(o).join(', ')}'
            '${CrystalGeometry.same(o, const [0, 0, 0]) ? '' : ' vom Ursprung ${CrystalGeometry.pointText(o)} aus'}'
            ' · ${atoms.length} ${lattice.short}-Atome in der Ebene';
    }
  }
}

/// Kristallgitter-Aufgabe bearbeiten: Gitter, Teilaufgaben (Art, Indizes),
/// Bestätigen unsicher gelesener Werte; Vorschau der Musterlösung je Teil.
class CrystalTaskEditor extends StatefulWidget {
  const CrystalTaskEditor({super.key, required this.task, required this.onChanged});

  final CrystalTask task;
  final ValueChanged<CrystalTask> onChanged;

  @override
  State<CrystalTaskEditor> createState() => _CrystalTaskEditorState();
}

class _CrystalTaskEditorState extends State<CrystalTaskEditor> {
  late CrystalTask _task = widget.task;
  late final List<TextEditingController> _indices = [
    for (final p in widget.task.parts) TextEditingController(text: _indexText(p.indices)),
  ];
  int _selected = 0;

  static String _indexText(List<int> v) => v.join(' ');

  @override
  void dispose() {
    for (final c in _indices) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(CrystalTask task) {
    setState(() => _task = task);
    widget.onChanged(task);
  }

  void _setPart(int i, CrystalPart part) => _set(_task.copyWith(parts: [..._task.parts]..[i] = part));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final problems = CrystalGeometry.problems(_task);
    final selected = _selected.clamp(0, _task.parts.isEmpty ? 0 : _task.parts.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GITTER', style: _caption(c)),
        const SizedBox(height: 6),
        SegmentedButton<CrystalLattice>(
          key: const ValueKey('crystal-edit-lattice'),
          segments: [
            for (final l in CrystalLattice.values) ButtonSegment(value: l, label: Text(l.short)),
          ],
          selected: {_task.lattice},
          showSelectedIcon: false,
          onSelectionChanged: (s) => _set(_task.copyWith(lattice: s.first)),
        ),
        if (_task.hasUncertain)
          Container(
            key: const ValueKey('crystal-edit-uncertain'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.help_outline, color: c.warn, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Manche Indizes waren schlecht lesbar (markiert) – Striche über den Zahlen bitte mit dem Blatt vergleichen.',
                      style: TextStyle(fontSize: 12.5, color: c.ink)),
                ),
                TextButton(key: const ValueKey('crystal-edit-confirm'), onPressed: () => _set(_task.confirmed()), child: const Text('Stimmt so')),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text('TEILAUFGABEN', style: _caption(c)),
        for (final (i, p) in _task.parts.indexed) _partCard(c, i, p, i == selected),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('crystal-edit-add'),
            onPressed: () {
              _indices.add(TextEditingController(text: '1 1 1'));
              _set(_task.copyWith(parts: [
                ..._task.parts,
                const CrystalPart(kind: CrystalPartKind.direction, indices: [1, 1, 1]),
              ]));
              setState(() => _selected = _task.parts.length - 1);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Teilaufgabe hinzufügen'),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('crystal-edit-check'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: problems.isEmpty ? c.goodSoft : c.warnSoft, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                problems.isEmpty ? 'Die App zeichnet und prüft alle Teilaufgaben selbst.' : 'Bitte prüfen:',
                style: TextStyle(fontWeight: FontWeight.w700, color: problems.isEmpty ? c.good : c.warn),
              ),
              for (final p in problems)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $p', style: const TextStyle(fontSize: 13))),
            ],
          ),
        ),
        if (_task.parts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('MUSTERLÖSUNG ${String.fromCharCode(97 + selected).toUpperCase()} – VON DER APP GEZEICHNET', style: _caption(c)),
          const SizedBox(height: 6),
          CrystalSolutionPreview(part: _task.parts[selected], lattice: _task.latticeOf(_task.parts[selected])),
        ],
      ],
    );
  }

  TextStyle _caption(AppColors c) => TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.inkMuted);

  Widget _partCard(AppColors c, int i, CrystalPart p, bool selected) {
    final parsed = parseMillerIndices(_indices[i].text);
    return GestureDetector(
      onTap: () => setState(() => _selected = i),
      child: Container(
        key: ValueKey('crystal-edit-part-$i'),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: selected ? c.accent : (p.uncertain ? c.warn : c.border), width: selected ? 1.6 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('${String.fromCharCode(97 + i)})', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<CrystalPartKind>(
                    key: ValueKey('crystal-edit-kind-$i'),
                    isExpanded: true,
                    value: p.kind,
                    underline: const SizedBox.shrink(),
                    items: [for (final k in CrystalPartKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
                    onChanged: (k) {
                      if (k == null) return;
                      setState(() => _selected = i);
                      _setPart(i, p.copyWith(kind: k));
                    },
                  ),
                ),
                IconButton(
                  key: ValueKey('crystal-edit-delete-$i'),
                  tooltip: 'Teilaufgabe entfernen',
                  onPressed: _task.parts.length <= 1
                      ? null
                      : () {
                          _indices.removeAt(i).dispose();
                          setState(() => _selected = 0);
                          _set(_task.copyWith(parts: [..._task.parts]..removeAt(i)));
                        },
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 130,
                  child: TextField(
                    key: ValueKey('crystal-edit-indices-$i'),
                    controller: _indices[i],
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: p.kind.isPlane ? 'h k l' : 'u v w',
                      border: const OutlineInputBorder(),
                      errorText: parsed == null ? 'drei Zahlen' : null,
                    ),
                    onTap: () => setState(() => _selected = i),
                    onChanged: (text) {
                      final v = parseMillerIndices(text);
                      setState(() => _selected = i);
                      if (v != null) {
                        _setPart(i, p.copyWith(indices: v, uncertain: false));
                      } else {
                        setState(() {});
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    parsed == null ? '' : CrystalPart(kind: p.kind, indices: parsed).notation,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: p.uncertain ? c.warn : c.ink),
                  ),
                ),
              ],
            ),
            if (p.uncertain)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('schlecht lesbar – bitte prüfen', style: TextStyle(fontSize: 12, color: c.warn, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}
