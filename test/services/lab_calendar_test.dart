import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/calendar_service.dart';

Module _module(String id) => Module(
      id: id,
      name: 'Modul $id',
      colorValue: 0xFF3D5AFE,
      icon: '📘',
      examDate: null,
      createdAt: DateTime(2026, 1, 1),
    );

LabExperiment _lab(String id, String moduleId, {DateTime? labDate, DateTime? reportDue, bool finished = false}) =>
    LabExperiment(
      id: id,
      moduleId: moduleId,
      title: 'Versuch $id',
      createdAt: DateTime(2026, 9, 1),
      labDate: labDate,
      reportDue: reportDue,
      finished: finished,
    );

void main() {
  final service = CalendarService();
  final start = DateTime(2026, 9, 1);
  final end = DateTime(2026, 10, 1);

  test('Labortermin und Berichtsabgabe erscheinen als Ereignisse, sortiert und mit Titel', () {
    final events = service.eventsInRange(
      modules: [_module('m1')],
      start: start,
      end: end,
      labs: [_lab('a', 'm1', labDate: DateTime(2026, 9, 20), reportDue: DateTime(2026, 9, 27))],
    );
    expect(events.map((e) => e.type), [CalendarEventType.lab, CalendarEventType.labReport]);
    expect(events.first.title, 'Versuch a');
    expect(events.first.experimentId, 'a');
    expect(events.first.dateTime, DateTime(2026, 9, 20));
    expect(events.first.module.id, 'm1');
  });

  test('außerhalb des Zeitraums, ohne Datum oder ohne Fach: nichts', () {
    final events = service.eventsInRange(
      modules: [_module('m1')],
      start: start,
      end: end,
      labs: [
        _lab('früh', 'm1', labDate: DateTime(2026, 8, 31)),
        _lab('spät', 'm1', labDate: DateTime(2026, 10, 1)),
        _lab('ohne', 'm1'),
        _lab('fremd', 'gibt-es-nicht', labDate: DateTime(2026, 9, 5)),
      ],
    );
    expect(events, isEmpty);
  });

  test('ein abgegebener Bericht taucht nicht mehr als Frist auf, der Termin bleibt', () {
    final events = service.eventsInRange(
      modules: [_module('m1')],
      start: start,
      end: end,
      labs: [_lab('a', 'm1', labDate: DateTime(2026, 9, 5), reportDue: DateTime(2026, 9, 12), finished: true)],
    );
    expect(events.map((e) => e.type), [CalendarEventType.lab]);
  });

  test('ohne Laborversuche unverändert (auch für Vorlesungen und Klausuren)', () {
    final module = Module(
      id: 'm1',
      name: 'M',
      colorValue: 0xFF3D5AFE,
      icon: '📘',
      examDate: DateTime(2026, 9, 15),
      createdAt: DateTime(2026, 1, 1),
    );
    final events = service.eventsInRange(modules: [module], start: start, end: end);
    expect(events.single.type, CalendarEventType.exam);
    expect(events.single.title, isNull);
    expect(events.single.experimentId, isNull);
  });
}
