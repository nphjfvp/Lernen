import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/flashcards/flashcard_list_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Flashcard _card(
  String id,
  String moduleId,
  String front, {
  QuestionType type = QuestionType.singleChoice,
  String? stageGroup,
  String? conceptId,
  int masteryBox = 0,
}) =>
    Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: front,
      back: 'Antwort',
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      type: type,
      stageGroup: stageGroup,
      masteryBox: masteryBox,
      options: type == QuestionType.singleChoice
          ? const [QuizOption(text: 'A', isCorrect: true), QuizOption(text: 'B', isCorrect: false)]
          : null,
      correctText: type == QuestionType.freeText ? 'U = R · I' : null,
      blanks: type == QuestionType.fillBlank ? const ['R'] : null,
    );

Future<void> _pumpList(WidgetTester tester, String moduleId, List<Flashcard> cards) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FlashcardRepository();
  await tester.runAsync(() async {
    await repo.saveAll(cards);
    await repo.loadForModule(moduleId);
  });
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: repo,
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: FlashcardListScreen(moduleId: moduleId, moduleName: 'Technik'),
    ),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_stage_folder_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  testWidgets('Ordner: zugeklappt Name, schwerste Frage und Stufen, aufgeklappt Leicht/Mittel/Schwer', (tester) async {
    const m = 'folder-module';
    await _pumpList(tester, m, [
      _card('l', m, 'Welche Formel gilt? (Auswahl)', stageGroup: 'Ohmsches Gesetz#1', masteryBox: Flashcard.masteryBoxCap),
      _card('mi', m, 'U = ___ · I', type: QuestionType.fillBlank, stageGroup: 'Ohmsches Gesetz#1'),
      _card('s', m, 'Leite den Strom aus U und R her.', type: QuestionType.freeText, stageGroup: 'Ohmsches Gesetz#1'),
      _card('solo', m, 'Was ist Leistung?'),
    ]);

    // Zugeklappt: Ordnername + schwerste Frage, einzelne Karten des Ordners
    // noch nicht als eigene Einträge.
    expect(find.text('Ohmsches Gesetz'), findsOneWidget);
    expect(find.text('Leite den Strom aus U und R her.'), findsOneWidget);
    expect(find.text('U = ___ · I'), findsNothing);
    expect(find.text('Was ist Leistung?'), findsOneWidget);
    expect(find.text('3 Fragen'), findsOneWidget);
    // Kein Hinweis: der Ordner stammt nicht nur aus dem Konzept.
    expect(find.byKey(const ValueKey('concept-hint-sort')), findsNothing);

    await tester.tap(find.text('Ohmsches Gesetz'));
    await tester.pumpAndSettle();

    expect(find.text('U = ___ · I'), findsOneWidget);
    expect(find.text('Leicht · geschafft – ruht'), findsOneWidget);
    expect(find.text('Mittel · gerade dran'), findsOneWidget);
    expect(find.text('Schwer · wartet'), findsOneWidget);
  });

  testWidgets('Auswahlmodus: Häkchen am Ordner wählt alle seine Fragen', (tester) async {
    const m = 'folder-select-module';
    await _pumpList(tester, m, [
      _card('a', m, 'Leicht?', stageGroup: 'G#1'),
      _card('b', m, 'Schwer?', type: QuestionType.freeText, stageGroup: 'G#1'),
      _card('c', m, 'Allein?'),
    ]);

    await tester.tap(find.byKey(const ValueKey('select-mode')));
    await tester.pumpAndSettle();
    final folderBox = find.descendant(of: find.byKey(ValueKey('folder-$m\u0000g#1')), matching: find.byType(Checkbox));
    await tester.tap(folderBox);
    await tester.pumpAndSettle();
    expect(find.text('2 ausgewählt'), findsOneWidget);
  });

  testWidgets('Ordner nur nach Konzept: Hinweis zum Sortieren per KI', (tester) async {
    const m = 'folder-concept-module';
    await _pumpList(tester, m, [
      _card('a', m, 'Leicht?', conceptId: 'k1'),
      _card('b', m, 'Schwer?', type: QuestionType.freeText, conceptId: 'k1'),
    ]);
    expect(find.byKey(const ValueKey('concept-hint-sort')), findsOneWidget);
    expect(find.textContaining('nach Konzept'), findsWidgets);
  });
}
