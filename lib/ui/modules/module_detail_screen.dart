import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/material_item.dart';
import '../../repositories/concept_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/summary_repository.dart';
import '../prepare/prepare_screen.dart';
import '../prepare/summary_detail_screen.dart';
import '../review/review_screen.dart';
import '../widgets/exam_countdown_badge.dart';
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
    final module = context.watch<ModuleRepository>().byId(widget.moduleId);
    if (module == null) {
      return const Scaffold(body: Center(child: Text('Fach nicht gefunden.')));
    }
    final materials = context.watch<MaterialRepository>().forModule(widget.moduleId);
    final summaries = context.watch<SummaryRepository>().forModule(widget.moduleId);
    final concepts = context.watch<ConceptRepository>().forModule(widget.moduleId);
    final flashcards = context.watch<FlashcardRepository>().forModule(widget.moduleId);

    return Scaffold(
      appBar: AppBar(
        title: Text(module.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ModuleFormScreen(existing: module)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, module.id, module.name),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Klausur', style: Theme.of(context).textTheme.titleMedium),
                ExamCountdownBadge(daysUntilExam: module.daysUntilExam),
              ],
            ),
            const SizedBox(height: 16),
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
                    icon: Icons.psychology_outlined,
                    title: 'Nachbereiten',
                    subtitle: 'Folien + Übungen → Konzepte & Karten',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ReviewScreen(moduleId: module.id)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionHeader(title: 'Zusammenfassungen', count: summaries.length),
            if (summaries.isEmpty)
              const _HintText('Noch keine Zusammenfassung – starte den Vorbereiten-Modus.')
            else
              ...summaries.map((s) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(s.title),
                      subtitle: Text('${s.keyPoints.length} Kernkonzepte'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SummaryDetailScreen(summary: s)),
                      ),
                    ),
                  )),
            const SizedBox(height: 24),
            _SectionHeader(title: 'Lernkonzepte', count: concepts.length),
            if (concepts.isEmpty)
              const _HintText('Noch keine Konzepte – starte den Nachbereiten-Modus.')
            else
              ...concepts.map((c) => Card(
                    child: ExpansionTile(
                      title: Text(c.title),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(c.explanation),
                          ),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 24),
            _SectionHeader(title: 'Karteikarten', count: flashcards.length),
            if (flashcards.isEmpty)
              const _HintText('Noch keine Karteikarten – entstehen automatisch im Nachbereiten-Modus.')
            else
              _HintText(
                '${flashcards.where((c) => c.reps == 0).length} neu · '
                '${flashcards.where((c) => c.reps > 0).length} in Wiederholung',
              ),
            const SizedBox(height: 24),
            _SectionHeader(title: 'Materialien', count: materials.length),
            if (materials.isEmpty)
              const _HintText('Noch keine Dateien hochgeladen.')
            else
              ...materials.map((m) => ListTile(
                    leading: Icon(m.kind == MaterialKind.slide
                        ? Icons.slideshow_outlined
                        : Icons.assignment_outlined),
                    title: Text(m.fileName),
                    subtitle: Text(m.kind == MaterialKind.slide ? 'Folien' : 'Übungsaufgabe'),
                  )),
          ],
        ),
      ),
    );
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          if (count > 0)
            Text('($count)', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
    );
  }
}
