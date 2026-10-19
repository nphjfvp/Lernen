import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/games/games_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// Schon gelernt, aber schwach (Ampel rot).
Flashcard _weak(String id) => Flashcard(
  id: id,
  moduleId: 'bm',
  front: 'Frage $id',
  back: 'Antwort $id',
  createdAt: DateTime(2026, 9, 1),
  due: DateTime(2026, 9, 1),
  reps: 2,
  state: 'review',
  stability: 2,
  difficulty: 5,
  lastReview: DateTime(2026, 9, 1),
);

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_boss_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('Boss-Kampf: falsch kommt wieder, alle richtig = besiegt und gezählt', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flashcards = FlashcardRepository();
    final modules = ModuleRepository();
    final settings = SettingsRepository();
    await tester.runAsync(() async {
      await settings.update(const AppSettings());
      await modules.save(
        Module(
          id: 'bm',
          name: 'Werkstoffe',
          colorValue: 0xFF336699,
          icon: 'science',
          examDate: null,
          createdAt: DateTime(2026),
        ),
      );
      await flashcards.saveAll([_weak('a'), _weak('b'), _weak('c')]);
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FlashcardRepository>.value(value: flashcards),
          ChangeNotifierProvider<ModuleRepository>.value(value: modules),
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const GamesScreen(),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('game-boss')));
    await settle(tester);
    expect(find.text('3 Karten · ${5} Herzen'), findsOneWidget);

    // Nur dieses Fach.
    await tester.tap(find.byKey(const ValueKey('boss-module')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Werkstoffe').last);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('boss-start')));
    await settle(tester);
    expect(find.text('Endgegner Werkstoffe'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);

    final seen = <String>[];
    String currentCard() => ['a', 'b', 'c'].firstWhere((id) => find.text('Frage $id').evaluate().isNotEmpty);

    // Erste Karte auflösen (falsch): Herz weg, Boss unverletzt.
    seen.add(currentCard());
    await tester.tap(find.byKey(const ValueKey('question-give-up')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('question-gave-up-next')));
    await settle(tester);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);

    // Die übrigen und die wiederkehrende richtig ("Gut").
    for (var i = 0; i < 3; i++) {
      seen.add(currentCard());
      await tester.tap(find.text('Zum Umdrehen tippen'));
      await tester.pump();
      await tester.tap(find.text('Gut'));
      await settle(tester);
    }
    expect(seen.last, seen.first, reason: 'die falsche kam wieder');
    expect(find.text('Endgegner Werkstoffe besiegt!'), findsOneWidget);
    expect(find.text('Diese Karten haben gehakt'), findsOneWidget);
    expect(settings.settings.bossesDefeated, 1);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
