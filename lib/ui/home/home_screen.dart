import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/module.dart';
import '../../repositories/module_repository.dart';
import '../../theme/app_colors.dart';
import '../modules/module_detail_screen.dart';
import '../modules/module_form_screen.dart';
import '../widgets/exam_countdown_badge.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = context.watch<ModuleRepository>().modules;
    final c = context.colors;

    return Material(
      color: c.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Meine Fächer', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    modules.isEmpty ? 'Noch keine Fächer' : '${modules.length} Fächer',
                    style: TextStyle(fontSize: 13, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: modules.isEmpty
                  ? _EmptyState(onCreate: () => _createModule(context))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 160),
                      itemCount: modules.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _ModuleTile(module: modules[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _createModule(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ModuleFormScreen()),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_rounded, size: 56, color: c.inkMuted),
            const SizedBox(height: 16),
            Text(
              'Noch keine Fächer angelegt.\nLege ein Fach an, um Folien und '
              'Übungsaufgaben zu sammeln und ein Klausurdatum zu setzen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Erstes Fach anlegen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});
  final Module module;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final softTint = Color.alphaBlend(module.color.withValues(alpha: 0.16), c.surface);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ModuleDetailScreen(moduleId: module.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: softTint, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text(module.icon, style: const TextStyle(fontSize: 19)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 7),
                    ExamCountdownBadge(daysUntilExam: module.daysUntilExam),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.inkMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
