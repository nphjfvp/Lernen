import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/ui/lab/lab_widgets.dart';

LabExperiment _lab(
  String title, {
  DateTime? labDate,
  DateTime? reportDue,
  int answered = 0,
  int prep = 2,
  int written = 0,
  bool finished = false,
}) =>
    LabExperiment(
      id: title,
      moduleId: 'm1',
      title: title,
      createdAt: DateTime(2026, 9, 1),
      labDate: labDate,
      reportDue: reportDue,
      finished: finished,
      prep: [
        for (var i = 0; i < prep; i++)
          LabQuestion(id: 'q$i', number: '${i + 1}', text: 'F$i', answer: i < answered ? 'Antwort' : ''),
      ],
      report: [
        for (var i = 0; i < 3; i++)
          LabReportSection(id: 's$i', title: 'S$i', text: i < written ? 'x' * LabReportSection.writtenThreshold : ''),
      ],
    );

void main() {
  final now = DateTime(2026, 9, 10, 9);

  group('labDayText', () {
    test('heute, morgen, gestern, Anzahl Tage', () {
      expect(labDayText(0), 'heute');
      expect(labDayText(1), 'morgen');
      expect(labDayText(5), 'in 5 Tagen');
      expect(labDayText(-1), 'gestern');
      expect(labDayText(-4), 'vor 4 Tagen');
    });
  });

  group('labStatusLine', () {
    test('Vorbereitung: Termin und Stand', () {
      expect(labStatusLine(_lab('A', labDate: DateTime(2026, 9, 13), answered: 1), now), 'Versuch in 3 Tagen · Vorbereitung 1/2');
      expect(labStatusLine(_lab('A'), now), 'Noch kein Termin · Vorbereitung 0/2');
      expect(labStatusLine(_lab('A', prep: 0), now), 'Noch kein Termin');
    });

    test('Labortag, Bericht und abgegeben', () {
      expect(labStatusLine(_lab('A', labDate: DateTime(2026, 9, 10)), now), 'Heute Versuch');
      expect(
        labStatusLine(_lab('A', labDate: DateTime(2026, 9, 8), reportDue: DateTime(2026, 9, 12), written: 1), now),
        'Bericht 1/3 · Abgabe in 2 Tagen',
      );
      expect(labStatusLine(_lab('A', labDate: DateTime(2026, 9, 8), finished: true), now), 'Bericht abgegeben');
    });
  });

  group('labHomeHint', () {
    test('offene Vorbereitung kurz vor dem Versuch', () {
      final hint = labHomeHint([_lab('Oszilloskop', labDate: DateTime(2026, 9, 12), answered: 1)], now);
      expect(hint, 'Vorbereitung offen: Oszilloskop · Versuch in 2 Tagen');
    });

    test('nichts, wenn vorbereitet, weit weg, ohne Termin oder abgegeben', () {
      expect(labHomeHint([_lab('A', labDate: DateTime(2026, 9, 12), answered: 2)], now), isNull);
      expect(labHomeHint([_lab('A', labDate: DateTime(2026, 11, 12))], now), isNull);
      expect(labHomeHint([_lab('A')], now), isNull);
      expect(labHomeHint([_lab('A', labDate: DateTime(2026, 9, 12), finished: true)], now), isNull);
      expect(labHomeHint(const [], now), isNull);
    });

    test('offener Bericht kurz vor der Abgabe', () {
      final lab = _lab('Diode', labDate: DateTime(2026, 9, 5), reportDue: DateTime(2026, 9, 13), written: 1);
      expect(labHomeHint([lab], now), 'Bericht offen: Diode · Abgabe in 3 Tagen');
      // Weit weg oder fertig geschrieben: kein Hinweis.
      expect(labHomeHint([_lab('D', labDate: DateTime(2026, 9, 5), reportDue: DateTime(2026, 9, 30))], now), isNull);
      expect(labHomeHint([_lab('D', labDate: DateTime(2026, 9, 5), reportDue: DateTime(2026, 9, 13), written: 3)], now), isNull);
    });

    test('der dringendste Fall gewinnt', () {
      final hint = labHomeHint([
        _lab('Später', labDate: DateTime(2026, 9, 20)),
        _lab('Bald', labDate: DateTime(2026, 9, 11)),
      ], now);
      expect(hint, 'Vorbereitung offen: Bald · Versuch morgen');
    });
  });
}
