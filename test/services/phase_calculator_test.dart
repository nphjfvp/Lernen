import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/phase_task.dart';
import 'package:lernen/models/sketch_task.dart';
import 'package:lernen/services/phase_calculator.dart';
import 'package:lernen/services/sketch_checker.dart';

/// Blei-Zinn mit geraden Linien zwischen den Eckdaten.
const pbSn = PhaseSystem(
  a: 'Pb',
  b: 'Sn',
  tMax: 350,
  meltA: 327,
  eutecticC: 61.9,
  eutecticT: 183,
  rightC: 100,
  rightT: 232,
  alphaMax: 18.3,
  alphaLow: 2,
  betaMax: 97.8,
  betaLow: 99,
);

/// Stahlecke (eutektoid): γ statt Schmelze, Perlit, Zementit rechts außerhalb.
const steel = PhaseSystem(
  a: 'Fe',
  b: 'C',
  cMax: 2.1,
  tMin: 500,
  tMax: 1200,
  liquid: 'γ',
  alpha: 'α',
  beta: 'Fe₃C',
  eutecticName: 'Perlit',
  eutectoid: true,
  meltA: 911,
  eutecticC: 0.8,
  eutecticT: 723,
  rightC: 2.06,
  rightT: 1147,
  alphaMax: 0.02,
  alphaLow: 0,
  betaMax: 6.67,
  betaLow: 6.67,
);

PhaseCalculator calcOf(PhaseSystem s, [List<PhasePart> parts = const []]) =>
    PhaseCalculator(PhaseTask(system: s, parts: parts));

void main() {
  final calc = calcOf(pbSn);

  group('Gebiete und Phasen', () {
    test('Pb-Sn: jedes Gebiet an einem typischen Punkt', () {
      expect(pbSn.isValid, isTrue);
      expect(calc.regionAt(40, 300), PhaseRegion.liquid);
      expect(calc.regionAt(40, 200), PhaseRegion.liquidAlpha);
      expect(calc.regionAt(5, 250), PhaseRegion.alpha);
      expect(calc.regionAt(80, 200), PhaseRegion.liquidBeta);
      expect(calc.regionAt(99.5, 150), PhaseRegion.beta);
      expect(calc.regionAt(40, 100), PhaseRegion.alphaBeta);
      expect(calc.phasesAt(40, 200), ['Schmelze', 'α']);
      expect(calc.phasesAt(40, 100), ['α', 'β']);
    });

    test('Liquidustemperatur links und rechts vom Eutektikum', () {
      expect(calc.liquidusT(0), closeTo(327, 1e-9));
      expect(calc.liquidusT(61.9), closeTo(183, 1e-9));
      expect(calc.liquidusT(40), closeTo(233.9, 0.1));
      expect(calc.liquidusT(100), 232);
    });

    test('Gebietsnamen zum Beschriften: alle sechs Gebiete, jedes im eigenen Gebiet', () {
      final labels = calc.regionLabels();
      expect({for (final l in labels) l.region}, PhaseRegion.values.toSet());
      for (final l in labels) {
        expect(calc.regionAt(l.at.c, l.at.t), l.region);
      }
    });
  });

  group('Hebelgesetz', () {
    test('40 % Sn bei 200 °C: α + Schmelze', () {
      final l = calc.lever(40, 200)!;
      expect(l.phase1, 'α');
      expect(l.phase2, 'Schmelze');
      expect(l.c1, closeTo(16.14, 0.01));
      expect(l.c2, closeTo(54.59, 0.01));
      expect(l.fraction1, closeTo(0.379, 0.002));
    });

    test('40 % Sn bei 100 °C: α + β', () {
      final l = calc.lever(40, 100)!;
      expect(l.c1, closeTo(10.91, 0.01));
      expect(l.c2, closeTo(98.34, 0.01));
      expect(l.fraction1, closeTo(0.667, 0.002));
    });

    test('Einphasengebiet: kein Hebel, 100 % reicht', () {
      expect(calc.lever(40, 300), isNull);
      const p = PhasePart(kind: PhasePartKind.lever, c: 40, t: 300);
      expect(calc.checkLever(p, f1: 100).ok, isTrue);
      expect(calc.checkLever(p, f1: 50, f2: 50).ok, isFalse);
    });

    test('Prüfung: richtig, falsch abgelesen mit passendem Folgefehler, falsch gerechnet', () {
      const p = PhasePart(kind: PhasePartKind.lever, c: 40, t: 200);
      final right = calc.checkLever(p, c1: 16, c2: 55, f1: 38, f2: 62);
      expect(right.ok, isTrue);
      expect(right.messages.last, contains('Richtig: α 38 %'));

      // 20 und 55 abgelesen: (55 − 40) / (55 − 20) = 42,9 % – Folgefehler.
      final follow = calc.checkLever(p, c1: 20, c2: 55, f1: 42.9, f2: 57.1);
      expect(follow.ok, isFalse);
      expect(follow.messages.join(' '), contains('Folgefehler'));
      expect(follow.messages.first, contains('16,1'));

      final wrong = calc.checkLever(p, c1: 16, c2: 55, f1: 62, f2: 38);
      expect(wrong.ok, isFalse);
      expect(wrong.messages.single, contains('Anteile'));
    });
  });

  group('Gefüge, Zusammensetzung, Löslichkeit', () {
    test('Gefügeanteile unterhalb der eutektischen Temperatur', () {
      final hypo = calc.structure(40);
      expect(hypo.primary, 'α');
      expect(hypo.primaryShare, closeTo(0.502, 0.002));
      final hyper = calc.structure(80);
      expect(hyper.primary, 'β');
      expect(hyper.primaryShare, closeTo(18.1 / 35.9, 0.002));
      expect(calc.structure(61.9).primaryShare, 0);
      expect(calc.structure(10).primaryShare, 1);
      const p = PhasePart(kind: PhasePartKind.structure, c: 40);
      expect(calc.checkStructure(p, primary: 50, eutectic: 50).ok, isTrue);
      expect(calc.checkStructure(p, primary: 30, eutectic: 70).messages.single, contains('Primär α ≈ 50 %'));
    });

    test('Zusammensetzungen zu einer Liquidustemperatur (beide Seiten)', () {
      final cs = calc.compositionsForLiquidus(230);
      expect(cs, hasLength(2));
      expect(cs[0], closeTo(41.70, 0.01));
      expect(cs[1], closeTo(98.45, 0.01));
      expect(calc.compositionsForLiquidus(300), hasLength(1));
      const p = PhasePart(kind: PhasePartKind.composition, t: 230);
      expect(calc.checkComposition(p, [98, 42]).ok, isTrue);
      expect(calc.checkComposition(p, [42, null]).ok, isFalse);
      expect(calc.checkComposition(p, [42, null]).messages.single, contains('98,4'));
    });

    test('Löslichkeit und eutektische Linie', () {
      const b = PhasePart(kind: PhasePartKind.solubility);
      const a = PhasePart(kind: PhasePartKind.solubility, side: 'a');
      expect(calc.checkSolubility(b, value: 18.3, t: 183).ok, isTrue);
      expect(calc.checkSolubility(a, value: 2.2, t: 183).ok, isTrue);
      expect(calc.checkSolubility(b, value: 18.3, t: 250).messages.single, contains('183 °C'));
      expect(calc.checkEutecticLine(from: 18, to: 98).ok, isTrue);
      expect(calc.checkEutecticLine(from: 2, to: 99).ok, isFalse);
    });

    test('Gebiete benennen und Gebiet antippen', () {
      final labels = calc.regionLabels();
      expect(calc.checkRegions({for (final (i, l) in labels.indexed) i: l.region}).ok, isTrue);
      final wrong = calc.checkRegions({0: PhaseRegion.beta});
      expect(wrong.ok, isFalse);
      expect(wrong.messages.first, 'Richtig wäre:');
      const p = PhasePart(kind: PhasePartKind.pickRegion, region: PhaseRegion.liquidBeta);
      expect(calc.checkPick(p, const PhasePoint(80, 200)).ok, isTrue);
      expect(calc.checkPick(p, const PhasePoint(40, 200)).messages.single, contains('Schmelze + α'));
      expect(calc.checkPick(p, null).ok, isFalse);
    });

    test('Phasen wählen', () {
      const p = PhasePart(kind: PhasePartKind.phases, c: 40, t: 200);
      expect(calc.checkPhases(p, {'α', 'Schmelze'}).ok, isTrue);
      final wrong = calc.checkPhases(p, {'α', 'β'});
      expect(wrong.ok, isFalse);
      expect(wrong.messages.join(' '), allOf(contains('Es fehlt: Schmelze'), contains('Liegt dort nicht vor: β')));
    });
  });

  group('Abkühlkurven', () {
    test('Ereignisse: rein, untereutektisch, eutektisch, Mischkristall', () {
      expect(calc.coolingEvents(0).single.plateau, isTrue);
      expect(calc.coolingEvents(100).single.t, 232);
      final hypo = calc.coolingEvents(40);
      expect([for (final e in hypo) e.plateau], [false, true]);
      expect(hypo.last.t, 183);
      expect(calc.coolingEvents(61.9).single.t, 183);
      final solid = calc.coolingEvents(10);
      expect([for (final e in solid) e.plateau], [false, false]);
      expect(solid.last.t, closeTo(327 - 144 * 10 / 18.3, 0.01));
    });

    test('erzeugte Skizze: eine Kurve je Legierung, Musterkurven bestehen ihre eigene Prüfung', () {
      final sketch = calc.coolingSketch([0, 40, 61.9, 80]);
      expect(sketch.curveNames, ['100 % Pb', '40 % Sn', 'eutektisch (61,9 % Sn)', '80 % Sn']);
      expect(sketch.features.where((f) => f.kind == SketchFeatureKind.plateau), hasLength(4));
      expect(sketch.features.where((f) => f.kind == SketchFeatureKind.kink), hasLength(2));
      expect(SketchChecker.selfCheck(sketch), isEmpty);
      final byCurve = {for (final c in sketch.curves) c.name: c.reference};
      expect(SketchChecker.check(sketch, byCurve.values.first, const [], byCurve: byCurve).ok, isTrue);
    });

    test('Kurvennamen vom Blatt, gegebene Kurve, Frage-Teile', () {
      const cooling = PhasePart(
        kind: PhasePartKind.cooling,
        compositions: [0, 20, 61.9],
        labels: ['100 % Pb, 0 % Sn', '', 'Eutektische Legierung'],
      );
      expect(calc.curveNames(cooling), ['100 % Pb, 0 % Sn', '20 % Sn', 'Eutektische Legierung']);
      expect(calc.solutionText(cooling), contains('Eutektische Legierung: Eutektikum: Haltepunkt bei 183 °C'));

      const given = PhasePart(kind: PhasePartKind.composition, t: 230, curveGiven: true);
      final curve = calc.givenCurve(given)!;
      expect(curve.features.map((f) => f.kind), [SketchFeatureKind.kink, SketchFeatureKind.plateau]);
      expect(curve.features.first.y, closeTo(230, 1e-9));
      expect(calc.promptText(given), isNot(contains('230')));
      expect(calc.hints(given).first, contains('Knick'));
      expect(calc.solutionText(given), startsWith('Knick der Kurve bei ≈ 230 °C'));

      const choice = PhasePart(
        kind: PhasePartKind.question,
        prompt: 'Typ?',
        options: ['vollständig löslich', 'eutektisch'],
        correct: 1,
        answer: 'Begrenzte Löslichkeit im festen Zustand.',
      );
      expect(choice.isValid, isTrue);
      expect(calc.checkChoice(choice, 1).ok, isTrue);
      expect(calc.checkChoice(choice, 0).ok, isFalse);
      expect(calc.solutionText(choice), 'eutektisch – Begrenzte Löslichkeit im festen Zustand.');
      expect(const PhasePart(kind: PhasePartKind.question, prompt: 'x').isValid, isFalse);

      final parsed = PhasePart.fromMap({
        'kind': 'frage',
        'prompt': 'Typ?',
        'options': [
          {'text': 'A'},
          {'text': 'B', 'correct': true},
        ],
      })!;
      expect(parsed.correct, 1);
      expect(PhasePart.fromMap(parsed.toMap())!.toMap(), parsed.toMap());
      expect(PhasePart.fromMap(cooling.toMap())!.labels, cooling.labels);
      expect(PhasePart.fromMap(given.toMap())!.curveGiven, isTrue);
    });

    test('Stahlecke: Umwandlung statt Erstarrung, Perlit als Haltepunkt', () {
      final s = calcOf(steel);
      expect(steel.isValid, isTrue);
      expect(s.regionAt(1.2, 800), PhaseRegion.liquidBeta);
      expect(s.regionAt(0.4, 800), PhaseRegion.liquidAlpha);
      expect(s.regionAt(0.4, 900), PhaseRegion.liquid);
      expect(s.structure(0.4).primaryShare, closeTo(0.4 / 0.78, 0.001));
      expect(s.structure(1.2).primary, 'Fe₃C');
      final events = s.coolingEvents(0.4);
      expect(events.first.why, contains('Beginn der Umwandlung'));
      expect(events.last.why, contains('Perlit'));
      expect(SketchChecker.selfCheck(s.coolingSketch([0.4, 0.8, 1.2])), isEmpty);
    });
  });

  group('Modell und Texte', () {
    test('toMap/fromMap mit Teilaufgaben, gekrümmten Linien und deutschen Feldnamen', () {
      final task = PhaseTask(
        system: pbSn.copyWith(
          lines: {
            PhaseLine.liquidusLeft: const [PhasePoint(0, 327), PhasePoint(30, 260), PhasePoint(61.9, 183)],
          },
        ),
        parts: const [
          PhasePart(kind: PhasePartKind.lever, c: 40, t: 200),
          PhasePart(kind: PhasePartKind.cooling, compositions: [0, 40]),
          PhasePart(kind: PhasePartKind.solubility, side: 'a'),
          PhasePart(kind: PhasePartKind.pickRegion, region: PhaseRegion.alphaBeta, prompt: 'Wo ist α + β?'),
        ],
        uncertain: true,
      );
      final map = task.toMap();
      expect(map['kind'], 'phase');
      final back = PhaseTask.fromMap(map)!;
      expect(back.toMap(), map);
      expect(PhaseCalculator(back).liquidusT(30), closeTo(260, 1e-9));

      final german = PhaseTask.fromMap({
        'diagramm': {
          'a': 'Cu',
          'b': 'Ag',
          'tA': '1085',
          'cE': '71,9',
          'tE': 779,
          'alphaMax': 8,
          'betaMax': 91.2,
          'tB': 962,
        },
        'teilaufgaben': [
          {'art': 'Hebelgesetz', 'zusammensetzung': 30, 'temperatur': 900},
          {
            'art': 'Abkühlkurve',
            'zusammensetzungen': ['20', 71.9],
          },
          {'art': 'Gebiet', 'gebiet': 'L + α'},
          {'art': 'gibt es nicht'},
        ],
      })!;
      expect(german.system.eutecticC, 71.9);
      expect(german.system.rightT, 962);
      expect(german.system.tMax, 1194);
      expect(
        [for (final p in german.parts) p.kind],
        [PhasePartKind.lever, PhasePartKind.cooling, PhasePartKind.pickRegion],
      );
      expect(german.parts[1].compositions, [20, 71.9]);
      expect(german.parts[2].region, PhaseRegion.liquidAlpha);
      expect(german.isUsable, isTrue);
    });

    test('ohne Pflicht-Eckdaten kein Diagramm; unstimmige Eckdaten melden', () {
      expect(
        PhaseTask.fromMap({
          'system': {'meltA': 327},
          'parts': [],
        }),
        isNull,
      );
      final broken = calcOf(pbSn.copyWith(alphaMax: 70), const [PhasePart(kind: PhasePartKind.structure, c: 40)]);
      expect(broken.problems().single, contains('Eckdaten passen nicht'));
      final outside = calcOf(pbSn, const [
        PhasePart(kind: PhasePartKind.phases, c: 120, t: 500),
        PhasePart(kind: PhasePartKind.composition, t: 340),
      ]);
      expect(outside.problems(), hasLength(3));
    });

    test('Aufgabentexte, Tipps und Musterlösung', () {
      final c = calcOf(pbSn, const [
        PhasePart(kind: PhasePartKind.lever, c: 40, t: 200),
        PhasePart(kind: PhasePartKind.cooling, compositions: [40]),
        PhasePart(kind: PhasePartKind.eutecticLine),
      ]);
      expect(c.promptText(c.task.parts[0]), contains('40 % Sn und 200 °C'));
      expect(c.promptText(c.task.parts[1]), contains('Abkühlkurven für 40 % Sn'));
      expect(c.hints(c.task.parts[0]), hasLength(2));
      final solution = c.fullSolution();
      expect(solution, contains('a) 40 % Sn und 200 °C: Hebel von 16,1 (α) bis 54,6 % Sn (Schmelze)'));
      expect(solution, contains('b) 40 % Sn: Beginn der Erstarrung (Liquidus) bei 233,9 °C'));
      expect(solution, contains('c) Eutektische Linie bei 183 °C: 18,3 bis 97,8 % Sn.'));
      expect(PhaseCalculator.fmt(0.025), '0,03');
      expect(PhaseCalculator.fmt(12.0), '12');
    });
  });
}
