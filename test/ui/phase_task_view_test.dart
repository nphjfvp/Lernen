import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/interactive_task.dart';
import 'package:lernen/models/phase_task.dart';
import 'package:lernen/models/sketch_task.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/answer_checker.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/phase_calculator.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/tasks/phase_task_editor.dart';
import 'package:lernen/ui/tasks/phase_task_view.dart';
import 'package:lernen/ui/tasks/task_import_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

class _RecordingCards extends FlashcardRepository {
  final saved = <Flashcard>[];

  @override
  Future<void> saveAll(List<Flashcard> cards) async => saved.addAll(cards);
}

const _pbSn = PhaseSystem(
  a: 'Pb',
  b: 'Sn',
  tMax: 350,
  meltA: 327,
  eutecticC: 61.9,
  eutecticT: 183,
  rightC: 100,
  rightT: 232,
  alphaMax: 18.3,
  alphaLow: 2,
  betaMax: 97.8,
  betaLow: 99,
);

PhaseTask _task(List<PhasePart> parts) => PhaseTask(system: _pbSn, parts: parts);

Flashcard _card(PhaseTask task) => Flashcard(
  id: 'p1',
  moduleId: 'm1',
  front: 'Gegeben ist das Zustandsdiagramm Blei-Zinn.',
  back: PhaseCalculator(task).fullSolution(),
  createdAt: DateTime(2026, 1, 1),
  due: DateTime(2026, 1, 1),
  type: QuestionType.phase,
  taskData: task.toMap(),
);

void main() {
  late List<({Grade? grade, bool? correct})> results;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_phase_task_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() => TaskImportScreen.pickJsonHook = null);

  Future<void> pump(
    WidgetTester tester,
    PhaseTask task, {
    bool examMode = false,
    bool viaQuestionView = false,
    bool canGiveUp = false,
  }) async {
    tester.view.physicalSize = const Size(700, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    results = [];
    final card = _card(task);
    void done({Grade? selfGrade, bool? isCorrect}) => results.add((grade: selfGrade, correct: isCorrect));
    await tester.pumpWidget(
      MaterialApp(
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
              : PhaseTaskView(
                  card: card,
                  task: task,
                  isNew: false,
                  examMode: examMode,
                  canGiveUp: canGiveUp,
                  onComplete: done,
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
    await tester.pump();
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.enterText(find.byKey(ValueKey(key)), value);
    await tester.pump();
  }

  String text(WidgetTester tester, String key) => tester
      .widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .join(' ');

  /// Bildschirmpunkt im Diagramm (Ränder wie PhaseDiagramCanvas.pad).
  Offset diagramAt(WidgetTester tester, double c, double t) {
    final box = tester.getRect(find.byKey(const ValueKey('phase-diagram-tap')));
    final plot = Rect.fromLTRB(box.left + 46, box.top + 14, box.right - 14, box.bottom - 36);
    return Offset(
      plot.left + c / _pbSn.cMax * plot.width,
      plot.bottom - (t - _pbSn.tMin) / (_pbSn.tMax - _pbSn.tMin) * plot.height,
    );
  }

  testWidgets('Phasen wählen: falsch, dann richtig – zählt als Schwer', (tester) async {
    await pump(tester, _task(const [PhasePart(kind: PhasePartKind.phases, c: 40, t: 200)]));
    expect(text(tester, 'phase-prompt'), contains('Welche Phasen liegen bei 40 % Sn und 200 °C vor?'));
    await tap(tester, 'phase-choice-1');
    await tap(tester, 'phase-check');
    expect(text(tester, 'phase-verdict'), contains('Es fehlt: Schmelze'));
    await tap(tester, 'phase-choice-0');
    expect(find.byKey(const ValueKey('phase-verdict')), findsNothing);
    await tap(tester, 'phase-check');
    expect(text(tester, 'phase-verdict'), contains('Richtig: Schmelze + α'));
    expect(text(tester, 'phase-finished'), contains('mit Hilfe'));
    await tap(tester, 'phase-next');
    expect(results.single.correct, isTrue);
    expect(results.single.grade, Grade.hard);
  });

  testWidgets('Hebel: Enden im Diagramm antippen (rechts zuerst), Anteile eintragen', (tester) async {
    await pump(
      tester,
      _task(const [
        PhasePart(kind: PhasePartKind.lever, c: 40, t: 200),
        PhasePart(kind: PhasePartKind.structure, c: 40),
      ]),
    );
    expect(text(tester, 'phase-prompt'), contains('Tippe im Diagramm die beiden Enden des Hebels an'));
    await tester.ensureVisible(find.byKey(const ValueKey('phase-diagram-tap')));
    await tester.tapAt(diagramAt(tester, 54.6, 200));
    await tester.pump();
    await tester.tapAt(diagramAt(tester, 16.1, 200));
    await tester.pump();
    final c1 = double.parse(
      tester.widget<TextField>(find.byKey(const ValueKey('phase-0-c1'))).controller!.text.replaceAll(',', '.'),
    );
    final c2 = double.parse(
      tester.widget<TextField>(find.byKey(const ValueKey('phase-0-c2'))).controller!.text.replaceAll(',', '.'),
    );
    expect(c1, closeTo(16.1, 0.8));
    expect(c2, closeTo(54.6, 0.8));
    await enter(tester, 'phase-0-f1', '38');
    await enter(tester, 'phase-0-f2', '62');
    await tap(tester, 'phase-check');
    expect(text(tester, 'phase-verdict'), contains('Richtig: α 38 %, Schmelze 62 %'));

    await tap(tester, 'phase-next-part');
    expect(text(tester, 'phase-prompt'), contains('Gefügeanteile'));
    await enter(tester, 'phase-1-primary', '50');
    await enter(tester, 'phase-1-eutectic', '50,2');
    await tap(tester, 'phase-check');
    await tap(tester, 'phase-next');
    expect(results.single.correct, isTrue);
    expect(results.single.grade, isNull);
  });

  testWidgets('Gebiet zeigen und Lösung ansehen: zählt als nicht gewusst; Tipps', (tester) async {
    await pump(tester, _task(const [PhasePart(kind: PhasePartKind.pickRegion, region: PhaseRegion.liquidBeta)]));
    await tester.ensureVisible(find.byKey(const ValueKey('phase-diagram-tap')));
    await tester.tapAt(diagramAt(tester, 40, 200));
    await tester.pump();
    await tap(tester, 'phase-check');
    expect(text(tester, 'phase-verdict'), contains('Dort liegt „Schmelze + α“'));
    await tap(tester, 'phase-hint-button');
    expect(text(tester, 'phase-hint-0'), contains('Schmelze + β'));
    await tap(tester, 'phase-reveal');
    expect(text(tester, 'phase-solution'), contains('Gebiet „Schmelze + β“'));
    await tap(tester, 'phase-next');
    expect(results.single.correct, isFalse);
  });

  testWidgets('Gebiete benennen: alle sechs nummeriert, Auswahl je Nummer', (tester) async {
    final task = _task(const [PhasePart(kind: PhasePartKind.regions)]);
    await pump(tester, task);
    final labels = PhaseCalculator(task).regionLabels();
    expect(labels, hasLength(6));
    for (final (i, l) in labels.indexed) {
      await tester.ensureVisible(find.byKey(ValueKey('phase-region-$i')));
      await tester.tap(find.byKey(ValueKey('phase-region-$i')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_pbSn.regionName(l.region)).last);
      await tester.pumpAndSettle();
    }
    await tap(tester, 'phase-check');
    expect(text(tester, 'phase-verdict'), contains('Alle Gebiete richtig benannt'));
  });

  testWidgets('Abkühlkurven: je Legierung eine Kurve, ungezeichnet → Rückmeldung', (tester) async {
    await pump(
      tester,
      _task(const [
        PhasePart(kind: PhasePartKind.cooling, compositions: [0, 40]),
      ]),
    );
    expect(find.byKey(const ValueKey('phase-curve-0')), findsOneWidget);
    expect(find.text('40 % Sn'), findsOneWidget);
    await tap(tester, 'phase-check');
    expect(find.byKey(const ValueKey('phase-verdict')), findsOneWidget);
    expect(text(tester, 'phase-verdict'), isNot(contains('Alle Merkmale stimmen')));

    // Musterkurve der ersten Legierung nachzeichnen.
    final sketch = PhaseCalculator(_task(const [])).coolingSketch([0, 40]);
    final box = tester.getRect(find.byKey(const ValueKey('phase-cooling-canvas')));
    final plot = Rect.fromLTRB(box.left + 46, box.top + 14, box.right - 14, box.bottom - 36);
    Offset at(SketchPoint p) =>
        Offset(plot.left + sketch.xAxis.norm(p.x) * plot.width, plot.bottom - sketch.yAxis.norm(p.y) * plot.height);
    Future<void> trace(List<SketchPoint> pts) async {
      final g = await tester.startGesture(at(pts.first));
      for (var i = 1; i < pts.length; i++) {
        for (var k = 1; k <= 6; k++) {
          final a = pts[i - 1], b = pts[i];
          await g.moveTo(at(SketchPoint(a.x + (b.x - a.x) * k / 6, a.y + (b.y - a.y) * k / 6)));
        }
      }
      await g.up();
      await tester.pump();
    }

    await trace(sketch.curves[0].reference.single);
    await tap(tester, 'phase-curve-1');
    await trace(sketch.curves[1].reference.single);
    await tap(tester, 'phase-check');
    expect(text(tester, 'phase-verdict'), contains('Alle Merkmale stimmen'));
  });

  testWidgets('Probeklausur: ohne Rückmeldung, alle Teile werden gewertet', (tester) async {
    await pump(
      tester,
      _task(const [PhasePart(kind: PhasePartKind.eutecticLine), PhasePart(kind: PhasePartKind.solubility)]),
      examMode: true,
    );
    await enter(tester, 'phase-0-from', '18');
    await enter(tester, 'phase-0-to', '98');
    await tap(tester, 'phase-next-part');
    await enter(tester, 'phase-1-value', '18,3');
    await enter(tester, 'phase-1-t', '100');
    await tap(tester, 'phase-submit');
    expect(find.byKey(const ValueKey('phase-verdict')), findsNothing);
    expect(results.single.correct, isFalse);
  });

  testWidgets('Auflösen: alle offenen Teile zeigen die Lösung', (tester) async {
    await pump(tester, _task(const [PhasePart(kind: PhasePartKind.composition, t: 230)]), canGiveUp: true);
    await tap(tester, 'question-give-up');
    expect(text(tester, 'phase-solution'), allOf(contains('Aufgelöst'), contains('41,7 % Sn und 98,4 % Sn')));
    await tap(tester, 'phase-next');
    expect(results.single.correct, isFalse);
  });

  testWidgets('Blatt 6, Aufgabe 1 (1:1): Fragen, gegebene Abkühlkurve, Kurven mit Namen vom Blatt', (tester) async {
    // So wie die KI es vom Blatt liest: Werte des abgebildeten Diagramms, Teile a)–e).
    final task = PhaseTask.fromMap({
      'system': {
        'a': 'Pb',
        'b': 'Sn',
        'tMin': 0,
        'tMax': 350,
        'meltA': 327,
        'eutecticC': 61.9,
        'eutecticT': 180,
        'rightC': 100,
        'rightT': 240,
        'alphaMax': 29,
        'alphaLow': 2,
        'betaMax': 97.5,
        'betaLow': 99,
        'alpha': 'α-MK',
        'beta': 'β-MK',
        'structureNames': true,
      },
      'parts': [
        {
          'kind': 'question',
          'prompt': 'a) Um welchen Typ von Zweistoffsystem handelt es sich?',
          'options': [
            'Vollständige Löslichkeit im festen Zustand',
            'Eutektisches System mit begrenzter Löslichkeit im festen Zustand',
            'Peritektisches System',
          ],
          'correct': 1,
        },
        {
          'kind': 'question',
          'prompt': 'b) Auf welche gegenseitige Löslichkeit lässt das Diagramm schließen?',
          'answer': 'Flüssig vollständig löslich, fest nur begrenzt (α- und β-Mischkristalle).',
        },
        {
          'kind': 'composition',
          'curveGiven': true,
          't': 228,
          'prompt': 'c) Ermitteln Sie die beiden möglichen Legierungszusammensetzungen.',
        },
        {
          'kind': 'question',
          'prompt': 'd) Schlagen Sie ein Verfahren zur Unterscheidung vor.',
          'answer': 'Metallografischer Schliff: primäre α- bzw. β-MK im Gefüge.',
        },
        {
          'kind': 'cooling',
          'compositions': [0, 20, 61.9],
          'labels': ['100 % Pb, 0 % Sn', '80 % Pb, 20 % Sn', 'Eutektische Legierung'],
        },
      ],
    })!;
    expect(task.isUsable, isTrue);
    expect(task.system.structureNames, isTrue);
    await pump(tester, task);

    // a) Auswahl.
    await tap(tester, 'phase-option-0');
    await tap(tester, 'phase-check');
    expect(text(tester, 'phase-verdict'), contains('Nicht ganz'));
    await tap(tester, 'phase-option-1');
    await tap(tester, 'phase-check');
    expect(text(tester, 'phase-verdict'), contains('Richtig'));

    // b) Freitext: Musterantwort aufdecken, selbst bewerten.
    await tap(tester, 'phase-next-part');
    expect(text(tester, 'phase-prompt'), contains('b) Auf welche gegenseitige Löslichkeit'));
    await tap(tester, 'phase-show-answer');
    expect(text(tester, 'phase-answer'), contains('Flüssig vollständig löslich'));
    await tap(tester, 'phase-self-ok');

    // c) Die gemessene Kurve wird gezeigt, die Temperatur steht nicht im Text.
    await tap(tester, 'phase-next-part');
    expect(find.byKey(const ValueKey('phase-given-curve')), findsOneWidget);
    expect(text(tester, 'phase-prompt'), isNot(contains('228')));
    final cs = PhaseCalculator(task).compositionsForLiquidus(228);
    expect(cs, hasLength(2));
    await enter(tester, 'phase-2-x1', PhaseCalculator.fmt(cs[0], digits: 0));
    await enter(tester, 'phase-2-x2', PhaseCalculator.fmt(cs[1], digits: 0));
    await tap(tester, 'phase-check');
    expect(text(tester, 'phase-verdict'), contains('Richtig'));

    // d) Freitext nicht gewusst → Lösung gezeigt.
    await tap(tester, 'phase-next-part');
    await tap(tester, 'phase-show-answer');
    await tap(tester, 'phase-self-wrong');
    expect(text(tester, 'phase-solution'), contains('Metallografischer Schliff'));

    // e) Kurven mit den Namen vom Blatt.
    await tap(tester, 'phase-next-part');
    expect(find.text('Eutektische Legierung'), findsOneWidget);
    expect(find.text('100 % Pb, 0 % Sn'), findsOneWidget);
    await tap(tester, 'phase-reveal');
    await tap(tester, 'phase-next');
    expect(results.single.correct, isFalse);
  });

  testWidgets('QuestionAnswerView zeigt Zustandsdiagramm-Karten als Diagramm', (tester) async {
    final task = _task(const [PhasePart(kind: PhasePartKind.phases, c: 40, t: 100)]);
    expect(AnswerChecker.isAnswerable(_card(task)), isTrue);
    await pump(tester, task, viaQuestionView: true);
    expect(find.byType(PhaseTaskView), findsOneWidget);
  });

  testWidgets('Editor: Eckdaten ändern, Teilaufgabe hinzufügen und Art wechseln', (tester) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var task = _task(const [PhasePart(kind: PhasePartKind.lever, c: 40, t: 200)]).copyWith(uncertain: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: PhaseTaskEditor(task: task, onChanged: (t) => setState(() => task = t)),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('phase-edit-uncertain')), findsOneWidget);
    await tap(tester, 'phase-edit-confirm');
    expect(task.uncertain, isFalse);
    await enter(tester, 'phase-edit-ec', '62');
    expect(task.system.eutecticC, 62);
    await tap(tester, 'phase-edit-add');
    expect(task.parts, hasLength(2));
    await tester.ensureVisible(find.byKey(const ValueKey('phase-edit-1-1-kind')));
    await tester.tap(find.byKey(const ValueKey('phase-edit-1-1-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abkühlkurven').last);
    await tester.pumpAndSettle();
    expect(task.parts[1].kind, PhasePartKind.cooling);
    expect(task.parts[1].compositions, [0, 62]);
    await enter(tester, 'phase-edit-1-2-comps', '0; 30; 62');
    expect(task.parts[1].compositions, [0, 30, 62]);
    expect(text(tester, 'phase-preview'), contains('b) 100 % Pb: reines Pb: Haltepunkt bei 327 °C'));
  });

  test('KI-Eintrag mit Diagramm-Eckdaten wird zum Zustandsdiagramm', () {
    final entry = QuestionParsing.normalizeGeneratedFlashcard({
      'type': 'Zustandsdiagramm',
      'front': 'Gegeben ist das Zustandsdiagramm Pb-Sn.',
      'system': _pbSn.toMap(),
      'parts': [
        {'kind': 'Hebelgesetz', 'c': 40, 't': 200},
      ],
    })!;
    expect(QuestionParsing.parseType(entry['type'] as String?), QuestionType.phase);
    expect(PhaseTask.fromMap(entry['taskData'])!.parts.single.kind, PhasePartKind.lever);
    expect(interactiveKindFrom('Zweistoffsystem'), InteractiveKind.phase);
  });

  testWidgets('JSON-Import einer externen KI: Zustandsdiagramm im Editor, gespeichert mit Musterlösung', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final json = jsonEncode({
      'tasks': [
        {
          'kind': 'phase',
          'front': 'Aufgabe 2: Zustandsdiagramm Blei-Zinn.',
          'taskData': {
            'system': _pbSn.toMap(),
            'parts': [
              {'kind': 'lever', 'c': 40, 't': 200},
              {
                'kind': 'cooling',
                'compositions': [0, 40, 61.9],
              },
            ],
          },
        },
      ],
    });
    expect(AiService.parseImportedTasks(json).drafts.single.phase, isNotNull);

    TaskImportScreen.pickJsonHook = () async => json;
    final cards = _RecordingCards();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
          ChangeNotifierProvider<FlashcardRepository>.value(value: cards),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const TaskImportScreen(moduleId: 'm1'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-import-json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-import-json-file')));
    await tester.pumpAndSettle();
    expect(find.byType(PhaseTaskEditor), findsOneWidget);
    expect(find.byKey(const ValueKey('task-import-back-0')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('task-import-save-top')));
    await tester.pumpAndSettle();
    final saved = cards.saved.single;
    expect(saved.type, QuestionType.phase);
    expect(saved.back, contains('a) 40 % Sn und 200 °C: Hebel von 16,1 (α)'));
    expect(PhaseTask.fromMap(saved.taskData)!.parts, hasLength(2));
  });
}
