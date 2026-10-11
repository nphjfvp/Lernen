import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/card_flag.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/card_flag_repository.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/visual_lesson_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/daily_quiz_screen.dart';
import 'package:lernen/ui/flags/flagged_questions_screen.dart';
import 'package:lernen/ui/visual/visual_from_card.dart';
import 'package:lernen/ui/visual/visual_lesson_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import '../services/visual_diagram_test.dart' show latticeScene;

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Settings extends SettingsRepository {
  _Settings({this.key});
  final String? key;

  @override
  AppSettings get settings => AppSettings(openRouterApiKey: key);
}

Module _module(String id, String name) =>
    Module(id: id, name: name, colorValue: 0xFF3D5AFE, icon: '📘', examDate: null, createdAt: DateTime(2026, 1, 1));

Flashcard _choice(String id, String moduleId) => Flashcard(
  id: id,
  moduleId: moduleId,
  front: 'Warum dehnt sich Stahl beim Erwärmen aus? ($id)',
  back: 'Die Atome schwingen stärker und brauchen mehr Platz.',
  createdAt: DateTime(2026, 9, 1),
  due: DateTime(2026, 1, 1),
  type: QuestionType.singleChoice,
  options: [
    QuizOption(text: 'Stärkere Gitterschwingung', isCorrect: true),
    QuizOption(text: 'Mehr Atome', isCorrect: false),
  ],
);

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_card_flags_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() => VisualFromCardDialog.aiFactory = null);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester);
  }

  testWidgets('Daily Quiz: Frage als fehlerhaft markieren mit Notiz, ändern, in der Liste wiederfinden, entfernen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final modules = ModuleRepository();
    final flashcards = FlashcardRepository();
    final flags = CardFlagRepository();
    await tester.runAsync(() async {
      await modules.save(_module('mf', 'Werkstoffkunde'));
      await flashcards.saveAll([_choice('f1', 'mf')]);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModuleRepository>.value(value: modules),
          ChangeNotifierProvider<FlashcardRepository>.value(value: flashcards),
          ChangeNotifierProvider<LectureUnitRepository>(create: (_) => LectureUnitRepository()),
          ChangeNotifierProvider<SettingsRepository>.value(value: _Settings()),
          ChangeNotifierProvider<CardFlagRepository>.value(value: flags),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const Scaffold(body: DailyQuizScreen()),
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('Warum dehnt sich Stahl'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('card-flag')), matching: find.byIcon(Icons.bookmark_border)),
      findsOneWidget,
    );

    await tap(tester, 'card-flag');
    expect(find.text('Frage markieren'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('card-flag-note')), 'Option „Mehr Atome“ ist unklar formuliert');
    await tap(tester, 'card-flag-save');
    expect(flags.flagOf('f1')!.kind, CardFlagKind.error);
    expect(flags.flagOf('f1')!.note, contains('unklar'));
    expect(flags.flagOf('f1')!.moduleId, 'mf');
    expect(
      find.descendant(of: find.byKey(const ValueKey('card-flag')), matching: find.byIcon(Icons.report_outlined)),
      findsOneWidget,
      reason: 'Knopf zeigt die Markierung',
    );

    // Ändern: doch nur merken.
    await tap(tester, 'card-flag');
    expect(find.byKey(const ValueKey('card-flag-remove')), findsOneWidget);
    await tester.tap(find.text('Merken'));
    await tester.pump();
    await tap(tester, 'card-flag-save');
    expect(flags.flagOf('f1')!.kind, CardFlagKind.saved);
    expect(flags.flagOf('f1')!.note, contains('unklar'), reason: 'Notiz bleibt');

    // Liste im Fach.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModuleRepository>.value(value: modules),
          ChangeNotifierProvider<FlashcardRepository>.value(value: flashcards),
          ChangeNotifierProvider<CardFlagRepository>.value(value: flags),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const FlaggedQuestionsScreen(moduleId: 'mf'),
        ),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('flag-0')), findsOneWidget);
    expect(find.text('Gemerkt'), findsOneWidget);
    expect(find.textContaining('Notiz: Option'), findsOneWidget);
    expect(find.byKey(const ValueKey('flag-visual-0')), findsNothing, reason: 'ohne Visuell-lernen-Speicher');
    await tap(tester, 'flags-filter-error');
    expect(find.byKey(const ValueKey('flag-0')), findsNothing);
    await tap(tester, 'flags-filter-all');
    await tap(tester, 'flag-remove-0');
    expect(flags.flagOf('f1'), isNull);
    expect(find.textContaining('Keine markierten Fragen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('Visuell erklären aus einer Frage: Lektion zur Frage gebaut, gespeichert, beim nächsten Mal öffnen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flashcards = FlashcardRepository();
    final flags = CardFlagRepository();
    final card = _choice('v1', 'mv');
    await tester.runAsync(() async {
      await flashcards.saveAll([card]);
      await flags.set(
        CardFlag(cardId: 'v1', moduleId: 'mv', kind: CardFlagKind.saved, front: card.front, createdAt: DateTime(2026)),
      );
    });
    final requests = <String>[];
    VisualFromCardDialog.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        requests.add(r.body);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'lessons': [
                      {
                        'title': 'Wärmeausdehnung',
                        'steps': [
                          {
                            'title': 'Atome schwingen',
                            'text': 'Wärme = Bewegung.',
                            'show': {'scene': latticeScene()},
                          },
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
      }),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FlashcardRepository>.value(value: flashcards),
          ChangeNotifierProvider<CardFlagRepository>.value(value: flags),
          ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
          ChangeNotifierProvider<SettingsRepository>.value(value: _Settings(key: 'sk-test')),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const FlaggedQuestionsScreen(),
        ),
      ),
    );
    await settle(tester);
    await tap(tester, 'flag-visual-0');
    expect(find.byKey(const ValueKey('card-visual-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('card-visual-open')), findsNothing);
    await tester.tap(find.text('Sokratisch'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('card-visual-create')));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await settle(tester);
    expect(requests, hasLength(1));
    final sent = jsonDecode(requests.single) as Map<String, dynamic>;
    final user = '${(sent['messages'] as List)[1]['content']}';
    expect(user, contains('Frage: Warum dehnt sich Stahl'));
    expect(user, contains('Antwortoptionen'));
    expect(user, contains('Erklärung/Lösungsweg: Die Atome schwingen'));
    expect(user, contains('Lernweg: SOKRATISCH'));
    expect(find.byType(VisualLessonScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-diagram')), findsOneWidget);
    final saved = await tester.runAsync(() => VisualLessonRepository().forCard('v1'));
    expect(saved!.title, 'Wärmeausdehnung');
    expect(saved.moduleId, 'mv');
    expect(saved.source, startsWith('Frage: Warum dehnt'));

    // Zurück – beim zweiten Mal gibt es „Öffnen“ ohne neue Anfrage.
    await tester.pageBack();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(VisualLessonScreen), findsNothing);
    await tap(tester, 'flag-visual-0');
    expect(find.textContaining('schon eine visuelle Erklärung („Wärmeausdehnung“)'), findsOneWidget);
    await tap(tester, 'card-visual-open');
    expect(find.byType(VisualLessonScreen), findsOneWidget);
    expect(requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    await settle(tester);
  });
}
