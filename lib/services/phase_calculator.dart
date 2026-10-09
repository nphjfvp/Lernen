import 'dart:math' as math;

import '../models/phase_task.dart';
import '../models/sketch_task.dart';

/// Hebelgesetz an einem Punkt im Zweiphasengebiet.
class PhaseLever {
  const PhaseLever({
    required this.phase1,
    required this.c1,
    required this.phase2,
    required this.c2,
    required this.fraction1,
  });

  /// Linke Phase (kleinerer B-Anteil) und ihre Zusammensetzung.
  final String phase1;
  final double c1;

  /// Rechte Phase.
  final String phase2;
  final double c2;

  /// Anteil der linken Phase (0..1).
  final double fraction1;
  double get fraction2 => 1 - fraction1;
}

/// Gefügeanteile direkt unterhalb der eutektischen Temperatur.
class PhaseStructure {
  const PhaseStructure({required this.primary, required this.primaryShare, required this.eutectic});

  /// Primär erstarrte Phase ('' = keine).
  final String primary;
  final double primaryShare;
  final String eutectic;
  double get eutecticShare => 1 - primaryShare;
}

/// Ergebnis einer Prüfung: je Eingabe eine Rückmeldung.
class PhaseCheck {
  const PhaseCheck(this.ok, this.messages);
  final bool ok;
  final List<String> messages;
}

/// Ein Knick bzw. Haltepunkt in der Abkühlkurve.
class CoolingEvent {
  const CoolingEvent({required this.t, required this.plateau, required this.why});
  final double t;
  final bool plateau;
  final String why;
}

/// Rechnet alles am Zweistoffsystem selbst – die KI liefert nur die Eckdaten.
class PhaseCalculator {
  PhaseCalculator(this.task);

  final PhaseTask task;
  PhaseSystem get s => task.system;

  /// Toleranzen beim Ablesen: 3 % der Achsen bzw. 5 Prozentpunkte bei Anteilen.
  double get cTol => s.cMax * 0.03;
  double get tTol => (s.tMax - s.tMin) * 0.03;
  static const fractionTol = 0.05;

  // ---------------------------------------------------------------------------
  // Linien
  // ---------------------------------------------------------------------------

  /// Zusammensetzung, bei der der Linienzug die Temperatur [t] hat.
  static double? cAtT(List<PhasePoint> line, double t) {
    for (var i = 0; i + 1 < line.length; i++) {
      final p = line[i], q = line[i + 1];
      final lo = math.min(p.t, q.t), hi = math.max(p.t, q.t);
      if (t < lo - 1e-9 || t > hi + 1e-9) continue;
      if ((q.t - p.t).abs() < 1e-9) return p.c;
      return p.c + (q.c - p.c) * (t - p.t) / (q.t - p.t);
    }
    return null;
  }

  /// Temperatur des Linienzugs bei der Zusammensetzung [c].
  static double? tAtC(List<PhasePoint> line, double c) {
    for (var i = 0; i + 1 < line.length; i++) {
      final p = line[i], q = line[i + 1];
      final lo = math.min(p.c, q.c), hi = math.max(p.c, q.c);
      if (c < lo - 1e-9 || c > hi + 1e-9) continue;
      if ((q.c - p.c).abs() < 1e-9) return math.max(p.t, q.t);
      return p.t + (q.t - p.t) * (c - p.c) / (q.c - p.c);
    }
    return null;
  }

  List<PhasePoint> line(PhaseLine l) => s.line(l);

  /// Liquidustemperatur (bzw. Beginn der Umwandlung) der Zusammensetzung [c].
  double liquidusT(double c) => c <= s.eutecticC
      ? (tAtC(line(PhaseLine.liquidusLeft), c) ?? s.meltA)
      : (c >= s.rightC ? s.rightT : (tAtC(line(PhaseLine.liquidusRight), c) ?? s.rightT));

  // ---------------------------------------------------------------------------
  // Gebiete, Phasen, Hebelgesetz
  // ---------------------------------------------------------------------------

  PhaseRegion regionAt(double c, double t) {
    if (t >= s.eutecticT) {
      if (c <= s.eutecticC) {
        if (t >= liquidusT(c)) return PhaseRegion.liquid;
        final solidus = cAtT(line(PhaseLine.solidusLeft), t) ?? s.alphaMax;
        return c <= solidus ? PhaseRegion.alpha : PhaseRegion.liquidAlpha;
      }
      if (t >= liquidusT(c)) return PhaseRegion.liquid;
      final solidus = cAtT(line(PhaseLine.solidusRight), t) ?? s.betaMax;
      return c >= solidus ? PhaseRegion.beta : PhaseRegion.liquidBeta;
    }
    final ca = cAtT(line(PhaseLine.solvusLeft), t) ?? s.alphaLow;
    final cb = cAtT(line(PhaseLine.solvusRight), t) ?? s.betaLow;
    if (c <= ca) return PhaseRegion.alpha;
    if (c >= cb) return PhaseRegion.beta;
    return PhaseRegion.alphaBeta;
  }

  List<String> phasesAt(double c, double t) => s.phasesOf(regionAt(c, t));

  /// Hebelgesetz – null im Einphasengebiet.
  PhaseLever? lever(double c, double t) {
    final region = regionAt(c, t);
    final (String, double?, String, double?) ends = switch (region) {
      PhaseRegion.liquidAlpha => (
        s.alpha,
        cAtT(line(PhaseLine.solidusLeft), t),
        s.liquid,
        cAtT(line(PhaseLine.liquidusLeft), t),
      ),
      PhaseRegion.liquidBeta => (
        s.liquid,
        cAtT(line(PhaseLine.liquidusRight), t),
        s.beta,
        cAtT(line(PhaseLine.solidusRight), t),
      ),
      PhaseRegion.alphaBeta => (
        s.alpha,
        cAtT(line(PhaseLine.solvusLeft), t),
        s.beta,
        cAtT(line(PhaseLine.solvusRight), t),
      ),
      _ => ('', null, '', null),
    };
    final (p1, c1, p2, c2) = ends;
    if (c1 == null || c2 == null || (c2 - c1).abs() < 1e-9) return null;
    return PhaseLever(phase1: p1, c1: c1, phase2: p2, c2: c2, fraction1: ((c2 - c) / (c2 - c1)).clamp(0.0, 1.0));
  }

  PhaseStructure structure(double c) {
    final none = PhaseStructure(primary: '', primaryShare: 0, eutectic: s.eutecticName);
    if (c <= s.alphaMax) return PhaseStructure(primary: s.alpha, primaryShare: 1, eutectic: s.eutecticName);
    if (c >= s.betaMax) return PhaseStructure(primary: s.beta, primaryShare: 1, eutectic: s.eutecticName);
    if ((c - s.eutecticC).abs() <= s.cMax * 0.004) return none;
    if (c < s.eutecticC) {
      return PhaseStructure(
        primary: s.alpha,
        primaryShare: (s.eutecticC - c) / (s.eutecticC - s.alphaMax),
        eutectic: s.eutecticName,
      );
    }
    return PhaseStructure(
      primary: s.beta,
      primaryShare: (c - s.eutecticC) / (s.betaMax - s.eutecticC),
      eutectic: s.eutecticName,
    );
  }

  /// Zusammensetzungen, deren Erstarrung (Umwandlung) bei [t] beginnt.
  List<double> compositionsForLiquidus(double t) => [
    if (t >= s.eutecticT - 1e-9 && t <= s.meltA + 1e-9) ?cAtT(line(PhaseLine.liquidusLeft), t),
    if (t >= s.eutecticT - 1e-9 && t <= s.rightT + 1e-9) ?cAtT(line(PhaseLine.liquidusRight), t),
  ];

  // ---------------------------------------------------------------------------
  // Abkühlkurven
  // ---------------------------------------------------------------------------

  String get _solidify => s.eutectoid ? 'Umwandlung' : 'Erstarrung';

  /// Knicke und Haltepunkte beim langsamen Abkühlen von [c].
  List<CoolingEvent> coolingEvents(double c) {
    final eps = s.cMax * 0.002;
    if (c <= eps) {
      return [CoolingEvent(t: s.meltA, plateau: true, why: 'reines ${s.a}: Haltepunkt bei ${fmt(s.meltA)} °C')];
    }
    if (c >= s.cMax - eps && s.rightC >= s.cMax - eps) {
      return [CoolingEvent(t: s.rightT, plateau: true, why: 'reines ${s.b}: Haltepunkt bei ${fmt(s.rightT)} °C')];
    }
    final tl = liquidusT(c);
    if ((c - s.eutecticC).abs() <= s.cMax * 0.004) {
      return [
        CoolingEvent(t: s.eutecticT, plateau: true, why: '${s.eutecticName}: Haltepunkt bei ${fmt(s.eutecticT)} °C'),
      ];
    }
    if (c <= s.alphaMax || c >= s.betaMax) {
      final ts = c <= s.alphaMax
          ? (tAtC(line(PhaseLine.solidusLeft), c) ?? s.eutecticT)
          : (tAtC(line(PhaseLine.solidusRight), c) ?? s.eutecticT);
      return [
        CoolingEvent(t: tl, plateau: false, why: 'Beginn der $_solidify (Liquidus) bei ${fmt(tl)} °C'),
        CoolingEvent(t: ts, plateau: false, why: 'Ende der $_solidify (Solidus) bei ${fmt(ts)} °C'),
      ];
    }
    return [
      CoolingEvent(t: tl, plateau: false, why: 'Beginn der $_solidify (Liquidus) bei ${fmt(tl)} °C'),
      CoolingEvent(
        t: s.eutecticT,
        plateau: true,
        why: 'Rest wird ${s.eutecticName}: Haltepunkt bei ${fmt(s.eutecticT)} °C',
      ),
    ];
  }

  String curveName(double c) => '${fmt(c)} % ${s.b}';

  /// Die Abkühlkurven als Skizze (T über t, je Zusammensetzung eine Kurve,
  /// zeitlich versetzt) – geprüft an Knicken und Haltepunkten.
  SketchTask coolingSketch(List<double> compositions) {
    final range = s.tMax - s.tMin;
    final liquid = range / 25, twoPhase = range / 80, solid = range / 30;
    const plateau = 14.0, offset = 20.0;
    final curves = <SketchNamedCurve>[];
    final features = <SketchFeature>[];
    var maxEnd = 0.0;
    for (final (i, c) in compositions.indexed) {
      final events = coolingEvents(c);
      final name = curveName(c);
      final first = events.first.t;
      var t = i * offset, temp = math.min(s.tMax, first + 0.15 * range);
      final pts = <SketchPoint>[SketchPoint(t, temp)];
      void go(double to, double rate) {
        t += (temp - to).abs() / rate;
        temp = to;
        pts.add(SketchPoint(t, temp));
      }

      for (final (k, e) in events.indexed) {
        // Bis zum ersten Ereignis kühlt die Schmelze schnell ab, danach langsamer.
        go(e.t, k == 0 ? liquid : twoPhase);
        if (e.plateau) {
          t += plateau;
          pts.add(SketchPoint(t, temp));
        }
        features.add(
          SketchFeature(
            kind: e.plateau ? SketchFeatureKind.plateau : SketchFeatureKind.kink,
            y: e.t,
            curve: name,
            tol: 0.06,
            text: e.why,
          ),
        );
      }
      go(math.max(s.tMin + 0.08 * range, temp - 0.35 * range), solid);
      maxEnd = math.max(maxEnd, t);
      curves.add(SketchNamedCurve(name: name, reference: [pts]));
    }
    return SketchTask(
      xAxis: SketchAxis(label: 'Zeit t', min: 0, max: (maxEnd + 5).ceilToDouble(), showNumbers: false),
      yAxis: SketchAxis(label: 'T in °C', min: s.tMin, max: s.tMax),
      curves: curves,
      features: features,
    );
  }

  // ---------------------------------------------------------------------------
  // Gebiete beschriften
  // ---------------------------------------------------------------------------

  /// Stellen für die Beschriftung der sichtbaren Gebiete (in Achsen-Einheiten).
  List<({PhaseRegion region, PhasePoint at})> regionLabels() {
    final out = <({PhaseRegion region, PhasePoint at})>[];
    void add(PhaseRegion r, double? c, double t) {
      if (c == null || c < 0 || c > s.cMax || t < s.tMin || t > s.tMax) return;
      if (regionAt(c, t) != r) return;
      out.add((region: r, at: PhasePoint(c, t)));
    }

    final top = math.max(s.meltA, s.rightT);
    add(PhaseRegion.liquid, s.eutecticC, math.min(s.tMax - (s.tMax - s.tMin) * 0.06, (top + s.tMax) / 2));
    final tl = s.eutecticT + (s.meltA - s.eutecticT) * 0.35;
    final la = cAtT(line(PhaseLine.solidusLeft), tl), ll = cAtT(line(PhaseLine.liquidusLeft), tl);
    add(PhaseRegion.liquidAlpha, la == null || ll == null ? null : (la + ll) / 2, tl);
    final tr = s.eutecticT + (s.rightT - s.eutecticT) * 0.35;
    final lr = cAtT(line(PhaseLine.liquidusRight), tr), sr = cAtT(line(PhaseLine.solidusRight), tr);
    add(PhaseRegion.liquidBeta, lr == null || sr == null ? null : (lr + math.min(sr, s.cMax)) / 2, tr);
    final tb = s.eutecticT - (s.eutecticT - s.tMin) * 0.3;
    add(PhaseRegion.alpha, (cAtT(line(PhaseLine.solvusLeft), tb) ?? s.alphaLow) / 2, tb);
    final cb = cAtT(line(PhaseLine.solvusRight), tb) ?? s.betaLow;
    add(PhaseRegion.beta, (cb + s.cMax) / 2, tb);
    add(PhaseRegion.alphaBeta, s.eutecticC, s.tMin + (s.eutecticT - s.tMin) * 0.5);
    return out;
  }

  // ---------------------------------------------------------------------------
  // Aufgabentexte, Prüfung, Tipps, Lösung
  // ---------------------------------------------------------------------------

  static String fmt(double v, {int digits = 1}) {
    if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
    final f = v.toStringAsFixed(v.abs() < 1 ? 2 : digits);
    // Nur Nachkommanullen kürzen ("50" bleibt "50").
    if (!f.contains('.')) return f;
    return f.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '').replaceAll('.', ',');
  }

  String _at(PhasePart p) => '${fmt(p.c ?? 0)} % ${s.b} und ${fmt(p.t ?? 0)} °C';

  String promptText(PhasePart p) {
    if (p.prompt.trim().isNotEmpty) return p.prompt.trim();
    return switch (p.kind) {
      PhasePartKind.phases => 'Welche Phasen liegen bei ${_at(p)} vor?',
      PhasePartKind.lever =>
        'Hebelgesetz bei ${_at(p)}: Wie sind die beiden Phasen zusammengesetzt, und wie groß sind ihre Anteile?',
      PhasePartKind.structure =>
        'Gefügeanteile einer Legierung mit ${fmt(p.c ?? 0)} % ${s.b} direkt unterhalb von ${fmt(s.eutecticT)} °C?',
      PhasePartKind.cooling =>
        'Zeichne die Abkühlkurven für ${[for (final c in p.compositions) curveName(c)].join(', ')}.',
      PhasePartKind.composition => 'Bei welchen Zusammensetzungen beginnt die $_solidify bei ${fmt(p.t ?? 0)} °C?',
      PhasePartKind.solubility =>
        p.side == 'a'
            ? 'Wie groß ist die maximale Löslichkeit von ${s.a} in ${s.beta}, und bei welcher Temperatur?'
            : 'Wie groß ist die maximale Löslichkeit von ${s.b} in ${s.alpha}, und bei welcher Temperatur?',
      PhasePartKind.eutecticLine =>
        'Über welchen ${s.b}-Bereich reicht die ${s.eutectoid ? 'eutektoide' : 'eutektische'} Linie?',
      PhasePartKind.regions => 'Benenne die nummerierten Gebiete im Diagramm.',
      PhasePartKind.pickRegion => 'Tippe im Diagramm das Gebiet „${s.regionName(p.region!)}“ an.',
    };
  }

  static bool _near(double? v, double target, double tol) => v != null && (v - target).abs() <= tol;

  PhaseCheck checkPhases(PhasePart p, Set<String> chosen) {
    final expected = phasesAt(p.c!, p.t!).toSet();
    final ok = chosen.length == expected.length && chosen.containsAll(expected);
    if (ok) return PhaseCheck(true, ['Richtig: ${expected.join(' + ')}.']);
    final missing = expected.difference(chosen), extra = chosen.difference(expected);
    return PhaseCheck(false, [
      if (missing.isNotEmpty) 'Es fehlt: ${missing.join(', ')}.',
      if (extra.isNotEmpty) 'Liegt dort nicht vor: ${extra.join(', ')}.',
      'Schau, in welchem Gebiet der Punkt liegt (${_at(p)}).',
    ]);
  }

  /// [c1]/[c2]: abgelesene Zusammensetzungen (links/rechts), [f1]/[f2]: Anteile in %.
  PhaseCheck checkLever(PhasePart p, {double? c1, double? c2, double? f1, double? f2}) {
    final l = lever(p.c!, p.t!);
    if (l == null) {
      final phase = phasesAt(p.c!, p.t!).single;
      final ok = _near(f1, 100, 5) || _near(f2, 100, 5);
      return PhaseCheck(ok, [
        ok ? 'Richtig: nur $phase – 100 %.' : 'Der Punkt liegt im Einphasengebiet: 100 % $phase.',
      ]);
    }
    final msgs = <String>[];
    var ok = true;
    final readOk1 = _near(c1, l.c1, cTol), readOk2 = _near(c2, l.c2, cTol);
    if (!readOk1) {
      ok = false;
      msgs.add('${l.phase1}: Zusammensetzung ≈ ${fmt(l.c1)} % ${s.b} (linkes Ende des Hebels bei ${fmt(p.t!)} °C).');
    }
    if (!readOk2) {
      ok = false;
      msgs.add('${l.phase2}: Zusammensetzung ≈ ${fmt(l.c2)} % ${s.b} (rechtes Ende des Hebels).');
    }
    // Folgefehler: mit den eigenen Ablesewerten richtig gerechnet zählt.
    double? own(double? a, double? b) =>
        a == null || b == null || (b - a).abs() < 1e-9 ? null : ((b - p.c!) / (b - a)) * 100;
    final ownF1 = own(c1, c2);
    bool fractionOk(double? given, double exact, double? ownValue) =>
        _near(given, exact, fractionTol * 100) || (ownValue != null && _near(given, ownValue, 2));
    final fOk1 = fractionOk(f1, l.fraction1 * 100, ownF1);
    final fOk2 = fractionOk(f2, l.fraction2 * 100, ownF1 == null ? null : 100 - ownF1);
    if (!fOk1 || !fOk2) {
      ok = false;
      msgs.add(
        'Anteile: ${l.phase1} = (${fmt(l.c2)} − ${fmt(p.c!)}) / (${fmt(l.c2)} − ${fmt(l.c1)}) ≈ ${fmt(l.fraction1 * 100, digits: 0)} %, '
        '${l.phase2} ≈ ${fmt(l.fraction2 * 100, digits: 0)} %.',
      );
    } else if (!readOk1 || !readOk2) {
      msgs.add('Die Anteile passen zu deinen Ablesewerten (Folgefehler).');
    }
    if (ok) {
      msgs.add(
        'Richtig: ${l.phase1} ${fmt(l.fraction1 * 100, digits: 0)} %, ${l.phase2} ${fmt(l.fraction2 * 100, digits: 0)} %.',
      );
    }
    return PhaseCheck(ok, msgs);
  }

  PhaseCheck checkStructure(PhasePart p, {double? primary, double? eutectic}) {
    final st = structure(p.c!);
    final okP = _near(primary, st.primaryShare * 100, fractionTol * 100);
    final okE = _near(eutectic, st.eutecticShare * 100, fractionTol * 100);
    if (okP && okE) return const PhaseCheck(true, ['Richtig.']);
    return PhaseCheck(false, [
      st.primary.isEmpty || st.primaryShare == 0
          ? 'Die Legierung ist (nahezu) eutektisch: 100 % ${st.eutectic}.'
          : st.primaryShare >= 1
          ? 'Hier entsteht kein ${st.eutectic}: 100 % ${st.primary}.'
          : 'Primär ${st.primary} ≈ ${fmt(st.primaryShare * 100, digits: 0)} %, ${st.eutectic} ≈ ${fmt(st.eutecticShare * 100, digits: 0)} % '
                '(Hebel zwischen ${fmt(st.primary == s.alpha ? s.alphaMax : s.betaMax)} und ${fmt(s.eutecticC)} % ${s.b}).',
    ]);
  }

  PhaseCheck checkComposition(PhasePart p, List<double?> given) {
    final expected = compositionsForLiquidus(p.t!);
    if (expected.isEmpty) {
      return PhaseCheck(given.every((g) => g == null), ['Bei ${fmt(p.t!)} °C beginnt keine $_solidify.']);
    }
    final remaining = [...given.whereType<double>()];
    final msgs = <String>[];
    var ok = remaining.length == expected.length;
    for (final e in expected) {
      final hit = remaining.indexWhere((g) => (g - e).abs() <= cTol);
      if (hit < 0) {
        ok = false;
        msgs.add('Gesucht ist auch ≈ ${fmt(e)} % ${s.b} (Liquidus bei ${fmt(p.t!)} °C).');
      } else {
        remaining.removeAt(hit);
      }
    }
    if (remaining.isNotEmpty) ok = false;
    return PhaseCheck(
      ok,
      ok
          ? [
              'Richtig: ${[for (final e in expected) '${fmt(e)} %'].join(' und ')}.',
            ]
          : msgs,
    );
  }

  ({double value, double t}) solubility(String side) =>
      side == 'a' ? (value: s.cMax - s.betaMax, t: s.eutecticT) : (value: s.alphaMax, t: s.eutecticT);

  PhaseCheck checkSolubility(PhasePart p, {double? value, double? t}) {
    final sol = solubility(p.side);
    final okV = _near(value, sol.value, cTol), okT = _near(t, sol.t, tTol);
    if (okV && okT) return const PhaseCheck(true, ['Richtig.']);
    return PhaseCheck(false, [
      if (!okV) 'Maximal ≈ ${fmt(sol.value)} % (Ende der ${s.eutectoid ? 'eutektoiden' : 'eutektischen'} Linie).',
      if (!okT) 'Am größten bei der ${s.eutectoid ? 'eutektoiden' : 'eutektischen'} Temperatur ${fmt(sol.t)} °C.',
    ]);
  }

  PhaseCheck checkEutecticLine({double? from, double? to}) {
    final okF = _near(from, s.alphaMax, cTol), okT = _near(to, s.betaMax, cTol);
    if (okF && okT) return const PhaseCheck(true, ['Richtig.']);
    return PhaseCheck(false, [
      'Die Linie bei ${fmt(s.eutecticT)} °C reicht von ${fmt(s.alphaMax)} bis ${fmt(s.betaMax)} % ${s.b}.',
    ]);
  }

  PhaseCheck checkRegions(Map<int, PhaseRegion?> answers) {
    final labels = regionLabels();
    final msgs = <String>[];
    var ok = true;
    for (final (i, l) in labels.indexed) {
      if (answers[i] != l.region) {
        ok = false;
        msgs.add('${i + 1}: ${s.regionName(l.region)}');
      }
    }
    return PhaseCheck(ok, ok ? ['Alle Gebiete richtig benannt.'] : ['Richtig wäre:', ...msgs]);
  }

  PhaseCheck checkPick(PhasePart p, PhasePoint? tapped) {
    if (tapped == null) return const PhaseCheck(false, ['Tippe eine Stelle im Diagramm an.']);
    final got = regionAt(tapped.c, tapped.t);
    if (got == p.region) return PhaseCheck(true, ['Richtig: ${s.regionName(got)}.']);
    return PhaseCheck(false, ['Dort liegt „${s.regionName(got)}“ – gesucht ist „${s.regionName(p.region!)}“.']);
  }

  /// Gestufte Tipps.
  List<String> hints(PhasePart p) => switch (p.kind) {
    PhasePartKind.phases => [
      'Suche den Punkt ${_at(p)} im Diagramm.',
      'Im Gebiet „${s.regionName(regionAt(p.c!, p.t!))}“ liegen genau diese Phasen vor.',
    ],
    PhasePartKind.lever => [
      'Zeichne bei ${fmt(p.t!)} °C eine waagerechte Linie durch den Punkt bis zu den Grenzen des Zweiphasengebiets.',
      'Die Enden geben die Zusammensetzungen der Phasen an; der Anteil einer Phase ist der GEGENÜBERLIEGENDE Hebelarm geteilt durch die ganze Länge.',
    ],
    PhasePartKind.structure => [
      'Hebel direkt unterhalb der eutektischen Temperatur: zwischen dem Ende der eutektischen Linie und dem eutektischen Punkt.',
      'Primär = (c_E − c) / (c_E − c_α) auf der linken Seite (rechts entsprechend).',
    ],
    PhasePartKind.cooling => [
      'Wo die Legierung die Liquiduslinie schneidet, wird die Kurve flacher (Knick) – Kristallisationswärme.',
      'Bei der ${s.eutectoid ? 'eutektoiden' : 'eutektischen'} Temperatur bleibt die Temperatur stehen (Haltepunkt); reine Stoffe haben nur einen Haltepunkt.',
    ],
    PhasePartKind.composition => [
      'Zeichne bei ${fmt(p.t!)} °C eine Waagerechte – wo schneidet sie die Liquiduslinien?',
    ],
    PhasePartKind.solubility => ['Die Löslichkeit ist dort am größten, wo das Mischkristallgebiet am breitesten ist.'],
    PhasePartKind.eutecticLine => ['Die eutektische Linie ist die Waagerechte bei ${fmt(s.eutecticT)} °C.'],
    PhasePartKind.regions => [
      'Oben ist alles ${s.liquid}, an den Rändern die Mischkristalle, dazwischen Zweiphasengebiete.',
    ],
    PhasePartKind.pickRegion => ['Gesucht: ${s.regionName(p.region!)}.'],
  };

  /// Musterlösung einer Teilaufgabe als Text.
  String solutionText(PhasePart p) {
    switch (p.kind) {
      case PhasePartKind.phases:
        return '${_at(p)}: ${phasesAt(p.c!, p.t!).join(' + ')} (Gebiet „${s.regionName(regionAt(p.c!, p.t!))}“).';
      case PhasePartKind.lever:
        final l = lever(p.c!, p.t!);
        if (l == null) return '${_at(p)}: Einphasengebiet – 100 % ${phasesAt(p.c!, p.t!).single}.';
        return '${_at(p)}: Hebel von ${fmt(l.c1)} (${l.phase1}) bis ${fmt(l.c2)} % ${s.b} (${l.phase2}).\n'
            '${l.phase1} = (${fmt(l.c2)} − ${fmt(p.c!)}) / (${fmt(l.c2)} − ${fmt(l.c1)}) ≈ ${fmt(l.fraction1 * 100, digits: 0)} %, '
            '${l.phase2} ≈ ${fmt(l.fraction2 * 100, digits: 0)} %.';
      case PhasePartKind.structure:
        final st = structure(p.c!);
        if (st.primaryShare >= 1) return '${fmt(p.c!)} % ${s.b}: 100 % ${st.primary}, kein ${st.eutectic}.';
        if (st.primaryShare == 0) return '${fmt(p.c!)} % ${s.b}: 100 % ${st.eutectic}.';
        return '${fmt(p.c!)} % ${s.b}: primär ${st.primary} ≈ ${fmt(st.primaryShare * 100, digits: 0)} %, '
            '${st.eutectic} ≈ ${fmt(st.eutecticShare * 100, digits: 0)} %.';
      case PhasePartKind.cooling:
        return [
          for (final c in p.compositions) '${curveName(c)}: ${[for (final e in coolingEvents(c)) e.why].join('; ')}',
        ].join('\n');
      case PhasePartKind.composition:
        final cs = compositionsForLiquidus(p.t!);
        return cs.isEmpty
            ? 'Bei ${fmt(p.t!)} °C beginnt keine $_solidify.'
            : 'Liquidus bei ${fmt(p.t!)} °C: ${[for (final c in cs) '${fmt(c)} % ${s.b}'].join(' und ')}.';
      case PhasePartKind.solubility:
        final sol = solubility(p.side);
        return 'Maximal ${fmt(sol.value)} % bei ${fmt(sol.t)} °C.';
      case PhasePartKind.eutecticLine:
        return '${s.eutectoid ? 'Eutektoide' : 'Eutektische'} Linie bei ${fmt(s.eutecticT)} °C: '
            '${fmt(s.alphaMax)} bis ${fmt(s.betaMax)} % ${s.b}.';
      case PhasePartKind.regions:
        return [for (final (i, l) in regionLabels().indexed) '${i + 1}: ${s.regionName(l.region)}'].join('\n');
      case PhasePartKind.pickRegion:
        return 'Gebiet „${s.regionName(p.region!)}“.';
    }
  }

  String fullSolution() =>
      [for (final (i, p) in task.parts.indexed) '${String.fromCharCode(97 + i)}) ${solutionText(p)}'].join('\n');

  /// Unstimmigkeiten in den Eckdaten (Hinweis beim Speichern).
  List<String> problems() {
    final out = <String>[];
    if (!s.isValid) {
      out.add(
        'Die Eckdaten passen nicht zusammen (Schmelzpunkte über der eutektischen Temperatur, '
        'Löslichkeitsgrenzen links bzw. rechts vom eutektischen Punkt).',
      );
      return out;
    }
    for (final (i, p) in task.parts.indexed) {
      final name = '${String.fromCharCode(97 + i)})';
      if (p.c != null && (p.c! < 0 || p.c! > s.cMax)) out.add('$name: ${fmt(p.c!)} % liegt außerhalb des Diagramms.');
      if (p.t != null && (p.t! < s.tMin || p.t! > s.tMax)) {
        out.add('$name: ${fmt(p.t!)} °C liegt außerhalb des Diagramms.');
      }
      if (p.kind == PhasePartKind.composition && p.t != null && compositionsForLiquidus(p.t!).isEmpty) {
        out.add('$name: Bei ${fmt(p.t!)} °C schneidet keine Liquiduslinie.');
      }
      if (p.kind == PhasePartKind.regions && regionLabels().length < 3) out.add('$name: Zu wenige Gebiete sichtbar.');
    }
    return out;
  }
}
