import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Extrahiert Text aus Word- (.docx) und PowerPoint- (.pptx) Dateien.
///
/// Beide Formate sind im Kern ein ZIP-Archiv aus XML-Dateien (Office Open
/// XML) – deshalb reicht ein allgemeines ZIP+XML-Paar (archive/xml) statt
/// einer format-spezifischen (und oft schlechter gewarteten) Bibliothek,
/// und es bleibt reines Dart ohne native Bindings (funktioniert identisch
/// auf Windows/iOS/Android/Web, wie auch schon PdfService).
class OfficeTextExtractor {
  /// Extrahiert den Fließtext aus einem Word-Dokument (word/document.xml).
  String extractDocxText(Uint8List bytes) {
    final archive = _decodeZip(bytes, formatLabel: 'Word-Dokument (.docx)');
    final entry = archive.files.where((f) => f.name == 'word/document.xml').firstOrNull;
    if (entry == null) {
      throw OfficeExtractionException(
          'Word-Dokument konnte nicht gelesen werden: word/document.xml fehlt (kein gültiges .docx?).');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(entry.content as List<int>));
    } catch (e) {
      throw OfficeExtractionException('Word-Dokument enthält kein lesbares XML: $e');
    }

    final buffer = StringBuffer();
    for (final paragraph in document.findAllElements('w:p')) {
      final text = paragraph.findAllElements('w:t').map((e) => e.innerText).join();
      if (text.trim().isNotEmpty) buffer.writeln(text);
    }
    return buffer.toString().trim();
  }

  /// Extrahiert den Text aller Folien einer PowerPoint-Datei
  /// (ppt/slides/slide1.xml, slide2.xml, ... in numerischer Reihenfolge).
  String extractPptxText(Uint8List bytes) {
    final archive = _decodeZip(bytes, formatLabel: 'PowerPoint-Datei (.pptx)');
    final slideFiles = archive.files
        .where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name))
        .toList()
      ..sort((a, b) => _slideNumber(a.name).compareTo(_slideNumber(b.name)));

    if (slideFiles.isEmpty) {
      throw OfficeExtractionException(
          'PowerPoint-Datei konnte nicht gelesen werden: keine Folien gefunden (kein gültiges .pptx?).');
    }

    final buffer = StringBuffer();
    for (final file in slideFiles) {
      final XmlDocument document;
      try {
        document = XmlDocument.parse(utf8.decode(file.content as List<int>));
      } catch (e) {
        continue; // einzelne kaputte Folie überspringen statt ganze Datei zu verwerfen
      }
      final slideText = document
          .findAllElements('a:t')
          .map((e) => e.innerText)
          .where((t) => t.trim().isNotEmpty)
          .join('\n');
      if (slideText.trim().isNotEmpty) {
        buffer
          ..writeln('--- Folie ${_slideNumber(file.name)} ---')
          ..writeln(slideText)
          ..writeln();
      }
    }
    return buffer.toString().trim();
  }

  Archive _decodeZip(Uint8List bytes, {required String formatLabel}) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw OfficeExtractionException(
          '$formatLabel konnte nicht gelesen werden (beschädigt oder falsches Format): $e');
    }
  }

  int _slideNumber(String path) {
    final match = RegExp(r'slide(\d+)\.xml$').firstMatch(path);
    return int.parse(match!.group(1)!);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class OfficeExtractionException implements Exception {
  final String message;
  OfficeExtractionException(this.message);

  @override
  String toString() => message;
}
