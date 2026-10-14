import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/visual_chat.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/visual_chat_repository.dart';
import 'package:lernen/repositories/visual_lesson_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/sync_merge.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/visual_chat_screen.dart';
import 'package:lernen/ui/visual/visual_learn_screen.dart';
import 'package:lernen/ui/visual/visual_lesson_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import '../services/visual_diagram_test.dart' show latticeScene;
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

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_visual_chat_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() => VisualChatScreen.aiFactory = null);

  test('Gespräch: speichern/lesen, Darstellung als Ein-Schritt-Lektion, Titel, Obergrenze', () {
    final now = DateTime(2026, 10, 14);
    var chat = VisualChat(id: 'c', moduleId: 'm', createdAt: now);
    expect(chat.displayTitle, 'Neuer Chat');
    chat = chat.withMessage(VisualChatMessage(user: true, text: 'Wie funktioniert ein Hebel?', createdAt: now));
    expect(chat.displayTitle, 'Wie funktioniert ein Hebel?');
    chat = chat.withMessage(
      VisualChatMessage(
        user: false,
        text: 'Kraft mal Hebelarm.',
        visual: {
          'show': {'scene': latticeScene()},
          'transform': [r'$F_1 l_1 = F_2 l_2$'],
        },
        createdAt: now,
      ),
      title: 'Hebelgesetz',
    );
    expect(chat.displayTitle, 'Hebelgesetz');
    final lesson = chat.messages.last.visualLesson!;
    expect(lesson.steps.single.show.scene, isNotNull);
    expect(lesson.steps.single.show.transform.single.latex, 'F_1 l_1 = F_2 l_2');
    expect(chat.messages.first.visualLesson, isNull);
    expect(VisualChat.fromMap(chat.toMap())!.toMap(), chat.toMap());
    expect(VisualChatMessage(user: false, text: 'x', visual: const {'show': {}}, createdAt: now).visualLesson, isNull);
    var long = VisualChat(id: 'l', moduleId: 'm', createdAt: now);
    for (var i = 0; i < VisualChat.maxMessages + 5; i++) {
      long = long.withMessage(VisualChatMessage(user: i.isEven, text: '$i', createdAt: now));
    }
    expect(long.messages.length, VisualChat.maxMessages);
    expect(long.messages.first.text, '5');
  });

  test('Abgleich: das längere Gespräch gewinnt', () {
    Map<String, dynamic> chat(int n) => {
      'id': 'c',
      'moduleId': 'm',
      'messages': [
        for (var i = 0; i < n; i++) {'user': i.isEven, 'text': 'n$i', 'createdAt': '2026-10-14T00:00:00.000'},
      ],
      'createdAt': '2026-10-14T00:00:00.000',
    };
    final modules = [
      {'id': 'm', 'name': 'WK'},
    ];
    final merged = mergeSyncPayloads(
      local: {
        'modules': modules,
        'visualChats': [chat(2)],
      },
      remote: {
        'modules': modules,
        'visualChats': [chat(4)],
      },
      base: const {},
    );
    expect((((merged.payload['visualChats'] as List).single as Map)['messages'] as List).length, 4);
  });

  testWidgets('Visueller Chat: Vorschlag, Rückfrage nur visuell (Rakete), als Lektion, später fortsetzen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final requests = <String>[];
    VisualChatScreen.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        final user = '${((jsonDecode(r.body) as Map)['messages'] as List)[1]['content']}';
        requests.add(user);
        final Object reply;
        if (user.contains('Mach aus diesem Gespräch eine Lektion')) {
          reply = {
            'lessons': [carLessonJson()],
          };
        } else if (user.contains('VISUELL')) {
          reply = {
            'text': 'So schnell wird die Rakete.',
            'variable': 't',
            'domain': [0, 10],
            'functions': [
              {'key': 's', 'label': 'Höhe', 'expr': 't^2', 'unit': 'm'},
            ],
            'show': {'car': 's', 'vehicle': 'rocket'},
          };
        } else {
          reply = {
            'title': 'Hebelgesetz',
            'text': r'Am Hebel gilt $F_1 l_1 = F_2 l_2$.',
            'show': {'scene': latticeScene()},
          };
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': jsonEncode(reply)},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    Future<void> settle([int rounds = 12]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Tippen in echter Zeit (Speichern nach der Antwort).
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
          ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
          ChangeNotifierProvider<VisualChatRepository>(create: (_) => VisualChatRepository()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const VisualLearnScreen(moduleId: 'mc', moduleName: 'Technische Mechanik'),
        ),
      ),
    );
    await settle();
    await tapReal(find.byKey(const ValueKey('visual-chat-open')));
    expect(find.byType(VisualChatScreen), findsOneWidget);
    expect(find.text('Frag einfach – die KI erklärt mit Bildern'), findsOneWidget);

    // Vorschlag antippen: Antwort mit Text und Szene.
    await tapReal(find.byKey(const ValueKey('visual-chat-suggest-0')));
    expect(requests.single, contains('Frage: Wie funktioniert ein Hebel?'));
    expect(requests.single, contains('Fach: Technische Mechanik'));
    expect(requests.single, contains('BEIDES'));
    expect(find.byKey(const ValueKey('visual-chat-visual-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-diagram')), findsOneWidget);
    expect(find.text('Hebelgesetz'), findsOneWidget, reason: 'Titel von der KI');

    // Rückfrage nur visuell – mit Bezug aufs Gespräch.
    await tester.tap(find.text('Visuell'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('visual-chat-input')), 'Und wie schnell steigt eine Rakete?');
    await tapReal(find.byKey(const ValueKey('visual-chat-send')));
    expect(requests.last, contains('Nutzer: Wie funktioniert ein Hebel?'));
    expect(requests.last, contains(r'Du: Am Hebel gilt $F_1 l_1 = F_2 l_2$.'));
    expect(requests.last, contains('VISUELL'));
    expect(find.textContaining('Rakete: Weg'), findsOneWidget);
    final saved = await tester.runAsync(() => VisualChatRepository().forModule('mc'));
    expect(saved!.single.messages, hasLength(4));

    // Als Lektion speichern.
    await tapReal(find.byKey(const ValueKey('visual-chat-lesson')));
    expect(requests.last, contains('Frage: Wie funktioniert ein Hebel?'));
    expect(requests.last, contains('Antwort: So schnell wird die Rakete.'));
    expect(find.byType(VisualLessonScreen), findsOneWidget);
    final lessons = await tester.runAsync(() => VisualLessonRepository().forModule('mc'));
    expect(lessons!.single.source, 'Visueller Chat: Hebelgesetz');

    // Zurück zur Liste: Gespräch fortsetzen.
    await tester.pageBack();
    await settle();
    await tester.pageBack();
    await settle();
    expect(find.byKey(const ValueKey('visual-chat-0')), findsOneWidget);
    expect(find.text('Hebelgesetz'), findsOneWidget);
    await tapReal(find.byKey(const ValueKey('visual-chat-0')));
    expect(find.byKey(const ValueKey('visual-chat-msg-3')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle();
  });
}
