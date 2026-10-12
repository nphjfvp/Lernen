import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/services/visual_math.dart';

/// So liefert die KI eine Lektion (Ableitung: Weg → Geschwindigkeit).
Map<String, dynamic> carLessonJson() => {
  'title': 'Vom Weg zur Geschwindigkeit',
  'intro': r'Ein Auto fährt nach $s(t) = 0{,}5t^2 + 2t$.',
  'variable': 't',
  'domain': [0, 10],
  'functions': [
    {'key': 's', 'label': 'Weg s(t)', 'expr': '0.5*t^2 + 2*t', 'unit': 'm'},
    {'key': 'v', 'label': 'Geschwindigkeit v(t)', 'expr': 't + 2', 'unit': 'm/s'},
    {'key': 'kaputt', 'expr': 't + a'},
  ],
  'steps': [
    {
      'title': 'Das Auto fährt',
      'text': 'Der Weg wächst immer schneller.',
      'show': {
        'car': 's',
        'plot': ['s'],
      },
    },
    {
      'title': 'Ableiten',
      'text': 'Die Steigung des Wegs ist die Geschwindigkeit.',
      'formula': r'$v(t) = \frac{ds}{dt}$',
      'show': {
        'plot': ['s', 'v', 'gibtsnicht'],
        'tangent': 's',
        'transform': [
          {'latex': r's(t) = 0{,}5t^2 + 2t', 'note': 'Ausgangspunkt'},
          r"$s'(t) = t + 2$",
        ],
      },
    },
    {
      'title': 'Strecke als Fläche',
      'show': {'area': 'v', 'car': 'v', 'carFrom': 'velocity'},
      'text': '…',
    },
  ],
  'result': {
    'title': 'Ergebnis',
    'text': 'v(t) = t + 2',
    'show': {'car': 's', 'plot': 'v'},
  },
  'exercise': {
    'front': r'Ein Auto fährt nach $s(t) = t^2$. Bestimme $v(t)$.',
    'simulate': 'velocity',
    'steps': [
      {
        'title': 'Ableiten',
        'prompt': 'v(t) = ?',
        'fields': [
          {
            'label': 'v(t) =',
            'kind': 'formula',
            'answer': '2*t',
            'variables': ['t'],
          },
        ],
      },
    ],
  },
};

void main() {
  test('Lektion aus KI-JSON: Bezüge auf unbekannte Funktionen fallen weg, toMap/fromMap', () {
    final lesson = VisualLesson.fromMap(carLessonJson(), id: 'l1', moduleId: 'm1', createdAt: DateTime(2026, 10, 11))!;
    expect(lesson.functions.map((f) => f.key), ['s', 'v', 'kaputt']);
    expect(lesson.steps, hasLength(3));
    expect(lesson.steps[1].show.plot, ['s', 'v']);
    expect(lesson.steps[1].formula, r'v(t) = \frac{ds}{dt}');
    expect(lesson.steps[1].show.transform.map((t) => t.latex), [r's(t) = 0{,}5t^2 + 2t', r"s'(t) = t + 2"]);
    expect(lesson.steps[2].show.carSource, CarSource.velocity);
    expect(lesson.result!.show.plot, ['v']);
    expect(lesson.exercise!.steps.single.fields.single.answer, '2*t');
    expect(lesson.exerciseFront, contains('Bestimme'));
    expect(lesson.simulation, ExerciseSimulation.velocity);
    expect(lesson.hasCar, isTrue);

    final back = VisualLesson.fromMap(lesson.toMap())!;
    expect(back.toMap(), lesson.toMap());
    expect(VisualLesson.fromMap({'title': 'ohne Schritte'}), isNull);
    expect(
      VisualLesson.fromMap({
        'title': 'Kurzform',
        'functions': {
          'f': 'x^2',
          'g': {'expr': '2*x', 'label': 'g(x)'},
        },
        'variable': 'x',
        'domain': [3, 1],
        'steps': [
          {
            'title': 'a',
            'show': {
              'plot': ['f', 'g'],
            },
          },
        ],
      })!.functions.map((f) => f.key),
      ['f', 'g'],
    );
  });

  test('Rechnen: Werte, Steigung, Integral, Auto über Weg oder Geschwindigkeit', () {
    final lesson = VisualMath.sanitize(VisualLesson.fromMap(carLessonJson(), createdAt: DateTime(2026))!);
    expect(lesson.functions.map((f) => f.key), ['s', 'v'], reason: '"t + a" hat eine unbekannte Größe');
    final m = VisualMath(lesson);
    expect(m.problems(), isEmpty);
    expect(m.value('s', 4), closeTo(16, 1e-9));
    expect(m.slope('s', 4), closeTo(6, 1e-6), reason: 's′(4) = v(4)');
    expect(m.integral('v', 4), closeTo(16, 1e-3), reason: '∫₀⁴ (t + 2) dt = s(4)');
    final byPosition = lesson.steps.first.show;
    final byVelocity = lesson.steps[2].show;
    expect(m.carPosition(byPosition, 6), closeTo(30, 1e-9));
    expect(m.carSpeed(byPosition, 6), closeTo(8, 1e-6));
    expect(m.carPosition(byVelocity, 6), closeTo(30, 1e-3));
    expect(m.carSpeed(byVelocity, 6), closeTo(8, 1e-9));
    final range = m.rangeOf([(t) => m.value('s', t)])!;
    expect(range.min, lessThan(0));
    expect(range.max, greaterThan(70));
    expect(VisualMath.fmt(2.5), '2,5');
    expect(VisualMath.fmt(1234.4), '1234');
    expect(VisualMath.fmt(double.nan), '–');
  });

  test('Funktionen erweitern (eigene Antwort) und Kurven nur in der Variablen', () {
    final lesson = VisualLesson.fromMap(carLessonJson(), createdAt: DateTime(2026))!;
    final derived = lesson.withFunctions(
      lesson.functions,
      extra: [const VisualFunction(key: '__deine', expr: 't^2')],
    );
    expect(derived.function('__deine')!.expr, 't^2');
    expect(derived.steps, hasLength(3));
    expect(VisualCurve.tryParse('2*t + 1', 't')!.at(3), 7);
    expect(VisualCurve.tryParse('2*x', 't'), isNull);
    expect(VisualCurve.tryParse('2*t +', 't'), isNull);
    expect(VisualCurve.tryParse('sin(t)', 't')!.slopeAt(0), closeTo(1, 1e-6));
  });

  test('Darstellung ändern: Schritt ersetzen (mit neuer Funktion), Ergebnis, Kurzfassung, ganze Lektion', () {
    final lesson = VisualLesson.fromMap(carLessonJson(), id: 'l1', moduleId: 'm1', createdAt: DateTime(2026))!;
    final step = lesson.revisedWith({
      'step': {
        'title': 'Die Rakete fliegt',
        'text': 'Statt des Autos.',
        'show': {
          'car': 's',
          'vehicle': 'rocket',
          'plot': ['s', 'h'],
        },
      },
      'functions': [
        {'key': 'h', 'label': 'Höhe', 'expr': 't^2'},
        {'key': 's', 'label': 'Weg s(t)', 'expr': '0.5*t^2 + 2*t', 'unit': 'km'},
      ],
    }, stepIndex: 0)!;
    expect(step.steps.first.title, 'Die Rakete fliegt');
    expect(step.steps.first.show.vehicle, 'rocket');
    expect(step.steps.first.show.plot, ['s', 'h']);
    expect(step.function('s')!.unit, 'km', reason: 'gleichnamige Funktion ersetzt');
    expect(step.steps[1].title, lesson.steps[1].title, reason: 'Rest bleibt');
    expect(step.exercise!.toMap(), lesson.exercise!.toMap());
    expect(step.id, 'l1');
    expect(step.vehicle, 'rocket');

    expect(
      lesson
          .revisedWith({
            'step': {'title': 'Neues Ergebnis'},
          }, stepIndex: -1)!
          .result!
          .title,
      'Neues Ergebnis',
    );
    expect(
      lesson
          .revisedWith({
            'step': {'title': 'Kurz', 'text': '• a'},
          }, stepIndex: -2)!
          .shortVersion!
          .text,
      '• a',
    );
    expect(lesson.revisedWith({'nix': 1}, stepIndex: 0), isNull);

    final whole = lesson.revisedWith({
      'lesson': {
        'title': 'Raketenstart',
        'steps': [
          {'title': 'Zündung'},
        ],
      },
    })!;
    expect(whole.title, 'Raketenstart');
    expect(whole.steps.single.title, 'Zündung');
    expect(whole.exercise, isNotNull, reason: 'ohne neue Übung bleibt die alte');
    expect(whole.simulation, lesson.simulation);
    final newExercise = lesson.revisedWith({
      'lesson': {
        'title': 'X',
        'steps': [
          {'title': 'a'},
        ],
        'exercise': {
          'front': 'Neue Aufgabe',
          'steps': [
            {
              'title': 'a',
              'fields': [
                {'label': 'x =', 'answer': '3', 'kind': 'number'},
              ],
            },
          ],
        },
      },
    })!;
    expect(newExercise.exerciseFront, 'Neue Aufgabe');
    expect(newExercise.simulation, ExerciseSimulation.graph, reason: 'alte Simulation gehört zur alten Übung');
  });
}
