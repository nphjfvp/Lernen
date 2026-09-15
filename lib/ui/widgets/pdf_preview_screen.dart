import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'page_question_sheet.dart';

/// Rein lesende PDF-Vorschau für eine noch NICHT gespeicherte Datei – z.B.
/// während Vorbereiten/Nachbereiten, bevor "Speichern"/"Fertig" gedrückt
/// wurde. Zeigt die tatsächlichen Folien (nicht nur den extrahierten Text
/// bzw. eine KI-Zusammenfassung davon) und erlaubt "Frage zur Seite" (siehe
/// PageQuestionSheet). Kein Markieren/Speichern von Annotationen – dafür
/// fehlt ein persistiertes MaterialItem; nach dem Speichern steht dieselbe
/// Folie mit voller Markier-Funktion in MaterialViewerScreen zur Verfügung.
class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({
    super.key,
    required this.fileName,
    required this.bytes,
    required this.documentText,
  });

  final String fileName;
  final Uint8List bytes;
  final String documentText;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  final _pdfController = PdfViewerController();
  final _pdfBoundaryKey = GlobalKey();
  bool _capturing = false;

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _capturePageImage() async {
    try {
      final boundary = _pdfBoundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _askAboutPage() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    final imageBytes = await _capturePageImage();
    final pageNumber = _pdfController.pageNumber;
    final totalPages = _pdfController.pageCount;
    if (!mounted) return;
    setState(() => _capturing = false);
    if (imageBytes == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Seite konnte nicht erfasst werden.')));
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => PageQuestionSheet(
        documentText: widget.documentText,
        pageNumber: pageNumber < 1 ? 1 : pageNumber,
        totalPages: totalPages < 1 ? 1 : totalPages,
        pageImageBytes: imageBytes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Frage zur Seite',
            icon: _capturing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.forum_outlined),
            onPressed: _capturing ? null : _askAboutPage,
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _pdfBoundaryKey,
        child: SfPdfViewer.memory(widget.bytes, controller: _pdfController),
      ),
    );
  }
}
