import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/pdf_storage_config.dart';
import 'package:lernen/repositories/auth_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/auto_sync_service.dart';
import 'package:lernen/services/sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// Tut so, als wäre Firebase verbunden – hochgeladen wird im Test nie (der
/// Upload wartet auf den 30-s-Debounce).
class _FakeSync extends SyncService {
  @override
  bool get isAvailable => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_auto_sync_settings_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  test('geänderte Zugangsdaten/Modelle lösen den Auto-Sync aus, reine Sync-Buchhaltung nicht', () async {
    final settings = SettingsRepository();
    await settings.update(const AppSettings(autoSyncEnabled: true, syncCode: 'mein-code'));
    final autoSync = AutoSyncService(settings: settings, auth: AuthRepository(), sync: _FakeSync());
    await autoSync.start();
    addTearDown(autoSync.dispose);
    expect(autoSync.status, AutoSyncStatus.idle);

    // Nur "zuletzt synchronisiert" – kein neuer Upload.
    await settings.update(settings.settings.copyWith(lastSyncAt: DateTime(2026, 9, 27)));
    expect(autoSync.status, AutoSyncStatus.idle);

    // Eigener PDF-Speicher eingetragen – soll auf die anderen Geräte.
    await settings.update(settings.settings.copyWith(
      pdfStorage: const PdfStorageConfig(
        type: PdfStorageType.s3,
        endpoint: 'https://x.r2.cloudflarestorage.com',
        bucket: 'b',
        accessKey: 'ak',
        secret: 'sk',
      ),
    ));
    expect(autoSync.status, AutoSyncStatus.pending);

    autoSync.markInSync();
    await settings.update(settings.settings.copyWith(questionModelId: 'anthropic/claude-sonnet'));
    expect(autoSync.status, AutoSyncStatus.pending);
  });
}
