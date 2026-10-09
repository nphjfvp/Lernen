import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/phase_task.dart';
import '../../services/phase_calculator.dart';
import '../../theme/app_colors.dart';

/// Ein Punkt im Diagramm, der hervorgehoben wird (gefragter Punkt,
/// angetippte Stelle).
class PhaseMarker {
  const PhaseMarker(this.point, this.color, {this.label = ''});
  final PhasePoint point;
  final Color color;
  final String label;
}

/// Ein Hebel (Konode) bei der Temperatur [t] von [c1] bis [c2].
class PhaseTie {
  const PhaseTie(this.t, this.c1, this.c2, this.color);
  final double t;
  final double? c1;
  final double? c2;
  final Color color;
}

/// Zeichnet das Zweistoffsystem aus den Eckdaten (Linien, eutektische Linie,
/// Gebietsnamen oder Nummern) und meldet angetippte Stellen ([onTap]) in
/// Achsen-Einheiten.
class PhaseDiagramCanvas extends StatelessWidget {
  const PhaseDiagramCanvas({
    super.key,
    required this.calc,
    this.height = 300,
    this.showRegionNames = true,
    this.numbered = false,
    this.markers = const [],
    this.ties = const [],
    this.onTap,
  });

  final PhaseCalculator calc;
  final double height;
  final bool showRegionNames;

  /// Gebiete mit Nummern statt Namen (zum Benennen).
  final bool numbered;
  final List<PhaseMarker> markers;
  final List<PhaseTie> ties;
  final ValueChanged<PhasePoint>? onTap;

  static const pad = EdgeInsets.fromLTRB(46, 14, 14, 36);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = calc.s;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        final plot = pad.deflateRect(Offset.zero & size);
        PhasePoint toData(Offset o) {
          final u = ((o.dx - plot.left) / plot.width).clamp(0.0, 1.0);
          final v = ((plot.bottom - o.dy) / plot.height).clamp(0.0, 1.0);
          return PhasePoint(u * s.cMax, s.tMin + v * (s.tMax - s.tMin));
        }

        final painted = Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: CustomPaint(
            size: size,
            painter: _PhasePainter(
              calc: calc,
              plot: plot,
              showRegionNames: showRegionNames,
              numbered: numbered,
              markers: markers,
              ties: ties,
              ink: c.ink,
              muted: c.inkMuted,
              grid: c.border,
              line: c.accent,
            ),
          ),
        );
        if (onTap == null) return painted;
        return GestureDetector(
          key: const ValueKey('phase-diagram-tap'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => onTap!(toData(d.localPosition)),
          child: painted,
        );
      },
    );
  }
}

class _PhasePainter extends CustomPainter {
  _PhasePainter({
    required this.calc,
    required this.plot,
    required this.showRegionNames,
    required this.numbered,
    required this.markers,
    required this.ties,
    required this.ink,
    required this.muted,
    required this.grid,
    required this.line,
  });

  final PhaseCalculator calc;
  final Rect plot;
  final bool showRegionNames;
  final bool numbered;
  final List<PhaseMarker> markers;
  final List<PhaseTie> ties;
  final Color ink, muted, grid, line;

  PhaseSystem get s => calc.s;

  Offset _px(double c, double t) =>
      Offset(plot.left + (c / s.cMax) * plot.width, plot.bottom - ((t - s.tMin) / (s.tMax - s.tMin)) * plot.height);

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
    )..layout(maxWidth: 140);
    tp.paint(canvas, Offset(at.dx - tp.width * (align.x + 1) / 2, at.dy - tp.height * (align.y + 1) / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.7;
    for (var i = 0; i <= 5; i++) {
      final x = plot.left + plot.width * i / 5, y = plot.bottom - plot.height * i / 5;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(canvas, PhaseCalculator.fmt(s.cMax * i / 5), Offset(x, plot.bottom + 4), align: Alignment.topCenter);
      _text(
        canvas,
        PhaseCalculator.fmt(s.tMin + (s.tMax - s.tMin) * i / 5, digits: 0),
        Offset(plot.left - 4, y),
        align: Alignment.centerRight,
      );
    }
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.4;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axis);
    _text(
      canvas,
      '${s.unit} ${s.b}',
      Offset(plot.right, plot.bottom + 20),
      color: ink,
      bold: true,
      align: Alignment.topRight,
    );
    _text(canvas, 'T in °C', Offset(plot.left + 6, plot.top), color: ink, bold: true, align: Alignment.topLeft);
    _text(canvas, s.a, Offset(plot.left, plot.bottom + 20), color: ink, bold: true, align: Alignment.topLeft);

    canvas.save();
    canvas.clipRect(plot.inflate(1));
    final pen = Paint()
      ..color = line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final l in PhaseLine.values) {
      final pts = s.line(l);
      final path = Path()..moveTo(_px(pts.first.c, pts.first.t).dx, _px(pts.first.c, pts.first.t).dy);
      for (final p in pts.skip(1)) {
        final o = _px(p.c, p.t);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, pen);
    }
    // Eutektische (eutektoide) Linie.
    canvas.drawLine(_px(s.alphaMax, s.eutecticT), _px(math.min(s.betaMax, s.cMax * 1.05), s.eutecticT), pen);

    for (final tie in ties) {
      final p = Paint()
        ..color = tie.color
        ..strokeWidth = 2.4;
      final y = _px(0, tie.t).dy;
      if (tie.c1 != null && tie.c2 != null) {
        canvas.drawLine(Offset(_px(tie.c1!, tie.t).dx, y), Offset(_px(tie.c2!, tie.t).dx, y), p);
      }
      for (final cc in [tie.c1, tie.c2]) {
        if (cc != null) canvas.drawCircle(_px(cc, tie.t), 4.5, p);
      }
    }
    canvas.restore();

    // Gefüge statt Phasen unter der eutektischen Linie: gestrichelte
    // Trennlinie an der eutektischen Zusammensetzung.
    final structure = s.structureNames && showRegionNames && !numbered;
    if (structure) {
      final dash = Paint()
        ..color = muted
        ..strokeWidth = 1.2;
      final top = _px(s.eutecticC, s.eutecticT), bottom = _px(s.eutecticC, s.tMin);
      for (var y = top.dy; y < bottom.dy; y += 9) {
        canvas.drawLine(Offset(top.dx, y), Offset(top.dx, math.min(y + 5, bottom.dy)), dash);
      }
    }
    if (showRegionNames || numbered) {
      for (final (i, l) in calc.regionLabels().indexed) {
        final o = _px(l.at.c, l.at.t);
        if (numbered) {
          canvas.drawCircle(o, 11, Paint()..color = line);
          _text(canvas, '${i + 1}', o, color: Colors.white, bold: true, size: 12);
        } else if (structure && l.region == PhaseRegion.alphaBeta) {
          final t = l.at.t;
          final left = (calc.cAtT(PhaseLine.solvusLeft, t) + s.eutecticC) / 2;
          final right = (s.eutecticC + calc.cAtT(PhaseLine.solvusRight, t)) / 2;
          _text(canvas, '${s.eutecticName} +\n${s.alpha}', _px(left, t), color: ink, size: 11);
          _text(canvas, '${s.eutecticName} +\n${s.beta}', _px(right, t), color: ink, size: 11);
        } else {
          _text(canvas, s.regionName(l.region), o, color: ink, size: 11.5);
        }
      }
    }
    _text(
      canvas,
      '${PhaseCalculator.fmt(s.eutecticT)} °C',
      _px(s.eutecticC, s.eutecticT) + const Offset(0, -4),
      color: muted,
      size: 10.5,
      align: Alignment.bottomCenter,
    );

    for (final m in markers) {
      final o = _px(m.point.c, m.point.t);
      canvas.drawCircle(o, 5.5, Paint()..color = m.color);
      canvas.drawCircle(
        o,
        9,
        Paint()
          ..color = m.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      if (m.label.isNotEmpty) {
        _text(
          canvas,
          m.label,
          o + const Offset(10, -10),
          color: m.color,
          bold: true,
          size: 11.5,
          align: Alignment.bottomLeft,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PhasePainter old) => true;
}
