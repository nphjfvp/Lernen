import 'dart:typed_data';

import '../models/app_settings.dart';
import 'ai_service.dart';
import 'pdf_service.dart';

/// Texterkennung für gescannte/bildbasierte PDFs: Seiten ohne Text-Ebene
/// werden (in kleinen Paketen, nur diese Seiten) als PDF an das
/// Vision-Modell geschickt, das den Text abschreibt. Seiten mit normaler
/// Text-Ebene bleiben unverändert – Kosten fallen nur für die leeren Seiten an.
class PdfOcrService {
  PdfOcrService({required AiService visionAi, PdfService? pdf})
      : _ai = visionAi,
        _pdf = pdf ?? PdfService();

  final AiService _ai;
  final PdfService _pdf;

  /// Nutzt das Vision-Modell aus den Einstellungen; ohne API-Key null –
  /// dann bleibt es bei der normalen Textextraktion.
  static PdfOcrService? fromSettings(AppSettings settings) => settings.hasApiKey
      ? PdfOcrService(visionAi: AiService(apiKey: settings.openRouterApiKey!, model: settings.visionModelId))
      : null;

  /// Ab so wenigen Zeichen gilt eine Seite als "ohne Text-Ebene".
  static const int minCharsPerPage = 25;

  /// Höchstens so viele Seiten pro KI-Anfrage (Antwortlänge begrenzt).
  static const int maxPagesPerRequest = 8;

  /// Automatisch nur, wenn mindestens die Hälfte der Seiten leer ist (also
  /// ein Scan) – normale Foliensätze mit ein paar reinen Bildfolien lösen
  /// so keine unerwarteten Kosten aus. Mit [force] (manuell angestoßen)
  /// werden alle leeren Seiten erkannt.
  static bool shouldOcr(List<String> pageTexts, {bool force = false}) {
    if (pageTexts.isEmpty) return false;
    final empty = pageTexts.where((t) => t.trim().length < minCharsPerPage).length;
    if (empty == 0) return false;
    return force || empty * 2 >= pageTexts.length;
  }

  /// Leere Seiten, gruppiert zu aufeinanderfolgenden Paketen.
  static List<List<int>> pagesNeedingOcr(List<String> pageTexts, {int maxGroupSize = maxPagesPerRequest}) {
    final groups = <List<int>>[];
    var current = <int>[];
    for (var i = 0; i < pageTexts.length; i++) {
      final empty = pageTexts[i].trim().length < minCharsPerPage;
      final continues = current.isNotEmpty && current.last == i - 1 && current.length < maxGroupSize;
      if (empty && (current.isEmpty || continues)) {
        current.add(i);
      } else {
        if (current.isNotEmpty) groups.add(current);
        current = empty ? [i] : <int>[];
      }
    }
    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  /// Ersetzt die leeren Seiten in [pageTexts] durch erkannten Text und
  /// liefert den gesamten Dokumenttext. Schlägt die Erkennung eines Pakets
  /// fehl, wird sie abgebrochen (Fehler an den Aufrufer).
  Future<String> recognize(
    Uint8List pdfBytes,
    List<String> pageTexts, {
    void Function(int done, int total)? onProgress,
  }) async {
    final result = List<String>.of(pageTexts);
    final groups = pagesNeedingOcr(pageTexts);
    for (var g = 0; g < groups.length; g++) {
      onProgress?.call(g, groups.length);
      final group = groups[g];
      final subPdf = _pdf.extractPages(pdfBytes, group);
      final pages = await _ai.transcribePdfPages(subPdf, pageCount: group.length);
      for (var i = 0; i < group.length && i < pages.length; i++) {
        if (pages[i].trim().isNotEmpty) result[group[i]] = pages[i].trim();
      }
    }
    onProgress?.call(groups.length, groups.length);
    return result.where((t) => t.trim().isNotEmpty).join('\n\n').trim();
  }
}
