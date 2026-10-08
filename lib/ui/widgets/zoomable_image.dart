import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Bild bildschirmfüllend anzeigen – mit zwei Fingern bzw. Mausrad zoomen,
/// ziehen zum Verschieben.
Future<void> showImageFullscreen(BuildContext context, Uint8List bytes) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog.fullscreen(
      key: const ValueKey('image-fullscreen'),
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 8,
              child: Center(
                child: Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton.filledTonal(
                key: const ValueKey('image-fullscreen-close'),
                tooltip: 'Schließen',
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Bild in einer Aufgabe: antippen öffnet es groß ([showImageFullscreen]),
/// ein kleines Lupen-Symbol zeigt, dass das geht.
class ZoomableImage extends StatelessWidget {
  const ZoomableImage({super.key, required this.bytes, this.maxHeight = 220, this.borderRadius = 12});

  final Uint8List bytes;
  final double maxHeight;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      child: GestureDetector(
        key: const ValueKey('zoomable-image'),
        onTap: () => showImageFullscreen(context, bytes),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.black.withAlpha(110), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.zoom_in, size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
