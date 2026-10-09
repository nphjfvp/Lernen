import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Ein Strich der Freihand-Zeichnung: Punkte relativ zur Fläche (0..1).
typedef DrawingStroke = List<Offset>;

/// Seitenverhältnis der Zeichenfläche (Breite : Höhe).
const drawingAspect = 4 / 3;

/// Freihand-Zeichenfläche: weiß wie Papier (auch im Dunkelmodus, damit die
/// Bild-KI dieselbe Zeichnung sieht), Striche in Achsen-unabhängigen
/// Koordinaten 0..1. Mit [photo] zeigt sie stattdessen das Foto.
class DrawingCanvas extends StatelessWidget {
  const DrawingCanvas({
    super.key,
    required this.strokes,
    this.photo,
    this.onStrokeStart,
    this.onStrokeUpdate,
    this.onStrokeEnd,
  });

  final List<DrawingStroke> strokes;
  final Uint8List? photo;
  final ValueChanged<Offset>? onStrokeStart;
  final ValueChanged<Offset>? onStrokeUpdate;
  final VoidCallback? onStrokeEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AspectRatio(
      aspectRatio: drawingAspect,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          Offset norm(Offset o) => Offset((o.dx / size.width).clamp(0.0, 1.0), (o.dy / size.height).clamp(0.0, 1.0));
          final surface = Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: photo != null
                ? Image.memory(photo!, fit: BoxFit.contain, width: size.width, height: size.height)
                : CustomPaint(size: size, painter: _DrawingPainter(strokes)),
          );
          if (photo != null || onStrokeStart == null) return surface;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => onStrokeStart!(norm(d.localPosition)),
            onPanUpdate: (d) => onStrokeUpdate?.call(norm(d.localPosition)),
            onPanEnd: (_) => onStrokeEnd?.call(),
            child: surface,
          );
        },
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  _DrawingPainter(this.strokes);
  final List<DrawingStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) => paintDrawing(canvas, size, strokes);

  @override
  bool shouldRepaint(_DrawingPainter old) => true;
}

/// Zeichnet die Striche (schwarz, rund) in [size].
void paintDrawing(Canvas canvas, Size size, List<DrawingStroke> strokes) {
  final pen = Paint()
    ..color = const Color(0xFF1B1B1F)
    ..strokeWidth = (size.shortestSide / 160).clamp(2.0, 6.0)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final s in strokes) {
    if (s.isEmpty) continue;
    final first = Offset(s.first.dx * size.width, s.first.dy * size.height);
    if (s.length == 1) {
      canvas.drawCircle(first, pen.strokeWidth / 2, pen..style = PaintingStyle.fill);
      pen.style = PaintingStyle.stroke;
      continue;
    }
    final path = Path()..moveTo(first.dx, first.dy);
    for (final p in s.skip(1)) {
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    canvas.drawPath(path, pen);
  }
}

/// Die Zeichnung als PNG (weißer Hintergrund) für die Bild-KI.
Future<Uint8List?> renderDrawingPng(List<DrawingStroke> strokes, {double width = 960}) async {
  final size = Size(width, width / drawingAspect);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  paintDrawing(canvas, size, strokes);
  final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}
