import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lab_experiment.dart';

Map<String, dynamic> _structure() => {
      'title': 'Digitalspeicheroszilloskop',
      'prepQuestions': [
        {'number': '1a', 'question': 'Wozu dient der Trigger?'},
        'Was ist die Abtastrate?',
        {'question': '   '},
        42,
      ],
      'parts': [
        {
          'title': 'Grundeinstellungen',
          'goals': ['Signal darstellen'],
          'steps': ['Tastkopf anschließen', '  ', 'AUTOSET drücken'],
          'tables': [
            {
              'title': 'Messwerte',
              'columns': ['Frequenz', 'Amplitude'],
              'rows': [
                ['1 kHz', ''],
                ['', ''],
              ],
            },
          ],
          'evaluationQuestions': [
            {'number': '2.1', 'question': 'Wie groß ist die Periodendauer?'},
            'Skizziere das Signal.',
          ],
        },
        {'title': 'Leer'},
        'kein Objekt',
        {
          'steps': ['Nur ein Schritt'],
        },
      ],
      'hints': ['USB-Stick mitbringen', ''],
    };

LabExperiment _experiment({DateTime? labDate, DateTime? reportDue}) => LabExperiment.fromStructure(
      _structure(),
      moduleId: 'm1',
      now: DateTime(2026, 9, 1),
      id: 'lab1',
      guideMaterialIds: const ['g1'],
      theoryMaterialIds: const ['t1'],
      labDate: labDate,
      reportDue: reportDue,
    );

void main() {
  group('LabExperiment.fromStructure', () {
    test('liest Vorbereitung, Teile, Tabellen und Hinweise; Unbrauchbares fällt weg', () {
      final e = _experiment();
      expect(e.title, 'Digitalspeicheroszilloskop');
      expect(e.prep.map((q) => (q.number, q.text)), [('1a', 'Wozu dient der Trigger?'), ('2', 'Was ist die Abtastrate?'), ('3', '42')]);
      expect(e.parts, hasLength(2));
      final part = e.parts.first;
      expect(part.title, 'Grundeinstellungen');
      expect(part.steps.map((s) => s.text), ['Tastkopf anschließen', 'AUTOSET drücken']);
      expect(part.questions.map((q) => q.number), ['2.1', '1.2']);
      expect(e.parts[1].title, 'Versuchsteil 4');
      expect(e.hints, ['USB-Stick mitbringen']);
      expect(e.guideMaterialIds, ['g1']);
      expect(e.theoryMaterialIds, ['t1']);
    });

    test('der Bericht bekommt Einleitung, je Teil einen Abschnitt und ein Fazit', () {
      final e = _experiment();
      expect(e.report.map((s) => s.title), [
        'Einleitung und Versuchsziel',
        'Grundeinstellungen',
        'Versuchsteil 4',
        'Diskussion und Fazit',
      ]);
      expect(e.report[1].partId, e.parts.first.id);
      expect(e.report[1].hint, contains('Wie groß ist die Periodendauer?'));
      expect(e.report.first.partId, isNull);
    });

    test('Titel: fehlender fällt auf den Ersatz zurück', () {
      final e = LabExperiment.fromStructure(const {}, moduleId: 'm', now: DateTime(2026, 1, 1), fallbackTitle: 'Laborversuch');
      expect(e.title, 'Laborversuch');
      expect(e.prep, isEmpty);
      expect(e.parts, isEmpty);
      expect(e.report, hasLength(2));
    });
  });

  group('LabTable', () {
    test('leere Zellen sind ausfüllbar, Vorgaben bleiben fest', () {
      final table = _experiment().parts.first.tables.single;
      expect(table.columns, ['Frequenz', 'Amplitude']);
      expect(table.editable, [
        [false, true],
        [true, true],
      ]);
      expect(table.editableCount, 3);
      expect(table.filledCount, 0);
      final changed = table.withCell(0, 0, 'x').withCell(0, 1, '2 V').withCell(9, 9, 'y');
      expect(changed.rows[0], ['1 kHz', '2 V']);
      expect(changed.filledCount, 1);
      // Bleibt ausfüllbar, auch wenn schon etwas drinsteht.
      expect(changed.editable[0][1], isTrue);
      expect(changed.asText(), 'Messwerte\nFrequenz | Amplitude\n1 kHz | 2 V\n– | –');
    });

    test('fromMap füllt zu kurze Zeilen auf', () {
      final table = LabTable.fromMap({
        'columns': ['a', 'b', 'c'],
        'rows': [
          ['1'],
        ],
      });
      expect(table.rows.single, ['1', '', '']);
      expect(table.editable.single, [false, true, true]);
    });
  });

  group('Fortschritt und Phase', () {
    test('zählt Antworten, Schritte, Messwerte, Auswertung und Bericht', () {
      var e = _experiment();
      expect((e.prepAnswered, e.prepTotal, e.prepComplete), (0, 3, false));
      expect((e.stepsDone, e.stepsTotal), (0, 3));
      expect((e.cellsFilled, e.cellsTotal), (0, 3));
      expect((e.evaluationAnswered, e.evaluationTotal), (0, 2));
      expect((e.reportWritten, e.reportTotal), (0, 4));

      for (final q in e.prep) {
        e = e.updateQuestion(q.id, (old) => old.copyWith(answer: 'Antwort'));
      }
      e = e.updatePart(e.parts.first.id, (p) => p.copyWith(
            steps: [p.steps.first.copyWith(done: true), p.steps.last],
            tables: [p.tables.single.withCell(1, 1, '3 V')],
            questions: [p.questions.first.copyWith(answer: 'ok'), p.questions.last],
          ));
      e = e.updateSection(e.report.first.id, (s) => s.copyWith(text: 'x' * LabReportSection.writtenThreshold));
      expect(e.prepComplete, isTrue);
      expect((e.stepsDone, e.cellsFilled, e.evaluationAnswered, e.reportWritten), (1, 1, 1, 1));
    });

    test('Phase nach Termin und "abgegeben"', () {
      final now = DateTime(2026, 9, 10, 15);
      expect(_experiment().phase(now), LabPhase.preparation);
      expect(_experiment(labDate: DateTime(2026, 9, 12)).phase(now), LabPhase.preparation);
      expect(_experiment(labDate: DateTime(2026, 9, 10)).phase(now), LabPhase.labDay);
      expect(_experiment(labDate: DateTime(2026, 9, 9)).phase(now), LabPhase.report);
      expect(_experiment(labDate: DateTime(2026, 9, 9)).copyWith(finished: true).phase(now), LabPhase.done);
    });

    test('Kalendertage bis zum Termin – unabhängig von der Uhrzeit', () {
      final e = _experiment(labDate: DateTime(2026, 9, 12), reportDue: DateTime(2026, 9, 20));
      expect(e.daysUntilLab(DateTime(2026, 9, 10, 23, 59)), 2);
      expect(e.daysUntilLab(DateTime(2026, 9, 12, 0, 1)), 0);
      expect(e.daysUntilLab(DateTime(2026, 9, 13)), -1);
      expect(e.daysUntilReport(DateTime(2026, 9, 10)), 10);
      expect(_experiment().daysUntilLab(DateTime(2026, 9, 10)), isNull);
    });

    test('Vorbereitung überfällig: bald Versuch, aber nicht alles beantwortet', () {
      final now = DateTime(2026, 9, 10);
      expect(_experiment(labDate: DateTime(2026, 9, 15)).preparationOverdue(now), isTrue);
      expect(_experiment(labDate: DateTime(2026, 10, 15)).preparationOverdue(now), isFalse);
      expect(_experiment(labDate: DateTime(2026, 9, 9)).preparationOverdue(now), isFalse);
      expect(_experiment().preparationOverdue(now), isFalse);
      var answered = _experiment(labDate: DateTime(2026, 9, 15));
      for (final q in answered.prep) {
        answered = answered.updateQuestion(q.id, (old) => old.copyWith(answer: 'x'));
      }
      expect(answered.preparationOverdue(now), isFalse);
      expect(_experiment(labDate: DateTime(2026, 9, 15)).copyWith(finished: true).preparationOverdue(now), isFalse);
    });
  });

  group('Speichern und Weitergeben', () {
    LabExperiment worked() {
      var e = _experiment(labDate: DateTime(2026, 9, 12), reportDue: DateTime(2026, 9, 20));
      final q = e.prep.first;
      e = e.updateQuestion(
        q.id,
        (old) => old.copyWith(
          answer: 'Der Trigger stabilisiert das Bild.',
          feedback: LabFeedback(
            verdict: 'teilweise',
            summary: 'Fast.',
            missing: const ['Pegel'],
            hints: const ['Kapitel 3'],
            forText: 'Der Trigger stabilisiert das Bild.',
            at: DateTime(2026, 9, 2),
          ),
        ),
      );
      e = e.updatePart(e.parts.first.id, (p) => p.copyWith(
            steps: [p.steps.first.copyWith(done: true), p.steps.last],
            tables: [p.tables.single.withCell(0, 1, '2 V')],
            notes: 'Tastkopf 10:1',
          ));
      return e.updateSection(e.report.first.id, (s) => s.copyWith(text: 'Einleitung ' * 10));
    }

    test('toMap/fromMap verlustfrei', () {
      final e = worked();
      final back = LabExperiment.fromMap(e.toMap());
      expect(back.toMap(), e.toMap());
      expect(back.prep.first.feedback!.verdict, 'teilweise');
      expect(back.prep.first.feedback!.missing, ['Pegel']);
      expect(back.parts.first.tables.single.rows[0], ['1 kHz', '2 V']);
      expect(back.labDate, DateTime(2026, 9, 12));
    });

    test('fromMap verträgt fehlende und kaputte Felder', () {
      final e = LabExperiment.fromMap({'id': 'x', 'prep': ['kaputt'], 'parts': [1], 'labDate': 'kein Datum'});
      expect(e.id, 'x');
      expect(e.prep, isEmpty);
      expect(e.parts, isEmpty);
      expect(e.labDate, isNull);
      expect(e.title, '');
    });

    test('Einschätzung ist veraltet, sobald sich der Text ändert', () {
      final feedback = worked().prep.first.feedback!;
      expect(feedback.isStaleFor('Der Trigger stabilisiert das Bild.'), isFalse);
      expect(feedback.isStaleFor('  Der Trigger stabilisiert das Bild.  '), isFalse);
      expect(feedback.isStaleFor('Etwas anderes'), isTrue);
    });

    test('withoutProgress: Aufgaben und Vorgaben bleiben, alles Eigene ist weg', () {
      final clean = worked().withoutProgress();
      expect(clean.prep.map((q) => q.text), worked().prep.map((q) => q.text));
      expect(clean.prep.every((q) => q.answer.isEmpty && q.feedback == null), isTrue);
      expect(clean.allSteps.every((s) => !s.done), isTrue);
      final table = clean.parts.first.tables.single;
      expect(table.rows[0], ['1 kHz', '']);
      expect(table.editable, worked().parts.first.tables.single.editable);
      expect(clean.parts.first.notes, isEmpty);
      expect(clean.report.every((s) => s.text.isEmpty && s.feedback == null), isTrue);
      expect(clean.labDate, isNull);
      expect(clean.reportDue, isNull);
      expect(clean.hints, ['USB-Stick mitbringen']);
      expect(clean.finished, isFalse);
    });

    test('reassigned: neue Kennungen, Materialien übersetzt, nicht mit-exportierte fallen weg', () {
      final e = worked().reassigned(newId: 'neu', newModuleId: 'm2', materialIds: const {'g1': 'g-neu'});
      expect(e.id, 'neu');
      expect(e.moduleId, 'm2');
      expect(e.guideMaterialIds, ['g-neu']);
      expect(e.theoryMaterialIds, isEmpty);
      expect(e.prep.first.answer, 'Der Trigger stabilisiert das Bild.');
    });
  });
}
