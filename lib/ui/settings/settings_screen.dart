import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../models/ai_model_info.dart';
import '../../models/app_settings.dart';
import '../../models/pdf_storage_config.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/model_catalog_repository.dart';
import '../../repositories/lab_experiment_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/auth_service.dart';
import '../../services/auto_sync_service.dart';
import '../../services/pdf_cloud_store.dart';
import '../../services/pdf_cloud_sync_service.dart';
import '../../services/reminder_service.dart';
import '../../services/sync_diagnostics.dart';
import '../../services/sync_service.dart';
import '../../services/update_checker_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../widgets/add_password_dialog.dart';
import '../widgets/question_type_dropdown.dart';
import '../widgets/update_actions.dart';
import 'model_picker_sheet.dart';
import 'sync_backups_dialog.dart';
import 'sync_diagnosis_dialog.dart';

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

  /// Zuletzt aus den Einstellungen ins Feld übernommener Wert – erkennt, ob
  /// der Nutzer selbst etwas getippt hat (siehe [_onSettingsChanged]).
  String _knownApiKey = '';
  String _knownSyncCode = '';

  @override
  void initState() {
    super.initState();
    _settingsRepo = context.read<SettingsRepository>();
    final settings = _settingsRepo.settings;
    _knownApiKey = settings.openRouterApiKey ?? '';
    _knownSyncCode = settings.syncCode ?? '';
    _apiKeyController = TextEditingController(text: _knownApiKey);
    _syncCodeController = TextEditingController(text: _knownSyncCode);
    _settingsRepo.addListener(_onSettingsChanged);
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
    _settingsRepo.removeListener(_onSettingsChanged);
    _apiKeyFocusNode.dispose();
    _apiKeyController.dispose();
    _syncCodeController.dispose();
    super.dispose();
  }

  /// Wurden die Einstellungen von außen geändert (Cloud-Download), zeigen die
  /// Felder sonst weiter den alten Stand – und [_persistApiKey] schriebe ihn
  /// beim Verlassen zurück (z.B. ein leeres Feld über den gerade
  /// heruntergeladenen Key). Selbst Getipptes bleibt stehen.
  void _onSettingsChanged() {
    final settings = _settingsRepo.settings;
    final key = settings.openRouterApiKey ?? '';
    if (key != _knownApiKey) {
      if (_apiKeyController.text.trim() == _knownApiKey) _apiKeyController.text = key;
      _knownApiKey = key;
    }
    final code = settings.syncCode ?? '';
    if (code != _knownSyncCode) {
      if (_syncCodeController.text.trim() == _knownSyncCode) _syncCodeController.text = code;
      _knownSyncCode = code;
    }
  }

  void _persistApiKey() {
    final trimmed = _apiKeyController.text.trim();
    // Nur speichern, was hier getippt wurde – nicht einen veralteten Stand.
    if (trimmed == _knownApiKey) return;
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
    } catch (e) {
      // Firestore-/Netzwerkfehler (z.B. Dokument über dem 1-MiB-Limit,
      // fehlende Berechtigung, offline) sind keine SyncException – ohne
      // diesen Zweig verschwände der Fehler kommentarlos.
      if (mounted) setState(() => _syncMessage = 'Sync fehlgeschlagen: ${SyncDiagnostics.describeError(e)}');
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
  Future<bool?> _confirmOverwrite(SyncTarget target) async {
    final counts = await _syncService.localCounts();
    if (!mounted) return false;
    // Auf einem neuen Gerät ohne Daten gibt es nichts zu verlieren.
    if (counts.modules == 0 && counts.materials == 0 && counts.concepts == 0 && counts.flashcards == 0) return true;
    final cloud = await _cloudSummary(target);
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lokale Daten überschreiben?'),
        content: Text(
            '${cloud == null ? '' : 'In der Cloud liegt: $cloud.\n\n'}'
            'Der Cloud-Stand ersetzt deine aktuell ${counts.modules} lokalen Fächer, '
            '${counts.materials} Materialien, ${counts.concepts} Konzepte und '
            '${counts.flashcards} Karteikarten VOLLSTÄNDIG – kein Zusammenführen. '
            'Hat ein anderes Gerät zwischenzeitlich offline weitergelernt und das '
            'noch nicht hochgeladen, geht dieser Fortschritt hier verloren.\n\n'
            'Vorher legt die App automatisch eine Sicherung auf diesem Gerät an – '
            'sie lässt sich unter "Sicherungen" wiederherstellen.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Überschreiben')),
        ],
      ),
    );
  }

  /// Was gerade in der Cloud liegt, als Satz (siehe SyncDiagnostics.describeCloudState);
  /// `null`, wenn dort nichts liegt oder sie nicht erreichbar ist.
  Future<String?> _cloudSummary(SyncTarget target) async {
    try {
      final cloud = await _syncService.cloudMeta(target);
      if (cloud == null) return null;
      final deviceId = await AutoSyncService.ensureDeviceId(_settingsRepo);
      return SyncDiagnostics.describeCloudState(
        modules: cloud.modules,
        flashcards: cloud.flashcards,
        updatedAt: cloud.updatedAt,
        fromThisDevice: cloud.deviceId == deviceId,
        now: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Vor "Hochladen": liegt in der Cloud ein Stand eines ANDEREN Geräts, den
  /// dieses Gerät nicht kennt, ersetzt der Upload ihn – dann mit Zahlen fragen,
  /// welcher der bessere Stand ist.
  Future<bool> _confirmUpload(SyncTarget target) async {
    final CloudSyncMeta? cloud;
    try {
      cloud = await _syncService.cloudMeta(target);
    } catch (_) {
      return true; // nicht erreichbar: der Upload selbst meldet das
    }
    if (cloud == null || !mounted) return true;
    final deviceId = await AutoSyncService.ensureDeviceId(_settingsRepo);
    if (!AutoSyncService.isBlockedByOtherDevice(
      meta: cloud,
      lastSyncedPushId: _settingsRepo.settings.lastSyncedPushId,
      deviceId: deviceId,
    )) {
      return true;
    }
    final local = await _syncService.localCounts();
    if (!mounted) return false;
    final cloudText = SyncDiagnostics.describeCloudState(
      modules: cloud.modules,
      flashcards: cloud.flashcards,
      updatedAt: cloud.updatedAt,
      fromThisDevice: false,
      now: DateTime.now(),
    );
    final cloudHasMore = (cloud.flashcards ?? 0) > local.flashcards || (cloud.modules ?? 0) > local.modules;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cloud-Stand eines anderen Geräts ersetzen?'),
        content: Text(
          'In der Cloud liegt: $cloudText – diesen Stand kennt dieses Gerät nicht.\n'
          'Dieses Gerät hat: ${local.modules} Fächer, ${local.flashcards} Karten.\n\n'
          '${cloudHasMore ? 'ACHTUNG: In der Cloud liegt MEHR als hier. Vielleicht ist der Cloud-Stand der neuere – '
              'dann besser erst "Herunterladen".\n\n' : ''}'
          'Ein Upload ersetzt den Cloud-Stand vollständig; der andere Stand ist danach nicht mehr in der Cloud.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cloud ersetzen')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _push(SyncTarget target, {String? codeToRemember}) async {
    final repo = context.read<SettingsRepository>();
    final autoSync = context.read<AutoSyncService>();
    await _runSync(
      () async {
        final deviceId = await AutoSyncService.ensureDeviceId(repo);
        // Erst die PDFs in den eigenen Speicher (falls eingerichtet), damit
        // der Upload der Lerndaten schon die Verweise enthält. Ein Fehler dort
        // hält den Sync der Lerndaten nicht auf.
        final store = PdfCloudStore.fromConfig(repo.settings.pdfStorage);
        if (store != null) {
          try {
            await autoSync.runWithoutTrigger(() => PdfCloudSyncService(store).uploadPending());
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF-Speicher: $e')));
            }
          }
        }
        final pushId = await _syncService.push(target, deviceId: deviceId);
        await repo.update(repo.settings.copyWith(
          syncCode: codeToRemember,
          lastSyncAt: DateTime.now(),
          lastSyncedPushId: pushId,
        ));
        autoSync.markInSync();
      },
      successMessage: 'Hochgeladen.',
    );
  }

  Future<void> _pull(SyncTarget target, {String? codeToRemember}) async {
    final confirmed = await _confirmOverwrite(target);
    if (confirmed != true || !mounted) return;
    final repo = context.read<SettingsRepository>();
    final autoSync = context.read<AutoSyncService>();
    final moduleRepo = context.read<ModuleRepository>();
    final labRepo = context.read<LabExperimentRepository?>();
    await _runSync(
      () async {
        // Der Download schreibt alle Daten neu – das soll keinen sofortigen
        // Auto-Upload desselben Stands auslösen.
        final pushId = await autoSync.runWithoutTrigger(() => _syncService.pull(target));
        // Der Pull hat die KI-Einstellungen bereits direkt in die DB
        // geschrieben – erst neu laden, sonst überschreibt das Update unten
        // sie wieder mit dem veralteten Stand aus dem Speicher.
        await repo.load();
        await repo.update(repo.settings.copyWith(
          syncCode: codeToRemember,
          lastSyncAt: DateTime.now(),
          lastSyncedPushId: pushId,
        ));
        // Fächerliste sofort aktualisieren (die übrigen Ansichten laden beim
        // Öffnen neu).
        await moduleRepo.load();
        await labRepo?.loadAll();
        autoSync.markInSync();
      },
      successMessage: 'Heruntergeladen.',
    );
  }

  /// "Sicherungen": die automatischen Sicherungen dieses Geräts ansehen und eine
  /// wiederherstellen.
  Future<void> _showBackups() async {
    final restored = await showDialog<bool>(context: context, builder: (_) => const SyncBackupsDialog());
    if (restored != true || !mounted) return;
    await context.read<ModuleRepository>().load();
    if (!mounted) return;
    await context.read<LabExperimentRepository?>()?.loadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sicherung wiederhergestellt.')));
  }

  /// "Verbindung prüfen": geht Ziel, Cloud-Stand und Schreibzugriff durch und
  /// zeigt, woran der Sync hängt (siehe SyncService.diagnose).
  Future<void> _diagnoseSync() async {
    final repo = context.read<SettingsRepository>();
    final auth = context.read<AuthRepository>();
    final target = _accountTarget() ?? _codeTarget();
    final deviceId = await AutoSyncService.ensureDeviceId(repo);
    if (!mounted) return;
    final future = _syncService.diagnose(
      target,
      deviceId: deviceId,
      lastSyncedPushId: repo.settings.lastSyncedPushId,
      email: auth.currentUser?.email,
    );
    await showDialog<void>(context: context, builder: (_) => SyncDiagnosisDialog(future: future));
  }

  SyncTarget? _codeTarget() {
    final code = _syncCodeController.text.trim();
    return code.isEmpty ? null : SyncTarget.code(code);
  }

  SyncTarget? _accountTarget() {
    final uid = context.read<AuthRepository>().currentUser?.uid;
    return uid == null ? null : SyncTarget.account(uid);
  }

  Future<void> _pushCode() async {
    final target = _codeTarget();
    if (target == null || !await _confirmUpload(target) || !mounted) return;
    await _push(target, codeToRemember: target.id);
  }

  Future<void> _pullCode() async {
    final target = _codeTarget();
    if (target != null) await _pull(target, codeToRemember: target.id);
  }

  Future<void> _pushAccount() async {
    final target = _accountTarget();
    if (target == null || !await _confirmUpload(target) || !mounted) return;
    await _push(target);
  }

  Future<void> _pullAccount() async {
    final target = _accountTarget();
    if (target != null) await _pull(target);
  }

  /// Direkt nach der Anmeldung: liegt im Konto schon ein Stand (z.B. vom
  /// Handy), bietet die App an, ihn auf dieses Gerät zu holen – samt API-Key
  /// und PDF-Speicher. Ist das Konto noch leer, stattdessen den Stand dieses
  /// Geräts hochladen. Offline o.ä.: still, die Buttons bleiben ja da.
  Future<void> _offerCloudSync() async {
    final target = _accountTarget();
    if (target == null || !_syncService.isAvailable) return;
    final CloudSyncMeta? cloud;
    try {
      cloud = await _syncService.cloudMeta(target);
    } catch (_) {
      return;
    }
    final local = await _syncService.localCounts();
    if (!mounted) return;
    if (cloud == null) {
      if (local.modules == 0) return;
      final upload = await _askSync(
        title: 'Konto ist noch leer',
        message: 'In deinem Konto liegt noch nichts. Den Stand dieses Geräts (${local.modules} Fächer, '
            '${local.flashcards} Karten) jetzt hochladen, damit deine anderen Geräte ihn holen können?',
        action: 'Hochladen',
      );
      if (upload) await _push(target);
      return;
    }
    if (cloud.pushId != null && cloud.pushId == _settingsRepo.settings.lastSyncedPushId) return;
    final when = cloud.updatedAt == null ? '' : ' (${_formatRelative(cloud.updatedAt!)} hochgeladen)';
    final what = cloud.modules == null ? '' : ' mit ${cloud.modules} Fächern und ${cloud.flashcards} Karten';
    final download = await _askSync(
      title: 'Stand aus deinem Konto holen?',
      message: 'In deinem Konto liegt ein Stand$what$when – samt API-Key, Modellwahl und PDF-Speicher, '
          'falls dort eingetragen. Jetzt auf dieses Gerät holen?',
      action: 'Herunterladen',
    );
    if (download) await _pull(target);
  }

  Future<bool> _askSync({required String title, required String message, required String action}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Später')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(action)),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _setAutoSync(bool enabled) async {
    final repo = context.read<SettingsRepository>();
    final autoSync = context.read<AutoSyncService>();
    final code = _syncCodeController.text.trim();
    await repo.update(repo.settings.copyWith(
      autoSyncEnabled: enabled,
      syncCode: code.isEmpty ? null : code,
    ));
    if (enabled) autoSync.requestSync();
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
    // Kein manueller Up-/Download, während der Auto-Sync gerade hochlädt –
    // sonst könnte dessen (älterer) Stand einen frischen Download in der
    // Cloud wieder überschreiben.
    final syncLocked = _syncBusy || context.watch<AutoSyncService>().status == AutoSyncStatus.syncing;

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
                  _SectionLabel('Erscheinungsbild'),
                  const SizedBox(height: 4),
                  Text(
                    'Nur die Farben ändern sich – Aufbau und Bedienung bleiben gleich.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  _ThemeSkinPicker(
                    value: themeSkinFromName(settings.themeSkin),
                    onChanged: (skin) => context
                        .read<SettingsRepository>()
                        .update(settings.copyWith(themeSkin: skin.name)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hell/Dunkel',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink),
                  ),
                  const SizedBox(height: 8),
                  _ThemeModePicker(
                    value: themeModePreferenceFromName(settings.themeModePreference),
                    onChanged: (mode) => context
                        .read<SettingsRepository>()
                        .update(settings.copyWith(themeModePreference: mode.name)),
                  ),
                  const SizedBox(height: 26),
                  _SectionLabel('KI (BYOK)'),
                  const SizedBox(height: 4),
                  Text(
                    'Eigener OpenRouter-Key – Anfragen gehen direkt von diesem '
                    'Gerät an OpenRouter, kein eigener Server. Mit Konto-Anmeldung '
                    'kommt er per Sync auf deine anderen Geräte.',
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
                  _SectionLabel('Frage erstellen'),
                  const SizedBox(height: 4),
                  Text(
                    'Welcher Fragetyp je Schwierigkeitsstufe vorausgewählt ist, wenn du im Lernmodus '
                    '"Frage erstellen" öffnest. "KI entscheidet" lässt der KI die Wahl. Vor dem '
                    'Erstellen kannst du jede Stufe trotzdem von Hand ändern.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  for (final level in const ['Leicht', 'Mittel', 'Schwer'])
                    Row(
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(level, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: KeyedSubtree(
                            key: ValueKey('tier-pref-${AppSettings.tierKey(level)}'),
                            child: QuestionTypeDropdown(
                              value: settings.pageTierType(level),
                              onChanged: (t) {
                                final types = {...settings.pageQuestionTierTypes};
                                if (t == null) {
                                  types.remove(AppSettings.tierKey(level));
                                } else {
                                  types[AppSettings.tierKey(level)] = t.name;
                                }
                                context.read<SettingsRepository>().update(
                                      settings.copyWith(pageQuestionTierTypes: types),
                                    );
                              },
                            ),
                          ),
                        ),
                      ],
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
                  _AccountSection(onSignedIn: _offerCloudSync),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Divider(height: 1, color: c.border),
                  ),
                  _SectionLabel('Cloud-Sync'),
                  const SizedBox(height: 4),
                  if (!_syncService.isAvailable) ...[
                    Text(
                      'Nicht konfiguriert: dieser Build hat kein Firebase-Projekt '
                      'verbunden. Die App funktioniert komplett offline. Siehe README '
                      '("flutterfire configure"), um Sync zwischen Windows/iPad/Android '
                      'zu aktivieren. (Ist es bei dir eingerichtet und trotzdem so: App neu starten – '
                      'die Verbindung zu Firebase kam beim Start nicht zustande.)',
                      style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    _SoftButton(icon: Icons.health_and_safety_outlined, label: 'Verbindung prüfen', onTap: _diagnoseSync),
                  ] else if (auth.isSignedIn) ...[
                    Text(
                      'Läuft automatisch über dein Konto '
                      '(${auth.currentUser?.email ?? auth.currentUser?.displayName ?? "angemeldet"}) – '
                      'auf jedem Gerät mit demselben Konto anmelden, dann hier '
                      'synchronisieren. Kein Code nötig. Überträgt auch API-Key, '
                      'Modellwahl und PDF-Speicher sowie Lerntage, Probeklausuren und Frage-Chats.',
                      style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _SoftButton(
                            icon: Icons.cloud_upload_outlined,
                            label: 'Hochladen',
                            onTap: syncLocked ? null : _pushAccount,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SoftButton(
                            icon: Icons.cloud_download_outlined,
                            label: 'Herunterladen',
                            onTap: syncLocked ? null : _pullAccount,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SoftButton(
                      icon: Icons.health_and_safety_outlined,
                      label: 'Verbindung prüfen',
                      onTap: _syncBusy ? null : _diagnoseSync,
                    ),
                    const SizedBox(height: 10),
                    _SoftButton(
                      icon: Icons.settings_backup_restore_outlined,
                      label: 'Sicherungen (auf diesem Gerät)',
                      onTap: _syncBusy ? null : _showBackups,
                    ),
                    _SyncStatus(busy: _syncBusy, message: _syncMessage, lastSyncAt: settings.lastSyncAt),
                    _AutoSyncTile(enabled: settings.autoSyncEnabled, onChanged: _setAutoSync),
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
                            onTap: syncLocked ? null : _pushCode,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SoftButton(
                            icon: Icons.cloud_download_outlined,
                            label: 'Herunterladen',
                            onTap: syncLocked ? null : _pullCode,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SoftButton(
                      icon: Icons.health_and_safety_outlined,
                      label: 'Verbindung prüfen',
                      onTap: _syncBusy ? null : _diagnoseSync,
                    ),
                    const SizedBox(height: 10),
                    _SoftButton(
                      icon: Icons.settings_backup_restore_outlined,
                      label: 'Sicherungen (auf diesem Gerät)',
                      onTap: _syncBusy ? null : _showBackups,
                    ),
                    _SyncStatus(busy: _syncBusy, message: _syncMessage, lastSyncAt: settings.lastSyncAt),
                    _AutoSyncTile(enabled: settings.autoSyncEnabled, onChanged: _setAutoSync),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Divider(height: 1, color: c.border),
                  ),
                  _SectionLabel('PDF-Speicher (eigene Cloud)'),
                  const SizedBox(height: 4),
                  _PdfStorageSection(fieldDecoration: _fieldDecoration),
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
            label: updateActionLabel,
            onTap: () => applyUpdate(context, _update!),
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

/// Drei Farbpaletten zur Auswahl (siehe theme/app_colors.dart) – jede als
/// Kachel mit Farbpunkt + Name, ausgewählte Kachel mit Rahmen/Häkchen.
/// Ändert Form/Layout der App NICHT, nur die Tönung.
class _ThemeSkinPicker extends StatelessWidget {
  const _ThemeSkinPicker({required this.value, required this.onChanged});

  final AppThemeSkin value;
  final ValueChanged<AppThemeSkin> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final skin in AppThemeSkin.values) ...[
          if (skin != AppThemeSkin.values.first) const SizedBox(width: 10),
          Expanded(
            child: _ThemeSkinTile(
              key: ValueKey('theme-skin-${skin.name}'),
              skin: skin,
              selected: skin == value,
              onTap: () => onChanged(skin),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemeSkinTile extends StatelessWidget {
  const _ThemeSkinTile({super.key, required this.skin, required this.selected, required this.onTap});

  final AppThemeSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? c.accent : c.border, width: selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: skin.previewSolid, shape: BoxShape.circle),
                ),
                if (selected)
                  const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              skin.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? c.accentOnSoft : c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hell/Dunkel unabhängig von der Farbpalette: "System" (Standard) folgt dem
/// Gerät, "Hell"/"Dunkel" erzwingen einen Modus – siehe
/// AppThemeModePreference.themeMode -> MaterialApp.themeMode in main.dart.
class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker({required this.value, required this.onChanged});

  final AppThemeModePreference value;
  final ValueChanged<AppThemeModePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final mode in AppThemeModePreference.values) ...[
          if (mode != AppThemeModePreference.values.first) const SizedBox(width: 10),
          Expanded(
            child: _ThemeModeTile(
              key: ValueKey('theme-mode-${mode.name}'),
              mode: mode,
              selected: mode == value,
              onTap: () => onChanged(mode),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({super.key, required this.mode, required this.selected, required this.onTap});

  final AppThemeModePreference mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = switch (mode) {
      AppThemeModePreference.system => Icons.brightness_auto_rounded,
      AppThemeModePreference.light => Icons.light_mode_rounded,
      AppThemeModePreference.dark => Icons.dark_mode_rounded,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? c.accent : c.border, width: selected ? 1.5 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? c.accentOnSoft : c.inkMuted),
            const SizedBox(height: 6),
            Text(
              mode.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? c.accentOnSoft : c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountSection extends StatefulWidget {
  const _AccountSection({required this.onSignedIn});

  /// Nach erfolgreicher Anmeldung (z.B. Cloud-Stand anbieten).
  final Future<void> Function() onSignedIn;

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
          onPressed: () async {
            final signedIn = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
            if (signedIn == true && mounted) await widget.onSignedIn();
          },
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

/// Zugangsdaten zum eigenen PDF-Speicher (S3-kompatibel oder WebDAV) –
/// ohne Eintrag bleibt der PDF-Sync aus, alles andere funktioniert trotzdem.
class _PdfStorageSection extends StatefulWidget {
  const _PdfStorageSection({required this.fieldDecoration});

  final InputDecoration Function(BuildContext context, {required String label}) fieldDecoration;

  @override
  State<_PdfStorageSection> createState() => _PdfStorageSectionState();
}

class _PdfStorageSectionState extends State<_PdfStorageSection> {
  late PdfStorageType _type;
  final _endpoint = TextEditingController();
  final _bucket = TextEditingController();
  final _region = TextEditingController();
  final _accessKey = TextEditingController();
  final _secret = TextEditingController();
  late bool _pathStyle;
  bool _busy = false;
  String? _message;
  int? _pending;
  late final SettingsRepository _repo;

  /// Gespeicherter Stand, den die Felder zeigen, und ob seitdem hier etwas
  /// geändert wurde – kommt der Speicher per Cloud-Download an, werden die
  /// Felder nachgeführt, außer der Nutzer tippt gerade selbst.
  String _shownConfig = '';
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _repo = context.read<SettingsRepository>();
    _fill(_repo.settings.pdfStorage);
    _repo.addListener(_onSettingsChanged);
    _refreshPending();
  }

  void _fill(PdfStorageConfig config) {
    _type = config.type;
    _endpoint.text = config.endpoint;
    _bucket.text = config.bucket;
    _region.text = config.region;
    _accessKey.text = config.accessKey;
    _secret.text = config.secret;
    _pathStyle = config.pathStyle;
    _shownConfig = jsonEncode(config.toMap());
    _edited = false;
  }

  void _onSettingsChanged() {
    final config = _repo.settings.pdfStorage;
    if (!mounted || _edited || jsonEncode(config.toMap()) == _shownConfig) return;
    setState(() => _fill(config));
  }

  void _markEdited([Object? _]) => _edited = true;

  @override
  void dispose() {
    _repo.removeListener(_onSettingsChanged);
    for (final c in [_endpoint, _bucket, _region, _accessKey, _secret]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshPending() async {
    final count = await PdfCloudSyncService.countPending();
    if (mounted) setState(() => _pending = count);
  }

  PdfStorageConfig get _config => PdfStorageConfig(
        type: _type,
        endpoint: _endpoint.text.trim(),
        bucket: _bucket.text.trim(),
        region: _region.text.trim().isEmpty ? 'auto' : _region.text.trim(),
        accessKey: _accessKey.text.trim(),
        secret: _secret.text,
        pathStyle: _pathStyle,
      );

  Future<void> _saveAndTest() async {
    final repo = context.read<SettingsRepository>();
    final config = _config;
    setState(() {
      _busy = true;
      _message = null;
    });
    await repo.update(repo.settings.copyWith(pdfStorage: config));
    _shownConfig = jsonEncode(config.toMap());
    _edited = false;
    final store = PdfCloudStore.fromConfig(config);
    if (store == null) {
      setState(() {
        _busy = false;
        _message = config.type == PdfStorageType.none ? 'PDF-Speicher ausgeschaltet.' : 'Bitte alle Felder ausfüllen.';
      });
      return;
    }
    try {
      await store.testConnection();
      if (mounted) {
        final autoSync = context.read<AutoSyncService>();
        final signedIn = context.read<AuthRepository>().currentUser != null;
        setState(() => _message = !signedIn
            ? 'Verbindung klappt. Gespeichert. Mit Konto-Anmeldung kommt der Speicher per Sync '
                'auch auf deine anderen Geräte.'
            : repo.settings.autoSyncEnabled && autoSync.target != null
                ? 'Verbindung klappt. Gespeichert – der Auto-Sync bringt ihn auf deine anderen Geräte.'
                : 'Verbindung klappt. Gespeichert. Für deine anderen Geräte: beim Konto "Hochladen", '
                    'dort "Herunterladen".');
      }
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadNow() async {
    final store = PdfCloudStore.fromConfig(context.read<SettingsRepository>().settings.pdfStorage);
    final autoSync = context.read<AutoSyncService>();
    if (store == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // Mit Auslösen des (Auto-)Syncs: die neuen Verweise sollen in die Cloud.
      final count = await PdfCloudSyncService(store).uploadPending(
        onProgress: (done, total) {
          if (mounted) setState(() => _message = 'Lade PDFs hoch … $done/$total');
        },
      );
      autoSync.requestSync();
      if (mounted) {
        setState(() => _message = count == 0
            ? 'Alle PDFs sind schon im Speicher.'
            : '$count PDF${count == 1 ? '' : 's'} hochgeladen. Andere Geräte holen sie beim Öffnen ab '
                '(nach dem nächsten Sync der Lerndaten).');
      }
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refreshPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final saved = context.watch<SettingsRepository>().settings.pdfStorage;
    final pdfError = context.watch<AutoSyncService>().lastPdfError;
    final field = widget.fieldDecoration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Damit die Original-PDFs auch auf deinen anderen Geräten da sind, trägst du hier deinen '
          'eigenen Speicher ein – z.B. Cloudflare R2 oder Backblaze B2 (S3-kompatibel, 10 GB '
          'kostenlos) oder eine Nextcloud/Uni-Cloud (WebDAV). Ohne Eintrag bleibt der PDF-Sync aus; '
          'Text, Karten und Lernstand synchronisieren trotzdem. Einmal eintragen reicht: mit '
          'Konto-Anmeldung reisen die Zugangsdaten (wie der API-Key) per Sync auf deine anderen '
          'Geräte, über einen Sync-Code nicht. Im Web muss der Speicher CORS erlauben.',
          style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 12),
        SegmentedButton<PdfStorageType>(
          segments: [
            for (final t in PdfStorageType.values) ButtonSegment(value: t, label: Text(t.label)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() {
            _type = s.first;
            _edited = true;
          }),
        ),
        if (_type == PdfStorageType.s3) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _endpoint,
            onChanged: _markEdited,
            decoration: field(context, label: 'Endpunkt (z.B. https://<konto>.r2.cloudflarestorage.com)'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: TextField(controller: _bucket, onChanged: _markEdited, decoration: field(context, label: 'Bucket'))),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: TextField(controller: _region, onChanged: _markEdited, decoration: field(context, label: 'Region')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(controller: _accessKey, onChanged: _markEdited, decoration: field(context, label: 'Access Key ID')),
          const SizedBox(height: 10),
          TextField(controller: _secret, onChanged: _markEdited, obscureText: true, decoration: field(context, label: 'Secret Access Key')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pathStyle,
            onChanged: (v) => setState(() {
              _pathStyle = v;
              _edited = true;
            }),
            title: const Text('Pfad-Adressierung'),
            subtitle: Text('An für R2, B2, MinIO; aus für neue AWS-Buckets.',
                style: TextStyle(fontSize: 12, color: c.inkMuted)),
          ),
        ],
        if (_type == PdfStorageType.webdav) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _endpoint,
            onChanged: _markEdited,
            decoration: field(context, label: 'Ordner-URL (z.B. …/remote.php/dav/files/NAME/Lernen)'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _accessKey, onChanged: _markEdited, decoration: field(context, label: 'Benutzername')),
          const SizedBox(height: 10),
          TextField(controller: _secret, onChanged: _markEdited, obscureText: true, decoration: field(context, label: 'App-Passwort')),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(onPressed: _busy ? null : _saveAndTest, child: const Text('Speichern & testen')),
            if (saved.isConfigured)
              OutlinedButton(
                onPressed: _busy || (_pending ?? 0) == 0 ? null : _uploadNow,
                child: Text('PDFs hochladen${_pending == null ? '' : ' ($_pending offen)'}'),
              ),
          ],
        ),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_message!, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
          ),
        if (pdfError != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Letzter automatischer PDF-Upload: $pdfError', style: TextStyle(fontSize: 12, color: c.warn)),
          ),
      ],
    );
  }
}

/// Schalter für den automatischen Upload (siehe AutoSyncService) plus
/// dessen aktueller Zustand.
class _AutoSyncTile extends StatelessWidget {
  const _AutoSyncTile({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final autoSync = context.watch<AutoSyncService>();
    final noTarget = enabled && autoSync.target == null;
    final status = noTarget
        ? 'Noch kein Ziel: mit einem Konto anmelden oder oben einen Sync-Code eintragen und einmal hochladen.'
        : switch (autoSync.status) {
            AutoSyncStatus.idle => enabled ? 'Alles hochgeladen.' : null,
            AutoSyncStatus.pending => 'Änderungen werden gleich hochgeladen …',
            AutoSyncStatus.syncing => 'Lädt hoch …',
            AutoSyncStatus.retrying =>
              'Upload fehlgeschlagen (${autoSync.lastError ?? 'offline?'}) – wird automatisch wiederholt.',
            AutoSyncStatus.conflict =>
              'Ein anderes Gerät hat inzwischen hochgeladen. Damit dessen Fortschritt nicht '
                  'überschrieben wird, lädt dieses Gerät nicht automatisch hoch – erst "Herunterladen" '
                  '(oder bewusst "Hochladen", um den Cloud-Stand zu ersetzen).',
          };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            onChanged: onChanged,
            title: const Text('Automatisch hochladen'),
            subtitle: Text(
              'Lädt Änderungen kurz nach dem Lernen selbst hoch; offline wird es später nachgeholt.',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
          ),
          if (status != null)
            Text(
              status,
              style: TextStyle(
                fontSize: 12,
                color: noTarget || autoSync.status == AutoSyncStatus.conflict ? c.warn : c.inkMuted,
                height: 1.4,
              ),
            ),
        ],
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
