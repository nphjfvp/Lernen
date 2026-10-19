import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/games/error_hunt_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

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

Flashcard _weak(String id) => Flashcard(
  id: id,
  moduleId: 'hm',
  front: 'Frage $id',
  back: 'Antwort $id',
  createdAt: DateTime(2026, 9, 1),
  due: DateTime(2026, 9, 1),
  reps: 2,
  lapses: 1,
  state: 'relearning',
  stability: 2,
  difficulty: 5,
  lastReview: DateTime(2026, 9, 1),
);

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_hunt_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });
  tearDown(() => ErrorHuntScreen.aiFactory = null);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('Fehlerjagd: Aussage bewerten, Begründung sehen, gehakte Karten nachüben', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flashcards = FlashcardRepository();
    final modules = ModuleRepository();
    await tester.runAsync(() async {
      await modules.save(
        Module(
          id: 'hm',
          name: 'Werkstoffe',
          colorValue: 0xFF336699,
          icon: 'science',
          examDate: null,
          createdAt: DateTime(2026),
        ),
      );
      await flashcards.saveAll([_weak('a'), _weak('b'), _weak('c')]);
    });
    String? sent;
    ErrorHuntScreen.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((req) async {
        sent = (jsonDecode(req.body)['messages'] as List).last['content'] as String;
        final content = jsonEncode({
          'statements': [
            {'card': 'a', 'text': 'Aussage über a stimmt.', 'true': true, 'explanation': 'Weil a.'},
            {'card': 'b', 'text': 'Aussage über b ist falsch.', 'true': false, 'explanation': 'Richtig wäre b.'},
          ],
        });
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
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
          ChangeNotifierProvider<ModuleRepository>.value(value: modules),
          ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const ErrorHuntScreen(),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('3 Karten als Grundlage'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('hunt-start')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    expect(sent, contains('Frage a'));
    expect(find.text('Aussage über a stimmt.'), findsOneWidget);

    // Richtig: stimmt.
    await tester.tap(find.byKey(const ValueKey('hunt-true')));
    await tester.pump();
    expect(find.textContaining('Richtig erkannt'), findsOneWidget);
    expect(find.text('Weil a.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hunt-next')));
    await tester.pump();

    // Daneben: die falsche Aussage für wahr gehalten.
    await tester.tap(find.byKey(const ValueKey('hunt-true')));
    await tester.pump();
    expect(find.textContaining('Daneben – die Aussage stimmt nicht.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hunt-next')));
    await tester.pump();

    expect(find.text('1 von 2 richtig erkannt'), findsOneWidget);
    expect(find.text('• Frage b'), findsOneWidget);
    expect(find.text('Diese 1 Karte üben'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
