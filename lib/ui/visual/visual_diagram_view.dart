import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/visual_diagram.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';

/// Farbe aus dem Namen der KI (Themenfarben, Grundfarben oder #RRGGBB);
/// null = keine.
Color? diagramColor(String name, AppColors c) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty || n == 'none' || n == 'transparent') return null;
  if (n.startsWith('#')) {
    var hex = n.substring(1);
    if (hex.length == 3) hex = hex.split('').map((x) => '$x$x').join();
    final v = int.tryParse(hex, radix: 16);
    if (v == null || hex.length != 6) return null;
    return Color(0xFF000000 | v);
  }
  return switch (n) {
    'accent' || 'blue' || 'blau' || 'primary' => c.accent,
    'red' || 'rot' || 'danger' => c.danger,
    'green' || 'grün' || 'gruen' || 'good' => c.good,
    'orange' || 'warn' || 'yellow' || 'gelb' => c.warn,
    'purple' || 'violet' || 'lila' => const Color(0xFF8E5BD8),
    'brown' || 'braun' => const Color(0xFF8D6E63),
    'gray' || 'grey' || 'grau' || 'muted' => c.inkMuted,
    'black' || 'schwarz' || 'ink' => c.ink,
    'white' || 'weiß' || 'weiss' => c.surface,
    'cyan' || 'türkis' => const Color(0xFF26A6C9),
    'pink' => const Color(0xFFE05A9A),
    _ => null,
  };
}

/// Spielt eine freie Szene ([VisualDiagram]) ab: Abspielen, Pause, von vorn,
/// Zeitregler; darunter die Beschriftung zum aktuellen Zeitpunkt und – falls
/// gesetzt – die mitlaufende Größe (z.B. Temperatur).
class VisualDiagramView extends StatefulWidget {
  const VisualDiagramView({super.key, required this.diagram, this.autoplay = true});

  final VisualDiagram diagram;
  final bool autoplay;

  @override
  State<VisualDiagramView> createState() => _VisualDiagramViewState();
}

class _VisualDiagramViewState extends State<VisualDiagramView> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: _duration)
    ..addListener(() => setState(() {}));

  Duration get _duration => Duration(milliseconds: (widget.diagram.seconds * 1000).round());

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) _clock.forward();
  }

  @override
  void didUpdateWidget(VisualDiagramView old) {
    super.didUpdateWidget(old);
    if (old.diagram != widget.diagram) {
      _clock.duration = _duration;
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
    final d = widget.diagram;
    final p = _clock.value;
    final caption = d.captionAt(p);
    final unit = d.paramUnit.isEmpty ? '' : ' ${d.paramUnit}';
    return Container(
      key: const ValueKey('visual-diagram'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 600.0;
              final height = math.min(width * d.height / d.width, 380.0);
              final formulas = DiagramPainter.formulasOf(d, p, c, Size(width, height));
              return SizedBox(
                width: width,
                height: height,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: DiagramPainter(diagram: d, progress: p, colors: c),
                      ),
                    ),
                    // Texte mit Formeln: echt gesetzt statt als Klartext.
                    for (final (i, f) in formulas.indexed) sceneFormula(f, key: ValueKey('diagram-formula-$i')),
                  ],
                ),
              );
            },
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(caption),
                child: Container(
                  key: const ValueKey('diagram-caption'),
                  child: MathText(caption, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink)),
                ),
              ),
            ),
          ],
          Row(
            children: [
              IconButton(
                key: const ValueKey('diagram-play'),
                tooltip: _clock.isAnimating ? 'Pause' : 'Abspielen',
                onPressed: _togglePlay,
                icon: Icon(_clock.isAnimating ? Icons.pause_circle_outline : Icons.play_circle_outline),
              ),
              IconButton(
                key: const ValueKey('diagram-restart'),
                tooltip: 'Von vorn',
                onPressed: () {
                  _clock.value = 0;
                  _clock.forward();
                },
                icon: const Icon(Icons.replay),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('diagram-time'),
                  value: p,
                  onChanged: (x) {
                    _clock.stop();
                    _clock.value = x;
                  },
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 52, maxWidth: 170),
                child: Text(
                  d.hasParam ? '${d.paramName} = ${_fmt(d.paramAt(p))}$unit' : '${(p * 100).round()} %',
                  key: const ValueKey('diagram-param'),
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) {
    final a = v.abs();
    final s = v.toStringAsFixed(a >= 100 ? 0 : (a >= 10 ? 1 : 2));
    final t = s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
    return (t == '-0' ? '0' : t).replaceAll('.', ',');
  }
}

/// Ein Text mit Formel in einer Szene: wird nicht gezeichnet, sondern als
/// echter Formelsatz darübergelegt (Mitte bei [at], Bildschirmpixel).
typedef SceneFormula = ({Offset at, double fontSize, Color color, String text});

/// Texte mit LaTeX ($…$, \(…\)) setzt der Formelsatz statt des Zeichners.
bool hasSceneFormula(String text) => text.contains(r'$') || text.contains(r'\(');

/// Legt [f] mittig an seine Stelle (in einem Stack über der Zeichnung).
Widget sceneFormula(SceneFormula f, {Key? key}) => Positioned(
  key: key,
  left: f.at.dx,
  top: f.at.dy,
  child: IgnorePointer(
    child: FractionalTranslation(
      translation: const Offset(-0.5, -0.5),
      child: MathText(
        f.text,
        style: TextStyle(fontSize: f.fontSize, color: f.color, fontWeight: FontWeight.w600),
      ),
    ),
  ),
);

/// Zeichnet die Szene zum Zeitpunkt [progress] (0…1).
class DiagramPainter extends CustomPainter {
  DiagramPainter({required this.diagram, required this.progress, required this.colors, this.formulasOut});

  final VisualDiagram diagram;
  final double progress;
  final AppColors colors;

  /// Sammelt die Texte mit Formeln (statt sie zu zeichnen).
  final List<SceneFormula>? formulasOut;

  /// Wo die Texte mit Formeln bei [size] stehen – per Probezeichnen, damit
  /// Verschieben, Raster und Skalierung genau wie beim Zeichnen gelten.
  static List<SceneFormula> formulasOf(VisualDiagram d, double progress, AppColors colors, Size size) {
    final out = <SceneFormula>[];
    final recorder = ui.PictureRecorder();
    DiagramPainter(diagram: d, progress: progress, colors: colors, formulasOut: out).paint(Canvas(recorder), size);
    recorder.endRecording().dispose();
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final d = diagram;
    final scale = math.min(size.width / d.width, size.height / d.height);
    final dxOff = (size.width - d.width * scale) / 2;
    final dyOff = (size.height - d.height * scale) / 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(dxOff, dyOff);
    canvas.scale(scale);
    final unit = math.max(d.width, d.height) / 200;
    for (final e in d.elements) {
      for (var j = 0; j < e.ny; j++) {
        for (var i = 0; i < e.nx; i++) {
          canvas.save();
          canvas.translate(i * e.dx, j * e.dy);
          _element(canvas, e, unit, scale);
          canvas.restore();
        }
      }
    }
    canvas.restore();
  }

  Color? _color(DiagramElement e, String which) {
    final track = e.colorAt(which, progress);
    if (track == null) return null;
    final a = diagramColor(track.$1, colors), b = diagramColor(track.$2, colors);
    if (a == null) return track.$3 >= 1 ? b : null;
    if (b == null) return track.$3 >= 1 ? null : a;
    return Color.lerp(a, b, track.$3);
  }

  void _element(Canvas canvas, DiagramElement e, double unit, double scale) {
    final p = progress;
    double n(String prop, double fallback) => e.number(prop, p) ?? fallback;
    final opacity = n('opacity', 1).clamp(0.0, 1.0);
    if (opacity <= 0.001) return;
    Color fade(Color c) => c.withValues(alpha: c.a * opacity);
    final strokeWidth = n('width', unit * 1.2);
    final fill = _color(e, 'fill');
    final stroke = _color(e, 'stroke');
    final rotate = n('rotate', 0) * math.pi / 180;
    final s = n('scale', 1);

    // Mittelpunkt für Drehen/Skalieren.
    Offset center;
    switch (e.shape) {
      case DiagramShape.circle || DiagramShape.text:
        center = Offset(n('x', 0), n('y', 0));
      case DiagramShape.rect:
        center = Offset(n('x', 0) + n('w', 10) / 2, n('y', 0) + n('h', 10) / 2);
      case DiagramShape.line || DiagramShape.arrow:
        center = Offset((n('x1', 0) + n('x2', 0)) / 2, (n('y1', 0) + n('y2', 0)) / 2);
      case DiagramShape.polygon || DiagramShape.path:
        final pts = e.pointsAt(p);
        var cx = 0.0, cy = 0.0;
        for (final q in pts) {
          cx += q[0];
          cy += q[1];
        }
        center = pts.isEmpty ? Offset.zero : Offset(cx / pts.length, cy / pts.length);
    }
    canvas.save();
    if (rotate != 0 || s != 1) {
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotate);
      canvas.scale(s);
      canvas.translate(-center.dx, -center.dy);
    }
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (e.shape) {
      case DiagramShape.circle:
        final r = n('r', 2);
        final f = fill ?? (stroke == null ? colors.accent : null);
        if (f != null) canvas.drawCircle(center, r, Paint()..color = fade(f));
        if (stroke != null) canvas.drawCircle(center, r, strokePaint..color = fade(stroke));
        final label = e.textAt(p);
        if (label.isNotEmpty) {
          _text(canvas, label, center, n('size', r * 1.1), fade(_onColor(f ?? colors.surface)), scale);
        }
      case DiagramShape.rect:
        final rect = Rect.fromLTWH(n('x', 0), n('y', 0), n('w', 10), n('h', 10));
        final f = fill;
        final st = stroke ?? (f == null ? colors.ink : null);
        if (f != null) canvas.drawRect(rect, Paint()..color = fade(f));
        if (st != null) canvas.drawRect(rect, strokePaint..color = fade(st));
        final label = e.textAt(p);
        if (label.isNotEmpty) {
          _text(
            canvas,
            label,
            rect.center,
            n('size', math.min(rect.height * 0.45, unit * 7)),
            fade(f == null ? colors.ink : _onColor(f)),
            scale,
          );
        }
      case DiagramShape.line || DiagramShape.arrow:
        final a = Offset(n('x1', 0), n('y1', 0));
        final b0 = Offset(n('x2', 0), n('y2', 0));
        final draw = n('draw', 1).clamp(0.0, 1.0);
        final b = Offset.lerp(a, b0, draw)!;
        final color = fade(stroke ?? fill ?? colors.ink);
        strokePaint.color = color;
        if (e.dashed) {
          _dashed(canvas, [a, b], strokePaint, unit * 3);
        } else {
          canvas.drawLine(a, b, strokePaint);
        }
        if (e.shape == DiagramShape.arrow && (b - a).distance > 0.001) {
          final dir = (b - a) / (b - a).distance;
          final head = math.max(strokeWidth * 3.5, unit * 3);
          final normal = Offset(-dir.dy, dir.dx);
          final path = Path()
            ..moveTo(b.dx, b.dy)
            ..lineTo(b.dx - dir.dx * head + normal.dx * head * 0.55, b.dy - dir.dy * head + normal.dy * head * 0.55)
            ..lineTo(b.dx - dir.dx * head - normal.dx * head * 0.55, b.dy - dir.dy * head - normal.dy * head * 0.55)
            ..close();
          canvas.drawPath(path, Paint()..color = color);
        }
        final label = e.textAt(p);
        if (label.isNotEmpty) {
          final mid = Offset.lerp(a, b, 0.5)!;
          final dir = (b - a).distance < 0.001 ? const Offset(1, 0) : (b - a) / (b - a).distance;
          final normal = Offset(dir.dy, -dir.dx);
          _text(canvas, label, mid + normal * unit * 5, n('size', unit * 6), color, scale);
        }
      case DiagramShape.polygon:
        final pts = [for (final q in e.pointsAt(p)) Offset(q[0], q[1])];
        final path = Path()..addPolygon(pts, true);
        final f = fill ?? (stroke == null ? colors.accent.withValues(alpha: 0.35) : null);
        if (f != null) canvas.drawPath(path, Paint()..color = fade(f));
        if (stroke != null) {
          strokePaint.color = fade(stroke);
          if (e.dashed) {
            _dashed(canvas, [...pts, pts.first], strokePaint, unit * 3);
          } else {
            canvas.drawPath(path, strokePaint);
          }
        }
        final label = e.textAt(p);
        if (label.isNotEmpty) _text(canvas, label, center, n('size', unit * 6), fade(colors.ink), scale);
      case DiagramShape.path:
        final all = [for (final q in e.pointsAt(p)) Offset(q[0], q[1])];
        final pts = _partial(all, n('draw', 1).clamp(0.0, 1.0));
        strokePaint.color = fade(stroke ?? fill ?? colors.accent);
        if (e.dashed) {
          _dashed(canvas, pts, strokePaint, unit * 3);
        } else if (pts.length >= 2) {
          canvas.drawPath(Path()..addPolygon(pts, false), strokePaint);
        }
        final label = e.textAt(p);
        if (label.isNotEmpty && pts.isNotEmpty) {
          _text(canvas, label, pts.last + Offset(unit * 4, -unit * 4), n('size', unit * 6), strokePaint.color, scale);
        }
      case DiagramShape.text:
        _text(canvas, e.textAt(p), center, n('size', diagram.height / 16), fade(fill ?? stroke ?? colors.ink), scale);
    }
    canvas.restore();
  }

  /// Kurvenzug nur bis zum Anteil [f] seiner Länge.
  static List<Offset> _partial(List<Offset> pts, double f) {
    if (f >= 1 || pts.length < 2) return pts;
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += (pts[i] - pts[i - 1]).distance;
    }
    var left = total * f;
    final out = [pts.first];
    for (var i = 1; i < pts.length; i++) {
      final seg = (pts[i] - pts[i - 1]).distance;
      if (seg >= left) {
        if (seg > 0) out.add(Offset.lerp(pts[i - 1], pts[i], left / seg)!);
        return out;
      }
      left -= seg;
      out.add(pts[i]);
    }
    return out;
  }

  static void _dashed(Canvas canvas, List<Offset> pts, Paint paint, double dash) {
    var on = true;
    var left = dash;
    for (var i = 1; i < pts.length; i++) {
      var a = pts[i - 1];
      final b = pts[i];
      var seg = (b - a).distance;
      while (seg > 0) {
        final step = math.min(left, seg);
        final next = Offset.lerp(a, b, step / (b - a).distance)!;
        if (on) canvas.drawLine(a, next, paint);
        seg -= step;
        left -= step;
        a = next;
        if (left <= 0) {
          on = !on;
          left = dash;
        }
      }
    }
  }

  Color _onColor(Color background) => background.computeLuminance() > 0.45 ? const Color(0xFF1B1B1F) : Colors.white;

  /// Text mittig an [at]; [size] in Szenen-Einheiten.
  void _text(Canvas canvas, String text, Offset at, double size, Color color, double scale) {
    if (text.isEmpty || size <= 0) return;
    if (hasSceneFormula(text)) {
      // Position in Bildschirmpixeln aus der aktuellen Zeichen-Transformation.
      final m = canvas.getTransform();
      final factor = math.sqrt(m[0] * m[0] + m[1] * m[1]);
      formulasOut?.add((
        at: Offset(m[0] * at.dx + m[4] * at.dy + m[12], m[1] * at.dx + m[5] * at.dy + m[13]),
        fontSize: size * factor,
        color: color,
        text: text,
      ));
      return;
    }
    // In Bildschirmpixeln setzen (scharf), dann zurückskalieren.
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size * scale, fontWeight: FontWeight.w600),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(1 / scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(DiagramPainter old) => old.progress != progress || old.diagram != diagram || old.colors != colors;
}
