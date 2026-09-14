import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lecture_unit.dart';

void main() {
  group('LectureUnit – Feld-Defaults', () {
    test('covered defaultet auf false, wenn nicht angegeben', () {
      final unit = LectureUnit(
        id: '1',
        moduleId: 'm1',
        title: 'Einheit 1',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(unit.covered, isFalse);
    });
  });

  group('LectureUnit – toMap/fromMap Round-Trip', () {
    test('erhält Titel und covered-Status', () {
      final unit = LectureUnit(
        id: '1',
        moduleId: 'm1',
        title: 'Einheit 1',
        createdAt: DateTime(2026, 1, 1),
        covered: true,
      );
      final restored = LectureUnit.fromMap(unit.toMap());
      expect(restored.title, 'Einheit 1');
      expect(restored.covered, isTrue);
      expect(restored.moduleId, 'm1');
    });

    test('ist abwärtskompatibel zu Datensätzen ohne covered-Feld', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'title': 'Einheit 1',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      expect(LectureUnit.fromMap(legacyMap).covered, isFalse);
    });

    test('erhält notes', () {
      final unit = LectureUnit(
        id: '1',
        moduleId: 'm1',
        title: 'Einheit 1',
        createdAt: DateTime(2026, 1, 1),
        notes: const ['Merksatz 1', 'Merksatz 2'],
      );
      final restored = LectureUnit.fromMap(unit.toMap());
      expect(restored.notes, ['Merksatz 1', 'Merksatz 2']);
    });

    test('ist abwärtskompatibel zu Datensätzen ohne notes-Feld', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'title': 'Einheit 1',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      expect(LectureUnit.fromMap(legacyMap).notes, isEmpty);
    });
  });
}
