import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/highlight_matcher.dart';

void main() {
  group('HighlightMatcher.findLineRange', () {
    test('findet ein Zitat, das komplett in einer einzigen Zeile steht', () {
      final lines = ['Die Mitochondrien sind das Kraftwerk der Zelle.', 'Zweite Zeile.'];
      expect(HighlightMatcher.findLineRange(lines, 'Kraftwerk der Zelle'), [0]);
    });

    test('findet ein Zitat, das über zwei PDF-Zeilen umbricht', () {
      final lines = ['Die Mitochondrien sind das Kraft-', 'werk der Zelle.', 'Andere Zeile.'];
      expect(HighlightMatcher.findLineRange(lines, 'Kraft- werk der Zelle'), [0, 1]);
    });

    test('ignoriert Groß-/Kleinschreibung und mehrfache Leerzeichen', () {
      final lines = ['Die   MITOCHONDRIEN sind wichtig.'];
      expect(HighlightMatcher.findLineRange(lines, 'mitochondrien sind wichtig'), [0]);
    });

    test('gibt null zurück, wenn das Zitat nicht vorkommt', () {
      final lines = ['Ein völlig anderer Satz.'];
      expect(HighlightMatcher.findLineRange(lines, 'Kraftwerk der Zelle'), isNull);
    });

    test('gibt null zurück bei leerem Zitat', () {
      expect(HighlightMatcher.findLineRange(['Text'], ''), isNull);
      expect(HighlightMatcher.findLineRange(['Text'], '   '), isNull);
    });

    test('findet den ersten Treffer, wenn das Zitat mehrfach vorkommt', () {
      final lines = ['Wiederholung.', 'Wiederholung.', 'Wiederholung.'];
      expect(HighlightMatcher.findLineRange(lines, 'Wiederholung'), [0]);
    });

    test('bricht die Fenstersuche ab, wenn sie zu lang würde, statt falsch zu matchen', () {
      final lines = List.generate(20, (i) => 'Zeile $i mit etwas mehr Fülltext drumherum.');
      expect(HighlightMatcher.findLineRange(lines, 'ein Zitat, das nirgends vorkommt'), isNull);
    });
  });
}
