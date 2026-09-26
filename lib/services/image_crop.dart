import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Schneidet aus einem Bild (PNG/JPEG) den Ausschnitt [relative] aus –
/// Koordinaten relativ zur Bildgröße (0..1) – und liefert ihn als PNG.
/// Läuft über `dart:ui`, also auf allen Plattformen inkl. Web. `null`, wenn
/// der Ausschnitt leer ist oder das Bild nicht gelesen werden kann.
Future<Uint8List?> cropImageRelative(Uint8List bytes, ui.Rect relative) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    // Auf ganze Pixel gerundet und 1:1 kopiert – jede Filterung würde an
    // den Rändern Nachbarpixel außerhalb des Ausschnitts einmischen.
    int px(double relativeValue, int size) => (relativeValue * size).round().clamp(0, size);
    final left = px(relative.left, image.width);
    final top = px(relative.top, image.height);
    final width = px(relative.right, image.width) - left;
    final height = px(relative.bottom, image.height) - top;
    if (width < 1 || height < 1) return null;

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
    final cropped = await recorder.endRecording().toImage(width, height);
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Pixelgröße eines Bildes, `null` wenn es nicht gelesen werden kann.
Future<ui.Size?> imageSizeOf(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    return ui.Size(image.width.toDouble(), image.height.toDouble());
  } catch (_) {
    return null;
  }
}

/// Verkleinert ein Bild so, dass die längere Seite höchstens [maxSide]
/// Pixel misst (als PNG) – für Bilder, die an Karten hängen: der
/// Seiten-Screenshot entsteht in doppelter Bildschirmauflösung, liegt sonst
/// in voller Größe in der lokalen Datenbank und reist bei jedem Cloud-Sync
/// mit. Kleinere Bilder bleiben unverändert; `null` bei einem Fehler.
Future<Uint8List?> downscaleImage(Uint8List bytes, {int maxSide = 1280}) async {
  try {
    final size = await imageSizeOf(bytes);
    if (size == null) return null;
    final longest = max(size.width, size.height);
    if (longest <= maxSide) return bytes;
    final scale = maxSide / longest;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: max(1, (size.width * scale).round()),
      targetHeight: max(1, (size.height * scale).round()),
    );
    final resized = (await codec.getNextFrame()).image;
    final data = await resized.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
