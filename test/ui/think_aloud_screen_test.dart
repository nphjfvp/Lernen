import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/study/think_aloud_screen.dart';
import 'package:provider/provider.dart';

class _Modules extends ModuleRepository {
  @override
  List<Module> get modules => [
    Module(id: 'm1', name: 'Mathe', colorValue: 0xFF336699, icon: 'calc', examDate: null, createdAt: DateTime(2026)),
    Module(id: 'm2', name: 'Physik', colorValue: 0xFF336699, icon: 'x', examDate: null, createdAt: DateTime(2026)),
  ];
}

class _Settings extends SettingsRepository {
  _Settings(this._value);
  final AppSettings _value;
  @override
  AppSettings get settings => _value;
}

Widget _app(AppSettings settings, {Set<String>? moduleIds}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ModuleRepository>.value(value: _Modules()),
        ChangeNotifierProvider<SettingsRepository>.value(value: _Settings(settings)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: ThinkAloudScreen(moduleIds: moduleIds)),
    );

void main() {
  testWidgets('ohne API-Key: Hinweis statt Start', (tester) async {
    await tester.pumpWidget(_app(const AppSettings()));
    expect(find.textContaining('OpenRouter-Key'), findsOneWidget);
    expect(find.byKey(const ValueKey('think-start')), findsNothing);
  });

  testWidgets('mit Key: Fächer wählbar, Vorauswahl aus dem Fach', (tester) async {
    await tester.pumpWidget(_app(const AppSettings(openRouterApiKey: 'k'), moduleIds: {'m2'}));
    expect(find.byKey(const ValueKey('think-start')), findsOneWidget);
    final mathe = tester.widget<FilterChip>(find.byKey(const ValueKey('think-module-m1')));
    final physik = tester.widget<FilterChip>(find.byKey(const ValueKey('think-module-m2')));
    expect(mathe.selected, isFalse);
    expect(physik.selected, isTrue);
  });
}
