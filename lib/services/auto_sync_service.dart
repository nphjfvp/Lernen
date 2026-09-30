import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../repositories/auth_repository.dart';
import '../repositories/settings_repository.dart';
import 'database_service.dart';
import 'pdf_cloud_store.dart';
import 'pdf_cloud_sync_service.dart';
import 'sync_diagnostics.dart';
import 'sync_merge.dart';
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

  /// Die Cloud hat einen neueren Stand von einem anderen Gerät und das
  /// automatische Zusammenführen ist mehrfach nicht gelungen (z.B. weil das
  /// andere Gerät ständig weiter hochlädt) – dann in den Einstellungen
  /// "Abgleichen".
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
/// hochgeladen, wird nichts überschrieben, sondern zusammengeführt (siehe
/// SyncService.merge): was hier neu oder weiter ist, kommt in die Cloud, was dort
/// neu oder weiter ist, hierher. Das passiert auch beim Start und beim
/// Zurückkehren in die App ([checkCloud]), damit der Stand des anderen Geräts
/// ohne Zutun ankommt.
class AutoSyncService extends ChangeNotifier with WidgetsBindingObserver {
  AutoSyncService({
    required this._settings,
    required this._auth,
    SyncService? sync,
    this.onDataChanged,
  }) : _sync = sync ?? SyncService();

  /// Wird aufgerufen, nachdem ein Abgleich lokale Daten verändert hat – die App
  /// lädt dann Fächerliste, Laborversuche und Einstellungen neu.
  final Future<void> Function()? onDataChanged;

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

  /// Was der letzte automatische Abgleich getan hat (siehe describeMerge), z.B.
  /// "In der Cloud neu oder geändert: 3 Karten." – `null`, wenn er nichts
  /// zusammenführen musste.
  String? _lastMergeMessage;
  String? get lastMergeMessage => _lastMergeMessage;

  /// Letzter Fehler beim Hochladen der PDFs in den eigenen Speicher – hält
  /// den Sync der Lerndaten bewusst NICHT auf.
  String? _lastPdfError;
  String? get lastPdfError => _lastPdfError;

  Timer? _timer;
  bool _disposed = false;
  bool _dirty = false;
  bool _running = false;
  int _suppressDepth = 0;
  int _retryIndex = 0;
  int _conflictRetries = 0;
  Database? _db;

  /// Die Speicher, deren Änderung einen Upload auslöst. Alles, was in
  /// SyncService._buildPayload steht und sich unabhängig von Karten ändern
  /// kann, gehört hierher (sonst bleibt es bis zur nächsten Kartenänderung
  /// lokal).
  @visibleForTesting
  static final watchedStores = [
    DatabaseService.modules,
    DatabaseService.materials,
    DatabaseService.summaries,
    DatabaseService.concepts,
    DatabaseService.flashcards,
    DatabaseService.lectureUnits,
    DatabaseService.labExperiments,
    DatabaseService.chatMessages,
  ];

  /// Stand der mitgesyncten Einstellungen beim letzten Blick – ändert sich
  /// z.B. der API-Key, ein Modell oder der PDF-Speicher, soll das genauso
  /// hochgeladen werden wie eine neue Karte (sonst kommt es auf den anderen
  /// Geräten erst beim nächsten gelernten Stück an).
  String? _settingsSignature;

  Future<void> start() async {
    if (!_sync.isAvailable) return;
    final db = await DatabaseService.instance.database;
    _db = db;
    for (final store in watchedStores) {
      store.addOnChangesListener(db, _onChanges);
    }
    _settingsSignature = _currentSettingsSignature();
    _settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    // Kurz nach dem Start nachsehen, ob ein anderes Gerät weitergelernt hat.
    unawaited(Future<void>.delayed(startCheckDelay, checkCloud));
  }

  /// Wartezeit vor dem ersten Blick in die Cloud – die App soll erst stehen.
  @visibleForTesting
  static Duration startCheckDelay = const Duration(seconds: 4);

  String _currentSettingsSignature() =>
      jsonEncode(syncedSettingsOf(_settings.settings, includeSecrets: true));

  void _onSettingsChanged() {
    final signature = _currentSettingsSignature();
    if (signature == _settingsSignature) return; // z.B. nur "zuletzt synchronisiert"
    _settingsSignature = signature;
    _markDirty();
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
    _settingsSignature = _currentSettingsSignature();
    _timer?.cancel();
    _dirty = false;
    _retryIndex = 0;
    _conflictRetries = 0;
    _lastError = null;
    _setStatus(AutoSyncStatus.idle);
  }

  void _onChanges(Transaction txn, List<RecordChange<String, Map<String, Object?>>> changes) => _markDirty();

  void _markDirty() {
    if (_disposed || _suppressDepth > 0 || !_settings.settings.autoSyncEnabled) return;
    _dirty = true;
    if (_status == AutoSyncStatus.conflict) return; // wartet auf "Abgleichen" in den Einstellungen
    _schedule(debounce);
    if (_status != AutoSyncStatus.retrying) _setStatus(AutoSyncStatus.pending);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(syncNow()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Beim Zurückkehren nachsehen, ob ein anderes Gerät weitergelernt hat.
    if (state == AppLifecycleState.resumed) unawaited(checkCloud());
    if (!_dirty) return;
    // Beim Verlassen (sonst liefe der Debounce-Timer im Hintergrund evtl. nie
    // ab) und beim Zurückkehren (Nachholen nach Offline-Zeit) sofort.
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(syncNow());
    }
  }

  /// Sieht in der Cloud nach, ob ein ANDERES Gerät seit dem letzten Abgleich
  /// hochgeladen hat, und führt dann zusammen. Ohne so einen Stand (oder ohne
  /// Netz) passiert nichts. Liegen lokale Änderungen an, übernimmt [syncNow]
  /// – der Upload merkt den fremden Stand ohnehin und führt zusammen.
  Future<void> checkCloud() async {
    if (_disposed || _running || !_settings.settings.autoSyncEnabled) return;
    if (_dirty) return syncNow();
    final target = this.target;
    if (target == null || !_sync.isAvailable) return;
    _running = true;
    try {
      final deviceId = await ensureDeviceId(_settings);
      final meta = await _sync.cloudMeta(target);
      if (!isBlockedByOtherDevice(
        meta: meta,
        lastSyncedPushId: _settings.settings.lastSyncedPushId,
        deviceId: deviceId,
      )) {
        return;
      }
      _setStatus(AutoSyncStatus.syncing);
      final pushId = await _mergeWithCloud(target, deviceId);
      await _settings.update(_settings.settings.copyWith(lastSyncAt: DateTime.now(), lastSyncedPushId: pushId));
      _lastError = null;
      _conflictRetries = 0;
      _setStatus(_dirty ? AutoSyncStatus.pending : AutoSyncStatus.idle);
    } catch (_) {
      // Offline o.ä.: kein Grund zu warnen – beim nächsten Start, Zurückkehren
      // oder Upload wird es erneut versucht.
      if (_status == AutoSyncStatus.syncing) _setStatus(AutoSyncStatus.idle);
    } finally {
      _running = false;
    }
  }

  /// Führt den Stand mit dem der Cloud zusammen und liefert die `pushId`, die
  /// jetzt als "zuletzt abgeglichen" gilt.
  Future<String?> _mergeWithCloud(SyncTarget target, String deviceId) async {
    final outcome = await runWithoutTrigger(() async {
      final outcome = await _sync.merge(target, deviceId: deviceId);
      // Der Abgleich schreibt Einstellungen (Key, Modelle …) direkt in die
      // Datenbank – vor dem nächsten Speichern neu laden, ohne dass die
      // übernommenen Werte gleich wieder hochgeladen werden.
      await _settings.load();
      return outcome;
    });
    _settingsSignature = _currentSettingsSignature();
    final result = outcome.result;
    _lastMergeMessage = result == null || (result.changedLocally == 0 && result.changedRemotely == 0)
        ? null
        : describeMerge(result);
    if (outcome.changedLocally) await onDataChanged?.call();
    return outcome.pushId;
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
      await _uploadPendingPdfs();
      String? pushId;
      try {
        pushId = await _sync.push(
          target,
          deviceId: deviceId,
          abortIf: (cloud) => isBlockedByOtherDevice(meta: cloud, lastSyncedPushId: lastSynced, deviceId: deviceId),
        );
      } on SyncConflictException {
        // Ein anderes Gerät hat hochgeladen: nichts überschreiben, sondern
        // abgleichen – beide Stände bleiben erhalten.
        pushId = await _mergeWithCloud(target, deviceId);
      }
      _conflictRetries = 0;
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
      // Das andere Gerät hat während des Abgleichs schon wieder hochgeladen.
      // Ein paar Mal neu versuchen, danach bleibt es beim manuellen "Abgleichen".
      _dirty = true;
      _lastError = null;
      _conflictRetries += 1;
      if (_conflictRetries <= 3) {
        _schedule(const Duration(seconds: 20));
        _setStatus(AutoSyncStatus.pending);
      } else {
        _setStatus(AutoSyncStatus.conflict);
      }
    } catch (e) {
      _dirty = true;
      _lastError = e is SyncException ? e.message : SyncDiagnostics.describeError(e);
      _schedule(retryDelays[_retryIndex.clamp(0, retryDelays.length - 1)]);
      _retryIndex += 1;
      _setStatus(AutoSyncStatus.retrying);
    } finally {
      _running = false;
    }
  }

  /// PDFs zuerst in den eigenen Speicher, damit der anschließende Upload der
  /// Lerndaten schon die Verweise darauf enthält. Ohne Speicher: nichts.
  Future<void> _uploadPendingPdfs() async {
    final store = PdfCloudStore.fromConfig(_settings.settings.pdfStorage);
    if (store == null) return;
    try {
      await runWithoutTrigger(() => PdfCloudSyncService(store).uploadPending());
      _lastPdfError = null;
    } catch (e) {
      _lastPdfError = e is PdfCloudStoreException ? e.message : e.toString();
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
    _disposed = true;
    _timer?.cancel();
    final db = _db;
    if (db != null) {
      for (final store in watchedStores) {
        try {
          store.removeOnChangesListener(db, _onChanges);
        } on TypeError {
          // Sembast vergleicht beim Entfernen Listener verschiedener Typen
          // und scheitert dabei an der Typprüfung – dann bleibt der Listener
          // eben registriert, [_disposed] schaltet ihn stumm.
        }
      }
      _settings.removeListener(_onSettingsChanged);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
