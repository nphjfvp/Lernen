/// Findet ein von der KI geliefertes Zitat (siehe [AiService.suggestHighlights])
/// innerhalb der Textzeilen EINER PDF-Seite wieder, damit es dort visuell als
/// Annotation platziert werden kann (siehe MaterialViewerScreen). Bewusst von
/// den PDF-Rendering-Packages entkoppelt (reine String-Listen rein/raus) –
/// PdfTextExtractor.TextLine bzw. PdfTextLine-Umwandlung übernimmt der
/// Aufrufer, damit diese Logik ohne Plugin-Initialisierung testbar ist.
class HighlightMatcher {
  HighlightMatcher._();

  /// Sucht [quote] in [pageLines] (Text-Zeilen EINER Seite, in
  /// Dokumentreihenfolge). PDF-Zeilen brechen oft mitten im Satz um, daher
  /// wird über ein Fenster aus bis zu [maxWindow] aufeinanderfolgenden Zeilen
  /// zusammengesetzt gesucht. Gibt die (0-basierten) Indizes der
  /// zusammenhängenden Zeilen zurück, die [quote] gemeinsam enthalten, oder
  /// `null`, wenn die Stelle auf dieser Seite nicht auffindbar ist.
  static List<int>? findLineRange(List<String> pageLines, String quote, {int maxWindow = 8}) {
    final target = _normalize(quote);
    if (target.isEmpty) return null;

    for (var start = 0; start < pageLines.length; start++) {
      var combined = '';
      for (var end = start; end < pageLines.length && end < start + maxWindow; end++) {
        final normalizedLine = _normalize(pageLines[end]);
        combined = combined.isEmpty ? normalizedLine : '$combined $normalizedLine';
        if (combined.contains(target)) {
          return List.generate(end - start + 1, (i) => start + i);
        }
        // Ist das Fenster schon deutlich länger als das gesuchte Zitat und
        // trotzdem kein Treffer, lohnt sich hier kein weiteres Ausdehnen.
        if (combined.length > target.length + 200) break;
      }
    }
    return null;
  }

  static String _normalize(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}
