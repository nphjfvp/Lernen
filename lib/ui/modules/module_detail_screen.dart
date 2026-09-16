import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/concept.dart';
import '../../models/lecture_unit.dart';
import '../../models/material_item.dart';
import '../../repositories/concept_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/summary_repository.dart';
import '../../services/material_file_store.dart';
import '../../services/material_text_extractor.dart';
import '../../services/mastery_service.dart';
import '../../theme/app_colors.dart';
import '../chat/module_chat_screen.dart';
import '../flashcards/flashcard_list_screen.dart';
import '../practice/practice_screen.dart';
import '../prepare/prepare_screen.dart';
import '../prepare/summary_detail_screen.dart';
import '../review/review_screen.dart';
import '../speedrun/speedrun_screen.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/edit_text_dialog.dart';
import '../widgets/mastery_dot.dart';
import 'material_viewer_screen.dart';
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
                            subtitle: 'Folien + Übungen → Konzepte & Karten',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ReviewScreen(moduleId: module.id)),
                            ),
                          ),
                        ),
                      ],
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
                      icon: Icons.bolt_outlined,
                      title: 'Speedrun (Nachbereiten)',
                      subtitle: 'Schneller Durchlauf durch alle Konzepte – Fehler werden danach vertieft',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SpeedrunScreen(moduleId: module.id, moduleName: module.name),
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
                      const _HintText('Noch keine Zusammenfassung – starte den Vorbereiten-Modus.')
                    else
                      ...summaries.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SoftRow(
                              icon: Icons.description_outlined,
                              title: s.title,
                              subtitle: '${s.keyPoints.length} Kernkonzepte',
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
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.surface,
                                border: Border.all(color: c.border),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                  title: Text(concept.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                                  iconColor: c.inkMuted,
                                  collapsedIconColor: c.inkMuted,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(concept.explanation, style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.5)),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
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
                              value: flashcards.where((card) => card.reps == 0).length,
                              label: 'neu',
                              fg: c.accentOnSoft,
                              bg: c.accentSoft,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatPill(
                              value: flashcards.where((card) => card.reps > 0).length,
                              label: 'in Wiederholung',
                              fg: c.good,
                              bg: c.goodSoft,
                            ),
                          ),
                        ],
                      ),
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
                    ],
                    const SizedBox(height: 20),
                    _SectionHeader(title: 'Einheiten', count: units.length),
                    const SizedBox(height: 6),
                    Text(
                      'Fasst Material zu einer Vorlesungssitzung zusammen. Du kannst ruhig den '
                      'ganzen Semesterstoff im Voraus hochladen – das Daily Quiz fragt trotzdem nur '
                      'Karten aus Einheiten ab, die du hier als "behandelt" markiert hast.',
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
                              onDelete: () => _deleteUnit(u),
                              onNotesChanged: (notes) =>
                                  context.read<LectureUnitRepository>().setNotes(u.id, u.moduleId, notes),
                            ),
                          )),
                    OutlinedButton.icon(
                      onPressed: _createUnit,
                      icon: const Icon(Icons.add),
                      label: const Text('Einheit anlegen'),
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(title: 'Materialien', count: materials.length),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _uploadMaterials,
                      icon: const Icon(Icons.add),
                      label: const Text('Material hochladen'),
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
                      if (materials.any((m) => m.unitId == null)) ...[
                        if (units.isNotEmpty) const _MaterialGroupLabel('Ohne Einheit'),
                        ...materials.where((m) => m.unitId == null).map(_materialRow),
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
          onOpen: m.hasViewablePdf ? () => _openMaterial(m) : null,
        ),
      );

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

  Future<void> _deleteUnit(LectureUnit unit) async {
    final ok = await confirmDelete(
      context,
      title: 'Einheit löschen?',
      message: '"${unit.title}" wird gelöscht. Zugeordnete Materialien/Karteikarten bleiben '
          'erhalten, verlieren aber die Zuordnung zu dieser Einheit (zählen dann wieder immer als '
          'verfügbar).',
    );
    if (ok && mounted) {
      await context.read<LectureUnitRepository>().delete(unit.id, unit.moduleId);
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
    final errors = <String>[];
    for (final file in files) {
      try {
        final Uint8List bytes = await file.readBytes();
        final text = MaterialTextExtractor().extractText(file.name, bytes);
        if (text.isEmpty) {
          errors.add('${file.name}: kein Text gefunden.');
          continue;
        }
        final id = const Uuid().v4();
        // Original-PDF-Bytes zusätzlich speichern (für Folien UND
        // Übungsklausuren im PDF-Format) – Grundlage für die visuelle
        // Ansicht + Markier-Funktion in MaterialViewerScreen. Andere
        // Formate/Übungsaufgaben funktionieren wie bisher rein textbasiert.
        String? filePath;
        String? fileBytesBase64;
        final isPdfViewable =
            (kind == MaterialKind.slide || kind == MaterialKind.practiceExam) &&
                file.name.toLowerCase().endsWith('.pdf');
        if (isPdfViewable) {
          (filePath, fileBytesBase64) = await MaterialFileStore.store(id, bytes);
        }
        await repo.save(MaterialItem(
          id: id,
          moduleId: widget.moduleId,
          fileName: file.name,
          kind: kind,
          extractedText: text,
          createdAt: DateTime.now(),
          filePath: filePath,
          fileBytesBase64: fileBytesBase64,
          unitId: unitId,
        ));
        if (!mounted) return;
      } catch (e) {
        errors.add('${file.name}: $e');
      }
    }
    if (errors.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errors.join('\n'))));
    }
  }

  void _openMaterial(MaterialItem material) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MaterialViewerScreen(material: material)),
    );
  }

  Future<void> _deleteMaterial(MaterialItem material) async {
    final ok = await confirmDelete(
      context,
      title: 'Material löschen?',
      message: '"${material.fileName}" wird endgültig gelöscht.',
    );
    if (ok && mounted) {
      await MaterialFileStore.delete(filePath: material.filePath);
      if (!mounted) return;
      await context.read<MaterialRepository>().delete(material.id, material.moduleId);
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
      await context.read<ModuleRepository>().delete(id);
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
  const _MaterialRow({required this.material, required this.onToggleCovered, required this.onDelete, this.onOpen});
  final MaterialItem material;
  final ValueChanged<bool> onToggleCovered;
  final VoidCallback onDelete;
  final VoidCallback? onOpen;

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
    required this.onDelete,
    required this.onNotesChanged,
  });
  final LectureUnit unit;
  final int materialCount;
  final ValueChanged<bool> onToggleCovered;
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
    final subtitleParts = [
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
                    Text('Behandelt', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                    Checkbox(
                      value: unit.covered,
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
