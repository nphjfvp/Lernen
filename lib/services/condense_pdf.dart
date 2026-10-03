import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/condense.dart';
import 'condense_service.dart';
import 'highlight_matcher.dart';
import 'pdf_service.dart';

/// Baut aus der Original-PDF die gekürzte: nur die behaltenen Seiten, auf Wunsch
/// mit Markierungen – an jedem zusammenhängenden relevanten Stück einer Seite
/// ein gelber Streifen "ab hier relevant" über den ersten Zeilen, und klein in
/// der Ecke die Seitenzahl im Original, damit sich die gekürzte Fassung mit dem
/// Skript abgleichen lässt.
class CondensePdf {
  CondensePdf._();

  /// Die Markierungsfarbe (gelb, deutlich genug auf weißem Grund).
  static final _markerColor = PdfColor(255, 214, 64);

  /// [keepPages]: Seiten des Originals (1-basiert, aufsteigend). [pages] liefert
  /// die Blocktexte, nach denen die Markierung im PDF gesucht wird; [runs] siehe
  /// CondenseService.runsByPage.
  static Uint8List build(
    Uint8List original, {
    required List<int> keepPages,
    required List<CondensePage> pages,
    required Map<int, List<({int from, int to, String title})>> runs,
    required bool markers,
    String label = 'Seite',
  }) {
    final subset = PdfService().extractPages(original, [for (final p in keepPages) p - 1]);
    if (!markers) return subset;

    final byNumber = {for (final p in pages) p.number: p};
    final document = PdfDocument(inputBytes: subset);
    try {
      final extractor = PdfTextExtractor(document);
      final font = PdfStandardFont(PdfFontFamily.helvetica, 7);
      for (var i = 0; i < document.pages.count && i < keepPages.length; i++) {
        final originalNumber = keepPages[i];
        final page = document.pages[i];
        // Erst lesen, dann beschriften – sonst stünde der Stempel im Text.
        final lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
        final texts = [for (final l in lines) l.text];

        for (final run in runs[originalNumber] ?? const <({int from, int to, String title})>[]) {
          final block = byNumber[originalNumber]?.blocks.elementAtOrNull(run.from - 1);
          if (block == null) continue;
          final range = HighlightMatcher.findLineRange(texts, _anchorOf(block.text));
          if (range == null) continue;
          // Nur der Anfang wird markiert (die ersten Zeilen), nicht das ganze Stück.
          final rects = <Rect>[for (final index in range.take(2)) lines[index].bounds];
          final bounds = rects.skip(1).fold<Rect>(rects.first, (a, b) => a.expandToInclude(b));
          page.annotations.add(
            PdfTextMarkupAnnotation(
              bounds,
              'Ab hier relevant: ${run.title}',
              _markerColor,
              boundsCollection: rects,
              textMarkupAnnotationType: PdfTextMarkupAnnotationType.highlight,
              author: 'Lernen',
              subject: 'Kürzen',
              setAppearance: true,
            ),
          );
        }

        final stamp = CondenseService.stampText(label, originalNumber);
        final width = page.size.width;
        page.graphics.drawString(
          _ascii(stamp),
          font,
          brush: PdfBrushes.gray,
          bounds: Rect.fromLTWH(width - 104, 3, 100, 10),
          format: PdfStringFormat(alignment: PdfTextAlignment.right),
        );
      }
      return Uint8List.fromList(document.saveSync());
    } finally {
      document.dispose();
    }
  }

  /// Das, wonach im PDF-Text gesucht wird: der Anfang des Blocks (die erste
  /// Zeile, bei sehr kurzer erste Zeile die ersten beiden).
  static String _anchorOf(String blockText) {
    final lines = blockText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return '';
    var anchor = lines.first.trim();
    if (anchor.length < 12 && lines.length > 1) anchor = '$anchor ${lines[1].trim()}';
    return anchor.length > 80 ? anchor.substring(0, 80) : anchor;
  }

  /// Die Standardschrift kann keine Umlaute – der Stempel soll nicht
  /// "kaputt" aussehen.
  static String _ascii(String s) => s
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('Ä', 'Ae')
      .replaceAll('Ö', 'Oe')
      .replaceAll('Ü', 'Ue')
      .replaceAll('ß', 'ss');
}
