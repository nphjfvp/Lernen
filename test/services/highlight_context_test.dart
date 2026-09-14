import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/services/highlight_context.dart';

MaterialItem _material({List<MaterialHighlight> highlights = const [], String notes = ''}) {
  return MaterialItem(
    id: 'm1',
    moduleId: 'mod1',
    fileName: 'Folie1.pdf',
    kind: MaterialKind.slide,
    extractedText: 'Text',
    createdAt: DateTime(2026, 1, 1),
    highlights: highlights,
    notes: notes,
  );
}

void main() {
  group('HighlightContext.build', () {
    test('gibt einen leeren String zurück, wenn nichts markiert/notiert wurde', () {
      expect(HighlightContext.build(_material()), '');
    });

    test('listet Markierungen mit Farbbedeutung auf', () {
      final material = _material(highlights: const [
        MaterialHighlight(
            id: 'h1', text: 'Kraftwerk der Zelle', color: HighlightColor.red, source: HighlightSource.manual),
        MaterialHighlight(
            id: 'h2', text: 'Mitochondrien', color: HighlightColor.green, source: HighlightSource.manual),
      ]);
      final result = HighlightContext.build(material);
      expect(result, contains('Kraftwerk der Zelle'));
      expect(result, contains('Prüfungsfrage'));
      expect(result, contains('Mitochondrien'));
      expect(result, contains('Antwort'));
    });

    test('hängt die Notiz des Nutzers an', () {
      final material = _material(notes: 'Das kommt sicher in der Klausur dran.');
      expect(HighlightContext.build(material), contains('Das kommt sicher in der Klausur dran.'));
    });
  });
}
