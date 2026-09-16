import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/ai_model_info.dart';
import '../../models/app_settings.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/model_catalog_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/reminder_service.dart';
import '../../services/sync_service.dart';
import '../../services/update_checker_service.dart';
import '../../theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import '../widgets/add_password_dialog.dart';
import 'model_picker_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _syncCodeController;
  final _apiKeyFocusNode = FocusNode();
  late SettingsRepository _settingsRepo;
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
    // Anders als jedes andere Feld auf diesem Screen (Modelle, Chunking,
    // Erinnerung – alle speichern sofort bei Änderung) verlangte der
    // API-Key bisher AUSSCHLIESSLICH den expliziten "Speichern"-Tap unten:
    // wer tippt und dann einfach den Screen verlässt (naheliegend, da jedes
    // andere Feld hier schon gespeichert ist), verliert den Key stillschweigend.
    // Zusätzlich beim Fokusverlust speichern behebt genau das, ohne den
    // Button selbst zu entfernen.
    _apiKeyFocusNode.addListener(() {
      if (!_apiKeyFocusNode.hasFocus) _persistApiKey();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settingsRepo = context.read<SettingsRepository>();
  }

  @override
  void dispose() {
    // Fängt den Fall ab, dass der Screen verlassen wird, während das Feld
    // noch fokussiert ist (dann feuert der obige Fokus-Listener nicht mehr).
    _persistApiKey();
    _apiKeyFocusNode.dispose();
    _apiKeyController.dispose();
    _syncCodeController.dispose();
    super.dispose();
  }

  void _persistApiKey() {
    final trimmed = _apiKeyController.text.trim();
    if (trimmed == (_settingsRepo.settings.openRouterApiKey ?? '')) return;
    unawaited(_settingsRepo.update(_settingsRepo.settings.copyWith(openRouterApiKey: trimmed)));
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

  Future<void> _runSync(
    Future<void> Function() action, {
    required String successMessage,
    Future<void> Function()? afterSuccess,
  }) async {
    setState(() {
      _syncBusy = true;
      _syncMessage = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (afterSuccess != null) await afterSuccess();
      if (!mounted) return;
      setState(() => _syncMessage = successMessage);
    } on SyncException catch (e) {
      if (mounted) setState(() => _syncMessage = e.message);
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  /// Zeigt vor einem Pull die TATSÄCHLICHE Anzahl lokal vorhandener
  /// Datensätze, statt nur pauschal zu warnen – [SyncService._pull] ist ein
  /// vollständiger Ersatz statt eines Merges: hat ein anderes Gerät
  /// zwischenzeitlich offline weitergelernt und noch nicht gepusht, geht
  /// dieser Fortschritt hier lautlos verloren. Die konkreten Zahlen machen
  /// zumindest sichtbar, was auf dem Spiel steht.
  Future<bool?> _confirmOverwrite() async {
    final counts = await _syncService.localCounts();
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lokale Daten überschreiben?'),
        content: Text(
            'Der Cloud-Stand ersetzt deine aktuell ${counts.modules} lokalen Fächer, '
            '${counts.materials} Materialien, ${counts.concepts} Konzepte und '
            '${counts.flashcards} Karteikarten VOLLSTÄNDIG – kein Zusammenführen. '
            'Hat ein anderes Gerät zwischenzeitlich offline weitergelernt und das '
            'noch nicht hochgeladen, geht dieser Fortschritt hier verloren. Das kann '
            'nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Überschreiben')),
        ],
      ),
    );
  }

  Future<void> _pushCode() async {
    final code = _syncCodeController.text.trim();
    if (code.isEmpty) return;
    await _runSync(
      () => _syncService.pushToCode(code),
      successMessage: 'Hochgeladen.',
      afterSuccess: () async {
        final repo = context.read<SettingsRepository>();
        await repo.update(repo.settings.copyWith(syncCode: code, lastSyncAt: DateTime.now()));
      },
    );
  }

  Future<void> _pullCode() async {
    final code = _syncCodeController.text.trim();
    if (code.isEmpty) return;
    final confirmed = await _confirmOverwrite();
    if (confirmed != true) return;
    await _runSync(
      () => _syncService.pullFromCode(code),
      successMessage: 'Heruntergeladen. Bitte App neu starten, um alle Ansichten zu aktualisieren.',
      afterSuccess: () async {
        final repo = context.read<SettingsRepository>();
        await repo.update(repo.settings.copyWith(syncCode: code, lastSyncAt: DateTime.now()));
      },
    );
  }

  Future<void> _pushAccount() async {
    final uid = context.read<AuthRepository>().currentUser?.uid;
    if (uid == null) return;
    await _runSync(
      () => _syncService.pushToAccount(uid),
      successMessage: 'Hochgeladen.',
      afterSuccess: () async {
        final repo = context.read<SettingsRepository>();
        await repo.update(repo.settings.copyWith(lastSyncAt: DateTime.now()));
      },
    );
  }

  Future<void> _pullAccount() async {
    final uid = context.read<AuthRepository>().currentUser?.uid;
    if (uid == null) return;
    final confirmed = await _confirmOverwrite();
    if (confirmed != true) return;
    await _runSync(
      () => _syncService.pullFromAccount(uid),
      successMessage: 'Heruntergeladen. Bitte App neu starten, um alle Ansichten zu aktualisieren.',
      afterSuccess: () async {
        final repo = context.read<SettingsRepository>();
        await repo.update(repo.settings.copyWith(lastSyncAt: DateTime.now()));
      },
    );
  }

  Future<void> _setReminderEnabled(bool enabled) async {
    final repo = context.read<SettingsRepository>();
    await repo.update(repo.settings.copyWith(dailyReminderEnabled: enabled));
    if (!mounted) return;
    await ReminderService().reschedule(repo.settings);
  }

  Future<void> _pickReminderTime() async {
    final settings = context.read<SettingsRepository>().settings;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.dailyReminderHour, minute: settings.dailyReminderMinute),
    );
    if (picked == null || !mounted) return;
    final repo = context.read<SettingsRepository>();
    await repo.update(repo.settings.copyWith(dailyReminderMinuteOfDay: picked.hour * 60 + picked.minute));
    if (!mounted) return;
    await ReminderService().reschedule(repo.settings);
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
    final auth = context.watch<AuthRepository>();
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
                    focusNode: _apiKeyFocusNode,
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
                  _SectionLabel('Lernmodus'),
                  const SizedBox(height: 4),
                  Text(
                    'Beim Lesen einer Folie in MaterialViewerScreen wird alle N Seiten '
                    'ein kurzer Zwischen-Check angeboten (überspringbar) – falsch '
                    'beantwortete Fragen landen automatisch im Daily Quiz. 0 = aus.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton.outlined(
                        onPressed: settings.checkpointQuizPageInterval <= 0
                            ? null
                            : () => context.read<SettingsRepository>().update(
                                  settings.copyWith(
                                      checkpointQuizPageInterval: settings.checkpointQuizPageInterval - 1),
                                ),
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          settings.checkpointQuizPageInterval <= 0
                              ? 'Aus'
                              : '${settings.checkpointQuizPageInterval} Seiten',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton.outlined(
                        onPressed: () => context.read<SettingsRepository>().update(
                              settings.copyWith(
                                  checkpointQuizPageInterval: settings.checkpointQuizPageInterval + 1),
                            ),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Divider(height: 1, color: c.border),
                  ),
                  _SectionLabel('Lernerinnerung'),
                  const SizedBox(height: 4),
                  Text(
                    'Tägliche Erinnerung als Push-Benachrichtigung, zur gewählten Uhrzeit.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.dailyReminderEnabled,
                    activeThumbColor: c.accent,
                    onChanged: (v) => _setReminderEnabled(v),
                    title: const Text('Tägliche Erinnerung', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  if (settings.dailyReminderEnabled)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time_rounded),
                      title: Text(
                        '${settings.dailyReminderHour.toString().padLeft(2, '0')}:'
                        '${settings.dailyReminderMinute.toString().padLeft(2, '0')} Uhr',
                      ),
                      trailing: TextButton(onPressed: _pickReminderTime, child: const Text('Ändern')),
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
                  else if (auth.isSignedIn) ...[
                    Text(
                      'Läuft automatisch über dein Konto '
                      '(${auth.currentUser?.email ?? auth.currentUser?.displayName ?? "angemeldet"}) – '
                      'auf jedem Gerät mit demselben Konto anmelden, dann hier '
                      'synchronisieren. Kein Code nötig. Überträgt auch API-Key und '
                      'Modellwahl.',
                      style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _SoftButton(
                            icon: Icons.cloud_upload_outlined,
                            label: 'Hochladen',
                            onTap: _syncBusy ? null : _pushAccount,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SoftButton(
                            icon: Icons.cloud_download_outlined,
                            label: 'Herunterladen',
                            onTap: _syncBusy ? null : _pullAccount,
                          ),
                        ),
                      ],
                    ),
                    _SyncStatus(busy: _syncBusy, message: _syncMessage, lastSyncAt: settings.lastSyncAt),
                  ] else ...[
                    Text(
                      'Ohne Konto: gib auf jedem Gerät denselben Sync-Code ein, um '
                      'Fächer und Lernfortschritt zu teilen. Der Code funktioniert wie '
                      'ein Passwort – teile ihn nicht mit Fremden. Mit Google/E-Mail '
                      'anmelden (oben) synchronisiert stattdessen automatisch ohne Code.',
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
                            onTap: _syncBusy ? null : _pushCode,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SoftButton(
                            icon: Icons.cloud_download_outlined,
                            label: 'Herunterladen',
                            onTap: _syncBusy ? null : _pullCode,
                          ),
                        ),
                      ],
                    ),
                    _SyncStatus(busy: _syncBusy, message: _syncMessage, lastSyncAt: settings.lastSyncAt),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Divider(height: 1, color: c.border),
                  ),
                  _SectionLabel('App-Version'),
                  const SizedBox(height: 4),
                  const _UpdateSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateSection extends StatefulWidget {
  const _UpdateSection();

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  PackageInfo? _info;
  bool _checking = false;
  bool _checked = false;
  UpdateInfo? _update;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _checked = false;
    });
    final update = await UpdateCheckerService().checkForUpdate();
    if (!mounted) return;
    setState(() {
      _update = update;
      _checking = false;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _info == null ? 'Version wird geladen …' : 'Version ${_info!.version} (Build ${_info!.buildNumber})',
          style: TextStyle(fontSize: 12, color: c.inkMuted),
        ),
        const SizedBox(height: 10),
        if (_update != null) ...[
          Text(
            'Update verfügbar: Build ${_update!.buildNumber}',
            style: TextStyle(fontSize: 12.5, color: c.good, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _SoftButton(
            icon: Icons.download_outlined,
            label: 'Herunterladen',
            onTap: () => launchUrl(Uri.parse(_update!.downloadUrl), mode: LaunchMode.externalApplication),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _checking ? null : _check,
            icon: _checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: Text(_checking ? 'Prüfe …' : (_checked ? 'Aktuell' : 'Nach Updates suchen')),
          ),
      ],
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

class _AccountSection extends StatefulWidget {
  const _AccountSection();

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  bool _linkingPassword = false;

  Future<void> _addPassword(String email) async {
    final password = await addPasswordDialog(context, email: email);
    if (password == null || !mounted) return;
    setState(() => _linkingPassword = true);
    try {
      await context.read<AuthRepository>().linkEmailPassword(email, password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Passwort hinzugefügt – Anmeldung mit "$email" geht jetzt auch auf Windows/Desktop.'),
        ));
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _linkingPassword = false);
    }
  }

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
      final hasPassword = user.providerData.any((p) => p.providerId == 'password');
      final canAddPassword = !hasPassword && user.email != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          ),
          if (canAddPassword) ...[
            const SizedBox(height: 10),
            Text(
              'Google-Anmeldung funktioniert nicht auf Windows/Desktop (das Package '
              'unterstützt das dort nicht). Passwort hinzufügen, um dich mit demselben '
              'Konto auch dort anzumelden – gleicher Cloud-Sync.',
              style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: _linkingPassword ? null : () => _addPassword(user.email!),
              child: _linkingPassword
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Passwort hinzufügen'),
            ),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Optional: mit E-Mail/Passwort oder Google anmelden, für '
            'automatischen Cloud-Sync ohne Code.',
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

class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.busy, required this.message, required this.lastSyncAt});

  final bool busy;
  final String? message;
  final DateTime? lastSyncAt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(message!, style: TextStyle(color: c.inkMuted)),
          ),
        if (lastSyncAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: c.good, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Text(
                  'Zuletzt synchronisiert: $lastSyncAt',
                  style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                ),
              ],
            ),
          ),
      ],
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
