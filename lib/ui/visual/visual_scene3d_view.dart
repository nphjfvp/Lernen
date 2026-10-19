import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/visual_scene3d.dart';
import '../../theme/app_colors.dart';
import '../tasks/crystal_cube.dart' show CubeProjection;
import '../widgets/math_text.dart';
import 'scene3d_open.dart';
import 'visual_diagram_view.dart' show SceneFormula, diagramColor, hasSceneFormula, sceneFormula;

/// Spielt eine räumliche Szene ([VisualScene3D]) ab – gleiche Projektion und
/// Bedienung wie der Würfel der Kristallgitter-Aufgaben: Ziehen dreht, ◀ ▶ in
/// 15°-Schritten, „Ansicht“ setzt zurück; dazu Abspielen, Zeitregler,
/// Beschriftung und mitlaufende Größe.
class VisualScene3DView extends StatefulWidget {
  const VisualScene3DView({
    super.key,
    required this.scene,
    this.autoplay = true,
    this.height = 340,
    this.title = '3D-Szene',
  });

  final VisualScene3D scene;

  /// Überschrift der echten 3D-Ansicht („In 3D ansehen“).
  final String title;
  final bool autoplay;
  final double height;

  @override
  State<VisualScene3DView> createState() => _VisualScene3DViewState();
}

class _VisualScene3DViewState extends State<VisualScene3DView> with SingleTickerProviderStateMixin {
  static const _theta0 = 24.0, _phi0 = 20.0;
  double _theta = _theta0;
  double _phi = _phi0;

  late final AnimationController _clock = AnimationController(vsync: this, duration: _duration)
    ..addListener(() => setState(() {}));

  Duration get _duration => Duration(milliseconds: (widget.scene.seconds * 1000).round());

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) _clock.forward();
  }

  @override
  void didUpdateWidget(VisualScene3DView old) {
    super.didUpdateWidget(old);
    if (old.scene != widget.scene) {
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

  void _rotate(double dTheta, double dPhi) => setState(() {
    _theta += dTheta;
    _phi = (_phi + dPhi).clamp(-15.0, 75.0);
  });

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
    final s = widget.scene;
    final p = _clock.value;
    final caption = s.captionAt(p);
    final unit = s.paramUnit.isEmpty ? '' : ' ${s.paramUnit}';
    // Beim Abspielen langsam mitdrehen (falls gewünscht).
    final theta = _theta + (s.spin ? 180 * p : 0);
    return Container(
      key: const ValueKey('visual-scene3d'),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => _rotate(d.delta.dx * 0.6, d.delta.dy * 0.4),
                    child: CustomPaint(
                      painter: Scene3DPainter(scene: s, progress: p, theta: theta, phi: _phi, colors: c),
                    ),
                  ),
                ),
                // Texte mit Formeln: echt gesetzt statt als Klartext.
                LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      for (final (i, f) in Scene3DPainter.formulasOf(
                        s,
                        p,
                        theta,
                        _phi,
                        c,
                        Size(constraints.maxWidth, widget.height),
                      ).indexed)
                        sceneFormula(f, key: ValueKey('scene3d-formula-$i')),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 10,
                  child: IgnorePointer(
                    child: Text('Ziehen zum Drehen', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Row(
                    children: [
                      _iconPill(
                        c,
                        'scene3d-open-3d',
                        Icons.view_in_ar_rounded,
                        Scene3DOpener.showsInApp ? 'In 3D ansehen' : 'In 3D ansehen (im Browser)',
                        () => Scene3DOpener.open(context, s, title: widget.title),
                      ),
                      const SizedBox(width: 6),
                      _iconPill(c, 'scene3d-rot-left', Icons.rotate_left, 'Nach links drehen', () => _rotate(-15, 0)),
                      const SizedBox(width: 6),
                      _iconPill(c, 'scene3d-rot-right', Icons.rotate_right, 'Nach rechts drehen', () => _rotate(15, 0)),
                      const SizedBox(width: 6),
                      Material(
                        color: c.surface,
                        shape: StadiumBorder(side: BorderSide(color: c.border)),
                        child: InkWell(
                          key: const ValueKey('scene3d-view'),
                          customBorder: const StadiumBorder(),
                          onTap: () => setState(() {
                            _theta = _theta0;
                            _phi = _phi0;
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Text(
                              'Ansicht',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey(caption),
                  child: Container(
                    key: const ValueKey('scene3d-caption'),
                    child: MathText(caption, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink)),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('scene3d-play'),
                  tooltip: _clock.isAnimating ? 'Pause' : 'Abspielen',
                  onPressed: _togglePlay,
                  icon: Icon(_clock.isAnimating ? Icons.pause_circle_outline : Icons.play_circle_outline),
                ),
                IconButton(
                  key: const ValueKey('scene3d-restart'),
                  tooltip: 'Von vorn',
                  onPressed: () {
                    _clock.value = 0;
                    _clock.forward();
                  },
                  icon: const Icon(Icons.replay),
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey('scene3d-time'),
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
                    s.hasParam ? '${s.paramName} = ${_fmt(s.paramAt(p))}$unit' : '${(p * 100).round()} %',
                    key: const ValueKey('scene3d-param'),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

  static String _fmt(double v) {
    final a = v.abs();
    final s = v.toStringAsFixed(a >= 100 ? 0 : (a >= 10 ? 1 : 2));
    final t = s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
    return (t == '-0' ? '0' : t).replaceAll('.', ',');
  }
}

/// Zeichnet die Szene: alles nach Tiefe sortiert (hinten zuerst).
class Scene3DPainter extends CustomPainter {
  Scene3DPainter({
    required this.scene,
    required this.progress,
    required this.theta,
    required this.phi,
    required this.colors,
    this.formulasOut,
  });

  /// Sammelt die Texte mit Formeln (statt sie zu zeichnen).
  final List<SceneFormula>? formulasOut;

  /// Wo die Texte mit Formeln stehen (Probezeichnen, siehe DiagramPainter).
  static List<SceneFormula> formulasOf(
    VisualScene3D scene,
    double progress,
    double theta,
    double phi,
    AppColors colors,
    Size size,
  ) {
    final out = <SceneFormula>[];
    final recorder = ui.PictureRecorder();
    Scene3DPainter(
      scene: scene,
      progress: progress,
      theta: theta,
      phi: phi,
      colors: colors,
      formulasOut: out,
    ).paint(Canvas(recorder), size);
    recorder.endRecording().dispose();
    return out;
  }

  final VisualScene3D scene;
  final double progress;
  final double theta;
  final double phi;
  final AppColors colors;

  late final double _m = scene.box.reduce(math.max);

  /// Szenen-Koordinate → Einheitswürfel der Projektion (Mitte bei 0,5).
  List<double> _unit(List<double> p) => [for (var i = 0; i < 3; i++) (p[i] - scene.box[i] / 2) / _m + 0.5];

  @override
  void paint(Canvas canvas, Size size) {
    final proj = CubeProjection(theta: theta, phi: phi, size: size);
    final scale = math.min(size.width, size.height) * 0.4;
    final parts = <(double, void Function())>[];
    Offset at(List<double> p) => proj.project(_unit(p));
    double depth(List<double> p) => proj.depth(_unit(p));
    final b = scene.box;
    final muted = colors.inkMuted;

    if (scene.frame) {
      final corners = [
        for (final x in [0.0, b[0]])
          for (final y in [0.0, b[1]])
            for (final z in [0.0, b[2]]) [x, y, z],
      ];
      for (var i = 0; i < corners.length; i++) {
        for (var j = i + 1; j < corners.length; j++) {
          final diff = [for (var k = 0; k < 3; k++) (corners[i][k] - corners[j][k]).abs() > 1e-9 ? 1 : 0];
          if (diff.reduce((a, b) => a + b) != 1) continue;
          final a = corners[i], e = corners[j];
          final mid = [for (var k = 0; k < 3; k++) (a[k] + e[k]) / 2];
          parts.add((
            depth(mid) - 0.01,
            () => canvas.drawLine(
              at(a),
              at(e),
              Paint()
                ..color = muted.withValues(alpha: 0.75)
                ..strokeWidth = 1.3,
            ),
          ));
        }
      }
    }
    if (scene.axes) {
      for (final (i, label) in ['x', 'y', 'z'].indexed) {
        final end = [0.0, 0.0, 0.0]..[i] = b[i] + _m * 0.25;
        parts.add((
          -10,
          () {
            final paint = Paint()
              ..color = muted.withValues(alpha: 0.8)
              ..strokeWidth = 1.2;
            _arrowLine(canvas, at([0, 0, 0]), at(end), paint, 9, dashed: false);
            _text(canvas, label, at(end) + const Offset(0, -12), 14, muted, italic: true);
          },
        ));
      }
    }

    final p = progress;
    for (final o in scene.objects) {
      for (var i = 0; i < o.n[0]; i++) {
        for (var j = 0; j < o.n[1]; j++) {
          for (var k = 0; k < o.n[2]; k++) {
            final shift = [i * o.d[0], j * o.d[1], k * o.d[2]];
            List<double> mv(List<double> v) => [for (var q = 0; q < 3; q++) v[q] + shift[q]];
            try {
              _object(canvas, o, p, mv, at, depth, scale, proj, parts);
            } catch (err) {
              debugPrint('3D-Szene: Objekt übersprungen ($err)');
            }
          }
        }
      }
    }
    parts.sort((a, b) => a.$1.compareTo(b.$1));
    for (final part in parts) {
      final saved = canvas.getSaveCount();
      try {
        part.$2();
      } catch (err) {
        debugPrint('3D-Szene: Teil übersprungen ($err)');
      }
      while (canvas.getSaveCount() > saved) {
        canvas.restore();
      }
    }
  }

  Color? _color(Scene3DObject o, String which) {
    final track = o.colorAt(which, progress);
    if (track == null) return null;
    final a = diagramColor(track.$1, colors), b = diagramColor(track.$2, colors);
    if (a == null) return track.$3 >= 1 ? b : null;
    if (b == null) return track.$3 >= 1 ? null : a;
    return Color.lerp(a, b, track.$3);
  }

  void _object(
    Canvas canvas,
    Scene3DObject o,
    double p,
    List<double> Function(List<double>) mv,
    Offset Function(List<double>) at,
    double Function(List<double>) depth,
    double scale,
    CubeProjection proj,
    List<(double, void Function())> parts,
  ) {
    final opacity = (o.number('opacity', p) ?? 1).clamp(0.0, 1.0);
    if (opacity <= 0.001) return;
    Color fade(Color c) => c.withValues(alpha: c.a * opacity);
    final fill = _color(o, 'fill');
    final stroke = _color(o, 'stroke');
    final label = o.textAt(p);
    switch (o.shape) {
      case Scene3DShape.sphere:
        final pos = mv(o.vector('at', p)!);
        final r = (o.number('r', p) ?? _m * 0.08) / _m * scale * proj.perspective(_unit(pos));
        final base = fill ?? colors.accent;
        parts.add((
          depth(pos),
          () {
            final c = at(pos);
            final rect = Rect.fromCircle(center: c, radius: r);
            canvas.drawCircle(
              c,
              r,
              Paint()
                ..shader = RadialGradient(
                  center: const Alignment(-0.35, -0.4),
                  colors: [fade(Color.lerp(base, Colors.white, 0.55)!), fade(base)],
                ).createShader(rect),
            );
            canvas.drawCircle(
              c,
              r,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1
                ..color = fade(stroke ?? Color.lerp(base, Colors.black, 0.35)!),
            );
            if (label.isNotEmpty) _text(canvas, label, c, math.max(9, r * 0.8), fade(_onColor(base)));
          },
        ));
      case Scene3DShape.line || Scene3DShape.arrow:
        final a = mv(o.vector('from', p)!), e0 = mv(o.vector('to', p)!);
        final f = (o.number('draw', p) ?? 1).clamp(0.0, 1.0);
        final e = [for (var q = 0; q < 3; q++) a[q] + (e0[q] - a[q]) * f];
        final mid = [for (var q = 0; q < 3; q++) (a[q] + e[q]) / 2];
        final color = fade(stroke ?? fill ?? colors.ink);
        parts.add((
          depth(mid) + 0.001,
          () {
            final paint = Paint()
              ..color = color
              ..strokeWidth = o.number('width', p) ?? 2
              ..strokeCap = StrokeCap.round;
            _arrowLine(canvas, at(a), at(e), paint, o.shape == Scene3DShape.arrow ? 10 : 0, dashed: o.dashed);
            if (label.isNotEmpty) _text(canvas, label, at(mid) + const Offset(10, -10), 13, color);
          },
        ));
      case Scene3DShape.box:
        final o0 = mv(o.vector('at', p)!);
        final dims =
            o.vector('dims', p) ?? [o.number('size', p) ?? 1, o.number('size', p) ?? 1, o.number('size', p) ?? 1];
        List<double> corner(int x, int y, int z) => [o0[0] + x * dims[0], o0[1] + y * dims[1], o0[2] + z * dims[2]];
        final faces = [
          [corner(0, 0, 0), corner(1, 0, 0), corner(1, 1, 0), corner(0, 1, 0)],
          [corner(0, 0, 1), corner(1, 0, 1), corner(1, 1, 1), corner(0, 1, 1)],
          [corner(0, 0, 0), corner(1, 0, 0), corner(1, 0, 1), corner(0, 0, 1)],
          [corner(0, 1, 0), corner(1, 1, 0), corner(1, 1, 1), corner(0, 1, 1)],
          [corner(0, 0, 0), corner(0, 1, 0), corner(0, 1, 1), corner(0, 0, 1)],
          [corner(1, 0, 0), corner(1, 1, 0), corner(1, 1, 1), corner(1, 0, 1)],
        ];
        final f = fill ?? colors.warn;
        for (final face in faces) {
          _polygon(canvas, face, f.withValues(alpha: f.a * 0.28), stroke ?? f, o.dashed, fade, at, depth, parts);
        }
        if (label.isNotEmpty) {
          final c = corner(1, 1, 1);
          parts.add((depth(c) + 0.002, () => _text(canvas, label, at(c) + const Offset(0, -12), 13, fade(f))));
        }
      case Scene3DShape.polygon:
        final pts = [for (final q in o.pointsAt(p)) mv(q)];
        final f = fill ?? colors.accent;
        _polygon(canvas, pts, f.withValues(alpha: f.a * 0.35), stroke ?? f, o.dashed, fade, at, depth, parts);
        if (label.isNotEmpty) {
          final c = [for (var q = 0; q < 3; q++) pts.map((v) => v[q]).reduce((a, b) => a + b) / pts.length];
          parts.add((depth(c) + 0.002, () => _text(canvas, label, at(c), 13, fade(colors.ink))));
        }
      case Scene3DShape.text:
        final pos = mv(o.vector('at', p)!);
        parts.add((
          depth(pos) + 0.003,
          () => _text(canvas, label, at(pos), o.number('size', p) ?? 14, fade(fill ?? colors.ink)),
        ));
    }
  }

  void _polygon(
    Canvas canvas,
    List<List<double>> pts,
    Color fill,
    Color stroke,
    bool dashed,
    Color Function(Color) fade,
    Offset Function(List<double>) at,
    double Function(List<double>) depth,
    List<(double, void Function())> parts,
  ) {
    if (pts.length < 3) return;
    final c = [for (var q = 0; q < 3; q++) pts.map((v) => v[q]).reduce((a, b) => a + b) / pts.length];
    parts.add((
      depth(c),
      () {
        final screen = [for (final q in pts) at(q)];
        final path = Path()..addPolygon(screen, true);
        canvas.drawPath(path, Paint()..color = fade(fill));
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = fade(stroke);
        if (dashed) {
          for (var i = 0; i < screen.length; i++) {
            _arrowLine(canvas, screen[i], screen[(i + 1) % screen.length], paint, 0, dashed: true);
          }
        } else {
          canvas.drawPath(path, paint);
        }
      },
    ));
  }

  static void _arrowLine(Canvas canvas, Offset a, Offset b, Paint paint, double head, {required bool dashed}) {
    if (dashed) {
      final len = (b - a).distance;
      const dash = 6.0;
      for (var s = 0.0; s < len; s += dash * 2) {
        canvas.drawLine(Offset.lerp(a, b, s / len)!, Offset.lerp(a, b, math.min(1, (s + dash) / len))!, paint);
      }
    } else {
      canvas.drawLine(a, b, paint);
    }
    if (head > 0 && (b - a).distance > 1) {
      final dir = (b - a) / (b - a).distance;
      final normal = Offset(-dir.dy, dir.dx);
      final path = Path()
        ..moveTo(b.dx, b.dy)
        ..lineTo(b.dx - dir.dx * head + normal.dx * head * 0.5, b.dy - dir.dy * head + normal.dy * head * 0.5)
        ..lineTo(b.dx - dir.dx * head - normal.dx * head * 0.5, b.dy - dir.dy * head - normal.dy * head * 0.5)
        ..close();
      canvas.drawPath(path, Paint()..color = paint.color);
    }
  }

  Color _onColor(Color background) => background.computeLuminance() > 0.45 ? const Color(0xFF1B1B1F) : Colors.white;

  void _text(Canvas canvas, String text, Offset at, double size, Color color, {bool italic = false}) {
    if (text.isEmpty) return;
    if (hasSceneFormula(text)) {
      formulasOut?.add((at: at, fontSize: size, color: color, text: text));
      return;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w600,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(Scene3DPainter old) =>
      old.progress != progress || old.theta != theta || old.phi != phi || old.scene != scene || old.colors != colors;
}
