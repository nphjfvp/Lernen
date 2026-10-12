import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/visual_lesson.dart';
import '../../services/visual_math.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';

/// Eine zusätzliche Kurve (z.B. die Antwort des Nutzers) im Graphen.
class ExtraCurve {
  const ExtraCurve({required this.label, required this.curve, required this.color});
  final String label;
  final VisualCurve curve;
  final Color color;
}

/// Ein zweites Auto (z.B. „so würde deine Antwort fahren“).
class GhostCar {
  const GhostCar({required this.label, required this.curve, this.source = CarSource.position});
  final String label;
  final VisualCurve curve;
  final CarSource source;
}

/// Farben der Kurven (der Reihe nach).
List<Color> visualPalette(AppColors c) => [c.accent, c.good, c.warn, const Color(0xFF8E5BD8), c.danger];

/// Die Simulation eines Schritts: Auto auf der Straße und/oder Funktionsgraph,
/// beide an derselben Zeit; Abspielen, Pause, Zeitregler. Die Umformung einer
/// Gleichung ([VisualShow.transform]) zeigt [EquationTransformView].
class VisualSceneView extends StatefulWidget {
  const VisualSceneView({
    super.key,
    required this.math,
    required this.show,
    this.extraCurves = const [],
    this.ghost,
    this.autoplay = true,
    this.duration = const Duration(seconds: 6),
  });

  final VisualMath math;
  final VisualShow show;
  final List<ExtraCurve> extraCurves;
  final GhostCar? ghost;
  final bool autoplay;
  final Duration duration;

  /// Gibt es etwas zu animieren?
  static bool hasScene(VisualShow show, {bool extra = false, bool ghost = false}) =>
      show.car != null || show.plot.isNotEmpty || show.tangent != null || show.area != null || extra || ghost;

  @override
  State<VisualSceneView> createState() => _VisualSceneViewState();
}

class _VisualSceneViewState extends State<VisualSceneView> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: widget.duration)
    ..addListener(() => setState(() {}));

  VisualMath get _m => widget.math;
  double get _t => _m.t0 + _m.span * _clock.value;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) _clock.forward();
  }

  @override
  void didUpdateWidget(VisualSceneView old) {
    super.didUpdateWidget(old);
    if (old.show != widget.show || old.ghost != widget.ghost || old.extraCurves != widget.extraCurves) {
      _clock.value = 0;
      if (widget.autoplay) _clock.forward();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_clock.isAnimating) {
      _clock.stop();
    } else {
      if (_clock.value >= 1) _clock.value = 0;
      _clock.forward();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final show = widget.show;
    final hasPlot = show.plot.isNotEmpty || show.tangent != null || show.area != null || widget.extraCurves.isNotEmpty;
    final hasCar = show.car != null || widget.ghost != null;
    final v = _m.lesson.variable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasCar) ...[_car(c), const SizedBox(height: 10)],
        if (hasPlot) _plot(c),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              key: const ValueKey('visual-play'),
              tooltip: _clock.isAnimating ? 'Pause' : 'Abspielen',
              onPressed: _togglePlay,
              icon: Icon(_clock.isAnimating ? Icons.pause_circle_outline : Icons.play_circle_outline),
            ),
            IconButton(
              key: const ValueKey('visual-restart'),
              tooltip: 'Von vorn',
              onPressed: () {
                _clock.value = 0;
                _clock.forward();
              },
              icon: const Icon(Icons.replay),
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('visual-time'),
                value: _clock.value,
                onChanged: (x) {
                  _clock.stop();
                  _clock.value = x;
                },
              ),
            ),
            SizedBox(
              width: 86,
              child: Text(
                '$v = ${VisualMath.fmt(_t)}',
                key: const ValueKey('visual-time-label'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Auto
  // -------------------------------------------------------------------------

  Widget _car(AppColors c) {
    final show = widget.show;
    final main = show.car == null ? null : _m.curve(show.car!);
    final ghost = widget.ghost;
    double posMain(double t) => _m.carPositionOf(main, show.carSource, t);
    double posGhost(double t) => ghost == null ? double.nan : _m.carPositionOf(ghost.curve, ghost.source, t);
    final range = _m.rangeOf([if (main != null) posMain, if (ghost != null) posGhost]) ?? (min: 0.0, max: 1.0);
    final fn = show.car == null ? null : _m.lesson.function(show.car!);
    final posUnit = show.carSource == CarSource.position ? (fn?.unit ?? '') : _integratedUnit(fn?.unit ?? '');
    final speedUnit = show.carSource == CarSource.velocity ? (fn?.unit ?? '') : _derivedUnit(fn?.unit ?? '');
    final t = _t;
    final look = vehicleLook(show.vehicle);
    final lanes = [
      if (main != null)
        (
          label: look.label,
          pos: posMain(t),
          speed: _m.carSpeedOf(main, show.carSource, t),
          color: c.accent,
          ghost: false,
        ),
      if (ghost != null)
        (
          label: ghost.label,
          pos: posGhost(t),
          speed: _m.carSpeedOf(ghost.curve, ghost.source, t),
          color: c.danger,
          ghost: true,
        ),
    ];
    return Container(
      key: const ValueKey('visual-car'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56.0 * lanes.length + 18,
            child: CustomPaint(
              painter: _RoadPainter(
                look: look,
                lanes: [for (final l in lanes) (pos: l.pos, speed: l.speed, color: l.color, ghost: l.ghost)],
                min: range.min,
                max: range.max,
                ink: c.inkMuted,
                road: c.surfaceAlt,
                unit: posUnit,
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (final l in lanes)
            Text(
              '${l.label}: Weg ${VisualMath.fmt(l.pos)} $posUnit · Geschwindigkeit ${VisualMath.fmt(l.speed)} $speedUnit',
              key: ValueKey(l.ghost ? 'visual-car-ghost-readout' : 'visual-car-readout'),
              style: TextStyle(fontSize: 12.5, color: l.ghost ? c.danger : c.ink),
            ),
        ],
      ),
    );
  }

  /// Einheit nach dem Ableiten bzw. Aufsummieren über die Variable (z.B. m → m/s).
  String _derivedUnit(String unit) {
    final x = _m.lesson.variable == 't' ? 's' : '';
    if (unit.isEmpty || x.isEmpty) return '';
    return '$unit/$x';
  }

  String _integratedUnit(String unit) {
    if (_m.lesson.variable != 't' || unit.isEmpty) return '';
    if (unit.endsWith('/s')) return unit.substring(0, unit.length - 2);
    return '$unit·s';
  }

  // -------------------------------------------------------------------------
  // Graph
  // -------------------------------------------------------------------------

  Widget _plot(AppColors c) {
    final show = widget.show;
    final palette = visualPalette(c);
    final keys = <String>[
      ...show.plot,
      for (final k in [show.tangent, show.area])
        if (k != null && !show.plot.contains(k)) k,
    ];
    final curves = <({String label, double Function(double) f, Color color, bool dashed})>[
      for (final (i, k) in keys.indexed)
        if (_m.curve(k) != null)
          (
            label: _m.lesson.function(k)?.title ?? k,
            f: _m.curve(k)!.at,
            color: palette[i % palette.length],
            dashed: false,
          ),
      for (final e in widget.extraCurves) (label: e.label, f: e.curve.at, color: e.color, dashed: true),
    ];
    final range = _m.rangeOf([for (final cv in curves) cv.f]) ?? (min: -1.0, max: 1.0);
    final t = _t;
    final tangentKey = show.tangent;
    final slope = tangentKey == null ? null : _m.slope(tangentKey, t);
    final areaValue = show.area == null ? null : _m.integral(show.area!, t);
    return Container(
      key: const ValueKey('visual-plot'),
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: CustomPaint(
              painter: _PlotPainter(
                curves: curves,
                t0: _m.t0,
                t1: _m.t1,
                yMin: range.min,
                yMax: range.max,
                t: t,
                tangent: tangentKey == null ? null : (y: _m.value(tangentKey, t), slope: slope ?? double.nan),
                area: show.area == null ? null : _m.curve(show.area!)?.at,
                areaColor: palette[keys.indexOf(show.area ?? '') % palette.length],
                ink: c.inkMuted,
                grid: c.border,
                variable: _m.lesson.variable,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final cv in curves)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 14, height: 3, color: cv.color),
                    const SizedBox(width: 4),
                    Text('${cv.label} = ${VisualMath.fmt(cv.f(t))}', style: TextStyle(fontSize: 12, color: c.ink)),
                  ],
                ),
            ],
          ),
          if (slope != null)
            Text(
              'Steigung der Tangente: ${VisualMath.fmt(slope)}',
              key: const ValueKey('visual-slope'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink),
            ),
          if (areaValue != null)
            Text(
              'Fläche bis hier: ${VisualMath.fmt(areaValue)}',
              key: const ValueKey('visual-area'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink),
            ),
        ],
      ),
    );
  }
}

/// Wie das Fahrzeug aussieht: Emoji (null = gezeichnetes Auto), Name und
/// Ausrichtung (Emojis schauen je nach Schrift in verschiedene Richtungen).
typedef VehicleLook = ({String? emoji, String label, double rotate, bool flip});

VehicleLook vehicleLook(String vehicle) {
  final v = vehicle.trim().toLowerCase();
  return switch (v) {
    '' || 'car' || 'auto' => (emoji: null, label: 'Auto', rotate: 0, flip: false),
    'rocket' || 'rakete' => (emoji: '🚀', label: 'Rakete', rotate: math.pi / 4, flip: false),
    'bike' || 'bicycle' || 'fahrrad' => (emoji: '🚲', label: 'Fahrrad', rotate: 0, flip: false),
    'train' || 'zug' => (emoji: '🚆', label: 'Zug', rotate: 0, flip: false),
    'runner' || 'person' || 'läufer' || 'laeufer' || 'mensch' => (emoji: '🏃', label: 'Läufer', rotate: 0, flip: true),
    'ball' => (emoji: '⚽', label: 'Ball', rotate: 0, flip: false),
    'plane' || 'airplane' || 'flugzeug' => (emoji: '✈️', label: 'Flugzeug', rotate: 0, flip: false),
    'boat' || 'ship' || 'boot' || 'schiff' => (emoji: '⛵', label: 'Boot', rotate: 0, flip: false),
    'truck' || 'lkw' => (emoji: '🚚', label: 'Lkw', rotate: 0, flip: true),
    'bus' => (emoji: '🚌', label: 'Bus', rotate: 0, flip: true),
    'snail' || 'schnecke' => (emoji: '🐌', label: 'Schnecke', rotate: 0, flip: true),
    _ when v.runes.any((r) => r > 0x2000) => (emoji: vehicle.trim(), label: 'Objekt', rotate: 0, flip: false),
    _ => (emoji: null, label: 'Auto', rotate: 0, flip: false),
  };
}

class _RoadPainter extends CustomPainter {
  _RoadPainter({
    required this.look,
    required this.lanes,
    required this.min,
    required this.max,
    required this.ink,
    required this.road,
    required this.unit,
  });

  final VehicleLook look;
  final List<({double pos, double speed, Color color, bool ghost})> lanes;
  final double min, max;
  final Color ink, road;
  final String unit;

  @override
  void paint(Canvas canvas, Size size) {
    const carW = 46.0, carH = 22.0, laneH = 56.0;
    final left = carW / 2 + 4, right = size.width - carW / 2 - 4;
    double xOf(double p) => left + ((p - min) / (max - min)).clamp(0.0, 1.0) * (right - left);
    for (final (i, lane) in lanes.indexed) {
      final top = i * laneH;
      final roadRect = Rect.fromLTWH(0, top + 18, size.width, 30);
      canvas.drawRRect(RRect.fromRectAndRadius(roadRect, const Radius.circular(6)), Paint()..color = road);
      final dash = Paint()
        ..color = ink.withValues(alpha: 0.5)
        ..strokeWidth = 1.5;
      for (var x = 6.0; x < size.width; x += 22) {
        canvas.drawLine(Offset(x, roadRect.center.dy), Offset(x + 10, roadRect.center.dy), dash);
      }
      if (!lane.pos.isFinite) continue;
      final cx = xOf(lane.pos);
      final emoji = look.emoji;
      if (emoji != null) {
        // Statt des Autos ein anderes Fahrzeug (Emoji), ausgerichtet nach rechts.
        final tp = TextPainter(
          text: TextSpan(text: emoji, style: const TextStyle(fontSize: 30)),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(cx, roadRect.center.dy - 6);
        if (look.rotate != 0) canvas.rotate(look.rotate);
        if (look.flip) canvas.scale(-1, 1);
        if (lane.ghost) {
          canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: 0.55));
        }
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        if (lane.ghost) canvas.restore();
        canvas.restore();
      } else {
        final body = Rect.fromCenter(center: Offset(cx, roadRect.center.dy - 3), width: carW, height: carH);
        final paint = Paint()..color = lane.ghost ? lane.color.withValues(alpha: 0.65) : lane.color;
        canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(7)), paint);
        final roof = Rect.fromLTWH(body.left + 10, body.top - 8, carW - 22, 10);
        canvas.drawRRect(RRect.fromRectAndRadius(roof, const Radius.circular(4)), paint);
        final wheel = Paint()..color = const Color(0xFF222222);
        canvas.drawCircle(Offset(body.left + 10, body.bottom), 5, wheel);
        canvas.drawCircle(Offset(body.right - 10, body.bottom), 5, wheel);
      }
      // Geschwindigkeitspfeil über dem Auto (Länge ~ Geschwindigkeit).
      if (lane.speed.isFinite && lane.speed.abs() > 1e-9) {
        final len = (lane.speed.abs() / ((max - min).abs() + 1e-9) * size.width * 0.6).clamp(6.0, 90.0);
        final dir = lane.speed.sign;
        final y = top + 6;
        final arrow = Paint()
          ..color = lane.color
          ..strokeWidth = 2.5;
        final end = Offset(cx + dir * len, y);
        canvas.drawLine(Offset(cx, y), end, arrow);
        canvas.drawLine(end, end + Offset(-dir * 6, -4), arrow);
        canvas.drawLine(end, end + Offset(-dir * 6, 4), arrow);
      }
    }
    // Skala unter der letzten Spur.
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final y = lanes.length * laneH + 2;
    for (final (frac, value) in [(0.0, min), (0.5, (min + max) / 2), (1.0, max)]) {
      tp.text = TextSpan(
        text: '${VisualMath.fmt(value)}${unit.isEmpty ? '' : ' $unit'}',
        style: TextStyle(fontSize: 10.5, color: ink),
      );
      tp.layout();
      final x = left + frac * (right - left) - tp.width * frac;
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) => true;
}

class _PlotPainter extends CustomPainter {
  _PlotPainter({
    required this.curves,
    required this.t0,
    required this.t1,
    required this.yMin,
    required this.yMax,
    required this.t,
    required this.tangent,
    required this.area,
    required this.areaColor,
    required this.ink,
    required this.grid,
    required this.variable,
  });

  final List<({String label, double Function(double) f, Color color, bool dashed})> curves;
  final double t0, t1, yMin, yMax, t;
  final ({double y, double slope})? tangent;
  final double Function(double)? area;
  final Color areaColor, ink, grid;
  final String variable;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 40.0, padB = 22.0, padT = 6.0, padR = 6.0;
    final plot = Rect.fromLTRB(padL, padT, size.width - padR, size.height - padB);
    Offset px(double x, double y) =>
        Offset(plot.left + (x - t0) / (t1 - t0) * plot.width, plot.bottom - (y - yMin) / (yMax - yMin) * plot.height);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.7;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 4; i++) {
      final x = plot.left + plot.width * i / 4, y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      tp.text = TextSpan(
        text: VisualMath.fmt(t0 + (t1 - t0) * i / 4),
        style: TextStyle(fontSize: 10, color: ink),
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, plot.bottom + 3));
      tp.text = TextSpan(
        text: VisualMath.fmt(yMin + (yMax - yMin) * i / 4),
        style: TextStyle(fontSize: 10, color: ink),
      );
      tp.layout();
      tp.paint(canvas, Offset(plot.left - tp.width - 4, y - tp.height / 2));
    }
    // Nulllinie.
    if (yMin < 0 && yMax > 0) {
      canvas.drawLine(
        px(t0, 0),
        px(t1, 0),
        Paint()
          ..color = ink
          ..strokeWidth = 1,
      );
    }
    canvas.save();
    canvas.clipRect(plot);
    // Fläche unter der Kurve bis zur aktuellen Stelle.
    final a = area;
    if (a != null) {
      final path = Path()..moveTo(px(t0, 0).dx, px(t0, 0).dy);
      const n = 120;
      for (var i = 0; i <= n; i++) {
        final x = t0 + (t - t0) * i / n;
        final y = a(x);
        if (y.isFinite) path.lineTo(px(x, y).dx, px(x, y).dy);
      }
      path.lineTo(px(t, 0).dx, px(t, 0).dy);
      path.close();
      canvas.drawPath(path, Paint()..color = areaColor.withValues(alpha: 0.22));
    }
    for (final cv in curves) {
      final pen = Paint()
        ..color = cv.color
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke;
      const n = 240;
      Path? path;
      for (var i = 0; i <= n; i++) {
        final x = t0 + (t1 - t0) * i / n;
        final y = cv.f(x);
        if (!y.isFinite) {
          path = null;
          continue;
        }
        final o = px(x, y);
        if (path == null) {
          path = Path()..moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
        if (cv.dashed && i.isOdd) {
          canvas.drawPath(path, pen);
          path = null;
        }
        if (i == n && path != null) canvas.drawPath(path, pen);
      }
      final y = cv.f(t);
      if (y.isFinite) canvas.drawCircle(px(t, y), 5, Paint()..color = cv.color);
    }
    // Tangente an der aktuellen Stelle.
    final tg = tangent;
    if (tg != null && tg.y.isFinite && tg.slope.isFinite) {
      final w = (t1 - t0) * 0.18;
      canvas.drawLine(
        px(t - w, tg.y - tg.slope * w),
        px(t + w, tg.y + tg.slope * w),
        Paint()
          ..color = ink
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
    // Zeitmarke.
    canvas.drawLine(
      Offset(px(t, 0).dx, plot.top),
      Offset(px(t, 0).dx, plot.bottom),
      Paint()
        ..color = ink.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
    tp.text = TextSpan(
      text: variable,
      style: TextStyle(fontSize: 11, color: ink, fontWeight: FontWeight.w700),
    );
    tp.layout();
    tp.paint(canvas, Offset(plot.right - tp.width, plot.bottom - tp.height - 2));
  }

  @override
  bool shouldRepaint(_PlotPainter old) => true;
}

/// Umformen einer Gleichung, ganz langsam: ein Zwischenstand nach dem anderen
/// (weich eingeblendet, die vorigen bleiben klein darüber stehen), mit
/// Begründung je Schritt. Weiter von Hand oder automatisch.
class EquationTransformView extends StatefulWidget {
  const EquationTransformView({super.key, required this.states, this.autoplay = false});

  final List<TransformState> states;
  final bool autoplay;

  @override
  State<EquationTransformView> createState() => _EquationTransformViewState();
}

class _EquationTransformViewState extends State<EquationTransformView> {
  int _shown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) _play();
  }

  @override
  void didUpdateWidget(EquationTransformView old) {
    super.didUpdateWidget(old);
    if (old.states != widget.states) {
      _timer?.cancel();
      _timer = null;
      _shown = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 2600), (timer) {
      if (!mounted || _shown >= widget.states.length - 1) {
        timer.cancel();
        if (mounted) setState(() => _timer = null);
        return;
      }
      setState(() => _shown++);
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final states = widget.states;
    if (states.isEmpty) return const SizedBox.shrink();
    final current = states[_shown];
    return Container(
      key: const ValueKey('visual-transform'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = math.max(0, _shown - 3); i < _shown; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Opacity(
                opacity: 0.45,
                child: MathText('\$${states[i].latex}\$', style: TextStyle(fontSize: 13, color: c.inkMuted)),
              ),
            ),
          if (_shown > 0) Icon(Icons.arrow_downward, size: 18, color: c.accent),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey('visual-transform-state-$_shown'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MathText('\$\$${current.latex}\$\$', style: const TextStyle(fontSize: 18)),
                if (current.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: MathText(
                      current.note,
                      key: const ValueKey('visual-transform-note'),
                      style: TextStyle(fontSize: 13, height: 1.4, color: c.accentOnSoft),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('${_shown + 1} / ${states.length}', style: TextStyle(fontSize: 12, color: c.inkMuted)),
              const Spacer(),
              IconButton(
                key: const ValueKey('visual-transform-back'),
                tooltip: 'Zurück',
                onPressed: _shown == 0 ? null : () => setState(() => _shown--),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                key: const ValueKey('visual-transform-play'),
                tooltip: _timer == null ? 'Langsam abspielen' : 'Anhalten',
                onPressed: () {
                  if (_timer != null) {
                    _timer!.cancel();
                    setState(() => _timer = null);
                  } else {
                    if (_shown >= states.length - 1) _shown = 0;
                    _play();
                  }
                },
                icon: Icon(_timer == null ? Icons.slow_motion_video : Icons.pause),
              ),
              FilledButton.tonal(
                key: const ValueKey('visual-transform-next'),
                onPressed: _shown >= states.length - 1 ? null : () => setState(() => _shown++),
                child: const Text('Nächster Schritt'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
