import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
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

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_settings_theme_skin_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
    PackageInfo.setMockInitialValues(
      appName: 'Lernen',
      packageName: 'com.pius.lernen',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('Standard ist "Klar" markiert, Tippen auf "Lebendig" speichert sofort', (tester) async {
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

    // Vor dem ersten Tippen: "Klar" ist der Standard (fettgedruckt/markiert).
    expect(settings.settings.themeSkin, 'klar');
    Text labelOf(String key) => tester.widget<Text>(find
        .descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))
        .last);
    expect(labelOf('theme-skin-klar').style?.fontWeight, FontWeight.w700);
    expect(labelOf('theme-skin-ruhig').style?.fontWeight, FontWeight.w500);

    await tester.tap(find.byKey(const ValueKey('theme-skin-lebendig')));
    // Schreibt in die echte Datenbank – echte Wartezeit nötig (wie bei
    // anderen speichernden Widget-Tests in diesem Repo).
    for (var i = 0; i < 20 && settings.settings.themeSkin != 'lebendig'; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(settings.settings.themeSkin, 'lebendig');
    expect(labelOf('theme-skin-lebendig').style?.fontWeight, FontWeight.w700);
    expect(labelOf('theme-skin-klar').style?.fontWeight, FontWeight.w500);

    await tester.pumpWidget(const SizedBox());
  });
}
