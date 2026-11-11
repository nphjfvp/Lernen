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

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

/// Lektion, wie Stufe 1 sie liefert: Texte fertig, Szenen nur als Bauplan.
Map<String, dynamic> stagedLessonJson() => {
  'title': 'Diffusion im Kupfer-Nickel-Paar',
  'intro': 'Ein Block aus Kupfer und Nickel wird geglüht.',
  'look': 'Links Kupfer (orange), rechts Nickel (grau), Grenze bei x = 50.',
  'functions': [],
  'steps': [
    {
      'title': 'Ausgangslage',
      'text': 'Zwei Blöcke liegen aneinander.',
      'show': {'idea': 'Zwei Blöcke nebeneinander', 'kind': 'scene'},
    },
    {
      'title': 'Atome wandern',
      'text': 'Mit der Zeit wandern Atome über die Grenze.',
      'show': {'idea': 'Atome wandern über die Grenze'},
    },
    {
      'title': 'Eindringtiefe',
      'text': 'Die Näherung liefert die Strecke.',
      'formula': r'x = 2\sqrt{D t}',
      'show': {
        'transform': [
          {'latex': r'x = 2\sqrt{D t}', 'note': 'Näherung'},
        ],
      },
    },
    {
      'title': 'Im Raum',
      'text': 'Der Block von außen.',
      'show': {'idea': 'Block räumlich', 'kind': 'scene3d'},
    },
  ],
  'result': {
    'title': 'Ergebnis',
    'text': 'Nickel dringt weiter ein.',
    'show': {'idea': 'Profil am Ende'},
  },
  'short': {
    'title': 'Kurzfassung',
    'text': '• Diffusion braucht Zeit',
    'show': {'idea': 'Alles auf einen Blick'},
  },
};

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

void main() {
  late List<({String system, String user})> requests;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_visual_staged_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  setUp(() => requests = []);
  tearDown(() => VisualLessonScreen.aiFactory = null);

  /// Stufe 1 liefert [stagedLessonJson]; Stufe 2 je Bauplan eine Szene, deren
  /// Text der Bauplan ist. [failing]: Baupläne, zu denen keine Szene kommt.
  AiService ai({Set<String> failing = const {}}) => AiService(
    apiKey: 'sk-test',
    model: 'm',
    client: MockClient((r) async {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final system = (body['messages'] as List)[0]['content'] as String;
      final user = (body['messages'] as List)[1]['content'] as String;
      requests.add((system: system, user: user));
      if (!system.trimLeft().startsWith('Du zeichnest')) {
        return _chat({
          'lessons': [stagedLessonJson()],
        });
      }
      final idea = RegExp(r'Bauplan: (.*)').firstMatch(user)!.group(1)!.trim();
      if (failing.contains(idea)) return _chat({'show': <String, dynamic>{}});
      return _chat({
        'show': user.contains('Art: räumlich')
            ? {
                'scene3d': {
                  'box': [2, 1, 1],
                  'objects': [
                    {
                      'type': 'box',
                      'at': [0, 0, 0],
                      'dims': [1, 1, 1],
                      'fill': 'orange',
                      'text': idea,
                    },
                  ],
                },
              }
            : {
                'scene': {
                  'width': 100,
                  'height': 60,
                  'elements': [
                    {'type': 'rect', 'x': 5, 'y': 20, 'w': 45, 'h': 20, 'fill': 'orange', 'text': idea},
                  ],
                },
              },
      });
    }),
  );

  test('Bauplan statt Szene: lesen, speichern, offene Szenen finden, Szene übernehmen', () {
    final lesson = VisualLesson.fromMap(stagedLessonJson(), id: 'l', moduleId: 'm', createdAt: DateTime(2026, 11, 11))!;
    expect(lesson.pendingScenes, [0, 1, 3, -1, -2]);
    expect(lesson.look, startsWith('Links Kupfer'));
    expect(lesson.steps[3].show.ideaKind, 'scene3d');
    expect(lesson.steps[2].show.isPending, isFalse);
    // Der Bauplan übersteht Speichern und Lesen.
    final again = VisualLesson.fromMap(lesson.toMap())!;
    expect(again.pendingScenes, [0, 1, 3, -1, -2]);
    expect(again.steps[1].show.idea, 'Atome wandern über die Grenze');
    expect(again.look, lesson.look);

    final drawn = lesson.withScene(0, {
      'show': {
        'scene': {
          'elements': [
            {'type': 'circle', 'x': 10, 'y': 10, 'r': 3},
          ],
        },
      },
    })!;
    expect(drawn.steps[0].show.scene, isNotNull);
    expect(drawn.steps[0].show.isPending, isFalse);
    expect(drawn.steps[0].title, 'Ausgangslage');
    expect(drawn.pendingScenes, [1, 3, -1, -2]);
    expect(VisualLesson.fromMap(drawn.toMap())!.steps[0].show.idea, isEmpty, reason: 'Bauplan ist erledigt');
    // Kurzfassung und Ergebnis.
    expect(drawn.withScene(-2, {'scene': drawn.steps[0].show.scene!.toMap()})!.pendingScenes, [1, 3, -1]);
    // Keine lesbare Szene: nichts übernehmen.
    expect(lesson.withScene(1, {'show': <String, dynamic>{}}), isNull);
    expect(lesson.withScene(9, {'show': <String, dynamic>{}}), isNull);
  });

  test('zwei Stufen: erst Texte und Baupläne, dann jede Szene einzeln – die erste als Vorlage', () async {
    final progress = <(int, int)>[];
    final raws = await ai().generateVisualLessons(topic: 'Diffusion', onSceneProgress: (d, t) => progress.add((d, t)));
    final lesson = VisualLesson.fromMap(raws.single)!;
    expect(lesson.pendingScenes, isEmpty);
    expect(lesson.steps[0].show.scene, isNotNull);
    expect(lesson.steps[1].show.scene, isNotNull);
    expect(lesson.steps[2].show.transform, hasLength(1), reason: 'kleine Darstellungen bleiben, wie sie sind');
    expect(lesson.steps[3].show.scene3d, isNotNull);
    expect(lesson.result!.show.scene, isNotNull);
    expect(lesson.shortVersion!.show.scene, isNotNull);
    expect(lesson.look, startsWith('Links Kupfer'));
    expect(progress, [(1, 5), (2, 5), (3, 5), (4, 5), (5, 5)]);

    expect(requests, hasLength(6));
    expect(requests.first.system, contains('ZWEI STUFEN'));
    expect(requests.first.system, contains('FREIE SZENE'), reason: 'Stufe 1 weiß, was die App zeichnen kann');
    // Die erste Szene allein und ohne Vorlage …
    expect(requests[1].user, contains('Zu zeichnen: Schritt 1 von 4'));
    expect(requests[1].user, contains('Bauplan: Zwei Blöcke nebeneinander'));
    expect(requests[1].user, contains('Links Kupfer (orange)'), reason: 'gemeinsamer Aufbau geht mit');
    expect(requests[1].user, isNot(contains('Vorlage')));
    // … die übrigen 2D-Szenen bekommen sie mit.
    final second = requests.firstWhere((r) => r.user.contains('Bauplan: Atome wandern'));
    expect(second.user, contains('Vorlage – die fertige Szene von „Ausgangslage“'));
    expect(second.user, contains('"fill":"orange"'));
    final overview = second.user.split('Vorlage').first;
    expect(overview, contains('(schon gezeichnet)'));
    expect(
      overview,
      isNot(contains('"elements"')),
      reason: 'fertige Szenen stehen nur in der Vorlage, nicht im Überblick',
    );
  });

  test('eine Szene scheitert: die Lektion kommt trotzdem, der Bauplan bleibt zum Nachholen', () async {
    final raws = await ai(failing: {'Atome wandern über die Grenze'}).generateVisualLessons(topic: 'Diffusion');
    final lesson = VisualLesson.fromMap(raws.single)!;
    expect(lesson.pendingScenes, [1]);
    expect(lesson.steps[1].show.idea, 'Atome wandern über die Grenze');
    expect(lesson.steps[0].show.scene, isNotNull);
  });

  test('abschaltbar: in einem Stück wie früher – und Baupläne offen lassen', () async {
    await ai().generateVisualLessons(topic: 'Diffusion', staged: false);
    expect(requests, hasLength(1));
    expect(requests.single.system, isNot(contains('ZWEI STUFEN')));

    requests.clear();
    final raws = await ai().generateVisualLessons(topic: 'Diffusion', drawScenes: false);
    expect(requests, hasLength(1));
    expect(VisualLesson.fromMap(raws.single)!.pendingScenes, hasLength(5));
  });

  testWidgets(
    'Lektion öffnet sofort; offene Szenen werden nachgezeichnet und gespeichert, Fehler lassen sich nachholen',
    (tester) async {
      tester.view.physicalSize = const Size(412, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var failing = {'Atome wandern über die Grenze'};
      VisualLessonScreen.aiFactory = (_, _) => ai(failing: failing);
      final lesson = VisualLesson.fromMap(
        stagedLessonJson(),
        id: 'l-staged',
        moduleId: 'm-staged',
        createdAt: DateTime(2026, 11, 11),
      )!;
      await tester.runAsync(() => VisualLessonRepository().save(lesson));

      Future<void> real([int ms = 600]) async {
        await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
              ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
            ],
            child: MaterialApp(
              theme: ThemeData(extensions: const [AppColors.light]),
              home: VisualLessonScreen(lesson: lesson),
            ),
          ),
        );
        // Erster Aufbau: Text ist da, die Szene noch nicht.
        expect(find.text('Ausgangslage'), findsOneWidget);
        expect(find.byKey(const ValueKey('visual-scene-pending')), findsOneWidget);
        expect(find.textContaining('Geplant: Zwei Blöcke nebeneinander'), findsOneWidget);
        await tester.pump();
      });
      await real();
      await real();

      // Schritt 1 ist gezeichnet – ohne dass man etwas tun musste.
      expect(find.byKey(const ValueKey('visual-scene-pending')), findsNothing);
      expect(find.byKey(const ValueKey('visual-diagram-0')), findsOneWidget);
      expect(requests.first.user, contains('Zu zeichnen: Schritt 1 von 4'), reason: 'der sichtbare Schritt zuerst');
      expect(tester.takeException(), isNull, reason: 'kein Überlauf in Handybreite');

      // Schritt 2 ist gescheitert: Meldung und „Jetzt zeichnen“.
      await tester.tap(find.byKey(const ValueKey('visual-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('visual-scene-pending')), findsOneWidget);
      expect(find.textContaining('keine Szene geliefert'), findsOneWidget);
      var saved = await tester.runAsync(() => VisualLessonRepository().byId('l-staged'));
      expect(saved!.pendingScenes, [1], reason: 'alles andere ist gezeichnet und gespeichert');

      failing = {};
      final before = requests.length;
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('visual-scene-draw')));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('visual-scene-pending')), findsNothing);
      expect(find.byKey(const ValueKey('visual-diagram-1')), findsOneWidget);
      expect(requests.length, before + 1, reason: 'nur die fehlende Szene');
      saved = await tester.runAsync(() => VisualLessonRepository().byId('l-staged'));
      expect(saved!.pendingScenes, isEmpty);

      // Mit einem veralteten Stand geöffnet: nichts wird doppelt gezeichnet.
      requests.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
              ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
            ],
            child: MaterialApp(
              theme: ThemeData(extensions: const [AppColors.light]),
              home: VisualLessonScreen(lesson: lesson),
            ),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(requests, isEmpty);
      expect(find.byKey(const ValueKey('visual-diagram-0')), findsOneWidget);
    },
  );

  testWidgets('dieselbe Lektion zweimal offen: Die Szenen werden nur einmal angefragt, beide Bildschirme zeigen sie', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    VisualLessonScreen.aiFactory = (_, _) => ai();
    final lesson = VisualLesson.fromMap(
      stagedLessonJson(),
      id: 'l-twice',
      moduleId: 'm-staged',
      createdAt: DateTime(2026, 11, 11),
    )!;
    await tester.runAsync(() => VisualLessonRepository().save(lesson));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
            // Wie in der App: EIN Repository für alle Bildschirme.
            ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [AppColors.light]),
            home: Column(
              children: [
                Expanded(child: VisualLessonScreen(lesson: lesson)),
                Expanded(child: VisualLessonScreen(lesson: lesson)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('visual-scene-pending')), findsNWidgets(2));
      await Future<void>.delayed(const Duration(milliseconds: 900));
    });
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(requests, hasLength(5), reason: 'fünf Szenen, jede einmal');
    expect(find.byKey(const ValueKey('visual-scene-pending')), findsNothing);
    expect(find.byKey(const ValueKey('visual-diagram-0')), findsNWidgets(2));
  });
}
