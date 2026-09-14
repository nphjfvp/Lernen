import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/home_widget_service.dart';

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

Flashcard _dueCard(String id, String moduleId, DateTime due) {
  return Flashcard(
    id: id,
    moduleId: moduleId,
    front: 'F',
    back: 'A',
    createdAt: DateTime(2025, 1, 1),
    due: due,
    reps: 1,
  );
}

void main() {
  final service = HomeWidgetService();

  group('HomeWidgetService.buildLectureLine', () {
    test('zeigt Wochentag, Uhrzeit und Modulnamen der nächsten Vorlesung', () {
      final module = _module(
        id: 'm1',
        name: 'Analysis 2',
        lectureSlots: const [LectureSlot(weekday: DateTime.monday, hour: 10, minute: 0)],
      );
      final line = service.buildLectureLine([module], from: DateTime(2026, 1, 5, 8, 0));
      expect(line, contains('Mo 10:00'));
      expect(line, contains('Analysis 2'));
    });

    test('zeigt einen Platzhalter, wenn keine Vorlesung geplant ist', () {
      final line = service.buildLectureLine([_module(id: 'm1')]);
      expect(line, 'Keine Vorlesung geplant');
    });

    test('zeigt Start–Ende, wenn eine Endzeit hinterlegt ist', () {
      final module = _module(
        id: 'm1',
        name: 'Analysis 2',
        lectureSlots: const [
          LectureSlot(weekday: DateTime.monday, hour: 10, minute: 0, endHour: 11, endMinute: 30),
        ],
      );
      final line = service.buildLectureLine([module], from: DateTime(2026, 1, 5, 8, 0));
      expect(line, contains('10:00–11:30'));
    });
  });

  group('HomeWidgetService.buildReminderLine', () {
    test('zeigt die Anzahl fälliger Karten heute', () {
      final module = _module(id: 'm1');
      final cards = [
        _dueCard('c1', 'm1', DateTime(2026, 1, 5)),
        _dueCard('c2', 'm1', DateTime(2026, 1, 5)),
      ];
      final line = service.buildReminderLine([module], cards, now: DateTime(2026, 1, 5));
      expect(line, contains('2 Karten fällig heute'));
    });

    test('zeigt einen positiven Hinweis, wenn nichts fällig ist', () {
      final line = service.buildReminderLine([_module(id: 'm1')], const [], now: DateTime(2026, 1, 5));
      expect(line, contains('nichts fällig'));
    });
  });

  group('HomeWidgetService.buildCountdownLine', () {
    test('zeigt Modulnamen und verbleibende Tage bis zur nächsten Klausur', () {
      final module = _module(id: 'm1', name: 'Analysis 2', examDate: DateTime(2026, 1, 15));
      final line = service.buildCountdownLine([module], from: DateTime(2026, 1, 5));
      expect(line, contains('Analysis 2'));
      expect(line, contains('10 Tag'));
    });

    test('zeigt einen Platzhalter, wenn keine Klausur ansteht', () {
      final line = service.buildCountdownLine([_module(id: 'm1')]);
      expect(line, 'Keine Klausur geplant');
    });
  });
}
