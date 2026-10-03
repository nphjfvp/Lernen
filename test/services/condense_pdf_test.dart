import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/condense.dart';
import 'package:lernen/services/condense_pdf.dart';
import 'package:lernen/services/condense_service.dart';
import 'package:lernen/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// PDF aus Seiten mit je einer Liste von Zeilen (jede Zeile eigene Textzeile).
Uint8List _pdf(List<List<String>> pages) {
  final document = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  for (final lines in pages) {
    final page = document.pages.add();
    for (var i = 0; i < lines.length; i++) {
      page.graphics.drawString(lines[i], font, bounds: Rect.fromLTWH(30, 40.0 + i * 30, 540, 20));
    }
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

int _annotations(Uint8List bytes, int pageIndex) {
  final document = PdfDocument(inputBytes: bytes);
  try {
    return document.pages[pageIndex].annotations.count;
  } finally {
    document.dispose();
  }
}

void main() {
  final lecture = [
    ['Organisatorisches', 'Klausurtermin am Freitag'],
    [
      'Partielle Integration: Herleitung aus der Produktregel durch Integrieren beider Seiten',
      'Die Produktregel besagt, dass die Ableitung von u mal v gleich u strich v plus u v strich ist.',
      'Integriert man beide Seiten, so bleibt auf der linken Seite das Produkt u mal v stehen.',
      'Stellt man um, erhaelt man die bekannte Formel der partiellen Integration fuer Integrale.',
      'Bedingung: u und v muessen differenzierbar sein, sonst gilt die Formel nicht.',
    ],
    ['Geschichte der Analysis', 'Newton und Leibniz'],
    ['Substitution', 'Ersetze g von x durch t.'],
  ];
  final bytes = _pdf(lecture);
  final texts = PdfService().extractPageTexts(bytes);
  final pages = CondenseService.pagesFromPageTexts(texts);

  test('die Testseiten werden in sinnvolle Blöcke zerlegt', () {
    expect(pages, hasLength(4));
    expect(pages[1].blocks, isNotEmpty);
    expect(pages[1].blocks.first.text, contains('Partielle Integration'));
  });

  test('nur die behaltenen Seiten stehen in der gekürzten PDF, in Originalreihenfolge', () {
    final sections = [
      CondenseSection(title: 'Partielle Integration', blockIds: [for (final b in pages[1].blocks) b.id]),
      CondenseSection(title: 'Substitution', blockIds: [for (final b in pages[3].blocks) b.id]),
    ];
    final keep = CondenseService.keptPageNumbers(pages, sections);
    expect(keep, [2, 4]);
    final result = CondensePdf.build(
      bytes,
      keepPages: keep,
      pages: pages,
      runs: CondenseService.runsByPage(pages, sections),
      markers: false,
    );
    final out = PdfService().extractPageTexts(result);
    expect(out, hasLength(2));
    expect(out[0], contains('Partielle Integration'));
    expect(out[1], contains('Substitution'));
    expect(out.join(), isNot(contains('Organisatorisches')));
    // Ohne Markierungen weder Annotation noch Stempel.
    expect(_annotations(result, 0), 0);
    expect(out[0], isNot(contains('Original')));
  });

  test('Markierungen: gelber Streifen am Beginn des relevanten Teils und Original-Seitenzahl', () {
    // Von Seite 2 ist nur der hintere Teil relevant (die Bedingung, nicht der Titel).
    final blocks = pages[1].blocks;
    expect(blocks.length, greaterThanOrEqualTo(2), reason: 'Seite 2 braucht mehrere Blöcke für den Test');
    final sections = [
      CondenseSection(title: 'Bedingung', blockIds: [blocks.last.id]),
    ];
    final keep = CondenseService.keptPageNumbers(pages, sections);
    final runs = CondenseService.runsByPage(pages, sections);
    expect(runs[2], isNotNull);
    final result = CondensePdf.build(bytes, keepPages: keep, pages: pages, runs: runs, markers: true);
    expect(_annotations(result, 0), runs[2]!.length);
    final out = PdfService().extractPageTexts(result);
    expect(out.single, contains('Original: S. 2'));
    // Der Seiteninhalt bleibt unverändert.
    expect(out.single, contains('Partielle Integration'));
  });

  test('eine ganz behaltene Seite bekommt nur die Seitenzahl, keinen Streifen', () {
    final sections = [
      CondenseSection(title: 'Substitution', blockIds: [for (final b in pages[3].blocks) b.id]),
    ];
    final result = CondensePdf.build(
      bytes,
      keepPages: const [4],
      pages: pages,
      runs: CondenseService.runsByPage(pages, sections),
      markers: true,
    );
    expect(_annotations(result, 0), 0);
    expect(PdfService().extractPageTexts(result).single, contains('Original: S. 4'));
  });

  test('Folien tragen "Folie" im Stempel', () {
    final result = CondensePdf.build(
      bytes,
      keepPages: const [2],
      pages: pages,
      runs: const {},
      markers: true,
      label: 'Folie',
    );
    expect(PdfService().extractPageTexts(result).single, contains('Original: Folie 2'));
  });
}
