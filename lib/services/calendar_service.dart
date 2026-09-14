import '../models/module.dart';

enum CalendarEventType { lecture, exam }

/// Ein einzelnes Kalender-Ereignis: entweder ein Vorlesungstermin
/// (wöchentlich wiederkehrend, aus [Module.lectureSlots] expandiert) oder
/// ein Klausurtermin ([Module.examDate]). [endDateTime] ist nur bei
/// Vorlesungen mit hinterlegter Endzeit gesetzt.
class CalendarEvent {
  final CalendarEventType type;
  final Module module;
  final DateTime dateTime;
  final DateTime? endDateTime;

  const CalendarEvent({required this.type, required this.module, required this.dateTime, this.endDateTime});
}

/// Reine Logik (keine UI/Persistenz): expandiert die wöchentlichen
/// Vorlesungstermine der Module und ihre Klausurdaten zu einer sortierten
/// Ereignisliste, wiederverwendbar für Kalender-Ansicht, Startbildschirm-
/// Widget und spätere Erinnerungen.
class CalendarService {
  DateTime? _endFor(LectureSlot slot, DateTime occurrence) {
    if (!slot.hasEndTime) return null;
    return DateTime(occurrence.year, occurrence.month, occurrence.day, slot.endHour!, slot.endMinute!);
  }

  /// Alle Ereignisse im Intervall `[start, end)`, chronologisch sortiert.
  List<CalendarEvent> eventsInRange({
    required List<Module> modules,
    required DateTime start,
    required DateTime end,
  }) {
    final events = <CalendarEvent>[];
    for (final module in modules) {
      final examDate = module.examDate;
      if (examDate != null && !examDate.isBefore(start) && examDate.isBefore(end)) {
        events.add(CalendarEvent(type: CalendarEventType.exam, module: module, dateTime: examDate));
      }
      final slots = module.lectureSlots;
      if (slots != null) {
        for (final slot in slots) {
          var occurrence = slot.nextOccurrenceFrom(start);
          while (occurrence.isBefore(end)) {
            events.add(CalendarEvent(
              type: CalendarEventType.lecture,
              module: module,
              dateTime: occurrence,
              endDateTime: _endFor(slot, occurrence),
            ));
            occurrence = occurrence.add(const Duration(days: 7));
          }
        }
      }
    }
    events.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return events;
  }

  /// Der nächste anstehende Vorlesungstermin über alle Module hinweg (oder
  /// `null`, wenn nirgends Termine hinterlegt sind).
  CalendarEvent? nextLecture(List<Module> modules, {DateTime? from}) {
    final start = from ?? DateTime.now();
    CalendarEvent? best;
    for (final module in modules) {
      final slots = module.lectureSlots;
      if (slots == null) continue;
      for (final slot in slots) {
        final occurrence = slot.nextOccurrenceFrom(start);
        if (best == null || occurrence.isBefore(best.dateTime)) {
          best = CalendarEvent(
            type: CalendarEventType.lecture,
            module: module,
            dateTime: occurrence,
            endDateTime: _endFor(slot, occurrence),
          );
        }
      }
    }
    return best;
  }

  /// Die nächste anstehende Klausur über alle Module hinweg (oder `null`).
  CalendarEvent? nextExam(List<Module> modules, {DateTime? from}) {
    final start = from ?? DateTime.now();
    final startDay = DateTime(start.year, start.month, start.day);
    CalendarEvent? best;
    for (final module in modules) {
      final examDate = module.examDate;
      if (examDate == null) continue;
      if (examDate.isBefore(startDay)) continue;
      if (best == null || examDate.isBefore(best.dateTime)) {
        best = CalendarEvent(type: CalendarEventType.exam, module: module, dateTime: examDate);
      }
    }
    return best;
  }
}
