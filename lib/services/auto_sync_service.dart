import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../repositories/auth_repository.dart';
import '../repositories/settings_repository.dart';
import 'database_service.dart';
import 'sync_service.dart';

enum AutoSyncStatus {
  /// Alles hochgeladen (oder Auto-Sync aus).
  idle,

  /// Änderungen warten auf den verzögerten Upload.
  pending,

  /// Upload läuft.
  syncing,

  /// Upload fehlgeschlagen (z.B. offline) – wird automatisch wiederholt.
  retrying,

  /// Die Cloud hat einen neueren Stand von einem anderen Gerät – ein
  /// automatischer Upload würde ihn überschreiben, daher erst herunterladen.
  conflict,
}

/// Lädt lokale Änderungen automatisch in die Cloud hoch, sobald
/// [AppSettings.autoSyncEnabled] an ist: kurz verzögert nach der letzten
/// Änderung (viele Antworten hintereinander ergeben so EINEN Upload), bei
/// Fehlern (offline) mit wachsenden Abständen erneut und beim Zurückkehren in
/// die App sofort. Ziel ist das angemeldete Konto, sonst der gespeicherte
/// Sync-Code.
///
/// Schutz vor Datenverlust: hat seit dem letzten Abgleich ein ANDERES Gerät
/// hochgeladen, wird nicht automatisch überschrieben ([AutoSyncStatus.conflict])
/// – dann erst in den Einstellungen herunterladen.
class AutoSyncService extends ChangeNotifier with WidgetsBindingObserver {
  AutoSyncService({
    required this._settings,
    required this._auth,
    SyncService? sync,
  }) : _sync = sync ?? SyncService();

  final SettingsRepository _settings;
  final AuthRepository _auth;
  final SyncService _sync;

  /// Wartezeit nach der letzten Änderung – viele Antworten hintereinander
  /// ergeben so EINEN Upload. Beim Verlassen der App wird sofort hochgeladen.
  static const debounce = Duration(seconds: 30);
  static const retryDelays = [
    Duration(minutes: 1),
    Duration(minutes: 3),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];

  AutoSyncStatus _status = AutoSyncStatus.idle;
  AutoSyncStatus get status => _status;

  String? _lastError;
  String? get lastError => _lastError;

  Timer? _timer;
  bool _dirty = false;
  bool _running = false;
  int _suppressDepth = 0;
  int _retryIndex = 0;
  Database? _db;

  static final _watchedStores = [
    DatabaseService.modules,
    DatabaseService.materials,
    DatabaseService.summaries,
    DatabaseService.concepts,
    DatabaseService.flashcards,
    DatabaseService.lectureUnits,
  ];

  Future<void> start() async {
    if (!_sync.isAvailable) return;
    final db = await DatabaseService.instance.database;
    _db = db;
    for (final store in _watchedStores) {
      store.addOnChangesListener(db, _onChanges);
    }
    WidgetsBinding.instance.addObserver(this);
  }

  /// Welche Cloud-Stelle der Auto-Sync gerade bedienen würde, oder null.
  SyncTarget? get target {
    final uid = _auth.currentUser?.uid;
    if (uid != null) return SyncTarget.account(uid);
    final code = _settings.settings.syncCode?.trim();
    if (code != null && code.isNotEmpty) return SyncTarget.code(code);
    return null;
  }

  /// Führt [action] aus, ohne dass die dabei geschriebenen Daten einen
  /// Upload auslösen – für den Download (der schreibt alle Stores neu).
  Future<T> runWithoutTrigger<T>(Future<T> Function() action) async {
    // Zähler statt bool: überlappende Aufrufe dürfen die Sperre nicht
    // vorzeitig aufheben.
    _suppressDepth += 1;
    try {
      return await action();
    } finally {
      _suppressDepth -= 1;
    }
  }

  /// Nach dem Einschalten: den aktuellen Stand einmal hochladen, auch wenn
  /// seitdem noch nichts geändert wurde.
  void requestSync() {
    _dirty = true;
    unawaited(syncNow());
  }

  /// Nach einem manuellen Up- oder Download: Konflikt/Warteschlange
  /// zurücksetzen, der lokale Stand entspricht jetzt der Cloud.
  void markInSync() {
    _timer?.cancel();
    _dirty = false;
    _retryIndex = 0;
    _lastError = null;
    _setStatus(AutoSyncStatus.idle);
  }

  void _onChanges(Transaction txn, List<RecordChange<String, Map<String, Object?>>> changes) {
    if (_suppressDepth > 0 || !_settings.settings.autoSyncEnabled) return;
    _dirty = true;
    if (_status == AutoSyncStatus.conflict) return; // wartet auf Download
    _schedule(debounce);
    if (_status != AutoSyncStatus.retrying) _setStatus(AutoSyncStatus.pending);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(syncNow()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_dirty || _status == AutoSyncStatus.conflict) return;
    // Beim Verlassen (sonst liefe der Debounce-Timer im Hintergrund evtl. nie
    // ab) und beim Zurückkehren (Nachholen nach Offline-Zeit) sofort.
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(syncNow());
    }
  }

  /// Lädt sofort hoch, falls Änderungen anstehen und Auto-Sync aktiv ist.
  Future<void> syncNow() async {
    if (_running || !_dirty || !_settings.settings.autoSyncEnabled) return;
    final target = this.target;
    if (target == null) return;
    _running = true;
    _timer?.cancel();
    _setStatus(AutoSyncStatus.syncing);
    try {
      final deviceId = await ensureDeviceId(_settings);
      final lastSynced = _settings.settings.lastSyncedPushId;
      _dirty = false;
      final pushId = await _sync.push(
        target,
        deviceId: deviceId,
        abortIf: (cloud) => isBlockedByOtherDevice(meta: cloud, lastSyncedPushId: lastSynced, deviceId: deviceId),
      );
      await _settings.update(_settings.settings.copyWith(lastSyncAt: DateTime.now(), lastSyncedPushId: pushId));
      _retryIndex = 0;
      _lastError = null;
      if (_dirty) {
        // Während des Uploads kamen neue Änderungen dazu.
        _schedule(debounce);
        _setStatus(AutoSyncStatus.pending);
      } else {
        _setStatus(AutoSyncStatus.idle);
      }
    } on SyncConflictException {
      _dirty = true;
      _lastError = null;
      _setStatus(AutoSyncStatus.conflict);
    } catch (e) {
      _dirty = true;
      _lastError = e is SyncException ? e.message : e.toString();
      _schedule(retryDelays[_retryIndex.clamp(0, retryDelays.length - 1)]);
      _retryIndex += 1;
      _setStatus(AutoSyncStatus.retrying);
    } finally {
      _running = false;
    }
  }

  void _setStatus(AutoSyncStatus status) {
    _status = status;
    notifyListeners();
  }

  /// true, wenn der Cloud-Stand seit dem letzten Abgleich von einem anderen
  /// Gerät hochgeladen wurde – dann darf nicht automatisch überschrieben
  /// werden. Rein, damit testbar.
  static bool isBlockedByOtherDevice({
    required CloudSyncMeta? meta,
    required String? lastSyncedPushId,
    required String deviceId,
  }) {
    if (meta == null || meta.pushId == null) return false; // leer oder altes Format
    if (meta.pushId == lastSyncedPushId) return false;
    return meta.deviceId != deviceId;
  }

  /// Liefert die Gerätekennung und legt sie beim ersten Mal an.
  static Future<String> ensureDeviceId(SettingsRepository settings) async {
    final existing = settings.settings.deviceId;
    if (existing != null) return existing;
    final id = const Uuid().v4();
    await settings.update(settings.settings.copyWith(deviceId: id));
    return id;
  }

  @override
  void dispose() {
    _timer?.cancel();
    final db = _db;
    if (db != null) {
      for (final store in _watchedStores) {
        store.removeOnChangesListener(db, _onChanges);
      }
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
