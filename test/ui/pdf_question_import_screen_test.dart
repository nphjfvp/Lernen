import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/interactive_task_scan_service.dart';
import 'package:lernen/services/pdf_question_import_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/import/pdf_question_import_screen.dart';
import 'package:lernen/ui/tasks/task_import_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast.dart';

import '../services/pdf_question_import_service_test.dart' show pdfWithPages, requestedPages;

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_pdf_import_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  testWidgets('PDF absuchen, Treffer abwählen, Rest als Karten importieren', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final pdf = pdfWithPages(2);
    final material = MaterialItem(
      id: 'mat1',
      moduleId: 'm1',
      fileName: 'Altklausur.pdf',
      kind: MaterialKind.exercise,
      extractedText: '',
      createdAt: DateTime(2026, 9, 27),
      fileBytesBase64: base64Encode(pdf),
      unitId: 'u1',
    );
    final client = MockClient((request) async {
      final pages = requestedPages(request);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'questions': [
                    for (final p in pages)
                      {
                        'page': p,
                        'type': 'free_text',
                        'front': 'Frage $p?',
                        'correctText': 'Antwort $p',
                        'solutionFromDocument': p == 1,
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

    final flashcards = FlashcardRepository();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MaterialRepository()),
        ChangeNotifierProvider.value(value: flashcards),
        ChangeNotifierProvider(create: (_) => SettingsRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PdfQuestionImportScreen(
                moduleId: 'm1',
                material: material,
                serviceFactory: () => PdfQuestionImportService(
                  ai: AiService(apiKey: 'k', model: 'vision', client: client),
                  // Ohne Render-Engine im Test: Seiten gehen als PDF an die KI.
                  renderer: (_) async => null,
                ),
              ),
            )),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('Altklausur.pdf'), findsOneWidget);
    expect(find.text('2 Seiten'), findsOneWidget);
    await tester.tap(find.text('Jede Frage'));
    await tester.pump();
    await tester.tap(find.text('Fragen suchen'));
    await tester.pumpAndSettle();

    expect(find.text('2 Fragen auf 2 Seiten gefunden.'), findsOneWidget);
    expect(find.text('Lösung von der KI'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-question-1')));
    await tester.pump();
    await tester.tap(find.text('1 Frage importieren'));
    // Speichern schreibt in die echte Datenbank – echte Wartezeit nötig.
    for (var i = 0; i < 20 && find.text('1 Frage importiert').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.text('1 Frage importiert'), findsOneWidget);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    expect(find.text('Öffnen'), findsOneWidget);

    final saved = (await tester.runAsync(() async {
      final db = await DatabaseService.instance.database;
      return (await DatabaseService.flashcards.find(db)).map((r) => Flashcard.fromMap(r.value)).toList();
    }))!;
    expect(saved.map((c) => c.front), ['Frage 1?']);
    expect(saved.single.unitId, 'u1');
    expect(saved.single.priorityIntroduction, isTrue);
  });

  testWidgets('Interaktive Aufgaben: Wunsch an die KI, Funde mit Seite in „Aufgabe übernehmen“', (tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final material = MaterialItem(
      id: 'blatt5',
      moduleId: 'm1',
      fileName: 'Übung 5.pdf',
      kind: MaterialKind.exercise,
      extractedText: '',
      createdAt: DateTime(2026, 10, 1),
      fileBytesBase64: base64Encode(pdfWithPages(3)),
    );
    final prompts = <String>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final content = (body['messages'] as List)[1]['content'];
      final text = content is String
          ? content
          : [
              for (final part in content as List)
                if (part is Map && part['type'] == 'text') part['text'] as String,
            ].join('\n');
      prompts.add(text);
      final first = text.contains('--- Seite 1 ---');
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'tasks': [
                    if (first)
                      {
                        'kind': 'steps',
                        'page': 2,
                        'front': 'Aufgabe 2: Löse x + 1 = 3.',
                        'taskData': {
                          'steps': [
                            {
                              'title': 'Ergebnis',
                              'prompt': 'Löse nach x auf.',
                              'fields': [
                                {'label': 'x =', 'answer': '2'},
                              ],
                            },
                          ],
                        },
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

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MaterialRepository()),
        ChangeNotifierProvider(create: (_) => FlashcardRepository()),
        ChangeNotifierProvider(create: (_) => SettingsRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PdfQuestionImportScreen(
                moduleId: 'm1',
                material: material,
                interactive: true,
                interactiveServiceFactory: () => InteractiveTaskScanService(
                  ai: AiService(apiKey: 'k', model: 'vision', client: client),
                  renderer: (_) async => null,
                ),
              ),
            )),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('Interaktive Aufgaben aus PDF'), findsOneWidget);
    // Die Fragen-Optionen gibt es in diesem Modus nicht.
    expect(find.text('Welche Fragen?'), findsNothing);
    expect(find.textContaining('2 KI-Anfragen'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('import-interactive-instruction')),
      'alle Mathe-Aufgaben als Rechenweg',
    );
    await tester.tap(find.byKey(const ValueKey('import-interactive-kind-steps')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('import-interactive-start')));
    await tester.tap(find.byKey(const ValueKey('import-interactive-start')));
    await tester.pumpAndSettle();

    expect(prompts, hasLength(2));
    expect(prompts.every((p) => p.contains('alle Mathe-Aufgaben als Rechenweg')), isTrue);
    expect(prompts.every((p) => p.contains('Gewünscht: "kind": "steps"')), isTrue);
    expect(find.byType(TaskImportScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('task-import-document')), findsOneWidget);
    expect(find.textContaining('S. 2 · Aufgabe 2'), findsOneWidget);
  });

  testWidgets('Moduswechsel: Fragen ↔ Interaktive Aufgaben', (tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final material = MaterialItem(
      id: 'blatt6',
      moduleId: 'm1',
      fileName: 'Übung 6.pdf',
      kind: MaterialKind.exercise,
      extractedText: '',
      createdAt: DateTime(2026, 10, 1),
      fileBytesBase64: base64Encode(pdfWithPages(1)),
    );
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MaterialRepository()),
        ChangeNotifierProvider(create: (_) => FlashcardRepository()),
        ChangeNotifierProvider(create: (_) => SettingsRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: PdfQuestionImportScreen(moduleId: 'm1', material: material),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Welche Fragen?'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-interactive-instruction')), findsNothing);
    await tester.tap(find.text('Interaktive Aufgaben'));
    await tester.pumpAndSettle();
    expect(find.text('Welche Fragen?'), findsNothing);
    expect(find.byKey(const ValueKey('import-interactive-instruction')), findsOneWidget);
    expect(find.text('Interaktive Aufgaben erstellen'), findsOneWidget);
  });

  /// Baut den Screen mit einer einzelnen KI-Antwort, deren erklärter Typ
  /// (hier single_choice) unvollständig ist (keine "options") – wird von
  /// normalizeGeneratedFlashcard auf "flashcard" zurückgestuft und muss in
  /// der Vorschau als unsicher markiert sein (siehe QuestionParsing).
  Future<FlashcardRepository> pumpWithUncertainQuestion(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final pdf = pdfWithPages(1);
    final material = MaterialItem(
      id: 'mat-uncertain',
      moduleId: 'm1',
      fileName: 'Uebungsblatt.pdf',
      kind: MaterialKind.exercise,
      extractedText: '',
      createdAt: DateTime(2026, 9, 27),
      fileBytesBase64: base64Encode(pdf),
    );
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'questions': [
                      {
                        'page': 1,
                        'type': 'single_choice',
                        'front': 'Unsichere Frage?',
                        'back': 'Kurze Antwort',
                      },
                    ],
                  }),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ));

    final flashcards = FlashcardRepository();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MaterialRepository()),
        ChangeNotifierProvider.value(value: flashcards),
        ChangeNotifierProvider(create: (_) => SettingsRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PdfQuestionImportScreen(
                moduleId: 'm1',
                material: material,
                serviceFactory: () => PdfQuestionImportService(
                  ai: AiService(apiKey: 'k', model: 'vision', client: client),
                  renderer: (_) async => null,
                ),
              ),
            )),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jede Frage'));
    await tester.pump();
    await tester.tap(find.text('Fragen suchen'));
    await tester.pumpAndSettle();
    return flashcards;
  }

  testWidgets('Unsicher erkannte Frage zeigt Warn-Chip und fragt vor dem Import nach', (tester) async {
    await pumpWithUncertainQuestion(tester);

    expect(find.textContaining('Unsicher: sollte'), findsOneWidget);
    await tester.tap(find.text('1 Frage importieren'));
    await tester.pumpAndSettle();

    expect(find.text('1 Frage unsicher erkannt'), findsOneWidget);
    expect(find.text('Weglassen'), findsOneWidget);
    expect(find.text('Als Karteikarte speichern'), findsOneWidget);
  });

  testWidgets('"Weglassen" speichert die unsichere Frage nicht', (tester) async {
    await pumpWithUncertainQuestion(tester);
    await tester.tap(find.text('1 Frage importieren'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Weglassen'));
    await tester.pumpAndSettle();

    // Kein Speichervorgang wurde ausgelöst – die Vorschau bleibt stehen.
    expect(find.text('1 Frage importieren'), findsOneWidget);
    final saved = (await tester.runAsync(() async {
      final db = await DatabaseService.instance.database;
      return (await DatabaseService.flashcards.find(db)).map((r) => Flashcard.fromMap(r.value)).toList();
    }))!;
    // Die DB ist prozessweit/über die Tests dieser Datei hinweg geteilt –
    // gezielt nach der Frage dieses Tests filtern statt den ganzen Bestand
    // zu prüfen.
    expect(saved.where((c) => c.front == 'Unsichere Frage?'), isEmpty);
  });

  testWidgets('"Als Karteikarte speichern" importiert sie trotzdem', (tester) async {
    await pumpWithUncertainQuestion(tester);
    await tester.tap(find.text('1 Frage importieren'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Als Karteikarte speichern'));
    for (var i = 0; i < 20 && find.text('1 Frage importiert').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.text('1 Frage importiert'), findsOneWidget);
    final saved = (await tester.runAsync(() async {
      final db = await DatabaseService.instance.database;
      return (await DatabaseService.flashcards.find(db)).map((r) => Flashcard.fromMap(r.value)).toList();
    }))!;
    final ours = saved.where((c) => c.front == 'Unsichere Frage?').toList();
    expect(ours.single.type, QuestionType.flashcard);
  });
}
