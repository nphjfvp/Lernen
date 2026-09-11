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
}
