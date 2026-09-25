import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/exam/mock_exam_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Flashcard _choice(String id, {required bool firstIsCorrect}) => Flashcard(
      id: id,
      moduleId: 'exam-m1',
      front: 'Frage $id',
      back: '',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      type: QuestionType.singleChoice,
      options: [
        QuizOption(text: 'Option A $id', isCorrect: firstIsCorrect),
        QuizOption(text: 'Option B $id', isCorrect: !firstIsCorrect),
      ],
    );

void main() {
  testWidgets('Probeklausur: Start, zwei Antworten, Note am Ende', (tester) async {
    final dir = Directory.systemTemp.createTempSync('lernen_exam_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);

    final flashcards = FlashcardRepository();
    await tester.runAsync(() => flashcards.saveAll([
          _choice('q1', firstIsCorrect: true),
          _choice('q2', firstIsCorrect: true),
        ]));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: flashcards),
        ChangeNotifierProvider(create: (_) => LectureUnitRepository()),
        ChangeNotifierProvider(create: (_) => SettingsRepository()),
      ],
      child: MaterialApp(
        // Ohne Google Fonts: runAsync ließe deren (im Test unmöglichen)
        // Download sonst als Fehler durchschlagen.
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const MockExamScreen(moduleId: 'exam-m1', moduleName: 'Testfach'),
      ),
    ));

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    expect(find.text('Probeklausur starten'), findsOneWidget);
    expect(find.textContaining('2 verfügbar'), findsOneWidget);

    await tester.tap(find.text('Ohne'));
    await tester.pump();
    await tester.tap(find.text('Probeklausur starten'));
    await tester.pump();

    for (var i = 0; i < 2; i++) {
      // Jeweils Option A wählen – bei beiden Fragen richtig.
      await tester.tap(find.textContaining('Option A'));
      await tester.pump();
      await tester.tap(find.text('Antwort abgeben'));
      await settle();
    }

    expect(find.text('2 von 2 richtig (100 %)'), findsOneWidget);
    expect(find.text('1,0'), findsOneWidget);
  });
}
