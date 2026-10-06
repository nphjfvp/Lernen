import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/gantt_task.dart';
import 'package:lernen/models/interactive_task.dart';
import 'package:lernen/models/step_task.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/tasks/paper_check_screen.dart';
import 'package:lernen/ui/tasks/task_import_screen.dart';
import 'package:provider/provider.dart';

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

class _RecordingCards extends FlashcardRepository {
  final saved = <Flashcard>[];
  final deleted = <String>[];

  @override
  Future<void> saveAll(List<Flashcard> cards) async => saved.addAll(cards);

  @override
  Future<void> delete(String id, String moduleId) async => deleted.add(id);
}

http.Response _chat(Object json) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': json is String ? json : jsonEncode(json)},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Ein gültiges 1×1-PNG.
final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Was die KI für "y' = 2x, y(0) = 1" liefert.
Map<String, dynamic> _stepsDraft() => {
      'kind': 'steps',
      'front': r"Löse $y' = 2x$ mit $y(0) = 1$.",
      'back': r'Integrieren: $y = x^2 + C$, mit $y(0) = 1$ folgt $C = 1$.',
      'taskData': {
        'steps': [
          {
            'title': 'Integrieren',
            'prompt': 'Integriere beide Seiten.',
            'fields': [
              {'label': 'y(x) =', 'answer': 'x^2 + C', 'variables': ['x'], 'constants': ['C']},
            ],
            'hints': ['Welche Funktion hat die Ableitung 2x?'],
          },
          {
            'title': 'Ergebnis',
            'prompt': 'Setze den Anfangswert ein.',
            'fields': [
              {'label': 'y(x) =', 'answer': 'x^2 + 1', 'variables': ['x']},
            ],
          },
        ],
        'probe': {
          'kind': 'ode',
          'equation': '2*x',
          'conditions': [
            {'x': 0, 'value': 1},
          ],
        },
      },
    };

Map<String, dynamic> _ganttDraft() => {
      'kind': 'gantt',
      'front': 'Terminiere die Baugruppe vorwärts ab Tag 1.',
      'taskData': {
        'start': 1,
        'due': 10,
        'direction': 'forward',
        'counting': 'inclusive',
        'items': [
          {
            'id': 'z',
            'name': 'Zahnrad',
            'uncertain': true,
            'operations': [
              {'name': 'Drehen', 'duration': 3},
            ],
          },
          {
            'id': 'b',
            'name': 'Baugruppe',
            'needs': ['z'],
            'operations': [
              {'name': 'Montage', 'duration': 2},
            ],
          },
        ],
        'questions': [
          {'item': 'b', 'ask': 'end'},
        ],
      },
    };

StepTask _paperTask() => StepTask.fromMap(_stepsDraft()['taskData'])!;

Flashcard _stepsCard() => Flashcard(
      id: 's1',
      moduleId: 'm1',
      front: r"Löse $y' = 2x$ mit $y(0) = 1$.",
      back: r'$y = x^2 + 1$',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      type: QuestionType.steps,
      taskData: _paperTask().toMap(),
    );

void main() {
  tearDown(() {
    TaskImportScreen.aiFactory = null;
    TaskImportScreen.pickImagesHook = null;
    PaperCheckScreen.aiFactory = null;
    PaperCheckScreen.pickImagesHook = null;
  });

  Future<_RecordingCards> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cards = _RecordingCards();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
        ChangeNotifierProvider<FlashcardRepository>.value(value: cards),
      ],
      child: MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: home),
    ));
    await tester.pump();
    return cards;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester);
  }

  group('KI-Antwort lesen', () {
    test('Rechenweg: Daten unter taskData, Art aus "kind"', () {
      final draft = AiService.parseInteractiveTask(_stepsDraft());
      expect(draft.kind, InteractiveKind.steps);
      expect(draft.isUsable, isTrue);
      expect(draft.steps!.steps, hasLength(2));
      expect(draft.taskData!['kind'], 'steps');
    });

    test('Terminierung: flach im Objekt, Art aus der Struktur', () {
      final flat = {'front': 'Plane', ...(_ganttDraft()['taskData'] as Map<String, dynamic>)};
      final draft = AiService.parseInteractiveTask(flat);
      expect(draft.kind, InteractiveKind.gantt);
      expect(draft.gantt!.items, hasLength(2));
      expect(draft.gantt!.hasUncertain, isTrue);
    });

    test('nicht geeignet: Begründung statt Aufgabe', () {
      final draft = AiService.parseInteractiveTask({'kind': 'none', 'reason': 'Hier soll gezeichnet werden.'});
      expect(draft.kind, isNull);
      expect(draft.isUsable, isFalse);
      expect(draft.reason, 'Hier soll gezeichnet werden.');
    });

    test('Fragen-Import: Typ "Rechenweg"/"Terminierung" mit Aufgabendaten bleibt erhalten', () {
      final steps = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'Rechenweg',
        'front': 'Löse',
        'back': 'y = x^2 + 1',
        'taskData': _stepsDraft()['taskData'],
      });
      expect(QuestionParsing.parseType(steps!['type'] as String?), QuestionType.steps);
      expect(StepTask.fromMap(parseTaskData(steps['taskData']))!.steps, hasLength(2));

      final gantt = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'Vorwärtsterminierung',
        'front': 'Plane',
        'back': '',
        'ganttTask': _ganttDraft()['taskData'],
      });
      expect(QuestionParsing.parseType(gantt!['type'] as String?), QuestionType.gantt);
      expect(GanttTask.fromMap(parseTaskData(gantt['taskData']))!.items, hasLength(2));
    });
  });

  testWidgets('Rechenweg übernehmen: KI-Entwurf, App rechnet nach, bearbeiten und speichern', (tester) async {
    final prompts = <String>[];
    TaskImportScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            prompts.add(((jsonDecode(r.body)['messages'] as List).last['content']) as String);
            return _chat(_stepsDraft());
          }),
        );
    final cards = await pump(tester, const TaskImportScreen(moduleId: 'm1', moduleName: 'Mathe 2'));
    await tester.enterText(find.byKey(const ValueKey('task-import-text')), "Löse y' = 2x mit y(0) = 1.");
    await tester.enterText(find.byKey(const ValueKey('task-import-solution')), 'y = x^2 + 1');
    await tap(tester, 'task-import-build');

    expect(prompts.single, contains("Löse y' = 2x"));
    expect(prompts.single, contains('Vorhandene Lösung'));
    expect(find.byKey(const ValueKey('task-import-draft')), findsOneWidget);
    // Die App hat die Musterlösung selbst geprüft (Probe der DGL).
    expect(find.text('Musterlösung von der App nachgerechnet'), findsOneWidget);

    // Eine falsche erwartete Antwort fällt sofort auf.
    await tester.tap(find.byKey(const ValueKey('step-edit-1')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('step-edit-answer-1-0')), 'x^2 + 2');
    await settle(tester);
    expect(find.text('Bitte prüfen – die App hat Unstimmigkeiten gefunden'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('step-edit-answer-1-0')), 'x^2 + 1');
    await settle(tester);
    expect(find.text('Musterlösung von der App nachgerechnet'), findsOneWidget);

    await tap(tester, 'task-import-save');
    final card = cards.saved.single;
    expect(card.type, QuestionType.steps);
    expect(card.moduleId, 'm1');
    expect(card.priorityIntroduction, isTrue);
    expect(card.front, contains("y' = 2x"));
    expect(card.back, contains('C = 1'));
    expect(StepTask.fromMap(card.taskData)!.finalField!.answer, 'x^2 + 1');
    expect(cards.deleted, isEmpty);
  });

  testWidgets('Terminierung übernehmen: unsichere Werte werden vor dem Speichern nachgefragt', (tester) async {
    String? model;
    TaskImportScreen.aiFactory = (key, m) => AiService(
          apiKey: key,
          model: m,
          client: MockClient((r) async {
            model = jsonDecode(r.body)['model'] as String;
            return _chat(_ganttDraft());
          }),
        );
    TaskImportScreen.pickImagesHook = () async => [(name: 'blatt.png', bytes: _tinyPng)];
    final replaced = Flashcard(
      id: 'learn1',
      moduleId: 'm1',
      front: 'Terminiere die Baugruppe.',
      back: 'Erklärung',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      type: QuestionType.learn,
      sourceMaterialId: 'blatt',
      sourcePage: 3,
    );
    final cards = await pump(
      tester,
      TaskImportScreen(
        moduleId: 'm1',
        initialText: replaced.front,
        initialSolution: replaced.back,
        initialKind: InteractiveKind.gantt,
        replaceCard: replaced,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('task-import-add-image')));
    for (var i = 0; i < 40 && find.byKey(const ValueKey('task-import-image-0')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tap(tester, 'task-import-build');
    expect(model, AppSettings.defaultVisionModel); // mit Foto: Vision-Modell

    expect(find.byKey(const ValueKey('gantt-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('gantt-edit-uncertain')), findsOneWidget);

    await tap(tester, 'task-import-remove-replaced');
    await tap(tester, 'task-import-save');
    expect(find.text('Trotzdem speichern?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Speichern')));
    await settle(tester);

    final card = cards.saved.single;
    expect(card.type, QuestionType.gantt);
    final task = GanttTask.fromMap(card.taskData)!;
    expect(task.hasUncertain, isFalse); // beim Speichern bestätigt
    expect(card.back, isNotEmpty); // Lösungsweg schreibt die App
    expect(card.sourceMaterialId, 'blatt');
    expect(card.sourcePage, 3);
    expect(cards.deleted, ['learn1']);
  });

  testWidgets('nicht geeignet: Begründung, dann trotzdem als Rechenweg versuchen', (tester) async {
    final prompts = <String>[];
    TaskImportScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            prompts.add(((jsonDecode(r.body)['messages'] as List).last['content']) as String);
            return prompts.length == 1
                ? _chat({'kind': 'none', 'reason': 'Hier soll ein Diagramm gezeichnet werden.'})
                : _chat(_stepsDraft());
          }),
        );
    final cards = await pump(tester, const TaskImportScreen(moduleId: 'm1', initialText: 'Zeichne das Diagramm.'));
    await tap(tester, 'task-import-build');
    expect(find.byKey(const ValueKey('task-import-unsuitable')), findsOneWidget);
    expect(find.text('Hier soll ein Diagramm gezeichnet werden.'), findsOneWidget);
    expect(prompts.first, contains('Entscheide selbst'));

    await tap(tester, 'task-import-force-steps');
    expect(prompts.last, contains('Gewünscht: "kind": "steps"'));
    expect(find.byKey(const ValueKey('task-import-unsuitable')), findsNothing);
    expect(find.byKey(const ValueKey('task-import-draft')), findsOneWidget);
    expect(cards.saved, isEmpty);
  });

  testWidgets('ausprobieren: die Aufgabe so lösen wie im Quiz, ohne zu speichern', (tester) async {
    TaskImportScreen.aiFactory = (key, model) => AiService(apiKey: key, model: model, client: MockClient((r) async => _chat(_stepsDraft())));
    final cards = await pump(tester, const TaskImportScreen(moduleId: 'm1', initialText: "Löse y' = 2x."));
    await tap(tester, 'task-import-build');
    await tap(tester, 'task-import-try');
    expect(find.widgetWithText(AppBar, 'Ausprobieren'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('step-input-0-0')), 'x^2 + C');
    await tester.pump();
    await tap(tester, 'step-check-0');
    await tester.enterText(find.byKey(const ValueKey('step-input-1-0')), 'x^2 + 1');
    await tester.pump();
    await tap(tester, 'step-check-1');
    await tap(tester, 'step-next');
    await tester.pumpAndSettle();
    expect(find.text('Ausprobiert: wäre als gewusst gewertet worden.'), findsOneWidget);
    expect(cards.saved, isEmpty);
  });

  group('Foto-Prüfung des Rechenwegs', () {
    Map<String, dynamic> review({required bool error}) => {
          'lines': [
            {'n': 1, 'text': r"$y' = 2x$", 'status': 'ok'},
            {
              'n': 2,
              'text': error ? r'$y = 2x^2 + C$' : r'$y = x^2 + C$',
              'status': error ? 'fehler' : 'ok',
              'comment': error ? 'Beim Integrieren fehlt der Faktor 1/2.' : '',
              'fix': error ? r'$y = x^2 + C$' : '',
            },
          ],
          'finalAnswer': error ? '2*x^2 + 1' : 'x^2 + 1',
          'firstErrorStep': error ? 1 : null,
          'summary': error ? '1 Fehler in Zeile 2' : 'Alles richtig',
          'grade': error ? 'nochmal' : 'gut',
        };

    Future<List<({Grade? grade, bool? correct})>> openPaperCheck(WidgetTester tester, {required bool error}) async {
      PaperCheckScreen.aiFactory =
          (key, model) => AiService(apiKey: key, model: model, client: MockClient((r) async => _chat(review(error: error))));
      PaperCheckScreen.pickImagesHook = () async => [(name: 'rechnung.png', bytes: _tinyPng)];
      final results = <({Grade? grade, bool? correct})>[];
      final card = _stepsCard();
      await pump(
        tester,
        Scaffold(
          body: Column(
            children: [
              Expanded(
                child: QuestionAnswerView(
                  card: card,
                  isNew: false,
                  onComplete: ({Grade? selfGrade, bool? isCorrect}) => results.add((grade: selfGrade, correct: isCorrect)),
                ),
              ),
            ],
          ),
        ),
      );
      await tap(tester, 'step-paper');
      await tester.tap(find.byKey(const ValueKey('paper-pick')));
      for (var i = 0; i < 40 && tester.widget<FilledButton>(find.byKey(const ValueKey('paper-check'))).onPressed == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tap(tester, 'paper-check');
      return results;
    }

    testWidgets('Fehler auf Papier: Zeile mit Erklärung, App prüft das Ergebnis, ab dem Fehler in der App weiter', (tester) async {
      final results = await openPaperCheck(tester, error: true);
      expect(find.text('1 Fehler in Zeile 2'), findsOneWidget);
      // Die erste Fehlerzeile ist schon aufgeklappt.
      expect(find.textContaining('Beim Integrieren fehlt der Faktor 1/2.', findRichText: true), findsWidgets);
      expect(find.text('Dein Endergebnis weicht von der Musterlösung ab.'), findsOneWidget);

      await tap(tester, 'paper-continue');
      await tester.pumpAndSettle();
      // Schritt 1 war schon falsch – dort geht es weiter, mit einem Fehlversuch.
      expect(find.byKey(const ValueKey('step-active-0')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('step-input-0-0')), 'x^2 + C');
      await tester.pump();
      await tap(tester, 'step-check-0');
      await tester.enterText(find.byKey(const ValueKey('step-input-1-0')), 'x^2 + 1');
      await tester.pump();
      await tap(tester, 'step-check-1');
      await tap(tester, 'step-next');
      expect(results, [(grade: Grade.hard, correct: true)]);
    });

    testWidgets('alles richtig auf Papier: selbst bewerten beendet die Aufgabe', (tester) async {
      final results = await openPaperCheck(tester, error: false);
      expect(find.text('Dein Endergebnis stimmt mit der Musterlösung überein.'), findsOneWidget);
      expect(find.byKey(const ValueKey('paper-continue')), findsNothing);
      await tap(tester, 'paper-grade-good');
      await tester.pumpAndSettle();
      expect(results, [(grade: Grade.good, correct: null)]);
    });
  });
}
