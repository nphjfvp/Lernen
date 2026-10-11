import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/daily_session_state.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/daily_session_repository.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/daily_quiz_screen.dart';
import 'package:lernen/ui/daily/missed_lessons_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

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

Module _module(String id, String name) =>
    Module(id: id, name: name, colorValue: 0xFF3D5AFE, icon: '📘', examDate: null, createdAt: DateTime(2026, 1, 1));

/// Auswahlfrage mit schon gespeicherter Lerneinheit (keine KI nötig).
Flashcard _choice(String id, String moduleId, {DateTime? due}) => Flashcard(
  id: id,
  moduleId: moduleId,
  front: 'Frage $id',
  back: '',
  createdAt: DateTime(2026, 9, 1),
  due: due ?? DateTime(2026, 9, 1),
  type: QuestionType.singleChoice,
  options: [
    QuizOption(text: 'richtig $id', isCorrect: true),
    QuizOption(text: 'falsch $id', isCorrect: false),
  ],
  miniLesson: 'Worum es geht: Thema $id\nKern: Erklärung zu $id\nMerke: Merksatz $id',
);

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_missed_lessons_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester);
  }

  /// Auswahlfrage beantworten: Option antippen, prüfen, weiter.
  Future<void> answer(WidgetTester tester, String optionText) async {
    await tester.ensureVisible(find.text(optionText));
    await tester.tap(find.text(optionText));
    await tester.pump();
    await tester.ensureVisible(find.text('Prüfen').first);
    await tester.tap(find.text('Prüfen').first);
    await settle(tester);
    await tester.ensureVisible(find.text('Weiter').last);
    await tester.tap(find.text('Weiter').last);
    await settle(tester);
  }

  String progress(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('lessons-progress'))).data ?? '';

  test('Tagesstand: falsch beantwortete Karten und erledigte Lerneinheiten bleiben erhalten', () {
    final state = DailySessionState.empty(DateTime(2026, 10, 11)).copyWith(missedIds: ['a', 'b'], lessonsDone: true);
    final back = DailySessionState.fromMap(state.toMap());
    expect(back.missedIds, ['a', 'b']);
    expect(back.lessonsDone, isTrue);
    final other = DailySessionState.empty(DateTime(2026, 10, 11)).copyWith(missedIds: ['b', 'c']);
    final merged = DailySessionState.empty(DateTime(2026, 10, 11)).copyWith(missedIds: ['a', 'b']).mergedWith(other);
    expect(merged.missedIds, ['a', 'b', 'c']);
    expect(merged.lessonsDone, isFalse);
    expect(DailySessionState.fromMap(DailySessionState.empty(DateTime(2026, 10, 11)).toMap()).missedIds, isEmpty);
  });

  testWidgets('Lerneinheiten nach Fächern: lesen, überspringen, nochmal versuchen, falsche erneut', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final modules = ModuleRepository();
    await tester.runAsync(() async {
      await modules.save(_module('mw', 'Werkstoffkunde'));
      await modules.save(_module('ma', 'Analysis'));
    });
    // Durcheinander beantwortet – angezeigt nach Fach (alphabetisch) gruppiert.
    final cards = [_choice('w1', 'mw'), _choice('a1', 'ma'), _choice('w2', 'mw'), _choice('a2', 'ma')];
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModuleRepository>.value(value: modules),
          ChangeNotifierProvider<SettingsRepository>.value(value: _Settings()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: MissedLessonsScreen(cards: cards),
        ),
      ),
    );
    await settle(tester);

    // Erst Analysis (a1, a2), dann Werkstoffkunde.
    expect(progress(tester), 'Analysis · Lerneinheit 1 von 2');
    expect(find.text('Frage a1'), findsOneWidget);
    expect(find.text('Erklärung zu a1'), findsOneWidget);
    expect(find.text('richtig a1'), findsOneWidget, reason: 'richtige Antwort steht dabei');
    await tap(tester, 'lessons-next');
    expect(find.text('Frage a2'), findsOneWidget);
    await tap(tester, 'lessons-skip');

    // Nach dem Fach: nochmal versuchen.
    expect(find.textContaining('2 Fragen aus Analysis'), findsOneWidget);
    await tap(tester, 'lessons-retry');
    expect(progress(tester), 'Analysis · Nochmal versuchen · 1 von 2');
    await answer(tester, 'richtig a1');
    await answer(tester, 'falsch a2');
    expect(find.text('1 von 2 richtig.'), findsOneWidget);
    // Die falsche nochmal.
    await tap(tester, 'lessons-retry-wrong');
    expect(progress(tester), 'Analysis · Nochmal versuchen · 1 von 1');
    await answer(tester, 'richtig a2');
    expect(find.text('Alle 1 richtig!'), findsOneWidget);
    expect(find.text('Weiter mit Werkstoffkunde'), findsOneWidget);
    await tap(tester, 'lessons-next-module');

    // Zweites Fach: ganzes Fach überspringen, nicht nochmal versuchen.
    expect(progress(tester), 'Werkstoffkunde · Lerneinheit 1 von 2');
    await tap(tester, 'lessons-skip-module');
    expect(find.text('Fertig'), findsOneWidget);
    await tap(tester, 'lessons-next-module');
    expect(find.byKey(const ValueKey('lessons-summary')), findsOneWidget);
    expect(find.textContaining('1 gelesen'), findsOneWidget);
    expect(find.textContaining('3 übersprungen'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('Daily Quiz: nach dem Quiz Lerneinheiten zu den falschen anbieten, danach für heute erledigt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final modules = ModuleRepository();
    final flashcards = FlashcardRepository();
    await tester.runAsync(() async {
      await modules.save(_module('dm', 'Daily-Fach'));
      await flashcards.saveAll([_choice('d1', 'dm', due: DateTime(2026, 1, 1))]);
    });

    Widget app() => MultiProvider(
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
    );

    await tester.pumpWidget(app());
    await settle(tester);
    // Falsch beantworten, in der Wiederholung richtig.
    await answer(tester, 'falsch d1');
    expect(find.textContaining('Wiederholung'), findsOneWidget);
    await answer(tester, 'richtig d1');
    expect(find.textContaining('Für heute geschafft'), findsOneWidget);
    expect(find.byKey(const ValueKey('daily-lessons-offer')), findsOneWidget);
    expect(find.textContaining('1 Frage war heute falsch'), findsOneWidget);

    // Lerneinheiten öffnen, beenden → Angebot weg.
    await tap(tester, 'daily-lessons');
    expect(find.byType(MissedLessonsScreen), findsOneWidget);
    expect(find.text('Erklärung zu d1'), findsOneWidget);
    await tap(tester, 'lessons-end');
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.byType(MissedLessonsScreen), findsNothing);
    expect(find.byKey(const ValueKey('daily-lessons-offer')), findsNothing);
    final saved = await tester.runAsync(() => DailySessionRepository().load(DateTime.now()));
    expect(saved!.missedIds, ['d1']);
    expect(saved.lessonsDone, isTrue);
    await drain(tester);
  });
}
