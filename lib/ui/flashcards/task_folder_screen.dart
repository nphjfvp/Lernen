import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/module_repository.dart';
import '../../services/mastery_service.dart';
import '../../services/task_folder_service.dart';
import '../../theme/app_colors.dart';
import '../study/study_aids.dart';
import '../tasks/task_import_screen.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/mastery_dot.dart';
import '../widgets/math_text.dart';
import 'card_edit_screen.dart';

/// Aufgaben-Ordner eines Fachs: alle Aufgaben zum Verstehen
/// ([QuestionType.learn]) 1:1 wie im Dokument, mit Erklärung – dauerhaft
/// einsehbar. Ab [TaskFolderService.warnDaysBeforeExam] Tagen vor der
/// Klausur steht oben ein roter Hinweis: jetzt außerhalb der App
/// durcharbeiten.
class TaskFolderScreen extends StatelessWidget {
  const TaskFolderScreen({super.key, required this.moduleId, required this.moduleName});

  final String moduleId;
  final String moduleName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tasks = TaskFolderService.tasksOf(context.watch<FlashcardRepository>().forModule(moduleId));
    final examDate = context.watch<ModuleRepository?>()?.byId(moduleId)?.examDate;
    final days = TaskFolderService.daysUntilExam(examDate);
    final warning = TaskFolderService.isWarning(taskCount: tasks.length, examDate: examDate);
    final materials = context.watch<MaterialRepository?>()?.forModule(moduleId) ?? const [];
    final materialNames = {for (final m in materials) m.id: m.fileName};

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text('Aufgaben-Ordner · $moduleName'),
        actions: [
          IconButton(
            key: const ValueKey('task-folder-import'),
            tooltip: 'Rechenweg / Terminierung übernehmen',
            icon: const Icon(Icons.functions),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TaskImportScreen(moduleId: moduleId, moduleName: moduleName)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Banner(warning: warning, days: days, count: tasks.length, hasExamDate: examDate != null),
          const SizedBox(height: 14),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Noch keine Aufgaben. Sie entstehen beim Import von Übungsblättern, wenn eine Aufgabe '
                'sich nicht abfragen lässt (zeichnen, entwerfen, langer Rechenweg …), oder wenn du beim '
                '"Frage erstellen" den Typ "Lernen" wählst.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkMuted, height: 1.4),
              ),
            )
          else
            for (final task in tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TaskTile(task: task, materialName: materialNames[task.sourceMaterialId]),
              ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.warning, required this.days, required this.count, required this.hasExamDate});

  final bool warning;
  final int? days;
  final int count;
  final bool hasExamDate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (warning) {
      final d = days!;
      final when = d == 0 ? 'Die Klausur ist heute' : 'Klausur in $d ${d == 1 ? 'Tag' : 'Tagen'}';
      return Container(
        key: const ValueKey('task-folder-warning'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.dangerSoft,
          border: Border.all(color: c.danger),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.flag_rounded, color: c.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$when – jetzt selbst durcharbeiten',
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.danger)),
                  const SizedBox(height: 4),
                  Text(
                    'Diese $count ${count == 1 ? 'Aufgabe lässt' : 'Aufgaben lassen'} sich in der App nicht '
                    'abfragen. Löse sie außerhalb der App (z.B. auf Papier) und schau danach in die Erklärung.',
                    style: TextStyle(fontSize: 12.5, color: c.ink, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(16)),
      child: Text(
        'Aufgaben, die sich in einer Quiz-App nicht prüfen lassen – 1:1 wie im Dokument, mit Erklärung. '
        '${TaskFolderService.warnDaysBeforeExam} Tage vor der Klausur wird dieser Ordner rot markiert, dann '
        'arbeitest du sie außerhalb der App durch.'
        '${hasExamDate ? '' : ' Trage dafür im Fach ein Klausurdatum ein.'}',
        style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.materialName});

  final Flashcard task;
  final String? materialName;

  String get _title {
    final firstLine = task.front.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return firstLine.length > 110 ? '${firstLine.substring(0, 107)}…' : firstLine;
  }

  String get _subtitle => [
        if (task.sourceMaterialId != null) materialName ?? 'Material',
        if (task.sourcePage != null) 'Seite ${task.sourcePage}',
        if (task.sourceMaterialId == null && task.sourcePage == null) 'selbst erstellt',
      ].join(' · ');

  Future<void> _edit(BuildContext context) async {
    final repo = context.read<FlashcardRepository>();
    final edited = await showCardEditor(context, task);
    if (edited == null) return;
    final stored = await repo.loadById(task.id);
    if (stored == null) return;
    await repo.update(stored.copyWithContent(front: edited.front, back: edited.back));
  }

  /// Die Aufgabe als Rechenweg oder Terminierung übernehmen – Text, Erklärung
  /// (als Lösung), Bild und Quelle werden vorbelegt.
  Future<void> _practice(BuildContext context) async {
    final image = task.imageBase64;
    Uint8List? bytes;
    if (image != null) {
      try {
        bytes = base64Decode(image);
      } catch (_) {
        bytes = null;
      }
    }
    final moduleName = context.read<ModuleRepository?>()?.byId(task.moduleId)?.name ?? '';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskImportScreen(
          moduleId: task.moduleId,
          moduleName: moduleName,
          initialText: task.front,
          initialSolution: task.back,
          initialImages: [?bytes],
          sourceMaterialId: task.sourceMaterialId,
          sourcePage: task.sourcePage,
          unitId: task.unitId,
          replaceCard: task,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirmDelete(
      context,
      title: 'Aufgabe löschen?',
      message: 'Die Aufgabe verschwindet aus dem Ordner und aus dem Lernplan.',
    );
    if (ok && context.mounted) {
      await context.read<FlashcardRepository>().delete(task.id, task.moduleId);
    }
  }

  void _zoomImage(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 6,
              child: Center(child: Image.memory(base64Decode(task.imageBase64!))),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Schließen',
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final level = MasteryService().levelFor(task);
    final image = task.imageBase64;
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(side: BorderSide(color: c.border), borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('task-${task.id}'),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          leading: MasteryDot(level: level),
          title: Text(_title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          subtitle: Text(_subtitle, style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () => _zoomImage(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: Image.memory(
                        base64Decode(image),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            Text('Aufgabe', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
            const SizedBox(height: 4),
            SelectionArea(child: MathText(task.front, style: const TextStyle(fontSize: 14.5, height: 1.5))),
            const SizedBox(height: 14),
            Text('Erklärung / Lösungsweg',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
            const SizedBox(height: 4),
            SelectionArea(
              child: MathText(
                task.back.trim().isEmpty ? '(noch keine Erklärung)' : task.back,
                style: TextStyle(fontSize: 14, height: 1.55, color: c.ink),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (task.sourceMaterialId != null || task.hasScript) SourceLinkButton(card: task, script: true),
                if (task.sourceMaterialId != null && isWorksheetQuestion(context, task)) SourceLinkButton(card: task),
                TextButton.icon(
                  key: ValueKey('task-practice-${task.id}'),
                  onPressed: () => _practice(context),
                  icon: const Icon(Icons.functions, size: 16),
                  label: const Text('Interaktiv üben'),
                ),
                TextButton.icon(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Bearbeiten'),
                ),
                TextButton.icon(
                  onPressed: () => _delete(context),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Löschen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
