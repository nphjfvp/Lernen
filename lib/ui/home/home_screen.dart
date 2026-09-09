import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/module.dart';
import '../../repositories/module_repository.dart';
import '../modules/module_detail_screen.dart';
import '../modules/module_form_screen.dart';
import '../widgets/exam_countdown_badge.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = context.watch<ModuleRepository>().modules;

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Fächer')),
      body: modules.isEmpty
          ? _EmptyState(onCreate: () => _createModule(context))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: modules.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _ModuleTile(module: modules[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createModule(context),
        icon: const Icon(Icons.add),
        label: const Text('Neues Fach'),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Noch keine Fächer angelegt.\nLege ein Fach an, um Folien und '
              'Übungsaufgaben zu sammeln und ein Klausurdatum zu setzen.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
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
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: module.color,
          child: Text(module.icon, style: const TextStyle(fontSize: 18)),
        ),
        title: Text(module.name),
        trailing: ExamCountdownBadge(daysUntilExam: module.daysUntilExam),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ModuleDetailScreen(moduleId: module.id)),
        ),
      ),
    );
  }
}
