import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';
import 'package:uuid/uuid.dart';

/// Liefert einzelne Seiten eines Dokuments als Bild (PNG).
abstract class PageImageRenderer {
  /// Seite [page] (1-basiert) als PNG, `null` wenn das nicht klappt.
  Future<Uint8List?> renderPng(int page);

  Future<void> close();
}

/// Rendert PDF-Seiten außerhalb des Viewers über dieselbe Engine, die auch
/// der PDF-Viewer nutzt (Android/iOS/Windows nativ, Web über pdf.js). Wo sie
/// fehlt (z.B. Linux, Tests), liefert [open] `null` – Aufrufer arbeiten dann
/// ohne Seitenbilder weiter.
class PdfPageRenderer implements PageImageRenderer {
  PdfPageRenderer._(this._id, this.pageCount, this._widths, this._heights, this.maxSide);

  final String _id;
  final int pageCount;
  final List _widths;
  final List _heights;

  /// Längere Bildseite in Pixeln – scharf genug für Abbildungen und
  /// Formeln, ohne den Speicher zu sprengen.
  final int maxSide;

  /// Die Engine rendert pro Dokument nur eine Seite zugleich zuverlässig.
  Future<void> _queue = Future.value();
  bool _closed = false;

  static Future<PdfPageRenderer?> open(Uint8List bytes, {int maxSide = 1800}) async {
    final platform = PdfViewerPlatform.instance;
    final id = 'lernen-render-${const Uuid().v4()}';
    try {
      final count = int.tryParse(await platform.initializePdfRenderer(bytes, id) ?? '');
      if (count == null || count <= 0) {
        await _closeQuietly(id);
        return null;
      }
      final widths = await platform.getPagesWidth(id);
      final heights = await platform.getPagesHeight(id);
      if (widths == null || heights == null || widths.length < count || heights.length < count) {
        await _closeQuietly(id);
        return null;
      }
      return PdfPageRenderer._(id, count, widths, heights, maxSide);
    } catch (_) {
      await _closeQuietly(id);
      return null;
    }
  }

  static Future<void> _closeQuietly(String id) async {
    try {
      await PdfViewerPlatform.instance.closeDocument(id);
    } catch (_) {}
  }

  @override
  Future<Uint8List?> renderPng(int page) {
    final result = _queue.then((_) => _render(page));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Uint8List?> _render(int page) async {
    if (_closed || page < 1 || page > pageCount) return null;
    try {
      final w = (_widths[page - 1] as num).toDouble();
      final h = (_heights[page - 1] as num).toDouble();
      if (w <= 0 || h <= 0) return null;
      final scale = maxSide / math.max(w, h);
      final width = math.max(1, (w * scale).round());
      final height = math.max(1, (h * scale).round());
      final pixels = await PdfViewerPlatform.instance.getPage(page, width, height, _id);
      if (pixels == null || pixels.length < width * height * 4) return null;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
      final image = await completer.future;
      // Transparente Stellen (manche Engines lassen den Seitenhintergrund
      // leer) auf Weiß legen – sonst werden sie im PNG schwarz angezeigt.
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..drawRect(
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        )
        ..drawImage(image, ui.Offset.zero, ui.Paint());
      final flat = await recorder.endRecording().toImage(width, height);
      final data = await flat.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _queue;
    await _closeQuietly(_id);
  }
}
