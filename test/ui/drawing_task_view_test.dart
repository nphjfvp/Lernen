import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/drawing_task.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/interactive_task.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/answer_checker.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/tasks/drawing_task_editor.dart';
import 'package:lernen/ui/tasks/drawing_task_view.dart';
import 'package:provider/provider.dart';

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

class _SettingsWithoutKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings();
}

http.Response _chat(Object json) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': jsonEncode(json)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _rolling = DrawingTask(
  panels: ['vor dem Walzen', 'nach dem Walzen'],
  criteria: [
    DrawingCriterion(text: 'Gleichmäßige, rundliche Körner (globulitisch)', panel: 'vor dem Walzen'),
    DrawingCriterion(text: 'Körner in Walzrichtung gestreckt', panel: 'nach dem Walzen'),
    DrawingCriterion(text: 'Walzrichtung als Pfeil', required: false),
  ],
  solution: 'Links ein Polygonnetz gleich großer Körner, rechts dieselben Körner langgezogen.',
);

Flashcard _card(DrawingTask task) => Flashcard(
  id: 'd1',
  moduleId: 'm1',
  front: 'Skizzieren Sie das Korngefüge vor und nach dem Kaltwalzen.',
  back: task.solutionText(),
  createdAt: DateTime(2026, 1, 1),
  due: DateTime(2026, 1, 1),
  type: QuestionType.drawing,
  taskData: task.toMap(),
);

void main() {
  late List<({Grade? grade, bool? correct})> results;
  late List<String> requests;

  setUp(() {
    requests = [];
    DrawingTaskView.renderHook = (strokes) async => Uint8List.fromList([137, 80, 78, 71, strokes.length]);
  });

  tearDown(() {
    DrawingTaskView.aiFactory = null;
    DrawingTaskView.pickPhotoHook = null;
    DrawingTaskView.renderHook = null;
  });

  void answerWith(List<Object> replies) {
    var n = 0;
    DrawingTaskView.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        requests.add(r.body);
        return _chat(replies[n++ % replies.length]);
      }),
    );
  }

  Future<void> pump(
    WidgetTester tester,
    DrawingTask task, {
    bool examMode = false,
    bool withKey = true,
    bool viaQuestionView = false,
    bool canGiveUp = false,
  }) async {
    tester.view.physicalSize = const Size(700, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    results = [];
    final card = _card(task);
    void done({Grade? selfGrade, bool? isCorrect}) => results.add((grade: selfGrade, correct: isCorrect));
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsRepository>.value(
        value: withKey ? _SettingsWithKey() : _SettingsWithoutKey(),
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: Scaffold(
            body: viaQuestionView
                ? Column(
                    children: [
                      Expanded(
                        child: QuestionAnswerView(card: card, isNew: false, onComplete: done),
                      ),
                    ],
                  )
                : DrawingTaskView(
                    card: card,
                    task: task,
                    isNew: false,
                    examMode: examMode,
                    canGiveUp: canGiveUp,
                    onComplete: done,
                  ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Future<void> scribble(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('drawing-canvas')));
    final box = tester.getRect(find.byKey(const ValueKey('drawing-canvas')));
    final g = await tester.startGesture(box.center - const Offset(60, 20));
    await g.moveTo(box.center);
    await g.moveTo(box.center + const Offset(60, 30));
    await g.up();
    await tester.pump();
  }

  String text(WidgetTester tester, String key) => tester
      .widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' ');

  test('Modell: Flächen, Kriterien, toMap/fromMap mit Aliasen, Urteil der KI', () {
    final map = _rolling.toMap();
    expect(map['kind'], 'drawing');
    expect(DrawingTask.fromMap(map)!.toMap(), map);
    expect(_rolling.criteriaFor('nach dem Walzen'), hasLength(2));
    expect(_rolling.solutionText(), contains('• nach dem Walzen: Körner in Walzrichtung gestreckt'));
    expect(_rolling.solutionText(), contains('Walzrichtung als Pfeil (optional)'));

    final german = DrawingTask.fromMap({
      'flaechen': ['primär', 'sekundär'],
      'kriterien': [
        'Neue, kleine Körner',
        {'kriterium': 'Einzelne sehr große Körner', 'fläche': 'sekundär', 'pflicht': 'false'},
        {'text': ''},
      ],
      'lösung': 'Feinkorn bzw. Grobkorn',
    })!;
    expect(german.panels, ['primär', 'sekundär']);
    expect(german.criteria, hasLength(2));
    expect(german.criteria[1].required, isFalse);
    expect(german.isUsable, isTrue);
    expect(const DrawingTask(criteria: [DrawingCriterion(text: 'x', required: false)]).isUsable, isFalse);

    final review = DrawingReview.fromJson({
      'results': [
        {'n': 2, 'met': 'ja', 'comment': 'gestreckt'},
        {'n': 1, 'met': 'ja'},
        {'n': 3, 'met': 'nein'},
      ],
      'feedback': 'Gut.',
    }, 3);
    expect(review.marks, [DrawingMark.met, DrawingMark.met, DrawingMark.missing]);
    expect(review.passes(_rolling), isTrue, reason: 'optionales Kriterium zählt nicht');
    expect(DrawingReview.fromJson({'results': []}, 3).passes(_rolling), isFalse);
  });

  testWidgets('KI prüft beide Flächen: erst fehlt etwas, nach dem Ergänzen bestanden → Schwer', (tester) async {
    answerWith([
      {
        'results': [
          {'n': 1, 'met': 'ja'},
          {'n': 2, 'met': 'nein', 'comment': 'Die Körner sind nicht gestreckt.'},
          {'n': 3, 'met': 'unklar'},
        ],
        'feedback': 'Rechts fehlt die Streckung.',
      },
      {
        'results': [
          {'n': 1, 'met': 'ja'},
          {'n': 2, 'met': 'ja'},
          {'n': 3, 'met': 'nein'},
        ],
        'feedback': 'Passt.',
      },
    ]);
    await pump(tester, _rolling);
    expect(find.textContaining('Körner in Walzrichtung'), findsNothing, reason: 'Kriterien vor der Prüfung verborgen');

    await tap(tester, 'drawing-check');
    expect(text(tester, 'drawing-error'), contains('Zeichne zuerst etwas'));

    await scribble(tester);
    await tap(tester, 'drawing-panel-1');
    await scribble(tester);
    await tap(tester, 'drawing-check');
    expect(requests, hasLength(1));
    final sent = requests.single;
    expect(sent, contains('Bild 1 – Fläche „vor dem Walzen“'));
    expect(sent, contains('Bild 2 – Fläche „nach dem Walzen“'));
    expect(sent, contains('2. [nach dem Walzen] Körner in Walzrichtung gestreckt'));
    expect(text(tester, 'drawing-review'), contains('Noch nicht alles zu erkennen'));
    expect(text(tester, 'drawing-result-1'), contains('Die Körner sind nicht gestreckt.'));

    await scribble(tester);
    expect(find.byKey(const ValueKey('drawing-review')), findsNothing, reason: 'neue Striche verwerfen das Urteil');
    await tap(tester, 'drawing-check');
    expect(text(tester, 'drawing-review'), contains('alle wichtigen Merkmale'));
    expect(text(tester, 'drawing-finished'), contains('im zweiten Anlauf'));
    await tap(tester, 'drawing-next');
    expect(results.single.correct, isTrue);
    expect(results.single.grade, Grade.hard);
  });

  testWidgets('Foto statt Zeichnung: geht an die KI, im ersten Versuch bestanden', (tester) async {
    const task = DrawingTask(criteria: [DrawingCriterion(text: 'Lamellen aus Ferrit und Zementit')]);
    answerWith([
      {
        'results': [
          {'n': 1, 'met': true},
        ],
      },
    ]);
    // Kleines gültiges PNG (1×1), damit prepareImageForAi es durchlässt.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
    );
    DrawingTaskView.pickPhotoHook = () async => png;
    await pump(tester, task);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('drawing-photo')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drawing-photo-remove')), findsOneWidget);
    await tap(tester, 'drawing-check');
    expect(requests.single, contains(base64Encode(png)));
    await tap(tester, 'drawing-next');
    expect(results.single.correct, isTrue);
    expect(results.single.grade, isNull);
  });

  testWidgets('ohne Key: Hinweis, selbst abhaken – nicht alles → zählt als nicht gewusst', (tester) async {
    await pump(tester, _rolling, withKey: false);
    await scribble(tester);
    await tap(tester, 'drawing-check');
    expect(text(tester, 'drawing-error'), contains('OpenRouter-Key'));
    await tap(tester, 'drawing-self');
    expect(text(tester, 'drawing-self-box'), contains('Polygonnetz'));
    await tap(tester, 'drawing-tick-0');
    await tap(tester, 'drawing-self-done');
    expect(text(tester, 'drawing-finished'), contains('Nicht alles getroffen'));
    expect(text(tester, 'drawing-solution'), contains('Körner in Walzrichtung gestreckt'));
    await tap(tester, 'drawing-next');
    expect(results.single.correct, isFalse);
  });

  testWidgets('selbst abhaken: alle Pflicht-Kriterien → gewusst', (tester) async {
    await pump(tester, _rolling, withKey: false);
    await tap(tester, 'drawing-self');
    await tap(tester, 'drawing-tick-0');
    await tap(tester, 'drawing-tick-1');
    await tap(tester, 'drawing-self-done');
    await tap(tester, 'drawing-next');
    expect(results.single.correct, isTrue);
  });

  testWidgets('Auflösen zeigt die Lösung, zählt als nicht gewusst', (tester) async {
    await pump(tester, _rolling, canGiveUp: true);
    await tap(tester, 'question-give-up');
    expect(text(tester, 'drawing-solution'), contains('Aufgelöst'));
    await tap(tester, 'drawing-next');
    expect(results.single.correct, isFalse);
  });

  testWidgets('Probeklausur: Antwort abgeben lässt die KI werten, ohne Rückmeldung', (tester) async {
    answerWith([
      {
        'results': [
          {'n': 1, 'met': 'ja'},
          {'n': 2, 'met': 'nein'},
        ],
      },
    ]);
    await pump(tester, _rolling, examMode: true);
    await scribble(tester);
    await tap(tester, 'drawing-submit');
    expect(find.byKey(const ValueKey('drawing-review')), findsNothing);
    expect(results.single.correct, isFalse);
  });

  testWidgets('QuestionAnswerView zeigt Freihand-Karten zum Zeichnen', (tester) async {
    expect(AnswerChecker.isAnswerable(_card(_rolling)), isTrue);
    await pump(tester, _rolling, viaQuestionView: true);
    expect(find.byType(DrawingTaskView), findsOneWidget);
  });

  testWidgets('Editor: Flächen, Kriterium hinzufügen, Fläche zuordnen, optional', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var task = const DrawingTask(criteria: [DrawingCriterion(text: 'Neue Körner')], uncertain: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: DrawingTaskEditor(task: task, onChanged: (t) => setState(() => task = t)),
            ),
          ),
        ),
      ),
    );
    await tap(tester, 'drawing-edit-confirm');
    expect(task.uncertain, isFalse);
    await tester.enterText(find.byKey(const ValueKey('drawing-edit-panels-0')), 'primär; sekundär');
    await tester.pump();
    expect(task.panels, ['primär', 'sekundär']);
    await tap(tester, 'drawing-edit-add');
    expect(task.isUsable, isFalse, reason: 'leeres Kriterium');
    await tester.enterText(find.byKey(const ValueKey('drawing-edit-1-1-text')), 'Wenige sehr große Körner');
    await tester.pump();
    await tap(tester, 'drawing-edit-1-1-panel');
    await tester.tap(find.text('sekundär').last);
    await tester.pumpAndSettle();
    await tap(tester, 'drawing-edit-1-1-required');
    expect(task.criteria[1].panel, 'sekundär');
    expect(task.criteria[1].required, isFalse);
    expect(task.isUsable, isTrue);
    expect(text(tester, 'drawing-preview'), contains('sekundär: Wenige sehr große Körner (optional)'));
  });

  test('KI-Antworten: Aufgabe "drawing" und Eintrag mit Kriterien', () {
    final draft = AiService.parseInteractiveTask({
      'kind': 'drawing',
      'front': 'Skizzieren Sie das Gefüge nach primärer und sekundärer Rekristallisation.',
      'taskData': {
        'panels': ['primär', 'sekundär'],
        'criteria': [
          {'text': 'Feine, gleichachsige Körner', 'panel': 'primär'},
          {'text': 'Einzelne Riesenkörner', 'panel': 'sekundär'},
        ],
      },
    });
    expect(draft.kind, InteractiveKind.drawing);
    expect(draft.drawing!.panels, hasLength(2));
    expect(
      AiService.parseInteractiveTask({
        'criteria': ['Körner'],
      }).kind,
      InteractiveKind.drawing,
    );
    expect(interactiveKindFrom('Gefüge skizzieren'), InteractiveKind.drawing);
    expect(interactiveKindFrom('Freihand'), InteractiveKind.drawing);

    final entry = QuestionParsing.normalizeGeneratedFlashcard({
      'type': 'Freihandskizze',
      'front': 'Skizzieren Sie Perlit.',
      'criteria': ['Lamellen'],
    })!;
    expect(QuestionParsing.parseType(entry['type'] as String?), QuestionType.drawing);
    expect(DrawingTask.fromMap(entry['taskData'])!.criteria.single.text, 'Lamellen');
  });
}
