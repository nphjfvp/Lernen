import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/services/lab_export_service.dart';
import 'package:lernen/services/pdf_service.dart';

LabExperiment _experiment({String answer = 'Der Trigger stabilisiert das Bild.'}) {
  var e = LabExperiment.fromStructure(
    {
      'title': 'Digitalspeicheroszilloskop',
      'prepQuestions': [
        {'number': '1a', 'question': 'Wozu dient der Trigger?'},
        {'number': '1b', 'question': 'Was ist die Abtastrate?'},
      ],
      'parts': [
        {
          'title': 'Grundeinstellungen',
          'tables': [
            {
              'title': 'Messwerte',
              'columns': ['Frequenz', 'Amplitude'],
              'rows': [
                ['1 kHz', ''],
              ],
            },
          ],
          'evaluationQuestions': ['Periodendauer?'],
        },
      ],
    },
    moduleId: 'm1',
    now: DateTime(2026, 9, 1),
    id: 'lab1',
    labDate: DateTime(2026, 9, 12),
    reportDue: DateTime(2026, 9, 20),
  );
  e = e.updateQuestion(e.prep.first.id, (q) => q.copyWith(
        answer: answer,
        feedback: LabFeedback(verdict: 'gut', summary: 'GEHEIME EINSCHÄTZUNG', forText: answer, at: DateTime(2026, 9, 2)),
      ));
  e = e.updatePart(e.parts.first.id, (p) => p.copyWith(
        tables: [p.tables.single.withCell(0, 1, '2 V')],
        notes: 'Tastkopf 10:1',
      ));
  return e.updateSection(e.report.first.id, (s) => s.copyWith(text: 'Der Versuch zeigt die Grundlagen der Messtechnik.'));
}

void main() {
  group('Text', () {
    test('Vorbereitung: Aufgaben mit eigenen Antworten, offene Aufgaben markiert, keine KI-Einschätzung', () {
      final text = LabExportService.preparationText(_experiment(), moduleName: 'Elektrotechnik');
      expect(text, startsWith('# Vorbereitung: Digitalspeicheroszilloskop'));
      expect(text, contains('Elektrotechnik · Versuch am 12.09.2026 · Abgabe bis 20.09.2026'));
      expect(text, contains('### 1a  Wozu dient der Trigger?\nDer Trigger stabilisiert das Bild.'));
      expect(text, contains('### 1b  Was ist die Abtastrate?\n(noch nicht beantwortet)'));
      expect(text, isNot(contains('GEHEIME EINSCHÄTZUNG')));
    });

    test('Bericht: Abschnitte, "noch nicht geschrieben", Messwerte im Anhang', () {
      final text = LabExportService.reportText(_experiment());
      expect(text, startsWith('# Bericht: Digitalspeicheroszilloskop'));
      expect(text, contains('## Einleitung und Versuchsziel\nDer Versuch zeigt die Grundlagen der Messtechnik.'));
      expect(text, contains('## Diskussion und Fazit\n(noch nicht geschrieben)'));
      expect(text, contains('## Anhang: Messwerte'));
      expect(text, contains('Frequenz | Amplitude\n1 kHz | 2 V'));
      expect(text, contains('Notizen: Tastkopf 10:1'));
    });

    test('ohne Tabellen kein Anhang', () {
      final e = LabExperiment.fromStructure(const {'title': 'X'}, moduleId: 'm', now: DateTime(2026, 1, 1));
      expect(LabExportService.reportText(e), isNot(contains('Anhang')));
    });
  });

  group('PDF', () {
    List<String> pagesOf(Uint8List bytes) => PdfService().extractPageTexts(bytes);

    test('ist eine lesbare PDF mit Titel, Aufgabe, Antwort und Messwerten', () {
      final prep = LabExportService.preparationPdf(_experiment(), moduleName: 'Elektrotechnik');
      expect(utf8.decode(prep.sublist(0, 5)), '%PDF-');
      final prepText = pagesOf(prep).join('\n');
      expect(prepText, contains('Vorbereitung: Digitalspeicheroszilloskop'));
      expect(prepText, contains('Wozu dient der Trigger?'));
      expect(prepText, contains('Der Trigger stabilisiert das Bild.'));

      final report = LabExportService.reportPdf(_experiment());
      final reportText = pagesOf(report).join('\n');
      expect(reportText, contains('Bericht: Digitalspeicheroszilloskop'));
      expect(reportText, contains('Anhang: Messwerte'));
      expect(reportText, contains('2 V'));
    });

    test('lange Antworten laufen auf weitere Seiten', () {
      final long = List.generate(150, (i) => 'Zeile $i: eine ausführliche Erklärung zur Triggerung.').join('\n');
      final pages = pagesOf(LabExportService.preparationPdf(_experiment(answer: long)));
      expect(pages.length, greaterThan(1));
      expect(pages.join('\n'), contains('Zeile 149'));
    });

    test('Zeichen außerhalb von Latin-1 werden ersetzt statt zu Kästchen', () {
      expect(LabExportService.latin1Safe('R = 50 Ω, μs – „Test“ → ok … ≈ 5'), 'R = 50 Ohm, µs - "Test" -> ok ... ~ 5');
      expect(LabExportService.latin1Safe('Größe ä ö ü ß ° ± ² µ'), 'Größe ä ö ü ß ° ± ² µ');
      expect(LabExportService.latin1Safe('日本'), '??');
      final pdf = LabExportService.preparationPdf(_experiment(answer: 'Widerstand 50 Ω und Zeit 5 μs'));
      expect(pagesOf(pdf).join('\n'), contains('Widerstand 50 Ohm'));
    });
  });

  test('Dateiname ohne Sonderzeichen', () {
    expect(LabExportService.fileName('Oszilloskop: Teil 1/2?', 'Bericht', 'pdf'), 'Oszilloskop Teil 12 – Bericht.pdf');
    expect(LabExportService.fileName('///', 'Vorbereitung', 'txt'), 'Laborversuch – Vorbereitung.txt');
  });
}
