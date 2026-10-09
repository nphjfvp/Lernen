import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/sketch_task.dart';
import 'package:lernen/services/sketch_checker.dart';

List<SketchPoint> line(List<List<num>> points) => [
  for (final p in points) SketchPoint(p[0].toDouble(), p[1].toDouble()),
];

/// Abkühlkurven Pb-Sn: 20 % Sn mit Knick an der Liquidus (≈ 280 °C) und
/// eutektischem Haltepunkt (183 °C), die eutektische Legierung nur mit
/// Haltepunkt.
final cooling = SketchTask(
  xAxis: const SketchAxis(label: 't', min: 0, max: 100, showNumbers: false),
  yAxis: const SketchAxis(label: 'T in °C', min: 0, max: 350),
  curves: [
    SketchNamedCurve(
      name: '20 % Sn',
      reference: [
        line([
          [0, 330],
          [8, 280],
          [35, 190],
          [38, 183],
          [55, 183],
          [80, 60],
        ]),
      ],
    ),
    SketchNamedCurve(
      name: '61,9 % Sn',
      reference: [
        line([
          [0, 330],
          [15, 183],
          [45, 183],
          [70, 60],
        ]),
      ],
    ),
  ],
  features: const [
    SketchFeature(kind: SketchFeatureKind.kink, y: 280, curve: '20 % Sn', text: 'Liquidus: Primärkristalle'),
    SketchFeature(kind: SketchFeatureKind.plateau, y: 183, curve: '20 % Sn', text: 'eutektische Erstarrung'),
    SketchFeature(kind: SketchFeatureKind.plateau, y: 183, curve: '61,9 % Sn'),
  ],
);

/// Hall-Petch: R_eL über 1/√L, bei T₂ > T₁ parallel nach unten verschoben.
final hallPetch = SketchTask(
  xAxis: const SketchAxis(label: '1/√L', min: 0, max: 1, showNumbers: false),
  yAxis: const SketchAxis(label: 'R_eL', min: 0, max: 500, showNumbers: false),
  curves: [
    SketchNamedCurve(
      name: 'T₁',
      reference: [
        line([
          [0.05, 120],
          [0.95, 400],
        ]),
      ],
    ),
    SketchNamedCurve(
      name: 'T₂',
      reference: [
        line([
          [0.05, 60],
          [0.95, 340],
        ]),
      ],
    ),
  ],
  features: const [
    SketchFeature(kind: SketchFeatureKind.rising, x: 0.1, x2: 0.9, curve: 'T₁'),
    SketchFeature(kind: SketchFeatureKind.below, curve: 'T₂', other: 'T₁', text: 'höhere Temperatur → geringere Reibspannung'),
    SketchFeature(kind: SketchFeatureKind.parallel, curve: 'T₂', other: 'T₁'),
  ],
);

/// Warmauslagern: bei höherer Temperatur T₃ früheres, niedrigeres Härtemaximum.
final aging = SketchTask(
  xAxis: const SketchAxis(label: 'log t', min: 0, max: 10, showNumbers: false),
  yAxis: const SketchAxis(label: 'Härte', min: 0, max: 1, showNumbers: false),
  curves: [
    SketchNamedCurve(
      name: 'T₁',
      reference: [
        line([
          [0, 0.2],
          [3, 0.5],
          [6.5, 0.9],
          [9.5, 0.7],
        ]),
      ],
    ),
    SketchNamedCurve(
      name: 'T₃',
      reference: [
        line([
          [0, 0.2],
          [2, 0.6],
          [5, 0.4],
          [9.5, 0.3],
        ]),
      ],
    ),
  ],
  features: const [
    SketchFeature(kind: SketchFeatureKind.max, curve: 'T₁'),
    SketchFeature(kind: SketchFeatureKind.max, curve: 'T₃'),
    SketchFeature(kind: SketchFeatureKind.maxEarlier, curve: 'T₃', other: 'T₁'),
    SketchFeature(kind: SketchFeatureKind.maxHigher, curve: 'T₁', other: 'T₃'),
  ],
);

Map<String, List<List<SketchPoint>>> drawn(SketchTask task, [Map<String, List<List<num>>> overrides = const {}]) => {
  for (final c in task.curves) c.name: overrides.containsKey(c.name) ? [line(overrides[c.name]!)] : c.reference,
};

SketchVerdict checkAll(SketchTask task, Map<String, List<List<SketchPoint>>> strokes) =>
    SketchChecker.check(task, strokes[task.curves.first.name] ?? const [], const [], byCurve: strokes);

void main() {
  test('Musterkurven erfüllen ihre eigenen Merkmale', () {
    expect(cooling.isUsable, isTrue);
    expect(SketchChecker.selfCheck(cooling), isEmpty);
    expect(SketchChecker.selfCheck(hallPetch), isEmpty);
    expect(SketchChecker.selfCheck(aging), isEmpty);
  });

  group('Abkühlkurven: Haltepunkt und Knick', () {
    test('richtig gezeichnet, etwas zittrig', () {
      final v = checkAll(cooling, drawn(cooling, {
        '20 % Sn': [
          [0, 335],
          [9, 280],
          [20, 250],
          [36, 186],
          [40, 184],
          [47, 182],
          [56, 183],
          [78, 70],
        ],
      }));
      expect(v.ok, isTrue, reason: [for (final r in v.results) r.message].join('\n'));
      expect(v.results.first.message, startsWith('20 % Sn: '));
    });

    test('ohne Knick: gleichmäßig bis zum Haltepunkt', () {
      final v = checkAll(cooling, drawn(cooling, {
        '20 % Sn': [
          [0, 330],
          [30, 183],
          [50, 183],
          [80, 60],
        ],
      }));
      expect(v.results[0].ok, isFalse);
      expect(v.results[0].message, contains('Knick'));
      expect(v.results[1].ok, isTrue);
    });

    test('Haltepunkt bei falscher Temperatur bzw. ganz ohne', () {
      final wrong = checkAll(cooling, drawn(cooling, {
        '61,9 % Sn': [
          [0, 330],
          [12, 230],
          [40, 230],
          [70, 60],
        ],
      }));
      expect(wrong.results[2].ok, isFalse);
      expect(wrong.results[2].message, contains('statt bei 183'));

      final none = checkAll(cooling, drawn(cooling, {
        '61,9 % Sn': [
          [0, 330],
          [70, 60],
        ],
      }));
      expect(none.results[2].message, contains('fehlt der Haltepunkt'));
    });

    test('Kurve fehlt', () {
      final v = checkAll(cooling, {'20 % Sn': cooling.curves.first.reference});
      expect(v.results[2].ok, isFalse);
      expect(v.results[2].message, '61,9 % Sn: Diese Kurve fehlt noch.');
    });
  });

  group('Vergleiche zwischen Kurven', () {
    test('Hall-Petch: unter und parallel', () {
      expect(checkAll(hallPetch, drawn(hallPetch)).ok, isTrue);

      final aboveInstead = checkAll(hallPetch, drawn(hallPetch, {
        'T₂': [
          [0.05, 180],
          [0.95, 460],
        ],
      }));
      expect(aboveInstead.results[1].ok, isFalse);
      expect(aboveInstead.results[1].message, contains('„T₂“ soll unter „T₁“ liegen'));

      final crossing = checkAll(hallPetch, drawn(hallPetch, {
        'T₂': [
          [0.05, 100],
          [0.95, 150],
        ],
      }));
      expect(crossing.results[2].ok, isFalse);
      expect(crossing.results[2].message, contains('parallel'));

      final same = checkAll(hallPetch, drawn(hallPetch, {
        'T₂': [
          [0.05, 121],
          [0.95, 401],
        ],
      }));
      expect(same.results[2].message, contains('nicht auf'));
    });

    test('Härtemaximum: früher und höher', () {
      expect(checkAll(aging, drawn(aging)).ok, isTrue);
      final swapped = checkAll(aging, {
        'T₁': aging.curves[1].reference,
        'T₃': aging.curves[0].reference,
      });
      expect(swapped.results[2].ok, isFalse);
      expect(swapped.results[2].message, contains('früher'));
      expect(swapped.results[3].ok, isFalse);
    });
  });

  group('Speichern und Lesen', () {
    test('mehrere Kurven: "curves", erste zusätzlich als "reference"', () {
      final map = cooling.toMap();
      expect(map['curves'], hasLength(2));
      expect((map['reference'] as List).single, hasLength(6));
      final back = SketchTask.fromMap(map)!;
      expect(back.curveNames, ['20 % Sn', '61,9 % Sn']);
      expect(back.features.first.curve, '20 % Sn');
      expect(back.features.first.kind, SketchFeatureKind.kink);
      expect(SketchChecker.selfCheck(back), isEmpty);
    });

    test('eine Kurve ohne Namen bleibt im alten Format', () {
      final single = SketchTask(
        xAxis: const SketchAxis(min: 0, max: 10),
        yAxis: const SketchAxis(min: 0, max: 10),
        reference: [
          line([
            [0, 0],
            [10, 10],
          ]),
        ],
        features: const [SketchFeature(kind: SketchFeatureKind.rising, x: 1, x2: 9)],
      );
      expect(single.toMap().containsKey('curves'), isFalse);
      expect(single.isMulti, isFalse);
    });

    test('KI-Antwort: Kurven, Merkmale mit Kurve und Vergleich, deutsche Namen', () {
      final t = SketchTask.fromMap({
        'xAxis': {'label': '1/√L', 'min': 0, 'max': 1},
        'yAxis': {'label': 'R_eL', 'min': 0, 'max': 500},
        'curves': [
          {
            'name': 'ε₁',
            'reference': [
              [0, 100],
              [1, 300],
            ],
          },
          {
            'name': 'ε₂',
            'points': [
              [0, 200],
              [1, 400],
            ],
          },
        ],
        'features': [
          {'kind': 'über', 'curve': 'ε₂', 'other': 'ε₁'},
          {'kind': 'haltepunkt', 'y': 200, 'curve': 'ε₁'},
          {'kind': 'knick', 'y': 150},
        ],
      })!;
      expect(t.curveNames, ['ε₁', 'ε₂']);
      expect(t.features.map((f) => f.kind), [
        SketchFeatureKind.above,
        SketchFeatureKind.plateau,
        SketchFeatureKind.kink,
      ]);
      expect(t.features.first.other, 'ε₁');
      expect(t.resolve(t.features.last.curve), 'ε₁');
      expect(t.isUsable, isTrue);
      // Vergleich mit sich selbst bzw. unbekannter Kurve ist unbrauchbar.
      expect(
        t.copyWith(features: const [SketchFeature(kind: SketchFeatureKind.above, curve: 'ε₁', other: 'ε₁')]).isUsable,
        isFalse,
      );
      expect(
        t.copyWith(features: const [SketchFeature(kind: SketchFeatureKind.above, curve: 'ε₁', other: 'x')]).isUsable,
        isFalse,
      );
    });

    test('Lösungstext und Tipps nennen die Kurven', () {
      final text = SketchChecker.solutionText(hallPetch);
      expect(text, contains('Kurven: T₁, T₂'));
      expect(text, contains('„T₂“ liegt unter „T₁“'));
      expect(SketchChecker.solutionText(cooling), contains('20 % Sn: Haltepunkt (waagerecht) bei 183'));
    });
  });
}
