import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_diagram.dart';
import 'package:lernen/models/visual_lesson.dart';

/// Wärmeausdehnung: Atome im Gitter schwingen stärker und rücken auseinander.
Map<String, dynamic> latticeScene() => {
  'width': 100,
  'height': 60,
  'seconds': 8,
  'param': {'name': 'Temperatur', 'unit': '°C', 'from': 20, 'to': 820},
  'captions': [
    {'at': 0, 'text': 'Kalt: Atome schwingen kaum.'},
    {'at': 0.5, 'text': r'Warm: größerer Abstand $a$.'},
  ],
  'elements': [
    {
      'type': 'circle',
      'x': 10,
      'y': 10,
      'r': 3,
      'fill': 'accent',
      'text': 'Fe',
      'repeat': {'nx': 6, 'ny': 4, 'dx': 12, 'dy': 12},
      'keys': [
        {'at': 1, 'r': 3.5, 'fill': 'red'},
      ],
    },
    {
      'type': 'arrow',
      'x1': 10,
      'y1': 55,
      'x2': 22,
      'y2': 55,
      'stroke': 'ink',
      'text': 'a',
      'keys': [
        {'at': 1, 'x2': 25},
      ],
    },
    {
      'type': 'path',
      'points': [
        [0, 50],
        [50, 30],
        [100, 10],
      ],
      'keys': [
        {'at': 0.5, 'draw': 1},
      ],
      'draw': 0,
    },
    {'type': 'text', 'x': 50, 'y': 3, 'text': 'Gitter'},
    {'type': 'kaputt', 'x': 1},
    {'type': 'line', 'x1': 0},
    {'type': 'text', 'x': 1, 'y': 1},
  ],
};

void main() {
  test('Szene aus KI-JSON: Formen, Raster, ungültige fallen weg, toMap/fromMap', () {
    final d = VisualDiagram.fromMap(latticeScene())!;
    expect(d.elements.map((e) => e.shape), [
      DiagramShape.circle,
      DiagramShape.arrow,
      DiagramShape.path,
      DiagramShape.text,
    ]);
    expect(d.elements.first.copies, 24);
    expect(d.seconds, 8);
    expect(d.hasParam, isTrue);
    expect(VisualDiagram.fromMap(d.toMap())!.toMap(), d.toMap());
    expect(VisualDiagram.fromMap({'elements': []}), isNull);
    expect(VisualDiagram.fromMap('kaputt'), isNull);
  });

  test('Schlüsselbilder: Zahlen, Punkte, Farben, Text, Beschriftung und Größe linear über die Zeit', () {
    final d = VisualDiagram.fromMap(latticeScene())!;
    final atom = d.elements.first;
    expect(atom.number('r', 0), 3);
    expect(atom.number('r', 0.5), closeTo(3.25, 1e-9));
    expect(atom.number('r', 1), 3.5);
    expect(atom.number('x', 0.7), 10, reason: 'ohne Schlüsselbild bleibt der Grundwert');
    expect(atom.number('opacity', 0.5), isNull);
    expect(atom.colorAt('fill', 0.25), ('accent', 'red', 0.25));
    expect(atom.colorAt('stroke', 0.25), isNull);

    final path = d.elements[2];
    expect(path.number('draw', 0), 0);
    expect(path.number('draw', 0.25), closeTo(0.5, 1e-9));
    expect(path.number('draw', 0.9), 1);

    expect(d.captionAt(0.2), 'Kalt: Atome schwingen kaum.');
    expect(d.captionAt(0.6), contains('größerer Abstand'));
    expect(d.paramAt(0.5), 420);

    final moving = DiagramElement.fromMap({
      'type': 'polygon',
      'points': [
        [0, 0],
        [10, 0],
        [10, 10],
      ],
      'text': 'klein',
      'keys': [
        {
          'at': 1,
          'text': 'groß',
          'points': [
            [0, 0],
            [20, 0],
            [20, 20],
          ],
        },
      ],
    })!;
    expect(moving.pointsAt(0.5)[1], [15, 0]);
    expect(moving.textAt(0.5), 'klein');
    expect(moving.textAt(1), 'groß');
  });

  test('Obergrenze für Formen und Szene im Schritt einer Lektion', () {
    final many = VisualDiagram.fromMap({
      'elements': [
        for (var i = 0; i < 3; i++)
          {
            'type': 'circle',
            'x': 1,
            'y': 1,
            'repeat': {'nx': 30, 'ny': 10},
          },
      ],
    })!;
    expect(many.elements.length, 2, reason: 'höchstens ${VisualDiagram.maxShapes} Formen');

    final lesson = VisualLesson.fromMap({
      'title': 'Wärmeausdehnung',
      'steps': [
        {
          'title': 'Atome schwingen',
          'show': {'scene': latticeScene()},
        },
      ],
    })!;
    expect(lesson.functions, isEmpty);
    expect(lesson.steps.single.show.scene!.elements, hasLength(4));
    expect(lesson.steps.single.show.isEmpty, isFalse);
    expect(
      VisualLesson.fromMap(lesson.toMap())!.steps.single.show.scene!.toMap(),
      lesson.steps.single.show.scene!.toMap(),
    );
  });

  test('Abweichungen der KI: pos/size/from-to, square/triangle, Gruppen, objects, NaN', () {
    final d = VisualDiagram.fromMap({
      'objects': [
        {
          'type': 'square',
          'pos': [10, 10],
          'size': [20, 20],
          'width': 1,
        },
        {'type': 'rect', 'x': 0, 'y': 0, 'width': 30, 'height': '12'},
        {
          'type': 'circle',
          'center': {'x': 5, 'y': 6},
          'radius': 2,
        },
        {
          'type': 'line',
          'from': [0, 0],
          'to': [10, 5],
          'width': 2,
        },
        {
          'type': 'triangle',
          'points': [
            [0, 0],
            [5, 5],
            [10, 0],
          ],
        },
        {
          'type': 'group',
          'x': 50,
          'y': 20,
          'children': [
            {'type': 'circle', 'x': 1, 'y': 2},
            {'type': 'text', 'x': 0, 'y': 0, 'text': 'A'},
          ],
        },
        {'type': 'circle', 'x': 'NaN', 'y': 3},
      ],
    })!;
    expect(d.elements.map((e) => e.shape), [
      DiagramShape.rect,
      DiagramShape.rect,
      DiagramShape.circle,
      DiagramShape.line,
      DiagramShape.polygon,
      DiagramShape.circle,
      DiagramShape.text,
    ], reason: 'Kreis mit NaN fällt weg');
    final square = d.elements[0];
    expect([square.number('x', 0), square.number('w', 0), square.number('width', 0)], [10, 20, 1]);
    final rect = d.elements[1];
    expect([rect.number('w', 0), rect.number('h', 0), rect.number('width', 0)], [30, 12, null]);
    expect(d.elements[2].number('r', 0), 2);
    expect(d.elements[3].number('x2', 0), 10);
    expect(d.elements[3].number('width', 0), 2, reason: 'bei Linien bleibt width die Strichstärke');
    expect([d.elements[5].number('x', 0), d.elements[5].number('y', 0)], [51, 22], reason: 'Gruppe verschoben');
    expect(d.elements[6].number('x', 0), 50);
    final key = DiagramKey.fromMap({
      'at': 1,
      'pos': [30, 40],
    })!;
    expect([key.numbers['x'], key.numbers['y']], [30, 40]);
  });

  test('Was sich nicht laden ließ, steht in broken – samt Darstellung direkt am Schritt', () {
    final bad = VisualShow.fromMap({
      'scene': {
        'elements': [
          {'type': 'blob'},
        ],
      },
      'transform': [42],
    });
    expect(bad.isEmpty, isTrue);
    expect(bad.broken, '2D-Szene ließ sich nicht lesen · Umformung ließ sich nicht lesen');
    final lesson = VisualLesson.fromMap({
      'title': 'T',
      'functions': [
        {'key': 's', 'expr': 't'},
      ],
      'steps': [
        {
          'title': 'a',
          'show': {
            'plot': ['s', 'v'],
          },
        },
        {'title': 'b', 'scene': latticeScene()},
      ],
    })!;
    expect(lesson.steps[0].show.plot, ['s']);
    expect(lesson.steps[0].show.broken, contains('Funktion „v“ fehlt'));
    expect(lesson.steps[1].show.scene, isNotNull, reason: 'Szene direkt am Schritt');
    expect(lesson.steps[1].show.broken, isEmpty);
    expect(VisualLesson.fromMap(lesson.toMap())!.steps[0].show.broken, lesson.steps[0].show.broken);
  });
}
