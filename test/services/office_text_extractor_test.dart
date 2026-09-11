import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/office_text_extractor.dart';

Uint8List _zipFrom(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded!);
}

void main() {
  group('OfficeTextExtractor.extractDocxText', () {
    test('extrahiert Text aus word/document.xml, Absatz für Absatz', () {
      const documentXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Erster Absatz.</w:t></w:r></w:p>
    <w:p><w:r><w:t>Zweiter</w:t></w:r><w:r><w:t> Absatz mit zwei Runs.</w:t></w:r></w:p>
  </w:body>
</w:document>
''';
      final bytes = _zipFrom({'word/document.xml': documentXml});

      final text = OfficeTextExtractor().extractDocxText(bytes);

      expect(text.contains('Erster Absatz.'), isTrue);
      // Mehrere <w:r>-Runs im selben Absatz werden zusammengeführt.
      expect(text.contains('Zweiter Absatz mit zwei Runs.'), isTrue);
    });

    test('wirft OfficeExtractionException, wenn word/document.xml fehlt', () {
      final bytes = _zipFrom({'irrelevant.txt': 'x'});
      expect(
        () => OfficeTextExtractor().extractDocxText(bytes),
        throwsA(isA<OfficeExtractionException>()),
      );
    });

    test('wirft OfficeExtractionException bei kaputten Bytes (kein ZIP)', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(
        () => OfficeTextExtractor().extractDocxText(bytes),
        throwsA(isA<OfficeExtractionException>()),
      );
    });
  });

  group('OfficeTextExtractor.extractPptxText', () {
    String slideXml(String text) => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>$text</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld>
</p:sld>
''';

    test('extrahiert Text aller Folien in numerischer statt alphabetischer Reihenfolge', () {
      final bytes = _zipFrom({
        'ppt/slides/slide1.xml': slideXml('Folie eins'),
        'ppt/slides/slide2.xml': slideXml('Folie zwei'),
        'ppt/slides/slide10.xml': slideXml('Folie zehn'),
      });

      final text = OfficeTextExtractor().extractPptxText(bytes);

      // Alphabetisch käme slide10 vor slide2 - hier muss es numerisch sein.
      expect(text.indexOf('Folie eins'), lessThan(text.indexOf('Folie zwei')));
      expect(text.indexOf('Folie zwei'), lessThan(text.indexOf('Folie zehn')));
    });

    test('wirft OfficeExtractionException, wenn keine Folien gefunden werden', () {
      final bytes = _zipFrom({'irrelevant.txt': 'x'});
      expect(
        () => OfficeTextExtractor().extractPptxText(bytes),
        throwsA(isA<OfficeExtractionException>()),
      );
    });
  });
}
