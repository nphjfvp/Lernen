import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/visual_chat.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/models/visual_task_type.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/visual_chat_repository.dart';
import 'package:lernen/repositories/visual_lesson_repository.dart';
import 'package:lernen/repositories/visual_task_type_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/visual_chat_screen.dart';
import 'package:lernen/ui/visual/visual_lesson_screen.dart';
import 'package:lernen/ui/visual/visual_task_types_screen.dart';
import 'package:lernen/ui/widgets/math_text.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

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

http.Response _reply(Object body) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': jsonEncode(body)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Flashcard _card(String id, String front, {QuestionType type = QuestionType.freeText}) => Flashcard(
  id: id,
  moduleId: 'mt',
  front: front,
  back: 'Lösung zu $front',
  createdAt: DateTime(2026, 10, 1),
  due: DateTime(2026, 10, 1),
  type: type,
);

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_visual_tasks_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() {
    VisualTaskTypesScreen.aiFactory = null;
    VisualChatScreen.aiFactory = null;
  });

  test('Aufgabentyp und Katalog: lesen, unbekannte Karten weglassen, speichern/lesen', () {
    final t = VisualTaskType.fromMap(
      {
        'name': 'Weg-Zeit-Funktion',
        'beschreibung': 'a(t) zweimal integrieren',
        'cards': ['c1', 'erfunden', 'c2'],
      },
      knownIds: {'c1', 'c2'},
      fallbackId: 'typ-0',
    )!;
    expect(t.id, 'typ-0');
    expect(t.title, 'Weg-Zeit-Funktion');
    expect(t.description, 'a(t) zweimal integrieren');
    expect(t.cardIds, ['c1', 'c2']);
    expect(VisualTaskType.fromMap({'title': ''}), isNull);
    expect(VisualTaskType.fromMap('x'), isNull);
    final catalog = VisualTaskCatalog(moduleId: 'm', types: [t], cardCount: 7, updatedAt: DateTime(2026, 11, 1));
    final back = VisualTaskCatalog.fromMap(jsonDecode(jsonEncode(catalog.toMap())))!;
    expect(back.toMap(), catalog.toMap());
    expect(VisualTaskCatalog.fromMap({'types': []}), isNull);
  });

  test('Aufgabe-Stellen: Wunsch enthält Typ, Stufe, Beispiele und Aufbau', () {
    final topic = AiService.visualTaskTopic(
      type: const VisualTaskType(id: 't', title: 'Weg-Zeit-Funktion', description: 'Aus a(t) über v(t) zu s(t)'),
      level: VisualTaskLevel.hard,
      examples: const [(front: 'a(t) = 2t, v(0) = 1. Bestimme s(t).', back: 's(t) = t^3/3 + t')],
    );
    expect(topic, contains('AUFGABE STELLEN UND VISUELL LÖSEN'));
    expect(topic, contains('Aufgabentyp: Weg-Zeit-Funktion'));
    expect(topic, contains('Worum es geht: Aus a(t) über v(t) zu s(t)'));
    expect(topic, contains('Schwierigkeit: Schwer – ${VisualTaskLevel.hard.meaning}'));
    expect(topic, contains('1. a(t) = 2t, v(0) = 1. Bestimme s(t).'));
    expect(topic, contains('Lösung: s(t) = t^3/3 + t'));
    expect(topic, contains('„Aufgabe:“'));
  });

  test('Typ-Erkennung: Einträge gehen mit ID an die KI, erfundene IDs fallen weg', () async {
    String? sent;
    final ai = AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((r) async {
        sent = '${((jsonDecode(r.body) as Map)['messages'] as List)[1]['content']}';
        return _reply({
          'types': [
            {
              'title': 'Weg-Zeit-Funktion',
              'description': 'integrieren',
              'cardIds': ['c1', 'x9'],
            },
            {'title': ''},
          ],
        });
      }),
    );
    final types = await ai.findTaskTypes([
      (id: 'c1', type: 'Freitext', text: 'a(t) = 2t gegeben'),
      (id: 'c2', type: 'Rechenweg', text: 'Packungsdichte'),
    ], subject: 'Physik');
    expect(sent, contains('Fach: Physik'));
    expect(sent, contains('ID c1 [Freitext]: a(t) = 2t gegeben'));
    expect(types.single.cardIds, ['c1']);
    await expectLater(ai.findTaskTypes(const []), throwsA(isA<AiServiceException>()));
  });

  test('Typ-Erkennung: echte Aufgaben zuerst, höchstens maxItems', () {
    final cards = [
      _card('k', 'Was ist Ferrit?', type: QuestionType.flashcard),
      _card('r', 'Berechne s(t)'),
      for (var i = 0; i < VisualTaskTypesScreen.maxItems + 5; i++)
        _card('f$i', 'Karte $i', type: QuestionType.singleChoice),
    ];
    final items = VisualTaskTypesScreen.itemsFor(cards);
    expect(items, hasLength(VisualTaskTypesScreen.maxItems));
    expect(items.first.id, 'r');
  });

  test('Lektion als Gesprächsgrundlage und Kontext im Chat speichern/lesen', () {
    final lesson = VisualLesson.fromMap(carLessonJson(), id: 'l', moduleId: 'm', createdAt: DateTime(2026, 11, 1))!;
    final text = lesson.chatContext(focus: lesson.steps.first.title);
    expect(text, startsWith(lesson.intro));
    expect(text, contains('Lektion „${lesson.title}“ – Lösungsweg:'));
    expect(text, contains('1. ${lesson.steps.first.title}: '));
    expect(text, endsWith('Der Nutzer ist gerade bei: ${lesson.steps.first.title}'));
    final chat = VisualChat(id: 'c', moduleId: 'm', createdAt: DateTime(2026, 11, 1), context: text);
    expect(VisualChat.fromMap(chat.toMap())!.context, text);
    expect(
      VisualChat(id: 'd', moduleId: 'm', createdAt: DateTime(2026, 11, 1)).toMap().containsKey('context'),
      isFalse,
    );
    final grown = chat.withMessage(VisualChatMessage(user: true, text: 'x', createdAt: DateTime(2026, 11, 1)));
    expect(grown.context, text);
  });

  testWidgets('Farbig markierte Formel wird gesetzt', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const Scaffold(body: MathText(r'$\textcolor{green}{s(t)} = \int \textcolor{red}{t}\,dt$')),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(MathText), findsOneWidget);
  });

  testWidgets('Aufgaben visuell lösen: Typen erkennen, Schwer wählen, Lektion, im Gespräch vertiefen', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final requests = <({String system, String user})>[];
    final client = MockClient((r) async {
      final messages = (jsonDecode(r.body) as Map)['messages'] as List;
      final system = '${messages[0]['content']}';
      final user = '${messages[1]['content']}';
      requests.add((system: system, user: user));
      if (system.contains('AUFGABENTYPEN')) {
        return _reply({
          'types': [
            {
              'title': 'Weg-Zeit-Funktion aus der Beschleunigung',
              'description': 'a(t) → v(t) → s(t)',
              'cardIds': ['c1', 'c2'],
            },
            {
              'title': 'Packungsdichte',
              'cardIds': ['c3'],
            },
          ],
        });
      }
      if (user.contains('AUFGABE STELLEN')) {
        return _reply({
          'lessons': [carLessonJson()],
        });
      }
      return _reply({'title': 'Farbig', 'text': r'Der Weg $\textcolor{green}{s}$ wächst mit der Zeit.'});
    });
    VisualTaskTypesScreen.aiFactory = (k, m) => AiService(apiKey: k, model: m, client: client);
    VisualChatScreen.aiFactory = (k, m) => AiService(apiKey: k, model: m, client: client);
    final cards = FlashcardRepository();
    await tester.runAsync(
      () => cards.saveAll([
        _card('c1', 'Ein Zug beschleunigt mit a(t) = 0,5 t. Bestimme s(t).'),
        _card('c2', 'Ein Auto bremst mit a = -2. Wann steht es?'),
        _card('c3', 'Packungsdichte von kfz'),
      ]),
    );

    Future<void> settle([int rounds = 12]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> tapReal(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(f);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settle();
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
          ChangeNotifierProvider<FlashcardRepository>.value(value: cards),
          ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
          ChangeNotifierProvider<VisualChatRepository>(create: (_) => VisualChatRepository()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const VisualTaskTypesScreen(moduleId: 'mt', moduleName: 'Physik'),
        ),
      ),
    );
    await settle();
    expect(find.textContaining('3 Aufgaben und Fragen im Fach'), findsOneWidget);

    await tapReal(find.byKey(const ValueKey('task-types-find')));
    expect(requests.single.user, contains('Fach: Physik'));
    expect(requests.single.user, contains('ID c1 [Freitext]'));
    expect(find.text('Weg-Zeit-Funktion aus der Beschleunigung'), findsOneWidget);
    expect(find.textContaining('2 Beispiele im Fach'), findsOneWidget);
    final stored = await tester.runAsync(() => VisualTaskTypeRepository().load('mt'));
    expect(stored!.types, hasLength(2));
    expect(stored.cardCount, 3);

    // Typ antippen → Stufe Schwer → Aufgabe stellen.
    await tapReal(find.byKey(const ValueKey('task-type-0')));
    expect(find.byKey(const ValueKey('task-level')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('task-level-hard')));
    await tester.pump();
    await tapReal(find.byKey(const ValueKey('task-start')));
    await settle();
    final ask = requests.last.user;
    expect(ask, contains('Aufgabentyp: Weg-Zeit-Funktion aus der Beschleunigung'));
    expect(ask, contains('Schwierigkeit: Schwer'));
    expect(ask, contains('Ein Zug beschleunigt'));
    expect(ask, isNot(contains('Packungsdichte von kfz')));
    expect(requests.last.system, contains('FARBIG MARKIEREN'));
    expect(find.byType(VisualLessonScreen), findsOneWidget);
    final lessons = await tester.runAsync(() => VisualLessonRepository().forModule('mt'));
    expect(lessons!.single.source, 'Aufgabentyp: Weg-Zeit-Funktion aus der Beschleunigung · Schwer');

    // Im Gespräch vertiefen: Chat kennt Aufgabe und Lösungsweg.
    await tapReal(find.byKey(const ValueKey('visual-deepen')));
    expect(find.byType(VisualChatScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-chat-context')), findsOneWidget);
    await tapReal(find.byKey(const ValueKey('visual-chat-task-suggest-1')));
    final input = tester.widget<TextField>(find.byKey(const ValueKey('visual-chat-input')));
    expect(input.controller!.text, contains('grün'));
    await tapReal(find.byKey(const ValueKey('visual-chat-send')));
    expect(requests.last.user, contains('Worauf sich das Gespräch bezieht'));
    expect(requests.last.user, contains('Lektion „Vom Weg zur Geschwindigkeit“ – Lösungsweg:'));
    expect(requests.last.user, contains('Der Nutzer ist gerade bei:'));
    expect(requests.last.user, contains('alles mit dem Weg grün'));
    await tester.pumpWidget(const SizedBox());
    await settle();
  });

  testWidgets('Ohne Key: Hinweis statt KI-Aufruf', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>(create: (_) => SettingsRepository()),
          ChangeNotifierProvider<FlashcardRepository>(create: (_) => FlashcardRepository()),
          ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const VisualTaskTypesScreen(moduleId: 'leer'),
        ),
      ),
    );
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('task-types-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('task-type-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('task-custom-field')), 'Weg-Zeit-Funktion');
    await tester.tap(find.byKey(const ValueKey('task-custom-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Weg-Zeit-Funktion'), findsOneWidget, reason: 'Auswahl für den eigenen Typ');
    await tester.tap(find.byKey(const ValueKey('task-start')));
    await tester.pumpAndSettle();
    expect(find.textContaining('OpenRouter-Key'), findsOneWidget);
  });
}
