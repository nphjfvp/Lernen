import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/crystal_task.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/gantt_task.dart';
import 'package:lernen/models/interactive_task.dart';
import 'package:lernen/models/step_task.dart';
import 'package:lernen/models/unsupported_task.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/unsupported_task_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/tasks/paper_check_screen.dart';
import 'package:lernen/ui/tasks/task_import_screen.dart';
import 'package:lernen/ui/tasks/unsupported_tasks_screen.dart';
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

/// Sammelliste im Speicher statt in der Datenbank.
class _MemoryUnsupported extends UnsupportedTaskRepository {
  final items = <UnsupportedTask>[];
  final removed = <String>[];

  @override
  bool get isLoaded => true;

  @override
  List<UnsupportedTask> get all => List.unmodifiable(items);

  @override
  List<UnsupportedTask> forModule(String moduleId) => [for (final t in items) if (t.moduleId == moduleId) t];

  @override
  Future<void> load() async {}

  @override
  Future<UnsupportedTask> add({
    required String moduleId,
    required String text,
    String reason = '',
    String needs = '',
    String? sourceMaterialId,
    int? sourcePage,
    DateTime? now,
  }) async {
    items.removeWhere((t) => t.moduleId == moduleId && UnsupportedTask.sameKey(t.text) == UnsupportedTask.sameKey(text));
    final t = UnsupportedTask(
      id: 'u${items.length + removed.length}',
      moduleId: moduleId,
      text: text,
      reason: reason,
      needs: needs,
      sourceMaterialId: sourceMaterialId,
      sourcePage: sourcePage,
      createdAt: now ?? DateTime(2026, 10, 1),
    );
    items.add(t);
    notifyListeners();
    return t;
  }

  @override
  Future<void> removeText(String moduleId, String text) async {
    removed.add(text);
    items.removeWhere((t) => t.moduleId == moduleId && UnsupportedTask.sameKey(t.text) == UnsupportedTask.sameKey(text));
    notifyListeners();
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  @override
  Future<void> clear({String? moduleId}) async {
    items.removeWhere((t) => moduleId == null || t.moduleId == moduleId);
    notifyListeners();
  }
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

Map<String, dynamic> _crystalDraft({bool uncertain = false}) => {
      'kind': 'crystal',
      'front': '2a) Zeichnen Sie die Richtungen [1 1 1] und [1̄ 1̄ 1] in die Einheitszelle ein.',
      'back': '',
      'taskData': {
        'lattice': 'sc',
        'parts': [
          {'kind': 'direction', 'indices': [1, 1, 1]},
          {'kind': 'direction', 'indices': [-1, -1, 1], 'uncertain': uncertain},
        ],
      },
    };

Map<String, dynamic> _noneDraft() => {
      'kind': 'none',
      'front': '3c) Skizzieren Sie das Spannungs-Dehnungs-Diagramm.',
      'reason': 'Hier soll eine Kurve gezeichnet werden.',
      'needs': 'Kurve in Diagramm zeichnen',
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

  late _MemoryUnsupported unsupported;

  Future<_RecordingCards> pump(WidgetTester tester, Widget home, {double height = 3200}) async {
    tester.view.physicalSize = Size(900, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cards = _RecordingCards();
    unsupported = _MemoryUnsupported();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
        ChangeNotifierProvider<FlashcardRepository>.value(value: cards),
        ChangeNotifierProvider<UnsupportedTaskRepository>.value(value: unsupported),
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

    test('mehrere Teilaufgaben: Liste unter "tasks", Kristall, Bedienart, unvollständige Daten', () {
      final drafts = AiService.parseInteractiveTasks({
        'tasks': [
          _crystalDraft(uncertain: true),
          _noneDraft(),
          {'kind': 'crystal', 'front': 'Ebene', 'taskData': {'parts': []}},
        ],
      });
      expect(drafts, hasLength(3));
      expect(drafts[0].kind, InteractiveKind.crystal);
      expect(drafts[0].crystal!.hasUncertain, isTrue);
      expect(drafts[0].taskData!['kind'], 'crystal');
      expect(drafts[1].kind, isNull);
      expect(drafts[1].needs, 'Kurve in Diagramm zeichnen');
      expect(drafts[1].incomplete, isFalse);
      expect(drafts[2].kind, isNull);
      expect(drafts[2].incomplete, isTrue);
      expect(drafts[2].reason, contains('Kristallgitter'));
      // Ein einzelnes Objekt ist eine Liste mit einem Eintrag.
      expect(AiService.parseInteractiveTasks(_stepsDraft()).single.kind, InteractiveKind.steps);
    });

    test('nur unvollständige Entwürfe: Fehler statt leerer Vorschau', () async {
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async => _chat({
              'tasks': [
                {'kind': 'steps', 'front': 'x', 'taskData': {'steps': []}},
              ],
            })),
      );
      await expectLater(ai.buildInteractiveTasks(text: 'Aufgabe'), throwsA(isA<AiServiceException>()));
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

      final crystal = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'Kristallgitter',
        'front': 'Zeichne [1 1 1] ein.',
        'back': '',
        'crystalTask': _crystalDraft()['taskData'],
      });
      expect(QuestionParsing.parseType(crystal!['type'] as String?), QuestionType.crystal);
      expect(CrystalTask.fromMap(parseTaskData(crystal['taskData']))!.parts, hasLength(2));
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
    expect(find.byKey(const ValueKey('task-import-draft-0')), findsOneWidget);
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
    expect(find.byKey(const ValueKey('task-import-unsuitable-0')), findsOneWidget);
    expect(find.text('Hier soll ein Diagramm gezeichnet werden.'), findsOneWidget);
    expect(prompts.first, contains('Entscheide je Teilaufgabe selbst'));
    // Automatisch auf der Sammelliste (Text aus der Eingabe, weil die KI keinen geliefert hat).
    expect(unsupported.items.single.text, 'Zeichne das Diagramm.');
    expect(find.byKey(const ValueKey('task-import-listed')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-import-save')), findsNothing);

    await tap(tester, 'task-import-force-0-steps');
    expect(prompts.last, contains('Gewünscht: "kind": "steps"'));
    expect(find.byKey(const ValueKey('task-import-unsuitable-0')), findsNothing);
    expect(find.byKey(const ValueKey('task-import-steps-0-2')), findsOneWidget);
    expect(cards.saved, isEmpty);

    // Doch noch interaktiv gespeichert: von der Sammelliste genommen.
    await tap(tester, 'task-import-save');
    expect(cards.saved.single.type, QuestionType.steps);
    expect(unsupported.removed, ['Zeichne das Diagramm.']);
    expect(unsupported.items, isEmpty);
  });

  testWidgets('mehrere Teilaufgaben von einem Foto: Kristall + Rechenweg speichern, Rest auf die Sammelliste', (tester) async {
    TaskImportScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async => _chat({
                'tasks': [_crystalDraft(), _stepsDraft(), _noneDraft()],
              })),
        );
    final cards = await pump(
      tester,
      TaskImportScreen(moduleId: 'm1', moduleName: 'Werkstoffkunde', initialImages: [_tinyPng], sourceMaterialId: 'blatt2', sourcePage: 1),
      height: 4200,
    );
    await tap(tester, 'task-import-build');

    expect(find.text('Die KI hat 3 Teilaufgaben gefunden – 2 davon interaktiv.'), findsOneWidget);
    // Die erste brauchbare ist aufgeklappt: Kristall-Editor mit Vorschau.
    expect(find.byKey(const ValueKey('crystal-edit-lattice')), findsOneWidget);
    expect(find.byKey(const ValueKey('crystal-preview')), findsOneWidget);
    expect(find.text('Kristallgitter · bereit'), findsOneWidget);
    expect(find.text('Rechenweg · nachgerechnet'), findsOneWidget);
    expect(find.text('Noch nicht interaktiv · auf der Liste'), findsOneWidget);

    final listed = unsupported.items.single;
    expect(listed.needs, 'Kurve in Diagramm zeichnen');
    expect(listed.reason, 'Hier soll eine Kurve gezeichnet werden.');
    expect(listed.sourceMaterialId, 'blatt2');
    expect(listed.sourcePage, 1);

    // Gesperrt: keine Speichern-Checkbox für die nicht interaktive Aufgabe.
    expect(find.byKey(const ValueKey('task-import-include-2')), findsNothing);
    expect(find.widgetWithText(FilledButton, '2 Aufgaben speichern'), findsOneWidget);
    await tap(tester, 'task-import-save');

    expect(cards.saved, hasLength(2));
    final crystal = cards.saved.firstWhere((c) => c.type == QuestionType.crystal);
    final task = CrystalTask.fromMap(crystal.taskData)!;
    expect(task.parts.map((p) => p.indices), [
      [1, 1, 1],
      [-1, -1, 1],
    ]);
    // Ohne Erklärung der KI schreibt die App den Lösungsweg.
    expect(crystal.back, contains('Starte bei (1, 1, 0) und gehe nach (0, 0, 1).'));
    expect(crystal.sourceMaterialId, 'blatt2');
    expect(crystal.priorityIntroduction, isTrue);
    expect(cards.saved.where((c) => c.type == QuestionType.steps), hasLength(1));
    // Die nicht passende Aufgabe bleibt auf der Liste.
    expect(unsupported.items, hasLength(1));
  });

  testWidgets('Teilaufgabe abwählen; unsichere Indizes werden vor dem Speichern nachgefragt', (tester) async {
    TaskImportScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async => _chat({
                'tasks': [_crystalDraft(uncertain: true), _stepsDraft()],
              })),
        );
    final cards = await pump(tester, const TaskImportScreen(moduleId: 'm1', initialText: 'Aufgabe 2'), height: 4200);
    await tap(tester, 'task-import-build');
    expect(find.text('Kristallgitter · bitte prüfen'), findsOneWidget);

    await tap(tester, 'task-import-include-1');
    expect(find.widgetWithText(FilledButton, 'Speichern'), findsOneWidget);
    await tap(tester, 'task-import-save');
    expect(find.text('Trotzdem speichern?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Speichern')));
    await settle(tester);

    final card = cards.saved.single;
    expect(card.type, QuestionType.crystal);
    expect(CrystalTask.fromMap(card.taskData)!.hasUncertain, isFalse); // beim Speichern bestätigt
  });

  testWidgets('Sammelliste: gruppiert, kopieren, einzeln und alle löschen', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pump(tester, const UnsupportedTasksScreen(moduleId: 'm1', moduleName: 'Werkstoffkunde'));
    await unsupported.add(moduleId: 'm1', text: 'Skizziere das Diagramm.', reason: 'Kurve zeichnen.', needs: 'Kurve in Diagramm zeichnen');
    await unsupported.add(moduleId: 'm1', text: 'Zeichne die Fließkurve.', needs: 'kurve in diagramm zeichnen', sourcePage: 4);
    await unsupported.add(moduleId: 'm1', text: 'Begründe, warum …', needs: 'Begründung schreiben');
    await unsupported.add(moduleId: 'm2', text: 'Anderes Fach', needs: 'Netzplan zeichnen');
    await tester.pump();

    expect(find.byKey(const ValueKey('unsupported-group-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('unsupported-group-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('unsupported-group-2')), findsNothing);
    expect(find.text('Kurve in Diagramm zeichnen'), findsOneWidget);
    expect(find.text('Anderes Fach'), findsNothing);

    await tap(tester, 'unsupported-copy-button');
    expect(copied, startsWith('Noch nicht interaktiv – 3 Aufgaben (Werkstoffkunde)'));
    expect(copied, contains('## Kurve in Diagramm zeichnen (2)'));
    expect(copied, contains('  Grund: Kurve zeichnen.'));
    expect(copied, contains('  (Seite 4)'));
    expect(find.text('Liste kopiert – du kannst sie jetzt einfügen und schicken.'), findsOneWidget);

    await tap(tester, 'unsupported-delete-${unsupported.items.first.id}');
    expect(unsupported.forModule('m1'), hasLength(2));

    await tap(tester, 'unsupported-clear');
    await tester.tap(find.widgetWithText(FilledButton, 'Alle löschen'));
    await settle(tester);
    expect(unsupported.forModule('m1'), isEmpty);
    expect(unsupported.items.single.moduleId, 'm2');
    expect(find.byKey(const ValueKey('unsupported-empty')), findsOneWidget);
  });

  testWidgets('ausprobieren: die Aufgabe so lösen wie im Quiz, ohne zu speichern', (tester) async {
    TaskImportScreen.aiFactory = (key, model) => AiService(apiKey: key, model: model, client: MockClient((r) async => _chat(_stepsDraft())));
    final cards = await pump(tester, const TaskImportScreen(moduleId: 'm1', initialText: "Löse y' = 2x."));
    await tap(tester, 'task-import-build');
    await tap(tester, 'task-import-try-0');
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
