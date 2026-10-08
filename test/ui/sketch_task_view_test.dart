import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/sketch_task.dart';
import 'package:lernen/services/answer_checker.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/tasks/sketch_task_editor.dart';
import 'package:lernen/ui/tasks/sketch_task_view.dart';

List<SketchPoint> _line(List<List<num>> points) => [
  for (final p in points) SketchPoint(p[0].toDouble(), p[1].toDouble()),
];

final _iron = SketchTask(
  xAxis: const SketchAxis(label: 'T in °C', min: 500, max: 1000),
  yAxis: const SketchAxis(label: 'ΔL/L', min: 0, max: 1, showNumbers: false),
  reference: [
    _line([
      [500, 0.2],
      [911, 0.6],
    ]),
    _line([
      [911, 0.45],
      [1000, 0.6],
    ]),
  ],
  features: const [
    SketchFeature(kind: SketchFeatureKind.rising, x: 500, x2: 911),
    SketchFeature(kind: SketchFeatureKind.jumpDown, x: 911, tol: 0.05, text: 'krz → kfz, dichter gepackt'),
    SketchFeature(kind: SketchFeatureKind.rising, x: 911, x2: 1000),
  ],
);

final _tensile = SketchTask(
  xAxis: const SketchAxis(label: 'ε in %', min: 0, max: 30),
  yAxis: const SketchAxis(label: 'σ in MPa', min: 0, max: 600),
  reference: [
    _line([
      [0, 0],
      [2, 300],
      [4, 330],
      [15, 500],
      [25, 420],
    ]),
  ],
  features: const [
    SketchFeature(kind: SketchFeatureKind.max, x: 15, tol: 0.15),
    SketchFeature(kind: SketchFeatureKind.mark, label: 'R_m', anchor: SketchAnchor.max),
    SketchFeature(kind: SketchFeatureKind.mark, label: 'A', anchor: SketchAnchor.end),
  ],
);

Flashcard _card(SketchTask task) => Flashcard(
  id: 's1',
  moduleId: 'm1',
  front: 'Skizzieren Sie das Diagramm.',
  back: '',
  createdAt: DateTime(2026, 1, 1),
  due: DateTime(2026, 1, 1),
  type: QuestionType.sketch,
  taskData: task.toMap(),
);

void main() {
  late List<({Grade? grade, bool? correct})> results;

  Future<void> pump(WidgetTester tester, SketchTask task, {bool examMode = false, bool viaQuestionView = false}) async {
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
              : SketchTaskView(card: card, task: task, isNew: false, examMode: examMode, onComplete: done),
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

  /// Bildschirmpunkt zu Achsen-Werten (Zeichenfläche: 46 px links, 14 oben, 14 rechts, 36 unten).
  Offset at(WidgetTester tester, SketchTask task, double x, double y) {
    final box = tester.getRect(find.byKey(const ValueKey('sketch-canvas')));
    final plot = Rect.fromLTRB(box.left + 46, box.top + 14, box.right - 14, box.bottom - 36);
    return Offset(plot.left + task.xAxis.norm(x) * plot.width, plot.bottom - task.yAxis.norm(y) * plot.height);
  }

  Future<void> draw(WidgetTester tester, SketchTask task, List<List<num>> points) async {
    final g = await tester.startGesture(at(tester, task, points.first[0].toDouble(), points.first[1].toDouble()));
    for (final p in points.skip(1)) {
      await g.moveTo(at(tester, task, p[0].toDouble(), p[1].toDouble()));
    }
    await g.up();
    await tester.pump();
  }

  String text(WidgetTester tester, String key) => tester
      .widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .join(' ');

  testWidgets('Sprung bei 911 °C zeichnen: geprüft, danach Musterkurve zum Vergleich', (tester) async {
    await pump(tester, _iron);
    await tester.ensureVisible(find.byKey(const ValueKey('sketch-canvas')));
    await draw(tester, _iron, [
      [500, 0.2],
      [700, 0.4],
      [905, 0.6],
    ]);
    await draw(tester, _iron, [
      [915, 0.42],
      [1000, 0.55],
    ]);
    await tap(tester, 'sketch-check');
    expect(text(tester, 'sketch-verdict'), contains('Alle Merkmale stimmen'));
    expect(find.text('Grün gestrichelt: die Musterkurve zum Vergleich.'), findsOneWidget);
    expect(text(tester, 'sketch-finished'), contains('ohne Hilfe'));
    await tap(tester, 'sketch-next');
    expect(results.single.correct, isTrue);
    expect(results.single.grade, isNull);
  });

  testWidgets('ohne Sprung: Rückmeldung je Merkmal, Rückgängig und neu zeichnen', (tester) async {
    await pump(tester, _iron);
    await tester.ensureVisible(find.byKey(const ValueKey('sketch-canvas')));
    await draw(tester, _iron, [
      [500, 0.2],
      [1000, 0.7],
    ]);
    await tap(tester, 'sketch-check');
    expect(text(tester, 'sketch-verdict'), contains('2 von 3 Merkmalen stimmen'));
    expect(text(tester, 'sketch-result-1'), contains('fehlt der Sprung nach unten (krz → kfz'));

    await tap(tester, 'sketch-undo');
    expect(find.byKey(const ValueKey('sketch-verdict')), findsNothing);
    await draw(tester, _iron, [
      [500, 0.2],
      [910, 0.6],
      [912, 0.35],
      [1000, 0.5],
    ]);
    await tap(tester, 'sketch-check');
    await tap(tester, 'sketch-next');
    expect(results.single.correct, isTrue);
    expect(results.single.grade, Grade.hard);
  });

  testWidgets('Kennwerte markieren: Modus wechseln, Name wählen, Stelle antippen', (tester) async {
    await pump(tester, _tensile);
    await tester.ensureVisible(find.byKey(const ValueKey('sketch-canvas')));
    await draw(tester, _tensile, [
      [0, 0],
      [2, 290],
      [8, 400],
      [15, 500],
      [25, 420],
    ]);
    await tester.tap(find.text('Markieren'));
    await tester.pump();
    await tap(tester, 'sketch-label-0');
    await tester.tapAt(at(tester, _tensile, 15, 495));
    await tester.pump();
    await tap(tester, 'sketch-label-1');
    await tester.tapAt(at(tester, _tensile, 26, 10));
    await tester.pump();
    await tap(tester, 'sketch-check');
    expect(text(tester, 'sketch-verdict'), contains('Alle Merkmale stimmen'), reason: text(tester, 'sketch-verdict'));
  });

  testWidgets('Lösung zeigen: Merkmale als Text, zählt als nicht gewusst; Tipps', (tester) async {
    await pump(tester, _iron);
    await tap(tester, 'sketch-hint-button');
    expect(text(tester, 'sketch-hint-0'), contains('Achte auf den Verlauf'));
    await tap(tester, 'sketch-reveal');
    expect(text(tester, 'sketch-solution'), contains('Sprung nach unten 911'));
    await tap(tester, 'sketch-next');
    expect(results.single.correct, isFalse);
  });

  testWidgets('Probeklausur: ohne Rückmeldung abgeben', (tester) async {
    await pump(tester, _iron, examMode: true);
    expect(find.byKey(const ValueKey('sketch-check')), findsNothing);
    await tap(tester, 'sketch-submit');
    expect(results.single.correct, isFalse);
    expect(find.byKey(const ValueKey('sketch-verdict')), findsNothing);
  });

  testWidgets('QuestionAnswerView zeigt Skizzen-Karten als Skizze', (tester) async {
    expect(AnswerChecker.isAnswerable(_card(_iron)), isTrue);
    await pump(tester, _iron, viaQuestionView: true);
    expect(find.byType(SketchTaskView), findsOneWidget);
  });

  test('KI-Eintrag mit Merkmalen wird zur Skizze', () {
    final entry = QuestionParsing.normalizeGeneratedFlashcard({
      'type': 'Skizze',
      'front': 'Skizzieren Sie die Potentialkurve.',
      'xAxis': {'label': 'r', 'min': 0, 'max': 10},
      'yAxis': {'label': 'U', 'min': -1, 'max': 1},
      'reference': [
        [1, 1],
        [1.5, -0.8],
        [10, 0],
      ],
      'features': [
        {'kind': 'min', 'x': 1.5},
      ],
    })!;
    expect(QuestionParsing.parseType(entry['type'] as String?), QuestionType.sketch);
    expect(SketchTask.fromMap(entry['taskData'])!.features.single.kind, SketchFeatureKind.min);
  });

  testWidgets('Editor: Musterkurve als Text, Merkmal ändern, Vorschau prüft die Musterkurve', (tester) async {
    tester.view.physicalSize = const Size(700, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var task = _iron;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: SketchTaskEditor(task: task, onChanged: (t) => setState(() => task = t)),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('sketch-preview')), findsOneWidget);
    expect(find.textContaining('⚠'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('sketch-edit-reference')), '500; 0.2\nfalsch');
    await tester.pump();
    expect(find.textContaining('Zeile 2'), findsOneWidget);

    // Sprung an eine Stelle verlegen, an der die Musterkurve keinen hat → Warnung.
    await tester.enterText(find.byKey(const ValueKey('sketch-edit-1-0-x')), '700');
    await tester.pump();
    expect(task.features[1].x, 700);
    expect(find.textContaining('⚠ Die Musterkurve erfüllt „Sprung nach unten“ nicht'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sketch-edit-remove-2')));
    await tester.pump();
    expect(task.features, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('sketch-edit-add')));
    await tester.pump();
    expect(task.features.last.kind, SketchFeatureKind.rising);
    await tester.tap(find.byKey(const ValueKey('sketch-edit-numbers')));
    await tester.pump();
    expect(task.xAxis.showNumbers, isFalse);
  });
}
