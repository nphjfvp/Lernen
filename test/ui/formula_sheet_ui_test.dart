import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/formula_sheet.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/summary.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/summary_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/condense/condense_screen.dart';
import 'package:lernen/ui/prepare/prepare_screen.dart';
import 'package:lernen/ui/prepare/summary_detail_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast.dart' as sembast;

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Settings extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

class _NoKeySettings extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings();
}

/// Materialien im Speicher: der Bildschirm soll nicht an die echte DB für das Material kommen.
class _Materials extends MaterialRepository {
  _Materials(this.items);
  final List<MaterialItem> items;

  @override
  List<MaterialItem> forModule(String moduleId) => [for (final m in items) if (m.moduleId == moduleId) m];

  @override
  Future<void> loadForModule(String moduleId) async {}

  @override
  Future<void> save(MaterialItem material) async {
    items.removeWhere((m) => m.id == material.id);
    items.add(material);
  }
}

http.Response _chat(String content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

String get _integralAnswer => jsonEncode({
      'title': 'Formelsammlung Integralrechnung',
      'sections': [
        {
          'title': 'Integrationsregeln',
          'entries': [
            {'name': 'Partielle Integration', 'formula': r"\int u v' dx = uv - \int u' v dx", 'level': 'kern', 'source': 'folien'},
            {'name': 'Substitution', 'formula': r"\int f(g(x))g'(x)dx", 'level': 'kern', 'source': 'folien'},
          ],
        },
        {
          'title': 'Ableitungsregeln',
          'entries': [
            {'name': 'Produktregel', 'formula': r"(uv)' = u'v + uv'", 'level': 'hilfsregel', 'source': 'ergaenzt'},
          ],
        },
        {
          'title': 'Potenzgesetze',
          'entries': [
            {'name': 'Potenzgesetz', 'formula': r'a^m \cdot a^n = a^{m+n}', 'level': 'rechenregel', 'source': 'ergaenzt'},
            {'name': 'Bruchaddition', 'formula': r'\frac{a}{b}+\frac{c}{d}', 'level': 'rechenregel', 'source': 'ergaenzt'},
          ],
        },
      ],
    });

MaterialItem _slides() => MaterialItem(
      id: 'mat1',
      moduleId: 'fm',
      fileName: 'Integralrechnung.pdf',
      kind: MaterialKind.slide,
      extractedText: 'Partielle Integration: ∫ u v\' dx = uv − ∫ u\' v dx',
      createdAt: DateTime(2026, 9, 1),
    );

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_formula_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() => PrepareScreen.aiFactory = null);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Wartet (mit echter Zeit für die Datenbank), bis [done] gilt – höchstens ~6 Sekunden.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var waited = 0; waited < 6000 && !done(); waited += 50) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<List<Summary>> storedSummaries(WidgetTester tester) => tester.runAsync(() async {
        final db = await DatabaseService.instance.database;
        final records = await DatabaseService.summaries.find(db, finder: sembast.Finder(filter: sembast.Filter.equals('moduleId', 'fm')));
        return [for (final r in records) Summary.fromMap(r.value)];
      }).then((v) => v!);

  Future<void> pumpPrepare(WidgetTester tester, {bool withKey = true, List<MaterialItem>? materials}) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MaterialRepository>.value(value: _Materials(materials ?? [_slides()])),
        ChangeNotifierProvider<SummaryRepository>(create: (_) => SummaryRepository()),
        ChangeNotifierProvider<LectureUnitRepository>(create: (_) => LectureUnitRepository()),
        ChangeNotifierProvider<SettingsRepository>.value(value: withKey ? _Settings() : _NoKeySettings()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const PrepareScreen(moduleId: 'fm'),
      ),
    ));
    await tester.pump();
  }

  Future<void> toReady(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('mode-formeln')));
    await tester.pump();
    await tester.tap(find.text('Vorhandenes Material verwenden'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await settle(tester);
  }

  testWidgets('Formelsammlung: Modus wählen, Genauigkeit wählen, erstellen, umstellen, speichern', (tester) async {
    late Map<String, dynamic> request;
    PrepareScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            request = jsonDecode(r.body) as Map<String, dynamic>;
            return _chat(_integralAnswer);
          }),
        );
    await pumpPrepare(tester);
    expect(find.text('Formelsammlung erstellen'), findsOneWidget); // Modus in der Auswahl
    await toReady(tester);

    // Genauigkeit: Standard Mittel, mit Erklärung; auf Fein umstellen.
    expect(find.byKey(const ValueKey('formula-detail-pick')), findsOneWidget);
    expect(find.textContaining('Das Neue plus die Regeln aus früheren Themen'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('formula-detail-pick')), matching: find.text('Fein')));
    await tester.pump();
    expect(find.textContaining('Bruch-, Potenz- und Logarithmusregeln'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('prepare-generate')));
    await settle(tester);
    final prompt = (((request['messages'] as List).last as Map)['content']) as String;
    expect(prompt, contains('Partielle Integration'));

    // Vorschau: Fein zeigt alle 5 Formeln, Ergänztes ist markiert.
    expect(find.text('Formelsammlung Integralrechnung'), findsOneWidget);
    expect(find.byKey(const ValueKey('formula-count')), findsOneWidget);
    expect(find.text('5 Formeln'), findsOneWidget);
    expect(find.text('Potenzgesetz'), findsOneWidget);
    expect(find.byKey(const ValueKey('formula-supplemented')), findsWidgets);

    // Auf Mittel: Rechenregeln weg; auf Grob: auch die Ableitungsregel weg.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('formula-detail')), matching: find.text('Mittel')));
    await tester.pump();
    expect(find.text('3 von 5 Formeln'), findsOneWidget);
    expect(find.text('Potenzgesetz'), findsNothing);
    expect(find.text('Produktregel'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('formula-detail')), matching: find.text('Grob')));
    await tester.pump();
    expect(find.text('2 von 5 Formeln'), findsOneWidget);
    expect(find.text('Produktregel'), findsNothing);
    expect(find.text('Partielle Integration'), findsOneWidget);

    // Speichern: die Sammlung wird mit der gewählten Ansicht (Grob) abgelegt, alles bleibt gespeichert.
    await tester.tap(find.byKey(const ValueKey('prepare-save')));
    await settle(tester);
    final saved = await storedSummaries(tester);
    expect(saved, hasLength(1));
    expect(saved.single.isFormulaSheet, isTrue);
    expect(saved.single.title, 'Formelsammlung Integralrechnung');
    expect(saved.single.formulaSheet!.detail, FormulaDetail.grob);
    expect(saved.single.formulaSheet!.totalCount, 5);
    expect(saved.single.sourceMaterialIds, ['mat1']);
    await tester.runAsync(() async {
      final db = await DatabaseService.instance.database;
      await DatabaseService.summaries.delete(db);
    });
  });

  testWidgets('Verwerfen geht zurück zur Auswahl der Genauigkeit; ohne API-Key steht der Grund da', (tester) async {
    await pumpPrepare(tester, withKey: false);
    await toReady(tester);
    await tester.tap(find.byKey(const ValueKey('prepare-generate')));
    await settle(tester);
    expect(find.textContaining('Kein OpenRouter-API-Key'), findsOneWidget);
    expect(find.byKey(const ValueKey('formula-detail-pick')), findsOneWidget);
  });

  testWidgets('Fehler der KI (keine Formeln): Meldung, Auswahl bleibt', (tester) async {
    PrepareScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async => _chat(jsonEncode({'title': 'x', 'sections': []}))),
        );
    await pumpPrepare(tester);
    await toReady(tester);
    await tester.tap(find.byKey(const ValueKey('prepare-generate')));
    await settle(tester);
    expect(find.textContaining('keine Formeln gefunden'), findsOneWidget);
    expect(find.byKey(const ValueKey('formula-detail-pick')), findsOneWidget);
  });

  group('SummaryDetailScreen mit Formelsammlung', () {
    Summary sheet({FormulaDetail detail = FormulaDetail.mittel}) => Summary(
          id: 'sheet1',
          moduleId: 'fm',
          sourceMaterialIds: const [],
          title: 'Formelsammlung',
          overview: '',
          keyPoints: const [],
          createdAt: DateTime(2026, 10, 1),
          formulaSheet: FormulaSheet.fromMap({
            'detail': detail.name,
            'sections': (jsonDecode(_integralAnswer) as Map)['sections'],
          }),
        );

    Future<void> pumpDetail(WidgetTester tester, Summary summary) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async => SummaryRepository().save(summary));
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<SummaryRepository>(create: (_) => SummaryRepository())],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: SummaryDetailScreen(summary: summary),
        ),
      ));
      await tester.pump();
    }

    Future<Summary> stored(WidgetTester tester) async =>
        (await storedSummaries(tester)).firstWhere((s) => s.id == 'sheet1');

    tearDown(() async {});

    testWidgets('Genauigkeit lässt sich später ändern und bleibt gespeichert, nichts geht verloren', (tester) async {
      await pumpDetail(tester, sheet());
      expect(find.text('3 von 5 Formeln'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('formula-detail')), matching: find.text('Fein')));
      await settle(tester);
      expect(find.text('5 Formeln'), findsOneWidget);
      var s = await stored(tester);
      expect(s.formulaSheet!.detail, FormulaDetail.fein);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('formula-detail')), matching: find.text('Grob')));
      await settle(tester);
      s = await stored(tester);
      expect(s.formulaSheet!.detail, FormulaDetail.grob);
      expect(s.formulaSheet!.totalCount, 5);
    });

    testWidgets('Bearbeiten: Eintrag ändern, löschen, hinzufügen', (tester) async {
      await pumpDetail(tester, sheet(detail: FormulaDetail.fein));
      await tester.tap(find.byIcon(Icons.edit_outlined).first); // AppBar: Bearbeiten
      await tester.pump();
      expect(find.text('Fertig'), findsOneWidget);

      // Ändern
      await tester.tap(find.byKey(const ValueKey('formula-edit-Substitution')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('formula-field-name')), 'Substitutionsregel');
      await tester.enterText(find.byKey(const ValueKey('formula-field-formula')), r'\int f(t)\,dt');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('formula-dialog-save')));
      // Der Name steht auch im (noch schließenden) Dialog – maßgeblich ist der Eintrag selbst.
      await until(tester, () => find.byKey(const ValueKey('formula-edit-Substitutionsregel')).evaluate().isNotEmpty);
      await tester.pumpAndSettle(); // Dialog schließt
      expect(find.text('Substitutionsregel'), findsOneWidget);
      expect(find.text('Substitution'), findsNothing);

      // Löschen (und der Abschnitt "Ableitungsregeln" verschwindet mit seinem letzten Eintrag)
      await tester.tap(find.byKey(const ValueKey('formula-delete-Produktregel')));
      await until(tester, () => find.text('Ableitungsregeln').evaluate().isEmpty);
      expect(find.text('Ableitungsregeln'), findsNothing);

      // Hinzufügen
      await tester.tap(find.byKey(const ValueKey('formula-add-Integrationsregeln')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('formula-field-name')), 'Linearität');
      await tester.enterText(find.byKey(const ValueKey('formula-field-formula')), r'\int (af+bg) = a\int f + b\int g');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('formula-dialog-save')));
      await until(tester, () => find.byKey(const ValueKey('formula-edit-Linearität')).evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.text('Linearität'), findsOneWidget);

      final s = await stored(tester);
      final names = [for (final sec in s.formulaSheet!.sections) ...sec.entries.map((e) => e.name)];
      expect(names, containsAll(['Substitutionsregel', 'Linearität', 'Partielle Integration']));
      expect(names, isNot(contains('Produktregel')));
      expect(names, isNot(contains('Substitution')));
      expect(s.formulaSheet!.totalCount, 5); // 5 - 1 gelöscht + 1 neu
    });

    testWidgets('Kopieren legt die Sammlung (bei der gewählten Genauigkeit) in die Zwischenablage', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpDetail(tester, sheet(detail: FormulaDetail.grob));
      await tester.tap(find.byKey(const ValueKey('formula-copy')));
      await settle(tester);
      expect(copied, contains('# Formelsammlung (Grob)'));
      expect(copied, contains('Partielle Integration'));
      expect(copied, isNot(contains('Produktregel')));
      expect(find.textContaining('kopiert'), findsOneWidget);
    });

    testWidgets('Eine normale Zusammenfassung sieht unverändert aus (kein Umschalter)', (tester) async {
      final plain = Summary(
        id: 'plain1',
        moduleId: 'fm',
        sourceMaterialIds: const [],
        title: 'Normal',
        overview: 'Übersicht',
        keyPoints: const ['Punkt'],
        createdAt: DateTime(2026, 10, 1),
      );
      await pumpDetail(tester, plain);
      expect(find.byKey(const ValueKey('formula-detail')), findsNothing);
      expect(find.text('Kernkonzepte'), findsOneWidget);
      expect(find.byKey(const ValueKey('formula-copy')), findsNothing);
    });
  });

  testWidgets('Vorbereiten: die Karte "Vorlesung kürzen" öffnet Kürzen statt eines weiteren Vorbereiten-Weges', (tester) async {
    await pumpPrepare(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('mode-kuerzen')));
    await tester.tap(find.byKey(const ValueKey('mode-kuerzen')));
    await tester.pumpAndSettle();
    expect(find.byType(CondenseScreen), findsOneWidget);
    // Ersetzt den Vorbereiten-Bildschirm: zurück geht es zum Fach, nicht in die Moduswahl.
    expect(find.byType(PrepareScreen), findsNothing);
    expect(find.byKey(const ValueKey('condense-lecture')), findsOneWidget);
    // Der Vorbereiten-Bildschirm hat beim Start die Datenbank geöffnet – in der Test-Uhr; echte Zeit
    // lassen, sonst bleibt das Öffnen hängen und blockiert die Tests dahinter.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  });
}
