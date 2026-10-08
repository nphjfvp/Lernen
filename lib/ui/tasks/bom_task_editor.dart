import 'package:flutter/material.dart';

import '../../models/bom_task.dart';
import '../../services/bom_calculator.dart';
import '../../theme/app_colors.dart';
import 'bom_tree.dart';

/// Vorschau einer Stücklisten-Aufgabe: Baum und Musterlösung, von der App
/// gerechnet.
class BomTaskPreview extends StatelessWidget {
  const BomTaskPreview({super.key, required this.task, this.showSolution = true});

  final BomTask task;
  final bool showSolution;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final calc = BomCalculator(task);
    final problems = calc.problems();
    return Column(
      key: const ValueKey('bom-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BomTreeView(root: task.root, assemblies: calc.assemblies().toSet()),
        for (final p in problems)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('⚠ $p', style: TextStyle(fontSize: 12.5, color: c.warn)),
          ),
        if (showSolution)
          for (final p in task.parts) ...[const SizedBox(height: 10), BomSolutionTables(calc: calc, part: p)],
      ],
    );
  }
}

/// Stücklisten-Aufgabe bearbeiten: der Baum als Text (eine Zeile je Teil wie
/// in der Strukturstückliste), welche Listen gefragt sind, Live-Vorschau.
class BomTaskEditor extends StatefulWidget {
  const BomTaskEditor({super.key, required this.task, required this.onChanged});

  final BomTask task;
  final ValueChanged<BomTask> onChanged;

  @override
  State<BomTaskEditor> createState() => _BomTaskEditorState();
}

class _BomTaskEditorState extends State<BomTaskEditor> {
  late final _outline = TextEditingController(text: BomTask.outline(widget.task.root));
  late final _lists = TextEditingController(text: _modular?.lists.join(', ') ?? '');
  late String _lastOutline = _outline.text;
  String? _error;

  BomPart? get _modular => widget.task.parts.where((p) => p.kind == BomListKind.modular).firstOrNull;

  @override
  void didUpdateWidget(BomTaskEditor old) {
    super.didUpdateWidget(old);
    final outline = BomTask.outline(widget.task.root);
    if (outline != _lastOutline) {
      _outline.text = outline;
      _lastOutline = outline;
      _error = null;
    }
  }

  @override
  void dispose() {
    _outline.dispose();
    _lists.dispose();
    super.dispose();
  }

  void _outlineChanged(String text) {
    final parsed = BomTask.parseOutline(text);
    setState(() => _error = parsed.error);
    if (parsed.root == null) return;
    _lastOutline = BomTask.outline(parsed.root!);
    widget.onChanged(widget.task.copyWith(root: parsed.root));
  }

  void _setParts(List<BomPart> parts) => widget.onChanged(widget.task.copyWith(parts: parts));

  void _toggleKind(BomListKind kind, bool on) {
    final parts = [...widget.task.parts];
    if (on) {
      parts.add(BomPart(kind: kind));
      parts.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    } else {
      parts.removeWhere((p) => p.kind == kind);
    }
    _setParts(parts);
  }

  void _updatePart(BomListKind kind, BomPart Function(BomPart) change) =>
      _setParts([for (final p in widget.task.parts) p.kind == kind ? change(p) : p]);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final task = widget.task;
    final kinds = {for (final p in task.parts) p.kind: p};
    final uncertain = [
      for (final e in task.root.walk())
        if (e.node.uncertain) e.node,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Erzeugnisbaum',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.inkMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('bom-edit-outline'),
          controller: _outline,
          minLines: 4,
          maxLines: 14,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            helperText:
                'Eine Zeile je Teil, von links nach ganz unten: Stufe; Sach-Nr.; Bezeichnung; Menge; Einheit.\n'
                'Menge = Zahl an der Linie (je 1 Stück der Baugruppe darüber). Zeile 1 = Erzeugnis (Stufe 0).',
            helperMaxLines: 3,
            errorText: _error,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: _outlineChanged,
        ),
        if (uncertain.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('bom-edit-uncertain'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Unsicher gelesen: ${[for (final n in uncertain) '${n.number} (${bomQuantityText(n.quantity)})'].join(', ')} '
                    '– bitte mit dem Original vergleichen (gelb im Baum).',
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
                TextButton(
                  key: const ValueKey('bom-edit-confirm'),
                  onPressed: () => widget.onChanged(task.confirmed()),
                  child: const Text('Stimmt'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Gefragte Listen',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.inkMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in BomListKind.values)
              FilterChip(
                key: ValueKey('bom-edit-kind-${k.name}'),
                label: Text(k.short),
                selected: kinds.containsKey(k),
                onSelected: (on) => _toggleKind(k, on),
              ),
          ],
        ),
        if (kinds[BomListKind.overview] case final p?)
          SwitchListTile(
            key: const ValueKey('bom-edit-assemblies'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: p.includeAssemblies,
            onChanged: (v) => _updatePart(BomListKind.overview, (p) => p.copyWith(includeAssemblies: v)),
            title: const Text('Mengenübersicht mit Baugruppen'),
          ),
        if (kinds[BomListKind.structure] case final p?)
          SwitchListTile(
            key: const ValueKey('bom-edit-totals'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: p.totals,
            onChanged: (v) => _updatePart(BomListKind.structure, (p) => p.copyWith(totals: v)),
            title: const Text('Strukturstückliste mit Gesamtmengen'),
            subtitle: const Text('Sonst: Menge je übergeordnete Baugruppe'),
          ),
        if (kinds.containsKey(BomListKind.modular))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextField(
              key: const ValueKey('bom-edit-lists'),
              controller: _lists,
              decoration: InputDecoration(
                labelText: 'Vorgegebene Baukastenstücklisten (Sach-Nr.)',
                helperText: 'Leer = selbst herausfinden, welche Listen nötig sind',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => _updatePart(
                BomListKind.modular,
                (p) => p.copyWith(
                  lists: [
                    for (final s in v.split(RegExp(r'[,;\s]+')))
                      if (s.trim().isNotEmpty) s.trim(),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (task.isUsable) BomTaskPreview(task: task),
      ],
    );
  }
}
