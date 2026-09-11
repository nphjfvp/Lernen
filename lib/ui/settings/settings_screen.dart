import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/ai_model_info.dart';
import '../../models/app_settings.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/model_catalog_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/sync_service.dart';
import '../../theme/app_colors.dart';
import '../auth/login_screen.dart';
import 'model_picker_sheet.dart';

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

  Future<void> _pickModel({
    required String role,
    required String title,
    required List<AiModelInfo> models,
    required String selectedId,
  }) async {
    final picked = await showModelPickerSheet(context, title: title, models: models, selectedId: selectedId);
    if (picked == null || !mounted) return;
    final repo = context.read<SettingsRepository>();
    switch (role) {
      case 'question':
        await repo.update(repo.settings.copyWith(questionModelId: picked));
      case 'vision':
        await repo.update(repo.settings.copyWith(visionModelId: picked));
      case 'crosscheck':
        await repo.update(repo.settings.copyWith(crosscheckModelId: picked));
    }
  }

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
    return 'vor ${diff.inDays} Tagen';
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
                  _SectionLabel('Modelle'),
                  const SizedBox(height: 4),
                  Consumer<ModelCatalogRepository>(
                    builder: (context, catalog, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  catalog.lastUpdated == null
                                      ? 'Noch nicht aktualisiert – eingebaute Fallback-Liste aktiv.'
                                      : '${catalog.models.length} Modelle von OpenRouter · aktualisiert ${_formatRelative(catalog.lastUpdated!)}',
                                  style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: catalog.isRefreshing ? null : () => catalog.refresh(),
                                icon: catalog.isRefreshing
                                    ? SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
                                      )
                                    : const Icon(Icons.refresh, size: 16),
                                label: const Text('Aktualisieren', style: TextStyle(fontSize: 12.5)),
                              ),
                            ],
                          ),
                          if (catalog.lastError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 6),
                              child: Text(catalog.lastError!, style: TextStyle(fontSize: 11.5, color: c.danger)),
                            ),
                          const SizedBox(height: 10),
                          _ModelSelectorTile(
                            label: 'Fragenerstellen',
                            sublabel: 'Zusammenfassungen, Konzepte, Karteikarten',
                            selectedId: settings.questionModelId,
                            catalog: catalog,
                            onTap: () => _pickModel(
                              role: 'question',
                              title: 'Modell für Fragenerstellen',
                              models: catalog.models,
                              selectedId: settings.questionModelId,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ModelSelectorTile(
                            label: 'Vision',
                            sublabel: 'Für gescannte Folien ohne Textebene',
                            selectedId: settings.visionModelId,
                            catalog: catalog,
                            onTap: () => _pickModel(
                              role: 'vision',
                              title: 'Vision-Modell',
                              models: catalog.visionModels,
                              selectedId: settings.visionModelId,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ModelSelectorTile(
                            label: 'Crosscheck',
                            sublabel: 'Zweitmeinung zur Prüfung der Ergebnisse',
                            selectedId: settings.crosscheckModelId,
                            catalog: catalog,
                            onTap: () => _pickModel(
                              role: 'crosscheck',
                              title: 'Crosscheck-Modell',
                              models: catalog.models,
                              selectedId: settings.crosscheckModelId,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  _SectionLabel('Chunking'),
                  const SizedBox(height: 4),
                  Text(
                    'Wie große Foliensätze/Übungen vor der KI-Generierung in Abschnitte '
                    'zerlegt werden.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ChunkGranularity.values.map((g) {
                      final selected = settings.chunkGranularity == g;
                      return ChoiceChip(
                        label: Text(g.label),
                        selected: selected,
                        onSelected: (_) => context.read<SettingsRepository>().update(settings.copyWith(chunkGranularity: g)),
                        selectedColor: c.accentSoft,
                        labelStyle: TextStyle(fontSize: 12.5, color: selected ? c.accentOnSoft : c.ink, fontWeight: FontWeight.w600),
                        backgroundColor: c.surface,
                        side: BorderSide(color: selected ? c.accent : c.border),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.rollingContextEnabled,
                    activeThumbColor: c.accent,
                    onChanged: (v) => context.read<SettingsRepository>().update(settings.copyWith(rollingContextEnabled: v)),
                    title: const Text('Rolling-Context', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Bereits erkannte Themen werden in den nächsten Abschnitt mitgegeben, '
                      'um doppelte Karten/Konzepte zu vermeiden.',
                      style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Divider(height: 1, color: c.border),
                  ),
                  _SectionLabel('Account'),
                  const SizedBox(height: 4),
                  const _AccountSection(),
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

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = context.watch<AuthRepository>();

    if (!auth.isAvailable) {
      return Text(
        'Nicht konfiguriert: dieser Build hat kein Firebase-Projekt verbunden.',
        style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
      );
    }

    if (auth.isSignedIn) {
      final user = auth.currentUser!;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Angemeldet als', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                const SizedBox(height: 2),
                Text(
                  user.email ?? user.displayName ?? user.uid,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => context.read<AuthRepository>().signOut(),
            child: const Text('Abmelden'),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Optional: mit E-Mail/Passwort oder Google anmelden.',
            style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.accentSolid,
            foregroundColor: c.accentInk,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          ),
          child: const Text('Anmelden'),
        ),
      ],
    );
  }
}

class _ModelSelectorTile extends StatelessWidget {
  const _ModelSelectorTile({
    required this.label,
    required this.sublabel,
    required this.selectedId,
    required this.catalog,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final String selectedId;
  final ModelCatalogRepository catalog;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final model = catalog.byId(selectedId);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(sublabel, style: TextStyle(fontSize: 11, color: c.inkMuted)),
                  const SizedBox(height: 6),
                  Text(
                    model?.name ?? selectedId,
                    style: TextStyle(fontSize: 12.5, color: c.accentOnSoft, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkMuted, size: 18),
          ],
        ),
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
