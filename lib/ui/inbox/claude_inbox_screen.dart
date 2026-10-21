import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/module.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/claude_inbox.dart';
import '../../theme/app_colors.dart';
import '../tasks/task_import_screen.dart';

/// Claude-Postfach: Lieferungen, die Claude in einer Claude-Code-Sitzung
/// unter dem Postfach-Code abgelegt hat (siehe ClaudeInbox). „Übernehmen“
/// öffnet sie im gewohnten Import zum Prüfen; erst nach dem Speichern dort
/// verschwindet die Lieferung aus dem Postfach.
class ClaudeInboxScreen extends StatefulWidget {
  const ClaudeInboxScreen({super.key});

  @override
  State<ClaudeInboxScreen> createState() => _ClaudeInboxScreenState();
}

class _ClaudeInboxScreenState extends State<ClaudeInboxScreen> {
  final _inbox = ClaudeInbox();
  List<InboxDelivery>? _items;
  String? _error;

  String? get _code => context.read<SettingsRepository>().settings.inboxCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final code = _code;
    if (code == null) {
      setState(() => _items = const []);
      return;
    }
    setState(() => _error = null);
    try {
      final items = await _inbox.fetch(code);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = const [];
          _error = 'Postfach nicht erreichbar ($e). Sind die Firestore-Regeln neu veröffentlicht?';
        });
      }
    }
  }

  /// Fach mit dem vorgeschlagenen Namen (grob verglichen: gleich, enthalten
  /// oder gleicher Wortanfang wie „Werkstoffe“/„Werkstoffkunde“), sonst das erste.
  static Module? guessModule(List<Module> modules, String subject) {
    final s = subject.toLowerCase().trim();
    if (s.isNotEmpty) {
      for (final m in modules) {
        final n = m.name.toLowerCase().trim();
        if (n == s || n.contains(s) || s.contains(n)) return m;
      }
      for (final m in modules) {
        final n = m.name.toLowerCase().trim();
        var common = 0;
        while (common < n.length && common < s.length && n[common] == s[common]) {
          common++;
        }
        if (common >= 6) return m;
      }
    }
    return modules.firstOrNull;
  }

  Future<void> _take(InboxDelivery d) async {
    final modules = context.read<ModuleRepository>().modules;
    if (modules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lege zuerst ein Fach an – dann lassen sich die Aufgaben übernehmen.')),
      );
      return;
    }
    final module = await showDialog<Module>(
      context: context,
      builder: (ctx) => _PickModuleDialog(modules: modules, initial: guessModule(modules, d.subject), subject: d.subject),
    );
    if (module == null || !mounted) return;
    final code = _code;
    final saved = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => TaskImportScreen(moduleId: module.id, moduleName: module.name, initialJson: d.payload),
      ),
    );
    final count = saved is List ? saved.length : 0;
    if (count == 0 || code == null) return;
    try {
      await _inbox.remove(code, d.id);
    } catch (_) {
      // Bleibt liegen – beim nächsten Mal lässt sie sich verwerfen.
    }
    // Das Speichern meldet der Import selbst.
    await _load();
  }

  Future<void> _discard(InboxDelivery d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lieferung verwerfen?'),
        content: Text('„${d.title}“ wird aus dem Postfach gelöscht, ohne etwas zu übernehmen.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Verwerfen')),
        ],
      ),
    );
    final code = _code;
    if (ok != true || code == null) return;
    await _inbox.remove(code, d.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items;
    final hasCode = context.watch<SettingsRepository>().settings.inboxCode != null;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Claude-Postfach'),
        actions: [IconButton(key: const ValueKey('inbox-refresh'), onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: TextStyle(color: c.danger)),
                    ),
                  if (!hasCode)
                    Text(
                      'Noch kein Postfach-Code – unter Einstellungen → Claude-Postfach einen erzeugen.',
                      style: TextStyle(color: c.inkMuted),
                    )
                  else if (items.isEmpty && _error == null)
                    Text(
                      'Das Postfach ist leer. Gib Claude in einer Claude-Code-Sitzung deinen Postfach-Code und das '
                      'Übungsblatt – die fertigen Aufgaben erscheinen dann hier.',
                      key: const ValueKey('inbox-empty'),
                      style: TextStyle(color: c.inkMuted, height: 1.4),
                    ),
                  for (final (i, d) in items.indexed) _tile(c, i, d),
                ],
              ),
            ),
    );
  }

  Widget _tile(AppColors c, int i, InboxDelivery d) {
    final count = d.taskCount;
    final when = d.createdAt == null ? '' : ' · ${DateFormat('d.M.yyyy, HH:mm').format(d.createdAt!.toLocal())}';
    return Card(
      key: ValueKey('inbox-item-$i'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d.title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
            ),
            const SizedBox(height: 4),
            Text(
              '${count == 0 ? 'Keine lesbaren Aufgaben' : '$count ${count == 1 ? 'Aufgabe' : 'Aufgaben'}'}'
              '${d.subject.isEmpty ? '' : ' · für ${d.subject}'}$when',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            ),
            if (d.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(d.note, style: TextStyle(color: c.ink, height: 1.4)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  key: ValueKey('inbox-discard-$i'),
                  onPressed: () => _discard(d),
                  child: const Text('Verwerfen'),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: ValueKey('inbox-take-$i'),
                  onPressed: count == 0 ? null : () => _take(d),
                  icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                  label: const Text('Ansehen & übernehmen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PickModuleDialog extends StatefulWidget {
  const _PickModuleDialog({required this.modules, required this.initial, required this.subject});

  final List<Module> modules;
  final Module? initial;
  final String subject;

  @override
  State<_PickModuleDialog> createState() => _PickModuleDialogState();
}

class _PickModuleDialogState extends State<_PickModuleDialog> {
  late Module? _module = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('In welches Fach?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.subject.isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Claude schlägt „${widget.subject}“ vor.')),
        DropdownButton<Module>(
          key: const ValueKey('inbox-module'),
          isExpanded: true,
          value: _module,
          items: [for (final m in widget.modules) DropdownMenuItem(value: m, child: Text(m.name))],
          onChanged: (m) => setState(() => _module = m),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
      FilledButton(
        key: const ValueKey('inbox-module-ok'),
        onPressed: _module == null ? null : () => Navigator.of(context).pop(_module),
        child: const Text('Weiter'),
      ),
    ],
  );
}
