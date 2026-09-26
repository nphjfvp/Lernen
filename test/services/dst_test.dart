import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/calendar_days.dart';
import 'package:lernen/services/calendar_service.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/home_widget_service.dart';
import 'package:lernen/services/stats_service.dart';

/// Tage/Uhrzeiten über die Zeitumstellung hinweg (Beginn der Sommerzeit in
/// der EU am 29.03.2026, Ende am 25.10.2026). Aussagekräftig in einer Zeitzone mit Umstellung, z.B.
/// `TZ=Europe/Berlin flutter test test/services/dst_test.dart`; in UTC
/// laufen sie trivial durch.
void main() {
  final module = Module(
    id: 'm1',
    name: 'Analysis',
    colorValue: 0xFF000000,
    icon: 'A',
    examDate: null,
    createdAt: DateTime(2026, 9, 1),
    lectureSlots: const [LectureSlot(weekday: DateTime.monday, hour: 10, minute: 15)],
  );

  test('wöchentliche Vorlesung behält ihre Uhrzeit über die Zeitumstellung', () {
    final events = CalendarService().eventsInRange(
      modules: [module],
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 11, 30),
    );
    expect(events, isNotEmpty);
    for (final e in events) {
      expect(e.dateTime.hour, 10, reason: '${e.dateTime}');
      expect(e.dateTime.minute, 15);
      expect(e.dateTime.weekday, DateTime.monday);
    }
  });

  test('nächste Vorlesung über die Zeitumstellung hinweg', () {
    final next = module.lectureSlots!.single.nextOccurrenceFrom(DateTime(2026, 10, 24, 12));
    expect(next, DateTime(2026, 10, 26, 10, 15));
  });

  test('Streak reißt an der Zeitumstellung nicht ab', () {
    final studyDays = {for (var d = 20; d <= 30; d++) DateTime(2026, 10, d)};
    final stats = StatsService().compute(
      modules: const [],
      allCards: const [],
      studyDays: studyDays,
      now: DateTime(2026, 10, 30, 18),
    );
    expect(stats.streakDays, 11);
  });

  test('Fälligkeit bleibt Mitternacht, auch über die Zeitumstellung', () {
    final card = Flashcard(
      id: 'c',
      moduleId: 'm1',
      front: 'F',
      back: 'A',
      createdAt: DateTime(2026, 10, 1),
      due: DateTime(2026, 10, 1),
      reps: 3,
      stability: 5,
      difficulty: 5,
      state: 'review',
      lastReview: DateTime(2026, 10, 20),
    );
    final reviewed = FsrsService().review(card, Grade.good, now: DateTime(2026, 10, 24, 22));
    expect(reviewed.due.hour, 0);
    expect(reviewed.due.isAfter(DateTime(2026, 10, 25)), isTrue);
  });

  test('Tage bis zur Klausur über den Beginn der Sommerzeit (23-Stunden-Tag)', () {
    // difference().inDays ergäbe hier 20 (21 Tage minus eine Stunde).
    expect(calendarDaysBetween(DateTime(2026, 3, 20), DateTime(2026, 4, 10)), 21);
    expect(calendarDaysBetween(DateTime(2026, 3, 28, 23, 30), DateTime(2026, 3, 30)), 2);
    expect(calendarDaysBetween(DateTime(2026, 4, 10), DateTime(2026, 3, 20)), -21);

    final examModule = Module(
      id: 'm2',
      name: 'Lineare Algebra',
      colorValue: 0xFF000000,
      icon: 'L',
      examDate: DateTime(2026, 4, 10),
      createdAt: DateTime(2026, 3, 1),
    );
    expect(
      HomeWidgetService().buildCountdownLine([examModule], from: DateTime(2026, 3, 20, 9)),
      '⏳ Lineare Algebra in 21 Tagen',
    );
  });
}
