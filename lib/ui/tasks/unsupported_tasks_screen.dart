import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/unsupported_task.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/unsupported_task_repository.dart';
import '../../services/ai_service.dart';
import '../../services/plain_question_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/confirm_delete_dialog.dart';
import 'task_import_screen.dart';

/// Sammelliste „Noch nicht interaktiv“: Übungsaufgaben, die die App (noch)
/// nicht selbst prüfen kann – gruppiert nach der Bedienart, die fehlt. Die
/// Liste lässt sich als Text kopieren und weiterschicken, damit man sieht,
/// welche Aufgabentypen als Nächstes am meisten bringen. „Fragen dazu
/// erstellen“ legt die Aufgaben trotzdem als (nicht interaktive) Karten an –
/// meist als Lernaufgabe mit Lösungsweg, wie beim Fragen-Import.
class UnsupportedTasksScreen extends StatefulWidget {
  const UnsupportedTasksScreen({super.key, this.moduleId, this.moduleName = ''});

  /// null = alle Fächer.
  final String? moduleId;
  final String moduleName;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  @override
  State<UnsupportedTasksScreen> createState() => _UnsupportedTasksScreenState();
}

class _UnsupportedTasksScreenState extends State<UnsupportedTasksScreen> {
  /// Fach-Filter (null = alle Fächer), vorbelegt mit [UnsupportedTasksScreen.moduleId].
  late String? _filter = widget.moduleId;

  String get _filterName => _filter == null
      ? ''
      : (_filter == widget.moduleId && widget.moduleName.isNotEmpty ? widget.moduleName : _moduleName(_filter!));

  /// Aufgaben, zu denen gerade Fragen erstellt werden.
  final Set<String> _creating = {};
  String? _progress;
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
      title: _filter == null ? 'alle Fächer' : _filterName,
      moduleName: _filter == null ? _moduleName : null,
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
    await context.read<UnsupportedTaskRepository>().clear(moduleId: _filter);
  }

  /// Legt zu [tasks] Karten an (eine KI-Anfrage je Aufgabe, damit Quelle und
  /// Zuordnung stimmen) und merkt sie an der Aufgabe.
  Future<void> _createCards(List<UnsupportedTask> tasks) async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return _snack('Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
    final ai =
        UnsupportedTasksScreen.aiFactory?.call(settings.openRouterApiKey!, settings.questionModelId) ??
        AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
    final cardsRepo = context.read<FlashcardRepository>();
    final list = context.read<UnsupportedTaskRepository>();
    setState(() => _creating.addAll(tasks.map((t) => t.id)));
    var created = 0, failed = 0;
    try {
      for (final (i, t) in tasks.indexed) {
        if (tasks.length > 1) setState(() => _progress = 'Fragen werden erstellt … ${i + 1} von ${tasks.length}');
        try {
          final cards = await PlainQuestionService.build(
            ai,
            text: t.text,
            moduleId: t.moduleId,
            sourceMaterialId: t.sourceMaterialId,
            sourcePage: t.sourcePage,
          );
          if (cards.isEmpty) {
            failed++;
            continue;
          }
          await cardsRepo.saveAll(cards);
          await list.markCards(t.id, [for (final c in cards) c.id]);
          created += cards.length;
        } catch (_) {
          failed++;
        } finally {
          if (mounted) setState(() => _creating.remove(t.id));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _creating.clear();
          _progress = null;
        });
      }
    }
    if (!mounted) return;
    _snack(
      [
        if (created > 0)
          created == 1
              ? '1 Frage erstellt – sie kommt bald im Lernplan dran.'
              : '$created Fragen erstellt – sie kommen bald im Lernplan dran.',
        if (failed > 0) '$failed ${failed == 1 ? 'Aufgabe ging' : 'Aufgaben gingen'} nicht – bitte erneut versuchen.',
      ].join(' '),
    );
  }

  Future<void> _retry(UnsupportedTask t) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TaskImportScreen(
        moduleId: t.moduleId,
        moduleName: _moduleName(t.moduleId).isNotEmpty ? _moduleName(t.moduleId) : widget.moduleName,
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
    final tasks = _filter == null ? repo.all : repo.forModule(_filter!);
    final modules = <String, int>{};
    for (final t in repo.all) {
      modules[t.moduleId] = (modules[t.moduleId] ?? 0) + 1;
    }
    final groups = UnsupportedTask.grouped(tasks);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Noch nicht interaktiv', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(_filter == null ? 'Alle Fächer' : _filterName, style: TextStyle(fontSize: 12, color: c.inkMuted)),
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
                  'welche Aufgabentypen als Nächstes am meisten bringen. Mit „Fragen dazu erstellen“ kommen sie '
                  'trotzdem ins Lernen – als normale Fragen bzw. Lernaufgaben mit Lösungsweg, ohne Prüfung durch die App.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
                ),
                const SizedBox(height: 12),
                if (modules.length > 1 || (_filter != null && modules.keys.any((m) => m != _filter))) ...[
                  Wrap(
                    key: const ValueKey('unsupported-filter'),
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: Text('Alle Fächer (${repo.all.length})'),
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      for (final e in modules.entries)
                        ChoiceChip(
                          key: ValueKey('unsupported-filter-${e.key}'),
                          label: Text('${_moduleName(e.key).isEmpty ? 'Fach' : _moduleName(e.key)} (${e.value})'),
                          selected: _filter == e.key,
                          onSelected: (_) => setState(() => _filter = e.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('unsupported-copy-button'),
                        onPressed: () => _copy(tasks),
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: Text('Liste kopieren (${tasks.length})'),
                      ),
                      if (tasks.any((t) => !t.hasCards))
                        OutlinedButton.icon(
                          key: const ValueKey('unsupported-create-all'),
                          onPressed: _creating.isNotEmpty
                              ? null
                              : () => _createCards([
                                  for (final t in tasks)
                                    if (!t.hasCards) t,
                                ]),
                          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                          label: Text('Fragen dazu erstellen (${tasks.where((t) => !t.hasCards).length})'),
                        ),
                    ],
                  ),
                  if (_progress != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_progress!, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                          ),
                        ],
                      ),
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
      if (_filter == null && _moduleName(t.moduleId).isNotEmpty) _moduleName(t.moduleId),
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
              if (_creating.contains(t.id))
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (t.hasCards)
                Padding(
                  key: ValueKey('unsupported-created-${t.id}'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '✓ ${t.cardIds.length == 1 ? 'Frage' : '${t.cardIds.length} Fragen'} erstellt',
                    style: TextStyle(fontSize: 12, color: c.good, fontWeight: FontWeight.w600),
                  ),
                )
              else
                TextButton(
                  key: ValueKey('unsupported-create-${t.id}'),
                  onPressed: _creating.isNotEmpty ? null : () => _createCards([t]),
                  child: const Text('Frage erstellen'),
                ),
              TextButton(
                key: ValueKey('unsupported-retry-${t.id}'),
                onPressed: () => _retry(t),
                child: const Text('Interaktiv versuchen'),
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
