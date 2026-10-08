import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../condense/condense_screen.dart';
import '../widgets/math_text.dart';
import '../../models/concept.dart';
import '../../models/flashcard.dart';
import '../../models/lecture_unit.dart';
import '../../models/material_item.dart';
import '../../models/module.dart';
import '../../repositories/concept_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/lab_experiment_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../models/summary.dart';
import '../../repositories/summary_repository.dart';
import '../../services/ai_service.dart';
import '../../services/mastery_service.dart';
import '../../services/material_file_store.dart';
import '../../services/material_text_extractor.dart';
import '../../services/module_export_service.dart';
import '../../services/pdf_cloud_store.dart';
import '../../services/pdf_cloud_sync_service.dart';
import '../../services/pdf_ocr_service.dart';
import '../../services/pdf_service.dart';
import '../../services/task_folder_service.dart';
import '../../services/unit_schedule_service.dart';
import '../../theme/app_colors.dart';
import '../chat/module_chat_screen.dart';
import '../exam/mock_exam_screen.dart';
import '../flashcards/flashcard_list_screen.dart';
import '../flashcards/task_folder_screen.dart';
import '../import/pdf_question_import_screen.dart';
import '../lab/lab_experiments_section.dart';
import '../practice/practice_screen.dart';
import '../prepare/prepare_screen.dart';
import '../prepare/summary_detail_screen.dart';
import '../review/review_screen.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/edit_text_dialog.dart';
import '../widgets/mastery_dot.dart';
import '../widgets/ocr_notice.dart';
import 'material_opener.dart';
import 'module_form_screen.dart';

class ModuleDetailScreen extends StatefulWidget {
  const ModuleDetailScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  bool _isDragOver = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    await context.read<MaterialRepository>().loadForModule(widget.moduleId);
    if (!mounted) return;
    await context.read<SummaryRepository>().loadForModule(widget.moduleId);
    if (!mounted) return;
    await context.read<ConceptRepository>().loadForModule(widget.moduleId);
    if (!mounted) return;
    await context.read<FlashcardRepository>().loadForModule(widget.moduleId);
    if (!mounted) return;
    await context.read<LectureUnitRepository>().loadForModule(widget.moduleId);
  }

  /// Knopf zum Aufgaben-Ordner (nur wenn es Aufgaben zum Verstehen gibt) –
  /// rot, sobald die Klausur nah ist (siehe TaskFolderService).
  List<Widget> _taskFolderButton(BuildContext context, Module module, List<Flashcard> flashcards) {
    final count = TaskFolderService.tasksOf(flashcards).length;
    if (count == 0) return const [];
    final c = context.colors;
    final warning = TaskFolderService.isWarning(taskCount: count, examDate: module.examDate);
    final days = TaskFolderService.daysUntilExam(module.examDate);
    return [
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const ValueKey('task-folder-button'),
        style: warning
            ? OutlinedButton.styleFrom(
                foregroundColor: c.danger,
                backgroundColor: c.dangerSoft,
                side: BorderSide(color: c.danger),
              )
            : null,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TaskFolderScreen(moduleId: module.id, moduleName: module.name)),
        ),
        icon: Icon(warning ? Icons.flag_rounded : Icons.folder_open_outlined),
        label: Text(
          warning
              ? 'Aufgaben-Ordner ($count) · ${days == 0 ? 'Klausur heute' : 'Klausur in $days ${days == 1 ? 'Tag' : 'Tagen'}'}'
              : 'Aufgaben-Ordner ($count)',
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final module = context.watch<ModuleRepository>().byId(widget.moduleId);
    if (module == null) {
      return Scaffold(backgroundColor: c.bg, body: const Center(child: Text('Fach nicht gefunden.')));
    }
    final materials = context.watch<MaterialRepository>().forModule(widget.moduleId);
    final summaries = context.watch<SummaryRepository>().forModule(widget.moduleId);
    final concepts = context.watch<ConceptRepository>().forModule(widget.moduleId);
    final flashcards = context.watch<FlashcardRepository>().forModule(widget.moduleId);
    final units = context.watch<LectureUnitRepository>().forModule(widget.moduleId);
    final days = module.daysUntilExam;

    final content = SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        _RoundIconButton(icon: Icons.chevron_left_rounded, onTap: () => Navigator.of(context).pop()),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            module.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _RoundIconButton(
                        icon: Icons.ios_share_outlined,
                        onTap: () => _exportModule(module, units, materials, concepts, flashcards, summaries),
                      ),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: Icons.edit_outlined,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ModuleFormScreen(existing: module)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: Icons.delete_outline,
                        onTap: () => _confirmDelete(context, module.id, module.name),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  children: [
                    if (days != null) ...[
                      Text(
                        'Klausur in',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.06,
                          color: c.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$days',
                            style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1),
                          ),
                          const SizedBox(width: 9),
                          Text('Tagen', style: TextStyle(fontSize: 16, color: c.inkMuted)),
                        ],
                      ),
                      const SizedBox(height: 26),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _ModeCard(
                            icon: Icons.auto_stories_outlined,
                            title: 'Vorbereiten',
                            subtitle: 'Folien hochladen → KI-Überblick',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => PrepareScreen(moduleId: module.id)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ModeCard(
                            icon: Icons.auto_awesome_outlined,
                            title: 'Nachbereiten',
                            subtitle: 'Folien + Übungen → Konzepte & Karten · Speedrun',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ReviewScreen(moduleId: module.id)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SoftRow(
                      icon: Icons.manage_search,
                      title: 'Fragen aus PDF importieren',
                      subtitle: 'KI liest beliebig viele PDFs fortlaufend und übernimmt jede vorhandene Frage/Aufgabe ins '
                          'Quiz – oder macht daraus interaktive Aufgaben (z.B. alle Mathe-Aufgaben als Rechenweg)',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PdfQuestionImportScreen(moduleId: module.id, moduleName: module.name),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SoftRow(
                      icon: Icons.style_outlined,
                      title: 'Üben (Lernmodus)',
                      subtitle: 'Frei üben, unabhängig von Fälligkeit/Klausur-Pacing – zählt trotzdem für die Planung',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PracticeScreen(moduleId: module.id, moduleName: module.name),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SoftRow(
                      icon: Icons.assignment_outlined,
                      title: 'Probeklausur',
                      subtitle: 'Wie in der Klausur: ohne Hilfen, mit Zeitlimit und Note am Ende',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MockExamScreen(moduleId: module.id, moduleName: module.name),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SoftRow(
                      icon: Icons.forum_outlined,
                      title: 'Fragen stellen',
                      subtitle: 'Zu deinen hochgeladenen Materialien nachfragen – nur wenn du fragst',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ModuleChatScreen(moduleId: module.id, moduleName: module.name),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    _SectionHeader(title: 'Zusammenfassungen', count: summaries.length),
                    const SizedBox(height: 10),
                    if (summaries.isEmpty)
                      const _HintText('Noch keine Zusammenfassung oder Formelsammlung – starte den Vorbereiten-Modus.')
                    else
                      ...summaries.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SoftRow(
                              icon: s.isFormulaSheet ? Icons.functions : Icons.description_outlined,
                              title: s.title,
                              subtitle: s.isFormulaSheet
                                  ? 'Formelsammlung · ${s.formulaSheet!.detail.label} · '
                                      '${s.formulaSheet!.visibleCount()} Formeln'
                                  : '${s.keyPoints.length} Kernkonzepte',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => SummaryDetailScreen(summary: s)),
                              ),
                            ),
                          )),
                    const SizedBox(height: 20),
                    _SectionHeader(title: 'Lernkonzepte', count: concepts.length),
                    const SizedBox(height: 10),
                    if (concepts.isEmpty)
                      const _HintText('Noch keine Konzepte – starte den Nachbereiten-Modus.')
                    else
                      ...concepts.map((concept) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            // Material statt DecoratedBox: ExpansionTile malt
                            // Hintergrund/Tipp-Effekt auf das nächste Material
                            // (sonst Debug-Assertion und unsichtbares Feedback).
                            child: Material(
                              color: c.surface,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: c.border),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                  title: MathText(concept.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                                  iconColor: c.inkMuted,
                                  collapsedIconColor: c.inkMuted,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: MathText(concept.explanation, style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.5)),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          if (concept.linkedMaterialId != null && concept.linkedPageNumber != null)
                                            TextButton.icon(
                                              onPressed: () => _openConceptSourcePage(concept, materials),
                                              icon: const Icon(Icons.description_outlined, size: 16),
                                              label: Text('Seite ${concept.linkedPageNumber}'),
                                            ),
                                          TextButton.icon(
                                            onPressed: () => _editConcept(concept),
                                            icon: const Icon(Icons.edit_outlined, size: 16),
                                            label: const Text('Bearbeiten'),
                                          ),
                                          TextButton.icon(
                                            onPressed: () => _deleteConcept(concept),
                                            icon: const Icon(Icons.delete_outline, size: 16),
                                            label: const Text('Löschen'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )),
                    const SizedBox(height: 20),
                    _SectionHeader(title: 'Karteikarten', count: flashcards.length),
                    const SizedBox(height: 10),
                    if (flashcards.isEmpty)
                      const _HintText('Noch keine Karteikarten – entstehen automatisch im Nachbereiten-Modus.')
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _StatPill(
                              value: flashcards.where((card) => card.reps == 0 && !card.isMuted).length,
                              label: 'neu',
                              fg: c.accentOnSoft,
                              bg: c.accentSoft,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatPill(
                              value: flashcards.where((card) => card.reps > 0 && !card.isMuted).length,
                              label: 'in Wiederholung',
                              fg: c.good,
                              bg: c.goodSoft,
                            ),
                          ),
                        ],
                      ),
                      if (flashcards.any((card) => card.isMuted)) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${flashcards.where((card) => card.isMuted).length} stummgeschaltet (Gewichtung 0) – '
                          'kommen nie dran und zählen hier nicht mit.',
                          key: const ValueKey('module-muted-count'),
                          style: TextStyle(fontSize: 12, color: c.inkMuted),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _AmpelRow(breakdown: MasteryService().breakdown(flashcards)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FlashcardListScreen(moduleId: module.id, moduleName: module.name),
                          ),
                        ),
                        icon: const Icon(Icons.style_outlined),
                        label: const Text('Alle Karteikarten ansehen'),
                      ),
                      ..._taskFolderButton(context, module, flashcards),
                    ],
                    const SizedBox(height: 20),
                    _SectionHeader(title: 'Einheiten', count: units.length),
                    const SizedBox(height: 6),
                    Text(
                      'Fasst Material zu einer Vorlesungssitzung zusammen. Du kannst ruhig den '
                      'ganzen Semesterstoff im Voraus hochladen – das Daily Quiz fragt trotzdem nur '
                      'Karten aus Einheiten ab, die "behandelt" sind: von Hand abgehakt oder '
                      'automatisch ab ihrem Termin.',
                      style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    if (units.isNotEmpty)
                      ...units.map((u) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _UnitRow(
                              unit: u,
                              materialCount: materials.where((m) => m.unitId == u.id).length,
                              onToggleCovered: (value) => context
                                  .read<LectureUnitRepository>()
                                  .setCovered(u.id, u.moduleId, value),
                              onPickDate: () => _pickUnitDate(u),
                              onDelete: () => _deleteUnit(u),
                              onNotesChanged: (notes) =>
                                  context.read<LectureUnitRepository>().setNotes(u.id, u.moduleId, notes),
                            ),
                          )),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _createUnit,
                          icon: const Icon(Icons.add),
                          label: const Text('Einheit anlegen'),
                        ),
                        if (context.watch<SettingsRepository>().settings.hasApiKey &&
                            materials.any((m) =>
                                m.kind != MaterialKind.condensed && (m.unitId == null || !units.any((u) => u.id == m.unitId))))
                          OutlinedButton.icon(
                            onPressed: _suggestingUnits ? null : () => _suggestUnits(materials, units),
                            icon: _suggestingUnits
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.auto_awesome_outlined),
                            label: const Text('Einheiten vorschlagen'),
                          ),
                        if (units.isNotEmpty && (module.lectureSlots?.isNotEmpty ?? false))
                          OutlinedButton.icon(
                            onPressed: () => _assignDatesFromSchedule(module, units),
                            icon: const Icon(Icons.event_available_outlined),
                            label: const Text('Termine aus Stundenplan'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (module.showsLab(
                        hasExperiments: context.watch<LabExperimentRepository?>()?.forModule(module.id).isNotEmpty ?? false)) ...[
                      LabExperimentsSection(moduleId: module.id, moduleName: module.name),
                      const SizedBox(height: 20),
                    ],
                    _SectionHeader(title: 'Materialien', count: materials.length),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _uploadMaterials,
                          icon: const Icon(Icons.add),
                          label: const Text('Material hochladen'),
                        ),
                        if (materials.any((m) => m.kind == MaterialKind.slide))
                          OutlinedButton.icon(
                            key: const ValueKey('module-condense'),
                            onPressed: _condense,
                            icon: const Icon(Icons.content_cut),
                            label: const Text('Vorlesung kürzen'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (materials.isEmpty)
                      const _HintText(
                          'Noch keine Dateien hochgeladen. Du kannst hier auch schon den ganzen '
                          'Semesterinhalt ablegen und vorarbeiten – ohne dass dafür KI-Anfragen anfallen.')
                    else ...[
                      for (final unit in units)
                        if (materials.any((m) => m.unitId == unit.id)) ...[
                          _MaterialGroupLabel(unit.title),
                          ...materials.where((m) => m.unitId == unit.id).map(_materialRow),
                          const SizedBox(height: 6),
                        ],
                      // Auch Materialien, deren Einheit nicht (mehr) existiert
                      // (z.B. vor dem Lösch-Kaskaden-Fix gelöscht), hier statt
                      // unsichtbar.
                      if (materials.any((m) => !units.any((u) => u.id == m.unitId))) ...[
                        if (units.isNotEmpty) const _MaterialGroupLabel('Ohne Einheit'),
                        ...materials.where((m) => !units.any((u) => u.id == m.unitId)).map(_materialRow),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
    );
    return Scaffold(
      backgroundColor: c.bg,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDragOver = true),
        onDragExited: (_) => setState(() => _isDragOver = false),
        onDragDone: (details) {
          setState(() => _isDragOver = false);
          _handleDroppedFiles(details.files);
        },
        child: Stack(
          children: [
            content,
            if (_isDragOver)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: c.accent.withAlpha(35),
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: c.accent, width: 3)),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: c.accent),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.file_download_outlined, color: c.accent),
                              const SizedBox(width: 8),
                              Text('Hier ablegen zum Hochladen',
                                  style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _materialRow(MaterialItem m) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _MaterialRow(
          material: m,
          onToggleCovered: (value) =>
              context.read<MaterialRepository>().setCovered(m.id, m.moduleId, value),
          onDelete: () => _deleteMaterial(m),
          onOpen: m.hasViewablePdf ||
                  (m.hasRemotePdf && context.watch<SettingsRepository>().settings.pdfStorage.isConfigured)
              ? () => _openMaterial(m)
              : null,
          onRecognizeText:
              m.hasViewablePdf && m.kind != MaterialKind.condensed && context.watch<SettingsRepository>().settings.hasApiKey
                  ? () => _recognizeScannedPages(m)
                  : null,
          onCondense: m.kind == MaterialKind.slide ? () => _condense(m) : null,
          onShowText: m.kind == MaterialKind.condensed ? () => showCondensedTextDialog(context, m) : null,
          onImportQuestions: m.hasViewablePdf && m.kind != MaterialKind.condensed && m.fileName.toLowerCase().endsWith('.pdf')
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PdfQuestionImportScreen(moduleId: m.moduleId, material: m),
                    ),
                  )
              : null,
          onInteractiveTasks:
              m.hasViewablePdf && m.kind != MaterialKind.condensed && m.fileName.toLowerCase().endsWith('.pdf')
                  ? () => _openInteractive([m])
                  : null,
          onAttachPdf: !m.hasViewablePdf && !m.hasRemotePdf && m.fileName.toLowerCase().endsWith('.pdf')
              ? () => _attachPdf(m)
              : null,
        ),
      );

  /// Öffnet "Kürzen" – mit [lecture] vorgewählt, falls angegeben.
  Future<void> _condense([MaterialItem? lecture]) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CondenseScreen(moduleId: widget.moduleId, lectureId: lecture?.id),
        ),
      );

  /// Legt die Original-PDF zu einem früher nur als Text gespeicherten
  /// Material nach (z.B. Übungen, deren PDF bisher nicht aufbewahrt wurde) –
  /// danach lässt es sich ansehen und seitenweise importieren.
  Future<void> _attachPdf(MaterialItem material) async {
    final repo = context.read<MaterialRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (picked.isEmpty) return;
    try {
      final bytes = await picked.first.readAsBytes();
      final (filePath, fileBytesBase64) = await MaterialFileStore.store(material.id, bytes);
      await repo.save(MaterialItem.fromMap({
        ...material.toMap(),
        'filePath': filePath,
        'fileBytesBase64': fileBytesBase64,
      }));
      messenger.showSnackBar(SnackBar(content: Text('PDF zu „${material.fileName}“ hinzugefügt.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('PDF konnte nicht gespeichert werden: $e')));
    }
  }

  /// Fragt einen Einheit-Titel ab (z.B. für "+ Neue Einheit anlegen" beim
  /// Hochladen). Schlägt "Einheit N" als Vorgabe vor. Null bei Abbruch.
  Future<String?> _promptUnitTitle() async {
    final existingCount = context.read<LectureUnitRepository>().forModule(widget.moduleId).length;
    final controller = TextEditingController(text: 'Einheit ${existingCount + 1}');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neue Einheit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Titel'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    return (title == null || title.isEmpty) ? null : title;
  }

  Future<void> _createUnit() async {
    final title = await _promptUnitTitle();
    if (title == null || !mounted) return;
    await context.read<LectureUnitRepository>().save(LectureUnit(
          id: const Uuid().v4(),
          moduleId: widget.moduleId,
          title: title,
          createdAt: DateTime.now(),
        ));
  }

  bool _suggestingUnits = false;

  Future<void> _pickUnitDate(LectureUnit unit) async {
    final repo = context.read<LectureUnitRepository>();
    // Entfernen nur als ausdrückliche Wahl – früher hieß "Abbrechen" im
    // Datumsdialog "Termin entfernen", schon ein Tippen daneben oder
    // "Zurück" löschte den Termin.
    if (unit.scheduledDate != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Termin: ${_formatDay(unit.scheduledDate!)}'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop('change'), child: const Text('Termin ändern')),
            SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop('remove'), child: const Text('Termin entfernen')),
          ],
        ),
      );
      if (action == 'remove') await repo.setScheduledDate(unit.id, unit.moduleId, null);
      if (action != 'change' || !mounted) return;
    }
    final now = DateTime.now();
    final initial = unit.scheduledDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(min(now.year, initial.year) - 2),
      lastDate: DateTime(max(now.year, initial.year) + 2),
      helpText: 'Vorlesungstermin – ab dann gilt die Einheit als behandelt',
    );
    if (picked != null) await repo.setScheduledDate(unit.id, unit.moduleId, picked);
  }

  Future<void> _assignDatesFromSchedule(Module module, List<LectureUnit> units) async {
    final updated = UnitScheduleService().assignLectureDates(units: units, module: module, from: DateTime.now());
    if (updated.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Keine offenen Einheiten oder keine kommenden Vorlesungstermine im Stundenplan.'),
      ));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Termine übernehmen?'),
        content: Text(
          'Die ${updated.length} noch offenen Einheiten bekommen der Reihe nach die nächsten '
          'Vorlesungstermine:\n\n'
          '${updated.map((u) => '• ${u.title}: ${_formatDay(u.scheduledDate!)}').join('\n')}\n\n'
          'Ab ihrem Termin gelten sie automatisch als behandelt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Übernehmen')),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<LectureUnitRepository>().saveAll(updated);
  }

  static String _formatDay(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

  /// KI ordnet die bisher keiner Einheit zugeordneten Materialien zu
  /// Einheiten; der Vorschlag wird vor dem Übernehmen gezeigt.
  Future<void> _suggestUnits(List<MaterialItem> materials, List<LectureUnit> units) async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return;
    final unitIds = {for (final u in units) u.id};
    final unassigned = materials
        .where((m) => m.kind != MaterialKind.condensed && (m.unitId == null || !unitIds.contains(m.unitId)))
        .toList();
    if (unassigned.isEmpty) return;
    setState(() => _suggestingUnits = true);
    List<({String title, List<String> materialIds})> suggestions;
    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      suggestions = await ai.suggestLectureUnits([
        for (final m in unassigned)
          (
            id: m.id,
            fileName: m.fileName,
            kind: m.kind.name,
            excerpt: (m.topicIndex?.trim().isNotEmpty ?? false) ? m.topicIndex! : m.extractedText,
          ),
      ]);
    } catch (e) {
      if (mounted) {
        setState(() => _suggestingUnits = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is AiServiceException ? e.message : 'Vorschlag fehlgeschlagen: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _suggestingUnits = false);
    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Die KI hat keine sinnvollen Einheiten gefunden.')));
      return;
    }
    final chosen = await showDialog<List<({String title, List<String> materialIds})>>(
      context: context,
      builder: (_) => _UnitSuggestionDialog(
        suggestions: suggestions,
        fileNameById: {for (final m in unassigned) m.id: m.fileName},
      ),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    final unitRepo = context.read<LectureUnitRepository>();
    final materialRepo = context.read<MaterialRepository>();
    final base = DateTime.now();
    final newUnits = <LectureUnit>[];
    for (var i = 0; i < chosen.length; i++) {
      newUnits.add(LectureUnit(
        id: const Uuid().v4(),
        moduleId: widget.moduleId,
        title: chosen[i].title,
        // Aufsteigend, damit die Reihenfolge der Vorschläge erhalten bleibt
        // (Einheiten werden nach createdAt sortiert).
        createdAt: base.add(Duration(milliseconds: i)),
      ));
    }
    await unitRepo.saveAll(newUnits);
    for (var i = 0; i < chosen.length; i++) {
      await materialRepo.assignUnit(chosen[i].materialIds, widget.moduleId, newUnits[i].id);
    }
  }

  Future<void> _deleteUnit(LectureUnit unit) async {
    final ok = await confirmDelete(
      context,
      title: 'Einheit löschen?',
      message: '"${unit.title}" wird gelöscht. Zugeordnete Materialien/Karteikarten bleiben '
          'erhalten, verlieren aber die Zuordnung zu dieser Einheit (zählen dann wieder immer als '
          'verfügbar).',
    );
    if (ok && mounted) {
      final materialRepo = context.read<MaterialRepository>();
      final conceptRepo = context.read<ConceptRepository>();
      final flashcardRepo = context.read<FlashcardRepository>();
      final summaryRepo = context.read<SummaryRepository>();
      await context.read<LectureUnitRepository>().delete(unit.id, unit.moduleId);
      await materialRepo.loadForModule(unit.moduleId);
      await conceptRepo.loadForModule(unit.moduleId);
      await flashcardRepo.loadForModule(unit.moduleId);
      await summaryRepo.loadForModule(unit.moduleId);
    }
  }

  /// Fragt vor dem eigentlichen Hochladen ab, welcher Einheit die Datei(en)
  /// zugeordnet werden sollen. Gibt `null` zurück, wenn der Dialog
  /// abgebrochen wurde (Upload soll dann abbrechen); einen leeren String für
  /// "Keine Einheit" (Upload läuft normal weiter, nur ohne Zuordnung); sonst
  /// die (ggf. gerade neu angelegte) Einheit-ID.
  Future<String?> _pickUnit() async {
    final units = context.read<LectureUnitRepository>().forModule(widget.moduleId);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Welcher Einheit zuordnen?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: const Text('Keine Einheit'),
          ),
          for (final u in units)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(u.id),
              child: Text(u.title),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('_new'),
            child: const Text('+ Neue Einheit anlegen'),
          ),
        ],
      ),
    );
    if (choice == null || choice != '_new') return choice;

    if (!mounted) return null;
    final title = await _promptUnitTitle();
    if (title == null || !mounted) return null;
    final unit = LectureUnit(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      title: title,
      createdAt: DateTime.now(),
    );
    await context.read<LectureUnitRepository>().save(unit);
    return unit.id;
  }

  Future<MaterialKind?> _pickKind() => showDialog<MaterialKind>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Was lädst du hoch?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(MaterialKind.slide),
              child: const Text('Folien'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(MaterialKind.exercise),
              child: const Text('Übungsaufgaben'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(MaterialKind.practiceExam),
              child: const Text('Übungsklausur (Stil-Referenz für die KI)'),
            ),
          ],
        ),
      );

  /// "Interaktive Aufgaben aus PDF" mit diesen Materialien vorgewählt.
  Future<void> _openInteractive(List<MaterialItem> materials) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfQuestionImportScreen(moduleId: widget.moduleId, materials: materials, interactive: true),
        ),
      );

  Future<void> _uploadMaterials() async {
    final kind = await _pickKind();
    if (kind == null || !mounted) return;

    final unitChoice = await _pickUnit();
    if (unitChoice == null || !mounted) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: MaterialTextExtractor.supportedExtensions,
    );
    if (picked.isEmpty || !mounted) return;

    await _processFiles(
      kind: kind,
      unitId: unitChoice.isEmpty ? null : unitChoice,
      files: picked.map((f) => (name: f.name, readBytes: f.readAsBytes)).toList(),
    );
  }

  /// Per Drag-and-Drop auf den Bildschirm gezogene Dateien (Windows/macOS/
  /// Linux/Web – auf Mobile ohne Wirkung, da OS-Drag-and-Drop von
  /// Dateien dort keine gängige Interaktion ist). Fragt dieselben Angaben
  /// ab wie der normale Upload-Button (Kind + Einheit), dann derselbe
  /// Verarbeitungsweg wie beim Datei-Picker.
  Future<void> _handleDroppedFiles(List<XFile> files) async {
    if (files.isEmpty || !mounted) return;
    final kind = await _pickKind();
    if (kind == null || !mounted) return;

    final unitChoice = await _pickUnit();
    if (unitChoice == null || !mounted) return;

    await _processFiles(
      kind: kind,
      unitId: unitChoice.isEmpty ? null : unitChoice,
      files: files.map((f) => (name: f.name, readBytes: f.readAsBytes)).toList(),
    );
  }

  Future<void> _processFiles({
    required MaterialKind kind,
    required String? unitId,
    required List<({String name, Future<Uint8List> Function() readBytes})> files,
  }) async {
    final repo = context.read<MaterialRepository>();
    final ocr = PdfOcrService.fromSettings(context.read<SettingsRepository>().settings);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errors = <String>[];
    final pdfs = <MaterialItem>[];
    for (final file in files) {
      try {
        final Uint8List bytes = await file.readBytes();
        final text = await MaterialTextExtractor()
            .extractTextWithOcr(file.name, bytes, ocr: ocr, onProgress: ocrStartNotice(messenger, file.name));
        if (text.isEmpty) {
          errors.add(ocr == null
              ? '${file.name}: kein Text gefunden (gescannt? Mit API-Key wird der Text automatisch erkannt).'
              : '${file.name}: kein Text gefunden.');
          continue;
        }
        final id = const Uuid().v4();
        // Original-PDF-Bytes zusätzlich speichern (Folien, Übungen und
        // Übungsklausuren) – Grundlage für die Ansicht in
        // MaterialViewerScreen und für den seitenweisen Fragen-Import mit
        // Abbildungen. Andere Formate bleiben rein textbasiert.
        String? filePath;
        String? fileBytesBase64;
        if (file.name.toLowerCase().endsWith('.pdf')) {
          (filePath, fileBytesBase64) = await MaterialFileStore.store(id, bytes);
        }
        final material = MaterialItem(
          id: id,
          moduleId: widget.moduleId,
          fileName: file.name,
          kind: kind,
          extractedText: text,
          createdAt: DateTime.now(),
          filePath: filePath,
          fileBytesBase64: fileBytesBase64,
          unitId: unitId,
        );
        await repo.save(material);
        if (material.hasViewablePdf) pdfs.add(material);
        if (!mounted) return;
      } catch (e) {
        errors.add('${file.name}: $e');
      }
    }
    if (!mounted) return;
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errors.join('\n'))));
    } else if (pdfs.isNotEmpty) {
      // Gleich anbieten, die Aufgaben darin interaktiv zu machen.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(pdfs.length == 1 ? '„${pdfs.single.fileName}“ hochgeladen.' : '${pdfs.length} PDFs hochgeladen.'),
        action: SnackBarAction(
          key: const ValueKey('upload-interactive'),
          label: 'Interaktive Aufgaben',
          onPressed: () {
            if (mounted) _openInteractive(pdfs);
          },
        ),
      ));
    }
  }

  /// Texterkennung nachträglich für alle Seiten ohne Text-Ebene (z.B. einzelne
  /// eingescannte Seiten in einem sonst normalen Skript).
  Future<void> _recognizeScannedPages(MaterialItem material) async {
    final messenger = ScaffoldMessenger.of(context);
    final ocr = PdfOcrService.fromSettings(context.read<SettingsRepository>().settings);
    final repo = context.read<MaterialRepository>();
    if (ocr == null) return;
    final bytes = await MaterialFileStore.load(filePath: material.filePath, fileBytesBase64: material.fileBytesBase64);
    if (bytes == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Die PDF liegt auf diesem Gerät nicht vor.')));
      return;
    }
    final pages = PdfService().extractPageTexts(bytes);
    final groups = PdfOcrService.pagesNeedingOcr(pages);
    if (groups.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Alle Seiten haben bereits Text – nichts zu erkennen.')));
      return;
    }
    if (!mounted) return;
    final emptyCount = groups.fold<int>(0, (sum, g) => sum + g.length);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Texterkennung starten?'),
        content: Text('$emptyCount von ${pages.length} Seiten haben keinen Text (gescannt/Bild). '
            'Sie werden per KI (Vision-Modell) abgeschrieben – dafür fallen beim Anbieter Kosten an.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Erkennen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final text = await ocr.recognize(bytes, pages, onProgress: ocrStartNotice(messenger, material.fileName));
      await repo.setExtractedText(material.id, material.moduleId, text);
      messenger.showSnackBar(SnackBar(content: Text('Text für „${material.fileName}“ aktualisiert.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e is AiServiceException ? e.message : 'Texterkennung fehlgeschlagen: $e'),
      ));
    }
  }

  Future<void> _openMaterial(MaterialItem material) => openMaterialAt(context, material);

  /// Folgt dem Quasi-Link eines im Lernmodus erstellten Konzepts (siehe
  /// Concept.linkedMaterialId/linkedPageNumber) zurück zu genau der Seite,
  /// auf der es entstanden ist.
  Future<void> _openConceptSourcePage(Concept concept, List<MaterialItem> materials) async {
    MaterialItem? material;
    for (final m in materials) {
      if (m.id == concept.linkedMaterialId) {
        material = m;
        break;
      }
    }
    final storageReady = context.read<SettingsRepository>().settings.pdfStorage.isConfigured;
    if (material == null || !(material.hasViewablePdf || (material.hasRemotePdf && storageReady))) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Quell-Material nicht mehr verfügbar.')));
      return;
    }
    await openMaterialAt(context, material, page: concept.linkedPageNumber);
  }

  Future<void> _deleteMaterial(MaterialItem material) async {
    final ok = await confirmDelete(
      context,
      title: 'Material löschen?',
      message: '"${material.fileName}" wird endgültig gelöscht.',
    );
    if (ok && mounted) {
      // Alles vor dem ersten await lesen und erst den Datensatz löschen, dann
      // die Datei – sonst bliebe beim Verlassen des Screens dazwischen ein
      // Material stehen, dessen PDF schon weg ist.
      final store = PdfCloudStore.fromConfig(context.read<SettingsRepository>().settings.pdfStorage);
      final repo = context.read<MaterialRepository>();
      await repo.delete(material.id, material.moduleId);
      await MaterialFileStore.delete(filePath: material.filePath);
      final remoteKey = material.remotePdfKey;
      if (store != null && remoteKey != null) await PdfCloudSyncService(store).deleteRemote([remoteKey]);
    }
  }

  Future<void> _editConcept(Concept concept) async {
    final result = await editTwoFieldsDialog(
      context,
      title: 'Konzept bearbeiten',
      label1: 'Titel',
      initial1: concept.title,
      label2: 'Erklärung',
      initial2: concept.explanation,
    );
    if (result == null || !mounted) return;
    final (title, explanation) = result;
    await context.read<ConceptRepository>().saveAll([
      Concept(
        id: concept.id,
        moduleId: concept.moduleId,
        title: title,
        explanation: explanation,
        sourceMaterialIds: concept.sourceMaterialIds,
        createdAt: concept.createdAt,
        unitId: concept.unitId,
        linkedMaterialId: concept.linkedMaterialId,
        linkedPageNumber: concept.linkedPageNumber,
      ),
    ]);
  }

  Future<void> _deleteConcept(Concept concept) async {
    final ok = await confirmDelete(
      context,
      title: 'Konzept löschen?',
      message: '"${concept.title}" wird endgültig gelöscht.',
    );
    if (ok && mounted) {
      await context.read<ConceptRepository>().delete(concept.id, concept.moduleId);
    }
  }

  /// Exportiert dieses Fach (Modul + Einheiten + Materialien inkl. PDF-
  /// Bytes + Zusammenfassungen + Konzepte + Karteikarten) als eigenständige JSON-Datei zum
  /// Sichern/Weitergeben – unabhängig vom (Firebase-basierten) Cloud-Sync,
  /// siehe ModuleExportService. Nutzt denselben plattformübergreifenden
  /// Speichern-Dialog wie file_picker ihn schon fürs Hochladen bereitstellt.
  Future<void> _exportModule(
    Module module,
    List<LectureUnit> units,
    List<MaterialItem> materials,
    List<Concept> concepts,
    List<Flashcard> flashcards,
    List<Summary> summaries,
  ) async {
    final materialsWithBytes = await ModuleExportService.embedBytes(materials);
    if (!mounted) return;
    final payload = ModuleExportService.buildPayload(
      module: module,
      lectureUnits: units,
      materialsWithBytes: materialsWithBytes,
      concepts: concepts,
      flashcards: flashcards,
      summaries: summaries,
      labExperiments: context.read<LabExperimentRepository?>()?.forModule(module.id) ?? const [],
    );
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final safeName = module.name.replaceAll(RegExp(r'[^\w\säöüÄÖÜß-]'), '').trim();
    final fileName = '${safeName.isEmpty ? 'Fach' : safeName}.json';
    try {
      final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: 'application/json');
      if (!mounted) return;
      if (uri != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fach exportiert.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fach löschen?'),
        content: Text('"$name" inkl. aller Materialien, Konzepte und Karteikarten wird endgültig gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final store = PdfCloudStore.fromConfig(context.read<SettingsRepository>().settings.pdfStorage);
      final remoteKeys = [
        for (final m in context.read<MaterialRepository>().forModule(id))
          if (m.remotePdfKey != null) m.remotePdfKey!,
      ];
      await context.read<ModuleRepository>().delete(id);
      if (store != null && remoteKeys.isNotEmpty) await PdfCloudSyncService(store).deleteRemote(remoteKeys);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: c.ink),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: c.accent),
              ),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 12, height: 1.4, color: c.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftRow extends StatelessWidget {
  const _SoftRow({required this.icon, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: c.inkMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, size: 16, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.material,
    required this.onToggleCovered,
    required this.onDelete,
    this.onOpen,
    this.onRecognizeText,
    this.onImportQuestions,
    this.onInteractiveTasks,
    this.onAttachPdf,
    this.onCondense,
    this.onShowText,
  });
  final MaterialItem material;
  final ValueChanged<bool> onToggleCovered;
  final VoidCallback onDelete;
  final VoidCallback? onOpen;
  final VoidCallback? onRecognizeText;
  final VoidCallback? onImportQuestions;
  final VoidCallback? onInteractiveTasks;
  final VoidCallback? onAttachPdf;
  final VoidCallback? onCondense;
  final VoidCallback? onShowText;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: Icon(
                  switch (material.kind) {
                    MaterialKind.slide => Icons.slideshow_outlined,
                    MaterialKind.exercise => Icons.assignment_outlined,
                    MaterialKind.practiceExam => Icons.school_outlined,
                    MaterialKind.condensed => Icons.content_cut,
                  },
                  size: 16,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      switch (material.kind) {
                        MaterialKind.slide => material.highlights.isNotEmpty
                            ? 'Folien · ${material.highlights.length} markiert'
                            : 'Folien',
                        MaterialKind.exercise => 'Übungsaufgabe',
                        MaterialKind.practiceExam => 'Übungsklausur (Stil-Referenz)',
                        MaterialKind.condensed => material.condensed == null
                            ? 'Gekürzt'
                            : 'Gekürzt · ${material.condensed!.shareText} · aus ${material.condensed!.sourceName}',
                      },
                      style: TextStyle(fontSize: 12, color: c.inkMuted),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Behandelt', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                  Checkbox(
                    value: material.covered,
                    onChanged: (v) => onToggleCovered(v ?? false),
                  ),
                  // Seltenere Aktionen im Menü – nebeneinander wird die Zeile
                  // auf dem Handy zu schmal für den Dateinamen.
                  if (onImportQuestions != null ||
                      onInteractiveTasks != null ||
                      onRecognizeText != null ||
                      onAttachPdf != null ||
                      onCondense != null ||
                      onShowText != null)
                    PopupMenuButton<VoidCallback>(
                      tooltip: 'Weitere Aktionen',
                      icon: Icon(Icons.more_vert, size: 18, color: c.inkMuted),
                      onSelected: (action) => action(),
                      itemBuilder: (_) => [
                        if (onCondense != null)
                          PopupMenuItem(
                            value: onCondense,
                            child: const ListTile(
                              leading: Icon(Icons.content_cut),
                              title: Text('Kürzen …'),
                              subtitle: Text('Nur, was für Übungsaufgaben nötig ist'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        if (onShowText != null)
                          PopupMenuItem(
                            value: onShowText,
                            child: const ListTile(
                              leading: Icon(Icons.notes),
                              title: Text('Text ansehen und kopieren'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        if (onImportQuestions != null)
                          PopupMenuItem(
                            value: onImportQuestions,
                            child: const ListTile(
                              leading: Icon(Icons.manage_search),
                              title: Text('Fragen daraus importieren'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        if (onInteractiveTasks != null)
                          PopupMenuItem(
                            key: ValueKey('material-interactive-${material.id}'),
                            value: onInteractiveTasks,
                            child: const ListTile(
                              leading: Icon(Icons.touch_app_outlined),
                              title: Text('Interaktive Aufgaben daraus erstellen'),
                              subtitle: Text('z.B. alle Mathe-Aufgaben als Rechenweg'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        if (onAttachPdf != null)
                          PopupMenuItem(
                            value: onAttachPdf,
                            child: const ListTile(
                              leading: Icon(Icons.picture_as_pdf_outlined),
                              title: Text('Original-PDF hinzufügen'),
                              subtitle: Text('Zum Ansehen und Importieren'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        if (onRecognizeText != null)
                          PopupMenuItem(
                            value: onRecognizeText,
                            child: const ListTile(
                              leading: Icon(Icons.document_scanner_outlined),
                              title: Text('Texterkennung für gescannte Seiten'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: c.inkMuted,
                    onPressed: onDelete,
                  ),
                ],
              ),
              if (onOpen != null) Icon(Icons.chevron_right_rounded, size: 16, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zeigt eine Vorlesungseinheit samt Materialienzahl + "behandelt"-Toggle,
/// aufklappbar für freie Textnotizen (siehe [LectureUnit.notes]) – z.B.
/// eigene Zusammenfassung oder Merksätze direkt an der Einheit, statt nur in
/// der (an eine einzelne Datei gebundenen) Material-Notiz.
class _UnitRow extends StatefulWidget {
  const _UnitRow({
    required this.unit,
    required this.materialCount,
    required this.onToggleCovered,
    required this.onPickDate,
    required this.onDelete,
    required this.onNotesChanged,
  });
  final LectureUnit unit;
  final int materialCount;
  final ValueChanged<bool> onToggleCovered;
  final VoidCallback onPickDate;
  final VoidCallback onDelete;
  final ValueChanged<List<String>> onNotesChanged;

  @override
  State<_UnitRow> createState() => _UnitRowState();
}

class _UnitRowState extends State<_UnitRow> {
  bool _expanded = false;

  Future<void> _addNote() async {
    final text = await _promptNoteText();
    if (text == null || text.isEmpty) return;
    widget.onNotesChanged([...widget.unit.notes, text]);
  }

  Future<void> _editNote(int index) async {
    final text = await _promptNoteText(initial: widget.unit.notes[index]);
    if (text == null) return;
    final updated = List<String>.of(widget.unit.notes);
    if (text.isEmpty) {
      updated.removeAt(index);
    } else {
      updated[index] = text;
    }
    widget.onNotesChanged(updated);
  }

  Future<String?> _promptNoteText({String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? 'Textfeld hinzufügen' : 'Textfeld bearbeiten'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(hintText: 'Freier Text zu dieser Einheit …'),
        ),
        actions: [
          if (initial != null)
            TextButton(onPressed: () => Navigator.of(ctx).pop(''), child: const Text('Löschen')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unit = widget.unit;
    final date = unit.scheduledDate;
    final coveredNow = unit.isCoveredOn(DateTime.now());
    final subtitleParts = [
      if (date != null) 'Termin ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.',
      '${widget.materialCount} Material${widget.materialCount == 1 ? '' : 'ien'}',
      if (unit.notes.isNotEmpty) '${unit.notes.length} Textfeld${unit.notes.length == 1 ? '' : 'er'}',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unit.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(subtitleParts.join(' · '), style: TextStyle(fontSize: 12, color: c.inkMuted)),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Vorlesungstermin',
                      icon: Icon(date == null ? Icons.event_outlined : Icons.event_available_outlined, size: 18),
                      color: date == null ? c.inkMuted : c.accent,
                      onPressed: widget.onPickDate,
                    ),
                    Text('Behandelt', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                    Checkbox(
                      // Effektiver Stand: auch automatisch ab Termin.
                      value: coveredNow,
                      onChanged: (v) => widget.onToggleCovered(v ?? false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: c.inkMuted,
                      onPressed: widget.onDelete,
                    ),
                    IconButton(
                      icon: Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                      color: c.inkMuted,
                      onPressed: () => setState(() => _expanded = !_expanded),
                    ),
                  ],
                ),
              ],
            ),
            if (_expanded) ...[
              Divider(height: 1, color: c.border),
              const SizedBox(height: 10),
              ...unit.notes.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => _editNote(e.key),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                        child: Text(e.value, style: TextStyle(fontSize: 12.5, color: c.ink, height: 1.4)),
                      ),
                    ),
                  )),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton.icon(
                  onPressed: _addNote,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Textfeld hinzufügen'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Vorschau der KI-Einheitenvorschläge: Titel editierbar, einzelne
/// Vorschläge abwählbar.
class _UnitSuggestionDialog extends StatefulWidget {
  const _UnitSuggestionDialog({required this.suggestions, required this.fileNameById});

  final List<({String title, List<String> materialIds})> suggestions;
  final Map<String, String> fileNameById;

  @override
  State<_UnitSuggestionDialog> createState() => _UnitSuggestionDialogState();
}

class _UnitSuggestionDialogState extends State<_UnitSuggestionDialog> {
  late final List<TextEditingController> _titles =
      widget.suggestions.map((s) => TextEditingController(text: s.title)).toList();
  late final List<bool> _selected = List.filled(widget.suggestions.length, true);

  @override
  void dispose() {
    for (final c in _titles) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('Einheiten-Vorschlag'),
      content: SizedBox(
        width: 480,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < widget.suggestions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(value: _selected[i], onChanged: (v) => setState(() => _selected[i] = v ?? false)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(controller: _titles[i], decoration: const InputDecoration(isDense: true)),
                          const SizedBox(height: 4),
                          Text(
                            widget.suggestions[i].materialIds.map((id) => widget.fileNameById[id] ?? id).join(', '),
                            style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop([
            for (var i = 0; i < widget.suggestions.length; i++)
              if (_selected[i] && _titles[i].text.trim().isNotEmpty)
                (title: _titles[i].text.trim(), materialIds: widget.suggestions[i].materialIds),
          ]),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

class _MaterialGroupLabel extends StatelessWidget {
  const _MaterialGroupLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6, left: 2),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.colors.inkMuted),
      ),
    );
  }
}

/// Ampel-Aufschlüsselung der Karten eines Fachs nach FSRS-Wissensstand
/// (siehe MasteryService) – macht auf einen Blick sichtbar, wie viele Karten
/// gerade schwach/mittel/gut sitzen, statt nur "neu"/"in Wiederholung".
class _AmpelRow extends StatelessWidget {
  const _AmpelRow({required this.breakdown});
  final Map<MasteryLevel, int> breakdown;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final relevant = [MasteryLevel.red, MasteryLevel.yellow, MasteryLevel.green];
    if (relevant.every((l) => (breakdown[l] ?? 0) == 0)) return const SizedBox.shrink();
    return Row(
      children: relevant
          .map((level) => Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MasteryDot(level: level),
                    const SizedBox(width: 6),
                    Text('${breakdown[level] ?? 0}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Text(level.label, style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.value, required this.label, required this.fg, required this.bg});
  final int value;
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: fg)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: context.colors.inkMuted)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.04, color: c.inkMuted),
        ),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Text('($count)', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
        ],
      ],
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: TextStyle(color: context.colors.inkMuted, fontSize: 13)),
    );
  }
}
