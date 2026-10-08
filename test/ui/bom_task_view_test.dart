import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/bom_task.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/answer_checker.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/tasks/bom_task_editor.dart';
import 'package:lernen/ui/tasks/bom_task_view.dart';

/// 10 Tisch: 4× 20 Bein, 2× 30 Platte (2× 40 Brett, 8× 50 Schraube).
/// Knoten im Baum (Reihenfolge von links nach unten): 0 = 10, 1 = 20, 2 = 30, 3 = 40, 4 = 50.
BomTask _task(List<BomListKind> kinds) => BomTask(
  parts: [for (final k in kinds) BomPart(kind: k)],
  root: const BomNode(
    number: '10',
    name: 'Tisch',
    children: [
      BomNode(number: '20', name: 'Bein', quantity: 4),
      BomNode(
        number: '30',
        name: 'Platte',
        quantity: 2,
        children: [
          BomNode(number: '40', name: 'Brett', quantity: 2),
          BomNode(number: '50', name: 'Schraube', quantity: 8),
        ],
      ),
    ],
  ),
);

Flashcard _card(BomTask task) => Flashcard(
  id: 'b1',
  moduleId: 'm1',
  front: 'Erstellen Sie die Stückliste zum Tisch.',
  back: '',
  createdAt: DateTime(2026, 1, 1),
  due: DateTime(2026, 1, 1),
  type: QuestionType.bom,
  taskData: task.toMap(),
);

void main() {
  late List<({Grade? grade, bool? correct})> results;

  Future<void> pump(WidgetTester tester, BomTask task, {bool examMode = false, bool viaQuestionView = false}) async {
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
              : BomTaskView(card: card, task: task, isNew: false, examMode: examMode, onComplete: done),
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

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pump();
  }

  Future<void> pick(WidgetTester tester, String key, String item) async {
    await tap(tester, key);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(item).last);
    await tester.pump(const Duration(milliseconds: 400));
  }

  String text(WidgetTester tester, String key) {
    final widget = tester.widget(find.byKey(ValueKey(key)));
    if (widget is Text) return widget.data ?? '';
    return tester
        .widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .join(' ');
  }

  testWidgets('Strukturstückliste: Teile im Baum antippen, je Zeile Rückmeldung, dann gelöst', (tester) async {
    await pump(tester, _task(const [BomListKind.structure]));
    expect(find.byKey(const ValueKey('bom-tree')), findsOneWidget);
    for (final node in [1, 2, 3, 4]) {
      await tap(tester, 'bom-node-$node');
    }
    expect(find.byKey(const ValueKey('bom-row-3')), findsOneWidget);
    for (final (i, (level, qty)) in const [('1', '4'), ('1', '2'), ('2', '2'), ('2', '16')].indexed) {
      await type(tester, 'bom-row-$i-level', level);
      await type(tester, 'bom-row-$i-qty', qty);
    }
    await tap(tester, 'bom-check');
    expect(text(tester, 'bom-verdict'), contains('1 Zeile stimmt nicht'));
    expect(text(tester, 'bom-row-3-error'), contains('nicht die Gesamtmenge'));
    expect(find.byKey(const ValueKey('bom-row-0-error')), findsNothing);

    await type(tester, 'bom-row-3-qty', '8');
    expect(find.byKey(const ValueKey('bom-verdict')), findsNothing);
    await tap(tester, 'bom-check');
    expect(text(tester, 'bom-verdict'), contains('Alles richtig'));
    expect(text(tester, 'bom-finished'), contains('mit Hilfe'));
    await tap(tester, 'bom-next');
    expect(results.single.correct, isTrue);
    expect(results.single.grade, Grade.hard);
  });

  testWidgets('Baukasten: Listen anlegen, AK wählen, Liste für ein Teil und fehlende Liste werden gemeldet', (
    tester,
  ) async {
    await pump(tester, _task(const [BomListKind.modular]));
    await tap(tester, 'bom-node-1');
    expect(find.text('Lege zuerst eine Liste an („Liste anlegen“), dann Teile antippen.'), findsOneWidget);

    await pick(tester, 'bom-add-list', '10 Tisch');
    expect(find.byKey(const ValueKey('bom-list-10')), findsOneWidget);
    await tap(tester, 'bom-node-1');
    await tap(tester, 'bom-node-2');
    await type(tester, 'bom-10-row-0-qty', '4');
    await tap(tester, 'bom-10-row-0-ak-2');
    await type(tester, 'bom-10-row-1-qty', '2');
    await tap(tester, 'bom-10-row-1-ak-2');
    await pick(tester, 'bom-add-list', '40 Brett');

    await tap(tester, 'bom-check');
    expect(find.byKey(const ValueKey('bom-10-row-0-error')), findsNothing);
    expect(text(tester, 'bom-10-row-1-error'), contains('AK 1'));
    expect(text(tester, 'bom-list-40-error'), contains('keine eigene Stückliste'));
    expect(text(tester, 'bom-verdict'), contains('fehlt noch 1 Liste'));

    await tap(tester, 'bom-list-40-remove');
    expect(find.byKey(const ValueKey('bom-list-40')), findsNothing);
    await tap(tester, 'bom-hint-button');
    await tap(tester, 'bom-hint-button');
    await tap(tester, 'bom-hint-button');
    expect(text(tester, 'bom-hint-2'), contains('10 Tisch, 30 Platte'));
  });

  testWidgets('Lösung zeigen: Musterlösung als Tabelle, zählt als nicht gewusst', (tester) async {
    await pump(tester, _task(const [BomListKind.overview, BomListKind.structure]));
    expect(find.byKey(const ValueKey('bom-part-1')), findsOneWidget);
    await tap(tester, 'bom-reveal');
    expect(find.byKey(const ValueKey('bom-solution')), findsOneWidget);
    expect(find.text('Mengenübersichtsstückliste'), findsOneWidget);
    expect(find.text('16'), findsOneWidget); // 2 × 8 Schrauben
    await tap(tester, 'bom-next-part');
    await tap(tester, 'bom-reveal');
    await tap(tester, 'bom-next');
    expect(results.single.correct, isFalse);
  });

  testWidgets('Probeklausur: keine Rückmeldung, Abgeben wertet', (tester) async {
    await pump(tester, _task(const [BomListKind.overview]), examMode: true);
    for (final node in [1, 2, 3, 4]) {
      await tap(tester, 'bom-node-$node');
    }
    for (final (i, qty) in const ['4', '2', '4', '16'].indexed) {
      await type(tester, 'bom-row-$i-qty', qty);
    }
    expect(find.byKey(const ValueKey('bom-check')), findsNothing);
    await tap(tester, 'bom-submit');
    expect(find.byKey(const ValueKey('bom-verdict')), findsNothing);
    expect(results.single.correct, isTrue);
  });

  testWidgets('QuestionAnswerView zeigt Stücklisten-Karten als Stückliste', (tester) async {
    final task = _task(const [BomListKind.structure]);
    expect(AnswerChecker.isAnswerable(_card(task)), isTrue);
    await pump(tester, task, viaQuestionView: true);
    expect(find.byType(BomTaskView), findsOneWidget);
  });

  test('KI-Eintrag mit Erzeugnisbaum wird zur Stückliste', () {
    final entry = QuestionParsing.normalizeGeneratedFlashcard({
      'type': 'Stückliste',
      'front': 'Erstellen Sie die Strukturstückliste.',
      'root': {
        'nr': '10',
        'children': [
          {'nr': '20', 'qty': 2},
        ],
      },
      'parts': [
        {'list': 'structure'},
      ],
    })!;
    expect(QuestionParsing.parseType(entry['type'] as String?), QuestionType.bom);
    expect(BomTask.fromMap(entry['taskData'])!.root.children.single.quantity, 2);
  });

  testWidgets('Editor: Baum als Text, Fehler mit Zeile, Listen wählen, Vorschau', (tester) async {
    var task = _task(const [BomListKind.structure]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: BomTaskEditor(task: task, onChanged: (t) => setState(() => task = t)),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('bom-preview')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('bom-edit-outline')), '0; 10; Tisch\n2; 20; Bein');
    await tester.pump();
    expect(find.textContaining('Zeile 2'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('bom-edit-outline')),
      '0; 10; Tisch\n1; 20; Bein; 4\n1; 30; Platte; 3; kg',
    );
    await tester.pump();
    expect(task.root.children.map((c) => c.number), ['20', '30']);
    expect(task.root.children.last.unit, 'kg');

    await tester.tap(find.byKey(const ValueKey('bom-edit-kind-modular')));
    await tester.pump();
    expect(task.parts.map((p) => p.kind), [BomListKind.structure, BomListKind.modular]);
    await tester.enterText(find.byKey(const ValueKey('bom-edit-lists')), '10, 30');
    await tester.pump();
    expect(task.parts.last.lists, ['10', '30']);
    await tester.tap(find.byKey(const ValueKey('bom-edit-totals')));
    await tester.pump();
    expect(task.parts.first.totals, isTrue);
  });
}
