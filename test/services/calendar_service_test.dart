import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/calendar_service.dart';

Module _module({
  required String id,
  String name = 'Modul',
  List<LectureSlot>? lectureSlots,
  DateTime? examDate,
}) {
  return Module(
    id: id,
    name: name,
    colorValue: 0xFF3D5AFE,
    icon: '📘',
    examDate: examDate,
    createdAt: DateTime(2026, 1, 1),
    lectureSlots: lectureSlots,
  );
}

void main() {
  final service = CalendarService();

  group('CalendarService.eventsInRange', () {
    test('expandiert wöchentliche Vorlesungstermine über den Zeitraum', () {
      final module = _module(
        id: 'm1',
        lectureSlots: const [LectureSlot(weekday: DateTime.monday, hour: 10, minute: 0)],
      );
      final events = service.eventsInRange(
        modules: [module],
        start: DateTime(2026, 1, 5), // Montag
        end: DateTime(2026, 1, 26), // 3 Wochen später
      );

      expect(events.length, 3);
      expect(events[0].dateTime, DateTime(2026, 1, 5, 10, 0));
      expect(events[1].dateTime, DateTime(2026, 1, 12, 10, 0));
      expect(events[2].dateTime, DateTime(2026, 1, 19, 10, 0));
      expect(events.every((e) => e.type == CalendarEventType.lecture), isTrue);
    });

    test('enthält Klausurtermine nur innerhalb des Intervalls', () {
      final module = _module(id: 'm1', examDate: DateTime(2026, 1, 15));
      final inRange = service.eventsInRange(
        modules: [module],
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 31),
      );
      expect(inRange.single.type, CalendarEventType.exam);

      final outOfRange = service.eventsInRange(
        modules: [module],
        start: DateTime(2026, 2, 1),
        end: DateTime(2026, 2, 28),
      );
      expect(outOfRange, isEmpty);
    });

    test('übernimmt die Endzeit des Slots in jedes expandierte Ereignis', () {
      final module = _module(
        id: 'm1',
        lectureSlots: const [
          LectureSlot(weekday: DateTime.monday, hour: 10, minute: 0, endHour: 11, endMinute: 30),
        ],
      );
      final events = service.eventsInRange(
        modules: [module],
        start: DateTime(2026, 1, 5),
        end: DateTime(2026, 1, 6),
      );
      expect(events.single.endDateTime, DateTime(2026, 1, 5, 11, 30));
    });

    test('sortiert Vorlesungen und Klausuren gemeinsam chronologisch', () {
      final lecture = _module(
        id: 'm1',
        lectureSlots: const [LectureSlot(weekday: DateTime.wednesday, hour: 9, minute: 0)],
      );
      final exam = _module(id: 'm2', examDate: DateTime(2026, 1, 5, 8, 0));
      final events = service.eventsInRange(
        modules: [lecture, exam],
        start: DateTime(2026, 1, 5), // Montag
        end: DateTime(2026, 1, 8),
      );
      expect(events.first.type, CalendarEventType.exam);
      expect(events.last.type, CalendarEventType.lecture);
    });
  });

  group('CalendarService.nextLecture', () {
    test('findet den zeitlich nächsten Termin über mehrere Module', () {
      final early = _module(
        id: 'm1',
        name: 'Früh dran',
        lectureSlots: const [LectureSlot(weekday: DateTime.tuesday, hour: 8, minute: 0)],
      );
      final late = _module(
        id: 'm2',
        name: 'Spät dran',
        lectureSlots: const [LectureSlot(weekday: DateTime.friday, hour: 10, minute: 0)],
      );
      final next = service.nextLecture([early, late], from: DateTime(2026, 1, 5, 7, 0));
      expect(next!.module.name, 'Früh dran');
    });

    test('gibt null zurück, wenn kein Modul Termine hat', () {
      expect(service.nextLecture([_module(id: 'm1')]), isNull);
    });

    test('übernimmt die Endzeit des gefundenen Slots', () {
      final module = _module(
        id: 'm1',
        lectureSlots: const [
          LectureSlot(weekday: DateTime.monday, hour: 10, minute: 0, endHour: 11, endMinute: 30),
        ],
      );
      final next = service.nextLecture([module], from: DateTime(2026, 1, 5, 7, 0));
      expect(next!.endDateTime, DateTime(2026, 1, 5, 11, 30));
    });
  });

  group('CalendarService.nextExam', () {
    test('ignoriert bereits vergangene Klausuren', () {
      final past = _module(id: 'm1', examDate: DateTime(2026, 1, 1));
      final upcoming = _module(id: 'm2', examDate: DateTime(2026, 2, 1));
      final next = service.nextExam([past, upcoming], from: DateTime(2026, 1, 10));
      expect(next!.module.id, 'm2');
    });

    test('gibt null zurück, wenn keine Klausur ansteht', () {
      expect(service.nextExam([_module(id: 'm1')]), isNull);
    });
  });
}
