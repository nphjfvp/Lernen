import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/lab_experiment_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/calendar/calendar_screen.dart';
import 'package:lernen/ui/lab/lab_experiment_screen.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;

class _Modules extends ModuleRepository {
  _Modules(this.items);
  final List<Module> items;

  @override
  List<Module> get modules => items;
}

class _Materials extends MaterialRepository {
  @override
  List<MaterialItem> forModule(String moduleId) => const [];

  @override
  Future<void> loadForModule(String moduleId) async {}
}

class _Settings extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings();
}

void main() {
  testWidgets('Kalender: Labortermin und Berichtsabgabe stehen im Tag, Tippen öffnet den Versuch', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final db = await tester.runAsync(() => databaseFactoryMemory.openDatabase('lab_cal_${DateTime.now().microsecondsSinceEpoch}'));
    final labs = LabExperimentRepository(openDatabase: () async => db!);
    await tester.runAsync(() async {
      await labs.save(LabExperiment(
        id: 'lab1',
        moduleId: 'm1',
        title: 'Oszilloskop',
        createdAt: day,
        labDate: day,
        reportDue: day,
      ));
      await labs.save(LabExperiment(
        id: 'lab2',
        moduleId: 'm1',
        title: 'Abgegeben',
        createdAt: day,
        reportDue: day,
        finished: true,
      ));
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ModuleRepository>.value(
          value: _Modules([
            Module(id: 'm1', name: 'Elektrotechnik', colorValue: 0xFF3D5AFE, icon: '⚡', examDate: null, createdAt: day),
          ]),
        ),
        ChangeNotifierProvider<LabExperimentRepository>.value(value: labs),
        ChangeNotifierProvider<MaterialRepository>.value(value: _Materials()),
        ChangeNotifierProvider<SettingsRepository>.value(value: _Settings()),
      ],
      child: MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: const CalendarScreen()),
    ));
    await tester.pump();

    expect(find.text('Laborversuch: Oszilloskop'), findsOneWidget);
    expect(find.text('Bericht abgeben: Oszilloskop'), findsOneWidget);
    // Ein abgegebener Bericht ist keine Frist mehr.
    expect(find.text('Bericht abgeben: Abgegeben'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('calendar-lab-lab-lab1')));
    await tester.pumpAndSettle();
    expect(find.byType(LabExperimentScreen), findsOneWidget);
    expect(find.text('Elektrotechnik'), findsOneWidget);
  });
}
