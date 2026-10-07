import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/crystal_task.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/answer_checker.dart';
import 'package:lernen/services/crystal_geometry.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/tasks/crystal_task_editor.dart';
import 'package:lernen/ui/tasks/crystal_task_view.dart';

Flashcard _card(CrystalTask task) => Flashcard(
  id: 'k1',
  moduleId: 'm1',
  front: 'Zeichne in die Einheitszelle ein.',
  back: '',
  createdAt: DateTime(2026, 1, 1),
  due: DateTime(2026, 1, 1),
  type: QuestionType.crystal,
  taskData: task.toMap(),
);

void main() {
  late List<({Grade? grade, bool? correct})> results;

  Future<void> pump(
    WidgetTester tester,
    CrystalTask task, {
    bool examMode = false,
    bool canGiveUp = false,
    bool viaQuestionView = false,
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
              : CrystalTaskView(
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

  Future<void> dot(WidgetTester tester, List<int> half) => tap(tester, 'crystal-pt-${half.join('-')}');

  String verdict(WidgetTester tester) {
    final box = find.byKey(const ValueKey('crystal-verdict'));
    return tester
        .widgetList<Text>(find.descendant(of: box, matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .join(' ');
  }

  String calc(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('crystal-calc'))).data ?? '';

  testWidgets('Richtung [1 1 1]: Pfeil zeichnen, Live-Anzeige rechnet mit, richtig = gewusst', (tester) async {
    await pump(
      tester,
      const CrystalTask(
        parts: [
          CrystalPart(kind: CrystalPartKind.direction, indices: [1, 1, 1]),
        ],
      ),
      viaQuestionView: true,
    );
    expect(find.byKey(const ValueKey('crystal-cube')), findsOneWidget);
    // Live-Anzeige ist standardmäßig an.
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('crystal-live'))).value, isTrue);

    await dot(tester, [0, 0, 0]);
    expect(find.text('Start (0, 0, 0) – jetzt den Zielpunkt antippen.'), findsOneWidget);
    await dot(tester, [2, 2, 2]);
    expect(calc(tester), contains('[1 1 1]'));

    await tap(tester, 'crystal-check');
    expect(verdict(tester), contains('Richtig'));
    expect(find.text('Alles gelöst – ohne Hilfe'), findsOneWidget);
    await tap(tester, 'crystal-next');
    expect(results, [(grade: null, correct: true)]);
  });

  testWidgets('Richtung andersherum: Rückmeldung, dann richtig = „Schwer“; Live-Anzeige lässt sich ausschalten', (
    tester,
  ) async {
    await pump(
      tester,
      const CrystalTask(
        parts: [
          CrystalPart(kind: CrystalPartKind.direction, indices: [1, 1, 1]),
        ],
      ),
    );
    await dot(tester, [2, 2, 2]);
    await dot(tester, [0, 0, 0]);
    await tap(tester, 'crystal-check');
    expect(verdict(tester), contains('andersherum'));

    await tap(tester, 'crystal-live');
    expect(find.byKey(const ValueKey('crystal-calc')), findsNothing);
    await tap(tester, 'crystal-clear');
    await dot(tester, [0, 0, 0]);
    await dot(tester, [2, 2, 2]);
    await tap(tester, 'crystal-check');
    expect(find.text('Alles gelöst – mit Hilfe, zählt als „Schwer“'), findsOneWidget);
    await tap(tester, 'crystal-next');
    expect(results, [(grade: Grade.hard, correct: true)]);
  });

  testWidgets('Ebene (1 1 0): drei Punkte, dann (1 1 1) über Achsenabschnitte', (tester) async {
    await pump(
      tester,
      const CrystalTask(
        parts: [
          CrystalPart(kind: CrystalPartKind.plane, indices: [1, 1, 0]),
          CrystalPart(kind: CrystalPartKind.plane, indices: [1, 1, 1]),
        ],
      ),
    );
    await dot(tester, [2, 0, 0]);
    await dot(tester, [0, 2, 0]);
    await dot(tester, [0, 2, 2]);
    expect(calc(tester), contains('(1 1 0)'));
    await tap(tester, 'crystal-check');
    expect(verdict(tester), contains('Richtig'));

    await tap(tester, 'crystal-next-part');
    await tester.tap(find.text('Achsenabschnitte'));
    await tester.pump();
    // Erst falsch: ½, ½, ½ ergibt (2 2 2).
    for (final axis in ['x', 'y', 'z']) {
      await tap(tester, 'crystal-icpt-$axis-half');
    }
    await tap(tester, 'crystal-check');
    expect(verdict(tester), contains('(2 2 2)'));
    for (final axis in ['x', 'y', 'z']) {
      await tap(tester, 'crystal-icpt-$axis-1');
    }
    await tap(tester, 'crystal-check');
    expect(verdict(tester), contains('Richtig'));
    await tap(tester, 'crystal-next');
    expect(results, [(grade: Grade.hard, correct: true)]);
  });

  testWidgets('Atome in der kfz-(1 1 1)-Ebene markieren', (tester) async {
    await pump(
      tester,
      const CrystalTask(
        lattice: CrystalLattice.fcc,
        parts: [
          CrystalPart(kind: CrystalPartKind.planeAtoms, indices: [1, 1, 1]),
        ],
      ),
    );
    final atoms = CrystalGeometry.atomsIn(const [1, 1, 1], CrystalLattice.fcc);
    expect(atoms, hasLength(6));
    for (final a in atoms.take(5)) {
      await dot(tester, a);
    }
    await tap(tester, 'crystal-check');
    expect(verdict(tester), contains('es fehlt noch 1'));
    await dot(tester, atoms.last);
    await tap(tester, 'crystal-check');
    expect(verdict(tester), contains('Richtig'));
  });

  testWidgets('Familie ⟨1 0 0⟩: sechs Pfeile, doppelte und falsche werden gemeldet', (tester) async {
    await pump(
      tester,
      const CrystalTask(
        parts: [
          CrystalPart(kind: CrystalPartKind.family, indices: [1, 0, 0]),
        ],
      ),
    );
    Future<void> arrow(List<int> a, List<int> b) async {
      await dot(tester, a);
      await dot(tester, b);
    }

    await arrow([0, 0, 0], [2, 0, 0]);
    expect(verdict(tester), contains('1 von 6'));
    await arrow([0, 0, 0], [2, 0, 0]);
    expect(verdict(tester), contains('schon'));
    await arrow([0, 0, 0], [2, 2, 0]);
    expect(verdict(tester), contains('gehört nicht zur Familie'));
    await arrow([2, 0, 0], [0, 0, 0]);
    await arrow([0, 0, 0], [0, 2, 0]);
    await arrow([0, 2, 0], [0, 0, 0]);
    await arrow([0, 0, 0], [0, 0, 2]);
    await arrow([0, 0, 2], [0, 0, 0]);
    expect(verdict(tester), contains('Alle 6 gefunden'));
    await tap(tester, 'crystal-next');
    expect(results, [(grade: Grade.hard, correct: true)]);
  });

  testWidgets('Richtung ablesen: andersherum wird erklärt, ungekürzt zählt mit Hinweis', (tester) async {
    await pump(
      tester,
      const CrystalTask(
        parts: [
          CrystalPart(kind: CrystalPartKind.readDirection, indices: [2, -2, 1]),
        ],
      ),
    );
    for (final (i, v) in ['-2', '2', '-1'].indexed) {
      await tester.enterText(find.byKey(ValueKey('crystal-uvw-$i')), v);
    }
    await tester.pump();
    await tap(tester, 'crystal-check');
    expect(verdict(tester), contains('andersherum'));
    for (final (i, v) in ['4', '-4', '2'].indexed) {
      await tester.enterText(find.byKey(ValueKey('crystal-uvw-$i')), v);
    }
    await tester.pump();
    await tap(tester, 'crystal-check');
    expect(verdict(tester), contains('gekürzt schreibt man [2 2̄ 1]'));
    await tap(tester, 'crystal-next');
    expect(results, [(grade: Grade.hard, correct: true)]);
  });

  testWidgets('Prüfungsmodus: keine Live-Anzeige, „Antwort abgeben“ wertet alle Teile', (tester) async {
    await pump(
      tester,
      const CrystalTask(
        parts: [
          CrystalPart(kind: CrystalPartKind.direction, indices: [1, 1, 1]),
          CrystalPart(kind: CrystalPartKind.readPlane, indices: [1, 1, 0]),
        ],
      ),
      examMode: true,
    );
    expect(find.byKey(const ValueKey('crystal-live')), findsNothing);
    await dot(tester, [0, 0, 0]);
    await dot(tester, [2, 2, 2]);
    expect(find.byKey(const ValueKey('crystal-calc')), findsNothing);
    await tap(tester, 'crystal-next-part');
    for (final (i, v) in ['1', '1', '0'].indexed) {
      await tester.enterText(find.byKey(ValueKey('crystal-uvw-$i')), v);
    }
    await tester.pump();
    await tap(tester, 'crystal-submit');
    expect(results, [(grade: null, correct: true)]);
  });

  testWidgets('Prüfungsmodus: ein offener Teil macht die Antwort falsch', (tester) async {
    await pump(
      tester,
      const CrystalTask(
        parts: [
          CrystalPart(kind: CrystalPartKind.direction, indices: [1, 1, 1]),
          CrystalPart(kind: CrystalPartKind.readPlane, indices: [1, 1, 0]),
        ],
      ),
      examMode: true,
    );
    await dot(tester, [0, 0, 0]);
    await dot(tester, [2, 2, 2]);
    await tap(tester, 'crystal-submit');
    expect(results, [(grade: null, correct: false)]);
  });

  testWidgets('Lösung zeigen bzw. Auflösen zählt als nicht gewusst', (tester) async {
    await pump(
      tester,
      const CrystalTask(
        parts: [
          CrystalPart(kind: CrystalPartKind.direction, indices: [-1, -1, 1]),
          CrystalPart(kind: CrystalPartKind.plane, indices: [1, 0, 0]),
        ],
      ),
      canGiveUp: true,
    );
    await tap(tester, 'crystal-reveal');
    expect(verdict(tester), contains('von (1, 1, 0) nach (0, 0, 1)'));
    await tap(tester, 'crystal-next-part');
    await tap(tester, 'question-give-up');
    expect(find.text('Aufgelöst – zählt als nicht gewusst'), findsOneWidget);
    await tap(tester, 'crystal-next');
    expect(results, [(grade: null, correct: false)]);
  });

  test('Prüfbarkeit: nur Aufgaben, die die App zeichnen kann, gelten als beantwortbar', () {
    expect(
      AnswerChecker.isAnswerable(
        _card(
          const CrystalTask(
            parts: [
              CrystalPart(kind: CrystalPartKind.plane, indices: [1, 1, 0]),
            ],
          ),
        ),
      ),
      isTrue,
    );
    expect(
      AnswerChecker.isAnswerable(
        _card(
          const CrystalTask(
            parts: [
              CrystalPart(kind: CrystalPartKind.plane, indices: [1, 2, 3]),
            ],
          ),
        ),
      ),
      isFalse,
    );
  });

  test('Lösungstext für Rückseite und Kartenliste', () {
    final text = CrystalGeometry.solutionText(
      const CrystalTask(
        parts: [
          CrystalPart(kind: CrystalPartKind.direction, indices: [1, 1, 1]),
          CrystalPart(kind: CrystalPartKind.family, indices: [1, 0, 0]),
          CrystalPart(kind: CrystalPartKind.plane, indices: [1, 1, 0]),
        ],
      ),
    );
    final lines = text.split('\n');
    expect(lines, hasLength(3));
    expect(lines[0], 'a) Richtung einzeichnen [1 1 1]: Starte bei (0, 0, 0) und gehe nach (1, 1, 1).');
    expect(lines[1], contains('6 Richtungen'));
    expect(lines[2], contains('1, 1, ∞'));
  });

  group('Editor', () {
    Future<CrystalTask?> pumpEditor(WidgetTester tester, CrystalTask task) async {
      tester.view.physicalSize = const Size(700, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      CrystalTask? changed;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CrystalTaskEditor(task: task, onChanged: (t) => changed = t),
            ),
          ),
        ),
      );
      await tester.pump();
      return changed;
    }

    testWidgets('Gitter, unsichere Indizes bestätigen, Teilaufgabe hinzufügen, Vorschau', (tester) async {
      CrystalTask? last;
      tester.view.physicalSize = const Size(700, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CrystalTaskEditor(
                task: const CrystalTask(
                  parts: [
                    CrystalPart(kind: CrystalPartKind.direction, indices: [-1, -1, 1], uncertain: true),
                  ],
                ),
                onChanged: (t) => last = t,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('crystal-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('crystal-edit-uncertain')), findsOneWidget);

      await tap(tester, 'crystal-edit-confirm');
      expect(last!.hasUncertain, isFalse);
      expect(find.byKey(const ValueKey('crystal-edit-uncertain')), findsNothing);

      await tester.tap(find.text('kfz'));
      await tester.pump();
      expect(last!.lattice, CrystalLattice.fcc);

      await tap(tester, 'crystal-edit-add');
      expect(last!.parts, hasLength(2));
      expect(find.text('Die App zeichnet und prüft alle Teilaufgaben selbst.'), findsOneWidget);
    });

    testWidgets('nicht zeichenbare Indizes werden gemeldet', (tester) async {
      await pumpEditor(
        tester,
        const CrystalTask(
          parts: [
            CrystalPart(kind: CrystalPartKind.plane, indices: [1, 2, 3]),
          ],
        ),
      );
      expect(find.text('Bitte prüfen:'), findsOneWidget);
      expect(find.textContaining('Ebene ablesen'), findsWidgets);
    });
  });
}
