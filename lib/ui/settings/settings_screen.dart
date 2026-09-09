import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../repositories/settings_repository.dart';
import '../../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _syncCodeController;
  bool _obscureKey = true;
  bool _syncBusy = false;
  String? _syncMessage;
  final _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsRepository>().settings;
    _apiKeyController = TextEditingController(text: settings.openRouterApiKey ?? '');
    _syncCodeController = TextEditingController(text: settings.syncCode ?? '');
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _syncCodeController.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    final repo = context.read<SettingsRepository>();
    await repo.update(repo.settings.copyWith(openRouterApiKey: _apiKeyController.text.trim()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API-Key gespeichert.')));
    }
  }

  Future<void> _selectModel(String modelId) async {
    final repo = context.read<SettingsRepository>();
    await repo.update(repo.settings.copyWith(selectedModel: modelId));
  }

  Future<void> _push() async {
    final code = _syncCodeController.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _syncBusy = true;
      _syncMessage = null;
    });
    try {
      await _syncService.push(code);
      if (!mounted) return;
      final repo = context.read<SettingsRepository>();
      await repo.update(repo.settings.copyWith(syncCode: code, lastSyncAt: DateTime.now()));
      setState(() => _syncMessage = 'Hochgeladen.');
    } on SyncException catch (e) {
      setState(() => _syncMessage = e.message);
    } finally {
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _pull() async {
    final code = _syncCodeController.text.trim();
    if (code.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lokale Daten überschreiben?'),
        content: const Text(
            'Alle lokalen Fächer, Materialien, Konzepte und Karteikarten werden '
            'durch den Stand aus der Cloud ersetzt. Das kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Überschreiben')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _syncBusy = true;
      _syncMessage = null;
    });
    try {
      await _syncService.pull(code);
      if (!mounted) return;
      final repo = context.read<SettingsRepository>();
      await repo.update(repo.settings.copyWith(syncCode: code, lastSyncAt: DateTime.now()));
      setState(() => _syncMessage = 'Heruntergeladen. Bitte App neu starten, um alle Ansichten zu aktualisieren.');
    } on SyncException catch (e) {
      setState(() => _syncMessage = e.message);
    } finally {
      setState(() => _syncBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsRepository>().settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('KI (BYOK)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Bring your own key: hinterlege deinen eigenen OpenRouter-API-Key. '
            'Es läuft kein eigener Server – Anfragen gehen direkt von diesem Gerät an OpenRouter.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'OpenRouter API-Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _saveApiKey, child: const Text('Speichern')),
          ),
          const SizedBox(height: 24),
          Text('Modell', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: settings.selectedModel,
            onChanged: (v) => _selectModel(v!),
            child: Column(
              children: kOpenRouterModels
                  .map((m) => RadioListTile<String>(
                        value: m.id,
                        title: Text(m.label),
                        subtitle: Text(m.id, style: const TextStyle(fontSize: 11)),
                      ))
                  .toList(),
            ),
          ),
          const Divider(height: 40),
          Text('Cloud-Sync', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (!_syncService.isAvailable)
            const Text(
              'Nicht konfiguriert: dieser Build hat kein Firebase-Projekt '
              'verbunden. Die App funktioniert komplett offline. Siehe README '
              '("flutterfire configure"), um Sync zwischen Windows/iPad/Android '
              'zu aktivieren.',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            const Text(
              'Gib auf jedem Gerät denselben Sync-Code ein, um Fächer und '
              'Lernfortschritt zu teilen. Der Code funktioniert wie ein '
              'Passwort – teile ihn nicht mit Fremden.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _syncCodeController,
              decoration: const InputDecoration(labelText: 'Sync-Code', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _syncBusy ? null : _push,
                    child: const Text('In Cloud hochladen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _syncBusy ? null : _pull,
                    child: const Text('Aus Cloud laden'),
                  ),
                ),
              ],
            ),
            if (_syncBusy) const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            if (_syncMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_syncMessage!),
              ),
            if (settings.lastSyncAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Zuletzt synchronisiert: ${settings.lastSyncAt}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
