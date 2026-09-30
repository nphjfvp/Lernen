import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/sync_backup_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/settings/sync_backups_dialog.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sembast/sembast.dart' hide Finder;

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_sync_backups_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  testWidgets('Sicherungen: Liste mit Stand, Wiederherstellen nach Rückfrage bringt den Stand zurück', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<List<String>> moduleNames() async =>
        (await tester.runAsync<List<String>>(() async {
          final db = await DatabaseService.instance.database;
          return [for (final r in await DatabaseService.modules.find(db)) r.value['name'] as String]..sort();
        }))!;

    await tester.runAsync(() async {
      final db = await DatabaseService.instance.database;
      await DatabaseService.modules.record('m1').put(
            db,
            Module(id: 'm1', name: 'Gesichertes Fach', colorValue: 0xFF112233, icon: '📘', examDate: null, createdAt: DateTime(2026, 1, 1))
                .toMap(),
          );
      await SyncBackupService.create(db, kind: SyncBackupService.kindPull, reason: 'Vor dem Herunterladen');
      // Danach "überschreibt ein Download" den Stand.
      await DatabaseService.modules.delete(db);
      await DatabaseService.modules.record('m2').put(
            db,
            Module(id: 'm2', name: 'Fremdes Fach', colorValue: 0xFF112233, icon: '📘', examDate: null, createdAt: DateTime(2026, 1, 1))
                .toMap(),
          );
    });
    expect(await moduleNames(), ['Fremdes Fach']);

    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await showDialog<bool>(context: context, builder: (_) => const SyncBackupsDialog()),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Öffnen'));
    // Die Liste kommt aus der echten Datenbank.
    for (var i = 0; i < 60 && find.text('Vor einem Download', skipOffstage: false).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Sicherungen auf diesem Gerät'), findsOneWidget);
    expect(find.textContaining('Vor einem Download · 1 Fächer'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Wiederherstellen'));
    await tester.pumpAndSettle();
    expect(find.text('Diese Sicherung wiederherstellen?'), findsOneWidget);
    expect(find.textContaining('du kannst es also zurücknehmen'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Wiederherstellen'));
    for (var i = 0; i < 60 && result == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(await moduleNames(), ['Gesichertes Fach']);
  });
}
