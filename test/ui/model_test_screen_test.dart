import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/ai_model_info.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/model_test_result.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/model_catalog_repository.dart';
import 'package:lernen/repositories/model_test_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/settings/model_test_screen.dart';
import 'package:lernen/ui/visual/visual_scene3d_view.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// Einstellungen im Speicher (ohne Datenbank).
class _Settings extends SettingsRepository {
  AppSettings _current = const AppSettings(
    openRouterApiKey: 'sk-test',
    questionModelId: 'a/eins',
    visionModelId: 'a/eins',
    crosscheckModelId: 'b/zwei',
    // Die Vorab-Klärung hat ihren eigenen Test.
    clarifyScene3d: false,
  );

  @override
  AppSettings get settings => _current;

  @override
  Future<void> update(AppSettings settings) async {
    _current = settings;
    notifyListeners();
  }
}

AiModelInfo _model(String id, String name) => AiModelInfo(
  id: id,
  name: name,
  contextLength: 200000,
  promptPricePerMillion: 1,
  completionPricePerMillion: 5,
  supportsVision: true,
  isFree: false,
);

class _Catalog extends ModelCatalogRepository {
  final _all = [
    _model('a/eins', 'Modell Eins'),
    _model('b/zwei', 'Modell Zwei mit einem ziemlich langen Namen (Vorschau)'),
  ];

  @override
  List<AiModelInfo> get models => _all;

  @override
  List<AiModelInfo> get visionModels => _all;

  @override
  AiModelInfo? byId(String id) {
    for (final m in _all) {
      if (m.id == id) return m;
    }
    return null;
  }
}

http.Response _chat(Object json, {Map<String, dynamic>? usage}) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': json is String ? json : jsonEncode(json)},
      },
    ],
    'usage': ?usage,
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Uint8List _pdf(List<String> pages) {
  final document = PdfDocument();
  for (final text in pages) {
    document.pages.add().graphics.drawString(
      text,
      PdfStandardFont(PdfFontFamily.helvetica, 11),
      bounds: const Rect.fromLTWH(0, 0, 500, 700),
    );
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

typedef _Request = ({String model, String system, String user});

void main() {
  late List<_Request> requests;
  late _Settings settings;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_model_test_screen_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  setUp(() {
    requests = [];
    settings = _Settings();
  });

  tearDown(() {
    ModelTestScreen.aiFactory = null;
    ModelTestScreen.pickFileHook = null;
  });

  void answerWith(http.Response Function(_Request request) answer) {
    ModelTestScreen.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final content = (body['messages'] as List)[1]['content'];
        final request = (
          model: '${body['model']}',
          system: (body['messages'] as List)[0]['content'] as String,
          user: content is String ? content : jsonEncode(content),
        );
        requests.add(request);
        return answer(request);
      }),
    );
  }

  /// Handy-Breite: ein Überlauf ließe den Test scheitern.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> open(
    WidgetTester tester,
    String role, {
    ModuleRepository? modules,
    MaterialRepository? materials,
  }) async {
    await tester.runAsync(() async {
      for (final kind in ModelTestKind.values) {
        await ModelTestRepository().clear(kind);
      }
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsRepository>.value(value: settings),
            ChangeNotifierProvider<ModelCatalogRepository>.value(value: _Catalog()),
            ChangeNotifierProvider<ModuleRepository>.value(value: modules ?? ModuleRepository()),
            ChangeNotifierProvider<MaterialRepository>.value(value: materials ?? MaterialRepository()),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [AppColors.light]),
            home: ModelTestScreen(role: role),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  String? textOf(WidgetTester tester, String name) => tester.widget<Text>(key(name)).data;

  /// Tippt in echter Zeit – alles, was die Datenbank oder die KI anfasst.
  Future<void> tapReal(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(key(name));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tap(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.pump();
    await tester.tap(key(name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<List<ModelTestResult>> stored(WidgetTester tester, ModelTestKind kind) async =>
      (await tester.runAsync(() => ModelTestRepository().all(kind: kind)))!;

  testWidgets('Erklärung: zwei Modelle vergleichen, behalten, löschen, Modell übernehmen', (tester) async {
    phone(tester);
    answerWith(
      (r) => _chat(
        r.model == 'a/eins' ? 'Antwort von Eins: Die Steigung ist 2x.' : 'Antwort von Zwei: Potenzregel.',
        usage: {'prompt_tokens': 400, 'completion_tokens': 120, 'cost': r.model == 'a/eins' ? 0.0004 : 0.002},
      ),
    );
    await open(tester, 'help');

    expect(find.text('Modell testen · Erklärungen & Hilfe'), findsOneWidget);
    expect(find.text('Noch keine Ergebnisse'), findsOneWidget);
    // Vorbelegt mit dem Modell, das gerade für die Rolle arbeitet.
    expect(find.descendant(of: key('model-test-model-0'), matching: find.text('Modell Eins')), findsOneWidget);

    // Ohne Frage: Hinweis statt Anfrage.
    await tapReal(tester, 'model-test-run');
    expect(find.textContaining('Gib eine Frage ein'), findsOneWidget);
    expect(requests, isEmpty);

    await tap(tester, 'model-test-example');
    expect(find.text('Warum ist die Ableitung von x² gleich 2x?'), findsOneWidget);

    // Zweites Modell dazu.
    await tap(tester, 'model-test-add-model');
    await tester.tap(find.textContaining('Modell Zwei').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(key('model-test-model-1'), findsOneWidget);
    expect(find.text('Test mit 2 Modellen starten'), findsOneWidget);

    await tapReal(tester, 'model-test-run');
    expect(requests.map((r) => r.model).toSet(), {'a/eins', 'b/zwei'});
    expect(requests.first.user, contains('Warum ist die Ableitung'));
    expect(find.text('Ergebnisse (2)'), findsOneWidget);
    expect(find.text('Antwort von Eins: Die Steigung ist 2x.'), findsOneWidget);
    expect(find.text('Antwort von Zwei: Potenzregel.'), findsOneWidget);

    final results = await stored(tester, ModelTestKind.explain);
    expect(results, hasLength(2));
    final one = results.firstWhere((r) => r.modelId == 'a/eins');
    final two = results.firstWhere((r) => r.modelId == 'b/zwei');
    expect(one.cost, closeTo(0.0004, 1e-9));
    // Messwerte: Kosten und Tokens stehen dabei.
    expect(find.descendant(of: key('model-test-stats-${one.id}'), matching: find.text('0,0004 \$')), findsOneWidget);
    expect(find.descendant(of: key('model-test-stats-${two.id}'), matching: find.text('0,0020 \$')), findsOneWidget);
    expect(find.text('400 → 120 Tokens'), findsNWidgets(2));
    expect(key('model-test-current-${one.id}'), findsOneWidget);
    expect(key('model-test-use-${one.id}'), findsNothing);

    // Behalten.
    expect(find.textContaining('sonst weg in'), findsNWidgets(2));
    await tapReal(tester, 'model-test-pin-${two.id}');
    expect(find.text('Wird behalten'), findsOneWidget);
    expect((await stored(tester, ModelTestKind.explain)).firstWhere((r) => r.id == two.id).pinned, isTrue);

    // Das andere Modell übernehmen.
    await tapReal(tester, 'model-test-use-${two.id}');
    expect(settings.settings.helpModelId, 'b/zwei');
    expect(key('model-test-current-${two.id}'), findsOneWidget);
    expect(key('model-test-use-${one.id}'), findsOneWidget);

    // Löschen.
    await tapReal(tester, 'model-test-delete-${one.id}');
    expect(find.text('Ergebnisse (1)'), findsOneWidget);
    expect(find.text('Antwort von Eins: Die Steigung ist 2x.'), findsNothing);
    expect((await stored(tester, ModelTestKind.explain)).single.id, two.id);
  });

  testWidgets('Fragen erstellen und Lektion: kleine PDF hochladen, Seite wählen, Ergebnis ansehen', (tester) async {
    phone(tester);
    ModelTestScreen.pickFileHook = () async =>
        (name: 'hebel.pdf', bytes: _pdf(['Seite eins: das Hebelgesetz', 'Seite zwei: das Drehmoment']));
    answerWith((r) {
      if (r.system.contains('"lessons"') || r.user.contains('Detailgrad')) {
        return _chat({
          'lessons': [
            {
              'title': 'Das Drehmoment',
              'intro': 'Kraft mal Hebelarm.',
              'functions': <Object>[],
              'steps': [
                {
                  'title': 'Kraft am Hebel',
                  'text': 'Eine Kraft greift am Hebel an.',
                  'show': {
                    'scene': {
                      'width': 100,
                      'height': 60,
                      'elements': [
                        {'type': 'rect', 'x': 5, 'y': 20, 'w': 45, 'h': 20, 'fill': 'orange', 'text': 'Hebel'},
                      ],
                    },
                  },
                },
                {'title': 'Formel', 'text': 'M = F mal a.', 'formula': 'M = F a'},
              ],
            },
          ],
        });
      }
      return _chat(
        {
          'concepts': [
            {'title': 'Drehmoment', 'explanation': 'Kraft mal Hebelarm.'},
          ],
          'flashcards': [
            for (var i = 1; i <= 5; i++) {'type': 'flashcard', 'front': 'Frage Nummer $i?', 'back': 'Antwort $i'},
          ],
        },
        usage: {'prompt_tokens': 800, 'completion_tokens': 300},
      );
    });
    await open(tester, 'question');

    // Ohne Eingabe: Hinweis.
    await tapReal(tester, 'model-test-run');
    expect(find.textContaining('Wähle zuerst, woraus getestet wird'), findsOneWidget);

    await tap(tester, 'model-test-upload');
    expect(textOf(tester, 'model-test-source'), 'hebel.pdf');
    expect(find.text('Seite 1 von 2'), findsOneWidget);
    expect(find.textContaining('Hebelgesetz'), findsOneWidget);
    await tap(tester, 'model-test-page-next');
    expect(find.text('Seite 2 von 2'), findsOneWidget);
    expect(find.textContaining('Drehmoment'), findsOneWidget);

    await tapReal(tester, 'model-test-run');
    expect(requests, hasLength(1));
    expect(requests.single.user, contains('Drehmoment'));
    expect(requests.single.user, isNot(contains('Hebelgesetz')), reason: 'nur die gewählte Seite');

    final made = (await stored(tester, ModelTestKind.questions)).single;
    expect(made.inputLabel, 'Seite 2 von hebel.pdf');
    expect(made.costEstimated, isTrue, reason: 'keine Kosten gemeldet: aus dem Listenpreis');
    expect(textOf(tester, 'model-test-count-${made.id}'), '1 Konzept · 5 Fragen');
    expect(find.text('Frage Nummer 4?'), findsOneWidget);
    expect(find.text('→ Antwort 4'), findsOneWidget);
    expect(find.text('Frage Nummer 5?'), findsNothing);
    await tap(tester, 'model-test-more-${made.id}');
    expect(find.text('Frage Nummer 5?'), findsOneWidget);

    // Zweiter Test derselben Rolle: die visuelle Lektion – mit eigener Ergebnisliste.
    requests.clear();
    await tapReal(tester, 'model-test-kind-lesson');
    expect(find.text('Noch keine Ergebnisse'), findsOneWidget);
    expect(find.text('Seite 2 von 2'), findsOneWidget, reason: 'die Eingabe bleibt');
    await tapReal(tester, 'model-test-run');
    final lesson = (await stored(tester, ModelTestKind.lesson)).single;
    expect(textOf(tester, 'model-test-lesson-title-${lesson.id}'), 'Das Drehmoment');
    expect(find.text('2 Schritte · 1 mit Darstellung'), findsOneWidget);
    expect(find.text('1. Kraft am Hebel'), findsOneWidget);

    await tap(tester, 'model-test-open-${lesson.id}');
    expect(key('model-test-lesson-preview'), findsOneWidget);
    expect(find.text('Eine Kraft greift am Hebel an.'), findsOneWidget);
    expect(find.textContaining('Test · Modell Eins'), findsOneWidget);

    // Nichts davon landet bei den Lektionen oder Karten: nur in der Test-Ablage.
    expect(await stored(tester, ModelTestKind.questions), hasLength(1));
  });

  testWidgets('Gegenprüfen: erstellt zuerst Fragen, nimmt sie beim nächsten Mal wieder', (tester) async {
    answerWith((r) {
      if (r.system.contains('fachlicher Prüfer')) {
        return _chat({
          'ok': false,
          'issues': [
            {
              'targetType': 'flashcard',
              'targetIndex': 0,
              'problem': 'Die Einheit der Kraft ist Newton, nicht Joule.',
              'fix': {'type': 'flashcard', 'front': 'Einheit der Kraft?', 'back': 'Newton'},
            },
          ],
        });
      }
      return _chat({
        'concepts': <Object>[],
        'flashcards': [
          {'type': 'flashcard', 'front': 'Einheit der Kraft?', 'back': 'Joule'},
        ],
      });
    });
    await open(tester, 'crosscheck');
    expect(
      find.descendant(of: key('model-test-model-0'), matching: find.textContaining('Modell Zwei')),
      findsOneWidget,
    );

    await tap(tester, 'model-test-own-text');
    await tester.enterText(key('model-test-text'), 'Kraft wird in Newton gemessen.');
    await tapReal(tester, 'model-test-run');

    // Erst das Fragen-Modell, dann der Prüfer.
    expect(requests.map((r) => r.model).toList(), ['a/eins', 'b/zwei']);
    expect(requests.last.user, contains('Joule'));
    expect(find.text('1 Beanstandung in 1 Frage'), findsOneWidget);
    expect(find.text('Die Einheit der Kraft ist Newton, nicht Joule.'), findsOneWidget);
    expect(find.text('Vorschlag: Einheit der Kraft? → Newton'), findsOneWidget);
    expect(await stored(tester, ModelTestKind.questions), hasLength(1));

    // Noch einmal: dieselben Fragen, keine neue Erstellung.
    requests.clear();
    await tapReal(tester, 'model-test-run');
    expect(requests.map((r) => r.model).toList(), ['b/zwei']);
    expect(find.text('Ergebnisse (2)'), findsOneWidget);

    await tapReal(tester, 'model-test-clear');
    expect(find.text('Noch keine Ergebnisse'), findsOneWidget);
    expect(await stored(tester, ModelTestKind.crosscheck), isEmpty);
  });

  testWidgets('3D-Modell aus einer Beschreibung; fehlgeschlagener Test bleibt sichtbar', (tester) async {
    phone(tester);
    var fail = false;
    answerWith(
      (r) => fail
          ? http.Response('{"error":{"message":"No auth","code":401}}', 401)
          : _chat({
              'show': {
                'scene3d': {
                  'box': [2, 1, 1],
                  'objects': [
                    {
                      'type': 'box',
                      'at': [0, 0, 0],
                      'dims': [1, 1, 1],
                      'fill': 'orange',
                    },
                  ],
                },
              },
            }),
    );
    await open(tester, 'scene3d');

    await tapReal(tester, 'model-test-run');
    expect(find.textContaining('Beschreibe, was das 3D-Modell zeigen soll'), findsOneWidget);

    await tap(tester, 'model-test-example-0');
    await tapReal(tester, 'model-test-run');
    expect(requests.single.user, contains('Bauplan: Welle mit zwei Lagern'));
    final result = (await stored(tester, ModelTestKind.scene3d)).single;
    expect(textOf(tester, 'model-test-scene-count-${result.id}'), '1 Bauteil');
    expect(find.byType(VisualScene3DView), findsOneWidget);

    fail = true;
    await tapReal(tester, 'model-test-run');
    final failed = (await stored(tester, ModelTestKind.scene3d)).firstWhere((r) => r.failed);
    expect(key('model-test-failed-${failed.id}'), findsOneWidget);
    expect(key('model-test-use-${failed.id}'), findsNothing);
    expect(find.text('Ergebnisse (2)'), findsOneWidget);
  });

  testWidgets('Seite aus Material: PDF mit Seitenwahl, Material ohne PDF mit seinem Text', (tester) async {
    final modules = ModuleRepository();
    final materials = MaterialRepository();
    await tester.runAsync(() async {
      await modules.save(
        Module(
          id: 'mod-test',
          name: 'Technische Mechanik',
          colorValue: 0xFF676FBC,
          icon: 'book',
          examDate: null,
          createdAt: DateTime(2026, 11, 1),
        ),
      );
      await materials.save(
        MaterialItem(
          id: 'mat-pdf',
          moduleId: 'mod-test',
          fileName: 'folien.pdf',
          kind: MaterialKind.slide,
          extractedText: 'Erste Folie Statik\n\nZweite Folie Dynamik',
          createdAt: DateTime(2026, 11, 2),
          fileBytesBase64: base64Encode(_pdf(['Erste Folie Statik', 'Zweite Folie Dynamik'])),
        ),
      );
      await materials.save(
        MaterialItem(
          id: 'mat-docx',
          moduleId: 'mod-test',
          fileName: 'skript.docx',
          kind: MaterialKind.slide,
          extractedText: 'Skripttext zur Kinematik',
          createdAt: DateTime(2026, 11, 3),
        ),
      );
    });
    answerWith(
      (r) => _chat({
        'concepts': <Object>[],
        'flashcards': [
          {'type': 'flashcard', 'front': 'Frage?', 'back': 'Antwort'},
        ],
      }),
    );
    await open(tester, 'question', modules: modules, materials: materials);

    await tapReal(tester, 'model-test-material');
    expect(key('model-test-material-sheet'), findsOneWidget);
    expect(find.text('Technische Mechanik'), findsNWidgets(2));
    await tapReal(tester, 'model-test-material-mat-pdf');
    expect(textOf(tester, 'model-test-source'), 'folien.pdf');
    expect(find.text('Seite 1 von 2'), findsOneWidget);
    // Wenige Seiten: auch alle auf einmal.
    await tap(tester, 'model-test-page-all');
    expect(find.text('Alle 2 Seiten'), findsOneWidget);
    await tapReal(tester, 'model-test-run');
    expect(requests.single.user, allOf(contains('Statik'), contains('Dynamik')));
    expect((await stored(tester, ModelTestKind.questions)).single.inputLabel, 'folien.pdf (2 Seiten)');

    // Material ohne PDF: sein gespeicherter Text.
    requests.clear();
    await tapReal(tester, 'model-test-material');
    await tapReal(tester, 'model-test-material-mat-docx');
    expect(textOf(tester, 'model-test-source'), startsWith('skript.docx'));
    expect(key('model-test-page'), findsNothing);
    await tapReal(tester, 'model-test-run');
    expect(requests.single.user, contains('Skripttext zur Kinematik'));
  });

  testWidgets('3D mit Hilfen: Bauplan für alle Modelle, Bausteine abschaltbar, nachgebessertes Modell mit Original', (
    tester,
  ) async {
    phone(tester);
    Map<String, dynamic> car({double gap = 0}) => {
      'box': [5, 2, 2],
      'objects': [
        {
          'type': 'box',
          'at': [0.5, 0.2, 0.4],
          'dims': [4, 1.6, 1],
        },
        {
          'type': 'cylinder',
          'from': [1.2, 0.0 - gap, 0.4],
          'to': [1.2, 0.2 - gap, 0.4],
          'r': 0.4,
          'text': 'Rad',
        },
      ],
    };
    answerWith((r) {
      if (r.system.trimLeft().startsWith('Du bereitest in einer Lern-App')) {
        return _chat({
          'summary': 'Ein Auto, freigeschnitten.',
          'points': ['Auto von der Seite'],
          'plan': 'BAUPLAN-AUTO',
          'question': '',
          'better2d': true,
          'reason2d': 'Liegt in einer Ebene.',
        });
      }
      if (r.system.trimLeft().startsWith('Du korrigierst in einer Lern-App eine räumliche Szene')) {
        return _chat({'scene3d': car()});
      }
      return _chat({
        'show': {'scene3d': car(gap: 0.7)},
      });
    });
    await open(tester, 'scene3d');

    // Vorgaben aus den Einstellungen: Klärung aus (siehe _Settings), Bausteine und Nachbessern an.
    expect(tester.widget<FilterChip>(key('model-test-opt-clarify')).selected, isFalse);
    expect(tester.widget<FilterChip>(key('model-test-opt-blocks')).selected, isTrue);
    expect(tester.widget<FilterChip>(key('model-test-opt-repair')).selected, isTrue);

    await tap(tester, 'model-test-example-0');
    await tap(tester, 'model-test-opt-clarify');
    await tapReal(tester, 'model-test-run');
    // Erst der Bauplan – im Test ohne 2D-Angebot (hier geht es um 3D).
    expect(key('scene-plan'), findsOneWidget);
    expect(key('scene-plan-2d'), findsNothing);
    expect(requests, hasLength(1));
    await tapReal(tester, 'scene-plan-ok');

    // Zeichnen (mit Bauplan und Bausteinen im Prompt) + eine Korrekturrunde.
    expect(requests, hasLength(3));
    expect(requests[1].user, contains('Bauplan: BAUPLAN-AUTO'));
    expect(requests[1].system, contains('"type": "body"'));
    expect(requests[2].user, contains('berührt kein anderes Teil'));
    final result = (await stored(tester, ModelTestKind.scene3d)).single;
    expect(result.inputLabel, endsWith('· mit Bauplan, Bausteine, nachgebessert'));
    expect(result.calls, 0, reason: 'die Probe-Antworten melden keinen Verbrauch');
    expect(
      textOf(tester, 'model-test-scene-check-${result.id}'),
      'Geprüft: 1 Auffälligkeit, nach 1 Korrekturrunde noch 0.',
    );
    // Das Modell vor dem Nachbessern bleibt zum Vergleich.
    expect(result.output['original'], isNotNull);
    await tap(tester, 'model-test-more-${result.id}');
    expect(find.text('Nachgebessertes zeigen'), findsOneWidget);

    // Ohne Hilfen: eine Anfrage, kein Baustein im Prompt, nur der Prüfhinweis.
    requests.clear();
    await tap(tester, 'model-test-opt-clarify');
    await tap(tester, 'model-test-opt-blocks');
    await tap(tester, 'model-test-opt-repair');
    await tapReal(tester, 'model-test-run');
    expect(requests, hasLength(1));
    expect(requests.single.system, isNot(contains('"type": "body"')));
    final plain = (await stored(tester, ModelTestKind.scene3d)).firstWhere((r) => r.id != result.id);
    expect(plain.inputLabel, endsWith('· ohne Hilfen'));
    expect(textOf(tester, 'model-test-scene-check-${plain.id}'), 'Geprüft: 1 Auffälligkeit.');
    expect(plain.output['original'], isNull);
  });

  testWidgets('Vision: braucht eine PDF-Seite, eigener Text wird nicht angeboten', (tester) async {
    ModelTestScreen.pickFileHook = () async => (name: 'scan.pdf', bytes: _pdf(['Abgeschriebener Inhalt']));
    answerWith((r) => _chat('<<<SEITE 1>>>\nErkannter Text der Seite'));
    await open(tester, 'vision');
    expect(key('model-test-own-text'), findsNothing);

    await tapReal(tester, 'model-test-run');
    expect(find.textContaining('braucht es eine PDF-Seite'), findsOneWidget);

    await tap(tester, 'model-test-upload');
    await tapReal(tester, 'model-test-run');
    expect(requests.single.user, contains('application/pdf'));
    expect(find.text('Erkannter Text der Seite'), findsOneWidget);
  });
}
