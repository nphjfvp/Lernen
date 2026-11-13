import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/visual_lesson_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/visual_lesson_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Settings extends SettingsRepository {
  _Settings(this._current);
  final AppSettings _current;

  @override
  AppSettings get settings => _current;
}

http.Response _chat(Object json) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': jsonEncode(json)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> lessonJson() => {
  'title': 'Kräfte am Auto',
  'intro': 'Ein Auto steht auf der Straße.',
  'functions': <Object>[],
  'steps': [
    {
      'title': 'Das Auto steht',
      'text': 'Welche Kräfte wirken im Stillstand?',
      'show': {
        'scene': {
          'width': 100,
          'height': 60,
          'elements': [
            {'type': 'rect', 'x': 20, 'y': 30, 'w': 60, 'h': 15, 'fill': 'accent', 'text': 'Auto'},
          ],
        },
      },
    },
  ],
};

/// Auto aus Quader und Rad; [gap] rückt das Rad vom Wagen weg (Auffälligkeit).
Map<String, dynamic> carScene({double gap = 0}) => {
  'box': [5, 2, 2],
  'objects': [
    {
      'type': 'box',
      'at': [0.5, 0.2, 0.4],
      'dims': [4, 1.6, 1],
      'text': 'Karosserie',
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

typedef _Request = ({String model, String system, String user});

void main() {
  late List<_Request> requests;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_scene3d_help_ui_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  setUp(() {
    requests = [];
    VisualAiBar.mode = VisualAiMode.change;
    VisualAiBar.collapsed = false;
  });

  tearDown(() {
    VisualLessonScreen.aiFactory = null;
    VisualAiBar.mode = VisualAiMode.ask;
  });

  bool isClarify(_Request r) => r.system.trimLeft().startsWith('Du bereitest in einer Lern-App');
  bool isRepair(_Request r) => r.system.trimLeft().startsWith('Du korrigierst in einer Lern-App eine räumliche Szene');

  /// [clarify]: Antwort der Vorab-Klärung; [drawn]: die erzeugte Szene;
  /// [repaired]: Antwort auf das Nachbessern.
  void answers({Map<String, dynamic>? clarify, Map<String, dynamic>? drawn, Map<String, dynamic>? repaired}) {
    VisualLessonScreen.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final request = (
          model: '${body['model']}',
          system: (body['messages'] as List)[0]['content'] as String,
          user: (body['messages'] as List)[1]['content'] as String,
        );
        requests.add(request);
        if (isClarify(request)) {
          return _chat(
            clarify ??
                {
                  'summary': 'Ein Auto im Stillstand, freigeschnitten.',
                  'points': ['Auto von der Seite auf ebener Fahrbahn', 'Gewichtskraft im Schwerpunkt nach unten'],
                  'plan': 'BAUPLAN-EINS: Auto mit Gewichtskraft und zwei Normalkräften.',
                  'question': 'Steht das Auto eben oder am Hang?',
                  'better2d': false,
                  'reason2d': '',
                },
          );
        }
        if (isRepair(request)) return _chat({'scene3d': repaired ?? carScene()});
        if (request.user.contains('flache 2D-Zeichnung')) {
          return _chat({
            'step': {
              'title': 'Flach',
              'text': 'Von der Seite.',
              'show': {
                'scene': {
                  'width': 100,
                  'height': 60,
                  'elements': [
                    {'type': 'rect', 'x': 10, 'y': 30, 'w': 80, 'h': 10, 'fill': 'gray', 'text': 'Seitenansicht'},
                  ],
                },
              },
            },
          });
        }
        return _chat({
          'step': {
            'title': 'Räumlich',
            'text': 'So sieht es aus.',
            'show': {'scene3d': drawn ?? carScene()},
          },
        });
      }),
    );
  }

  Future<void> open(WidgetTester tester, AppSettings settings) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lesson = VisualLesson.fromMap(lessonJson(), id: 'l-help', moduleId: 'm-help', createdAt: DateTime(2026))!;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: _Settings(settings)),
          ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: VisualLessonScreen(lesson: lesson),
        ),
      ),
    );
    await tester.pump();
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  /// Tippt in echter Zeit (KI-Anfrage und Speichern laufen in dieser Zone).
  Future<void> tapReal(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(key(name));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Hinweis-Leisten („Geändert.“ mit Rückgängig) auslaufen lassen, bevor der
  /// Test endet.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    // Was in echter Zeit angestoßen wurde, auch dort zu Ende laufen lassen.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  const withKey = AppSettings(openRouterApiKey: 'sk-test', helpModelId: 'hilfe/modell');

  testWidgets('Vorab-Klärung: Bauplan zeigen, Rückfrage beantworten, dann genau danach bauen', (tester) async {
    answers();
    await open(tester, withKey);
    await tester.enterText(key('visual-live-input'), 'auto freigeschnitten mit kraftpfeilen im stillstand');
    await tapReal(tester, 'visual-live-3d');

    // Erst die Klärung – mit dem Modell für „Erklärungen & Hilfe“, noch kein 3D.
    expect(key('scene-plan'), findsOneWidget);
    expect(requests, hasLength(1));
    expect(requests.single.model, 'hilfe/modell');
    expect(requests.single.user, contains('auto freigeschnitten mit kraftpfeilen im stillstand'));
    expect(requests.single.user, contains('Das Auto steht'), reason: 'der Schritt geht als Zusammenhang mit');
    expect(find.text('Ein Auto im Stillstand, freigeschnitten.'), findsOneWidget);
    expect(key('scene-plan-point-1'), findsOneWidget);
    expect(find.text('Steht das Auto eben oder am Hang?'), findsOneWidget);
    expect(key('scene-plan-2d-hint'), findsNothing);

    // Antwort auf die Rückfrage: Der Plan wird angepasst.
    await tester.enterText(key('scene-plan-answer'), 'am Hang, 10 Grad');
    await tapReal(tester, 'scene-plan-refine');
    expect(requests, hasLength(2));
    expect(requests.last.user, allOf(contains('BAUPLAN-EINS'), contains('am Hang, 10 Grad')));

    await tapReal(tester, 'scene-plan-ok');
    expect(key('scene-plan'), findsNothing);
    expect(requests, hasLength(3));
    expect(requests.last.model, AppSettings.defaultQuestionModel);
    expect(requests.last.user, contains('Bauplan – genau so umsetzen: BAUPLAN-EINS'));
    expect(requests.last.user, contains('scene3d'));
    expect(key('visual-scene3d-0'), findsOneWidget);
    // Sauberes Modell: kein Hinweis.
    expect(key('scene3d-notice'), findsNothing);
    await settle(tester);
  });

  testWidgets('2D ist nur ein Vorschlag: ohne Wahl bleibt es bei 3D, auf Wunsch flach', (tester) async {
    answers(
      clarify: {
        'summary': 'Freikörperbild eines Autos.',
        'points': ['Auto von der Seite'],
        'plan': 'BAUPLAN-FLACH',
        'question': '',
        'better2d': true,
        'reason2d': 'Alle Kräfte liegen in einer Ebene.',
      },
    );
    await open(tester, withKey);
    await tapReal(tester, 'visual-live-3d');
    expect(key('scene-plan-2d-hint'), findsOneWidget);
    expect(find.text('Alle Kräfte liegen in einer Ebene.'), findsOneWidget);
    expect(find.textContaining('ohne deine Wahl bleibt es bei 3D'), findsOneWidget);

    // Der Hauptknopf baut weiter 3D.
    await tapReal(tester, 'scene-plan-ok');
    expect(requests.last.user, contains('scene3d'));
    expect(requests.last.user, isNot(contains('flache 2D-Zeichnung')));
    expect(key('visual-scene3d-0'), findsOneWidget);

    // Noch einmal – diesmal dem Vorschlag folgen.
    requests.clear();
    await tapReal(tester, 'visual-live-3d');
    await tapReal(tester, 'scene-plan-2d');
    expect(requests.last.user, contains('flache 2D-Zeichnung'));
    expect(requests.last.user, contains('BAUPLAN-FLACH'));
    expect(find.text('Flach'), findsOneWidget);
    expect(key('visual-scene3d-0'), findsNothing);
    await settle(tester);
  });

  testWidgets('Klärung überspringen oder abschalten: gebaut wird wie bisher', (tester) async {
    answers();
    await open(tester, withKey);
    await tapReal(tester, 'visual-live-3d');
    await tapReal(tester, 'scene-plan-skip');
    expect(requests.last.user, contains(VisualLessonScreen.scene3dRequestForTest));
    expect(requests.last.user, isNot(contains('Bauplan – genau so umsetzen')));
    expect(key('visual-scene3d-0'), findsOneWidget);

    // Abgeschaltet: kein Fenster, keine Klärungs-Anfrage.
    requests.clear();
    await tester.pumpWidget(const SizedBox());
    await open(tester, withKey.copyWith(clarifyScene3d: false));
    await tapReal(tester, 'visual-live-3d');
    expect(key('scene-plan'), findsNothing);
    expect(requests.where(isClarify), isEmpty);
    expect(requests.single.user, contains('scene3d'));
    await settle(tester);
  });

  testWidgets('Prüfen und nachbessern: Auffälligkeit finden, korrigieren lassen, Original zurückholen', (tester) async {
    answers(drawn: carScene(gap: 0.7), repaired: carScene());
    await open(tester, withKey.copyWith(clarifyScene3d: false, scene3dRepair: 'on'));
    await tapReal(tester, 'visual-live-3d');

    // Erzeugen + eine Korrekturrunde beim selben Modell.
    expect(requests.map(isRepair).toList(), [false, true]);
    expect(requests.last.user, allOf(contains('Rad'), contains('berührt kein anderes Teil')));
    expect(requests.last.model, requests.first.model);
    expect(key('scene3d-notice'), findsOneWidget);
    expect(find.text('Geprüft und nachgebessert: 1 Auffälligkeit behoben.'), findsOneWidget);
    expect(key('scene3d-notice-repair'), findsNothing);

    Future<VisualLesson?> stored() => tester.runAsync<VisualLesson?>(() => VisualLessonRepository().byId('l-help'));
    double wheelY(VisualLesson l) => l.steps.first.show.scene3d!.objects.last.vectors['from']![1];
    expect(wheelY((await stored())!), closeTo(0, 1e-9), reason: 'die nachgebesserte Szene ist gespeichert');

    // Das Original lässt sich zurückholen.
    await tapReal(tester, 'scene3d-notice-original');
    expect(wheelY((await stored())!), closeTo(-0.7, 1e-9));
    expect(key('scene3d-notice'), findsNothing);
    await settle(tester);
  });

  testWidgets('Nachbessern aus oder Modell unbekannt: nur der Hinweis – nachbessern auf Knopfdruck', (tester) async {
    answers(drawn: carScene(gap: 0.7), repaired: carScene(gap: 0.7));
    // „Automatisch“ ohne Katalog: Das Modell gilt nicht als günstig – nichts läuft von allein.
    await open(tester, withKey.copyWith(clarifyScene3d: false));
    await tapReal(tester, 'visual-live-3d');
    expect(requests, hasLength(1));
    expect(find.text('Die App hat das 3D-Modell geprüft: 1 Auffälligkeit.'), findsOneWidget);
    expect(find.textContaining('berührt kein anderes Teil'), findsOneWidget);
    expect(key('scene3d-notice-original'), findsNothing);

    // Auf Knopfdruck – die Antwort ist nicht besser, also bleibt alles, wie es war.
    await tapReal(tester, 'scene3d-notice-repair');
    expect(requests.where(isRepair), hasLength(2), reason: 'zwei Runden, keine besser');
    expect(find.textContaining('Das Nachbessern hat nichts verbessert'), findsOneWidget);
    expect(key('scene3d-notice-original'), findsNothing);

    await tester.tap(key('scene3d-notice-close'));
    await tester.pump();
    expect(key('scene3d-notice'), findsNothing);
    await settle(tester);
  });
}
