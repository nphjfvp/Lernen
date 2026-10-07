import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/step_task.dart';
import 'package:lernen/services/step_checker.dart';

/// Die DGL-Aufgabe aus dem Übungsblatt: y' = 1/(x − y) + 1, y(4) = 2.
StepTask dglTask() => StepTask.fromMap({
      'steps': [
        {
          'title': 'Substitution wählen',
          'prompt': 'Welche Substitution macht die DGL lösbar?',
          'options': [
            {'text': r'$u = x - y$', 'correct': true},
            {'text': r'$u = y/x$', 'feedback': "Das hilft bei y' = f(y/x) – hier steht x − y."},
            {'text': r"$u = y'$", 'feedback': 'Damit wird es nicht einfacher.'},
          ],
          'hints': ['Was steht im Nenner?', 'Setze den Nenner als neue Größe.'],
        },
        {
          'title': "u' bestimmen",
          'fields': [
            {
              'label': r"$u' =$",
              'answer': '-1/u',
              'variables': ['u'],
              'mistakes': [
                {'answer': '1/u', 'feedback': 'Das Minus vor der Klammer gilt für beide Summanden.'}
              ],
            }
          ],
        },
        {
          'title': 'Trennen und integrieren',
          'fields': [
            {
              'label': r'$u^2 =$',
              'answer': '-2x + C',
              'variables': ['x'],
              'constants': ['C'],
              'mistakes': [
                {'answer': '-x + C', 'feedback': 'Beim Auflösen von ½u² fehlt der Faktor 2.'}
              ],
            }
          ],
        },
        {
          'title': 'Anfangsbedingung',
          'fields': [
            {'label': r'$u(4) =$', 'kind': 'number', 'answer': '2'},
            {'label': r'$C =$', 'kind': 'zahl', 'answer': '12'},
          ],
        },
        {
          'title': 'Zurück zu y',
          'fields': [
            {
              'label': r'$y(x) =$',
              'answer': 'x - sqrt(12 - 2x)',
              'variables': ['x'],
              'mistakes': [
                {'answer': 'x + sqrt(12 - 2x)', 'feedback': 'u(4) = 2 ist positiv – also die positive Wurzel für u.'}
              ],
            }
          ],
        },
      ],
      'probe': {
        'kind': 'ode',
        'equation': '1/(x - y) + 1',
        'conditions': [
          {'x': 4, 'value': 2}
        ],
      },
      'domainNote': 'für x < 6',
    })!;

void main() {
  late StepTask task;
  setUp(() => task = dglTask());

  group('StepTask lesen', () {
    test('Schritte, Felder, Probe und Endergebnis', () {
      expect(task.steps, hasLength(5));
      expect(task.steps.first.isChoice, isTrue);
      expect(task.steps.first.hints, hasLength(2));
      expect(task.steps[3].fields.map((f) => f.kind), [StepFieldKind.number, StepFieldKind.number]);
      expect(task.finalField!.answer, 'x - sqrt(12 - 2x)');
      expect(task.probe!.conditions.single.value, 2);
      expect(task.isUsable, isTrue);
    });

    test('Speichern und wieder lesen ändert nichts', () {
      final again = StepTask.fromMap(task.toMap())!;
      expect(again.toMap(), task.toMap());
      expect(task.toMap()['kind'], 'steps');
    });

    test('tolerant: Feld direkt am Schritt, richtige Option als Index, deutsche Schlüssel', () {
      final t = StepTask.fromMap({
        'schritte': [
          {'titel': 'A', 'answer': '2x', 'label': "f'(x) ="},
          {
            'frage': 'Welche?',
            'choices': ['eins', 'zwei'],
            'correctIndex': 1,
          },
          {'title': 'leer'},
        ],
        'probe': {'type': 'Stammfunktion', 'integrand': '2x'},
      })!;
      expect(t.steps, hasLength(2));
      expect(t.steps[0].fields.single.answer, '2x');
      expect(t.steps[1].options.map((o) => o.correct), [false, true]);
      expect(t.probe!.kind, StepProbeKind.antiderivative);
    });

    test('ohne brauchbaren Schritt null', () {
      expect(StepTask.fromMap({'steps': []}), isNull);
      expect(StepTask.fromMap('kaputt'), isNull);
    });
  });

  group('Formeln prüfen', () {
    StepField field(int step, [int i = 0]) => task.steps[step].fields[i];

    test("u' = -1/u in jeder gleichwertigen Schreibweise", () {
      for (final input in ['-1/u', '−1/u', '-(1/u)', '-u^-1', "u' = -1/u", r'\frac{-1}{u}', '-1:u']) {
        expect(StepChecker.check(field(1), input).isCorrect, isTrue, reason: input);
      }
    });

    test('typischer Fehler bekommt seine Rückmeldung', () {
      final v = StepChecker.check(field(1), '1/u');
      expect(v.kind, FieldVerdictKind.mistake);
      expect(v.message, contains('Minus vor der Klammer'));
      expect(v.isAttempt, isTrue);
    });

    test('falsche, leere und unlesbare Eingaben', () {
      expect(StepChecker.check(field(1), '1 - 1/u').kind, FieldVerdictKind.wrong);
      expect(StepChecker.check(field(1), '').kind, FieldVerdictKind.empty);
      final unknown = StepChecker.check(field(1), '1/(x - y)');
      expect(unknown.kind, FieldVerdictKind.invalid);
      expect(unknown.message, contains('kommen hier nicht vor'));
      expect(unknown.message, contains('u'));
      expect(StepChecker.check(field(1), '(-1').kind, FieldVerdictKind.invalid);
      expect(StepChecker.check(field(1), '(-1').isAttempt, isFalse);
    });

    test('Integrationskonstante: jede Schreibweise der Lösungsschar', () {
      for (final input in ['-2x + C', 'C - 2x', '2(K - x)', '2C - 2x', '-2(x - C)']) {
        expect(StepChecker.check(field(2), input).isCorrect, isTrue, reason: input);
      }
    });

    test('Konstante vergessen, typischer Fehler, falsche Schar', () {
      final missing = StepChecker.check(field(2), '-2x');
      expect(missing.kind, FieldVerdictKind.wrong);
      expect(missing.message, contains('Konstante C fehlt'));
      expect(StepChecker.check(field(2), '-x + C').kind, FieldVerdictKind.mistake);
      expect(StepChecker.check(field(2), '2x + C').kind, FieldVerdictKind.wrong);
      expect(StepChecker.check(field(2), 'x^2 + C').kind, FieldVerdictKind.wrong);
    });

    test('Endergebnis: Umformungen zählen, Vorzeichenfehler der Wurzel nicht', () {
      for (final input in ['x - √(12 - 2x)', 'x - sqrt(2(6 - x))', 'x-(12-2x)^(1/2)', 'y = x - sqrt(12-2x)']) {
        expect(StepChecker.check(field(4), input).isCorrect, isTrue, reason: input);
      }
      expect(StepChecker.check(field(4), 'x + sqrt(12 - 2x)').kind, FieldVerdictKind.mistake);
    });

    test('Vorschau der Eingabe', () {
      expect(StepChecker.preview(field(4), 'x - sqrt(12 - 2x)'), r'x - \sqrt{12 - 2x}');
      expect(StepChecker.preview(field(4), '(('), isNull);
      expect(StepChecker.preview(field(4), ''), isNull);
    });

    test('erkennt Vorzeichen-, Faktor- und Konstantenfehler selbst', () {
      const f = StepField(label: "f'(x) =", answer: '3x^2', variables: ['x']);
      expect(StepChecker.check(f, '-3x^2').message, contains('Vorzeichen'));
      expect(StepChecker.check(f, '6x^2').message, contains('Faktor'));
      expect(StepChecker.check(f, '3x^2 + 1').message, contains('Konstante'));
      expect(StepChecker.check(f, 'x^3').message, 'Das stimmt noch nicht.');
    });
  });

  group('Zahlen prüfen', () {
    test('exakt, als Rechnung, mit Komma', () {
      final c = task.steps[3].fields[1];
      for (final input in ['12', '12,0', '24/2', 'C = 12', '1,2e1']) {
        expect(StepChecker.check(c, input).isCorrect, isTrue, reason: input);
      }
      expect(StepChecker.check(c, '11').kind, FieldVerdictKind.wrong);
      expect(StepChecker.check(c, '-12').message, contains('Vorzeichen'));
      expect(StepChecker.check(c, '12x').kind, FieldVerdictKind.invalid);
    });

    test('richtig gerundet zählt, zu grob nicht', () {
      const pd = StepField(label: 'PD =', answer: 'pi*sqrt(3)/8', kind: StepFieldKind.number);
      expect(StepChecker.check(pd, '0,68').message, contains('gerundet'));
      expect(StepChecker.check(pd, '0,6802').isCorrect, isTrue);
      expect(StepChecker.check(pd, 'pi*sqrt(3)/8').isCorrect, isTrue);
      expect(StepChecker.check(pd, '0,7').message, contains('Zu grob'));
      expect(StepChecker.check(pd, '0,69').kind, FieldVerdictKind.wrong);
    });

    test('sehr kleine Zahlen: relativ geprüft, nicht alle „gleich“ (Diffusionskoeffizient)', () {
      const d = StepField(
        label: 'D =',
        answer: '8.63*10^-9',
        kind: StepFieldKind.number,
        tolerance: 0.01,
        mistakes: [StepMistake(answer: '-8.63*10^-9', feedback: 'Vorzeichen im Exponenten')],
      );
      expect(StepChecker.check(d, '8.63*10^-9').isCorrect, isTrue);
      expect(StepChecker.check(d, '8,6*10^-9').isCorrect, isTrue);
      expect(StepChecker.check(d, '0').isCorrect, isFalse);
      expect(StepChecker.check(d, '5.79*10^-13').isCorrect, isFalse);
      expect(StepChecker.check(d, '2.62*10^-7').isCorrect, isFalse);
      expect(StepChecker.check(d, '-8.63*10^-9').kind, FieldVerdictKind.mistake);
      // Die Nachprüfung meldet die typischen Fehler nicht mehr als „in Wahrheit richtig“.
      final task = StepTask(steps: [
        TaskStep(title: 'Exponentialterm', fields: [d]),
      ]);
      expect(StepChecker.verify(task).problems.where((p) => p.contains('in Wahrheit richtig')), isEmpty);
      // Gerundet in Zehnerpotenz-Schreibweise.
      const exact = StepField(label: 'D =', answer: '0.67*exp(-18.57)', kind: StepFieldKind.number);
      expect(StepChecker.check(exact, '5.8*10^-9').message, contains('gerundet'));
      expect(StepChecker.check(exact, '6*10^-9').message, contains('Zu grob'));
    });

    test('Toleranz aus der Aufgabe', () {
      const v = StepField(label: 'v =', answer: '12.5', kind: StepFieldKind.number, tolerance: 0.01);
      expect(StepChecker.check(v, '12,4').isCorrect, isTrue);
      expect(StepChecker.check(v, '12,2').isCorrect, isFalse);
    });
  });

  group('Auswahl', () {
    test('richtige und falsche Option', () {
      final step = task.steps.first;
      expect(StepChecker.checkOption(step, 0).isCorrect, isTrue);
      final wrong = StepChecker.checkOption(step, 1);
      expect(wrong.kind, FieldVerdictKind.mistake);
      expect(wrong.message, contains('x − y'));
      expect(StepChecker.checkOption(step, 7).kind, FieldVerdictKind.empty);
    });
  });

  group('Probe', () {
    test('richtiges Ergebnis erfüllt Anfangswert und DGL', () {
      final report = StepChecker.probe(task, 'x - sqrt(12 - 2x)')!;
      expect(report.passed, isTrue);
      expect(report.rows.first.label, contains('Anfangswert y(4) = 2'));
      expect(report.rows.where((r) => r.label.startsWith('DGL')), hasLength(3));
    });

    test('Folgefehler vom Papier: Anfangswert stimmt, DGL nicht', () {
      final report = StepChecker.probe(task, 'x - sqrt(2x - 4)')!;
      expect(report.passed, isFalse);
      expect(report.rows.first.ok, isTrue);
      expect(report.rows.where((r) => !r.ok), isNotEmpty);
      expect(report.rows.firstWhere((r) => !r.ok).detail, contains('≠'));
    });

    test('unlesbares Ergebnis und Aufgabe ohne Probe', () {
      expect(StepChecker.probe(task, '((')!.note, contains('nicht lesbar'));
      expect(StepChecker.probe(task.copyWith(), 'x') != null, isTrue);
      expect(StepChecker.probe(StepTask(steps: task.steps), 'x'), isNull);
    });

    test('Stammfunktion und DGL 2. Ordnung', () {
      const anti = StepProbe(kind: StepProbeKind.antiderivative, equation: '2x');
      expect(StepChecker.runProbe(anti, 'x^2 + C', constants: ['C']).passed, isTrue);
      expect(StepChecker.runProbe(anti, 'x^2/2').passed, isFalse);
      const osc = StepProbe(kind: StepProbeKind.ode, equation: '-y', order: 2, conditions: [
        ProbeCondition(x: 0, value: 0),
        ProbeCondition(x: 0, value: 1, derivative: 1),
      ]);
      expect(StepChecker.runProbe(osc, 'sin(x)').passed, isTrue);
      expect(StepChecker.runProbe(osc, 'cos(x)').passed, isFalse);
    });
  });

  group('Musterlösung nachrechnen', () {
    test('die DGL-Aufgabe ist in Ordnung', () {
      final check = StepChecker.verify(task);
      expect(check.problems, isEmpty);
      expect(check.probe!.passed, isTrue);
      expect(check.ok, isTrue);
    });

    test('falsche Musterlösung fällt in der Probe auf', () {
      final steps = [...task.steps];
      steps[4] = steps[4].copyWith(fields: [steps[4].fields.single.copyWith(answer: 'x - sqrt(2x - 4)', mistakes: const [])]);
      final check = StepChecker.verify(task.copyWith(steps: steps));
      expect(check.probe!.passed, isFalse);
      expect(check.ok, isFalse);
    });

    test('unlesbare Antwort, richtiger "Fehler", Auswahl ohne Lösung', () {
      final steps = [...task.steps];
      steps[0] = steps[0].copyWith(options: [for (final o in steps[0].options) StepOption(text: o.text)]);
      steps[1] = steps[1].copyWith(fields: [
        steps[1].fields.single.copyWith(mistakes: const [StepMistake(answer: '-u^(-1)', feedback: 'x')]),
      ]);
      steps[3] = steps[3].copyWith(fields: [steps[3].fields.first.copyWith(answer: '((')]);
      final problems = StepChecker.verify(task.copyWith(steps: steps)).problems;
      expect(problems, hasLength(3));
      expect(problems[0], contains('Schritt 1'));
      expect(problems[1], contains('in Wahrheit richtig'));
      expect(problems[2], contains('nicht lesbar'));
    });
  });
}
