import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/visual_lesson_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/visual_learn_screen.dart';
import 'package:lernen/ui/visual/visual_lesson_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../services/visual_math_test.dart' show carLessonJson;

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test', clarifyScene3d: false);
}

class _SettingsWith3d extends SettingsRepository {
  @override
  AppSettings get settings =>
      const AppSettings(openRouterApiKey: 'sk-test', scene3dModelId: 'stark/modell', clarifyScene3d: false);
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

void main() {
  late List<Map<String, dynamic>> requests;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_visual_learn_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  setUp(() {
    requests = [];
    // Die KI-Leiste merkt sich ihre Art – jeder Test beginnt bei „Fragen“.
    VisualAiBar.mode = VisualAiMode.ask;
    VisualAiBar.collapsed = false;
  });

  tearDown(() {
    VisualLessonScreen.aiFactory = null;
    VisualLearnScreen.aiFactory = null;
    VisualLearnScreen.pickPdfHook = null;
    VisualLearnScreen.renderPagesHook = null;
  });

  AiService Function(String, String) replying(Object Function(String userText) reply) =>
      (key, model) => AiService(
        apiKey: key,
        model: model,
        client: MockClient((r) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          requests.add(body);
          final content = (body['messages'] as List)[1]['content'];
          final text = content is String
              ? content
              : [
                  for (final part in content as List)
                    if (part['type'] == 'text') part['text'],
                ].join('\n');
          return _chat(reply(text));
        }),
      );

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
          ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  /// Animationen (6 s Simulation, Umformung) durchlaufen lassen.
  Future<void> run(WidgetTester tester, [int seconds = 8]) async {
    for (var i = 0; i < seconds * 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)).first);
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(key)).first);
    await tester.pump();
    await run(tester, 1);
  }

  String textOf(WidgetTester tester, String key) => tester
      .widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' ');

  final lesson = VisualLesson.fromMap(carLessonJson(), id: 'l1', moduleId: 'm1', createdAt: DateTime(2026, 10, 11))!;

  testWidgets('Lektion: Auto fährt, Graph mit Tangente, Umformung Schritt für Schritt, Navigation', (tester) async {
    await pumpApp(tester, VisualLessonScreen(lesson: lesson));
    expect(find.byKey(const ValueKey('visual-intro')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-car')), findsOneWidget);
    await run(tester);
    // Nach 6 s ist das Auto am Ende: s(10) = 70 m, v(10) = 12 m/s.
    expect(textOf(tester, 'visual-car'), contains('Weg 70 m · Geschwindigkeit 12 m/s'));
    expect(tester.widget<Text>(find.byKey(const ValueKey('visual-time-label'))).data, 't = 10');

    // Zeitregler: zurück an den Anfang.
    await tester.drag(find.byKey(const ValueKey('visual-time')), const Offset(-2000, 0));
    await tester.pump();
    expect(textOf(tester, 'visual-car'), contains('Weg 0 m'));

    await tap(tester, 'visual-next');
    expect(find.byKey(const ValueKey('visual-transform')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-slope')), findsOneWidget);
    expect(textOf(tester, 'visual-transform'), contains('Ausgangspunkt'));
    await tap(tester, 'visual-transform-next');
    expect(find.text('2 / 2'), findsOneWidget);

    // Dritter Schritt: Auto über die Geschwindigkeit, Fläche = Weg.
    await tap(tester, 'visual-next');
    await run(tester);
    expect(textOf(tester, 'visual-car'), contains('Weg 70 m'));
    expect(textOf(tester, 'visual-plot'), contains('Fläche bis hier: 70'));

    // Ergebnis, dann Übung.
    await tap(tester, 'visual-next');
    expect(find.text('Ergebnis'), findsWidgets);
    expect(find.text('Jetzt du'), findsOneWidget);
    await tap(tester, 'visual-page-4');
    expect(find.byKey(const ValueKey('visual-exercise')), findsOneWidget);
    await run(tester);
  });

  testWidgets('Rückfrage zu einem Schritt: visuell mit Umformung und Graph', (tester) async {
    VisualLessonScreen.aiFactory = replying(
      (_) => {
        'text': r'$y′$ heißt: Änderung von $y$ geteilt durch Änderung von $x$.',
        'transform': [
          {'latex': r"y' = \lim_{\Delta x \to 0} \frac{\Delta y}{\Delta x}", 'note': 'Differenzenquotient'},
          {'latex': r"y' = \frac{dy}{dx}", 'note': 'Grenzwert als Schreibweise'},
        ],
        'functions': [
          {'key': 'sek', 'label': 'Sekante', 'expr': '7*t - 10'},
        ],
        'show': {
          'plot': ['s', 'sek', 'gibtsnicht'],
        },
      },
    );
    await pumpApp(tester, VisualLessonScreen(lesson: lesson));
    await tap(tester, 'visual-next');
    await tap(tester, 'visual-ask');
    await tester.enterText(find.byKey(const ValueKey('visual-question')), 'Warum ist y′ = dy/dx?');
    await tap(tester, 'visual-mode');
    await tester.tap(find.text('Visuell'));
    await tester.pump();
    await tap(tester, 'visual-ask-send');
    await run(tester);
    final sent = jsonEncode(requests.single);
    expect(sent, contains('Warum ist y′ = dy/dx?'));
    expect(sent, contains('VISUELL'));
    expect(sent, contains('Gefragter Schritt: Ableiten'));
    expect(find.byKey(const ValueKey('visual-answer-text')), findsOneWidget);
    expect(find.text('Grenzwert als Schreibweise'), findsOneWidget, reason: 'Umformung läuft automatisch weiter');
    expect(find.byKey(const ValueKey('visual-answer-scene')), findsOneWidget);
    expect(textOf(tester, 'visual-answer-scene'), contains('Sekante'));
    await run(tester, 10);
  });

  testWidgets('Rückfrage behalten: Die Antwort samt 3D-Szene wird ein Schritt der Lektion – ohne neue Anfrage', (
    tester,
  ) async {
    VisualLessonScreen.aiFactory = replying(
      (_) => {
        'text': 'Im Raum sieht das so aus.',
        'functions': [
          {'key': 'sek', 'label': 'Sekante', 'expr': '7*t - 10'},
        ],
        'show': {
          'scene3d': {
            'objects': [
              {
                'type': 'sphere',
                'at': [0.5, 0.5, 0.5],
                'r': 0.2,
              },
            ],
          },
          'plot': ['sek'],
        },
      },
    );
    final own = VisualLesson.fromMap(carLessonJson(), id: 'l-keep', moduleId: 'm-keep', createdAt: DateTime(2026, 11, 12))!;
    await tester.runAsync(() => VisualLessonRepository().save(own));
    await pumpApp(tester, VisualLessonScreen(lesson: own));
    await tap(tester, 'visual-next');
    await tap(tester, 'visual-ask');
    expect(find.byKey(const ValueKey('visual-answer-keep')), findsNothing, reason: 'erst mit einer Antwort');
    await tester.enterText(find.byKey(const ValueKey('visual-question')), 'Wie sieht das räumlich aus?');
    await tap(tester, 'visual-ask-send');
    await run(tester, 2);
    expect(find.byKey(const ValueKey('visual-answer-scene3d')), findsOneWidget);

    // Behalten (in echter Zeit: es wird gespeichert).
    await tester.ensureVisible(find.byKey(const ValueKey('visual-answer-keep')));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('visual-answer-keep')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await run(tester, 2);
    expect(requests, hasLength(1), reason: 'Behalten kostet keine Anfrage');
    expect(find.byKey(const ValueKey('visual-answer-keep')), findsNothing, reason: 'Fenster ist zu');
    // Der neue Schritt steht hinter dem gefragten und ist aufgeschlagen.
    expect(tester.widget<Text>(find.byKey(const ValueKey('visual-step-title'))).data, 'Wie sieht das räumlich aus?');
    expect(find.byKey(const ValueKey('visual-scene3d-2')), findsOneWidget);
    expect(find.text('Antwort als Schritt 3 gespeichert.'), findsOneWidget);
    final saved = await tester.runAsync(() => VisualLessonRepository().forModule('m-keep'));
    final lessonNow = saved!.single;
    expect(lessonNow.steps.length, own.steps.length + 1);
    expect(lessonNow.steps[1].title, own.steps[1].title, reason: 'der gefragte Schritt bleibt');
    expect(lessonNow.steps[2].text, 'Im Raum sieht das so aus.');
    expect(lessonNow.steps[2].show.scene3d, isNotNull);
    expect(lessonNow.steps[2].show.plot, ['sek']);
    expect(lessonNow.functions.map((f) => f.key), contains('sek'));
    expect(lessonNow.steps[3].title, own.steps[2].title);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  });

  testWidgets('Übung: falsche Antwort simulieren (zweites Auto) und erklären lassen', (tester) async {
    VisualLessonScreen.aiFactory = replying(
      (_) => {'text': 'Du hast den Exponenten nicht als Faktor nach vorn gezogen – dein Auto wäre viel zu langsam.'},
    );
    await pumpApp(tester, VisualLessonScreen(lesson: lesson));
    await tap(tester, 'visual-page-4');
    final field = find.descendant(of: find.byKey(const ValueKey('visual-exercise')), matching: find.byType(TextField));
    await tester.enterText(field.first, 't');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await run(tester, 1);
    expect(find.byKey(const ValueKey('visual-wrong-bar')), findsOneWidget);
    expect(find.text('Deine Antwort: t'), findsOneWidget);

    await tap(tester, 'visual-simulate-wrong');
    await run(tester);
    // Geschwindigkeit 2t statt t: am Ende 20 statt 10, als Auto über die Geschwindigkeit.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('visual-simulate-text'))).data,
      contains('deine Antwort 10, richtig 20'),
    );
    expect(find.byKey(const ValueKey('visual-car-ghost-readout')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('visual-car-ghost-readout'))).data, contains('Weg 50'));
    await tester.tapAt(const Offset(10, 10));
    await run(tester, 2);

    await tap(tester, 'visual-why-wrong');
    await tap(tester, 'visual-ask-send');
    await run(tester, 2);
    final sent = jsonEncode(requests.single);
    expect(sent, contains('FALSCH geantwortet: t'));
    expect(sent, contains('Richtig wäre: 2*t'));
    expect(find.textContaining('viel zu langsam'), findsOneWidget);
  });

  testWidgets('Darstellung ändern: Rakete statt Auto für einen Schritt, gespeichert, Rückgängig', (tester) async {
    VisualLessonScreen.aiFactory = replying((text) {
      if (text.contains('die GANZE Lektion')) {
        return {
          'lesson': {
            'title': 'Raketenstart',
            'steps': [
              {'title': 'Zündung', 'text': 'Los geht es.'},
            ],
          },
        };
      }
      return {
        'step': {
          'title': 'Die Rakete fliegt',
          'text': 'Statt des Autos.',
          'show': {
            'car': 's',
            'vehicle': 'rocket',
            'plot': ['s'],
          },
        },
      };
    });
    final own = VisualLesson.fromMap(carLessonJson(), id: 'l-rev', moduleId: 'm-rev', createdAt: DateTime(2026))!;
    await pumpApp(tester, VisualLessonScreen(lesson: own));
    expect(textOf(tester, 'visual-car'), contains('Auto: Weg'));

    // „Ändern“ in der KI-Leiste → „Ausführlich …“ öffnet das Fenster.
    await tap(tester, 'visual-ai-mode-change');
    // In echter Zeit: das Speichern nach dem Ändern braucht sie.
    await tester.ensureVisible(find.byKey(const ValueKey('visual-revise')));
    await tester.pump();
    await tester.runAsync(() async => tester.tap(find.byKey(const ValueKey('visual-revise'))));
    await run(tester, 1);
    expect(find.text('Nur Schritt 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('visual-revise-quick-3')));
    await tester.pump();
    expect(find.text('Rakete statt Auto'), findsWidgets);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('visual-revise-send')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await run(tester, 1);
    final sent = jsonEncode(requests.single);
    expect(sent, contains('NUR Schritt 1'));
    expect(sent, contains('Wunsch des Nutzers: Rakete statt Auto'));
    expect(find.text('Die Rakete fliegt'), findsOneWidget);
    expect(textOf(tester, 'visual-car'), contains('Rakete: Weg'));
    expect(find.text('Darstellung geändert.'), findsOneWidget);
    final saved = await tester.runAsync(() => VisualLessonRepository().forModule('m-rev'));
    expect(saved!.single.steps.first.show.vehicle, 'rocket');

    // Rückgängig.
    await tester.runAsync(() async {
      await tester.tap(find.text('Rückgängig'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await run(tester, 1);
    expect(find.text('Die Rakete fliegt'), findsNothing);
    expect(textOf(tester, 'visual-car'), contains('Auto: Weg'));

    // Ganze Lektion.
    // In echter Zeit: das Speichern nach dem Ändern braucht sie.
    await tester.ensureVisible(find.byKey(const ValueKey('visual-revise')));
    await tester.pump();
    await tester.runAsync(() async => tester.tap(find.byKey(const ValueKey('visual-revise'))));
    await run(tester, 1);
    await tester.enterText(find.byKey(const ValueKey('visual-revise-request')), 'Mach eine Rakete draus');
    await tester.tap(find.text('Ganze Lektion'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('visual-revise-send')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await run(tester, 1);
    expect(jsonEncode(requests.last), contains('die GANZE Lektion'));
    expect(find.text('Raketenstart'), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-page-1')), findsOneWidget, reason: 'Zündung + Übung');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  });

  test('Aufteilen: mehrere Schritte ersetzen den einen, Rest bleibt', () {
    final base = VisualLesson.fromMap(carLessonJson(), id: 'l-split', moduleId: 'm', createdAt: DateTime(2026))!;
    final n = base.steps.length;
    final split = base.revisedWith({
      'steps': [
        {'title': 'Zwischenschritt', 'text': 'Erst das.'},
        {'title': 'Dann', 'text': 'Dann das.'},
        'kaputt',
      ],
    }, stepIndex: 0)!;
    expect(split.steps.map((s) => s.title).take(2), ['Zwischenschritt', 'Dann']);
    expect(split.steps, hasLength(n + 1));
    expect(split.steps.last.title, base.steps.last.title);
    final many = base.revisedWith({
      'steps': [
        for (var i = 0; i < 9; i++) {'title': 'S$i', 'text': 't'},
      ],
    }, stepIndex: 0)!;
    expect(many.steps, hasLength(n - 1 + VisualLesson.maxSplitSteps));
    expect(base.revisedWith({'steps': []}, stepIndex: 0), isNull);
    expect(
      base.revisedWith({
        'steps': [
          {'title': 'x', 'text': 'y'},
        ],
      }, stepIndex: -1),
      isNull,
      reason: 'Ergebnis lässt sich nicht aufteilen',
    );
  });

  testWidgets('Live ändern: Zwischenschritt einfügen, Rückgängig, eigener Wunsch', (tester) async {
    VisualLessonScreen.aiFactory = replying((text) {
      if (text.contains('Wunsch des Nutzers: Mach aus diesem Schritt zwei')) {
        return {
          'steps': [
            {'title': 'Erst die Strecke', 'text': r'Der Weg $\textcolor{green}{s}$ wächst.'},
            {'title': 'Dann das Tempo', 'text': 'Schneller wird es.'},
          ],
        };
      }
      return {
        'step': {'title': 'Als Graph', 'text': 'So sieht es aus.'},
      };
    });
    final own = VisualLesson.fromMap(carLessonJson(), id: 'l-live', moduleId: 'm-live', createdAt: DateTime(2026))!;
    final n = own.steps.length;
    await pumpApp(tester, VisualLessonScreen(lesson: own));
    // Eine Leiste für alles: „Fragen“ ist vorgewählt, die Vorschläge zum Umbauen stehen unter „Ändern“.
    expect(find.byKey(const ValueKey('visual-ai')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-live-chip-1')), findsNothing);
    expect(find.byKey(const ValueKey('visual-deepen')), findsOneWidget);
    await tap(tester, 'visual-ai-mode-change');
    expect(find.byKey(const ValueKey('visual-live-chip-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-deepen')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('visual-live-chip-1')));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('visual-live-chip-1')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await run(tester, 1);
    final sent = jsonEncode(requests.single);
    expect(sent, contains('NUR Schritt 1'));
    expect(sent, contains('Zwischenschritt'));
    expect(sent, contains('2 bis 5 Schritte'));
    expect(find.text('Erst die Strecke'), findsOneWidget);
    expect(find.text('Aus dem Schritt wurden 2 Schritte.'), findsOneWidget);
    final saved = await tester.runAsync(() => VisualLessonRepository().forModule('m-live'));
    expect(saved!.single.steps, hasLength(n + 1));

    await tester.runAsync(() async {
      await tester.tap(find.text('Rückgängig'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await run(tester, 1);
    expect(find.text('Erst die Strecke'), findsNothing);
    expect(find.text(own.steps.first.title), findsOneWidget);

    // Eigener Wunsch im Eingabefeld.
    await tester.enterText(find.byKey(const ValueKey('visual-live-input')), 'Zeig das als Graph');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('visual-live-send')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await run(tester, 1);
    expect(jsonEncode(requests.last), contains('Wunsch des Nutzers: Zeig das als Graph'));
    expect(find.text('Als Graph'), findsOneWidget);
    expect(find.text('Geändert.'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  });

  testWidgets('3D-Modell erzeugen: ohne eigenes Modell direkt, mit eigenem erst nach Rückfrage', (tester) async {
    Object reply(String text) => {
      'step': {
        'title': 'Räumlich',
        'text': 'So sieht es aus.',
        'show': {
          'scene3d': {
            'box': [100, 40, 40],
            'frame': false,
            'objects': [
              {'type': 'cylinder', 'from': [0, 20, 20], 'to': [100, 20, 20], 'r': 10},
            ],
          },
        },
      },
    };
    VisualLessonScreen.aiFactory = replying(reply);
    final own = VisualLesson.fromMap(carLessonJson(), id: 'l-3d', moduleId: 'm-3d', createdAt: DateTime(2026))!;

    // Alles in echter Zeit tippen: Die Anfrage und das Speichern laufen in
    // der Zone, in der der Knopf gedrückt wurde – sonst bleibt die Datenbank
    // für die folgenden Tests gesperrt.
    Future<void> tapReal(String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey(key)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await run(tester, 1);
    }

    // Kein eigenes 3D-Modell: sofort mit dem Fragen-Modell, ohne Rückfrage.
    VisualAiBar.mode = VisualAiMode.change;
    await pumpApp(tester, VisualLessonScreen(lesson: own));
    await tapReal('visual-live-3d');
    expect(find.byKey(const ValueKey('scene3d-confirm')), findsNothing);
    expect(requests.single['model'], AppSettings.defaultQuestionModel);
    expect(jsonEncode(requests.single), contains('scene3d'));
    expect(find.text('Räumlich'), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-scene3d-0')), findsOneWidget);

    // Eigenes (teures) Modell: erst fragen. Abbrechen = keine Anfrage.
    requests.clear();
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWith3d()),
          ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: VisualLessonScreen(lesson: own),
        ),
      ),
    );
    await tester.pump();
    await tapReal('visual-live-3d');
    expect(find.byKey(const ValueKey('scene3d-confirm')), findsOneWidget);
    expect(find.textContaining('stark/modell'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Abbrechen'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await run(tester, 1);
    expect(requests, isEmpty);

    // Bestätigen: genau dieses Modell wird benutzt.
    await tapReal('visual-live-3d');
    await tapReal('scene3d-confirm-ok');
    expect(requests.single['model'], 'stark/modell');

    // „Standard-Modell“ in der Rückfrage: das Fragen-Modell.
    requests.clear();
    await tapReal('visual-live-3d');
    await tapReal('scene3d-confirm-default');
    expect(requests.single['model'], AppSettings.defaultQuestionModel);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  });

  testWidgets('Sokratisch: Leitfrage, eigene Antwort, Tipp mit Simulation, selbst gefunden oder auflösen', (
    tester,
  ) async {
    final json = carLessonJson();
    (json['steps'] as List)[0]['guide'] = 'Was fällt dir am Auto auf, wenn du es fahren lässt?';
    final socratic = VisualLesson.fromMap(
      json,
      id: 'l-sok',
      moduleId: 'm-sokratisch',
      createdAt: DateTime(2026, 10, 11),
      style: VisualStyle.socratic,
    )!;
    expect(socratic.steps.first.guide, startsWith('Was fällt dir'));
    expect(VisualLesson.fromMap(socratic.toMap())!.style, VisualStyle.socratic);

    VisualLessonScreen.aiFactory = replying((text) {
      if (text.contains('TIPP')) {
        return {
          'reply': 'Achte darauf, wie weit das Auto in jeder Sekunde kommt. Was bedeutet das?',
          'show': {
            'plot': ['s'],
            'tangent': 's',
          },
        };
      }
      if (text.contains('Antwort des Lernenden: Es wird immer schneller')) {
        return {'reply': r'Genau – der Weg $s(t)$ wächst immer schneller.', 'reached': true};
      }
      if (text.contains('Antwort des Lernenden:')) {
        return {'reply': 'Fast – schau nochmal genau hin.', 'reached': false};
      }
      return {'reply': 'Wie könntest du aus dem Weg ablesen, wie schnell das Auto gerade ist?'};
    });
    await pumpApp(tester, VisualLessonScreen(lesson: socratic));
    await tester.pump();

    // Schritt 1: Leitfrage aus der Lektion (ohne KI-Aufruf), Erklärung verdeckt.
    expect(textOf(tester, 'socratic-turn-0'), contains('Was fällt dir am Auto auf'));
    expect(find.textContaining('Der Weg wächst immer schneller.'), findsNothing);
    expect(find.byKey(const ValueKey('visual-car')), findsOneWidget, reason: 'Auto zum Beobachten');
    expect(requests, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('socratic-answer')), 'Es steht still');
    await tap(tester, 'socratic-send');
    expect(textOf(tester, 'socratic-turn-1'), 'Es steht still');
    expect(textOf(tester, 'socratic-turn-2'), contains('Fast'));
    expect(find.byKey(const ValueKey('socratic-reached')), findsNothing);

    // Tipp: die KI zeigt die Tangente zum Beobachten.
    await tap(tester, 'socratic-hint');
    expect(textOf(tester, 'socratic-turn-4'), contains('in jeder Sekunde'));
    expect(find.byKey(const ValueKey('visual-slope')), findsOneWidget);
    var sent = jsonEncode(requests.last);
    expect(sent, contains('AKTUELLER SCHRITT'));
    expect(sent, contains('Lernender: Es steht still'));

    await tester.enterText(find.byKey(const ValueKey('socratic-answer')), 'Es wird immer schneller');
    await tap(tester, 'socratic-send');
    expect(find.byKey(const ValueKey('socratic-reached')), findsOneWidget);
    expect(find.text('Selbst herausgefunden!'), findsOneWidget);
    expect(find.textContaining('Der Weg wächst immer schneller.'), findsOneWidget, reason: 'Schritt aufgedeckt');

    // Schritt 2 ohne gespeicherte Leitfrage: die KI eröffnet; dann auflösen.
    await tap(tester, 'visual-next');
    await run(tester, 1);
    sent = jsonEncode(requests.last);
    expect(sent, contains('Eröffne den Schritt'));
    expect(textOf(tester, 'socratic-turn-0'), contains('aus dem Weg ablesen'));
    expect(find.byKey(const ValueKey('visual-formula')), findsNothing);
    expect(find.byKey(const ValueKey('visual-transform')), findsNothing);
    await tap(tester, 'socratic-reveal');
    expect(find.byKey(const ValueKey('socratic-revealed')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-formula')), findsOneWidget);

    // Umschalten auf „Erklären“: alles offen wie gewohnt.
    await tap(tester, 'visual-page-2');
    expect(find.byKey(const ValueKey('socratic-answer')), findsOneWidget);
    // (Speichern der Wahl braucht echte Zeit.)
    await tester.runAsync(() async {
      await tester.tap(find.text('Erklären'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await run(tester, 1);
    expect(find.byKey(const ValueKey('socratic-answer')), findsNothing);
    expect(find.byKey(const ValueKey('visual-ask')), findsOneWidget);
    final saved = await tester.runAsync(() => VisualLessonRepository().forModule('m-sokratisch'));
    expect(saved!.single.style, VisualStyle.explain, reason: 'Wahl wird gemerkt');
  });

  /// Fach-Bildschirm mit hochgeladener PDF (3 Seiten), Liste geladen.
  Future<void> openWithPdf(WidgetTester tester, String moduleId) async {
    final pdf = _pdf(['Seite eins: Grundlagen', 'Seite zwei: Ableitung von Weg-Zeit-Funktionen', 'Seite drei']);
    VisualLearnScreen.pickPdfHook = () async => (name: 'Kinematik.pdf', bytes: pdf);
    VisualLearnScreen.renderPagesHook = (_, pages) async => [
      for (final _ in pages) Uint8List.fromList([137, 80, 78, 71]),
    ];
    await pumpApp(tester, VisualLearnScreen(moduleId: moduleId, moduleName: 'Physik'));
    for (var i = 0; i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('visual-upload')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('Kinematik.pdf · 3 Seiten'), findsOneWidget);
  }

  /// Tippen und die KI (echte Zeit) arbeiten lassen.
  Future<void> tapAndWait(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey(key)));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await run(tester, 2);
  }

  testWidgets('Eine Seite: Lektion direkt erstellt, gespeichert und geöffnet', (tester) async {
    VisualLearnScreen.aiFactory = replying(
      (_) => {
        'lessons': [carLessonJson()],
      },
    );
    await openWithPdf(tester, 'm1');
    await tester.scrollUntilVisible(
      find.text('Noch keine – erstelle oben die erste.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('visual-topic')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const ValueKey('visual-page-from')), '2');
    await tester.pump();
    expect(find.text('Lektion erstellen'), findsOneWidget);
    await tapAndWait(tester, 'visual-create');
    final sent = jsonEncode(requests.single);
    expect(sent, contains('--- Seite 2 ---'));
    expect(sent, isNot(contains('--- Seite 3 ---')));
    expect(sent, contains('FREIE SZENE'), reason: 'Werkzeuge für jedes Fach');
    expect(sent, contains('Das Auto NUR, wenn es wirklich um Bewegung geht'));
    expect(find.byType(VisualLessonScreen), findsOneWidget);
    await run(tester);
    final saved = await tester.runAsync(() => VisualLessonRepository().forModule('m1'));
    expect(saved!.single.source, 'Kinematik.pdf, S. 2');
    expect(saved.single.functions.map((f) => f.key), ['s', 'v'], reason: 'unlesbare Funktion aussortiert');
  });

  testWidgets('PDF-Bereich: erst Themenliste (was lässt sich zeigen), dann Lektion je Thema mit seinen Seiten', (
    tester,
  ) async {
    VisualLearnScreen.aiFactory = replying(
      (text) => text.startsWith('Höchstens')
          ? {
              'topics': [
                {
                  'title': 'Ableitung von Weg-Zeit-Funktionen',
                  'summary': 'Vom Weg zur Geschwindigkeit.',
                  'pages': [2, 1],
                  'how': 'Auto fährt, Tangente am Weg zeigt das Tempo.',
                  'visual': true,
                },
                {
                  'title': 'Literatur',
                  'pages': [3],
                  'visual': false,
                  'reason': 'nur eine Liste von Büchern',
                },
              ],
            }
          : {
              'lessons': [carLessonJson()],
            },
    );
    await openWithPdf(tester, 'm2');
    await tester.enterText(find.byKey(const ValueKey('visual-topic')), 'Ableitung mit einem Auto erklären');
    await tester.tap(find.text('Bereich'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('visual-page-from')), '2');
    await tester.enterText(find.byKey(const ValueKey('visual-page-to')), '3');
    await tester.tap(find.text('Ausführlich'));
    await tester.pump();
    await tester.ensureVisible(find.text('Sokratisch'));
    await tester.tap(find.text('Sokratisch'));
    await tester.pump();
    expect(find.text('Themen finden'), findsOneWidget);

    await tapAndWait(tester, 'visual-create');
    var sent = jsonEncode(requests.single);
    expect(sent, contains('Wunsch des Nutzers (Schwerpunkt): Ableitung mit einem Auto erklären'));
    expect(sent, contains('--- Seite 2 ---'));
    expect(sent, isNot(contains('--- Seite 1 ---')));
    expect(sent, contains('Seite 2, 3'), reason: 'welches Bild welche Seite ist');
    expect(sent.split('"type":"image_url"').length - 1, 2, reason: 'zwei Seiten als Bild');
    expect(find.byKey(const ValueKey('visual-topic-0')), findsOneWidget);
    expect(find.textContaining('So: Auto fährt'), findsOneWidget);
    expect(find.textContaining('nur eine Liste von Büchern'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('visual-topic-0'))).value, isTrue);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('visual-topic-1'))).value, isFalse);
    expect(find.text('1 Lektion erstellen'), findsOneWidget);

    await tapAndWait(tester, 'visual-topics-create');
    expect(requests, hasLength(2));
    sent = jsonEncode(requests.last);
    expect(sent, contains('Thema: Ableitung von Weg-Zeit-Funktionen'));
    expect(sent, contains('Idee zur Darstellung: Auto fährt'));
    expect(sent, contains('Wunsch des Nutzers: Ableitung mit einem Auto erklären'));
    expect(sent, contains('--- Seite 2 ---'));
    expect(sent, isNot(contains('--- Seite 3 ---')), reason: 'nur die Seiten des Themas (in der Auswahl)');
    expect(sent, contains('Detailgrad: ausführlich'));
    expect(sent, contains('Lernweg: SOKRATISCH'));

    // Eine Lektion → gleich geöffnet und gespeichert.
    expect(find.byType(VisualLessonScreen), findsOneWidget);
    await run(tester);
    final saved = await tester.runAsync(() => VisualLessonRepository().forModule('m2'));
    expect(saved!.single.title, 'Vom Weg zur Geschwindigkeit');
    expect(saved.single.source, 'Kinematik.pdf, S. 2');
    expect(saved.single.detail, 'ausführlich');
    expect(saved.single.style, VisualStyle.socratic);
  });

  testWidgets('Ganze PDF: mehrere Themen gewählt, eins scheitert – die anderen werden gespeichert', (tester) async {
    VisualLearnScreen.aiFactory = replying((text) {
      if (text.startsWith('Höchstens')) {
        return {
          'topics': [
            {
              'title': 'Grundlagen',
              'pages': [1],
              'how': 'Szene',
              'visual': true,
            },
            {
              'title': 'Ableitung',
              'pages': [2],
              'how': 'Graph',
              'visual': true,
            },
            {
              'title': 'Schwieriges',
              'pages': [3],
              'how': 'Szene',
              'visual': true,
            },
          ],
        };
      }
      if (text.contains('Thema: Schwieriges')) return {'lessons': []};
      final json = carLessonJson();
      json['title'] = text.contains('Thema: Grundlagen') ? 'Grundlagen' : 'Ableitung';
      return {
        'lessons': [json],
      };
    });
    await openWithPdf(tester, 'm3');
    await tester.tap(find.text('Ganze PDF'));
    await tester.pump();
    await tapAndWait(tester, 'visual-create');
    expect(find.text('3 Lektionen erstellen'), findsOneWidget);
    await tapAndWait(tester, 'visual-topics-create');
    await run(tester, 1);
    expect(requests, hasLength(4));
    expect(find.byType(VisualLessonScreen), findsNothing, reason: 'mehrere → in der Liste statt öffnen');
    expect(find.text('2 Lektionen erstellt – unten in der Liste.'), findsOneWidget);
    expect(find.textContaining('Nicht geklappt: „Schwieriges“'), findsOneWidget);
    final saved = await tester.runAsync(() => VisualLessonRepository().forModule('m3'));
    expect(saved!.map((l) => l.title).toSet(), {'Grundlagen', 'Ableitung'});
    expect(saved.map((l) => l.source).toSet(), {'Kinematik.pdf, S. 1', 'Kinematik.pdf, S. 2'});
  });
}
