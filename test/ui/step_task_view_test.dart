import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/step_task.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';

/// y' = 2x mit y(0) = 1: Methode wählen, integrieren, Konstante bestimmen,
/// Ergebnis. Die Probe rechnet die App (DGL + Anfangswert).
Map<String, dynamic> _taskData() => {
      'kind': 'steps',
      'steps': [
        {
          'title': 'Methode wählen',
          'prompt': 'Wie kommst du von y\' auf y?',
          'options': [
            {'text': 'Integrieren', 'correct': true},
            {'text': 'Ableiten', 'correct': false, 'feedback': 'Ableiten macht aus y\' nur y\'\' – du willst zurück zu y.'},
          ],
          'hints': ['Was ist die Umkehrung des Ableitens?'],
          'result': 'Integrieren',
        },
        {
          'title': 'Integrieren',
          'prompt': 'Integriere beide Seiten.',
          'fields': [
            {
              'label': 'y(x) =',
              'answer': 'x^2 + C',
              'variables': ['x'],
              'constants': ['C'],
              'mistakes': [
                {'answer': '2*x^2 + C', 'feedback': 'Prüf den Vorfaktor: Welche Funktion hat die Ableitung 2x?'},
              ],
            },
          ],
          'hints': ['Welche Funktion hat die Ableitung 2x?', 'Potenzregel rückwärts: (x²)\' = 2x.'],
          'result': r'$y = x^2 + C$',
        },
        {
          'title': 'Konstante bestimmen',
          'prompt': 'Setze y(0) = 1 ein.',
          'fields': [
            {'label': 'C =', 'kind': 'number', 'answer': '1'},
          ],
          'result': r'$C = 1$',
        },
        {
          'title': 'Ergebnis',
          'prompt': 'Schreibe die Lösung hin.',
          'fields': [
            {'label': 'y(x) =', 'answer': 'x^2 + 1', 'variables': ['x']},
          ],
          'result': r'$y = x^2 + 1$',
        },
      ],
      'probe': {
        'kind': 'ode',
        'equation': '2*x',
        'conditions': [
          {'x': 0, 'value': 1},
        ],
      },
    };

Flashcard _card() => Flashcard(
      id: 's1',
      moduleId: 'm1',
      front: r"Löse $y' = 2x$ mit $y(0) = 1$.",
      back: r'$y = x^2 + 1$',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      type: QuestionType.steps,
      taskData: _taskData(),
    );

void main() {
  late List<({Grade? grade, bool? correct})> results;

  Future<void> pump(WidgetTester tester, {bool examMode = false, bool canGiveUp = false}) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    results = [];
    final card = _card();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: QuestionAnswerView(
                key: ValueKey(card.id),
                card: card,
                isNew: false,
                examMode: examMode,
                canGiveUp: canGiveUp,
                onComplete: ({Grade? selfGrade, bool? isCorrect}) => results.add((grade: selfGrade, correct: isCorrect)),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  test('Testaufgabe ist vollständig und die Musterlösung besteht die Probe', () {
    final task = StepTask.fromMap(_taskData())!;
    expect(task.isUsable, isTrue);
    expect(task.steps, hasLength(4));
    expect(task.finalField!.answer, 'x^2 + 1');
  });

  testWidgets('Schritt für Schritt ohne Fehler: gewusst', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('step-mode')), findsOneWidget);
    expect(find.byKey(const ValueKey('step-active-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('step-locked-1')), findsOneWidget);

    await tap(tester, 'step-option-0-0');
    await tap(tester, 'step-check-0');
    expect(find.byKey(const ValueKey('step-done-0')), findsOneWidget);

    // Andere, gleichwertige Schreibweise der Lösungsschar zählt.
    await enter(tester, 'step-input-1-0', 'C + x*x');
    await tap(tester, 'step-check-1');
    expect(find.byKey(const ValueKey('step-done-1')), findsOneWidget);

    await enter(tester, 'step-input-2-0', '1');
    await tap(tester, 'step-check-2');
    await enter(tester, 'step-input-3-0', '1 + x^2');
    await tap(tester, 'step-check-3');

    expect(find.byKey(const ValueKey('step-finished')), findsOneWidget);
    expect(find.text('Gelöst – ohne Hilfe'), findsOneWidget);
    expect(find.byKey(const ValueKey('step-probe')), findsOneWidget); // Probe der Musterlösung

    await tap(tester, 'step-next');
    expect(results, [(grade: null, correct: true)]);
  });

  testWidgets('falsche Auswahl und typischer Fehler: eigene Rückmeldung, Tipps, am Ende Schwer', (tester) async {
    await pump(tester);
    await tap(tester, 'step-option-0-1');
    await tap(tester, 'step-check-0');
    expect(find.textContaining('Ableiten macht aus'), findsOneWidget);
    expect(find.byKey(const ValueKey('step-active-0')), findsOneWidget);

    await tap(tester, 'step-option-0-0');
    await tap(tester, 'step-check-0');

    await enter(tester, 'step-input-1-0', '2*x^2 + C');
    await tap(tester, 'step-check-1');
    expect(find.textContaining('Prüf den Vorfaktor'), findsOneWidget);

    // Ohne Konstante: die App erkennt das selbst.
    await enter(tester, 'step-input-1-0', 'x^2');
    await tap(tester, 'step-check-1');
    expect(find.textContaining('Die Konstante C fehlt'), findsOneWidget);

    await tap(tester, 'step-hint-button-1');
    expect(find.byKey(const ValueKey('step-hint-1-0')), findsOneWidget);

    await enter(tester, 'step-input-1-0', 'x^2 + C');
    await tap(tester, 'step-check-1');
    await enter(tester, 'step-input-2-0', '1');
    await tap(tester, 'step-check-2');
    await enter(tester, 'step-input-3-0', 'x^2 + 1');
    await tap(tester, 'step-check-3');

    expect(find.text('Gelöst – mit Hilfe'), findsOneWidget);
    expect(find.textContaining('3 Fehlversuche'), findsOneWidget);
    await tap(tester, 'step-next');
    expect(results, [(grade: Grade.hard, correct: true)]);
  });

  testWidgets('Schritt zeigen zählt als nicht gewusst', (tester) async {
    await pump(tester);
    await tap(tester, 'step-option-0-0');
    await tap(tester, 'step-check-0');
    await enter(tester, 'step-input-1-0', 'x');
    await tap(tester, 'step-check-1');
    await tap(tester, 'step-reveal-1');
    expect(find.textContaining('aufgedeckt'), findsOneWidget);

    await enter(tester, 'step-input-2-0', '1');
    await tap(tester, 'step-check-2');
    await enter(tester, 'step-input-3-0', 'x^2 + 1');
    await tap(tester, 'step-check-3');
    expect(find.text('Mit aufgedecktem Schritt gelöst'), findsOneWidget);
    await tap(tester, 'step-next');
    expect(results, [(grade: null, correct: false)]);
  });

  testWidgets('Nur Ergebnis: falsches Ergebnis zeigt die Probe, richtiges löst', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Nur Ergebnis'));
    await tester.pump();

    await enter(tester, 'step-result-input', 'x^2 + 2');
    await tap(tester, 'step-result-check');
    // Die DGL stimmt, der Anfangswert nicht – das zeigt die Probe.
    expect(find.byKey(const ValueKey('step-probe')), findsOneWidget);
    expect(find.textContaining('Anfangswert'), findsWidgets);
    expect(find.byKey(const ValueKey('step-result-reveal')), findsOneWidget);

    await enter(tester, 'step-result-input', 'x^2 + 1');
    await tap(tester, 'step-result-check');
    expect(find.byKey(const ValueKey('step-finished')), findsOneWidget);
    await tap(tester, 'step-next');
    expect(results, [(grade: Grade.hard, correct: true)]);
  });

  testWidgets('Probeklausur: nur das Ergebnis, ohne Rückmeldung, sofort abgegeben', (tester) async {
    await pump(tester, examMode: true);
    expect(find.byKey(const ValueKey('step-mode')), findsNothing);
    expect(find.byKey(const ValueKey('step-hint-button-0')), findsNothing);
    await enter(tester, 'step-result-input', '1 + x^2');
    await tap(tester, 'step-result-check');
    expect(results, [(grade: null, correct: true)]);
    expect(find.byKey(const ValueKey('step-probe')), findsNothing);
  });

  testWidgets('Auflösen deckt alle Schritte auf und wertet als falsch', (tester) async {
    await pump(tester, canGiveUp: true);
    await tap(tester, 'question-give-up');
    expect(find.text('Aufgelöst – zählt als nicht gewusst'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('step-done-$i')), findsOneWidget);
    }
    await tap(tester, 'step-next');
    expect(results, [(grade: null, correct: false)]);
  });

  testWidgets('Rechenweg ohne Schritte fällt auf die Karteikarten-Ansicht zurück', (tester) async {
    final card = _card().copyWithContent(taskData: const {'kind': 'steps', 'steps': []});
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Column(
          children: [
            Expanded(child: QuestionAnswerView(card: card, isNew: false, onComplete: ({Grade? selfGrade, bool? isCorrect}) {})),
          ],
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('step-mode')), findsNothing);
  });
}
