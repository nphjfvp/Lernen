import 'dart:typed_data';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../services/image_crop.dart';

/// Zeigt ein Bild in seinem echten Seitenverhältnis und legt Widgets darüber,
/// die sich über relative Koordinaten (0..1) positionieren – Grundlage für
/// Bildfragen (Beschriftungen, Markier-Bereiche) und den Bild-Editor. Die
/// Bildgröße wird dafür einmal dekodiert; bis dahin erscheint ein Platzhalter.
class RelativeImage extends StatefulWidget {
  const RelativeImage({
    super.key,
    required this.bytes,
    this.overlayBuilder,
    this.onTapRelative,
    this.onPanStartRelative,
    this.onPanUpdateRelative,
    this.onPanEndRelative,
    this.maxHeight = 420,
  });

  final Uint8List bytes;

  /// Baut die Ebenen über dem Bild; [box] ist die angezeigte Bildgröße in
  /// Pixeln (relative Koordinate × box = Position).
  final List<Widget> Function(BuildContext context, Size box)? overlayBuilder;

  /// Antippen des Bildes, als relative Position (0..1).
  final ValueChanged<Offset>? onTapRelative;

  /// Ziehen auf dem Bild (z.B. Rechteck aufziehen), relative Positionen.
  final ValueChanged<Offset>? onPanStartRelative;
  final ValueChanged<Offset>? onPanUpdateRelative;
  final VoidCallback? onPanEndRelative;

  final double maxHeight;

  @override
  State<RelativeImage> createState() => _RelativeImageState();
}

class _RelativeImageState extends State<RelativeImage> {
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant RelativeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) _resolve();
  }

  void _resolve() {
    final bytes = widget.bytes;
    imageSizeOf(bytes).then((size) {
      if (!mounted || !identical(bytes, widget.bytes)) return;
      setState(() => _imageSize = size ?? const Size(4, 3));
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    if (size == null) {
      return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final box = constraints.biggest;
              Offset rel(Offset local) => Offset(
                    (local.dx / box.width).clamp(0.0, 1.0),
                    (local.dy / box.height).clamp(0.0, 1.0),
                  );
              final onTap = widget.onTapRelative;
              final onPanStart = widget.onPanStartRelative;
              final onPanUpdate = widget.onPanUpdateRelative;
              final onPanEnd = widget.onPanEndRelative;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Ein Rahmen beginnt dort, wo der Finger aufsetzt.
                dragStartBehavior: DragStartBehavior.down,
                onTapUp: onTap == null ? null : (d) => onTap(rel(d.localPosition)),
                onPanStart: onPanStart == null ? null : (d) => onPanStart(rel(d.localPosition)),
                onPanUpdate: onPanUpdate == null ? null : (d) => onPanUpdate(rel(d.localPosition)),
                onPanEnd: onPanEnd == null ? null : (_) => onPanEnd(),
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(widget.bytes, fit: BoxFit.fill, gaplessPlayback: true),
                    ),
                    ...?widget.overlayBuilder?.call(context, box),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Positioniert [child] mit seinem Mittelpunkt auf der relativen Stelle
/// [x]/[y] eines [RelativeImage] der Größe [box].
Widget positionedAt({required Size box, required double x, required double y, required Widget child}) {
  return Positioned(
    left: x * box.width,
    top: y * box.height,
    child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: child),
  );
}
