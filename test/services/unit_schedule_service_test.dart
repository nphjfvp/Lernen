import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lecture_unit.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/unit_schedule_service.dart';

LectureUnit _unit(String id, {bool covered = false, DateTime? date}) => LectureUnit(
      id: id,
      moduleId: 'm1',
      title: 'Einheit $id',
      createdAt: DateTime(2026, 9, 1),
      covered: covered,
      scheduledDate: date,
    );

void main() {
  group('LectureUnit.isCoveredOn', () {
    test('abgehakt ist immer behandelt, Termin zählt ab dem Tag selbst', () {
      expect(_unit('a', covered: true).isCoveredOn(DateTime(2026, 1, 1)), isTrue);
      final dated = _unit('b', date: DateTime(2026, 10, 14));
      expect(dated.isCoveredOn(DateTime(2026, 10, 13, 23, 59)), isFalse);
      expect(dated.isCoveredOn(DateTime(2026, 10, 14, 8)), isTrue);
      expect(_unit('c').isCoveredOn(DateTime(2030)), isFalse);
    });

    test('Termin übersteht toMap/fromMap, alte Datensätze ohne Termin bleiben lesbar', () {
      final unit = _unit('a', date: DateTime(2026, 10, 14));
      expect(LectureUnit.fromMap(unit.toMap()).scheduledDate, DateTime(2026, 10, 14));
      final old = unit.toMap()..remove('scheduledDate');
      expect(LectureUnit.fromMap(old).scheduledDate, isNull);
    });
  });

  group('UnitScheduleService.assignLectureDates', () {
    final module = Module(
      id: 'm1',
      name: 'Mathe',
      colorValue: 0,
      icon: '📘',
      examDate: null,
      createdAt: DateTime(2026, 1, 1),
      lectureSlots: const [LectureSlot(weekday: DateTime.tuesday, hour: 10, minute: 0)],
    );

    test('verteilt offene Einheiten der Reihe nach auf die kommenden Vorlesungen', () {
      // Freitag, 25.09.2026 → nächste Dienstage: 29.09., 06.10., 13.10.
      final updated = UnitScheduleService().assignLectureDates(
        units: [
          _unit('done', covered: true),
          _unit('past', date: DateTime(2026, 9, 22)),
          _unit('a'),
          _unit('b', date: DateTime(2026, 12, 1)),
          _unit('c'),
        ],
        module: module,
        from: DateTime(2026, 9, 25, 14),
      );
      expect(updated.map((u) => u.id).toList(), ['a', 'b', 'c']);
      expect(updated.map((u) => u.scheduledDate).toList(), [
        DateTime(2026, 9, 29),
        DateTime(2026, 10, 6),
        DateTime(2026, 10, 13),
      ]);
    });

    test('ohne Stundenplan passiert nichts', () {
      final noSlots = Module(
        id: 'm2',
        name: 'X',
        colorValue: 0,
        icon: '📘',
        examDate: null,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(
        UnitScheduleService().assignLectureDates(units: [_unit('a')], module: noSlots, from: DateTime(2026, 9, 25)),
        isEmpty,
      );
    });
  });
}
