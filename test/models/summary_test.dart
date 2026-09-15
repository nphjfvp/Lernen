import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/summary.dart';

void main() {
  group('Summary – toMap/fromMap Round-Trip', () {
    test('erhält alle Felder inkl. unitId', () {
      final summary = Summary(
        id: '1',
        moduleId: 'm1',
        sourceMaterialIds: const ['mat-1', 'mat-2'],
        title: 'Titel',
        overview: 'Übersicht',
        keyPoints: const ['Punkt 1', 'Punkt 2'],
        createdAt: DateTime(2026, 1, 1),
        unitId: 'unit-1',
      );
      final restored = Summary.fromMap(summary.toMap());
      expect(restored.title, 'Titel');
      expect(restored.keyPoints, ['Punkt 1', 'Punkt 2']);
      expect(restored.unitId, 'unit-1');
    });

    test('unitId ist null, wenn nicht angegeben', () {
      final summary = Summary(
        id: '1',
        moduleId: 'm1',
        sourceMaterialIds: const [],
        title: 'Titel',
        overview: '',
        keyPoints: const [],
        createdAt: DateTime(2026, 1, 1),
      );
      expect(Summary.fromMap(summary.toMap()).unitId, isNull);
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne unitId-Feld', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'sourceMaterialIds': <String>[],
        'title': 'Titel',
        'overview': '',
        'keyPoints': <String>[],
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      expect(Summary.fromMap(legacyMap).unitId, isNull);
    });
  });
}
