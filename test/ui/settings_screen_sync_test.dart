import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/pdf_storage_config.dart';
import 'package:lernen/repositories/auth_repository.dart';
import 'package:lernen/repositories/model_catalog_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/auto_sync_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/settings/settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

const _storage = PdfStorageConfig(
  type: PdfStorageType.s3,
  endpoint: 'https://konto.r2.cloudflarestorage.com',
  bucket: 'lernen',
  accessKey: 'ak',
  secret: 'geheim',
);

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_settings_sync_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
    PackageInfo.setMockInitialValues(
      appName: 'Lernen',
      packageName: 'com.pius.lernen',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('nach einem Download zeigen die Felder die neuen Werte und schreiben keine alten zurück',
      (tester) async {
    tester.view.physicalSize = const Size(900, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = SettingsRepository();
    final auth = AuthRepository();
    await tester.runAsync(() => settings.update(const AppSettings()));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => ModelCatalogRepository()),
        ChangeNotifierProvider(create: (_) => ModuleRepository()),
        ChangeNotifierProvider(create: (_) => AutoSyncService(settings: settings, auth: auth)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const Scaffold(body: SettingsScreen())),
    ));
    await tester.pump();

    TextField field(String label) => tester.widget<TextField>(
          find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label),
        );
    expect(field('OpenRouter API-Key').controller!.text, '');

    // Wie ein Cloud-Download: die Einstellungen ändern sich von außen.
    await tester.runAsync(() => settings.update(settings.settings.copyWith(
          openRouterApiKey: 'sk-vom-handy',
          pdfStorage: _storage,
        )));
    await tester.pump();

    expect(field('OpenRouter API-Key').controller!.text, 'sk-vom-handy');
    expect(field('Bucket').controller!.text, 'lernen');
    expect(field('Access Key ID').controller!.text, 'ak');

    // Feld antippen und wieder verlassen darf den Key nicht mit einem
    // veralteten Stand überschreiben.
    await tester.tap(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'OpenRouter API-Key'));
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(settings.settings.openRouterApiKey, 'sk-vom-handy');
    expect(settings.settings.pdfStorage.bucket, 'lernen');

    await tester.pumpWidget(const SizedBox());
  });
}
