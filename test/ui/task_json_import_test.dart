import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/interactive_task.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/step_task.dart';
import 'package:lernen/models/task_verification.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/flashcards/task_folder_screen.dart';
import 'package:lernen/ui/study/script_match_runner.dart';
import 'package:lernen/ui/tasks/task_import_screen.dart';
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

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

/// Speichert nur im Speicher und merkt sich die Fundstellen im Skript.
class _RecordingCards extends FlashcardRepository {
  final saved = <Flashcard>[];
  final located = <String, ({String? materialId, int page})>{};

  @override
  Future<void> saveAll(List<Flashcard> cards) async => saved.addAll(cards);

  @override
  Future<int> updateScriptLocations(Map<String, ({String? materialId, int page})> locations) async {
    located.addAll(locations);
    return locations.length;
  }
}

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

Map<String, dynamic> _stepsTaskData(String answer) => {
      'steps': [
        {
          'title': 'Ergebnis',
          'prompt': 'Wie groß ist der Strom I in A?',
          'fields': [
            {'label': 'I =', 'kind': 'number', 'answer': answer},
          ],
        },
      ],
    };

/// Antwort einer externen KI: ein Rechenweg (mit falschem Ergebnis), eine
/// fertige Auswahlfrage und eine Aufgabe, die nicht interaktiv geht.
final _externalJson = '```json\n${jsonEncode({
  'tasks': [
    {
      'kind': 'steps',
      'page': 1,
      'front': 'Berechne den Strom I nach dem Ohmschen Gesetz für U = 12 V und R = 4 Ohm.',
      'back': 'I = U/R',
      'taskData': _stepsTaskData('4'),
    },
    {
      'kind': 'question',
      'page': 2,
      'front': 'Wie lautet das Ohmsche Gesetz?',
      'questionType': 'single_choice',
      'reason': 'Auswahl aus Formeln',
      'card': {
        'type': 'single_choice',
        'options': [
          {'text': 'U = R · I', 'isCorrect': true},
          {'text': 'U = R / I', 'isCorrect': false},
        ],
      },
    },
    {'kind': 'none', 'front': 'Zeichne den Schaltplan.', 'reason': 'Zeichnen', 'needs': 'Schaltplan zeichnen'},
  ],
})}\n```';

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_task_json_import_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() {
    TaskImportScreen.aiFactory = null;
    TaskImportScreen.pickJsonHook = null;
    ScriptMatchContext.aiFactory = null;
  });

  group('JSON einer externen KI lesen', () {
    test('Aufgaben, fertige Fragen (unter "card" oder als Liste) und Unbrauchbares', () {
      final result = AiService.parseImportedTasks(_externalJson);
      expect(result.drafts, hasLength(3));
      expect(result.dropped, 0);
      final steps = result.drafts[0];
      expect(steps.kind, InteractiveKind.steps);
      expect(steps.page, 1);
      final question = result.drafts[1];
      expect(question.asQuestion, isTrue);
      expect(question.questionData, isNotNull);
      // Ohne eigenen Wortlaut in "card" gilt der der Aufgabe.
      expect(question.front, 'Wie lautet das Ohmsche Gesetz?');
      expect(question.questionData!['type'], 'single_choice');
      expect(question.page, 2);
      expect(result.drafts[2].needs, 'Schaltplan zeichnen');

      // Liste fertiger Quizfragen (Format aus „JSON einfügen“), kaputte Einträge zählen.
      final cards = AiService.parseImportedTasks(jsonEncode({
        'flashcards': [
          {'type': 'free_text', 'front': 'Einheit der Spannung?', 'correctText': 'Volt'},
          {'type': 'single_choice', 'front': 'Ohne Optionen'},
          'kaputt',
        ],
      }));
      expect(cards.drafts.map((d) => d.front), contains('Einheit der Spannung?'));
      expect(cards.drafts.first.questionData!['correctText'], 'Volt');
      expect(cards.dropped, greaterThanOrEqualTo(1));
    });

    test('kein JSON: verständlicher Fehler', () {
      expect(() => AiService.parseImportedTasks('Hier ist deine Antwort!'), throwsA(isA<AiServiceException>()));
    });

    test('Prompt: ganzes Dokument, keine Höchstzahl, fertige Fragen unter "card"', () {
      final prompt = AiService.externalTaskPrompt;
      expect(prompt, isNot(contains('höchstens 8')));
      expect(prompt, contains('"card"'));
      expect(prompt, contains('"kind": "steps"'));
      expect(prompt, contains('aufgaben.json'));
    });

    test('Urteil der zweiten KI lesen', () {
      final v = TaskVerification.fromJson({
        'verdict': 'fehler',
        'comment': 'I = 3 A',
        'corrected': _stepsTaskData('3'),
      });
      expect(v.verdict, TaskVerdict.wrong);
      expect(v.corrected, isNotNull);
      expect(taskVerdictFrom('ok'), TaskVerdict.ok);
      expect(taskVerdictFrom('unklar'), TaskVerdict.unclear);
    });
  });

  testWidgets(
      'Importieren: einfügen, auf Richtigkeit prüfen, Korrektur übernehmen, Vorlesung zuordnen – dort wird die Lösung gesucht',
      (tester) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final verifyRequests = <String>[];
    TaskImportScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            final body = jsonDecode(r.body) as Map<String, dynamic>;
            final user = (body['messages'] as List)[1]['content'] as String;
            verifyRequests.add(user);
            if (user.contains('Art: steps')) {
              return _chat({
                'verdict': 'fehler',
                'comment': r'$I = U/R = 12/4 = 3$ A, nicht 4 A.',
                'corrected': _stepsTaskData('3'),
              });
            }
            return _chat({'verdict': 'ok', 'comment': 'Stimmt.', 'corrected': null});
          }),
        );
    ScriptMatchContext.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async => _chat({
                'matches': [
                  {'n': 1, 'page': 'c1'},
                  {'n': 2, 'page': 'c1'},
                ],
              })),
        );

    final materials = MaterialRepository();
    await tester.runAsync(() async {
      await materials.save(MaterialItem(
        id: 'folien',
        moduleId: 'm1',
        fileName: 'Vorlesung 2 – Gleichstrom.pdf',
        kind: MaterialKind.slide,
        extractedText: '',
        createdAt: DateTime(2026, 10, 1),
        unitId: 'u2',
        fileBytesBase64: base64Encode(_pdf([
          'Organisatorisches: Termine und Klausur',
          'Das Ohmsche Gesetz: Spannung U gleich Widerstand R mal Strom I',
        ])),
      ));
      await materials.loadForModule('m1');
    });
    final cards = _RecordingCards();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
        ChangeNotifierProvider<FlashcardRepository>.value(value: cards),
        ChangeNotifierProvider<MaterialRepository>.value(value: materials),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const TaskImportScreen(moduleId: 'm1', startWithJsonImport: true),
      ),
    ));
    await tester.pumpAndSettle();

    // Das Import-Fenster ist gleich offen: Prompt kopieren, Antwort einfügen.
    await tester.tap(find.byKey(const ValueKey('task-import-json-copy')));
    await tester.pumpAndSettle();
    expect(copied, AiService.externalTaskPrompt);
    expect(find.text('Prompt kopiert'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('task-import-json-text')), _externalJson);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-import-json-apply')));
    await tester.pumpAndSettle();

    expect(find.text('3 Aufgaben zum Übernehmen'), findsOneWidget);
    expect(
      find.text('3 Einträge importiert: 1 interaktiv, 1 fertige Frage.'),
      findsOneWidget,
    );
    expect(find.textContaining('fertige Frage (Single Choice)'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '2 Aufgaben speichern'), findsOneWidget);

    // Auf Richtigkeit prüfen: die zweite KI findet den Fehler im Rechenweg.
    await tester.ensureVisible(find.byKey(const ValueKey('task-import-verify')));
    await tester.tap(find.byKey(const ValueKey('task-import-verify')));
    await tester.pumpAndSettle();
    expect(verifyRequests, hasLength(2));
    expect(verifyRequests.first, contains('"answer":"4"'));
    expect(find.byKey(const ValueKey('task-import-verdict-0')), findsOneWidget);
    expect(find.textContaining('KI: Fehler gefunden'), findsWidgets);
    await tester.ensureVisible(find.byKey(const ValueKey('task-import-apply-fix-0')));
    await tester.tap(find.byKey(const ValueKey('task-import-apply-fix-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Korrektur übernommen'), findsWidgets);

    // Vorlesung zuordnen.
    await tester.ensureVisible(find.byKey(const ValueKey('task-import-lecture')));
    await tester.tap(find.byKey(const ValueKey('task-import-lecture')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorlesung 2 – Gleichstrom.pdf').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('task-import-save')));
    await tester.tap(find.byKey(const ValueKey('task-import-save')));
    await tester.pump();

    expect(cards.saved, hasLength(2));
    final steps = cards.saved.firstWhere((c) => c.type == QuestionType.steps);
    expect(StepTask.fromMap(steps.taskData)!.finalField!.answer, '3');
    final question = cards.saved.firstWhere((c) => c.type == QuestionType.singleChoice);
    expect(question.options!.where((o) => o.isCorrect).single.text, 'U = R · I');
    // Die Einheit der Vorlesung geht an die Aufgaben.
    expect(cards.saved.every((c) => c.unitId == 'u2'), isTrue);

    // Im Hintergrund: die Lösung in genau dieser Vorlesung suchen.
    for (var i = 0; i < 100 && cards.located.length < 2; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(cards.located.keys, containsAll([steps.id, question.id]));
    expect(cards.located.values.every((l) => l.materialId == 'folien'), isTrue);
  });

  testWidgets('Importieren aus einer Datei; kein JSON → Fehler mit Rohtext', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var content = 'Das ist leider kein JSON.';
    TaskImportScreen.pickJsonHook = () async => content;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
        ChangeNotifierProvider<FlashcardRepository>.value(value: _RecordingCards()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const TaskImportScreen(moduleId: 'm1'),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('task-import-json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-import-json-file')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-import-error')), findsOneWidget);
    expect(find.textContaining('kein gültiges JSON'), findsOneWidget);

    content = jsonEncode({
      'flashcards': [
        {'type': 'free_text', 'front': 'Einheit der Spannung?', 'correctText': 'Volt'},
      ],
    });
    await tester.tap(find.byKey(const ValueKey('task-import-json-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-import-json-file')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-import-error')), findsNothing);
    expect(find.textContaining('fertige Frage (Freitext)'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-import-answer-0')), findsOneWidget);
    expect(find.text('Speichern'), findsWidgets);
  });

  testWidgets('Aufgaben-Ordner: Import-Knopf öffnet das Import-Fenster', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
        ChangeNotifierProvider<FlashcardRepository>.value(value: _RecordingCards()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const TaskFolderScreen(moduleId: 'm1', moduleName: 'E-Technik'),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-folder-json-import')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskImportScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('task-import-json-copy')), findsOneWidget);
  });
}
