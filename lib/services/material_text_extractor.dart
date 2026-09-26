import 'dart:typed_data';

import 'office_text_extractor.dart';
import 'pdf_ocr_service.dart';
import 'pdf_service.dart';

/// Wählt anhand der Dateiendung den passenden Text-Extraktor (PDF, Word,
/// PowerPoint) – ein gemeinsamer Einstiegspunkt für alle Upload-Flows
/// (Vorbereiten, Nachbereiten, Materialien-Upload), statt dass jeder davon
/// die Dateiendung selbst auswerten müsste.
class MaterialTextExtractor {
  static const List<String> supportedExtensions = ['pdf', 'docx', 'pptx'];

  String extractText(String fileName, Uint8List bytes) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return PdfService().extractText(bytes);
      case 'docx':
        return OfficeTextExtractor().extractDocxText(bytes);
      case 'pptx':
        return OfficeTextExtractor().extractPptxText(bytes);
      default:
        throw MaterialExtractionException(
            'Nicht unterstütztes Dateiformat: ${ext.isEmpty ? fileName : '.$ext'}. '
            'Unterstützt: ${supportedExtensions.map((e) => '.$e').join(', ')}.');
    }
  }
}

extension MaterialTextOcr on MaterialTextExtractor {
  /// Wie [MaterialTextExtractor.extractText], erkennt bei PDFs aber
  /// zusätzlich gescannte Seiten per KI (siehe PdfOcrService), falls [ocr]
  /// gesetzt ist. Automatisch nur bei überwiegend leeren Seiten; mit [force]
  /// für jede leere Seite (manuell angestoßen). Ohne [ocr] (kein API-Key)
  /// genau das bisherige Verhalten.
  Future<String> extractTextWithOcr(
    String fileName,
    Uint8List bytes, {
    PdfOcrService? ocr,
    bool force = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final isPdf = fileName.toLowerCase().endsWith('.pdf');
    if (!isPdf || ocr == null) return extractText(fileName, bytes);
    final pages = PdfService().extractPageTexts(bytes);
    if (!PdfOcrService.shouldOcr(pages, force: force)) return extractText(fileName, bytes);
    return ocr.recognize(bytes, pages, onProgress: onProgress);
  }
}

class MaterialExtractionException implements Exception {
  final String message;
  MaterialExtractionException(this.message);

  @override
  String toString() => message;
}
