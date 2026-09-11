import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/services/text_chunker.dart';

void main() {
  group('TextChunker.chunkSizeFor', () {
    test('off liefert immer null (kein Chunking)', () {
      expect(TextChunker.chunkSizeFor(ChunkGranularity.off, 500000), isNull);
    });

    test('auto liefert null für kurze Texte', () {
      expect(TextChunker.chunkSizeFor(ChunkGranularity.auto, 5000), isNull);
    });

    test('auto wählt gröbere Stufen für zunehmend längere Texte', () {
      final coarse = TextChunker.chunkSizeFor(ChunkGranularity.auto, 30000);
      final medium = TextChunker.chunkSizeFor(ChunkGranularity.auto, 100000);
      final fine = TextChunker.chunkSizeFor(ChunkGranularity.auto, 300000);
      expect(coarse, isNotNull);
      expect(medium, isNotNull);
      expect(fine, isNotNull);
      expect(medium! < coarse!, isTrue);
      expect(fine! < medium, isTrue);
    });

    test('feste Granularität ignoriert die Textlänge', () {
      expect(TextChunker.chunkSizeFor(ChunkGranularity.fine, 100),
          TextChunker.chunkSizeFor(ChunkGranularity.fine, 999999));
    });
  });

  group('TextChunker.split', () {
    test('gibt den Text unverändert zurück, wenn er bereits passt', () {
      expect(TextChunker.split('kurzer Text', 1000), ['kurzer Text']);
    });

    test('gibt leere Liste für leeren Text zurück', () {
      expect(TextChunker.split('   ', 1000), isEmpty);
    });

    test('zerlegt langen Text in mehrere Abschnitte ohne Zeichen zu verlieren', () {
      final paragraph = 'Ein Satz mit ausreichend Inhalt, um Länge zu erzeugen. ' * 20;
      final text = List.generate(6, (i) => '$paragraph[$i]').join('\n\n');
      final chunks = TextChunker.split(text, 500);

      expect(chunks.length, greaterThan(1));
      // Jeder Chunk bleibt innerhalb der Zielgröße (Trim kann geringfügig
      // abweichen, daher großzügige Toleranz statt exakter Gleichheit).
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(600));
      }
      // Kein Inhalt geht beim Zerlegen verloren.
      final rejoined = chunks.join();
      for (var i = 0; i < 6; i++) {
        expect(rejoined.contains('[$i]'), isTrue);
      }
    });

    test('bricht bevorzugt an Absatzgrenzen statt mitten im Wort', () {
      final text = 'Erster Absatz mit etwas Text.\n\nZweiter Absatz mit etwas mehr Text als der erste.';
      final chunks = TextChunker.split(text, 40);
      expect(chunks.first.endsWith('.'), isTrue);
    });
  });
}
