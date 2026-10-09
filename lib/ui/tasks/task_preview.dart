import 'package:flutter/material.dart';

import '../../models/bom_task.dart';
import '../../models/crystal_task.dart';
import '../../models/flashcard.dart';
import '../../models/phase_task.dart';
import '../../models/sketch_task.dart';
import '../../models/gantt_task.dart';
import '../../models/step_task.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';
import 'bom_task_editor.dart';
import 'crystal_task_editor.dart';
import 'gantt_task_editor.dart';
import 'phase_task_editor.dart';
import 'sketch_task_editor.dart';

/// Lösung einer interaktiven Aufgabe auf einen Blick (Kartenliste, Aufgaben-
/// Ordner): beim Rechenweg die Schritte mit ihren Ergebnissen, bei der
/// Terminierung die von der App berechnete Musterlösung.
class TaskAnswerPreview extends StatelessWidget {
  const TaskAnswerPreview({super.key, required this.card});

  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.45);
    switch (card.type) {
      case QuestionType.steps:
        final task = StepTask.fromMap(card.taskData);
        if (task == null || task.steps.isEmpty) {
          return Text('Kein Rechenweg hinterlegt.', style: muted.copyWith(color: c.danger));
        }
        return Column(
          key: const ValueKey('task-preview-steps'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, s) in task.steps.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: MathText('${i + 1}. ${s.title}: ${s.resultText}', style: muted),
              ),
            if (task.domainNote.trim().isNotEmpty) MathText('Gilt ${task.domainNote}', style: muted),
          ],
        );
      case QuestionType.gantt:
        final task = GanttTask.fromMap(card.taskData);
        if (task == null) return Text('Keine Terminierung hinterlegt.', style: muted.copyWith(color: c.danger));
        return GanttSolutionPreview(task: task);
      case QuestionType.crystal:
        final crystal = CrystalTask.fromMap(card.taskData);
        if (crystal == null) return Text('Keine Kristallaufgabe hinterlegt.', style: muted.copyWith(color: c.danger));
        return Column(
          key: const ValueKey('task-preview-crystal'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, p) in crystal.parts.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${String.fromCharCode(97 + i)}) ${p.kind.label} ${p.notation}', style: muted),
              ),
            const SizedBox(height: 6),
            CrystalSolutionPreview(part: crystal.parts.first, lattice: crystal.latticeOf(crystal.parts.first), height: 180),
          ],
        );
      case QuestionType.bom:
        final bom = BomTask.fromMap(card.taskData);
        if (bom == null) return Text('Keine Stückliste hinterlegt.', style: muted.copyWith(color: c.danger));
        return Column(
          key: const ValueKey('task-preview-bom'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, p) in bom.parts.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${String.fromCharCode(97 + i)}) ${p.kind.label}', style: muted),
              ),
            const SizedBox(height: 6),
            BomTaskPreview(task: bom),
          ],
        );
      case QuestionType.sketch:
        final sketch = SketchTask.fromMap(card.taskData);
        if (sketch == null) return Text('Keine Skizze hinterlegt.', style: muted.copyWith(color: c.danger));
        return SketchTaskPreview(task: sketch, height: 180);
      case QuestionType.phase:
        final phase = PhaseTask.fromMap(card.taskData);
        if (phase == null) return Text('Kein Zustandsdiagramm hinterlegt.', style: muted.copyWith(color: c.danger));
        return PhaseTaskPreview(task: phase, height: 200);
      default:
        return MathText(card.back, style: muted);
    }
  }
}
