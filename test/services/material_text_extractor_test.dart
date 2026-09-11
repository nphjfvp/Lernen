import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/material_text_extractor.dart';

void main() {
  group('MaterialTextExtractor.extractText', () {
    test('wirft MaterialExtractionException für nicht unterstützte Dateiendungen', () {
      expect(
        () => MaterialTextExtractor().extractText('notizen.txt', Uint8List(0)),
        throwsA(isA<MaterialExtractionException>()),
      );
    });

    test('wirft MaterialExtractionException, wenn die Datei keine Endung hat', () {
      expect(
        () => MaterialTextExtractor().extractText('README', Uint8List(0)),
        throwsA(isA<MaterialExtractionException>()),
      );
    });

    test('Dateiendung wird unabhängig von Groß-/Kleinschreibung erkannt', () {
      // Ein PDF mit kaputten Bytes soll am PdfService scheitern (nicht am
      // Dispatch selbst) - das belegt, dass ".PDF" korrekt erkannt wurde.
      expect(
        () => MaterialTextExtractor().extractText('Folien.PDF', Uint8List.fromList([1, 2, 3])),
        throwsA(isNot(isA<MaterialExtractionException>())),
      );
    });

    test('supportedExtensions listet pdf, docx und pptx', () {
      expect(MaterialTextExtractor.supportedExtensions, containsAll(['pdf', 'docx', 'pptx']));
    });
  });
}
