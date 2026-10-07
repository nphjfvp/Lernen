import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/unsupported_task.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/unsupported_task_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/confirm_delete_dialog.dart';
import 'task_import_screen.dart';

/// Sammelliste „Noch nicht interaktiv“: Übungsaufgaben, die die App (noch)
/// nicht selbst prüfen kann – gruppiert nach der Bedienart, die fehlt. Die
/// Liste lässt sich als Text kopieren und weiterschicken, damit man sieht,
/// welche Aufgabentypen als Nächstes am meisten bringen.
class UnsupportedTasksScreen extends StatefulWidget {
  const UnsupportedTasksScreen({super.key, this.moduleId, this.moduleName = ''});

  /// null = alle Fächer.
  final String? moduleId;
  final String moduleName;

  @override
  State<UnsupportedTasksScreen> createState() => _UnsupportedTasksScreenState();
}

class _UnsupportedTasksScreenState extends State<UnsupportedTasksScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final repo = context.read<UnsupportedTaskRepository>();
      if (!repo.isLoaded) repo.load();
    });
  }

  String _moduleName(String id) => context.read<ModuleRepository?>()?.byId(id)?.name ?? '';

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _copy(List<UnsupportedTask> tasks) async {
    final text = UnsupportedTask.exportText(
      tasks,
      title: widget.moduleId == null ? 'alle Fächer' : widget.moduleName,
      moduleName: widget.moduleId == null ? _moduleName : null,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _snack('Liste kopiert – du kannst sie jetzt einfügen und schicken.');
  }

  Future<void> _clear(int count) async {
    final ok = await confirmDelete(
      context,
      title: 'Liste leeren?',
      message: count == 1
          ? 'Die Aufgabe wird von der Liste genommen.'
          : 'Alle $count Aufgaben werden von der Liste genommen.',
      confirmLabel: 'Alle löschen',
    );
    if (!ok || !mounted) return;
    await context.read<UnsupportedTaskRepository>().clear(moduleId: widget.moduleId);
  }

  Future<void> _retry(UnsupportedTask t) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TaskImportScreen(
        moduleId: t.moduleId,
        moduleName: widget.moduleId == null ? _moduleName(t.moduleId) : widget.moduleName,
        initialText: t.text,
        sourceMaterialId: t.sourceMaterialId,
        sourcePage: t.sourcePage,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final repo = context.watch<UnsupportedTaskRepository>();
    final tasks = widget.moduleId == null ? repo.all : repo.forModule(widget.moduleId!);
    final groups = UnsupportedTask.grouped(tasks);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Noch nicht interaktiv', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(
              widget.moduleId == null ? 'Alle Fächer' : widget.moduleName,
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
          ],
        ),
        actions: [
          if (tasks.isNotEmpty) ...[
            IconButton(
              key: const ValueKey('unsupported-copy'),
              tooltip: 'Als Text kopieren',
              onPressed: () => _copy(tasks),
              icon: const Icon(Icons.copy_all_outlined),
            ),
            IconButton(
              key: const ValueKey('unsupported-clear'),
              tooltip: 'Alle löschen',
              onPressed: () => _clear(tasks.length),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              children: [
                Text(
                  'Diese Aufgaben kann die App noch nicht selbst prüfen. Die KI sammelt sie beim „Aufgabe übernehmen“ '
                  'mit Begründung und der Bedienart, die fehlt. Kopier die Liste und schick sie weiter – dann sieht man, '
                  'welche Aufgabentypen als Nächstes am meisten bringen.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
                ),
                const SizedBox(height: 12),
                if (!repo.isLoaded)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (tasks.isEmpty)
                  Container(
                    key: const ValueKey('unsupported-empty'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Noch nichts gesammelt – alle übernommenen Aufgaben passten bisher.',
                      style: TextStyle(fontSize: 13, color: c.inkMuted),
                    ),
                  )
                else ...[
                  FilledButton.icon(
                    key: const ValueKey('unsupported-copy-button'),
                    onPressed: () => _copy(tasks),
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: Text('Liste kopieren (${tasks.length})'),
                  ),
                  for (final (gi, g) in groups.indexed) ...[
                    const SizedBox(height: 18),
                    Row(
                      key: ValueKey('unsupported-group-$gi'),
                      children: [
                        Expanded(
                          child: Text(g.group, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(10)),
                          child: Text(
                            '${g.tasks.length}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.warn),
                          ),
                        ),
                      ],
                    ),
                    for (final t in g.tasks) _entry(c, t),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _entry(AppColors c, UnsupportedTask t) {
    final where = [
      if (widget.moduleId == null && _moduleName(t.moduleId).isNotEmpty) _moduleName(t.moduleId),
      if (t.sourcePage != null) 'Seite ${t.sourcePage}',
      '${t.createdAt.day}.${t.createdAt.month}.${t.createdAt.year}',
    ].join(' · ');
    return Container(
      key: ValueKey('unsupported-${t.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              t.text,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
            ),
          ),
          if (t.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(t.reason, style: TextStyle(fontSize: 12.5, height: 1.35, color: c.inkMuted)),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text(where, style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
              ),
              TextButton(
                key: ValueKey('unsupported-retry-${t.id}'),
                onPressed: () => _retry(t),
                child: const Text('Erneut versuchen'),
              ),
              IconButton(
                key: ValueKey('unsupported-delete-${t.id}'),
                tooltip: 'Von der Liste nehmen',
                onPressed: () => context.read<UnsupportedTaskRepository>().delete(t.id),
                icon: Icon(Icons.close, size: 18, color: c.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
