import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/concept.dart';
import '../../models/material_item.dart';
import '../../repositories/concept_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/summary_repository.dart';
import '../../services/material_text_extractor.dart';
import '../../theme/app_colors.dart';
import '../chat/module_chat_screen.dart';
import '../flashcards/flashcard_list_screen.dart';
import '../prepare/prepare_screen.dart';
import '../prepare/summary_detail_screen.dart';
import '../review/review_screen.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/edit_text_dialog.dart';
import 'module_form_screen.dart';

class ModuleDetailScreen extends StatefulWidget {
  const ModuleDetailScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
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
    final days = module.daysUntilExam;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
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
                    else
                      ...materials.map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _MaterialRow(
                              material: m,
                              onToggleCovered: (value) =>
                                  context.read<MaterialRepository>().setCovered(m.id, m.moduleId, value),
                              onDelete: () => _deleteMaterial(m),
                            ),
                          )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadMaterials() async {
    final kind = await showDialog<MaterialKind>(
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
        ],
      ),
    );
    if (kind == null || !mounted) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: MaterialTextExtractor.supportedExtensions,
    );
    if (picked.isEmpty || !mounted) return;

    final repo = context.read<MaterialRepository>();
    final errors = <String>[];
    for (final file in picked) {
      try {
        final Uint8List bytes = await file.readAsBytes();
        final text = MaterialTextExtractor().extractText(file.name, bytes);
        if (text.isEmpty) {
          errors.add('${file.name}: kein Text gefunden.');
          continue;
        }
        await repo.save(MaterialItem(
          id: const Uuid().v4(),
          moduleId: widget.moduleId,
          fileName: file.name,
          kind: kind,
          extractedText: text,
          createdAt: DateTime.now(),
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

  Future<void> _deleteMaterial(MaterialItem material) async {
    final ok = await confirmDelete(
      context,
      title: 'Material löschen?',
      message: '"${material.fileName}" wird endgültig gelöscht.',
    );
    if (ok && mounted) {
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
  const _MaterialRow({required this.material, required this.onToggleCovered, required this.onDelete});
  final MaterialItem material;
  final ValueChanged<bool> onToggleCovered;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
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
                material.kind == MaterialKind.slide ? Icons.slideshow_outlined : Icons.assignment_outlined,
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
                    material.kind == MaterialKind.slide ? 'Folien' : 'Übungsaufgabe',
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
          ],
        ),
      ),
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
