import 'package:flutter/material.dart';

import '../../models/drawing_task.dart';
import '../../theme/app_colors.dart';

/// Vorschau einer Freihand-Aufgabe: Flächen, Kriterien und Musterlösung.
class DrawingTaskPreview extends StatelessWidget {
  const DrawingTaskPreview({super.key, required this.task});

  final DrawingTask task;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('drawing-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(12)),
      child: Text(
        [if (task.panels.length > 1) 'Flächen: ${task.panels.join(', ')}', task.solutionText()].join('\n'),
        style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
      ),
    );
  }
}

/// Freihand-Aufgabe bearbeiten: Flächen, Kriterien (Pflicht/optional, je
/// Fläche) und Beschreibung der Musterskizze.
class DrawingTaskEditor extends StatefulWidget {
  const DrawingTaskEditor({super.key, required this.task, required this.onChanged});

  final DrawingTask task;
  final ValueChanged<DrawingTask> onChanged;

  @override
  State<DrawingTaskEditor> createState() => _DrawingTaskEditorState();
}

class _DrawingTaskEditorState extends State<DrawingTaskEditor> {
  /// Neu aufgebaute Zeilen nach Hinzufügen/Entfernen.
  int _revision = 0;

  DrawingTask get _task => widget.task;
  void _emit(DrawingTask t) => widget.onChanged(t);

  void _setCriterion(int i, DrawingCriterion c) => _emit(_task.copyWith(criteria: [..._task.criteria]..[i] = c));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_task.uncertain)
          Container(
            key: const ValueKey('drawing-edit-uncertain'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Die Kriterien waren nicht ganz eindeutig – bitte mit der Aufgabe vergleichen.',
                    style: TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
                TextButton(
                  key: const ValueKey('drawing-edit-confirm'),
                  onPressed: () => _emit(_task.confirmed()),
                  child: const Text('Stimmt'),
                ),
              ],
            ),
          ),
        TextFormField(
          key: ValueKey('drawing-edit-panels-$_revision'),
          initialValue: _task.panels.join('; '),
          decoration: const InputDecoration(
            labelText: 'Zeichenflächen (mit ; getrennt, leer = eine)',
            hintText: 'z.B. vor dem Walzen; nach dem Walzen',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            final panels = [
              for (final p in v.split(';'))
                if (p.trim().isNotEmpty) p.trim(),
            ];
            // Kriterien zu einer entfernten Fläche gelten danach für alle.
            _emit(
              _task.copyWith(
                panels: panels,
                criteria: [for (final cr in _task.criteria) panels.contains(cr.panel) ? cr : cr.copyWith(panel: '')],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Text('Das soll die Zeichnung zeigen (prüft die KI bzw. hakt man selbst ab)', style: head),
        const SizedBox(height: 6),
        for (final (i, cr) in _task.criteria.indexed) _criterionRow(c, i, cr),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('drawing-edit-add'),
            onPressed: () {
              setState(() => _revision++);
              _emit(
                _task.copyWith(
                  criteria: [
                    ..._task.criteria,
                    const DrawingCriterion(text: ''),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Kriterium hinzufügen'),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('drawing-edit-solution'),
          initialValue: _task.solution,
          minLines: 2,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Musterskizze beschrieben (für „Lösung zeigen“)',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _emit(_task.copyWith(solution: v)),
        ),
        const SizedBox(height: 10),
        DrawingTaskPreview(task: _task),
      ],
    );
  }

  Widget _criterionRow(AppColors c, int i, DrawingCriterion cr) {
    final k = 'drawing-edit-$i-$_revision';
    final panels = _task.panels;
    return Container(
      key: ValueKey('drawing-edit-criterion-$i'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: cr.text.trim().isEmpty ? Border.all(color: c.danger) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('$k-text'),
                  initialValue: cr.text,
                  maxLines: null,
                  decoration: InputDecoration(labelText: 'Kriterium ${i + 1}', isDense: true),
                  onChanged: (v) => _setCriterion(i, cr.copyWith(text: v.trim())),
                ),
              ),
              IconButton(
                key: ValueKey('drawing-edit-remove-$i'),
                tooltip: 'Kriterium entfernen',
                icon: Icon(Icons.close, size: 18, color: c.inkMuted),
                onPressed: () {
                  setState(() => _revision++);
                  _emit(_task.copyWith(criteria: [..._task.criteria]..removeAt(i)));
                },
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (panels.length > 1)
                DropdownButton<String>(
                  key: ValueKey('$k-panel'),
                  value: panels.contains(cr.panel) ? cr.panel : '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('alle Flächen')),
                    for (final p in panels) DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => v == null ? null : _setCriterion(i, cr.copyWith(panel: v)),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    key: ValueKey('$k-required'),
                    value: cr.required,
                    onChanged: (v) => _setCriterion(i, cr.copyWith(required: v ?? true)),
                  ),
                  const Text('muss erfüllt sein'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
