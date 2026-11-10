import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/lecture_unit.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/card_flag_repository.dart';
import 'package:lernen/repositories/concept_repository.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/lab_experiment_repository.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/summary_repository.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/modules/module_detail_screen.dart';
import 'package:lernen/ui/practice/study_sequence_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Fach-Seite in Handybreite (412 px, wie ein Pixel): Die Material-Zeile lief
/// mit „N Aufgaben der Reihe nach“ über und schnitt Dateinamen nach wenigen
/// Zeichen ab.
void main() {
  setUpAll(() {
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      Directory.systemTemp.createTempSync('lernen_module_phone_').path,
    );
  });

  testWidgets('Material-Zeilen am Handy: kein Überlauf, ganzer Name, „der Reihe nach“, Löschen im Menü', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final modules = ModuleRepository();
    final materials = MaterialRepository();
    final cards = FlashcardRepository();
    final units = LectureUnitRepository();
    final settings = SettingsRepository();
    const longName = 'Übung 2 Achse Transportwagen mit sehr langem Dateinamen Wintersemester.pdf';
    await tester.runAsync(() async {
      await settings.update(const AppSettings(openRouterApiKey: 'sk-test'));
      await modules.save(
        Module(
          id: 'ph',
          name: 'Maschinenelemente',
          colorValue: 0xFF3D5AFE,
          icon: '⚙️',
          examDate: null,
          createdAt: DateTime(2026, 9, 1),
        ),
      );
      await units.saveAll([
        LectureUnit(id: 'pu', moduleId: 'ph', title: 'Einheit 2 – Achsen und Wellen', createdAt: DateTime(2026, 9, 8)),
      ]);
      await materials.save(
        MaterialItem(
          id: 'pm',
          moduleId: 'ph',
          fileName: longName,
          kind: MaterialKind.exercise,
          extractedText: 'x',
          createdAt: DateTime(2026, 9, 9),
          unitId: 'pu',
        ),
      );
      await cards.saveAll([
        for (var i = 0; i < 12; i++)
          Flashcard(
            id: 'pc$i',
            moduleId: 'ph',
            front: 'Frage $i',
            back: 'Antwort',
            createdAt: DateTime(2026, 9, 2, 10, i),
            due: DateTime(2026, 9, 2),
            unitId: 'pu',
            sourceMaterialId: 'pm',
          ),
      ]);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: modules),
          ChangeNotifierProvider.value(value: materials),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: cards),
          ChangeNotifierProvider.value(value: units),
          ChangeNotifierProvider(create: (_) => SummaryRepository()),
          ChangeNotifierProvider(create: (_) => ConceptRepository()),
          ChangeNotifierProvider(create: (_) => CardFlagRepository()),
          ChangeNotifierProvider(create: (_) => LabExperimentRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ModuleDetailScreen(moduleId: 'ph'),
        ),
      ),
    );
    for (var i = 0; i < 40 && find.text(longName).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull, reason: 'kein RenderFlex-Überlauf in Handybreite');
    expect(find.text(longName), findsOneWidget);
    expect(find.text('12 Aufgaben der Reihe nach'), findsOneWidget);
    // Der Name bekommt die Breite der Zeile (früher blieben ~100 px).
    expect(tester.getSize(find.text(longName)).width, greaterThan(220));

    // Löschen steht im Menü (mit Rückfrage), nicht mehr neben der Checkbox.
    await tester.ensureVisible(find.byTooltip('Weitere Aktionen'));
    await tester.tap(find.byTooltip('Weitere Aktionen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('material-delete-pm')));
    await tester.pumpAndSettle();
    expect(find.text('Material löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    // Der Link führt in „Der Reihe nach“.
    await tester.ensureVisible(find.byKey(const ValueKey('material-tasks-pm')));
    await tester.tap(find.byKey(const ValueKey('material-tasks-pm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StudySequenceScreen), findsOneWidget);
  });
}
