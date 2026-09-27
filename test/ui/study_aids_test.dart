import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/repositories/concept_repository.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/study/socratic_screen.dart';
import 'package:lernen/ui/study/study_aids.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast.dart';

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

Flashcard _choice({String id = 'q1', int lapses = 0, int missStreak = 0, String? sourceId, int? page}) => Flashcard(
      id: id,
      moduleId: 'm1',
      front: 'Welche Einheit hat die Spannung?',
      back: '',
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      type: QuestionType.singleChoice,
      options: const [
        QuizOption(text: 'Volt', isCorrect: true),
        QuizOption(text: 'Ampere', isCorrect: false),
      ],
      lapses: lapses,
      variantMissStreak: missStreak,
      reps: lapses + missStreak,
      sourceMaterialId: sourceId,
      sourcePage: page,
    );

http.Response _text(String content) => http.Response(
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

Future<void> _answerWrong(WidgetTester tester, Flashcard card, {bool withMaterials = false}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsRepository>(create: (_) => _SettingsWithKey()),
      if (withMaterials) ChangeNotifierProvider(create: (_) => MaterialRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: QuestionAnswerView(key: ValueKey(card.id), card: card, isNew: false, onComplete: ({selfGrade, isCorrect}) {}),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Ampere'));
  await tester.pump();
  await tester.tap(find.text('Prüfen'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_study_aids_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  group('Lernhilfen nach der Antwort', () {
    testWidgets('erstmals falsch: Lerneinheit ja, Sokrates noch nicht; ohne Material kein "Im Skript"', (tester) async {
      await _answerWrong(tester, _choice());
      expect(find.byKey(const ValueKey('aid-lesson')), findsOneWidget);
      expect(find.byKey(const ValueKey('aid-socratic')), findsNothing);
      expect(find.byKey(const ValueKey('aid-source')), findsNothing);
    });

    testWidgets('wieder falsch: Sokrates wird angeboten, "Im Skript" mit Material', (tester) async {
      await _answerWrong(tester, _choice(missStreak: 1), withMaterials: true);
      expect(find.text('Diese Frage geht öfter schief – erarbeite sie dir Schritt für Schritt selbst.'), findsOneWidget);
      expect(find.byKey(const ValueKey('aid-socratic')), findsOneWidget);
      expect(find.byKey(const ValueKey('aid-source')), findsOneWidget);
    });
  });

  testWidgets('Sokrates-Dialog: Gegenfrage, eigene Antwort, gelöst', (tester) async {
    final prompts = <String>[];
    final replies = [
      'Womit misst man Spannung – und wie heißt das Messgerät?',
      'Genau, das Voltmeter misst in Volt.\n[[GELÖST]]',
    ];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      prompts.add((body['messages'] as List).last['content'] as String);
      return _text(replies[prompts.length - 1]);
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: SocraticScreen(
        card: _choice(),
        ai: AiService(apiKey: 'k', model: 'm', client: client),
        wrongAnswer: 'Ampere',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Womit misst man Spannung – und wie heißt das Messgerät?'), findsOneWidget);
    expect(prompts.single, contains('Seine letzte falsche Antwort: Ampere'));

    await tester.enterText(find.byKey(const ValueKey('socratic-input')), 'Mit dem Voltmeter, also Volt');
    await tester.tap(find.byKey(const ValueKey('socratic-send')));
    await tester.pumpAndSettle();
    expect(prompts.last, contains('Lernender: Mit dem Voltmeter, also Volt'));
    expect(find.text('Genau, das Voltmeter misst in Volt.'), findsOneWidget);
    expect(find.byKey(const ValueKey('socratic-solved')), findsOneWidget);
    expect(find.text('Fertig'), findsOneWidget);
    expect(find.byKey(const ValueKey('socratic-input')), findsNothing);
  });

  testWidgets('Sokrates-Dialog: "Lösung zeigen" beendet ihn mit der Lösung', (tester) async {
    final client = MockClient((request) async => _text('Was misst ein Voltmeter?'));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: SocraticScreen(card: _choice(), ai: AiService(apiKey: 'k', model: 'm', client: client)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lösung zeigen'));
    await tester.pumpAndSettle();
    expect(find.text('Lösung: Volt'), findsOneWidget);
    expect(find.text('Fertig'), findsOneWidget);
  });

  testWidgets('Lerneinheit wird einmal erzeugt, an der Karte gespeichert und zeigt die Quellseite', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final flashcards = FlashcardRepository();
    final materials = MaterialRepository();
    final card = _choice(id: 'lesson-card', sourceId: 'skript', page: 3);
    await tester.runAsync(() async {
      await flashcards.saveAll([card]);
      await materials.save(MaterialItem(
        id: 'skript',
        moduleId: 'm1',
        fileName: 'Skript.pdf',
        kind: MaterialKind.slide,
        extractedText: 'x',
        createdAt: DateTime(2026, 9, 1),
      ));
    });
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return _text('Worum es geht: Spannung.\nKern: Sie wird in Volt gemessen.\nMerke: U in V.');
    });
    final ai = AiService(apiKey: 'k', model: 'm', client: client);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: flashcards),
        ChangeNotifierProvider.value(value: materials),
        ChangeNotifierProvider(create: (_) => ConceptRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showMiniLesson(context, card, ai: ai), child: const Text('Öffnen')),
          ),
        ),
      ),
    ));

    Future<void> openAndWait() async {
      await tester.tap(find.text('Öffnen'));
      for (var i = 0; i < 30 && find.text('Sie wird in Volt gemessen.').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    await openAndWait();
    expect(find.text('Sie wird in Volt gemessen.'), findsOneWidget);
    expect(find.text('Kern'), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-open-source')), findsOneWidget);
    expect(find.text('Skript.pdf, Seite 3'), findsOneWidget);
    expect(calls, 1);

    final stored = (await tester.runAsync(() async {
      final db = await DatabaseService.instance.database;
      return Flashcard.fromMap((await DatabaseService.flashcards.record('lesson-card').get(db))!);
    }))!;
    expect(stored.miniLesson, contains('Sie wird in Volt gemessen.'));

    // Zweites Öffnen: aus der gespeicherten Karte, ohne neue Anfrage.
    Navigator.of(tester.element(find.text('Kurze Lerneinheit'))).pop();
    await tester.pumpAndSettle();
    await openAndWait();
    expect(find.text('Sie wird in Volt gemessen.'), findsOneWidget);
    expect(calls, 1);
  });
}
