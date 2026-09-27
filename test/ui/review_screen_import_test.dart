import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/repositories/concept_repository.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/pdf_page_renderer.dart';
import 'package:lernen/services/pdf_question_import_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/review/review_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast.dart';

import '../services/pdf_question_import_service_test.dart' show pdfWithPages;

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _FakeRenderer implements PageImageRenderer {
  _FakeRenderer(this.png);
  final Uint8List png;

  @override
  Future<Uint8List?> renderPng(int page) async => png;

  @override
  Future<void> close() async {}
}

Future<Uint8List> _grayPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 300, 400), ui.Paint()..color = const ui.Color(0xFF888888));
  final image = await recorder.endRecording().toImage(300, 400);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_review_import_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() => ReviewScreen.importServiceFactory = null);

  testWidgets('Nachbereiten-Import: PDF seitenweise mit Bild, Aufgabenform und Abbildung bleiben erhalten',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final png = (await tester.runAsync(_grayPng))!;
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(body);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'questions': [
                    // Abweichendes Format einer Auswahlfrage (Optionen als Text,
                    // Lösung als Buchstabe) – früher eine Karteikarte.
                    {
                      'page': 1,
                      'type': 'singleChoice',
                      'question': 'Welche Einheit hat die Spannung?',
                      'options': ['Ampere', 'Volt', 'Ohm'],
                      'answer': 'B',
                      'solutionFromDocument': true,
                    },
                    {
                      'page': 1,
                      'type': 'fill_blank',
                      'front': 'U = ___ · I',
                      'blanks': ['R'],
                      'solutionFromDocument': true,
                    },
                    {
                      'page': 2,
                      'type': 'free_text',
                      'front': 'Wie groß ist der Strom in der Schaltung?',
                      'correctText': '2 A',
                      'imageBox': [0.1, 0.2, 0.9, 0.6],
                      'solutionFromDocument': false,
                    },
                  ],
                }),
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    ReviewScreen.importServiceFactory = (ai) => PdfQuestionImportService(
          ai: AiService(apiKey: ai.apiKey, model: ai.model, client: client),
          renderer: (_) async => _FakeRenderer(png),
        );

    final settings = SettingsRepository();
    final materials = MaterialRepository();
    final flashcards = FlashcardRepository();
    await tester.runAsync(() async {
      await settings.update(const AppSettings(openRouterApiKey: 'sk-test'));
      await materials.save(MaterialItem(
        id: 'blatt3',
        moduleId: 'm1',
        fileName: 'Blatt 3.pdf',
        kind: MaterialKind.exercise,
        extractedText: 'Seite 1\nSeite 2',
        createdAt: DateTime(2026, 9, 27),
        fileBytesBase64: base64Encode(pdfWithPages(2)),
      ));
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: materials),
        ChangeNotifierProvider.value(value: flashcards),
        ChangeNotifierProvider(create: (_) => ConceptRepository()),
        ChangeNotifierProvider(create: (_) => LectureUnitRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReviewScreen(moduleId: 'm1')),
            ),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fragen importieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorhandenes Material verwenden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blatt 3.pdf'));
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Übung ansehen'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.file_download_outlined));
    for (var i = 0; i < 60 && find.text('Speichern').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Vision-Modell mit Seitenbildern.
    expect(requests, hasLength(1));
    expect(requests.single['model'], const AppSettings().visionModelId);
    final content = (requests.single['messages'] as List)[1]['content'] as List;
    expect(content.where((c) => c['type'] == 'image_url'), hasLength(2));

    expect(find.textContaining('Single Choice'), findsOneWidget);
    expect(find.textContaining('Lückentext'), findsOneWidget);
    expect(find.textContaining('Freitext'), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    for (var i = 0; i < 40 && find.text('Öffnen').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('Öffnen'), findsOneWidget);

    final saved = (await tester.runAsync(() async {
      final db = await DatabaseService.instance.database;
      return (await DatabaseService.flashcards.find(db)).map((r) => Flashcard.fromMap(r.value)).toList();
    }))!;
    final byType = {for (final c in saved) c.type: c};
    expect(byType.keys.toSet(), {QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText});
    expect(byType[QuestionType.singleChoice]!.options!.map((o) => o.isCorrect), [false, true, false]);
    expect(byType[QuestionType.freeText]!.imageBase64, isNotNull);
    expect(byType[QuestionType.singleChoice]!.imageBase64, isNull);
    // Jede Frage weiß, wo sie im Material steht.
    expect(byType[QuestionType.singleChoice]!.sourceMaterialId, 'blatt3');
    expect(byType[QuestionType.singleChoice]!.sourcePage, 1);
    expect(byType[QuestionType.freeText]!.sourcePage, 2);

    await tester.pumpWidget(const SizedBox());
  });
}
