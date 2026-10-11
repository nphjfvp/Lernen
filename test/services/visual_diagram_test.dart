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
}
