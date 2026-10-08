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

  static SketchVerdict check(SketchTask task, List<List<SketchPoint>> strokes, List<SketchMark> marks) {
    final curve = SketchCurve(task, strokes);
    return SketchVerdict([for (final f in task.features) _check(task, curve, marks, f)]);
  }

  static SketchFeatureResult _check(SketchTask task, SketchCurve curve, List<SketchMark> marks, SketchFeature f) {
    SketchFeatureResult ok(String m) => SketchFeatureResult(f, true, m);
    SketchFeatureResult no(String m) => SketchFeatureResult(f, false, m);
    final xs = task.xAxis;
    double nx(double? x) => xs.norm(x ?? xs.min);
    if (curve.isEmpty && f.kind != SketchFeatureKind.mark) return no('Noch keine Kurve gezeichnet.');

    switch (f.kind) {
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

  static double _dist((double, double) a, (double, double) b) =>
      math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

  /// Wo die Markierungen in der Musterlösung sitzen.
  static List<SketchMark> referenceMarks(SketchTask task) {
    final curve = SketchCurve(task, task.reference);
    final out = <SketchMark>[];
    for (final f in task.marks) {
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
    final v = check(task, task.reference, referenceMarks(task));
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
    SketchFeatureKind.linear => '${f.kind.label} zwischen ${_x(t, f.x)} und ${_x(t, f.x2)}',
    SketchFeatureKind.approaches => 'nähert sich ${_x(t, f.y)} an',
    SketchFeatureKind.max || SketchFeatureKind.min => '${f.kind.label}${f.x == null ? '' : ' bei ≈ ${_x(t, f.x)}'}',
    _ => '${f.kind.label} ${_x(t, f.x)}',
  };

  /// Musterlösung als Text (Rückseite der Karte).
  static String solutionText(SketchTask task) => [
    'Skizze: ${task.yAxis.label.isEmpty ? 'y' : task.yAxis.label} über ${task.xAxis.label.isEmpty ? 'x' : task.xAxis.label}',
    for (final f in task.features)
      '- ${f.kind == SketchFeatureKind.mark ? '${f.label} ${f.anchor.label}' : _describe(task, f)}'
          '${f.text.isNotEmpty && f.kind != SketchFeatureKind.mark ? ': ${f.text}' : (f.text.isNotEmpty ? ' – ${f.text}' : '')}',
  ].join('\n');
}
