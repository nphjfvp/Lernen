import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/models/visual_scene3d.dart';
import 'package:lernen/models/visual_scene3d_blocks.dart';

void main() {
  group('Baustein „surface“: Fläche z = f(x, y)', () {
    Map<String, dynamic> saddle() => {
      'box': [1, 1, 0.8],
      'objects': [
        {
          'type': 'surface',
          'expr': 'x^2 - y^2',
          'x': [-2, 2],
          'y': [-2, 2],
          'n': 8,
          'tangent': [1, 0],
          'gradient': [1, 1],
          'points': [
            {
              'at': [0, 0],
              'text': 'Sattelpunkt',
            },
          ],
          'curve': {'y': 'x', 'text': 'y = x', 'stroke': 'purple'},
        },
        {
          'type': 'text',
          'at': [0.5, 0.5, 1],
          'text': 'frei daneben',
        },
      ],
    };

    test('die App rechnet die Fläche: Raster, Höhen, Achsenbeschriftung', () {
      final scene = VisualScene3D.fromMap(saddle())!;
      final quads = scene.objects.where((o) => o.shape == Scene3DShape.polygon && o.points.length == 4).toList();
      // 8 × 8 Felder + die Tangentialebene.
      expect(quads, hasLength(65));
      // Ecke (−2, −2): z = 0 → mittlere Höhe des Raums (Bereich −4 … 4).
      final corner = quads.first.points.first;
      expect(corner[0], closeTo(0, 1e-9));
      expect(corner[1], closeTo(0, 1e-9));
      expect(corner[2], closeTo(0.4, 1e-9));
      // Alles liegt im Raum der Szene.
      for (final q in quads.take(64)) {
        for (final p in q.points) {
          expect(p[0], inInclusiveRange(0, 1));
          expect(p[1], inInclusiveRange(0, 1));
          expect(p[2], inInclusiveRange(-1e-9, 0.8 + 1e-9));
        }
      }
      // Oben und unten haben verschiedene Farben.
      expect(quads.take(64).map((q) => q.fill).toSet().length, greaterThan(4));
      final texts = scene.objects.map((o) => o.text).where((t) => t.isNotEmpty).toList();
      expect(texts, containsAll(['x: −2 … 2', 'y: −2 … 2', 'z: −4 … 4', 'frei daneben']));
    });

    test('Punkt, Tangentialebene, Gradient und Kurve – alles aus der Formel gerechnet', () {
      final scene = VisualScene3D.fromMap(saddle())!;
      final texts = scene.objects.map((o) => o.text).toList();
      // f(1, 0) = 1; f_x = 2, f_y = 0.
      expect(texts, contains('P(1 | 0 | 1)'));
      expect(texts, contains('Tangentialebene'));
      // grad f(1, 1) = (2, −2).
      expect(texts, contains('grad f = (2 | −2)'));
      expect(texts, contains('Sattelpunkt'));
      // Der Punkt liegt auf der Fläche (z = 0 → halbe Höhe), seine Beschriftung darüber.
      final spheres = scene.objects.where((o) => o.shape == Scene3DShape.sphere).toList();
      final saddle3d = spheres.first.vectors['at']!;
      expect((saddle3d[0], saddle3d[1]), (0.5, 0.5));
      expect(saddle3d[2], closeTo(0.4, 1e-9));
      expect(spheres.every((o) => o.text.isEmpty), isTrue);
      final saddleLabel = scene.objects.firstWhere((o) => o.text == 'Sattelpunkt');
      expect(saddleLabel.shape, Scene3DShape.text);
      expect(saddleLabel.vectors['at']![2], greaterThan(0.4));
      // Tangentialebene: an (1, 0) berührt sie die Fläche, Steigung 2 in x.
      final plane = scene.objects.firstWhere((o) => o.text == 'Tangentialebene');
      final zs = plane.points.map((p) => p[2]).toList();
      expect(zs[1] - zs[0], greaterThan(0), reason: 'steigt in x-Richtung');
      expect(zs[2], closeTo(zs[1], 1e-6), reason: 'f_y = 0: in y-Richtung eben');
      // Kurve y = x liegt auf der Fläche: dort ist z = 0.
      final curve = scene.objects.where((o) => o.shape == Scene3DShape.line && o.stroke == 'purple').toList();
      expect(curve.length, greaterThan(50));
      for (final l in curve) {
        expect(l.vectors['to']![2], closeTo(0.4, 1e-6));
      }
      expect(curve.where((l) => l.text == 'y = x'), hasLength(1));
    });

    test('gespeichert wird der Baustein, nicht das Raster', () {
      final scene = VisualScene3D.fromMap(saddle())!;
      final map = scene.toMap();
      final objects = map['objects'] as List;
      expect(objects, hasLength(2));
      expect(objects.map((o) => (o as Map)['type']), containsAll(['surface', 'text']));
      final again = VisualScene3D.fromMap(map)!;
      expect(again.objects.length, scene.objects.length);
      // Auch in einer Lektion übersteht er Speichern und Lesen.
      final lesson = VisualLesson.fromMap({
        'title': 'Sattel',
        'steps': [
          {
            'title': 'Fläche',
            'text': 'So sieht sie aus.',
            'show': {'scene3d': saddle()},
          },
        ],
      })!;
      final stored = VisualLesson.fromMap(lesson.toMap())!;
      expect(stored.steps.single.show.scene3d!.objects.length, scene.objects.length);
      expect(((stored.toMap()['steps'] as List).single['show']['scene3d']['objects'] as List), hasLength(2));
    });

    test('Pole und Lücken: nichts Unendliches, Ausreißer gekappt; unlesbarer Term → Baustein entfällt', () {
      final pole = VisualScene3D.fromMap({
        'objects': [
          {
            'type': 'surface',
            'expr': 'x/y + ln(y)',
            'x': [-2, 2],
            'y': [-1, 3],
            'n': 20,
          },
        ],
      })!;
      for (final o in pole.objects.where((o) => o.shape == Scene3DShape.polygon)) {
        for (final p in o.points) {
          expect(p.every((v) => v.isFinite), isTrue);
          expect(p[2], inInclusiveRange(-1e-9, 1 + 1e-9));
        }
      }
      expect(pole.objects.where((o) => o.shape == Scene3DShape.polygon).length, lessThan(400), reason: 'y ≤ 0 fehlt');
      // Fremde Größe im Term: kein Baustein – die Szene behält den Rest.
      final broken = VisualScene3D.fromMap({
        'objects': [
          {'type': 'surface', 'expr': 'a*x + y'},
          {
            'type': 'sphere',
            'at': [0, 0, 0],
            'r': 0.1,
          },
        ],
      })!;
      expect(broken.objects, hasLength(1));
      expect(
        VisualScene3D.fromMap({
          'objects': [
            {'type': 'surface', 'expr': '((('},
          ],
        }),
        isNull,
      );
    });

    test('Höhenfarbe und Zahlen', () {
      expect(Scene3DBlocks.heightColor(0), '#3b6fd8');
      expect(Scene3DBlocks.heightColor(1), '#f2a33a');
      expect(Scene3DBlocks.heightColor(double.nan), Scene3DBlocks.heightColor(0.5));
      expect(Scene3DBlocks.fmt(-2), '−2');
      expect(Scene3DBlocks.fmt(0.125), '0,125');
      expect(Scene3DBlocks.fmt(12.50), '12,5');
      expect(Scene3DBlocks.fmt(1000), '1000');
    });
  });

  group('Baustein „shaft“: Welle aus Abschnitten', () {
    Map<String, dynamic> axle() => {
      'box': [1000, 140, 140],
      'frame': false,
      'objects': [
        {
          'type': 'shaft',
          'segments': [
            {'d': 60, 'l': 175},
            {'d': 70, 'l': 650, 'text': 'Ø70 Mitte'},
            {'d': 60, 'l': 175},
          ],
          'supports': [
            {'at': 60, 'text': 'A'},
            {'at': 940, 'text': 'B'},
          ],
          'forces': [
            {'at': 175, 'text': 'F = 20 kN'},
            {'at': 825, 'text': 'F = 20 kN', 'dir': 'up'},
          ],
          'marks': [
            {'at': 175, 'text': 'gefährdeter Querschnitt'},
          ],
        },
      ],
    };

    test('Abschnitte maßstäblich hintereinander, beschriftet', () {
      final scene = VisualScene3D.fromMap(axle())!;
      final cylinders = scene.objects.where((o) => o.shape == Scene3DShape.cylinder).toList();
      // 3 Abschnitte + 1 Markierung + 2 Lager.
      expect(cylinders, hasLength(6));
      expect(cylinders[0].vectors['from']![0], 0);
      expect(cylinders[0].vectors['to']![0], 175);
      expect(cylinders[1].vectors['from']![0], 175);
      expect(cylinders[1].vectors['to']![0], 825);
      expect(cylinders[2].vectors['to']![0], 1000);
      expect(cylinders.take(3).map((c) => c.numbers['r']), [30, 35, 30]);
      // Alle auf derselben Achse.
      expect(cylinders.take(3).map((c) => c.vectors['from']![2]).toSet(), hasLength(1));
      final texts = scene.objects.map((o) => o.text).where((t) => t.isNotEmpty).toList();
      expect(texts, containsAll(['Ø60', 'Ø70 Mitte', 'A', 'B', 'F = 20 kN', 'gefährdeter Querschnitt']));
    });

    test('Lager von unten, Kräfte quer auf die Oberfläche, Markierung am Absatz', () {
      final scene = VisualScene3D.fromMap(axle())!;
      final axisZ = scene.objects.firstWhere((o) => o.shape == Scene3DShape.cylinder).vectors['from']![2];
      final arrows = scene.objects.where((o) => o.shape == Scene3DShape.arrow).toList();
      expect(arrows, hasLength(2));
      // Von oben: endet auf der Oberfläche des Abschnitts an dieser Stelle (r = 30 bei x = 175).
      expect(arrows[0].vectors['to'], [175, anything, axisZ + 30]);
      expect(arrows[0].vectors['from']![2], greaterThan(axisZ + 30));
      // Von unten (hier beginnt der dickere Abschnitt erst danach: r = 35 ab x > 825).
      expect(arrows[1].vectors['to']![2], axisZ - 35);
      expect(arrows[1].vectors['from']![2], lessThan(axisZ - 35));
      final cones = scene.objects.where((o) => o.shape == Scene3DShape.cylinder && o.numbers['r2'] == 0).toList();
      expect(cones, hasLength(2));
      expect(cones.first.vectors['to']![2], axisZ - 30, reason: 'Spitze an der Welle');
      final mark = scene.objects.firstWhere((o) => o.shape == Scene3DShape.cylinder && o.fill == 'red');
      expect((mark.vectors['from']![0] + mark.vectors['to']![0]) / 2, closeTo(175, 1e-9));
      expect(mark.numbers['r'], greaterThan(30));
    });

    test('ein einfacher Zylinder mit „type: welle“ bleibt ein Zylinder; Baustein wird kompakt gespeichert', () {
      final plain = VisualScene3D.fromMap({
        'objects': [
          {
            'type': 'welle',
            'from': [0, 0, 0],
            'to': [10, 0, 0],
            'r': 2,
          },
        ],
      })!;
      expect(plain.objects.single.shape, Scene3DShape.cylinder);
      final scene = VisualScene3D.fromMap(axle())!;
      expect((scene.toMap()['objects'] as List).single['type'], 'shaft');
      expect(VisualScene3D.fromMap(scene.toMap())!.objects.length, scene.objects.length);
    });

    test('senkrechte Achse und unbrauchbare Abschnitte', () {
      final vertical = VisualScene3D.fromMap({
        'objects': [
          {
            'type': 'shaft',
            'axis': 'z',
            'from': [5, 5, 0],
            'segments': [
              {'d': 4, 'l': 10},
              {'d': 0, 'l': 5},
              {'d': 2, 'l': 6},
            ],
          },
        ],
      })!;
      final cylinders = vertical.objects.where((o) => o.shape == Scene3DShape.cylinder).toList();
      expect(cylinders, hasLength(2));
      expect(cylinders.last.vectors['to'], [5, 5, 16]);
    });
  });
}
