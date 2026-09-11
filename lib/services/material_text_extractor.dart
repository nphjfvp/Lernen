import 'dart:typed_data';

import 'office_text_extractor.dart';
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

class MaterialExtractionException implements Exception {
  final String message;
  MaterialExtractionException(this.message);

  @override
  String toString() => message;
}
