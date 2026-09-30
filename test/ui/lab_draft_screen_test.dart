import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/repositories/lab_experiment_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/lab/lab_draft_screen.dart';
import 'package:lernen/ui/lab/lab_experiment_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _SettingsWithKey extends SettingsRepository {
  _SettingsWithKey({this.withKey = true});
  final bool withKey;

  @override
  AppSettings get settings => AppSettings(openRouterApiKey: withKey ? 'sk-test' : null);
}

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
    notifyListeners();
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

final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

LabExperiment _experiment({List<String> templates = const []}) => LabExperiment.fromStructure(
      {
        'title': 'Oszilloskop',
        'prepQuestions': [
          {'number': '1', 'question': 'Wozu dient der Trigger?'},
        ],
        'parts': [
          {
            'title': 'Grundeinstellungen',
            'steps': ['Tastkopf anschließen'],
            'tables': [
              {
                'title': 'Messwerte',
                'columns': ['Frequenz', 'Amplitude'],
                'rows': [
                  ['1 kHz', '2 V'],
                ],
              },
            ],
          },
        ],
      },
      moduleId: 'm1',
      now: DateTime(2026, 9, 1),
      id: 'lab1',
    ).copyWith(reportTemplateIds: templates);

MaterialItem _template() => MaterialItem(
      id: 'tpl',
      moduleId: 'm1',
      fileName: 'Berichtsvorlage.docx',
      kind: MaterialKind.slide,
      extractedText: '1 Zielsetzung\n2 Versuchsaufbau\n3 Auswertung',
      createdAt: DateTime(2026, 9, 1),
    );

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_draft_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() {
    LabDraftScreen.aiFactory = null;
    LabDraftScreen.pickFilesHook = null;
  });

  late LabExperimentRepository labs;

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    required LabExperiment experiment,
    List<MaterialItem> materials = const [],
    bool withKey = true,
  }) async {
    tester.view.physicalSize = const Size(900, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = await tester.runAsync(() => databaseFactoryMemory.openDatabase('draft_ui_${DateTime.now().microsecondsSinceEpoch}'));
    labs = LabExperimentRepository(openDatabase: () async => db!);
    await tester.runAsync(() => labs.save(experiment));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LabExperimentRepository>.value(value: labs),
        ChangeNotifierProvider<MaterialRepository>.value(value: _Materials([...materials])),
        ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey(withKey: withKey)),
      ],
      child: MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: home),
    ));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  const draftJson = r'''
{"sections": [
  {"sectionId": "%S0%", "title": "Einleitung", "text": "Im Versuch wurde ein Oszilloskop untersucht."},
  {"sectionId": "%S1%", "title": "Grundeinstellungen", "text": "Bei 1 kHz ergab sich eine Amplitude von 2 V. [ergänzen: Tastkopfteilung]"},
  {"sectionId": null, "title": "Anhang", "text": "[Abbildung: Schaltplan]"}
 ],
 "missing": ["Schaltplan", "Messunsicherheiten"]}
''';

  String draftFor(LabExperiment e) =>
      draftJson.replaceAll('%S0%', e.report[0].id).replaceAll('%S1%', e.report[1].id);

  testWidgets('Entwurf erstellen: Vorlage geht mit, Entwürfe landen in den Abschnitten, Neues wird angelegt', (tester) async {
    final e = _experiment(templates: ['tpl']);
    String? prompt;
    LabDraftScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            prompt = ((jsonDecode(r.body)['messages'] as List).last['content']) as String;
            return _chat(draftFor(e));
          }),
        );
    await pump(tester, const LabDraftScreen(experimentId: 'lab1', moduleName: 'ET'), experiment: e, materials: [_template()]);

    expect(find.byKey(const ValueKey('draft-template-tpl')), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('draft-specs')), matching: find.byType(TextField)), 'max. 3 Seiten');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('draft-create')));
    await settle(tester);

    expect(prompt, contains('=== Vorlage / Vorgaben: Berichtsvorlage.docx ==='));
    expect(prompt, contains('2 Versuchsaufbau'));
    expect(prompt, contains('max. 3 Seiten'));
    expect(prompt, contains('1 kHz | 2 V')); // Messwerte des Versuchs
    expect(prompt, contains('Gliederung: der Vorlage folgen'));

    final saved = labs.byId('lab1')!;
    expect(saved.reportSpecs, 'max. 3 Seiten');
    expect(saved.report.map((s) => s.title), [
      'Einleitung und Versuchsziel',
      'Grundeinstellungen',
      'Anhang',
      'Diskussion und Fazit',
    ]);
    expect(saved.report[0].draft, contains('Oszilloskop untersucht'));
    expect(saved.report[1].draft, contains('[ergänzen: Tastkopfteilung]'));
    expect(saved.report[2].draft, contains('Schaltplan'));
    expect(saved.report.every((s) => s.text.isEmpty), isTrue);

    expect(find.byKey(const ValueKey('draft-done')), findsOneWidget);
    expect(find.text('•  Schaltplan'), findsOneWidget);
    expect(find.text('•  Messunsicherheiten'), findsOneWidget);
  });

  testWidgets('Gliederung nicht übernehmen: keine neuen Abschnitte, Gerüst-Modus wird gemeldet', (tester) async {
    final e = _experiment(templates: ['tpl']);
    String? prompt;
    LabDraftScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            prompt = ((jsonDecode(r.body)['messages'] as List).last['content']) as String;
            return _chat(draftFor(e));
          }),
        );
    await pump(tester, const LabDraftScreen(experimentId: 'lab1', moduleName: 'ET'), experiment: e, materials: [_template()]);

    await tester.tap(find.text('Nur Gerüst'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('draft-structure')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('draft-create')));
    await settle(tester);

    expect(prompt, contains('Modus: Gerüst (Stichpunkte)'));
    expect(prompt, contains('NICHT übernehmen'));
    final saved = labs.byId('lab1')!;
    expect(saved.report, hasLength(3)); // keine Anlage "Anhang"
    expect(saved.report[1].draft, contains('Schaltplan')); // als Unterpunkt in den davor
  });

  testWidgets('Foto der Vorlage geht mit dem Vision-Modell; eine nicht lesbare Datei wird gemeldet', (tester) async {
    final e = _experiment();
    String? model;
    dynamic content;
    LabDraftScreen.aiFactory = (key, m) => AiService(
          apiKey: key,
          model: m,
          client: MockClient((r) async {
            final body = jsonDecode(r.body) as Map<String, dynamic>;
            model = body['model'] as String;
            content = (body['messages'] as List).last['content'];
            return _chat(draftFor(e));
          }),
        );
    LabDraftScreen.pickFilesHook = ({required bool images}) async =>
        images ? [(name: 'vorlage.png', bytes: Uint8List.fromList(_tinyPng))] : [(name: 'vorlage.txt', bytes: Uint8List.fromList([65, 66]))];
    await pump(tester, const LabDraftScreen(experimentId: 'lab1', moduleName: 'ET'), experiment: e);

    await tester.tap(find.byKey(const ValueKey('draft-upload')));
    await settle(tester);
    expect(find.byKey(const ValueKey('draft-error')), findsOneWidget);
    expect(find.textContaining('Nicht unterstütztes Dateiformat'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('draft-image')));
    for (var i = 0; i < 40 && find.byKey(const ValueKey('draft-image-0')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('draft-image-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('draft-create')));
    await settle(tester);
    expect(content, isA<List<dynamic>>());
    expect(model, AppSettings.defaultVisionModel);
  });

  testWidgets('ohne API-Key ist "Entwurf erstellen" aus', (tester) async {
    await pump(tester, const LabDraftScreen(experimentId: 'lab1', moduleName: 'ET'), experiment: _experiment(), withKey: false);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('draft-create'))).onPressed, isNull);
    expect(find.textContaining('OpenRouter-Key'), findsOneWidget);
  });

  testWidgets('Bericht-Reiter: Entwurf steht getrennt vom eigenen Text, Übernehmen hängt an, Verwerfen räumt weg', (tester) async {
    var e = _experiment();
    e = e.updateSection(e.report[0].id, (s) => s.copyWith(text: 'Mein eigener Anfang.', draft: 'Entwurf **Einleitung** mit \$T = 1/f\$'));
    e = e.updateSection(e.report[1].id, (s) => s.copyWith(draft: 'Entwurf zu Teil 1'));
    await pump(tester, LabExperimentScreen(experimentId: 'lab1', moduleName: 'ET'), experiment: e);
    await tester.tap(find.text('Bericht'));
    await tester.pumpAndSettle();

    expect(find.textContaining('nur zur Inspiration'), findsWidgets);
    expect(find.byKey(ValueKey('draft-panel-${e.report[0].id}')), findsOneWidget);
    expect(find.byKey(ValueKey('draft-panel-${e.report[1].id}')), findsOneWidget);
    // Wo schon ein Entwurf liegt, gibt es den Knopf "Neu erzeugen" statt "Entwurf zur Inspiration" am Abschnitt.
    expect(find.byKey(ValueKey('draft-section-${e.report[0].id}')), findsNothing);
    expect(find.byKey(ValueKey('draft-section-${e.report[2].id}')), findsOneWidget);

    await tester.ensureVisible(find.byKey(ValueKey('draft-adopt-${e.report[0].id}')));
    await tester.tap(find.byKey(ValueKey('draft-adopt-${e.report[0].id}')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final adopted = labs.byId('lab1')!.report[0];
    expect(adopted.text, startsWith('Mein eigener Anfang.\n\nEntwurf **Einleitung**'));
    expect(adopted.draft, '');
    expect(find.byKey(ValueKey('draft-panel-${e.report[0].id}')), findsNothing);
    // Das Textfeld zeigt den neuen Text sofort.
    expect(find.textContaining('Mein eigener Anfang.', findRichText: true), findsWidgets);

    await tester.ensureVisible(find.byKey(ValueKey('draft-discard-${e.report[1].id}')));
    await tester.tap(find.byKey(ValueKey('draft-discard-${e.report[1].id}')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(labs.byId('lab1')!.report[1].draft, '');
    expect(labs.byId('lab1')!.report[1].text, '');
  });

  testWidgets('Entwurf kopieren legt den Text in die Zwischenablage', (tester) async {
    var e = _experiment();
    e = e.updateSection(e.report[0].id, (s) => s.copyWith(draft: 'Nur zum Kopieren'));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pump(tester, LabExperimentScreen(experimentId: 'lab1', moduleName: 'ET'), experiment: e);
    await tester.tap(find.text('Bericht'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(ValueKey('draft-copy-${e.report[0].id}')));
    await tester.tap(find.byKey(ValueKey('draft-copy-${e.report[0].id}')));
    await tester.pump();
    expect(copied, 'Nur zum Kopieren');
  });

  testWidgets('Entwurf für einen einzelnen Abschnitt: eigener Titel, ändert nur diesen', (tester) async {
    final e = _experiment();
    final target = e.report[1];
    String? prompt;
    LabDraftScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            prompt = ((jsonDecode(r.body)['messages'] as List).last['content']) as String;
            return _chat('{"sections": [{"sectionId": "${target.id}", "title": "x", "text": "Nur dieser Abschnitt"}], "missing": []}');
          }),
        );
    await pump(
      tester,
      LabExperimentScreen(experimentId: 'lab1', moduleName: 'ET'),
      experiment: e,
    );
    await tester.tap(find.text('Bericht'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(ValueKey('draft-section-${target.id}')));
    await tester.tap(find.byKey(ValueKey('draft-section-${target.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Entwurf: Grundeinstellungen'), findsOneWidget);
    expect(find.byKey(const ValueKey('draft-structure')), findsNothing); // bei einem Abschnitt gibt es keine Gliederung

    await tester.tap(find.byKey(const ValueKey('draft-create')));
    await settle(tester);
    expect(prompt, contains('NUR den Entwurf für den Abschnitt mit der id ${target.id}'));
    final saved = labs.byId('lab1')!;
    expect(saved.report[1].draft, 'Nur dieser Abschnitt');
    expect(saved.report[0].draft, '');
    expect(saved.report, hasLength(3));
  });
}
