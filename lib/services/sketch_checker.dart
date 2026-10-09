import 'dart:math' as math;

import '../models/sketch_task.dart';

/// Eine gesetzte Markierung (Name + Stelle in Achsen-Einheiten).
class SketchMark {
  const SketchMark(this.label, this.point);
  final String label;
  final SketchPoint point;
}

/// Eine gezeichnete Kurve in normierten Koordinaten (0..1 je Achse).
/// Senkrechte Stücke (ein Sprung) zählen nicht als Funktionswert; wo
/// mehrere Linien übereinander liegen, gilt ihr Mittel.
class SketchCurve {
  SketchCurve(SketchTask task, List<List<SketchPoint>> strokes)
    : _segments = [
        for (final s in strokes)
          for (var i = 0; i + 1 < s.length; i++)
            (
              task.xAxis.norm(s[i].x),
              task.yAxis.norm(s[i].y),
              task.xAxis.norm(s[i + 1].x),
              task.yAxis.norm(s[i + 1].y),
            ),
      ],
      _points = [
        for (final s in strokes)
          for (final p in s) (task.xAxis.norm(p.x), task.yAxis.norm(p.y)),
      ];

  final List<(double, double, double, double)> _segments;
  final List<(double, double)> _points;

  bool get isEmpty => _points.length < 2;
  double get uMin => _points.map((p) => p.$1).reduce(math.min);
  double get uMax => _points.map((p) => p.$1).reduce(math.max);

  /// Höhe der Kurve an der Stelle [u] (null = dort nichts gezeichnet).
  double? vAt(double u) {
    var sum = 0.0;
    var n = 0;
    for (final (x1, y1, x2, y2) in _segments) {
      final lo = math.min(x1, x2), hi = math.max(x1, x2);
      if (hi - lo < 1e-6 || u < lo || u > hi) continue;
      sum += y1 + (y2 - y1) * (u - x1) / (x2 - x1);
      n++;
    }
    return n == 0 ? null : sum / n;
  }

  /// Abtastwerte im Bereich [a]..[b] (nur wo gezeichnet ist).
  List<(double, double)> samples(double a, double b, [int n = 40]) => [
    for (var i = 0; i <= n; i++)
      if (vAt(a + (b - a) * i / n) case final v?) (a + (b - a) * i / n, v),
  ];

  (double, double)? get maxPoint => _extreme(true);
  (double, double)? get minPoint => _extreme(false);

  (double, double)? _extreme(bool max) {
    if (isEmpty) return null;
    final s = samples(uMin, uMax, 200);
    if (s.isEmpty) return null;
    return s.reduce((a, b) => (max ? b.$2 > a.$2 : b.$2 < a.$2) ? b : a);
  }

  /// Steigung (normiert) der Ausgleichsgeraden im Bereich [a]..[b]; null,
  /// wenn dort zu wenig gezeichnet ist.
  double? slope(double a, double b) {
    final s = samples(a, b, 30);
    if (s.length < 6) return null;
    final mu = s.map((p) => p.$1).reduce((x, y) => x + y) / s.length;
    final mv = s.map((p) => p.$2).reduce((x, y) => x + y) / s.length;
    var num = 0.0, den = 0.0;
    for (final (u, v) in s) {
      num += (u - mu) * (v - mv);
      den += (u - mu) * (u - mu);
    }
    return den < 1e-9 ? null : num / den;
  }

  /// Waagerechte Stücke im Bereich [a]..[b] (Steigung über ein kurzes Stück
  /// klein): (Anfang, Ende, mittlere Höhe).
  List<(double, double, double)> flatRuns(double a, double b, {double maxSlope = 0.4}) {
    const step = 0.004, span = 5;
    final s = samples(a, b, ((b - a) / step).ceil().clamp(2, 500));
    bool flat(int i) {
      final du = s[i + span].$1 - s[i].$1;
      return du > 1e-6 && ((s[i + span].$2 - s[i].$2) / du).abs() <= maxSlope;
    }

    final runs = <(double, double, double)>[];
    var i = 0;
    while (i + span < s.length) {
      if (!flat(i)) {
        i++;
        continue;
      }
      var j = i;
      while (j + 1 + span < s.length && flat(j + 1)) {
        j++;
      }
      final part = s.sublist(i, j + span + 1);
      runs.add((part.first.$1, part.last.$1, part.map((p) => p.$2).reduce((x, y) => x + y) / part.length));
      i = j + 1;
    }
    return runs;
  }

  /// Wo die Kurve die Höhe [v] erreicht (Stellen u).
  List<double> crossings(double v) {
    if (isEmpty) return const [];
    final s = samples(uMin, uMax, 300);
    return [
      for (var i = 0; i + 1 < s.length; i++)
        if ((s[i].$2 - v) * (s[i + 1].$2 - v) <= 0 && s[i].$2 != s[i + 1].$2) (s[i].$1 + s[i + 1].$1) / 2,
    ];
  }

  /// Wie deutlich die Steigung an der Stelle [u] wechselt (Verhältnis der
  /// Steigungen links und rechts, ≥ 1; Vorzeichenwechsel zählt hoch).
  double kinkScore(double u, {double w = 0.06}) {
    final l = slope(u - w, u - 0.004), r = slope(u + 0.004, u + w);
    if (l == null || r == null) return 0;
    if (l * r < 0 && (l - r).abs() > 0.3) return 3;
    final big = math.max(l.abs(), r.abs()), small = math.max(math.min(l.abs(), r.abs()), 0.05);
    return big / small;
  }

  /// Wo die Kurve am stärksten fällt (bzw. steigt) im Bereich [a]..[b] –
  /// gemessen über ein kurzes Stück (2 % der Achse), damit auch ein steil,
  /// aber nicht ganz senkrecht gezeichneter Sprung zählt. (Stelle, Höhe des Sprungs)
  (double, double)? steepestChange(double a, double b, {required bool down}) {
    const step = 0.005, span = 4;
    final s = samples(a, b, ((b - a) / step).ceil().clamp(2, 400));
    if (s.length <= span) return null;
    (double, double)? best;
    for (var i = 0; i + span < s.length; i++) {
      final d = s[i + span].$2 - s[i].$2;
      final score = down ? -d : d;
      if (best == null || score > best.$2) best = ((s[i].$1 + s[i + span].$1) / 2, score);
    }
    return best;
  }
}

/// Ergebnis eines Merkmals.
class SketchFeatureResult {
  const SketchFeatureResult(this.feature, this.ok, this.message);
  final SketchFeature feature;
  final bool ok;
  final String message;
}

class SketchVerdict {
  const SketchVerdict(this.results);
  final List<SketchFeatureResult> results;

  bool get ok => results.every((r) => r.ok);
  int get passed => results.where((r) => r.ok).length;
  String get summary => ok ? 'Alle Merkmale stimmen!' : '$passed von ${results.length} Merkmalen stimmen.';
}

/// Prüft eine Skizze grob anhand der Merkmale – nicht pixelgenau: es
/// zählen Verlauf (steigt/fällt/gerade), Sprünge, Extremstellen, Anfang/Ende
/// und Markierungen in der Nähe der richtigen Stelle.
class SketchChecker {
  const SketchChecker._();

  static String _x(SketchTask t, double? x) {
    if (x == null) return '';
    final v = (x - x.roundToDouble()).abs() < 1e-9 ? x.round().toString() : x.toStringAsFixed(2);
    return v.replaceAll('.', ',');
  }

  /// Eine Stelle aus der Zeichnung, gerundet auf etwa 1 % der Achse.
  static String _pos(SketchAxis axis, double value) {
    final digits = (-(math.log((axis.max - axis.min) / 100) / math.ln10).floor()).clamp(0, 4);
    return '≈ ${value.toStringAsFixed(digits).replaceAll('.', ',')}';
  }

  static String _what(SketchFeature f) => f.text.trim().isNotEmpty ? ' (${f.text.trim()})' : '';

  /// [strokes] = die gezeichnete (erste) Kurve; bei mehreren Kurven
  /// [byCurve] = Striche je Kurvenname.
  static SketchVerdict check(
    SketchTask task,
    List<List<SketchPoint>> strokes,
    List<SketchMark> marks, {
    Map<String, List<List<SketchPoint>>>? byCurve,
  }) {
    final drawn = byCurve ?? {task.curves.first.name: strokes};
    final curves = {for (final c in task.curves) c.name: SketchCurve(task, drawn[c.name] ?? const [])};
    return SketchVerdict([
      for (final f in task.features)
        _named(task, f, _check(task, curves[task.resolve(f.curve)] ?? SketchCurve(task, const []), marks, f, curves)),
    ]);
  }

  /// Bei mehreren Kurven: welche gemeint ist.
  static SketchFeatureResult _named(SketchTask task, SketchFeature f, SketchFeatureResult r) {
    if (!task.isMulti || f.kind.isComparison) return r;
    return SketchFeatureResult(r.feature, r.ok, '${task.resolve(f.curve)}: ${r.message}');
  }

  static SketchFeatureResult _check(
    SketchTask task,
    SketchCurve curve,
    List<SketchMark> marks,
    SketchFeature f,
    Map<String, SketchCurve> curves,
  ) {
    SketchFeatureResult ok(String m) => SketchFeatureResult(f, true, m);
    SketchFeatureResult no(String m) => SketchFeatureResult(f, false, m);
    final xs = task.xAxis, ys = task.yAxis;
    double nx(double? x) => xs.norm(x ?? xs.min);
    if (curve.isEmpty && f.kind.isComparison) return no('Zeichne auch „${task.resolve(f.curve)}“.');
    if (curve.isEmpty && f.kind != SketchFeatureKind.mark) {
      return no(task.isMulti ? 'Diese Kurve fehlt noch.' : 'Noch keine Kurve gezeichnet.');
    }

    switch (f.kind) {
      case SketchFeatureKind.plateau:
        final target = ys.norm(f.y!), tol = math.max(f.tol, 0.04);
        final a = f.x == null ? curve.uMin : math.max(curve.uMin, nx(f.x) - f.tol);
        final b = f.x2 == null ? curve.uMax : math.min(curve.uMax, nx(f.x2) + f.tol);
        final runs = b - a < 0.02 ? <(double, double, double)>[] : curve.flatRuns(a, b);
        final long = [for (final r in runs) if (r.$2 - r.$1 >= 0.035) r];
        if (long.any((r) => (r.$3 - target).abs() <= tol)) return ok('Haltepunkt bei ${_x(task, f.y)}.');
        if (long.isNotEmpty) {
          final nearest = long.reduce((p, q) => (p.$3 - target).abs() <= (q.$3 - target).abs() ? p : q);
          return no('Der Haltepunkt liegt bei ${_pos(ys, ys.denorm(nearest.$3))} statt bei ${_x(task, f.y)}${_what(f)}.');
        }
        return no('Bei ${_x(task, f.y)} fehlt der Haltepunkt – ein waagerechtes Stück${_what(f)}.');

      case SketchFeatureKind.kink:
        final candidates = f.y != null
            ? [
                for (final u in curve.crossings(ys.norm(f.y!)))
                  if (f.x == null || (u - nx(f.x)).abs() <= f.tol * 2) u,
              ]
            : [for (var i = 0; i <= 10; i++) nx(f.x) - f.tol + 2 * f.tol * i / 10];
        final where = f.y != null ? 'bei ${_x(task, f.y)}' : 'bei x ≈ ${_x(task, f.x)}';
        if (candidates.isEmpty) return no('Die Kurve soll $where einen Knick haben${_what(f)}.');
        // Etwas Spielraum: der Knick darf knapp neben der Stelle sitzen.
        final probes = [
          for (final u in candidates)
            for (var d = -0.04; d <= 0.0401; d += 0.01) u + d,
        ];
        final best = probes.map(curve.kinkScore).reduce(math.max);
        return best >= 1.5 ? ok('Knick $where.') : no('$where soll die Kurve einen deutlichen Knick haben${_what(f)}.');

      case SketchFeatureKind.above:
      case SketchFeatureKind.below:
      case SketchFeatureKind.parallel:
      case SketchFeatureKind.steeper:
      case SketchFeatureKind.maxEarlier:
      case SketchFeatureKind.maxHigher:
        return _compare(task, f, curve, curves[task.resolve(f.other)], ok, no);


      case SketchFeatureKind.rising:
      case SketchFeatureKind.falling:
      case SketchFeatureKind.linear:
        final a = nx(f.x), b = nx(f.x2);
        final pad = (b - a) * 0.1;
        final s = curve.samples(a + pad, b - pad, 20);
        final range = 'zwischen ${_x(task, f.x)} und ${_x(task, f.x2)}';
        if (s.length < 12) return no('Die Kurve fehlt $range.');
        if (f.kind == SketchFeatureKind.linear) {
          final (u0, v0) = s.first;
          final (u1, v1) = s.last;
          final dev = s.map((p) => (p.$2 - (v0 + (v1 - v0) * (p.$1 - u0) / (u1 - u0))).abs()).reduce(math.max);
          return dev <= math.max(0.06, f.tol)
              ? ok('Verläuft $range gerade.')
              : no('$range soll die Kurve (nahezu) gerade verlaufen${_what(f)}.');
        }
        final up = f.kind == SketchFeatureKind.rising;
        final total = (s.last.$2 - s.first.$2) * (up ? 1 : -1);
        var against = 0;
        for (var i = 0; i + 1 < s.length; i++) {
          if ((s[i + 1].$2 - s[i].$2) * (up ? 1 : -1) < -0.012) against++;
        }
        if (total > 0.03 && against <= (s.length - 1) * 0.25) return ok('${up ? 'Steigt' : 'Fällt'} $range.');
        return no(
          '${range[0].toUpperCase()}${range.substring(1)} soll die Kurve ${up ? 'steigen' : 'fallen'}${_what(f)}.',
        );

      case SketchFeatureKind.jumpDown:
      case SketchFeatureKind.jumpUp:
        final down = f.kind == SketchFeatureKind.jumpDown;
        final at = nx(f.x), tol = f.tol;
        final step = curve.steepestChange(at - 3 * tol, at + 3 * tol, down: down);
        final word = down ? 'nach unten' : 'nach oben';
        if (step == null) return no('Bei ${_x(task, f.x)} fehlt die Kurve – zeichne links und rechts davon weiter.');
        if (step.$2 < 0.04) return no('Bei ${_x(task, f.x)} fehlt der Sprung $word${_what(f)}.');
        if ((step.$1 - at).abs() > tol) {
          return no('Der Sprung $word liegt bei ${_pos(xs, xs.denorm(step.$1))} statt bei ${_x(task, f.x)}.');
        }
        return ok('Sprung $word bei ${_x(task, f.x)}.');

      case SketchFeatureKind.max:
      case SketchFeatureKind.min:
        final isMax = f.kind == SketchFeatureKind.max;
        final p = isMax ? curve.maxPoint : curve.minPoint;
        final word = isMax ? 'Maximum' : 'Minimum';
        if (p == null) return no('Die Kurve soll ein $word haben${_what(f)}.');
        // Ein echtes Extremum: vorher und nachher geht es in die andere Richtung.
        final left = curve.samples(curve.uMin, p.$1, 20), right = curve.samples(p.$1, curve.uMax, 20);
        final rise = left.isEmpty ? 0.0 : (p.$2 - left.map((q) => q.$2).reduce(isMax ? math.min : math.max)).abs();
        final fall = right.isEmpty ? 0.0 : (p.$2 - right.map((q) => q.$2).reduce(isMax ? math.min : math.max)).abs();
        if (rise < 0.03 || fall < 0.03) {
          return no(
            'Die Kurve soll ein $word haben – ${isMax ? 'erst steigen, dann wieder fallen' : 'erst fallen, dann wieder steigen'}${_what(f)}.',
          );
        }
        if (f.x != null && (p.$1 - nx(f.x)).abs() > f.tol) {
          return no('Das $word soll bei ≈ ${_x(task, f.x)} liegen (deins: ${_pos(xs, xs.denorm(p.$1))}).');
        }
        if (!isMax && f.y != null && p.$2 > task.yAxis.norm(f.y!)) {
          return no('Das Minimum soll unter ${_x(task, f.y)} liegen${_what(f)}.');
        }
        if (isMax && f.y != null && p.$2 < task.yAxis.norm(f.y!)) {
          return no('Das Maximum soll über ${_x(task, f.y)} liegen${_what(f)}.');
        }
        return ok('$word an der richtigen Stelle.');

      case SketchFeatureKind.startsAt:
      case SketchFeatureKind.endsAt:
        final start = f.kind == SketchFeatureKind.startsAt;
        final u = start ? curve.uMin : curve.uMax;
        if ((u - nx(f.x)).abs() <= f.tol) return ok('${start ? 'Beginnt' : 'Endet'} bei ${_x(task, f.x)}.');
        return no(
          'Die Kurve soll bei ≈ ${_x(task, f.x)} ${start ? 'beginnen' : 'enden'} (deine: ${_pos(xs, xs.denorm(u))})${_what(f)}.',
        );

      case SketchFeatureKind.approaches:
        final end = curve.uMax;
        final v = curve.vAt(end - 0.01) ?? curve.vAt(end);
        final earlier = curve.vAt(end - 0.15);
        final target = task.yAxis.norm(f.y!);
        if (v == null) return no('Am rechten Ende fehlt die Kurve.');
        if ((v - target).abs() > math.max(f.tol, 0.06)) {
          return no('Für große Werte soll sich die Kurve ${_x(task, f.y)} annähern${_what(f)}.');
        }
        if (earlier != null && (v - earlier).abs() > 0.1) {
          return no('Am Ende soll die Kurve flach auslaufen (sich ${_x(task, f.y)} annähern), nicht steil.');
        }
        return ok('Nähert sich ${_x(task, f.y)} an.');

      case SketchFeatureKind.steeperLeft:
        final p = f.x == null ? curve.minPoint : (nx(f.x), curve.vAt(nx(f.x)) ?? 0.0);
        if (p == null) return no('Noch keine Kurve gezeichnet.');
        // Vergleichsbreite: höchstens 12 % der Achse, aber innerhalb der Kurve.
        final w = [0.12, p.$1 - curve.uMin - 0.005, curve.uMax - p.$1 - 0.005].reduce(math.min);
        if (w < 0.02) return no('Zeichne die Kurve links und rechts des Minimums weiter.');
        final l = curve.vAt(p.$1 - w), r = curve.vAt(p.$1 + w);
        if (l == null || r == null) return no('Zeichne die Kurve links und rechts des Minimums weiter.');
        final left = l - p.$2, right = r - p.$2;
        if (left > 0.05 && left > 1.5 * right) return ok('Links steiler als rechts.');
        return no('Links vom Minimum soll die Kurve deutlich steiler sein als rechts (asymmetrisch)${_what(f)}.');

      case SketchFeatureKind.mark:
        final mark = marks.where((m) => m.label == f.label).firstOrNull;
        if (mark == null) return no('Markiere ${f.label}${_what(f)}.');
        final mu = nx(mark.point.x), mv = task.yAxis.norm(mark.point.y);
        final where =
            '${f.label} soll ${f.anchor.label}${f.anchor == SketchAnchor.x || f.anchor == SketchAnchor.curve || f.anchor == SketchAnchor.point ? ' ${_x(task, f.x)}' : ''} sitzen';
        bool onCurve() {
          final v = curve.vAt(mu);
          return v != null && (v - mv).abs() <= f.tol;
        }

        final good = switch (f.anchor) {
          SketchAnchor.max => curve.maxPoint != null && _dist(curve.maxPoint!, (mu, mv)) <= f.tol,
          SketchAnchor.min => curve.minPoint != null && _dist(curve.minPoint!, (mu, mv)) <= f.tol,
          SketchAnchor.end => !curve.isEmpty && (curve.uMax - mu).abs() <= f.tol,
          SketchAnchor.start => !curve.isEmpty && (curve.uMin - mu).abs() <= f.tol,
          SketchAnchor.beforeMax => onCurve() && curve.maxPoint != null && mu < curve.maxPoint!.$1 - 0.01,
          SketchAnchor.curve => onCurve() && (mu - nx(f.x)).abs() <= f.tol,
          SketchAnchor.x => (mu - nx(f.x)).abs() <= f.tol,
          SketchAnchor.point => _dist((nx(f.x), task.yAxis.norm(f.y ?? 0)), (mu, mv)) <= f.tol,
        };
        return good ? ok('${f.label} sitzt richtig.') : no('$where${_what(f)}.');
    }
  }

  /// Vergleich zweier Kurven.
  static SketchFeatureResult _compare(
    SketchTask task,
    SketchFeature f,
    SketchCurve a,
    SketchCurve? b,
    SketchFeatureResult Function(String) ok,
    SketchFeatureResult Function(String) no,
  ) {
    final na = task.resolve(f.curve), nb = task.resolve(f.other);
    if (b == null || b.isEmpty) return no('Zeichne auch „$nb“.');
    final xs = task.xAxis;
    var lo = math.max(a.uMin, b.uMin), hi = math.min(a.uMax, b.uMax);
    if (f.x != null) lo = math.max(lo, xs.norm(f.x!));
    if (f.x2 != null) hi = math.min(hi, xs.norm(f.x2!));
    final pairs = hi - lo < 0.03
        ? <(double, double)>[]
        : [
            for (var i = 0; i <= 30; i++)
              if ((a.vAt(lo + (hi - lo) * i / 30), b.vAt(lo + (hi - lo) * i / 30)) case (final va?, final vb?))
                (va, vb),
          ];
    final why = _what(f);
    switch (f.kind) {
      case SketchFeatureKind.above:
      case SketchFeatureKind.below:
        if (pairs.length < 5) return no('„$na“ und „$nb“ sollen sich über einen gemeinsamen Bereich erstrecken.');
        final sign = f.kind == SketchFeatureKind.above ? 1 : -1;
        final share = pairs.where((p) => (p.$1 - p.$2) * sign > 0.005).length / pairs.length;
        final mean = pairs.map((p) => (p.$1 - p.$2) * sign).reduce((x, y) => x + y) / pairs.length;
        final word = f.kind == SketchFeatureKind.above ? 'über' : 'unter';
        return share >= 0.8 && mean >= 0.02
            ? ok('„$na“ liegt $word „$nb“.')
            : no('„$na“ soll $word „$nb“ liegen$why.');
      case SketchFeatureKind.parallel:
      case SketchFeatureKind.steeper:
        final sa = a.slope(lo, hi), sb = b.slope(lo, hi);
        if (sa == null || sb == null) return no('„$na“ und „$nb“ sollen sich über einen gemeinsamen Bereich erstrecken.');
        if (f.kind == SketchFeatureKind.steeper) {
          return sa.abs() >= 1.25 * sb.abs() + 0.03
              ? ok('„$na“ ist steiler als „$nb“.')
              : no('„$na“ soll steiler verlaufen als „$nb“$why.');
        }
        final gap = pairs.isEmpty ? 0.0 : pairs.map((p) => (p.$1 - p.$2).abs()).reduce((x, y) => x + y) / pairs.length;
        if ((sa - sb).abs() > 0.3 * math.max(sa.abs(), sb.abs()) + 0.08) {
          return no('„$na“ soll parallel zu „$nb“ verlaufen (gleiche Steigung)$why.');
        }
        if (gap < 0.03) return no('„$na“ soll parallel verschoben sein, nicht auf „$nb“ liegen$why.');
        return ok('„$na“ verläuft parallel zu „$nb“.');
      case SketchFeatureKind.maxEarlier:
      case SketchFeatureKind.maxHigher:
        final pa = a.maxPoint, pb = b.maxPoint;
        if (pa == null || pb == null) return no('Beide Kurven brauchen ein Maximum.');
        if (f.kind == SketchFeatureKind.maxEarlier) {
          return pa.$1 < pb.$1 - 0.01
              ? ok('Das Maximum von „$na“ liegt früher als das von „$nb“.')
              : no('Das Maximum von „$na“ soll früher (weiter links) liegen als das von „$nb“$why.');
        }
        return pa.$2 > pb.$2 + 0.02
            ? ok('Das Maximum von „$na“ liegt höher als das von „$nb“.')
            : no('Das Maximum von „$na“ soll höher liegen als das von „$nb“$why.');
      default:
        return no('');
    }
  }

  static double _dist((double, double) a, (double, double) b) =>
      math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

  /// Wo die Markierungen in der Musterlösung sitzen.
  static List<SketchMark> referenceMarks(SketchTask task) {
    final out = <SketchMark>[];
    for (final f in task.marks) {
      final curve = SketchCurve(task, task.curveNamed(f.curve)?.reference ?? const []);
      final (double, double)? p = switch (f.anchor) {
        SketchAnchor.max => curve.maxPoint,
        SketchAnchor.min => curve.minPoint,
        SketchAnchor.end => curve.isEmpty ? null : (curve.uMax, curve.vAt(curve.uMax - 0.005) ?? 0),
        SketchAnchor.start => curve.isEmpty ? null : (curve.uMin, curve.vAt(curve.uMin + 0.005) ?? 0),
        SketchAnchor.point => (task.xAxis.norm(f.x!), task.yAxis.norm(f.y!)),
        SketchAnchor.beforeMax || SketchAnchor.curve || SketchAnchor.x => () {
          // Ohne Stelle: vor dem Maximum etwa ein Drittel des Wegs.
          final max = curve.maxPoint;
          final u = f.x != null
              ? task.xAxis.norm(f.x!)
              : (max == null || curve.isEmpty ? null : curve.uMin + (max.$1 - curve.uMin) / 3);
          if (u == null) return null;
          return (u, curve.vAt(u) ?? task.yAxis.norm(f.y ?? 0));
        }(),
      };
      if (p != null) out.add(SketchMark(f.label, SketchPoint(task.xAxis.denorm(p.$1), task.yAxis.denorm(p.$2))));
    }
    return out;
  }

  /// Die Musterkurve muss ihre eigenen Merkmale erfüllen – sonst stimmt
  /// ein Merkmal oder die Kurve nicht (Hinweis beim Speichern).
  static List<String> selfCheck(SketchTask task) {
    if (!task.isUsable) return const [];
    final v = check(
      task,
      task.reference,
      referenceMarks(task),
      byCurve: {for (final c in task.curves) c.name: c.reference},
    );
    return [
      for (final r in v.results)
        if (!r.ok)
          'Die Musterkurve erfüllt „${r.feature.kind == SketchFeatureKind.mark ? r.feature.label : r.feature.kind.label}“ nicht: ${r.message}',
    ];
  }

  /// Gestufte Tipps: erst die Merkmale ohne Markierungen, dann die Markierungen.
  static List<String> hints(SketchTask task) {
    String line(SketchFeature f) => switch (f.kind) {
      SketchFeatureKind.mark => '${f.label}: ${f.anchor.label}${f.text.isEmpty ? '' : ' – ${f.text}'}',
      _ => f.text.isNotEmpty ? f.text : _describe(task, f),
    };
    final shape = [
      for (final f in task.features)
        if (f.kind != SketchFeatureKind.mark) line(f),
    ];
    final marks = [for (final f in task.marks) line(f)];
    return [
      if (shape.isNotEmpty) 'Achte auf den Verlauf: ${shape.first}',
      if (shape.length > 1) 'Außerdem: ${shape.skip(1).join(' · ')}',
      if (marks.isNotEmpty) 'Markierungen: ${marks.join(' · ')}',
    ];
  }

  static String _describe(SketchTask t, SketchFeature f) => switch (f.kind) {
    SketchFeatureKind.rising ||
    SketchFeatureKind.falling ||
    SketchFeatureKind.linear => '${_of(t, f)}${f.kind.label} zwischen ${_x(t, f.x)} und ${_x(t, f.x2)}',
    SketchFeatureKind.approaches => '${_of(t, f)}nähert sich ${_x(t, f.y)} an',
    SketchFeatureKind.max || SketchFeatureKind.min => '${_of(t, f)}${f.kind.label}${f.x == null ? '' : ' bei ≈ ${_x(t, f.x)}'}',
    SketchFeatureKind.plateau => '${_of(t, f)}Haltepunkt (waagerecht) bei ${_x(t, f.y)}',
    SketchFeatureKind.kink => '${_of(t, f)}Knick bei ${f.y != null ? _x(t, f.y) : 'x ≈ ${_x(t, f.x)}'}',
    _ when f.kind.isComparison => '„${t.resolve(f.curve)}“ ${f.kind.label} „${t.resolve(f.other)}“',
    _ => '${_of(t, f)}${f.kind.label} ${_x(t, f.x)}',
  };

  /// "T₁: " bei mehreren Kurven.
  static String _of(SketchTask t, SketchFeature f) => t.isMulti ? '${t.resolve(f.curve)}: ' : '';

  /// Musterlösung als Text (Rückseite der Karte).
  static String solutionText(SketchTask task) => [
    'Skizze: ${task.yAxis.label.isEmpty ? 'y' : task.yAxis.label} über ${task.xAxis.label.isEmpty ? 'x' : task.xAxis.label}'
        '${task.isMulti ? ' – Kurven: ${task.curveNames.join(', ')}' : ''}',
    for (final f in task.features)
      '- ${f.kind == SketchFeatureKind.mark ? '${f.label} ${f.anchor.label}' : _describe(task, f)}'
          '${f.text.isNotEmpty && f.kind != SketchFeatureKind.mark ? ': ${f.text}' : (f.text.isNotEmpty ? ' – ${f.text}' : '')}',
  ].join('\n');
}
