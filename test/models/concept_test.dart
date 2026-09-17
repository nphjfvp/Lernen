import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/concept.dart';

void main() {
  group('Concept – toMap/fromMap Round-Trip', () {
    test('erhält alle Felder inkl. unitId', () {
      final concept = Concept(
        id: '1',
        moduleId: 'm1',
        title: 'Titel',
        explanation: 'Erklärung',
        sourceMaterialIds: const ['mat1', 'mat2'],
        createdAt: DateTime(2026, 1, 1),
        unitId: 'u1',
      );
      final restored = Concept.fromMap(concept.toMap());
      expect(restored.title, 'Titel');
      expect(restored.explanation, 'Erklärung');
      expect(restored.sourceMaterialIds, ['mat1', 'mat2']);
      expect(restored.unitId, 'u1');
    });

    test('unitId ist null, wenn nicht angegeben', () {
      final concept = Concept(
        id: '1',
        moduleId: 'm1',
        title: 'Titel',
        explanation: 'Erklärung',
        sourceMaterialIds: const [],
        createdAt: DateTime(2026, 1, 1),
      );
      expect(Concept.fromMap(concept.toMap()).unitId, isNull);
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne unitId-Feld', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'title': 'Titel',
        'explanation': 'Erklärung',
        'sourceMaterialIds': <String>[],
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      expect(Concept.fromMap(legacyMap).unitId, isNull);
    });

    test('erhält den Seiten-Quasi-Link (linkedMaterialId/linkedPageNumber)', () {
      final concept = Concept(
        id: '1',
        moduleId: 'm1',
        title: 'Titel',
        explanation: 'Erklärung',
        sourceMaterialIds: const [],
        createdAt: DateTime(2026, 1, 1),
        linkedMaterialId: 'mat1',
        linkedPageNumber: 4,
      );
      final restored = Concept.fromMap(concept.toMap());
      expect(restored.linkedMaterialId, 'mat1');
      expect(restored.linkedPageNumber, 4);
    });

    test('Seiten-Quasi-Link ist null, wenn nicht angegeben (abwärtskompatibel)', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'title': 'Titel',
        'explanation': 'Erklärung',
        'sourceMaterialIds': <String>[],
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final restored = Concept.fromMap(legacyMap);
      expect(restored.linkedMaterialId, isNull);
      expect(restored.linkedPageNumber, isNull);
    });
  });
}
