import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/material_item.dart';

void main() {
  group('MaterialItem – covered-Feld', () {
    test('defaultet auf false, wenn nicht angegeben', () {
      final material = MaterialItem(
        id: '1',
        moduleId: 'm1',
        fileName: 'a.pdf',
        kind: MaterialKind.slide,
        extractedText: 'text',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(material.covered, isFalse);
    });

    test('toMap/fromMap Round-Trip erhält den covered-Status', () {
      final material = MaterialItem(
        id: '1',
        moduleId: 'm1',
        fileName: 'a.pdf',
        kind: MaterialKind.exercise,
        extractedText: 'text',
        createdAt: DateTime(2026, 1, 1),
        covered: true,
      );
      final restored = MaterialItem.fromMap(material.toMap());
      expect(restored.covered, isTrue);
    });

    test('fromMap ist abwärtskompatibel zu älteren Datensätzen ohne covered-Feld', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'fileName': 'a.pdf',
        'kind': 'slide',
        'extractedText': 'text',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final restored = MaterialItem.fromMap(legacyMap);
      expect(restored.covered, isFalse);
    });
  });

  group('MaterialItem – topicIndex-Feld', () {
    test('ist null, wenn nicht angegeben (noch nicht indiziert)', () {
      final material = MaterialItem(
        id: '1',
        moduleId: 'm1',
        fileName: 'a.pdf',
        kind: MaterialKind.slide,
        extractedText: 'text',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(material.topicIndex, isNull);
    });

    test('toMap/fromMap Round-Trip erhält den topicIndex', () {
      final material = MaterialItem(
        id: '1',
        moduleId: 'm1',
        fileName: 'a.pdf',
        kind: MaterialKind.slide,
        extractedText: 'text',
        createdAt: DateTime(2026, 1, 1),
        topicIndex: 'Themen: Kristallgitter, Gitterfehler.',
      );
      final restored = MaterialItem.fromMap(material.toMap());
      expect(restored.topicIndex, 'Themen: Kristallgitter, Gitterfehler.');
    });

    test('fromMap ist abwärtskompatibel zu älteren Datensätzen ohne topicIndex-Feld', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'fileName': 'a.pdf',
        'kind': 'slide',
        'extractedText': 'text',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final restored = MaterialItem.fromMap(legacyMap);
      expect(restored.topicIndex, isNull);
    });
  });

  group('MaterialItem – Markierungen/Notiz/PDF-Referenz', () {
    test('defaulten auf leer, wenn nicht angegeben', () {
      final material = MaterialItem(
        id: '1',
        moduleId: 'm1',
        fileName: 'a.pdf',
        kind: MaterialKind.slide,
        extractedText: 'text',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(material.highlights, isEmpty);
      expect(material.notes, '');
      expect(material.hasViewablePdf, isFalse);
    });

    test('hasViewablePdf ist true, wenn filePath ODER fileBytesBase64 gesetzt ist', () {
      final withPath = MaterialItem(
        id: '1',
        moduleId: 'm1',
        fileName: 'a.pdf',
        kind: MaterialKind.slide,
        extractedText: 'text',
        createdAt: DateTime(2026, 1, 1),
        filePath: '/tmp/a.pdf',
      );
      final withBytes = MaterialItem(
        id: '2',
        moduleId: 'm1',
        fileName: 'b.pdf',
        kind: MaterialKind.slide,
        extractedText: 'text',
        createdAt: DateTime(2026, 1, 1),
        fileBytesBase64: 'YWJj',
      );
      expect(withPath.hasViewablePdf, isTrue);
      expect(withBytes.hasViewablePdf, isTrue);
    });

    test('toMap/fromMap Round-Trip erhält Markierungen, Notiz und PDF-Referenz', () {
      final material = MaterialItem(
        id: '1',
        moduleId: 'm1',
        fileName: 'a.pdf',
        kind: MaterialKind.slide,
        extractedText: 'text',
        createdAt: DateTime(2026, 1, 1),
        filePath: '/tmp/a.pdf',
        notes: 'Kommt sicher in der Klausur dran.',
        highlights: const [
          MaterialHighlight(
            id: 'h1',
            text: 'Kraftwerk der Zelle',
            color: HighlightColor.red,
            source: HighlightSource.manual,
            pageNumber: 2,
          ),
          MaterialHighlight(
            id: 'h2',
            text: 'Mitochondrien',
            color: HighlightColor.green,
            source: HighlightSource.ai,
            reason: 'Kernaussage des Abschnitts.',
          ),
        ],
      );
      final restored = MaterialItem.fromMap(material.toMap());
      expect(restored.filePath, '/tmp/a.pdf');
      expect(restored.notes, 'Kommt sicher in der Klausur dran.');
      expect(restored.highlights.length, 2);
      expect(restored.highlights[0].text, 'Kraftwerk der Zelle');
      expect(restored.highlights[0].color, HighlightColor.red);
      expect(restored.highlights[0].source, HighlightSource.manual);
      expect(restored.highlights[0].pageNumber, 2);
      expect(restored.highlights[1].color, HighlightColor.green);
      expect(restored.highlights[1].source, HighlightSource.ai);
      expect(restored.highlights[1].reason, 'Kernaussage des Abschnitts.');
      expect(restored.highlights[1].pageNumber, isNull);
    });

    test('fromMap ist abwärtskompatibel zu älteren Datensätzen ohne diese Felder', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'fileName': 'a.pdf',
        'kind': 'slide',
        'extractedText': 'text',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final restored = MaterialItem.fromMap(legacyMap);
      expect(restored.filePath, isNull);
      expect(restored.fileBytesBase64, isNull);
      expect(restored.highlights, isEmpty);
      expect(restored.notes, '');
    });

    test('copyWith aktualisiert Markierungen/Notiz unabhängig voneinander', () {
      final material = MaterialItem(
        id: '1',
        moduleId: 'm1',
        fileName: 'a.pdf',
        kind: MaterialKind.slide,
        extractedText: 'text',
        createdAt: DateTime(2026, 1, 1),
      );
      final updated = material.copyWith(notes: 'Neue Notiz');
      expect(updated.notes, 'Neue Notiz');
      expect(updated.highlights, isEmpty);
      expect(updated.id, material.id);
    });
  });

  group('MaterialItem.practiceExamTextFrom', () {
    MaterialItem material(MaterialKind kind, String text) => MaterialItem(
          id: kind.name,
          moduleId: 'm1',
          fileName: '${kind.name}.pdf',
          kind: kind,
          extractedText: text,
          createdAt: DateTime(2026, 1, 1),
        );

    test('liefert den Text der Übungsklausur, wenn vorhanden', () {
      final materials = [
        material(MaterialKind.slide, 'Folientext'),
        material(MaterialKind.practiceExam, 'Klausurtext'),
      ];
      expect(MaterialItem.practiceExamTextFrom(materials), 'Klausurtext');
    });

    test('liefert null, wenn keine Übungsklausur hochgeladen wurde', () {
      final materials = [material(MaterialKind.slide, 'Folientext')];
      expect(MaterialItem.practiceExamTextFrom(materials), isNull);
    });
  });
}
