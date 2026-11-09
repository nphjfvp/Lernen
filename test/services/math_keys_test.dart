import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/step_task.dart';
import 'package:lernen/services/math_keys.dart';

StepTask _task(List<Map<String, dynamic>> steps) => StepTask.fromMap({'kind': 'steps', 'steps': steps})!;

void main() {
  test('Ableitung/Integral: Funktionen, dy/dx, Striche, Integral, Differential, Konstante', () {
    final task = _task([
      {
        'title': 'Integrieren',
        'prompt': 'Integriere beide Seiten.',
        'fields': [
          {
            'label': 'y(x) =',
            'answer': 'x^2 + C',
            'variables': ['x'],
            'constants': ['C'],
          },
        ],
        'result': r'$y = x^2 + C$',
      },
      {
        'title': 'Ergebnis',
        'prompt': 'Setze ein.',
        'fields': [
          {'label': 'C =', 'kind': 'number', 'answer': '1'},
        ],
        'result': r'$C = 1$',
      },
    ]);
    final keys = MathKeys.forTask(task, text: r"Löse die DGL $y' = 2x$ mit $y(0) = 1$.");
    expect(keys.take(3), ['=', '⇒', '+']);
    expect(keys, containsAll(['y(x)', 'x', 'C', 'dy/dx', 'y′', 'y″', 'd/dx', '∫', 'dx']));
    expect(keys, isNot(contains('sin(')));
    expect(keys.toSet(), hasLength(keys.length), reason: 'keine doppelten Tasten');
  });

  test('Je nach Aufgabe: Winkelfunktionen, Logarithmus, Grenzwert, griechische Buchstaben – sonst nicht', () {
    final trig = _task([
      {
        'title': 'Winkel',
        'prompt': r'Berechne $\alpha$ aus $\sin(\alpha) = 0.5$.',
        'fields': [
          {'label': 'α =', 'kind': 'number', 'answer': 'pi/6'},
        ],
        'result': r'$\alpha = \pi/6$',
      },
    ]);
    final keys = MathKeys.forTask(trig, text: r'Bestimme den Grenzwert $\lim_{x \to \infty} \ln(x)/x$.');
    expect(keys, containsAll(['sin(', 'cos(', 'tan(', 'α', 'π', 'lim', '→', '∞', 'ln(']));

    final plain = _task([
      {
        'title': 'Abstand',
        'prompt': 'Berechne den Abstand mit der Konstante k.',
        'fields': [
          {'label': 's =', 'kind': 'number', 'answer': '12'},
        ],
        'result': r'$s = 12$',
      },
    ]);
    final few = MathKeys.forTask(plain);
    expect(few, isNot(contains('tan(')), reason: '„Abstand“/„Konstante“ sind keine Winkelfunktion');
    expect(few, isNot(contains('∫')));
    expect(few, isNot(contains('lim')));
  });
}
