import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/flashcards/task_folder_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _OneModule extends ModuleRepository {
  _OneModule(this.module);
  final Module module;

  @override
  Module? byId(String id) => module;
}

Flashcard _task(String id, String moduleId, String front, {String back = 'Erklärung', int? page}) => Flashcard(
      id: id,
      moduleId: moduleId,
      front: front,
      back: back,
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      type: QuestionType.learn,
      sourcePage: page,
    );

Module _module(String id, DateTime? exam) => Module(
      id: id,
      name: 'Produktion',
      colorValue: 0xFF3D5AFE,
      icon: '🏭',
      examDate: exam,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_task_folder_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  Future<void> pump(WidgetTester tester, String moduleId, DateTime? exam, List<Flashcard> cards) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FlashcardRepository();
    await tester.runAsync(() async {
      await repo.saveAll(cards);
      await repo.loadForModule(moduleId);
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: repo),
        ChangeNotifierProvider<ModuleRepository>.value(value: _OneModule(_module(moduleId, exam))),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: TaskFolderScreen(moduleId: moduleId, moduleName: 'Produktion'),
      ),
    ));
    await tester.pump();
  }

  testWidgets('20 Tage vor der Klausur: roter Hinweis mit Tagen und Aufgabenzahl', (tester) async {
    final exam = DateTime.now().add(const Duration(days: 12));
    await pump(tester, 'tf-red', exam, [
      _task('a', 'tf-red', 'Erstellen Sie ein Gantt-Diagramm.', page: 2),
      _task('b', 'tf-red', 'Zeichnen Sie den Netzplan.', page: 3),
    ]);
    expect(find.byKey(const ValueKey('task-folder-warning')), findsOneWidget);
    expect(find.textContaining('Klausur in 12 Tagen'), findsOneWidget);
    expect(find.textContaining('Diese 2 Aufgaben lassen sich in der App nicht abfragen'), findsOneWidget);
  });

  testWidgets('Klausur noch weit weg: neutraler Hinweis, Aufgaben trotzdem einsehbar', (tester) async {
    final exam = DateTime.now().add(const Duration(days: 90));
    await pump(tester, 'tf-far', exam, [
      _task('a', 'tf-far', 'Erstellen Sie ein Gantt-Diagramm.', back: 'Zuerst die Dauern eintragen.', page: 2),
    ]);
    expect(find.byKey(const ValueKey('task-folder-warning')), findsNothing);
    expect(find.textContaining('20 Tage vor der Klausur wird dieser Ordner rot markiert'), findsOneWidget);

    expect(find.text('Zuerst die Dauern eintragen.'), findsNothing);
    await tester.tap(find.text('Erstellen Sie ein Gantt-Diagramm.'));
    await tester.pumpAndSettle();
    expect(find.text('Zuerst die Dauern eintragen.'), findsOneWidget);
    expect(find.text('Aufgabe'), findsOneWidget);
    expect(find.text('Erklärung / Lösungsweg'), findsOneWidget);
  });

  testWidgets('ohne Klausurdatum: Hinweis, ein Datum einzutragen; ohne Aufgaben: Leerzustand', (tester) async {
    await pump(tester, 'tf-none', null, const []);
    expect(find.textContaining('Klausurdatum ein'), findsOneWidget);
    expect(find.textContaining('Noch keine Aufgaben'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-folder-warning')), findsNothing);
  });

  testWidgets('andere Fragetypen und andere Fächer stehen nicht im Ordner', (tester) async {
    await pump(tester, 'tf-mix', null, [
      _task('a', 'tf-mix', 'Nur diese Aufgabe'),
      Flashcard(
        id: 'q',
        moduleId: 'tf-mix',
        front: 'Eine Karteikarte',
        back: 'Antwort',
        createdAt: DateTime(2026, 9, 1),
        due: DateTime(2026, 9, 1),
      ),
      _task('x', 'anderes-fach', 'Aufgabe eines anderen Fachs'),
    ]);
    expect(find.text('Nur diese Aufgabe'), findsOneWidget);
    expect(find.text('Eine Karteikarte'), findsNothing);
    expect(find.text('Aufgabe eines anderen Fachs'), findsNothing);
  });
}
