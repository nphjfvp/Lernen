import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/module.dart';

Module _module({List<LectureSlot>? lectureSlots, DateTime? examDate}) {
  return Module(
    id: 'm1',
    name: 'Analysis 2',
    colorValue: 0xFF3D5AFE,
    icon: '📘',
    examDate: examDate,
    createdAt: DateTime(2026, 1, 1),
    lectureSlots: lectureSlots,
  );
}

void main() {
  group('LectureSlot.nextOccurrenceFrom', () {
    test('liegt später am selben Tag, wenn die Uhrzeit noch nicht vorbei ist', () {
      const slot = LectureSlot(weekday: DateTime.monday, hour: 14, minute: 0);
      final from = DateTime(2026, 1, 5, 9, 0); // Montag, 09:00
      final next = slot.nextOccurrenceFrom(from);
      expect(next, DateTime(2026, 1, 5, 14, 0));
    });

    test('springt eine Woche weiter, wenn die Uhrzeit am selben Tag schon vorbei ist', () {
      const slot = LectureSlot(weekday: DateTime.monday, hour: 8, minute: 0);
      final from = DateTime(2026, 1, 5, 9, 0); // Montag, 09:00 (Termin war 08:00)
      final next = slot.nextOccurrenceFrom(from);
      expect(next, DateTime(2026, 1, 12, 8, 0));
    });

    test('findet den nächsten passenden Wochentag', () {
      const slot = LectureSlot(weekday: DateTime.thursday, hour: 10, minute: 15);
      final from = DateTime(2026, 1, 5, 9, 0); // Montag
      final next = slot.nextOccurrenceFrom(from);
      expect(next, DateTime(2026, 1, 8, 10, 15)); // Donnerstag derselben Woche
    });

    test('mit Endzeit: läuft die Vorlesung noch, zählt sie nicht als vorbei', () {
      const slot = LectureSlot(weekday: DateTime.monday, hour: 10, minute: 0, endHour: 11, endMinute: 30);
      final from = DateTime(2026, 1, 5, 10, 45); // Montag, mitten in der Vorlesung
      final next = slot.nextOccurrenceFrom(from);
      expect(next, DateTime(2026, 1, 5, 10, 0)); // bleibt der heutige Termin
    });

    test('mit Endzeit: springt erst nach Vorlesungsende eine Woche weiter', () {
      const slot = LectureSlot(weekday: DateTime.monday, hour: 10, minute: 0, endHour: 11, endMinute: 30);
      final from = DateTime(2026, 1, 5, 12, 0); // Montag, nach Vorlesungsende
      final next = slot.nextOccurrenceFrom(from);
      expect(next, DateTime(2026, 1, 12, 10, 0));
    });
  });

  group('LectureSlot.timeLabel', () {
    test('zeigt nur die Startzeit ohne hinterlegte Endzeit', () {
      const slot = LectureSlot(weekday: 1, hour: 9, minute: 5);
      expect(slot.timeLabel, '09:05');
      expect(slot.hasEndTime, isFalse);
    });

    test('zeigt Start–Ende mit hinterlegter Endzeit', () {
      const slot = LectureSlot(weekday: 1, hour: 10, minute: 0, endHour: 11, endMinute: 30);
      expect(slot.timeLabel, '10:00–11:30');
      expect(slot.hasEndTime, isTrue);
    });
  });

  group('LectureSlot.toMap/fromMap', () {
    test('Round-Trip erhält alle Felder inkl. Endzeit', () {
      const slot = LectureSlot(weekday: 3, hour: 12, minute: 30, endHour: 14, endMinute: 0);
      final restored = LectureSlot.fromMap(slot.toMap());
      expect(restored.weekday, 3);
      expect(restored.hour, 12);
      expect(restored.minute, 30);
      expect(restored.endHour, 14);
      expect(restored.endMinute, 0);
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne Endzeit-Felder', () {
      final map = const LectureSlot(weekday: 3, hour: 12, minute: 30).toMap()
        ..remove('endHour')
        ..remove('endMinute');
      final restored = LectureSlot.fromMap(map);
      expect(restored.endHour, isNull);
      expect(restored.endMinute, isNull);
      expect(restored.hasEndTime, isFalse);
    });
  });

  group('Module.nextLectureFrom', () {
    test('gibt null zurück, wenn keine Termine hinterlegt sind', () {
      final module = _module();
      expect(module.nextLectureFrom(DateTime(2026, 1, 5)), isNull);
    });

    test('wählt unter mehreren Terminen den zeitlich nächsten', () {
      final module = _module(lectureSlots: const [
        LectureSlot(weekday: DateTime.friday, hour: 10, minute: 0),
        LectureSlot(weekday: DateTime.tuesday, hour: 8, minute: 0),
      ]);
      final next = module.nextLectureFrom(DateTime(2026, 1, 5, 7, 0)); // Montag
      expect(next, DateTime(2026, 1, 6, 8, 0)); // Dienstag vor Freitag
    });
  });

  group('Module – toMap/fromMap mit lectureSlots', () {
    test('Round-Trip erhält lectureSlots', () {
      final module = _module(lectureSlots: const [
        LectureSlot(weekday: 1, hour: 10, minute: 0),
        LectureSlot(weekday: 3, hour: 14, minute: 15),
      ]);
      final restored = Module.fromMap(module.toMap());
      expect(restored.lectureSlots, isNotNull);
      expect(restored.lectureSlots!.length, 2);
      expect(restored.lectureSlots![1].hour, 14);
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne lectureSlots-Feld', () {
      final map = _module().toMap()..remove('lectureSlots');
      final restored = Module.fromMap(map);
      expect(restored.lectureSlots, isNull);
    });
  });

  group('Module.copyWith', () {
    test('clearLectureSlots setzt die Termine zurück', () {
      final module = _module(lectureSlots: const [LectureSlot(weekday: 1, hour: 9, minute: 0)]);
      final cleared = module.copyWith(clearLectureSlots: true);
      expect(cleared.lectureSlots, isNull);
    });
  });
}
