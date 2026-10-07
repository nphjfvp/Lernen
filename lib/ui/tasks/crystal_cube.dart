import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/crystal_geometry.dart';
import '../../theme/app_colors.dart';

/// Ein Pfeil im Würfel (Würfeleinheiten 0..1).
class CubeArrow {
  const CubeArrow(this.from, this.to, this.color, {this.dashed = false});
  final List<double> from;
  final List<double> to;
  final Color color;
  final bool dashed;
}

/// Ein ebenes Vieleck im Würfel (Ecken unsortiert – sortiert wird beim Zeichnen).
class CubePolygon {
  const CubePolygon(this.points, {required this.stroke, this.fill, this.dashed = false});
  final List<List<double>> points;
  final Color stroke;
  final Color? fill;
  final bool dashed;
}

/// Ein antippbarer Punkt bzw. ein Atom (halbe Einheiten 0..2).
class CubeDot {
  const CubeDot({
    required this.half,
    this.atom = false,
    this.fill,
    this.ring,
    this.ringWidth = 1.2,
    this.dashedRing = false,
    this.selected = false,
    this.label,
  });

  final List<int> half;
  final bool atom;
  final Color? fill;
  final Color? ring;
  final double ringWidth;
  final bool dashedRing;
  final bool selected;
  final String? label;

  String get id => half.join('-');
}

/// Projektion des Würfels: Drehung um z ([theta]) und Neigung ([phi]),
/// leichte Perspektive. x zeigt nach vorne links, y nach rechts, z nach oben.
class CubeProjection {
  CubeProjection({required this.theta, required this.phi, required this.size});

  final double theta;
  final double phi;
  final Size size;

  double get _th => theta * math.pi / 180;
  double get _ph => phi * math.pi / 180;
  List<double> get _d => [math.cos(_th) * math.cos(_ph), math.sin(_th) * math.cos(_ph), math.sin(_ph)];
  List<double> get _r => [-math.sin(_th), math.cos(_th), 0];
  List<double> get _u => [-math.cos(_th) * math.sin(_ph), -math.sin(_th) * math.sin(_ph), math.cos(_ph)];
  double get _scale => math.min(size.width, size.height) * 0.4;

  double depth(List<double> p) {
    final d = _d;
    return (p[0] - .5) * d[0] + (p[1] - .5) * d[1] + (p[2] - .5) * d[2];
  }

  double perspective(List<double> p) => 4.2 / (4.2 - depth(p));

  Offset project(List<double> p) {
    final x = p[0] - .5, y = p[1] - .5, z = p[2] - .5;
    final r = _r, u = _u, k = perspective(p) * _scale;
    return Offset(
      size.width * 0.48 + k * (x * r[0] + y * r[1] + z * r[2]),
      size.height * 0.5 - k * (x * u[0] + y * u[1] + z * u[2]),
    );
  }

  /// Ob eine Würfelfläche mit der Außennormale [n] zur Kamera zeigt.
  bool faces(List<double> n) {
    final d = _d;
    return n[0] * d[0] + n[1] * d[1] + n[2] * d[2] > 0;
  }
}

List<double> halfToUnit(List<int> half) => [for (final h in half) h / 2];

/// Drehbarer Einheitswürfel mit Achsen, Pfeilen, Ebenen und antippbaren
/// Punkten/Atomen. Ziehen dreht, ◀ ▶ drehen in 15°-Schritten.
class CrystalCube extends StatefulWidget {
  const CrystalCube({
    super.key,
    this.arrows = const [],
    this.polygons = const [],
    this.lines = const [],
    this.dots = const [],
    this.onTapDot,
    this.height = 330,
    this.half,
    this.onToggleHalf,
    this.note,
    this.compact = false,
  });

  final List<CubeArrow> arrows;
  final List<CubePolygon> polygons;

  /// Ebenen, die den Würfel nur in einer Kante berühren.
  final List<CubeArrow> lines;
  final List<CubeDot> dots;
  final ValueChanged<CubeDot>? onTapDot;
  final double height;

  /// ½-Punkte-Schalter (null = kein Schalter).
  final bool? half;
  final VoidCallback? onToggleHalf;

  /// Kleiner Hinweis oben links.
  final String? note;

  /// Kleine Vorschau ohne Bedienelemente.
  final bool compact;

  @override
  State<CrystalCube> createState() => _CrystalCubeState();
}

class _CrystalCubeState extends State<CrystalCube> {
  static const _theta0 = 24.0, _phi0 = 20.0;
  double _theta = _theta0;
  double _phi = _phi0;

  void _rotate(double dTheta, double dPhi) => setState(() {
        _theta += dTheta;
        _phi = (_phi + dPhi).clamp(-15.0, 65.0);
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('crystal-cube'),
      height: widget.height,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final proj = CubeProjection(theta: _theta, phi: _phi, size: size);
        final dots = [...widget.dots]
          ..sort((a, b) => proj.depth(halfToUnit(a.half)).compareTo(proj.depth(halfToUnit(b.half))));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: widget.compact ? null : (d) => _rotate(d.delta.dx * 0.6, d.delta.dy * 0.4),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CubePainter(
                    proj: proj,
                    colors: c,
                    arrows: widget.arrows,
                    polygons: widget.polygons,
                    lines: widget.lines,
                    textStyle: TextStyle(color: c.inkMuted, fontSize: widget.compact ? 12 : 15, fontStyle: FontStyle.italic),
                  ),
                ),
              ),
              for (final dot in dots) _dot(c, proj, dot),
              if (widget.note != null && !widget.compact)
                Positioned(
                  left: 12,
                  top: 10,
                  right: 12,
                  child: IgnorePointer(child: Text(widget.note!, style: TextStyle(fontSize: 11.5, color: c.inkMuted))),
                ),
              if (!widget.compact)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Row(
                    children: [
                      if (widget.half != null)
                        _pill(
                          c,
                          key: 'crystal-half',
                          label: '½-Punkte',
                          active: widget.half!,
                          onTap: widget.onToggleHalf,
                        ),
                      const Spacer(),
                      _iconPill(c, 'crystal-rot-left', Icons.rotate_left, 'Würfel nach links drehen', () => _rotate(-15, 0)),
                      const SizedBox(width: 6),
                      _iconPill(c, 'crystal-rot-right', Icons.rotate_right, 'Würfel nach rechts drehen', () => _rotate(15, 0)),
                      const SizedBox(width: 6),
                      _pill(c, key: 'crystal-view-reset', label: 'Ansicht', onTap: () => setState(() {
                            _theta = _theta0;
                            _phi = _phi0;
                          })),
                    ],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _dot(AppColors c, CubeProjection proj, CubeDot dot) {
    final p = halfToUnit(dot.half);
    final o = proj.project(p);
    final k = proj.perspective(p);
    final base = widget.compact ? 0.55 : 1.0;
    final size = (dot.atom ? 22.0 * k : (dot.selected ? 15.0 : 10.0)) * base;
    final fill = dot.fill ?? (dot.atom ? c.surfaceAlt : c.surface);
    final ring = dot.ring ?? (dot.atom ? c.inkMuted : c.inkMuted.withValues(alpha: 0.6));
    final shape = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: dot.atom
            ? RadialGradient(center: const Alignment(-0.35, -0.4), colors: [Color.lerp(fill, Colors.white, 0.55)!, fill])
            : null,
        color: dot.atom ? null : fill,
        border: dot.dashedRing ? null : Border.all(color: ring, width: dot.ringWidth),
        boxShadow: dot.selected ? [BoxShadow(color: c.accent.withValues(alpha: 0.3), spreadRadius: 4)] : null,
      ),
      child: dot.label == null
          ? null
          : Center(
              child: Text(dot.label!, style: TextStyle(fontSize: 9.5 * base, fontWeight: FontWeight.w700, color: c.ink)),
            ),
    );
    final visual = dot.dashedRing
        ? CustomPaint(foregroundPainter: _DashedCirclePainter(ring, dot.ringWidth), child: shape)
        : shape;
    const hit = 36.0;
    final tap = widget.onTapDot;
    return Positioned(
      left: o.dx - hit / 2,
      top: o.dy - hit / 2,
      width: hit,
      height: hit,
      child: Semantics(
        button: tap != null,
        label: '${dot.atom ? 'Atom' : 'Punkt'} ${CrystalGeometry.pointText(dot.half)}',
        selected: dot.selected,
        child: GestureDetector(
          key: ValueKey('crystal-pt-${dot.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: tap == null ? null : () => tap(dot),
          child: Center(child: visual),
        ),
      ),
    );
  }

  Widget _pill(AppColors c, {required String key, required String label, bool active = false, VoidCallback? onTap}) => Material(
        color: active ? c.accentSoft : c.surface,
        shape: StadiumBorder(side: BorderSide(color: active ? c.accent : c.border)),
        child: InkWell(
          key: ValueKey(key),
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(label,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? c.accentOnSoft : c.ink)),
          ),
        ),
      );

  Widget _iconPill(AppColors c, String key, IconData icon, String tooltip, VoidCallback onTap) => Material(
        color: c.surface,
        shape: StadiumBorder(side: BorderSide(color: c.border)),
        child: IconButton(
          key: ValueKey(key),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: c.ink),
        ),
      );
}

class _CubePainter extends CustomPainter {
  _CubePainter({
    required this.proj,
    required this.colors,
    required this.arrows,
    required this.polygons,
    required this.lines,
    required this.textStyle,
  });

  final CubeProjection proj;
  final AppColors colors;
  final List<CubeArrow> arrows;
  final List<CubePolygon> polygons;
  final List<CubeArrow> lines;
  final TextStyle textStyle;

  static const _faces = [
    ([1.0, 0.0, 0.0], [[1, 0, 0], [1, 1, 0], [1, 1, 1], [1, 0, 1]]),
    ([-1.0, 0.0, 0.0], [[0, 0, 0], [0, 1, 0], [0, 1, 1], [0, 0, 1]]),
    ([0.0, 1.0, 0.0], [[0, 1, 0], [1, 1, 0], [1, 1, 1], [0, 1, 1]]),
    ([0.0, -1.0, 0.0], [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]]),
    ([0.0, 0.0, 1.0], [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]]),
    ([0.0, 0.0, -1.0], [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]),
  ];

  Offset _p(List<num> v) => proj.project([for (final x in v) x.toDouble()]);

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    // Sichtbare Flächen leicht getönt.
    final facePaint = Paint()..color = c.accent.withValues(alpha: 0.05);
    for (final (n, pts) in _faces) {
      if (!proj.faces(n)) continue;
      canvas.drawPath(Path()..addPolygon([for (final q in pts) _p(q)], true), facePaint);
    }
    // Achsen vom Ursprung aus.
    final axisPaint = Paint()
      ..color = c.inkMuted.withValues(alpha: 0.75)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    for (final (i, name) in const ['x', 'y', 'z'].indexed) {
      final end = [0.0, 0.0, 0.0]..[i] = 1.42;
      final label = [0.0, 0.0, 0.0]..[i] = 1.56;
      _arrow(canvas, [0, 0, 0], end, axisPaint, head: 8);
      final tp = TextPainter(text: TextSpan(text: name, style: textStyle), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, _p(label) - Offset(tp.width / 2, tp.height / 2));
    }
    // Kanten, die hinterste Ecke gestrichelt.
    final corners = [
      for (final x in [0, 1])
        for (final y in [0, 1])
          for (final z in [0, 1]) [x, y, z],
    ];
    var far = corners.first;
    for (final q in corners) {
      if (proj.depth([for (final x in q) x.toDouble()]) < proj.depth([for (final x in far) x.toDouble()])) far = q;
    }
    for (final a in corners) {
      for (var ax = 0; ax < 3; ax++) {
        if (a[ax] != 0) continue;
        final b = [...a]..[ax] = 1;
        final hidden = _same(a, far) || _same(b, far);
        final paint = Paint()
          ..color = hidden ? c.inkMuted.withValues(alpha: 0.45) : c.ink.withValues(alpha: 0.8)
          ..strokeWidth = hidden ? 1 : 1.5
          ..strokeCap = StrokeCap.round;
        if (hidden) {
          _dashed(canvas, _p(a), _p(b), paint);
        } else {
          canvas.drawLine(_p(a), _p(b), paint);
        }
      }
    }
    // Ebenen.
    for (final poly in polygons) {
      if (poly.points.length < 3) continue;
      final pts = [for (final q in poly.points) proj.project(q)];
      final cx = pts.fold(0.0, (s, o) => s + o.dx) / pts.length;
      final cy = pts.fold(0.0, (s, o) => s + o.dy) / pts.length;
      pts.sort((a, b) => math.atan2(a.dy - cy, a.dx - cx).compareTo(math.atan2(b.dy - cy, b.dx - cx)));
      final path = Path()..addPolygon(pts, true);
      if (poly.fill != null) canvas.drawPath(path, Paint()..color = poly.fill!);
      final stroke = Paint()
        ..color = poly.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round;
      if (poly.dashed) {
        for (var i = 0; i < pts.length; i++) {
          _dashed(canvas, pts[i], pts[(i + 1) % pts.length], stroke, dash: 7, gap: 5);
        }
      } else {
        canvas.drawPath(path, stroke);
      }
    }
    for (final l in lines) {
      canvas.drawLine(
        proj.project(l.from),
        proj.project(l.to),
        Paint()
          ..color = l.color.withValues(alpha: 0.7)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
    // Pfeile.
    for (final a in arrows) {
      final paint = Paint()
        ..color = a.color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      _arrow(canvas, a.from, a.to, paint, head: 13, dashed: a.dashed);
    }
  }

  bool _same(List<int> a, List<int> b) => a[0] == b[0] && a[1] == b[1] && a[2] == b[2];

  void _arrow(Canvas canvas, List<num> from, List<num> to, Paint paint, {double head = 12, bool dashed = false}) {
    final a = _p(from), b = _p(to);
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final u = d / len;
    final n = Offset(-u.dy, u.dx);
    final base = b - u * head;
    if (dashed) {
      _dashed(canvas, a, base + u * 2, paint, dash: 7, gap: 5);
    } else {
      canvas.drawLine(a, base + u * 2, paint);
    }
    canvas.drawPath(
      Path()
        ..moveTo(b.dx, b.dy)
        ..lineTo((base + n * head * 0.5).dx, (base + n * head * 0.5).dy)
        ..lineTo((base - n * head * 0.5).dx, (base - n * head * 0.5).dy)
        ..close(),
      Paint()..color = paint.color,
    );
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, {double dash = 4, double gap = 4}) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    for (var t = 0.0; t < len; t += dash + gap) {
      canvas.drawLine(a + u * t, a + u * math.min(t + dash, len), paint);
    }
  }

  @override
  bool shouldRepaint(_CubePainter old) => true;
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter(this.color, this.width);
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final r = size.width / 2;
    const n = 10;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n;
      canvas.drawArc(Rect.fromCircle(center: size.center(Offset.zero), radius: r), a, math.pi / n, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.color != color || old.width != width;
}
