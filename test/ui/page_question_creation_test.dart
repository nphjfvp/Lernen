import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/repositories/model_catalog_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/image_crop.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/widgets/model_override_tile.dart';
import 'package:provider/provider.dart';
import 'package:lernen/ui/widgets/page_question_creation_sheet.dart';
import 'package:lernen/ui/widgets/page_region_picker.dart';

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

/// Einstellungen mit Typ-Vorgaben; merkt sich, was gespeichert wird.
class _SettingsWithPrefs extends SettingsRepository {
  _SettingsWithPrefs(this._current);
  AppSettings _current;

  @override
  AppSettings get settings => _current;

  @override
  Future<void> update(AppSettings settings) async {
    _current = settings;
    notifyListeners();
  }
}

/// PNG mit linker Hälfte rot, rechter Hälfte blau.
Future<Uint8List> _twoColorPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, width / 2, height.toDouble()), ui.Paint()..color = const ui.Color(0xFFFF0000));
  canvas.drawRect(
      ui.Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()), ui.Paint()..color = const ui.Color(0xFF0000FF));
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<(int, int, int)> _sizeAndFirstPixel(Uint8List png) async {
  final image = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (image.width, image.height, rgba.getUint32(0));
}

void main() {
  group('buildPageQuestionCards', () {
    final now = DateTime(2026, 9, 26);

    test('schneidet auf bestellte Fragen/Stufen zu und verwirft unbrauchbare Karten', () {
      final groups = [
        [
          {'type': 'flashcard', 'front': 'F1', 'back': 'A1', 'needsImage': true},
          {'type': 'free_text', 'front': 'F1 schwer', 'correctText': 'A1'},
          {'type': 'flashcard', 'front': 'zu viel', 'back': 'x'},
        ],
        [
          // Ohne jede Antwort nicht zu retten -> Frage fällt weg.
          {'type': 'flashcard', 'front': 'F2'},
        ],
        [
          {'type': 'flashcard', 'front': 'F3', 'back': 'A3'},
        ],
        [
          {'type': 'flashcard', 'front': 'nicht bestellt', 'back': 'x'},
        ],
      ];

      final result = buildPageQuestionCards(
        groups,
        moduleId: 'm1',
        unitId: 'u1',
        questionCount: 3,
        tierCount: 2,
        attachImageBase64: 'BILD',
        now: now,
      );

      expect(result.map((q) => q.map((c) => c.front).toList()).toList(), [
        ['F1', 'F1 schwer'],
        ['F3'],
      ]);
      final first = result.first.first;
      expect(first.imageBase64, 'BILD');
      expect(result.first[1].imageBase64, isNull);
      expect(result.first[1].type, QuestionType.freeText);
      expect(first.moduleId, 'm1');
      expect(first.unitId, 'u1');
      expect(first.priorityIntroduction, isTrue);
    });
  });

  group('mergeTiersIntoChain', () {
    Flashcard card(String id, QuestionType type, String front) => Flashcard(
          id: id,
          moduleId: 'm1',
          front: front,
          back: 'Antwort',
          createdAt: DateTime(2026, 9, 26),
          due: DateTime(2026, 9, 26),
          type: type,
          priorityIntroduction: true,
        );

    test('mehrere Stufen werden eine Karte mit vorbereiteten Folgestufen', () {
      final merged = mergeTiersIntoChain([
        card('a', QuestionType.singleChoice, 'Leicht'),
        card('b', QuestionType.fillBlank, 'Mittel'),
        card('c', QuestionType.freeText, 'Schwer'),
      ]);
      expect(merged.id, 'a');
      expect(merged.front, 'Leicht');
      expect(merged.variantChain, [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText]);
      expect(merged.pendingVariants!.map((v) => v.front), ['Mittel', 'Schwer']);
      expect(merged.priorityIntroduction, isTrue);
    });

    test('eine Stufe bleibt unverändert', () {
      final single = card('a', QuestionType.flashcard, 'Nur eine');
      expect(identical(mergeTiersIntoChain([single]), single), isTrue);
    });
  });

  group('cropImageRelative', () {
    test('schneidet den relativen Ausschnitt pixelgenau aus', () async {
      final png = await _twoColorPng(100, 50);
      final crop = await cropImageRelative(png, const ui.Rect.fromLTRB(0.5, 0, 1, 1));
      final (width, height, firstPixel) = await _sizeAndFirstPixel(crop!);
      expect(width, 50);
      expect(height, 50);
      expect(firstPixel, 0x0000FFFF); // RGBA: blau
    });

    test('leerer Ausschnitt und kaputte Bilder liefern null', () async {
      final png = await _twoColorPng(10, 10);
      expect(await cropImageRelative(png, const ui.Rect.fromLTRB(0.5, 0.5, 0.5, 0.9)), isNull);
      expect(await cropImageRelative(Uint8List.fromList([1, 2, 3]), const ui.Rect.fromLTRB(0, 0, 1, 1)), isNull);
    });
  });

  group('downscaleImage', () {
    test('verkleinert auf die längere Seite, kleine Bilder bleiben', () async {
      final big = await _twoColorPng(2000, 1000);
      final (w, h, _) = await _sizeAndFirstPixel((await downscaleImage(big, maxSide: 1280))!);
      expect(w, 1280);
      expect(h, 640);
      final small = await _twoColorPng(300, 200);
      expect(identical(await downscaleImage(small, maxSide: 1280), small), isTrue);
    });
  });

  testWidgets('Bereich markieren: Rahmen ziehen und übernehmen', (tester) async {
    final png = (await tester.runAsync(() => _twoColorPng(200, 100)))!;
    Rect? picked;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showPageRegionPicker(context, png),
            child: const Text('öffnen'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Bildgröße wird echt asynchron gelesen.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    final canvas = find.byKey(const ValueKey('region-canvas'));
    expect(canvas, findsOneWidget);
    final box = tester.getRect(canvas);
    // Seitenverhältnis des Bildes (2:1) bleibt erhalten.
    expect(box.width / box.height, closeTo(2, 0.01));

    await tester.dragFrom(
      box.topLeft + Offset(box.width * 0.25, box.height * 0.2),
      Offset(box.width * 0.5, box.height * 0.6),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Übernehmen'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.left, closeTo(0.25, 0.005));
    expect(picked!.top, closeTo(0.2, 0.005));
    expect(picked!.right, closeTo(0.75, 0.02));
    expect(picked!.bottom, closeTo(0.8, 0.02));
  });

  testWidgets('Einstellungen: Stufen stehen auf "KI entscheidet", bis zu 5 Fragen wählbar', (tester) async {
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(
        body: PageQuestionCreationSheet(
          material: MaterialItem(
            id: 'mat1',
            moduleId: 'm1',
            fileName: 'Folien.pdf',
            kind: MaterialKind.slide,
            extractedText: 'Text',
            createdAt: DateTime(2026, 9, 26),
          ),
          pageNumber: 3,
          pageText: 'Seitentext',
          pageImageBytes: Uint8List.fromList([1]),
          highlightsOnPage: const [],
          initialQuestionText: 'Markierter Satz',
        ),
      ),
    ));

    expect(find.text('Frage aus Seite 3'), findsOneWidget);
    expect(find.text('Markierter Satz'), findsOneWidget);
    expect(find.text('KI entscheidet'), findsNWidgets(3));
    expect(find.text('Bereich markieren'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Frage erstellen'), findsOneWidget);

    await tester.tap(find.text('5'));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, '5 Fragen erstellen'), findsOneWidget);

    // "Interaktiv" ist als fester Typ wählbar.
    await tester.tap(find.text('KI entscheidet').first);
    await tester.pumpAndSettle();
    expect(find.text('Interaktiv').last, findsOneWidget);
  });

  group('Modellwechsel', () {
    Widget host(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
            ChangeNotifierProvider<ModelCatalogRepository>.value(value: ModelCatalogRepository()),
          ],
          child: MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: Scaffold(body: child)),
        );

    testWidgets('schon erstellte Fragen der Seite, Doppel-Warnung, interaktiv üben', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final png = (await tester.runAsync(() => _twoColorPng(40, 20)))!;
      String? interactive;
      final existing = Flashcard(
        id: 'k1',
        moduleId: 'm1',
        front: 'Berechne den Diffusionskoeffizienten bei 1000 K.',
        back: '',
        createdAt: DateTime(2026, 10, 1),
        due: DateTime(2026, 10, 1),
        sourceMaterialId: 'mat1',
        sourcePage: 3,
      );
      await tester.pumpWidget(host(Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: PageQuestionCreationSheet(
                material: MaterialItem(
                  id: 'mat1',
                  moduleId: 'm1',
                  fileName: 'Blatt.pdf',
                  kind: MaterialKind.exercise,
                  extractedText: 'Text',
                  createdAt: DateTime(2026, 9, 26),
                ),
                pageNumber: 3,
                pageText: 'Aufgabe 1 a) b)',
                pageImageBytes: png,
                highlightsOnPage: const [
                  MaterialHighlight(
                    id: 'h1',
                    text: 'Aufgabe 1a',
                    color: HighlightColor.yellow,
                    source: HighlightSource.question,
                    pageNumber: 3,
                  ),
                ],
                existingCards: [existing],
                onInteractive: (focus) => interactive = focus,
              ),
            ),
          )),
          child: const Text('Öffnen'),
        ),
      )));
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();

      expect(find.text('1 Frage aus dieser Seite gibt es schon'), findsOneWidget);
      final focus = find.byType(TextField).first;
      await tester.enterText(focus, '1 a');
      await tester.pump();
      expect(find.byKey(const ValueKey('page-q-duplicate')), findsOneWidget);
      await tester.enterText(focus, 'Aufgabe 1b');
      await tester.pump();
      expect(find.byKey(const ValueKey('page-q-duplicate')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('page-q-interactive')));
      await tester.tap(find.byKey(const ValueKey('page-q-interactive')));
      await tester.pumpAndSettle();
      expect(interactive, 'Aufgabe 1b');
      expect(find.byType(PageQuestionCreationSheet), findsNothing);
    });

    testWidgets('Auswahlfeld: Standard zeigen, anderes Modell wählen, zurück auf Standard', (tester) async {
      String? override;
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => ModelOverrideTile(
          defaultId: AppSettings.defaultVisionModel,
          overrideId: override,
          vision: true,
          hint: 'Ein Hinweis',
          onChanged: (id) => setState(() => override = id),
        ),
      )));

      expect(find.textContaining('Standard aus den Einstellungen'), findsOneWidget);
      expect(find.textContaining('Gemini 2.5 Flash'), findsOneWidget);
      expect(find.text('Ein Hinweis'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('model-override')));
      await tester.pumpAndSettle();
      // Nur Modelle mit Bildverständnis stehen zur Wahl.
      expect(find.textContaining('DeepSeek'), findsNothing);
      await tester.tap(find.textContaining('Claude 3.5 Haiku'));
      await tester.pumpAndSettle();

      expect(override, 'anthropic/claude-3.5-haiku');
      expect(find.text('KI-Modell für diese Aktion'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('model-override-reset')));
      await tester.pumpAndSettle();
      expect(override, isNull);
      expect(find.textContaining('Standard aus den Einstellungen'), findsOneWidget);
    });

    testWidgets('Frage erstellen: gewähltes Modell geht an die KI, "Neu" nutzt es erneut', (tester) async {
      tester.view.physicalSize = const Size(1200, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final png = (await tester.runAsync(() => _twoColorPng(40, 20)))!;

      final models = <String>[];
      final client = MockClient((request) async {
        models.add((jsonDecode(request.body) as Map)['model'] as String);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'questions': [
                      {
                        'flashcards': [
                          {'type': 'flashcard', 'front': 'Was ist ein Werkstoff?', 'back': 'Ein Stoff'},
                        ],
                      },
                    ],
                  }),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      await tester.pumpWidget(host(PageQuestionCreationSheet(
        material: MaterialItem(
          id: 'mat1',
          moduleId: 'm1',
          fileName: 'Folien.pdf',
          kind: MaterialKind.slide,
          extractedText: 'Text',
          createdAt: DateTime(2026, 9, 26),
        ),
        pageNumber: 3,
        pageText: 'Seitentext',
        pageImageBytes: png,
        highlightsOnPage: const [],
        aiFactory: (key, model) => AiService(apiKey: key, model: model, client: client),
      )));

      // Bilder werden echt asynchron verarbeitet, der Ladekreis animiert
      // endlos – deshalb gezielt warten, bis das Erstellen durch ist.
      Future<void> untilGenerated(int calls) async {
        for (var i = 0; i < 100 && (models.length < calls || find.byType(CircularProgressIndicator).evaluate().isNotEmpty); i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
      }

      // Standard: das Vision-Modell aus den Einstellungen.
      await tester.tap(find.widgetWithText(FilledButton, 'Frage erstellen'));
      await tester.pump();
      await untilGenerated(1);
      expect(models, [AppSettings.defaultVisionModel]);
      expect(find.text('Was ist ein Werkstoff?'), findsWidgets);

      // In der Vorschau ein stärkeres Modell wählen und alles neu erstellen.
      await tester.tap(find.byKey(const ValueKey('model-override')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Claude 3.5 Haiku'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('regenerate-with-model')));
      await tester.pumpAndSettle();
      expect(find.text('Alle Fragen neu erstellen?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Neu erstellen'));
      await tester.pump();
      await untilGenerated(2);

      expect(models, [AppSettings.defaultVisionModel, 'anthropic/claude-3.5-haiku']);
    });

    testWidgets('Hinweis erscheint bei Tabellen als gewähltem Typ', (tester) async {
      tester.view.physicalSize = const Size(1200, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(PageQuestionCreationSheet(
        material: MaterialItem(
          id: 'mat1',
          moduleId: 'm1',
          fileName: 'Folien.pdf',
          kind: MaterialKind.slide,
          extractedText: 'Text',
          createdAt: DateTime(2026, 9, 26),
        ),
        pageNumber: 3,
        pageText: 'Seitentext',
        pageImageBytes: Uint8List.fromList([1]),
        highlightsOnPage: const [],
      )));
      expect(find.textContaining('stärkeren Modell'), findsNothing);

      await tester.tap(find.text('KI entscheidet').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tabelle').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tabellen, interaktive Seiten und Bildfragen'), findsOneWidget);
    });
  });

  group('Typ-Vorgaben je Stufe', () {
    MaterialItem material() => MaterialItem(
          id: 'mat1',
          moduleId: 'm1',
          fileName: 'Folien.pdf',
          kind: MaterialKind.slide,
          extractedText: 'Text',
          createdAt: DateTime(2026, 9, 26),
        );

    Widget host(SettingsRepository settings) => MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsRepository>.value(value: settings),
            ChangeNotifierProvider<ModelCatalogRepository>.value(value: ModelCatalogRepository()),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [AppColors.light]),
            home: Scaffold(
              body: PageQuestionCreationSheet(
                material: material(),
                pageNumber: 1,
                pageText: 'Seitentext',
                pageImageBytes: Uint8List.fromList([1]),
                highlightsOnPage: const [],
              ),
            ),
          ),
        );

    testWidgets('sind vorausgewählt, ohne Vorgabe entscheidet die KI', (tester) async {
      tester.view.physicalSize = const Size(1200, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(_SettingsWithPrefs(const AppSettings(
        openRouterApiKey: 'sk-test',
        pageQuestionTierTypes: {'schwer': 'freeText', 'mittel': 'table'},
      ))));

      // Leicht: keine Vorgabe.
      expect(find.text('KI entscheidet'), findsOneWidget);
      expect(find.text('Tabelle'), findsOneWidget);
      expect(find.text('Freitext'), findsOneWidget);
    });

    testWidgets('von Hand änderbar und als neuer Standard speicherbar', (tester) async {
      tester.view.physicalSize = const Size(1200, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final settings = _SettingsWithPrefs(const AppSettings(
        openRouterApiKey: 'sk-test',
        pageQuestionTierTypes: {'schwer': 'freeText'},
      ));
      await tester.pumpWidget(host(settings));

      // Schwer einschalten und dort "Lernen" statt "Freitext" wählen.
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Freitext'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lernen').last);
      await tester.pumpAndSettle();
      // Nur für dieses Fenster: gespeichert ist noch der alte Stand.
      expect(settings.settings.pageQuestionTierTypes, {'schwer': 'freeText'});

      await tester.tap(find.byKey(const ValueKey('save-tier-defaults')));
      await tester.pumpAndSettle();
      expect(settings.settings.pageQuestionTierTypes, {'schwer': 'learn'});
      expect(find.textContaining('Als Standard gespeichert'), findsOneWidget);
    });
  });
}
