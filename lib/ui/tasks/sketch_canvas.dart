import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/sketch_task.dart';
import '../../services/sketch_checker.dart';
import '../../theme/app_colors.dart';

/// Zeichenfläche mit vorgegebenen Achsen. Zeichnen per Finger/Maus
/// ([onStrokeStart]/[onStrokeUpdate]/[onStrokeEnd]) bzw. Antippen
/// ([onTapPoint], zum Markieren). Die Fläche fängt Berührungen sofort ab,
/// damit beim Zeichnen nicht die Seite scrollt.
class SketchCanvas extends StatelessWidget {
  const SketchCanvas({
    super.key,
    required this.task,
    this.strokes = const [],
    this.marks = const [],
    this.showReference = false,
    this.referenceMarks = const [],
    this.onStrokeStart,
    this.onStrokeUpdate,
    this.onStrokeEnd,
    this.onTapPoint,
    this.height = 300,
  });

  final SketchTask task;
  final List<List<SketchPoint>> strokes;
  final List<SketchMark> marks;
  final bool showReference;
  final List<SketchMark> referenceMarks;
  final ValueChanged<SketchPoint>? onStrokeStart;
  final ValueChanged<SketchPoint>? onStrokeUpdate;
  final VoidCallback? onStrokeEnd;
  final ValueChanged<SketchPoint>? onTapPoint;
  final double height;

  static const _pad = EdgeInsets.fromLTRB(46, 14, 14, 36);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final interactive = onStrokeStart != null || onTapPoint != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        final plot = _pad.deflateRect(Offset.zero & size);
        SketchPoint toData(Offset o) {
          final u = ((o.dx - plot.left) / plot.width).clamp(0.0, 1.0);
          final v = ((plot.bottom - o.dy) / plot.height).clamp(0.0, 1.0);
          return SketchPoint(task.xAxis.denorm(u), task.yAxis.denorm(v));
        }

        Widget canvas = Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: CustomPaint(
            size: size,
            painter: _SketchPainter(
              task: task,
              plot: plot,
              strokes: strokes,
              marks: marks,
              reference: showReference ? task.reference : const [],
              referenceMarks: showReference ? referenceMarks : const [],
              ink: c.ink,
              muted: c.inkMuted,
              grid: c.border,
              accent: c.accent,
              good: c.good,
            ),
          ),
        );
        if (!interactive) return canvas;
        canvas = Listener(
          onPointerDown: (e) {
            final p = toData(e.localPosition);
            if (onTapPoint != null) {
              onTapPoint!(p);
            } else {
              onStrokeStart?.call(p);
            }
          },
          onPointerMove: (e) {
            final p = toData(e.localPosition);
            if (onTapPoint != null) {
              onTapPoint!(p);
            } else {
              onStrokeUpdate?.call(p);
            }
          },
          onPointerUp: (_) {
            if (onTapPoint == null) onStrokeEnd?.call();
          },
          child: canvas,
        );
        return RawGestureDetector(
          gestures: {
            EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              EagerGestureRecognizer.new,
              (_) {},
            ),
          },
          child: canvas,
        );
      },
    );
  }
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({
    required this.task,
    required this.plot,
    required this.strokes,
    required this.marks,
    required this.reference,
    required this.referenceMarks,
    required this.ink,
    required this.muted,
    required this.grid,
    required this.accent,
    required this.good,
  });

  final SketchTask task;
  final Rect plot;
  final List<List<SketchPoint>> strokes;
  final List<SketchMark> marks;
  final List<List<SketchPoint>> reference;
  final List<SketchMark> referenceMarks;
  final Color ink, muted, grid, accent, good;

  Offset _px(SketchPoint p) =>
      Offset(plot.left + task.xAxis.norm(p.x) * plot.width, plot.bottom - task.yAxis.norm(p.y) * plot.height);

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    Color? color,
    double size = 11,
    bool bold = false,
    Alignment align = Alignment.center,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color ?? muted, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 160);
    final dx = at.dx - tp.width * (align.x + 1) / 2;
    final dy = at.dy - tp.height * (align.y + 1) / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  static String _tick(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
    return v.toStringAsFixed(v.abs() < 1 ? 2 : 1).replaceAll('.', ',');
  }

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.4;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.8;

    // Raster + Zahlen.
    for (var i = 0; i <= 5; i++) {
      final x = plot.left + plot.width * i / 5, y = plot.bottom - plot.height * i / 5;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      if (task.xAxis.showNumbers) {
        _text(canvas, _tick(task.xAxis.denorm(i / 5)), Offset(x, plot.bottom + 4), align: Alignment.topCenter);
      }
      if (task.yAxis.showNumbers) {
        _text(canvas, _tick(task.yAxis.denorm(i / 5)), Offset(plot.left - 4, y), align: Alignment.centerRight);
      }
    }
    // Nulllinie, wenn 0 innerhalb der y-Achse liegt.
    if (task.yAxis.min < 0 && task.yAxis.max > 0) {
      final y = plot.bottom - task.yAxis.norm(0) * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), axis..strokeWidth = 1);
      axis.strokeWidth = 1.4;
    }
    // Achsen mit Pfeilen.
    canvas.drawLine(plot.bottomLeft, plot.bottomRight + const Offset(8, 0), axis);
    canvas.drawLine(plot.bottomLeft, plot.topLeft - const Offset(0, 8), axis);
    final arrow = Paint()..color = ink;
    canvas.drawPath(
      Path()
        ..moveTo(plot.right + 12, plot.bottom)
        ..lineTo(plot.right + 4, plot.bottom - 4)
        ..lineTo(plot.right + 4, plot.bottom + 4)
        ..close(),
      arrow,
    );
    canvas.drawPath(
      Path()
        ..moveTo(plot.left, plot.top - 12)
        ..lineTo(plot.left - 4, plot.top - 4)
        ..lineTo(plot.left + 4, plot.top - 4)
        ..close(),
      arrow,
    );
    _text(
      canvas,
      task.xAxis.label,
      Offset(plot.right, plot.bottom + 20),
      color: ink,
      bold: true,
      align: Alignment.topRight,
    );
    _text(
      canvas,
      task.yAxis.label,
      Offset(plot.left + 6, plot.top - 2),
      color: ink,
      bold: true,
      align: Alignment.topLeft,
    );

    // Musterkurve (gestrichelt).
    final refPaint = Paint()
      ..color = good
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    for (final s in reference) {
      for (var i = 0; i + 1 < s.length; i++) {
        _dashed(canvas, _px(s[i]), _px(s[i + 1]), refPaint);
      }
    }
    // Eigene Kurve.
    final pen = Paint()
      ..color = accent
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      final path = Path()..moveTo(_px(s.first).dx, _px(s.first).dy);
      for (final p in s.skip(1)) {
        path.lineTo(_px(p).dx, _px(p).dy);
      }
      if (s.length == 1) path.lineTo(_px(s.first).dx + 0.1, _px(s.first).dy);
      canvas.drawPath(path, pen);
    }
    for (final m in referenceMarks) {
      _mark(canvas, m, good, below: true);
    }
    for (final m in marks) {
      _mark(canvas, m, accent);
    }
  }

  void _mark(Canvas canvas, SketchMark m, Color color, {bool below = false}) {
    final o = _px(m.point);
    canvas.drawCircle(o, 5, Paint()..color = color);
    canvas.drawCircle(
      o,
      8,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    _text(
      canvas,
      m.label,
      o + Offset(0, below ? 12 : -12),
      color: color,
      bold: true,
      size: 12,
      align: below ? Alignment.topCenter : Alignment.bottomCenter,
    );
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final d = (b - a).distance;
    if (d < 0.5) return;
    final dir = (b - a) / d;
    for (var t = 0.0; t < d; t += 10) {
      canvas.drawLine(a + dir * t, a + dir * math.min(t + 6, d), paint);
    }
  }

  @override
  bool shouldRepaint(_SketchPainter old) => true;
}
