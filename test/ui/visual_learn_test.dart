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
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
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

  setUp(() => requests = []);

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

  testWidgets('Neue Lektion aus Thema und PDF-Bereich: KI bekommt Seiten, Lektion wird gespeichert und geöffnet', (
    tester,
  ) async {
    VisualLearnScreen.aiFactory = replying(
      (_) => {
        'lessons': [carLessonJson()],
      },
    );
    final pdf = _pdf(['Seite eins: Grundlagen', 'Seite zwei: Ableitung von Weg-Zeit-Funktionen', 'Seite drei']);
    VisualLearnScreen.pickPdfHook = () async => (name: 'Kinematik.pdf', bytes: pdf);
    VisualLearnScreen.renderPagesHook = (_, pages) async => [
      for (final _ in pages) Uint8List.fromList([137, 80, 78, 71]),
    ];
    await pumpApp(tester, const VisualLearnScreen(moduleId: 'm1', moduleName: 'Physik'));
    for (var i = 0; i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Noch keine – erstelle oben die erste.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('visual-topic')), 'Ableitung mit einem Auto erklären');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('visual-upload')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('Kinematik.pdf · 3 Seiten'), findsOneWidget);
    await tester.tap(find.text('Bereich'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('visual-page-from')), '2');
    await tester.enterText(find.byKey(const ValueKey('visual-page-to')), '3');
    await tester.tap(find.text('Ausführlich'));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('visual-create')));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await run(tester, 2);
    final sent = jsonEncode(requests.single);
    expect(sent, contains('Ableitung mit einem Auto erklären'));
    expect(sent, contains('--- Seite 2 ---'));
    expect(sent, isNot(contains('--- Seite 1 ---')));
    expect(sent, contains('Detailgrad: ausführlich'));
    expect(sent.split('"type":"image_url"').length - 1, 2, reason: 'zwei Seiten als Bild');

    // Geöffnet …
    expect(find.byType(VisualLessonScreen), findsOneWidget);
    await run(tester);
    // … und gespeichert.
    final saved = await tester.runAsync(() => VisualLessonRepository().forModule('m1'));
    expect(saved!.single.title, 'Vom Weg zur Geschwindigkeit');
    expect(saved.single.source, 'Kinematik.pdf, S. 2–3');
    expect(saved.single.detail, 'ausführlich');
    expect(saved.single.functions.map((f) => f.key), ['s', 'v'], reason: 'unlesbare Funktion aussortiert');
  });
}
