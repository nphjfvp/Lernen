import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/sketch_task.dart';
import 'package:lernen/services/sketch_checker.dart';

List<SketchPoint> line(List<List<num>> points) => [
  for (final p in points) SketchPoint(p[0].toDouble(), p[1].toDouble()),
];

/// Eisen: Längenänderung über T, krz → kfz bei 911 °C (dichter gepackt → Sprung nach unten).
final iron = SketchTask(
  xAxis: const SketchAxis(label: 'T in °C', min: 500, max: 1000),
  yAxis: const SketchAxis(label: 'ΔL/L', min: 0, max: 1, showNumbers: false),
  reference: [
    line([
      [500, 0.2],
      [911, 0.6],
    ]),
    line([
      [911, 0.45],
      [1000, 0.6],
    ]),
  ],
  features: const [
    SketchFeature(kind: SketchFeatureKind.rising, x: 500, x2: 911, text: 'α-Eisen dehnt sich beim Erwärmen aus'),
    SketchFeature(kind: SketchFeatureKind.jumpDown, x: 911, tol: 0.05, text: 'krz → kfz, dichter gepackt'),
    SketchFeature(kind: SketchFeatureKind.rising, x: 911, x2: 1000),
  ],
);

/// Spannungs-Dehnungs-Kurve (qualitativ, elastischer Bereich überzeichnet).
final tensile = SketchTask(
  xAxis: const SketchAxis(label: 'ε in %', min: 0, max: 30),
  yAxis: const SketchAxis(label: 'σ in MPa', min: 0, max: 600),
  reference: [
    line([
      [0, 0],
      [2, 300],
      [4, 330],
      [15, 500],
      [25, 420],
    ]),
  ],
  features: const [
    SketchFeature(kind: SketchFeatureKind.linear, x: 0, x2: 2, text: 'Hookesche Gerade'),
    SketchFeature(kind: SketchFeatureKind.max, x: 15, tol: 0.15),
    SketchFeature(kind: SketchFeatureKind.endsAt, x: 25, tol: 0.1, text: 'Bruch'),
    SketchFeature(kind: SketchFeatureKind.mark, label: 'R_p0,2', anchor: SketchAnchor.beforeMax),
    SketchFeature(kind: SketchFeatureKind.mark, label: 'R_m', anchor: SketchAnchor.max),
    SketchFeature(kind: SketchFeatureKind.mark, label: 'A', anchor: SketchAnchor.end, text: 'Bruchdehnung'),
  ],
);

/// Potentialkurve U(r): steil von oben, Minimum unter 0 bei r0, flach gegen 0.
final potential = SketchTask(
  xAxis: const SketchAxis(label: 'r', min: 0, max: 10, showNumbers: false),
  yAxis: const SketchAxis(label: 'U', min: -1, max: 1, showNumbers: false),
  reference: [
    line([
      [0.8, 1],
      [1, 0],
      [1.2, -0.6],
      [1.5, -0.8],
      [2, -0.6],
      [3, -0.3],
      [5, -0.1],
      [10, -0.01],
    ]),
  ],
  features: const [
    SketchFeature(kind: SketchFeatureKind.min, x: 1.5, y: 0, tol: 0.1, text: 'Gleichgewichtsabstand r0'),
    SketchFeature(kind: SketchFeatureKind.steeperLeft, text: 'Abstoßung wirkt kurzreichweitig und stark'),
    SketchFeature(kind: SketchFeatureKind.approaches, y: 0),
    SketchFeature(kind: SketchFeatureKind.mark, label: 'r0', anchor: SketchAnchor.min),
  ],
);

void main() {
  test('die Musterkurven erfüllen ihre eigenen Merkmale', () {
    expect(SketchChecker.selfCheck(iron), isEmpty);
    expect(SketchChecker.selfCheck(tensile), isEmpty);
    expect(SketchChecker.selfCheck(potential), isEmpty);
    expect(SketchChecker.referenceMarks(tensile).map((m) => m.label), ['R_p0,2', 'R_m', 'A']);
  });

  group('Eisen bei 911 °C', () {
    test('freihändig mit Sprung in zwei Strichen: richtig', () {
      final v = SketchChecker.check(iron, [
        line([
          [505, 0.25],
          [700, 0.42],
          [905, 0.62],
        ]),
        line([
          [915, 0.4],
          [995, 0.55],
        ]),
      ], const []);
      expect(v.ok, isTrue, reason: v.results.map((r) => r.message).join('\n'));
    });

    test('Sprung als ein Strich (senkrecht nach unten): richtig', () {
      final v = SketchChecker.check(iron, [
        line([
          [500, 0.2],
          [910, 0.6],
          [912, 0.4],
          [1000, 0.55],
        ]),
      ], const []);
      expect(v.ok, isTrue, reason: v.results.map((r) => r.message).join('\n'));
    });

    test('ohne Sprung bzw. an der falschen Stelle', () {
      final none = SketchChecker.check(iron, [
        line([
          [500, 0.2],
          [1000, 0.7],
        ]),
      ], const []);
      expect(none.results[0].ok, isTrue);
      expect(none.results[1].message, contains('fehlt der Sprung nach unten'));
      expect(none.results[1].message, contains('krz → kfz'));
      expect(none.summary, '2 von 3 Merkmalen stimmen.');

      final early = SketchChecker.check(iron, [
        line([
          [500, 0.2],
          [850, 0.55],
        ]),
        line([
          [850, 0.4],
          [1000, 0.6],
        ]),
      ], const []);
      expect(early.results[1].message, 'Der Sprung nach unten liegt bei ≈ 846 statt bei 911.');
    });

    test('fallend statt steigend', () {
      final v = SketchChecker.check(iron, [
        line([
          [500, 0.8],
          [911, 0.5],
          [912, 0.3],
          [1000, 0.2],
        ]),
      ], const []);
      expect(v.results.first.message, contains('soll die Kurve steigen'));
    });
  });

  group('Spannungs-Dehnungs-Kurve', () {
    final drawn = [
      line([
        [0, 0],
        [1.8, 280],
        [5, 340],
        [14, 490],
        [20, 470],
        [26, 400],
      ]),
    ];

    test('Kurve und Kennwerte an den richtigen Stellen', () {
      final v = SketchChecker.check(tensile, drawn, const [
        SketchMark('R_p0,2', SketchPoint(2.5, 300)),
        SketchMark('R_m', SketchPoint(14, 485)),
        SketchMark('A', SketchPoint(26, 0)),
      ]);
      expect(v.ok, isTrue, reason: v.results.map((r) => r.message).join('\n'));
    });

    test('ohne Einschnürung und mit falschen Markierungen', () {
      final v = SketchChecker.check(
        tensile,
        [
          line([
            [0, 0],
            [2, 300],
            [15, 500],
          ]),
        ],
        const [SketchMark('R_m', SketchPoint(5, 340)), SketchMark('R_p0,2', SketchPoint(14, 100))],
      );
      final byLabel = {
        for (final r in v.results) r.feature.kind == SketchFeatureKind.mark ? r.feature.label : r.feature.kind.name: r,
      };
      expect(byLabel['linear']!.ok, isTrue);
      expect(byLabel['max']!.message, contains('erst steigen, dann wieder fallen'));
      expect(byLabel['endsAt']!.message, contains('bei ≈ 25 enden'));
      expect(byLabel['R_m']!.message, 'R_m soll am Maximum der Kurve sitzen.');
      expect(byLabel['R_p0,2']!.ok, isFalse);
      expect(byLabel['A']!.message, 'Markiere A (Bruchdehnung).');
    });

    test('Hookesche Gerade krumm gezeichnet', () {
      final v = SketchChecker.check(tensile, [
        line([
          [0, 0],
          [0.5, 200],
          [2, 230],
          [15, 500],
          [25, 420],
        ]),
      ], const []);
      expect(v.results.first.message, contains('(nahezu) gerade'));
    });
  });

  group('Potentialkurve', () {
    test('richtig skizziert', () {
      final v = SketchChecker.check(
        potential,
        [
          line([
            [0.9, 0.9],
            [1.1, -0.2],
            [1.4, -0.7],
            [1.8, -0.6],
            [3, -0.25],
            [6, -0.06],
            [9.8, -0.02],
          ]),
        ],
        const [SketchMark('r0', SketchPoint(1.45, -0.72))],
      );
      expect(v.ok, isTrue, reason: v.results.map((r) => r.message).join('\n'));
    });

    test('symmetrische Mulde über null', () {
      final v = SketchChecker.check(potential, [
        line([
          [1, 0.9],
          [3, 0.3],
          [5, 0.1],
          [7, 0.3],
          [9, 0.9],
        ]),
      ], const []);
      expect(v.results[0].ok, isFalse);
      expect(v.results[1].message, contains('asymmetrisch'));
      expect(v.results[2].message, contains('annähern'));
    });
  });

  group('Modell', () {
    test('toMap/fromMap, KI-Feldnamen, Musterkurve als Text', () {
      expect(SketchTask.fromMap(tensile.toMap())!.toMap(), tensile.toMap());
      final ai = SketchTask.fromMap({
        'xAxis': {'label': 'T in °C', 'min': '500', 'max': 1000},
        'yAxis': {'label': 'ΔL', 'min': 0, 'max': 1, 'showNumbers': false},
        'reference': [
          [500, 0.2],
          [911, 0.6],
        ],
        'features': [
          {'kind': 'sprung', 'at': 911, 'tolerance': 0.04},
          {
            'kind': 'steigend',
            'range': [500, 911],
          },
          {'kind': 'kennwert', 'label': 'R_m', 'anchor': 'Maximum'},
          {'kind': 'unbekannt'},
        ],
      })!;
      expect(ai.xAxis.min, 500);
      expect(ai.yAxis.showNumbers, isFalse);
      expect(ai.reference.single, hasLength(2));
      expect(ai.features.map((f) => f.kind), [
        SketchFeatureKind.jumpDown,
        SketchFeatureKind.rising,
        SketchFeatureKind.mark,
      ]);
      expect(ai.features[1].x2, 911);
      expect(ai.features[2].anchor, SketchAnchor.max);
      expect(ai.isUsable, isTrue);

      final text = SketchTask.referenceText(iron.reference);
      expect(text, '500; 0.2\n911; 0.6\n\n911; 0.45\n1000; 0.6');
      final parsed = SketchTask.parseReference(text);
      expect(parsed.error, isNull);
      expect(parsed.strokes, hasLength(2));
      expect(SketchTask.parseReference('1; 2\nx').error, contains('Zeile 2'));
      expect(SketchTask.parseReference('1; 2').error, contains('mindestens 2 Punkte'));
    });

    test('Tipps und Lösungstext', () {
      final hints = SketchChecker.hints(tensile);
      expect(hints.first, 'Achte auf den Verlauf: Hookesche Gerade');
      expect(hints.last, contains('R_m: am Maximum der Kurve'));
      expect(SketchChecker.solutionText(iron), contains('- Sprung nach unten 911: krz → kfz, dichter gepackt'));
    });
  });
}
