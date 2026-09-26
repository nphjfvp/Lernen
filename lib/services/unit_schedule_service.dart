import '../models/lecture_unit.dart';
import '../models/module.dart';
import 'calendar_service.dart';

/// Verteilt die noch nicht behandelten Einheiten eines Fachs der Reihe nach
/// auf die kommenden Vorlesungstermine aus dem Stundenplan (siehe
/// Module.lectureSlots) – danach gelten sie am jeweiligen Tag automatisch
/// als behandelt (LectureUnit.isCoveredOn).
class UnitScheduleService {
  UnitScheduleService({CalendarService? calendar}) : _calendar = calendar ?? CalendarService();

  final CalendarService _calendar;

  /// [units] in ihrer Reihenfolge (wie im Fach angezeigt). Liefert nur die
  /// geänderten Einheiten; leer, wenn das Fach keinen Stundenplan hat oder
  /// alles schon behandelt ist.
  List<LectureUnit> assignLectureDates({
    required List<LectureUnit> units,
    required Module module,
    required DateTime from,
  }) {
    final start = DateTime(from.year, from.month, from.day);
    // Offen = nicht abgehakt und Termin (falls vorhanden) nicht schon vor heute.
    final open = units.where((u) => !u.isCoveredOn(DateTime(start.year, start.month, start.day - 1))).toList();
    if (open.isEmpty) return const [];
    final lectures = _calendar
        .eventsInRange(modules: [module], start: start, end: start.add(const Duration(days: 400)))
        .where((e) => e.type == CalendarEventType.lecture)
        .toList();
    final updated = <LectureUnit>[];
    for (var i = 0; i < open.length && i < lectures.length; i++) {
      final d = lectures[i].dateTime;
      updated.add(open[i].copyWith(scheduledDate: DateTime(d.year, d.month, d.day)));
    }
    return updated;
  }
}
