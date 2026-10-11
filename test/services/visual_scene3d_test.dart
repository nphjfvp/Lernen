import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/models/visual_scene3d.dart';

/// kfz-Elementarzelle: Atome wachsen, bis sie sich auf der Flächendiagonale
/// berühren (r = a·√2/4) – Packungsdichte als mitlaufende Größe.
Map<String, dynamic> fccScene() => {
  'box': [1, 1, 1],
  'seconds': 6,
  'param': {'name': 'Packungsdichte', 'unit': '%', 'from': 2, 'to': 74},
  'captions': [
    {'at': 0, 'text': 'Kleine Atome: viel Platz.'},
    {'at': 0.8, 'text': r'Berühren sich: $r = a\sqrt{2}/4$'},
  ],
  'objects': [
    {
      'type': 'sphere',
      'at': [0, 0, 0],
      'r': 0.1,
      'fill': 'accent',
      'repeat': {
        'n': [2, 2, 2],
        'd': [1, 1, 1],
      },
      'keys': [
        {'t': 1, 'r': 0.354},
      ],
    },
    for (final p in [
      [0.5, 0.5, 0],
      [0.5, 0.5, 1],
      [0.5, 0, 0.5],
      [0.5, 1, 0.5],
      [0, 0.5, 0.5],
      [1, 0.5, 0.5],
    ])
      {
        'type': 'sphere',
        'at': p,
        'r': 0.1,
        'fill': 'orange',
        'keys': [
          {'t': 1, 'r': 0.354},
        ],
      },
    {
      'type': 'line',
      'from': [0, 0, 0],
      'to': [1, 1, 0],
      'stroke': 'red',
      'dashed': true,
      'text': 'Flächendiagonale',
    },
    {
      'type': 'polygon',
      'points': [
        [1, 0, 0],
        [0, 1, 0],
        [0, 0, 1],
      ],
      'fill': 'purple',
      'text': '(111)',
      'opacity': 0,
      'keys': [
        {'t': 0.8, 'opacity': 0},
        {'t': 1, 'opacity': 1},
      ],
    },
    {
      'type': 'arrow',
      'from': [0, 0, 1],
      'to': [1, 0, 1],
      'draw': 0,
      'keys': [
        {'t': 1, 'draw': 1},
      ],
    },
    {
      'type': 'box',
      'pos': [0, 0, 0],
      'size': [0.5, 0.5, 0.5],
      'fill': '#e0a030',
      'text': 'Achtelwürfel',
    },
    {
      'type': 'text',
      'at': [0.5, 0.5, 1.2],
      'text': 'kfz',
    },
    {'type': 'sphere'},
    {
      'type': 'quatsch',
      'at': [0, 0, 0],
    },
    {
      'type': 'line',
      'from': [0, 0],
    },
  ],
};

void main() {
  test('3D-Szene aus KI-JSON: Objekte, Raster, Aliase, ungültige fallen weg, toMap/fromMap', () {
    final s = VisualScene3D.fromMap(fccScene())!;
    expect(s.objects.map((o) => o.shape), [
      Scene3DShape.sphere,
      for (var i = 0; i < 6; i++) Scene3DShape.sphere,
      Scene3DShape.line,
      Scene3DShape.polygon,
      Scene3DShape.arrow,
      Scene3DShape.box,
      Scene3DShape.text,
    ]);
    expect(s.objects.first.copies, 8, reason: '8 Eckatome per Raster');
    final box = s.objects[10];
    expect(box.vectors['at'], [0, 0, 0], reason: '"pos" als Alias');
    expect(box.vectors['dims'], [0.5, 0.5, 0.5], reason: '"size" als Vektor bei Quadern');
    expect(VisualScene3D.fromMap(s.toMap())!.toMap(), s.toMap());
    expect(VisualScene3D.fromMap({'objects': []}), isNull);
  });

  test('Schlüsselbilder: Radius, Deckkraft, Zeichnen; Beschriftung und Packungsdichte', () {
    final s = VisualScene3D.fromMap(fccScene())!;
    final corner = s.objects.first;
    expect(corner.number('r', 0), 0.1);
    expect(corner.number('r', 1), closeTo(0.354, 1e-9));
    expect(corner.number('r', 0.5), closeTo(0.227, 1e-9));
    final plane = s.objects[8];
    expect(plane.number('opacity', 0.5), 0);
    expect(plane.number('opacity', 0.9), closeTo(0.5, 1e-9));
    expect(s.objects[9].number('draw', 0.25), 0.25);
    expect(s.paramAt(1), 74);
    expect(s.captionAt(0.9), contains('Berühren sich'));

    final moving = Scene3DObject.fromMap({
      'type': 'sphere',
      'at': [0, 0, 0],
      'keys': [
        {
          't': 1,
          'at': [1, 2, 3],
          'fill': 'red',
        },
      ],
    })!;
    expect(moving.vector('at', 0.5), [0.5, 1, 1.5]);
    expect(moving.colorAt('fill', 0.5), ('red', 'red', 0));
  });

  test('Obergrenze und Raster-Grenzen; 3D im Schritt einer Lektion', () {
    final big = VisualScene3D.fromMap({
      'objects': [
        for (var i = 0; i < 3; i++)
          {
            'type': 'sphere',
            'at': [0, 0, 0],
            'repeat': {
              'n': [20, 8, 3],
              'd': [1, 1, 1],
            },
          },
      ],
    })!;
    expect(big.objects.first.n, [8, 8, 3], reason: 'je Richtung höchstens 8');
    expect(big.objects.length, 2, reason: 'höchstens ${VisualScene3D.maxObjects} Objekte');

    final lesson = VisualLesson.fromMap({
      'title': 'Packungsdichte kfz',
      'steps': [
        {
          'title': 'Atome wachsen',
          'show': {'scene3d': fccScene()},
        },
      ],
    })!;
    expect(lesson.steps.single.show.scene3d!.objects, hasLength(12));
    expect(lesson.steps.single.show.isEmpty, isFalse);
    expect(
      VisualLesson.fromMap(lesson.toMap())!.steps.single.show.scene3d!.toMap(),
      lesson.steps.single.show.scene3d!.toMap(),
    );
  });
}
