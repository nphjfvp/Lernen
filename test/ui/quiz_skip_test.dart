import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/daily_quiz_screen.dart';
import 'package:lernen/ui/practice/practice_screen.dart';
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

class _Settings extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings();
}

Flashcard _card(String id, String moduleId, {DateTime? due}) => Flashcard(
      id: id,
      moduleId: moduleId,
      front: 'Frage $id',
      back: 'Antwort $id',
      createdAt: DateTime(2026, 9, 1),
      due: due ?? DateTime(2026, 9, 1),
    );

/// Falsch gewertet: eben beantwortet und schon bald wieder fällig (ein richtiges
/// "Gut" auf eine neue Karte läge Tage entfernt).
void expectWrongAnswered(Flashcard card) {
  final now = DateTime.now();
  expect(card.reps, greaterThan(0));
  expect(card.due.isAfter(now.subtract(const Duration(hours: 1))), isTrue);
  expect(card.due.isBefore(now.add(const Duration(days: 1))), isTrue);
}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_quiz_skip_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  Future<Flashcard?> stored(WidgetTester tester, String id) => tester.runAsync<Flashcard?>(() async {
        final db = await DatabaseService.instance.database;
        final raw = await DatabaseService.flashcards.record(id).get(db);
        return raw == null ? null : Flashcard.fromMap(raw);
      });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Offene Datenbank-/Widget-Aufträge der Bildschirme abwarten, damit kein
  /// Timer über das Testende hinaus läuft.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> giveUpAndContinue(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('question-give-up')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('question-gave-up-next')));
    await settle(tester);
  }

  testWidgets('Üben: Überspringen legt die Karte ans Ende, Auflösen wertet falsch, die letzte Karte lässt sich nicht mehr überspringen',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flashcards = FlashcardRepository();
    final cards = [_card('p1', 'pm'), _card('p2', 'pm'), _card('p3', 'pm')];
    await tester.runAsync(() => flashcards.saveAll(cards));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<FlashcardRepository>.value(value: flashcards),
        ChangeNotifierProvider<SettingsRepository>.value(value: _Settings()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: PracticeScreen.cards(title: 'Test', cards: cards),
      ),
    ));
    await tester.pump();

    expect(find.text('Frage p1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('question-skip')));
    await tester.pump();
    expect(find.text('Frage p2'), findsOneWidget);
    expect(find.textContaining('1 / 3'), findsOneWidget);
    // Übersprungen heißt: nichts verbucht.
    expect((await stored(tester, 'p1'))!.reps, 0);

    await giveUpAndContinue(tester); // p2 aufgelöst
    expectWrongAnswered((await stored(tester, 'p2'))!);

    expect(find.text('Frage p3'), findsOneWidget);
    await giveUpAndContinue(tester); // p3 aufgelöst

    // Übrig: die übersprungene p1 – als letzte Karte ohne Überspringen.
    expect(find.text('Frage p1'), findsOneWidget);
    expect(find.byKey(const ValueKey('question-skip')), findsNothing);
    await giveUpAndContinue(tester);
    expect(find.textContaining('3 Karten geübt'), findsOneWidget);
    expectWrongAnswered((await stored(tester, 'p1'))!);
    await drain(tester);
  });

  testWidgets('Daily Quiz: übersprungene Karten kommen nach der Hauptrunde noch einmal dran', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final modules = ModuleRepository();
    final flashcards = FlashcardRepository();
    final module = Module(
      id: 'dm',
      name: 'Daily-Fach',
      colorValue: 0xFF3D5AFE,
      icon: '📘',
      examDate: null,
      createdAt: DateTime(2026, 1, 1),
    );
    await tester.runAsync(() async {
      await modules.save(module);
      await flashcards.saveAll([for (final id in ['d1', 'd2']) _card(id, 'dm', due: DateTime(2026, 1, 1))]);
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ModuleRepository>.value(value: modules),
        ChangeNotifierProvider<FlashcardRepository>.value(value: flashcards),
        ChangeNotifierProvider<LectureUnitRepository>(create: (_) => LectureUnitRepository()),
        ChangeNotifierProvider<SettingsRepository>.value(value: _Settings()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const Scaffold(body: DailyQuizScreen()),
      ),
    ));
    await settle(tester);

    final first = find.textContaining('Frage d').evaluate().isNotEmpty;
    expect(first, isTrue);
    String shownCard() => find.text('Frage d1').evaluate().isNotEmpty ? 'd1' : 'd2';
    final a = shownCard();
    final b = a == 'd1' ? 'd2' : 'd1';
    expect(find.textContaining('1 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('question-skip')));
    await settle(tester);
    expect(shownCard(), b);
    // Nichts verbucht.
    expect((await stored(tester, a))!.reps, 0);
    // Letzte Karte der Hauptrunde, aber a wartet schon: Überspringen wäre möglich.
    expect(find.textContaining('2 / 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('question-skip')), findsOneWidget);

    await giveUpAndContinue(tester); // b aufgelöst
    // Jetzt die übersprungene Karte.
    expect(find.text('Frage $a'), findsOneWidget);
    expect(find.textContaining('Übersprungen · noch 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('question-skip')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('question-give-up')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('question-gave-up-next')));
    await settle(tester);
    // a und b waren falsch: danach die Wiederholungsrunde.
    expect(find.textContaining('Wiederholung'), findsOneWidget);
    expectWrongAnswered((await stored(tester, a))!);
    await drain(tester);
  });
}
