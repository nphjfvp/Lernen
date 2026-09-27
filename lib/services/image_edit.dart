import 'dart:typed_data';
import 'dart:ui' as ui;

/// Eine Bearbeitung eines Bildes im Bild-Editor, in Koordinaten relativ zum
/// Bild (0..1) – unabhängig davon, wie groß es gerade angezeigt wird.
sealed class ImageEdit {
  const ImageEdit();
}

/// Abdecken: ein gefülltes Rechteck, z.B. über einer Beschriftung, die sonst
/// die Antwort verrät (für Zuordnen/Bild beschriften).
class CoverEdit extends ImageEdit {
  const CoverEdit(this.rect, {this.dark = false});

  final ui.Rect rect;

  /// Schwarz statt Weiß.
  final bool dark;

  ui.Color get color => dark ? const ui.Color(0xFF111111) : const ui.Color(0xFFFFFFFF);
}

/// Beschriften: Text mit hellem Hintergrund, mittig auf [position].
class TextEdit extends ImageEdit {
  const TextEdit(this.position, this.text, {this.size = 0.05});

  final ui.Offset position;
  final String text;

  /// Schriftgröße relativ zur Bildhöhe.
  final double size;

  static const textColor = ui.Color(0xFF111111);
  static const backgroundColor = ui.Color(0xE6FFFFFF);
}

/// Rechnet [edits] fest in das Bild ein und liefert es als PNG in
/// Originalauflösung. Ohne Bearbeitungen kommt [bytes] unverändert zurück;
/// `null`, wenn das Bild nicht gelesen werden kann.
Future<Uint8List?> applyImageEdits(Uint8List bytes, List<ImageEdit> edits) async {
  if (edits.isEmpty) return bytes;
  try {
    final image = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.none);
    for (final edit in edits) {
      switch (edit) {
        case CoverEdit():
          final r = edit.rect;
          canvas.drawRect(ui.Rect.fromLTRB(r.left * w, r.top * h, r.right * w, r.bottom * h), ui.Paint()..color = edit.color);
        case TextEdit():
          final paragraph = layoutLabel(edit.text, fontSize: edit.size * h, maxWidth: w);
          final box = labelBox(paragraph, center: ui.Offset(edit.position.dx * w, edit.position.dy * h), fontSize: edit.size * h);
          canvas.drawRRect(ui.RRect.fromRectAndRadius(box, ui.Radius.circular(edit.size * h * 0.25)),
              ui.Paint()..color = TextEdit.backgroundColor);
          canvas.drawParagraph(paragraph, box.topLeft + ui.Offset(edit.size * h * 0.3, edit.size * h * 0.15));
      }
    }
    final result = await recorder.endRecording().toImage(image.width, image.height);
    final data = await result.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Gesetzter Beschriftungstext (für das Einrechnen und die Vorschau gleich).
ui.Paragraph layoutLabel(String text, {required double fontSize, required double maxWidth}) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: fontSize, fontWeight: ui.FontWeight.w600))
    ..pushStyle(ui.TextStyle(color: TextEdit.textColor, fontSize: fontSize, fontWeight: ui.FontWeight.w600))
    ..addText(text);
  return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
}

/// Hintergrund-Rechteck einer Beschriftung, mittig auf [center].
ui.Rect labelBox(ui.Paragraph paragraph, {required ui.Offset center, required double fontSize}) {
  final width = paragraph.longestLine + fontSize * 0.6;
  final height = paragraph.height + fontSize * 0.3;
  return ui.Rect.fromCenter(center: center, width: width, height: height);
}

/// Zeichnet ein feines Koordinatenraster in Zehnteln (mit 0.1 … 0.9 an den
/// Rändern) über das Bild – nur für die KI, damit sie Positionen für
/// Bildfragen genauer ablesen kann (ohne Raster schätzen Sprachmodelle
/// Koordinaten oft grob daneben). `null`, wenn das Bild nicht lesbar ist.
Future<Uint8List?> drawCoordinateGrid(Uint8List bytes) async {
  try {
    final image = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    final line = ui.Paint()
      ..color = const ui.Color(0x99E6007E)
      ..strokeWidth = (w < h ? w : h) / 500 + 0.5;
    final fontSize = ((w < h ? w : h) * 0.028).clamp(9.0, 28.0);
    for (var i = 1; i < 10; i++) {
      final x = w * i / 10;
      final y = h * i / 10;
      canvas.drawLine(ui.Offset(x, 0), ui.Offset(x, h), line);
      canvas.drawLine(ui.Offset(0, y), ui.Offset(w, y), line);
      final label = '0.$i';
      for (final (px, py) in [(x, fontSize * 0.9), (fontSize * 1.2, y)]) {
        final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: fontSize))
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFE6007E), fontSize: fontSize, fontWeight: ui.FontWeight.w700))
          ..addText(label);
        final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 200));
        final box = ui.Rect.fromCenter(
          center: ui.Offset(px, py),
          width: paragraph.longestLine + fontSize * 0.4,
          height: paragraph.height + fontSize * 0.1,
        );
        canvas.drawRect(box, ui.Paint()..color = const ui.Color(0xD9FFFFFF));
        canvas.drawParagraph(paragraph, box.topLeft + ui.Offset(fontSize * 0.2, fontSize * 0.05));
      }
    }
    final result = await recorder.endRecording().toImage(image.width, image.height);
    final data = await result.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Wie [drawCoordinateGrid], aber nur als Skala an den vier Rändern (Striche
/// in Zwanzigsteln, Zahlen in Zehnteln) – für ganze Seiten, deren Inhalt die
/// KI ungestört lesen soll, während sie Positionen (z.B. den Bereich einer
/// Abbildung) trotzdem ablesen kann. `null`, wenn das Bild nicht lesbar ist.
Future<Uint8List?> drawEdgeRuler(Uint8List bytes) async {
  try {
    final image = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final shorter = w < h ? w : h;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    const color = ui.Color(0xFFE6007E);
    final line = ui.Paint()
      ..color = color
      ..strokeWidth = shorter / 600 + 0.5;
    final fontSize = (shorter * 0.018).clamp(8.0, 22.0);
    final longTick = shorter * 0.022;
    for (var i = 1; i < 20; i++) {
      final major = i.isEven;
      final len = major ? longTick : longTick * 0.5;
      final x = w * i / 20;
      final y = h * i / 20;
      canvas
        ..drawLine(ui.Offset(x, 0), ui.Offset(x, len), line)
        ..drawLine(ui.Offset(x, h), ui.Offset(x, h - len), line)
        ..drawLine(ui.Offset(0, y), ui.Offset(len, y), line)
        ..drawLine(ui.Offset(w, y), ui.Offset(w - len, y), line);
      if (!major) continue;
      final label = '0.${i ~/ 2}';
      for (final center in [
        ui.Offset(x, longTick + fontSize * 0.7),
        ui.Offset(x, h - longTick - fontSize * 0.7),
        ui.Offset(longTick + fontSize, y),
        ui.Offset(w - longTick - fontSize, y),
      ]) {
        final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: fontSize))
          ..pushStyle(ui.TextStyle(color: color, fontSize: fontSize, fontWeight: ui.FontWeight.w700))
          ..addText(label);
        final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 200));
        final box = ui.Rect.fromCenter(
          center: center,
          width: paragraph.longestLine + fontSize * 0.4,
          height: paragraph.height + fontSize * 0.1,
        );
        canvas.drawRect(box, ui.Paint()..color = const ui.Color(0xD9FFFFFF));
        canvas.drawParagraph(paragraph, box.topLeft + ui.Offset(fontSize * 0.2, fontSize * 0.05));
      }
    }
    final result = await recorder.endRecording().toImage(image.width, image.height);
    final data = await result.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
