import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/practice/placement_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Flashcard _stage(String id, int level) => Flashcard(
      id: id,
      moduleId: 'place-m1',
      front: 'Frage $id',
      back: '',
      createdAt: DateTime(2026, 1, 1 + level),
      due: DateTime(2026, 1, 1),
      type: QuestionType.singleChoice,
      stageLevel: level,
      stageGroup: 'Ohm',
      options: [
        QuizOption(text: 'Richtig $id', isCorrect: true),
        QuizOption(text: 'Falsch $id', isCorrect: false),
      ],
    );

void main() {
  testWidgets('Schwere Stufe sicher gewusst: leichtere Stufen ruhen, Ergebnis wird gemeldet', (tester) async {
    final dir = Directory.systemTemp.createTempSync('lernen_placement_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
    final flashcards = FlashcardRepository();
    await tester.runAsync(() => flashcards.saveAll([_stage('l', 0), _stage('m', 1), _stage('s', 2)]));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: flashcards),
        ChangeNotifierProvider(create: (_) => SettingsRepository()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const PlacementScreen(moduleId: 'place-m1', moduleName: 'Physik'),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    // Zuerst die schwerste Stufe.
    expect(find.text('Frage s'), findsOneWidget);
    expect(find.textContaining('Stufe Schwer'), findsOneWidget);
    await tester.tap(find.textContaining('Richtig s'));
    await tester.pump();
    await tester.ensureVisible(find.text('Prüfen'));
    await tester.tap(find.text('Prüfen'));
    await tester.pump();
    await tester.ensureVisible(find.text('Weiter'));
    await tester.tap(find.text('Weiter'));
    await settle();
    await settle();

    expect(find.textContaining('In 1 Ordnern startest du direkt weiter oben'), findsOneWidget);
    final saved = await tester.runAsync(() => flashcards.loadModuleCards('place-m1'));
    final byId = {for (final c in saved!) c.id: c};
    expect(byId['l']!.placedOut, isTrue);
    expect(byId['m']!.placedOut, isTrue);
    expect(byId['s']!.placedOut, isFalse);
    expect(byId['s']!.reps, 1, reason: 'die richtige Antwort wird verbucht');
  });
}
