import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../repositories/settings_repository.dart';
import '../../services/sync_service.dart';
import '../../theme/app_colors.dart';

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

  InputDecoration _fieldDecoration(BuildContext context, {required String label}) {
    final c = context.colors;
    final radius = BorderRadius.circular(14);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.accent)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsRepository>().settings;
    final c = context.colors;

    return Material(
      color: c.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
              child: Text('Einstellungen', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 160),
                children: [
                  _SectionLabel('KI (BYOK)'),
                  const SizedBox(height: 4),
                  Text(
                    'Eigener OpenRouter-Key – Anfragen gehen direkt von diesem '
                    'Gerät an OpenRouter, kein eigener Server.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    decoration: _fieldDecoration(context, label: 'OpenRouter API-Key').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: c.inkMuted),
                        onPressed: () => setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.accentSolid,
                        foregroundColor: c.accentInk,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _saveApiKey,
                      child: const Text('Speichern'),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _SectionLabel('Modell'),
                  RadioGroup<String>(
                    groupValue: settings.selectedModel,
                    onChanged: (v) => _selectModel(v!),
                    child: Column(
                      children: kOpenRouterModels
                          .map((m) => RadioListTile<String>(
                                value: m.id,
                                activeColor: c.accent,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(m.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                subtitle: Text(m.id, style: TextStyle(fontSize: 11, color: c.inkMuted)),
                              ))
                          .toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Divider(height: 1, color: c.border),
                  ),
                  _SectionLabel('Cloud-Sync'),
                  const SizedBox(height: 4),
                  if (!_syncService.isAvailable)
                    Text(
                      'Nicht konfiguriert: dieser Build hat kein Firebase-Projekt '
                      'verbunden. Die App funktioniert komplett offline. Siehe README '
                      '("flutterfire configure"), um Sync zwischen Windows/iPad/Android '
                      'zu aktivieren.',
                      style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                    )
                  else ...[
                    Text(
                      'Gib auf jedem Gerät denselben Sync-Code ein, um Fächer und '
                      'Lernfortschritt zu teilen. Der Code funktioniert wie ein '
                      'Passwort – teile ihn nicht mit Fremden.',
                      style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _syncCodeController,
                      decoration: _fieldDecoration(context, label: 'Sync-Code'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _SoftButton(
                            icon: Icons.cloud_upload_outlined,
                            label: 'Hochladen',
                            onTap: _syncBusy ? null : _push,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SoftButton(
                            icon: Icons.cloud_download_outlined,
                            label: 'Herunterladen',
                            onTap: _syncBusy ? null : _pull,
                          ),
                        ),
                      ],
                    ),
                    if (_syncBusy)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_syncMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_syncMessage!, style: TextStyle(color: c.inkMuted)),
                      ),
                    if (settings.lastSyncAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Container(width: 7, height: 7, decoration: BoxDecoration(color: c.good, shape: BoxShape.circle)),
                            const SizedBox(width: 7),
                            Text(
                              'Zuletzt synchronisiert: ${settings.lastSyncAt}',
                              style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.04, color: c.inkMuted),
      ),
    );
  }
}

class _SoftButton extends StatelessWidget {
  const _SoftButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: c.ink),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
          ],
        ),
      ),
    );
  }
}
