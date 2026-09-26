import 'dart:typed_data';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../services/image_crop.dart';
import '../../theme/app_colors.dart';

/// Öffnet den Seiten-Screenshot bildschirmfüllend: der Nutzer zieht einen
/// Rahmen um den Bereich, auf den sich die Frage konzentrieren soll (z.B.
/// ein Diagramm oder eine Formel, die sich nicht als Text markieren lässt).
/// Liefert den Bereich relativ zur Bildgröße (0..1), `null` bei Abbruch.
Future<Rect?> showPageRegionPicker(BuildContext context, Uint8List imageBytes, {Rect? initial}) {
  return Navigator.of(context).push<Rect>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PageRegionPicker(imageBytes: imageBytes, initial: initial),
  ));
}

class PageRegionPicker extends StatefulWidget {
  const PageRegionPicker({super.key, required this.imageBytes, this.initial});

  final Uint8List imageBytes;
  final Rect? initial;

  /// Kleinere Rahmen (relativ zur Bildbreite/-höhe) gelten als versehentliches
  /// Antippen statt als Markierung.
  static const minSide = 0.03;

  @override
  State<PageRegionPicker> createState() => _PageRegionPickerState();
}

class _PageRegionPickerState extends State<PageRegionPicker> {
  Size? _imageSize;
  Offset? _start;
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    _rect = widget.initial;
    imageSizeOf(widget.imageBytes).then((size) {
      if (mounted) setState(() => _imageSize = size ?? const Size(1, 1));
    });
  }

  bool get _valid {
    final rect = _rect;
    return rect != null && rect.width >= PageRegionPicker.minSide && rect.height >= PageRegionPicker.minSide;
  }

  static Offset _relative(Offset local, Size box) => Offset(
        (local.dx / box.width).clamp(0.0, 1.0),
        (local.dy / box.height).clamp(0.0, 1.0),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = _imageSize;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: const Text('Bereich markieren'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Zieh einen Rahmen um den Teil der Seite, zu dem die Frage sein soll.',
                style: TextStyle(fontSize: 13, color: c.inkMuted),
              ),
            ),
            Expanded(
              child: size == null
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: AspectRatio(
                          aspectRatio: size.width / size.height,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final box = constraints.biggest;
                              return GestureDetector(
                                key: const ValueKey('region-canvas'),
                                // Rahmen beginnt dort, wo der Finger aufsetzt,
                                // nicht erst nach der Zieh-Schwelle.
                                dragStartBehavior: DragStartBehavior.down,
                                onPanStart: (d) {
                                  final start = _relative(d.localPosition, box);
                                  setState(() {
                                    _start = start;
                                    _rect = Rect.fromPoints(start, start);
                                  });
                                },
                                onPanUpdate: (d) {
                                  final start = _start;
                                  if (start == null) return;
                                  setState(() => _rect = Rect.fromPoints(start, _relative(d.localPosition, box)));
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.memory(widget.imageBytes, fit: BoxFit.fill, gaplessPlayback: true),
                                    CustomPaint(painter: _RegionPainter(rect: _rect, color: c.accent)),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _rect == null ? null : () => setState(() => _rect = null),
                    child: const Text('Zurücksetzen'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _valid ? () => Navigator.of(context).pop(_rect) : null,
                    child: const Text('Übernehmen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionPainter extends CustomPainter {
  _RegionPainter({required this.rect, required this.color});

  final Rect? rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final relative = rect;
    if (relative == null) return;
    final region = Rect.fromLTRB(
      relative.left * size.width,
      relative.top * size.height,
      relative.right * size.width,
      relative.bottom * size.height,
    );
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(region);
    canvas.drawPath(outside, Paint()..color = const Color(0x66000000));
    canvas.drawRect(
      region,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_RegionPainter oldDelegate) => oldDelegate.rect != rect || oldDelegate.color != color;
}
