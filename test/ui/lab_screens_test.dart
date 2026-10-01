import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
import 'package:lernen/ui/lab/lab_create_screen.dart';
import 'package:lernen/ui/lab/lab_experiment_screen.dart';
import 'package:lernen/ui/lab/lab_experiments_section.dart';
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

/// Materialien im Speicher – die Bildschirme dürfen nicht an die echte
/// Datenbank kommen.
class _Materials extends MaterialRepository {
  _Materials(this.items);
  final List<MaterialItem> items;

  @override
  List<MaterialItem> forModule(String moduleId) => [for (final m in items) if (m.moduleId == moduleId) m];

  @override
  Future<void> loadForModule(String moduleId) async {}
}

MaterialItem _material(String id, String name, String text) => MaterialItem(
      id: id,
      moduleId: 'm1',
      fileName: name,
      kind: MaterialKind.slide,
      extractedText: text,
      createdAt: DateTime(2026, 9, 1),
    );

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

LabExperiment _experiment({DateTime? labDate}) => LabExperiment.fromStructure(
      {
        'title': 'Oszilloskop',
        'prepQuestions': [
          {'number': '1a', 'question': 'Wozu dient der Trigger?'},
          {'number': '1b', 'question': 'Was ist die Abtastrate?'},
        ],
        'parts': [
          {
            'title': 'Grundeinstellungen',
            'steps': ['Tastkopf anschließen', 'AUTOSET drücken'],
            'tables': [
              {
                'title': 'Messwerte',
                'columns': ['Frequenz', 'Amplitude'],
                'rows': [
                  ['1 kHz', ''],
                ],
              },
            ],
            'evaluationQuestions': ['Periodendauer?'],
          },
        ],
        'hints': ['USB-Stick mitbringen'],
      },
      moduleId: 'm1',
      now: DateTime(2026, 9, 1),
      id: 'lab1',
      labDate: labDate,
      reportDue: labDate?.add(const Duration(days: 7)),
    );

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_lab_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() {
    LabExperimentScreen.aiFactory = null;
    LabExperimentScreen.saveFileHook = null;
    LabCreateScreen.aiFactory = null;
  });

  late LabExperimentRepository labs;

  Future<void> pumpApp(
    WidgetTester tester,
    Widget home, {
    List<MaterialItem> materials = const [],
    bool withKey = true,
    LabExperiment? experiment,
  }) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = await tester.runAsync(() => databaseFactoryMemory.openDatabase('lab_ui_${DateTime.now().microsecondsSinceEpoch}'));
    labs = LabExperimentRepository(openDatabase: () async => db!);
    if (experiment != null) await tester.runAsync(() => labs.save(experiment));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LabExperimentRepository>.value(value: labs),
        ChangeNotifierProvider<MaterialRepository>.value(value: _Materials(materials)),
        ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey(withKey: withKey)),
      ],
      child: MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: home),
    ));
    await tester.pump();
  }

  Finder fieldIn(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

  testWidgets('Vorbereitung: Antworten zählen mit und bleiben gespeichert; KI liest gegen', (tester) async {
    late String userPrompt;
    LabExperimentScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((request) async {
            userPrompt = ((jsonDecode(request.body)['messages'] as List).last['content']) as String;
            return _chat('{"verdict": "teilweise", "summary": "Guter Ansatz.", "missing": ["Der Pegel fehlt"], "hints": ["Kapitel 3"]}');
          }),
        );
    final e = _experiment();
    await pumpApp(tester, const LabExperimentScreen(experimentId: 'lab1', moduleName: 'Elektrotechnik'), experiment: e);

    expect(find.text('0 von 2 Aufgaben beantwortet'), findsOneWidget);
    expect(find.text('Wozu dient der Trigger?'), findsOneWidget);
    // Ohne Antwort kein Gegenlesen.
    final review = find.widgetWithText(FilledButton, 'Gegenlesen lassen').first;
    expect(tester.widget<FilledButton>(review).onPressed, isNull);

    await tester.enterText(fieldIn('lab-question-${e.prep.first.id}'), 'Er stabilisiert das Bild.');
    await tester.pump(const Duration(seconds: 1));
    expect(labs.byId('lab1')!.prep.first.answer, 'Er stabilisiert das Bild.');
    expect(find.text('1 von 2 Aufgaben beantwortet'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Gegenlesen lassen').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(userPrompt, contains('Er stabilisiert das Bild.'));
    expect(find.byKey(const ValueKey('lab-feedback')), findsOneWidget);
    expect(find.text('Teilweise'), findsOneWidget);
    expect(find.text('Guter Ansatz.'), findsOneWidget);
    expect(find.text('Der Pegel fehlt'), findsOneWidget);
    expect(find.text('Kapitel 3'), findsOneWidget);
    expect(labs.byId('lab1')!.prep.first.feedback!.verdict, 'teilweise');

    // Text ändern: die Einschätzung ist veraltet.
    await tester.enterText(fieldIn('lab-question-${e.prep.first.id}'), 'Er stabilisiert das Bild bei einem Pegel.');
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Text seither geändert'), findsOneWidget);
    expect(find.text('Erneut gegenlesen'), findsOneWidget);
  });

  testWidgets('ohne API-Key ist Gegenlesen aus, Nachschlagen meldet fehlende Unterlagen', (tester) async {
    final e = _experiment();
    await pumpApp(tester, const LabExperimentScreen(experimentId: 'lab1', moduleName: 'ET'), experiment: e, withKey: false);
    await tester.enterText(fieldIn('lab-question-${e.prep.first.id}'), 'Antwort');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Gegenlesen lassen').first).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('review-all'))).onPressed, isNull);

    await tester.tap(find.text('Im Skript nachschlagen').first);
    await tester.pump();
    expect(find.text('Für diesen Versuch sind keine Unterlagen hinterlegt.'), findsOneWidget);
  });

  testWidgets('Durchführung: Schritte abhaken, Messwerte eintragen, Notizen', (tester) async {
    final e = _experiment(labDate: DateTime.now());
    await pumpApp(tester, const LabExperimentScreen(experimentId: 'lab1', moduleName: 'ET'), experiment: e);

    // Am Labortag öffnet der Versuch direkt die Durchführung.
    expect(find.text('Schritte: 0 von 2 erledigt'), findsOneWidget);
    expect(find.text('Messwerte: 0 von 1 Feldern eingetragen'), findsOneWidget);
    expect(find.textContaining('USB-Stick mitbringen'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('step-${e.parts.first.id}-0')));
    await tester.pump();
    expect(labs.byId('lab1')!.parts.first.steps.first.done, isTrue);
    expect(find.text('Schritte: 1 von 2 erledigt'), findsOneWidget);

    await tester.enterText(find.byKey(ValueKey('cell-${e.parts.first.id}-0-0-0-1')).last, '2 V');
    await tester.pump(const Duration(seconds: 1));
    expect(labs.byId('lab1')!.parts.first.tables.single.rows[0], ['1 kHz', '2 V']);
    expect(find.text('Messwerte: 1 von 1 Feldern eingetragen'), findsOneWidget);

    await tester.enterText(find.byKey(ValueKey('notes-${e.parts.first.id}-0-0')).last, 'Tastkopf 10:1');
    await tester.pump(const Duration(seconds: 1));
    expect(labs.byId('lab1')!.parts.first.notes, 'Tastkopf 10:1');
  });

  testWidgets('Reiter wechseln direkt nach dem Tippen: nichts geht verloren, kein Fehler beim Aufräumen', (tester) async {
    final e = _experiment();
    await pumpApp(tester, const LabExperimentScreen(experimentId: 'lab1', moduleName: 'ET'), experiment: e);

    await tester.enterText(fieldIn('lab-question-${e.prep.first.id}'), 'Noch nicht entprellt gespeichert');
    // Sofort weg – die Pause von 700 ms ist noch nicht um.
    await tester.tap(find.text('Durchführung'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(labs.byId('lab1')!.prep.first.answer, 'Noch nicht entprellt gespeichert');

    await tester.tap(find.text('Vorbereitung'));
    await tester.pumpAndSettle();
    expect(find.text('1 von 2 Aufgaben beantwortet'), findsOneWidget);
    expect(find.text('Noch nicht entprellt gespeichert'), findsOneWidget);
  });

  testWidgets('Versuch schließen direkt nach dem Tippen: die Eingabe bleibt gespeichert', (tester) async {
    final e = _experiment();
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LabExperimentScreen(experimentId: 'lab1', moduleName: 'ET'),
              )),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
      experiment: e,
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldIn('lab-question-${e.prep.first.id}'), 'Schnell zurück');
    final NavigatorState navigator = tester.state(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(labs.byId('lab1')!.prep.first.answer, 'Schnell zurück');
  });

  testWidgets('Bericht: Abschnitt schreiben und als Text exportieren', (tester) async {
    Uint8List? exported;
    String? exportedName;
    LabExperimentScreen.saveFileHook = (name, bytes, mime) async {
      exportedName = name;
      exported = bytes;
    };
    final e = _experiment(labDate: DateTime.now().subtract(const Duration(days: 2)));
    await pumpApp(tester, const LabExperimentScreen(experimentId: 'lab1', moduleName: 'ET'), experiment: e);

    // Nach dem Versuch öffnet der Bericht.
    expect(find.textContaining('0 von 3 Abschnitten geschrieben'), findsWidgets);

    final section = e.report.first;
    final text = 'Der Versuch zeigt die Grundlagen der Messtechnik mit dem Oszilloskop.';
    await tester.enterText(fieldIn('lab-section-${section.id}'), text);
    await tester.pump(const Duration(seconds: 1));
    expect(labs.byId('lab1')!.report.first.text, text);
    expect(find.textContaining('1 von 3 Abschnitten geschrieben'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('export-report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-txt')));
    await tester.pumpAndSettle();
    expect(exportedName, 'Oszilloskop – Bericht.txt');
    final content = utf8.decode(exported!);
    expect(content, contains('# Bericht: Oszilloskop'));
    expect(content, contains(text));
  });

  testWidgets('Versuch anlegen: die KI liest die Unterlagen, der Versuch öffnet mit den Aufgaben', (tester) async {
    late String userPrompt;
    LabCreateScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((request) async {
            userPrompt = ((jsonDecode(request.body)['messages'] as List).last['content']) as String;
            return _chat(jsonEncode({
              'title': 'Digitalspeicheroszilloskop',
              'prepQuestions': [
                {'number': '1', 'question': 'Wozu dient der Trigger?'},
              ],
              'parts': [
                {
                  'title': 'Grundeinstellungen',
                  'steps': ['Tastkopf anschließen'],
                }
              ],
            }));
          }),
        );
    await pumpApp(
      tester,
      const LabCreateScreen(moduleId: 'm1', moduleName: 'Elektrotechnik'),
      materials: [
        _material('g1', 'Durchfuehrung.pdf', 'Schritt 1: Tastkopf anschließen'),
        _material('t1', 'Theorie.pdf', 'Vorbereitungsaufgabe 1: Wozu dient der Trigger?'),
      ],
    );

    // Ohne Unterlagen kann nicht eingelesen werden.
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('lab-read'))).onPressed, isNull);

    Future<void> pick(int pickerIndex, String fileName) async {
      await tester.tap(find.text('Aus dem Fach').at(pickerIndex));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, fileName));
      await tester.pump();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
    }

    await pick(0, 'Durchfuehrung.pdf');
    await pick(1, 'Theorie.pdf');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('lab-read'))).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('lab-read')));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(userPrompt, contains('Versuchsanleitung: Durchfuehrung.pdf'));
    expect(userPrompt, contains('Theorie-Skript: Theorie.pdf'));
    final stored = labs.all.single;
    expect(stored.title, 'Digitalspeicheroszilloskop');
    expect(stored.guideMaterialIds, ['g1']);
    expect(stored.theoryMaterialIds, ['t1']);
    expect(stored.prep.single.text, 'Wozu dient der Trigger?');
    // Der neue Versuch ist geöffnet.
    expect(find.byType(LabExperimentScreen), findsOneWidget);
    expect(find.text('Wozu dient der Trigger?'), findsOneWidget);
  });

  testWidgets('Versuch anlegen: leer ohne KI, Name ist Pflicht', (tester) async {
    await pumpApp(tester, const LabCreateScreen(moduleId: 'm1', moduleName: 'ET'), withKey: false);
    await tester.tap(find.byKey(const ValueKey('lab-empty')));
    await tester.pump();
    expect(find.text('Gib dem Versuch einen Namen.'), findsOneWidget);
    expect(labs.all, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('lab-title')), 'Diodenkennlinie');
    await tester.tap(find.byKey(const ValueKey('lab-empty')));
    await tester.pumpAndSettle();
    expect(labs.all.single.title, 'Diodenkennlinie');
    expect(labs.all.single.prep, isEmpty);
    expect(find.byType(LabExperimentScreen), findsOneWidget);
  });

  testWidgets('Fach-Abschnitt: Versuche mit Stand, Tippen öffnet, Anlegen-Knopf', (tester) async {
    final soon = _experiment(labDate: DateTime.now().add(const Duration(days: 3)));
    await pumpApp(
      tester,
      const Scaffold(body: SingleChildScrollView(child: LabExperimentsSection(moduleId: 'm1', moduleName: 'Elektrotechnik'))),
      experiment: soon,
    );
    expect(find.text('LABORVERSUCHE'), findsOneWidget);
    expect(find.text('Oszilloskop'), findsOneWidget);
    expect(find.text('Versuch in 3 Tagen · Vorbereitung 0/2'), findsOneWidget);
    expect(find.byKey(const ValueKey('lab-add')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lab-row-lab1')));
    await tester.pumpAndSettle();
    expect(find.byType(LabExperimentScreen), findsOneWidget);
  });
}
