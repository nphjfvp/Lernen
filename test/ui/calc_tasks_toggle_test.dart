import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/widgets/calc_tasks_toggle.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// Hält die Einstellungen im Speicher (die Datenbank ist hier unwichtig).
class _MemorySettings extends SettingsRepository {
  AppSettings _value = const AppSettings();

  @override
  AppSettings get settings => _value;

  @override
  Future<void> update(AppSettings next) async {
    _value = next;
    notifyListeners();
  }
}

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePathProviderPlatform(Directory.systemTemp.createTempSync('calc_toggle_').path);
  });

  testWidgets('Schalter "Rechenaufgaben": an/aus, speichert die Einstellung, meldet die Änderung', (tester) async {
    final settings = _MemorySettings();
    final changes = <bool>[];
    await tester.pumpWidget(ChangeNotifierProvider<SettingsRepository>.value(
      value: settings,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(body: CalcTasksToggle(onChanged: changes.add, note: '2 Rechenaufgaben heute aufgehoben')),
      ),
    ));
    expect(find.text('Rechenaufgaben: an'), findsOneWidget);
    expect(find.text('2 Rechenaufgaben heute aufgehoben'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calc-tasks-toggle')));
    await tester.pump();
    expect(settings.settings.includeCalcTasks, isFalse);
    expect(changes, [false]);
    expect(find.text('Rechenaufgaben: aus'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calc-tasks-toggle')));
    await tester.pump();
    expect(settings.settings.includeCalcTasks, isTrue);
    expect(changes, [false, true]);
  });

  testWidgets('ohne Einstellungen (z.B. in Tests anderer Bildschirme) gilt "an"', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Builder(
        builder: (context) => Text(CalcTasksToggle.includeOf(context) ? 'an' : 'aus'),
      ),
    ));
    expect(find.text('an'), findsOneWidget);
  });
}
