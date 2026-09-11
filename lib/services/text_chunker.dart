import '../models/app_settings.dart';

/// Zerlegt großen Text in Abschnitte für die KI-Generierung – die im
/// Vorgänger als "Rolling-Context-Chunking" bekannte Technik: statt eines
/// einzigen (u.U. abgeschnittenen) Aufrufs wird der Text in mehrere Anfragen
/// aufgeteilt, die App trägt dabei aber bereits erkannte Themen in den
/// nächsten Abschnitt weiter (siehe AiService), um Wiederholungen/Lücken an
/// den Chunk-Grenzen zu vermeiden.
class TextChunker {
  TextChunker._();

  static const Map<ChunkGranularity, int> _fixedChunkChars = {
    ChunkGranularity.coarse: 24000,
    ChunkGranularity.medium: 12000,
    ChunkGranularity.fine: 6000,
  };

  /// Chunkgröße in Zeichen für die gewählte Granularität, oder null wenn
  /// NICHT gechunkt werden soll (Text bleibt ein einziger Aufruf).
  /// "auto" wählt die Stufe anhand der Gesamtlänge: kurze Texte bleiben ganz,
  /// sehr lange werden feiner zerlegt, damit ein einzelner Chunk nicht zu
  /// grob für ein kleineres Modell-Kontextfenster wird.
  static int? chunkSizeFor(ChunkGranularity granularity, int totalLength) {
    switch (granularity) {
      case ChunkGranularity.off:
        return null;
      case ChunkGranularity.auto:
        if (totalLength <= 15000) return null;
        if (totalLength <= 60000) return _fixedChunkChars[ChunkGranularity.coarse];
        if (totalLength <= 200000) return _fixedChunkChars[ChunkGranularity.medium];
        return _fixedChunkChars[ChunkGranularity.fine];
      case ChunkGranularity.coarse:
      case ChunkGranularity.medium:
      case ChunkGranularity.fine:
        return _fixedChunkChars[granularity];
    }
  }

  /// Zerlegt [text] in Abschnitte von höchstens [chunkSizeChars] Zeichen.
  /// Schneidet bevorzugt an Absatz- oder Zeilengrenzen statt mitten im Satz.
  static List<String> split(String text, int chunkSizeChars) {
    if (chunkSizeChars <= 0 || text.length <= chunkSizeChars) {
      return text.trim().isEmpty ? [] : [text];
    }

    final chunks = <String>[];
    var start = 0;
    final minBreakPoint = (chunkSizeChars * 0.5).round();

    while (start < text.length) {
      var end = start + chunkSizeChars;
      if (end >= text.length) {
        end = text.length;
      } else {
        final paragraphBreak = text.lastIndexOf('\n\n', end);
        if (paragraphBreak > start + minBreakPoint) {
          end = paragraphBreak;
        } else {
          final lineBreak = text.lastIndexOf('\n', end);
          if (lineBreak > start + minBreakPoint) end = lineBreak;
        }
      }
      final piece = text.substring(start, end).trim();
      if (piece.isNotEmpty) chunks.add(piece);
      start = end;
    }
    return chunks;
  }
}
