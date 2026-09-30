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
import 'package:lernen/ui/calc/calc_screen.dart';
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
  @override
  List<MaterialItem> forModule(String moduleId) => const [];

  @override
  Future<void> loadForModule(String moduleId) async {}
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

/// Ein gültiges 1×1-PNG.
final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const _ohm = r'''
{"title": "Ohmsches Gesetz",
 "given": [{"symbol": "U", "name": "Spannung", "raw": "12,3 V", "values": [12.3], "unit": "V"},
           {"symbol": "I", "name": "Strom", "raw": "450 mA", "values": [0.45], "unit": "A", "uncertain": true}],
 "steps": [{"symbol": "R", "name": "Widerstand", "latex": "$R = \\frac{U}{I}$", "expression": "U / I", "unit": "Ω",
            "explanation": "Ohmsches Gesetz"},
           {"symbol": "P", "name": "Leistung", "latex": "$P = U \\cdot I$", "expression": "U * I", "unit": "W"}],
 "result": ["R", "P"], "assumptions": ["ideale Messgeräte"], "notes": ["Größenordnung passt"], "missing": []}
''';

const _series = r'''
{"title": "Messreihe", "given": [{"symbol": "U", "values": [2, 4, 6], "unit": "V"}, {"symbol": "I", "values": [0.1, 0.2, 0.3], "unit": "A"}],
 "steps": [{"symbol": "R", "expression": "U / I", "unit": "Ω", "name": "Widerstand"},
           {"symbol": "R_m", "expression": "mean(R)", "unit": "Ω", "name": "Mittelwert"}],
 "result": ["R_m"]}
''';

LabExperiment _experiment() => LabExperiment.fromStructure(
      {
        'title': 'Oszilloskop',
        'parts': [
          {
            'title': 'Grundeinstellungen',
            'goals': ['Widerstand bestimmen'],
            'steps': ['Tastkopf anschließen'],
            'tables': [
              {
                'title': 'Messwerte',
                'columns': ['U', 'I'],
                'rows': [
                  ['2 V', '0,1 A'],
                ],
              },
            ],
            'evaluationQuestions': [
              {'number': '2.1', 'question': 'Wie groß ist der Widerstand?'},
            ],
          },
        ],
      },
      moduleId: 'm1',
      now: DateTime(2026, 9, 1),
      id: 'lab1',
    );

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_calc_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() {
    CalcScreen.aiFactory = null;
    CalcScreen.pickImagesHook = null;
    LabExperimentScreen.aiFactory = null;
  });

  Future<void> pump(WidgetTester tester, Widget home, {bool withKey = true, LabExperimentRepository? labs}) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        if (labs != null) ChangeNotifierProvider<LabExperimentRepository>.value(value: labs),
        ChangeNotifierProvider<MaterialRepository>.value(value: _Materials()),
        ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey(withKey: withKey)),
      ],
      child: MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: home),
    ));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Rechnen: Plan der KI wird von der App durchgerechnet, mit Rechenweg und Ergebnis', (tester) async {
    late Map<String, dynamic> request;
    CalcScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            request = jsonDecode(r.body) as Map<String, dynamic>;
            return _chat(_ohm);
          }),
        );
    await pump(tester, const CalcScreen(moduleName: 'Elektrotechnik', initialTask: 'Berechne R und P'));

    await tester.enterText(find.byKey(const ValueKey('calc-values')), 'U = 12,3 V\nI = 450 mA');
    await tester.tap(find.byKey(const ValueKey('calc-run')));
    await settle(tester);

    final prompt = ((request['messages'] as List).last['content']) as String;
    expect(prompt, contains('Berechne R und P'));
    expect(prompt, contains('U = 12,3 V'));

    expect(find.text('Ohmsches Gesetz'), findsWidgets); // Titel und die Erklärung des Schritts
    expect(find.byKey(const ValueKey('calc-final')), findsOneWidget);
    // Die App rechnet: 12,3 / 0,45 = 27,33 Ω, 12,3 · 0,45 = 5,535 W.
    expect(find.text('R = 27,33 Ω'), findsWidgets);
    expect(find.text('P = 5,535 W'), findsWidgets);
    expect(find.text('R = 12,3 V / 0,45 A'), findsOneWidget); // eingesetzt
    expect(find.text('P = 12,3 V · 0,45 A'), findsOneWidget);
    expect(find.textContaining('Unsicher gelesen'), findsOneWidget); // I war unsicher
    expect(find.textContaining('ideale Messgeräte'), findsOneWidget);
    expect(find.textContaining('Größenordnung passt'), findsOneWidget);
  });

  testWidgets('einen gelesenen Wert korrigieren rechnet sofort neu (ohne weitere KI-Anfrage)', (tester) async {
    var requests = 0;
    CalcScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            requests++;
            return _chat(_ohm);
          }),
        );
    await pump(tester, const CalcScreen(moduleName: 'ET', initialTask: 'Rechne'));
    await tester.tap(find.byKey(const ValueKey('calc-run')));
    await settle(tester);
    expect(find.text('R = 27,33 Ω'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey('calc-given-I')), '0,5');
    await tester.pump();
    expect(find.text('R = 24,6 Ω'), findsWidgets);
    expect(find.text('R = 12,3 V / 0,5 A'), findsOneWidget);
    expect(find.textContaining('Unsicher gelesen'), findsNothing); // selbst eingegeben = geprüft
    expect(requests, 1);

    // Keine Zahl: Hinweis am Feld, Ergebnis bleibt beim letzten gültigen Wert.
    await tester.enterText(find.byKey(const ValueKey('calc-given-I')), 'abc');
    await tester.pump();
    expect(find.text('Das ist keine Zahl.'), findsOneWidget);
    expect(find.text('R = 24,6 Ω'), findsWidgets);
  });

  testWidgets('Messreihe: Tabelle mit jeder Zeile und Kennzahl darunter', (tester) async {
    CalcScreen.aiFactory = (key, model) => AiService(apiKey: key, model: model, client: MockClient((r) async => _chat(_series)));
    await pump(tester, const CalcScreen(moduleName: 'ET', initialTask: 'Widerstand je Messung'));
    await tester.tap(find.byKey(const ValueKey('calc-run')));
    await settle(tester);

    expect(find.byKey(const ValueKey('calc-series-R')), findsOneWidget);
    expect(find.text('R in Ω'), findsOneWidget);
    expect(find.text('20'), findsWidgets);
    expect(find.text('R_m = 20 Ω'), findsWidgets);
  });

  testWidgets('Bilder gehen mit (Vision-Modell), Fehler der KI werden angezeigt', (tester) async {
    String? model;
    dynamic content;
    CalcScreen.aiFactory = (key, m) => AiService(
          apiKey: key,
          model: m,
          client: MockClient((r) async {
            final body = jsonDecode(r.body) as Map<String, dynamic>;
            model = body['model'] as String;
            content = (body['messages'] as List).last['content'];
            return _chat('kein json');
          }),
        );
    CalcScreen.pickImagesHook = () async => [
          (name: 'tabelle.png', bytes: _tinyPng),
        ];
    await pump(tester, const CalcScreen(moduleName: 'ET'));
    await tester.tap(find.byKey(const ValueKey('calc-add-image')));
    // Das Verkleinern des Bildes läuft in der echten Engine.
    for (var i = 0; i < 40 && find.byKey(const ValueKey('calc-image-0')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('calc-image-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calc-run')));
    await settle(tester);
    expect(content, isA<List<dynamic>>());
    expect(model, AppSettings.defaultVisionModel);
    expect(find.byKey(const ValueKey('calc-error')), findsOneWidget);
    expect(find.text('Rohantwort anzeigen'), findsOneWidget);
  });

  testWidgets('ohne API-Key ist Berechnen aus und der Grund steht da', (tester) async {
    await pump(tester, const CalcScreen(moduleName: 'ET'), withKey: false);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('calc-run'))).onPressed, isNull);
    expect(find.textContaining('OpenRouter-Key'), findsOneWidget);
  });

  testWidgets('Plan überarbeiten schickt den bisherigen Plan und den Wunsch', (tester) async {
    final prompts = <String>[];
    CalcScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            prompts.add(((jsonDecode(r.body)['messages'] as List).last['content']) as String);
            return _chat(_ohm);
          }),
        );
    await pump(tester, const CalcScreen(moduleName: 'ET', initialTask: 'Rechne'));
    await tester.tap(find.byKey(const ValueKey('calc-run')));
    await settle(tester);

    await tester.enterText(find.byKey(const ValueKey('calc-instruction')), 'Rechne auch die Energie');
    await tester.tap(find.byKey(const ValueKey('calc-refine')));
    await settle(tester);
    expect(prompts, hasLength(2));
    expect(prompts.last, contains('Bisheriger Plan (JSON):'));
    expect(prompts.last, contains('Rechne auch die Energie'));
  });

  testWidgets('Rechenweg kopieren legt den Text in die Zwischenablage', (tester) async {
    CalcScreen.aiFactory = (key, model) => AiService(apiKey: key, model: model, client: MockClient((r) async => _chat(_ohm)));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pump(tester, const CalcScreen(moduleName: 'ET', initialTask: 'Rechne'));
    await tester.tap(find.byKey(const ValueKey('calc-run')));
    await settle(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('calc-copy')));
    await tester.tap(find.byKey(const ValueKey('calc-copy')));
    await tester.pump();
    expect(copied, contains('1) Widerstand: R = U / I = 12,3 V / 0,45 A = 27,33 Ω'));
    expect(find.text('Rechenweg kopiert.'), findsOneWidget);
  });

  testWidgets('aus dem Versuch: Messwerte stehen schon im Werte-Feld, der Rechenweg landet in den Notizen des Teils',
      (tester) async {
    CalcScreen.aiFactory = (key, model) => AiService(apiKey: key, model: model, client: MockClient((r) async => _chat(_ohm)));
    final db = await tester.runAsync(() => databaseFactoryMemory.openDatabase('calc_ui_${DateTime.now().microsecondsSinceEpoch}'));
    final labs = LabExperimentRepository(openDatabase: () async => db!);
    final e = _experiment();
    await tester.runAsync(() => labs.save(e));
    await pump(tester, const LabExperimentScreen(experimentId: 'lab1', moduleName: 'ET'), labs: labs);

    await tester.tap(find.text('Durchführung'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(ValueKey('calc-${e.parts.first.id}')));
    await tester.tap(find.byKey(ValueKey('calc-${e.parts.first.id}')));
    await tester.pumpAndSettle();

    final values = tester.widget<TextField>(find.byKey(const ValueKey('calc-values'))).controller!.text;
    expect(values, contains('2 V | 0,1 A'));

    await tester.tap(find.byKey(const ValueKey('calc-run')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('calc-save-note')));
    await tester.tap(find.byKey(const ValueKey('calc-save-note')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(labs.byId('lab1')!.parts.first.notes, contains('R = U / I = 12,3 V / 0,45 A = 27,33 Ω'));

    // Zurück im Versuch steht der Rechenweg in den Notizen.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('27,33 Ω', findRichText: true), findsWidgets);
  });

  testWidgets('bei einer Auswertungsaufgabe gibt es "Rechnen" und die Aufgabe steht als Aufgabe drin', (tester) async {
    final db = await tester.runAsync(() => databaseFactoryMemory.openDatabase('calc_ui_${DateTime.now().microsecondsSinceEpoch}'));
    final labs = LabExperimentRepository(openDatabase: () async => db!);
    final e = _experiment();
    await tester.runAsync(() => labs.save(e));
    await pump(tester, const LabExperimentScreen(experimentId: 'lab1', moduleName: 'ET'), labs: labs);
    await tester.tap(find.text('Durchführung'));
    await tester.pumpAndSettle();

    final q = e.parts.first.questions.first;
    await tester.ensureVisible(find.byKey(ValueKey('calc-question-${q.id}')));
    await tester.tap(find.byKey(ValueKey('calc-question-${q.id}')));
    await tester.pumpAndSettle();
    final task = tester.widget<TextField>(find.byKey(const ValueKey('calc-task'))).controller!.text;
    expect(task, '2.1 Wie groß ist der Widerstand?');
  });
}
