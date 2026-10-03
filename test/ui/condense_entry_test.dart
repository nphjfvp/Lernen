import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/condense.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/concept_repository.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/summary_repository.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/condense/condense_screen.dart';
import 'package:lernen/ui/modules/module_detail_screen.dart';
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

/// Einstiegspunkte von "Kürzen" im Fach und die Darstellung gekürzter Dokumente.
void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_condense_entry_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  var counter = 0;
  late String moduleId;

  Future<void> pump(WidgetTester tester, List<MaterialItem> Function(String moduleId) materialsFor) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    moduleId = 'm-entry-${counter++}';
    final modules = ModuleRepository();
    final materials = MaterialRepository();
    await tester.runAsync(() async {
      await modules.save(Module(
        id: moduleId,
        name: 'Analysis',
        colorValue: 0xFF3D5AFE,
        icon: '📘',
        examDate: null,
        createdAt: DateTime(2026, 1, 1),
      ));
      for (final m in materialsFor(moduleId)) {
        await materials.save(m);
      }
    });
    final settings = SettingsRepository();
    await tester.runAsync(() => settings.update(const AppSettings(openRouterApiKey: 'sk-test')));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: modules),
        ChangeNotifierProvider.value(value: materials),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => SummaryRepository()),
        ChangeNotifierProvider(create: (_) => ConceptRepository()),
        ChangeNotifierProvider(create: (_) => FlashcardRepository()),
        ChangeNotifierProvider(create: (_) => LectureUnitRepository()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: ModuleDetailScreen(moduleId: moduleId)),
    ));
    for (var i = 0; i < 40 && find.text('Materialien').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  MaterialItem lecture(String moduleId) => MaterialItem(
        id: 'lec-$moduleId',
        moduleId: moduleId,
        fileName: 'Analysis.pdf',
        kind: MaterialKind.slide,
        extractedText: 'Skripttext',
        createdAt: DateTime(2026, 9, 1),
      );

  MaterialItem condensed(String moduleId) => MaterialItem(
        id: 'con-$moduleId',
        moduleId: moduleId,
        fileName: 'Analysis – gekürzt',
        kind: MaterialKind.condensed,
        extractedText: 'Gekürzte Fassung: Analysis.pdf\n\n## Seite 2 · Partielle Integration\nDie Formel lautet uv minus Integral.',
        createdAt: DateTime(2026, 9, 2),
        condensed: const CondensedInfo(
          sourceMaterialId: 'x',
          sourceName: 'Analysis.pdf',
          prompt: 'alles',
          pages: [2, 4],
          totalPages: 40,
          notFound: ['Laplace'],
        ),
      );

  testWidgets('ohne Vorlesung im Fach gibt es keinen Kürzen-Knopf', (tester) async {
    await pump(tester, (_) => const []);
    expect(find.byKey(const ValueKey('module-condense')), findsNothing);
  });

  testWidgets('mit Vorlesung: Knopf öffnet "Kürzen"', (tester) async {
    await pump(tester, (m) => [lecture(m)]);
    await tester.ensureVisible(find.byKey(const ValueKey('module-condense')));
    await tester.tap(find.byKey(const ValueKey('module-condense')));
    await tester.pumpAndSettle();
    expect(find.byType(CondenseScreen), findsOneWidget);
    expect(find.text('Vorlesung kürzen'), findsWidgets);
    expect(find.byKey(const ValueKey('condense-lecture')), findsOneWidget);
  });

  testWidgets('Menü einer Folie: "Kürzen …" wählt diese Vorlesung vor', (tester) async {
    await pump(tester, (m) => [lecture(m)]);
    await tester.ensureVisible(find.byTooltip('Weitere Aktionen'));
    await tester.tap(find.byTooltip('Weitere Aktionen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kürzen …'));
    await tester.pumpAndSettle();
    expect(find.byType(CondenseScreen), findsOneWidget);
    expect(tester.widget<CondenseScreen>(find.byType(CondenseScreen)).lectureId, 'lec-$moduleId');
  });

  testWidgets('gekürztes Dokument: Zeile mit Umfang und Herkunft, Text ansehen im Menü', (tester) async {
    await pump(tester, (m) => [lecture(m), condensed(m)]);
    expect(find.text('Gekürzt · 2 von 40 Seiten · aus Analysis.pdf'), findsOneWidget);
    // Neueste zuerst: das gekürzte Dokument bietet "Text ansehen", nur die Folie "Kürzen …".
    final menus = find.byTooltip('Weitere Aktionen');
    expect(menus, findsNWidgets(2));
    await tester.ensureVisible(menus.first);
    await tester.tap(menus.first);
    await tester.pumpAndSettle();
    expect(find.text('Kürzen …'), findsNothing);
    await tester.tap(find.text('Text ansehen und kopieren'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Die Formel lautet uv minus Integral.'), findsOneWidget);
    expect(find.textContaining('Nicht in der Vorlesung: Laplace'), findsOneWidget);
  });
}
