import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/repositories/auth_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/auto_sync_service.dart';
import 'package:lernen/services/sync_merge.dart';
import 'package:lernen/services/sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// Tut so, als wäre Firebase verbunden: ein anderes Gerät hat in der Cloud
/// hochgeladen ([cloud]), der Upload dieses Geräts meldet dann den Konflikt und
/// der Abgleich liefert [outcome].
class _FakeSync extends SyncService {
  @override
  bool get isAvailable => true;

  CloudSyncMeta? cloud;
  bool conflictOnPush = false;
  bool failMerge = false;
  int pushes = 0;
  int merges = 0;
  SyncMergeOutcome outcome = const SyncMergeOutcome(pushId: 'gemeinsam-1', pushed: true);

  @override
  Future<String> push(
    SyncTarget target, {
    required String deviceId,
    bool Function(CloudSyncMeta? cloud)? abortIf,
    bool forceHistory = false,
  }) async {
    pushes++;
    if (conflictOnPush) throw SyncConflictException('anderes Gerät');
    return 'push-$pushes';
  }

  @override
  Future<SyncMergeOutcome> merge(SyncTarget target, {required String deviceId, bool alwaysUpload = false}) async {
    merges++;
    if (failMerge) throw SyncConflictException('schon wieder ein anderes Gerät');
    return outcome;
  }

  @override
  Future<CloudSyncMeta?> cloudMeta(SyncTarget target) async => cloud;
}

SyncMergeOutcome _outcome({int cards = 3}) => SyncMergeOutcome(
      pushId: 'gemeinsam-1',
      pushed: true,
      result: SyncMergeResult(
        payload: const {},
        collections: {'flashcards': CollectionMerge(changedLocally: cards, changedRemotely: 1)},
      ),
    );

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_auto_sync_merge_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
    AutoSyncService.startCheckDelay = const Duration(hours: 1); // im Test ruft nur der Test selbst checkCloud auf
  });

  Future<(AutoSyncService, SettingsRepository, _FakeSync, List<int>)> setup({String? lastSynced}) async {
    final settings = SettingsRepository();
    await settings.update(AppSettings(autoSyncEnabled: true, syncCode: 'mein-code', lastSyncedPushId: lastSynced));
    final sync = _FakeSync();
    final reloads = <int>[];
    final autoSync = AutoSyncService(
      settings: settings,
      auth: AuthRepository(),
      sync: sync,
      onDataChanged: () async => reloads.add(1),
    );
    await autoSync.start();
    addTearDown(autoSync.dispose);
    return (autoSync, settings, sync, reloads);
  }

  test('Konflikt beim Upload: statt zu blockieren wird zusammengeführt, die Ansichten laden neu', () async {
    final (autoSync, settings, sync, reloads) = await setup(lastSynced: 'alt');
    sync
      ..conflictOnPush = true
      ..outcome = _outcome(cards: 3);

    autoSync.requestSync();
    await _until(() => sync.merges == 1 && autoSync.status == AutoSyncStatus.idle);

    expect(sync.pushes, 1);
    expect(sync.merges, 1);
    expect(autoSync.status, AutoSyncStatus.idle);
    expect(settings.settings.lastSyncedPushId, 'gemeinsam-1');
    expect(reloads, hasLength(1));
    expect(autoSync.lastMergeMessage, contains('3 Karten'));
  });

  test('Abgleich ohne Änderung an diesem Gerät: keine Neuladung, keine Meldung', () async {
    final (autoSync, _, sync, reloads) = await setup(lastSynced: 'alt');
    sync
      ..conflictOnPush = true
      ..outcome = const SyncMergeOutcome(pushId: 'gemeinsam-2', pushed: false);

    autoSync.requestSync();
    await _until(() => sync.merges == 1 && autoSync.status == AutoSyncStatus.idle);

    expect(reloads, isEmpty);
    expect(autoSync.lastMergeMessage, isNull);
  });

  test('scheitert der Abgleich immer wieder am Konflikt, bleibt es nach ein paar Versuchen beim manuellen Abgleichen', () async {
    final (autoSync, _, sync, _) = await setup(lastSynced: 'alt');
    sync
      ..conflictOnPush = true
      ..failMerge = true;

    autoSync.requestSync();
    await _until(() => sync.merges == 1);
    // Der erste Fehlschlag wird bald wiederholt (Status "wartet"), nicht sofort aufgegeben.
    expect(autoSync.status, AutoSyncStatus.pending);
    // Wiederholungen von Hand anstoßen, bis die Grenze erreicht ist.
    for (var i = 0; i < 3; i++) {
      final before = sync.merges;
      autoSync.requestSync();
      await _until(() => sync.merges > before && autoSync.status != AutoSyncStatus.syncing);
    }
    expect(autoSync.status, AutoSyncStatus.conflict);
  });

  test('checkCloud: ein anderes Gerät hat hochgeladen → zusammenführen, ohne dass hier etwas geändert wurde', () async {
    final (autoSync, settings, sync, reloads) = await setup(lastSynced: 'alt');
    sync
      ..cloud = const CloudSyncMeta(pushId: 'vom-pc', deviceId: 'anderes-geraet')
      ..outcome = _outcome(cards: 2);

    await autoSync.checkCloud();

    expect(sync.merges, 1);
    expect(sync.pushes, 0);
    expect(settings.settings.lastSyncedPushId, 'gemeinsam-1');
    expect(reloads, hasLength(1));
    expect(autoSync.status, AutoSyncStatus.idle);
  });

  test('checkCloud: nichts Neues (schon abgeglichen oder vom eigenen Gerät) → nichts passiert', () async {
    final (autoSync, settings, sync, _) = await setup(lastSynced: 'vom-pc');
    sync.cloud = const CloudSyncMeta(pushId: 'vom-pc', deviceId: 'anderes-geraet');
    await autoSync.checkCloud();
    expect(sync.merges, 0);

    final own = settings.settings.deviceId ?? await AutoSyncService.ensureDeviceId(settings);
    sync.cloud = CloudSyncMeta(pushId: 'neu', deviceId: own);
    await autoSync.checkCloud();
    expect(sync.merges, 0);

    sync.cloud = null;
    await autoSync.checkCloud();
    expect(sync.merges, 0);
  });

  test('checkCloud ohne Netz oder Auto-Sync: still, ohne Fehleranzeige', () async {
    final (autoSync, settings, sync, _) = await setup(lastSynced: 'alt');
    sync
      ..cloud = const CloudSyncMeta(pushId: 'vom-pc', deviceId: 'anderes-geraet')
      ..failMerge = true;
    await autoSync.checkCloud();
    expect(autoSync.lastError, isNull);
    expect(autoSync.status, AutoSyncStatus.idle);

    await settings.update(settings.settings.copyWith(autoSyncEnabled: false));
    sync.failMerge = false;
    final before = sync.merges;
    await autoSync.checkCloud();
    expect(sync.merges, before);
  });
}
