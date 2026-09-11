import '../models/app_settings.dart';

/// Ergebnis der Kurzanalyse eines hochgeladenen Materials: wie lang ist der
/// Text, und welche Chunking-Einstellungen passen dazu.
class ContentAnalysis {
  const ContentAnalysis({
    required this.totalChars,
    required this.recommendedGranularity,
    required this.recommendedRollingContext,
    required this.label,
  });

  final int totalChars;
  final ChunkGranularity recommendedGranularity;
  final bool recommendedRollingContext;
  final String label;
}

/// Schätzt anhand von Textlänge, welche Chunk-Granularität für die
/// KI-Generierung sinnvoll ist – bewusst eine lokale, kostenlose Heuristik
/// (keine zusätzliche KI-Anfrage) für die "kurze Analyse" direkt nach dem
/// Hochladen, bevor der eigentliche (kostenpflichtige) Generierungsschritt
/// startet. Nutzt dieselben Längen-Schwellen wie [TextChunker], damit die
/// Empfehlung mit dem tatsächlichen Chunking-Verhalten übereinstimmt.
class ContentAnalyzer {
  ContentAnalyzer._();

  static ContentAnalysis analyze(String text) {
    final totalChars = text.length;
    final ChunkGranularity granularity;
    final String label;
    if (totalChars <= 15000) {
      granularity = ChunkGranularity.off;
      label = 'Kurzer Text – wird in einer einzigen Anfrage verarbeitet.';
    } else if (totalChars <= 60000) {
      granularity = ChunkGranularity.coarse;
      label = 'Mittellanger Text – wird in wenige große Abschnitte zerlegt.';
    } else if (totalChars <= 200000) {
      granularity = ChunkGranularity.medium;
      label = 'Langer Text – wird in mehrere Abschnitte zerlegt.';
    } else {
      granularity = ChunkGranularity.fine;
      label = 'Sehr langer Text – wird in viele kleine Abschnitte zerlegt.';
    }

    return ContentAnalysis(
      totalChars: totalChars,
      recommendedGranularity: granularity,
      recommendedRollingContext: granularity != ChunkGranularity.off,
      label: label,
    );
  }
}
