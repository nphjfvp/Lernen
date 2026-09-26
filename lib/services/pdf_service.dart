import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Extrahiert Text aus hochgeladenen PDF-Dateien (Folien/Übungsaufgaben).
///
/// Nutzt syncfusion_flutter_pdf (reines Dart, funktioniert auf Windows/iOS/
/// Android ohne native Plattform-Kanäle). Für kommerzielle Nutzung jenseits
/// der kostenlosen Community-License-Grenze siehe README.
class PdfService {
  /// Extrahiert den kompletten Text eines PDFs. Wirft [PdfExtractionException]
  /// bei kaputten/verschlüsselten Dateien, statt die App abstürzen zu lassen.
  String extractText(Uint8List bytes) {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final text = PdfTextExtractor(document).extractText();
      return text.trim();
    } catch (e) {
      throw PdfExtractionException(
          'PDF konnte nicht gelesen werden (beschädigt, gescannt ohne '
          'Text-Ebene oder passwortgeschützt): $e');
    } finally {
      document?.dispose();
    }
  }
}

extension PdfPageTools on PdfService {
  /// Text je Seite (Index 0 = Seite 1) – Grundlage, um Seiten ohne
  /// Text-Ebene (gescannt/Bild) zu erkennen (siehe PdfOcrService).
  List<String> extractPageTexts(Uint8List bytes) {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      return [
        for (var i = 0; i < document.pages.count; i++)
          extractor.extractText(startPageIndex: i, endPageIndex: i).trim(),
      ];
    } catch (e) {
      throw PdfExtractionException('PDF konnte nicht gelesen werden (beschädigt oder passwortgeschützt): $e');
    } finally {
      document?.dispose();
    }
  }

  /// Neue PDF, die nur die Seiten [pageIndices] (0-basiert) enthält – damit
  /// für die Texterkennung nicht das ganze Dokument verschickt werden muss.
  Uint8List extractPages(Uint8List bytes, List<int> pageIndices) {
    final keep = pageIndices.toSet();
    final document = PdfDocument(inputBytes: bytes);
    try {
      for (var i = document.pages.count - 1; i >= 0; i--) {
        if (!keep.contains(i)) document.pages.removeAt(i);
      }
      return Uint8List.fromList(document.saveSync());
    } finally {
      document.dispose();
    }
  }
}

class PdfExtractionException implements Exception {
  final String message;
  PdfExtractionException(this.message);

  @override
  String toString() => message;
}
