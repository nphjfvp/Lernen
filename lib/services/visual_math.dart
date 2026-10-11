import 'dart:math' as math;

import '../models/visual_lesson.dart';
import 'math_input.dart';

/// Eine Funktion einer Variablen, fertig zum Auswerten.
class VisualCurve {
  VisualCurve._(this._expression, this.variable);

  final MathExpression _expression;
  final String variable;

  /// Liest [expr] als Funktion von [variable]; null, wenn sich der Term nicht
  /// lesen lässt oder weitere unbekannte Größen enthält.
  static VisualCurve? tryParse(String expr, String variable) {
    final e = MathExpression.tryParse(expr, names: {variable});
    if (e == null) return null;
    if (!e.freeSymbols.every((s) => s == variable)) return null;
    return VisualCurve._(e, variable);
  }

  double at(double x) => _expression.evaluate({variable: x});

  /// Ableitung an der Stelle [x] (zentraler Differenzenquotient).
  double slopeAt(double x, {double span = 1}) {
    final h = math.max(1e-6, span.abs() * 1e-4);
    return (at(x + h) - at(x - h)) / (2 * h);
  }

  String get latex => _expression.toLatex();
}

/// Rechnet für eine [VisualLesson]: Funktionswerte, Ableitungen, der Weg eines
/// über die Geschwindigkeit gesteuerten Autos (aufsummiert) und Wertebereiche
/// fürs Zeichnen. Alles numerisch – die KI liefert nur die Terme.
class VisualMath {
  VisualMath(this.lesson) {
    for (final f in lesson.functions) {
      final curve = VisualCurve.tryParse(f.expr, lesson.variable);
      if (curve != null) _curves[f.key] = curve;
    }
  }

  final VisualLesson lesson;
  final Map<String, VisualCurve> _curves = {};

  /// Stützstellen für Integrale und Bereiche.
  static const samples = 400;

  double get t0 => lesson.domainMin;
  double get t1 => lesson.domainMax;
  double get span => t1 - t0;

  VisualCurve? curve(String key) => _curves[key];

  double value(String key, double t) => _curves[key]?.at(t) ?? double.nan;

  double slope(String key, double t) => _curves[key]?.slopeAt(t, span: span) ?? double.nan;

  /// Integral von [t0] bis [t] (Trapezregel auf feinem Raster).
  double integral(String key, double t) => _integralOf(_curves[key], t);

  double _integralOf(VisualCurve? c, double t) {
    if (c == null) return double.nan;
    final end = t.clamp(t0, t1);
    if (end <= t0) return 0;
    final n = math.max(8, (samples * (end - t0) / span).ceil());
    final h = (end - t0) / n;
    var sum = 0.0;
    var prev = c.at(t0);
    for (var i = 1; i <= n; i++) {
      final next = c.at(t0 + i * h);
      if (prev.isFinite && next.isFinite) sum += (prev + next) / 2 * h;
      prev = next;
    }
    return sum;
  }

  /// Weg des Autos zur Zeit [t].
  double carPosition(VisualShow show, double t) => carPositionOf(_curves[show.car], show.carSource, t);

  /// Geschwindigkeit des Autos zur Zeit [t].
  double carSpeed(VisualShow show, double t) => carSpeedOf(_curves[show.car], show.carSource, t);

  double carPositionOf(VisualCurve? c, CarSource source, double t) =>
      source == CarSource.velocity ? _integralOf(c, t) : (c?.at(t) ?? double.nan);

  double carSpeedOf(VisualCurve? c, CarSource source, double t) =>
      source == CarSource.velocity ? (c?.at(t) ?? double.nan) : (c?.slopeAt(t, span: span) ?? double.nan);

  /// Kleinster und größter endlicher Wert von [f] auf dem Bereich – mit etwas
  /// Rand; null, wenn nirgends endlich.
  ({double min, double max})? rangeOf(Iterable<double Function(double)> fs) {
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final f in fs) {
      for (var i = 0; i <= samples; i++) {
        final y = f(t0 + span * i / samples);
        if (!y.isFinite) continue;
        lo = math.min(lo, y);
        hi = math.max(hi, y);
      }
    }
    if (!lo.isFinite || !hi.isFinite) return null;
    if ((hi - lo).abs() < 1e-9) {
      final pad = hi.abs() < 1e-9 ? 1.0 : hi.abs() * 0.2;
      return (min: lo - pad, max: hi + pad);
    }
    final pad = (hi - lo) * 0.08;
    return (min: lo - pad, max: hi + pad);
  }

  /// Unstimmigkeiten (für Hinweise beim Erstellen und in Tests).
  List<String> problems() {
    final out = <String>[];
    for (final f in lesson.functions) {
      final c = _curves[f.key];
      if (c == null) {
        out.add('„${f.title}“ lässt sich nicht als Funktion von ${lesson.variable} lesen: ${f.expr}');
        continue;
      }
      var finite = 0;
      for (var i = 0; i <= 40; i++) {
        if (c.at(t0 + span * i / 40).isFinite) finite++;
      }
      if (finite < 20) out.add('„${f.title}“ ist auf dem Bereich kaum definiert.');
    }
    return out;
  }

  /// Die Lektion ohne Funktionen, die sich nicht lesen lassen (und ohne
  /// Bezüge darauf).
  static VisualLesson sanitize(VisualLesson lesson) {
    final ok = [
      for (final f in lesson.functions)
        if (VisualCurve.tryParse(f.expr, lesson.variable) != null) f,
    ];
    return ok.length == lesson.functions.length ? lesson : lesson.withFunctions(ok);
  }

  /// Zahl kurz für die Anzeige.
  static String fmt(double v) {
    if (!v.isFinite) return '–';
    final a = v.abs();
    final digits = a >= 100 ? 0 : (a >= 10 ? 1 : 2);
    final s = v.toStringAsFixed(digits);
    final trimmed = s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
    return (trimmed == '-0' ? '0' : trimmed).replaceAll('.', ',');
  }
}
