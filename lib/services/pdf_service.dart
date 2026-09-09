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

class PdfExtractionException implements Exception {
  final String message;
  PdfExtractionException(this.message);

  @override
  String toString() => message;
}
