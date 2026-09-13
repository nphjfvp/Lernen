import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:lernen/main.dart';
import 'package:lernen/repositories/settings_repository.dart';

/// path_provider hat in Widget-Tests keinen echten Platform-Channel – ohne
/// dieses Fake würde jeder DB-Zugriff (Sembast öffnet die Datei über
/// getApplicationSupportDirectory) mit MissingPluginException abbrechen.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = await Directory.systemTemp.createTemp('lernen_test_');
    return dir.path;
  }
}

void main() {
  setUp(() {
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  testWidgets('App startet und zeigt die leere Fächer-Übersicht', (tester) async {
    await tester.pumpWidget(LernenApp(settingsRepository: SettingsRepository()));
    // pumpAndSettle wartet auf "keine Animation mehr aktiv" – die (im
    // Hintergrund weiterlaufende) CircularProgressIndicator im Daily-Quiz-
    // Tab (IndexedStack hält alle Tabs aktiv) würde das nie erfüllen, daher
    // hier gezielt auf die asynchronen DB-Loads warten statt auf Animationen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Meine Fächer'), findsOneWidget);
    expect(find.text('Erstes Fach anlegen'), findsOneWidget);
  });
}
