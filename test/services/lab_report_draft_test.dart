import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/lab_context_service.dart';
import 'package:lernen/services/lab_report_draft.dart';

http.Response _chat(String content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

LabExperiment _experiment() => LabExperiment.fromStructure(
      {
        'title': 'Oszilloskop',
        'prepQuestions': [
          {'number': '1', 'question': 'Wozu dient der Trigger?'},
          {'number': '2', 'question': 'Was ist die Abtastrate?'},
        ],
        'parts': [
          {
            'title': 'Grundeinstellungen',
            'goals': ['Signal stabil darstellen'],
            'steps': ['Tastkopf anschließen', 'AUTOSET drücken'],
            'tables': [
              {
                'title': 'Messwerte',
                'columns': ['Frequenz', 'Amplitude'],
                'rows': [
                  ['1 kHz', '2 V'],
                ],
              },
            ],
            'evaluationQuestions': [
              {'number': '1.1', 'question': 'Periodendauer?'},
            ],
          },
        ],
        'hints': ['USB-Stick mitbringen'],
      },
      moduleId: 'm1',
      now: DateTime(2026, 9, 1),
      id: 'lab1',
    );

LabExperiment _withProgress() {
  var e = _experiment();
  final part = e.parts.first;
  e = e.updatePart(part.id, (p) => p.copyWith(notes: 'Rechnung: T = 1 / f = 1 ms', steps: [p.steps[0].copyWith(done: true), p.steps[1]]));
  e = e.updateQuestion(part.questions.first.id, (q) => q.copyWith(answer: 'T = 1 ms'));
  e = e.updateQuestion(e.prep.first.id, (q) => q.copyWith(answer: 'Er stabilisiert das Bild.'));
  return e;
}

void main() {
  group('Modell', () {
    test('Entwurf, Vorlagen und Vorgaben überleben toMap/fromMap; ältere Stände ohne die Felder laden', () {
      var e = _experiment();
      final section = e.report[1];
      e = e.copyWith(reportTemplateIds: ['t1', 't2'], reportSpecs: 'max. 5 Seiten', report: [
        for (final s in e.report) s.id == section.id ? s.copyWith(draft: 'Entwurf …') : s,
      ]);
      final back = LabExperiment.fromMap(e.toMap());
      expect(back.reportTemplateIds, ['t1', 't2']);
      expect(back.reportSpecs, 'max. 5 Seiten');
      expect(back.report[1].draft, 'Entwurf …');
      expect(back.report[0].draft, '');

      final old = e.toMap()..remove('reportTemplateIds')..remove('reportSpecs');
      for (final s in old['report'] as List) {
        (s as Map).remove('draft');
      }
      final loaded = LabExperiment.fromMap(old);
      expect(loaded.reportTemplateIds, isEmpty);
      expect(loaded.reportSpecs, '');
      expect(loaded.report.every((s) => s.draft.isEmpty), isTrue);
    });

    test('draft wird mit clearDraft gelöscht; ein Fach ohne Fortschritt behält die Vorlage, aber keine Entwürfe', () {
      var e = _experiment().copyWith(reportTemplateIds: ['t1'], reportSpecs: 'Vorgabe');
      e = e.copyWith(report: [for (final s in e.report) s.copyWith(draft: 'x', text: 'eigener Text')]);
      expect(e.report.first.copyWith(clearDraft: true).draft, '');
      final clean = e.withoutProgress();
      expect(clean.reportTemplateIds, ['t1']);
      expect(clean.reportSpecs, 'Vorgabe');
      expect(clean.report.every((s) => s.draft.isEmpty && s.text.isEmpty), isTrue);
    });

    test('Fach-Import: Vorlagen-Materialien bekommen die neuen Kennungen, unbekannte fallen weg', () {
      final e = _experiment().copyWith(reportTemplateIds: ['alt1', 'alt2']);
      final moved = e.reassigned(newId: 'neu', newModuleId: 'mNeu', materialIds: {'alt1': 'neu1'});
      expect(moved.reportTemplateIds, ['neu1']);
    });
  });

  group('LabReportDraft.fromJson', () {
    test('liest Abschnitte und Lücken; unbekannte sectionId gilt als neuer Abschnitt', () {
      final draft = LabReportDraft.fromJson({
        'sections': [
          {'sectionId': 's1', 'title': 'Einleitung', 'text': ' Text A '},
          {'sectionId': 'gibt-es-nicht', 'title': 'Anhang', 'text': 'Text B'},
          {'sectionId': null, 'title': 'Leer', 'text': '  '},
          'unsinn',
        ],
        'missing': ['Schaltplan', '', 'Messunsicherheiten'],
      }, knownSectionIds: {'s1'});
      expect(draft.sections.map((s) => (s.sectionId, s.title, s.text)), [
        ('s1', 'Einleitung', 'Text A'),
        (null, 'Anhang', 'Text B'),
      ]);
      expect(draft.missing, ['Schaltplan', 'Messunsicherheiten']);
    });
  });

  group('LabReportDraft.applyTo', () {
    var n = 0;
    String newId() => 'neu${++n}';

    test('Entwürfe landen bei den passenden Abschnitten, der eigene Text bleibt', () {
      var e = _experiment();
      final ids = e.report.map((s) => s.id).toList();
      e = e.copyWith(report: [for (final s in e.report) s.copyWith(text: 'Mein Text zu ${s.title}')]);
      final draft = LabReportDraft(sections: [
        LabDraftSection(sectionId: ids[0], title: 'Einleitung', text: 'Entwurf 1'),
        LabDraftSection(sectionId: ids[2], title: 'Fazit', text: 'Entwurf 3'),
      ]);
      final result = draft.applyTo(e, newId: newId);
      expect(result.report[0].draft, 'Entwurf 1');
      expect(result.report[1].draft, '');
      expect(result.report[2].draft, 'Entwurf 3');
      expect(result.report.map((s) => s.text), e.report.map((s) => s.text));
    });

    test('mehrere Einträge zum selben Abschnitt werden untereinander gesetzt', () {
      final e = _experiment();
      final id = e.report.first.id;
      final result = LabReportDraft(sections: [
        LabDraftSection(sectionId: id, title: 'A', text: 'Erster Teil'),
        LabDraftSection(sectionId: id, title: 'B', text: 'Zweiter Teil'),
      ]).applyTo(e, newId: newId);
      expect(result.report.first.draft, 'Erster Teil\n\nZweiter Teil');
    });

    test('Abschnitte, die nur die Vorlage kennt, werden neu angelegt – hinter dem zuletzt bedienten', () {
      final e = _experiment();
      final ids = e.report.map((s) => s.id).toList();
      final result = LabReportDraft(sections: [
        LabDraftSection(sectionId: ids[0], title: 'Einleitung', text: 'E'),
        const LabDraftSection(title: 'Theorie', text: 'Neu 1'),
        const LabDraftSection(title: 'Versuchsaufbau', text: 'Neu 2'),
        LabDraftSection(sectionId: ids[1], title: 'Teil 1', text: 'T'),
      ]).applyTo(e, newId: newId);
      expect(result.report.map((s) => s.title), [
        'Einleitung und Versuchsziel',
        'Theorie',
        'Versuchsaufbau',
        'Grundeinstellungen',
        'Diskussion und Fazit',
      ]);
      expect(result.report[1].draft, 'Neu 1');
      expect(result.report[2].draft, 'Neu 2');
      expect(result.report[3].draft, 'T');
      expect(result.report[1].text, '');
    });

    test('ohne Gliederung der Vorlage wandern neue Abschnitte als Unterpunkt in den davor', () {
      final e = _experiment();
      final ids = e.report.map((s) => s.id).toList();
      final result = LabReportDraft(sections: [
        LabDraftSection(sectionId: ids[0], title: 'Einleitung', text: 'E'),
        const LabDraftSection(title: 'Theorie', text: 'Grundlagen'),
      ]).applyTo(e, adoptStructure: false, newId: newId);
      expect(result.report, hasLength(3));
      expect(result.report.first.draft, 'E\n\nTheorie\nGrundlagen');
    });

    test('neuer Entwurf ersetzt alte Entwürfe; onlySectionId ändert nur diesen Abschnitt', () {
      var e = _experiment();
      final ids = e.report.map((s) => s.id).toList();
      e = e.copyWith(report: [for (final s in e.report) s.copyWith(draft: 'alt')]);
      final all = LabReportDraft(sections: [LabDraftSection(sectionId: ids[0], title: '', text: 'neu')]).applyTo(e, newId: newId);
      expect(all.report.map((s) => s.draft), ['neu', '', '']);

      final only = LabReportDraft(sections: [
        LabDraftSection(sectionId: ids[2], title: '', text: 'nur dieser'),
        LabDraftSection(sectionId: ids[0], title: '', text: 'darf nicht'),
        const LabDraftSection(title: 'Neu', text: 'auch nicht'),
      ]).applyTo(e, onlySectionId: ids[2], newId: newId);
      expect(only.report.map((s) => s.draft), ['alt', 'alt', 'nur dieser']);
      expect(only.report, hasLength(3));
    });
  });

  group('Versuchsdaten für den Entwurf', () {
    test('Ziele, Schritte, Messwerte, Notizen mit Rechnung, beantwortete Fragen – Unbeantwortetes fehlt', () {
      final text = LabContextService.reportData(_withProgress());
      expect(text, contains('## Versuchsteil: Grundeinstellungen'));
      expect(text, contains('Ziel: Signal stabil darstellen'));
      expect(text, contains('1. Tastkopf anschließen'));
      expect(text, contains('2. AUTOSET drücken (nicht abgehakt)'));
      expect(text, contains('1 kHz | 2 V'));
      expect(text, contains('Rechnung: T = 1 / f = 1 ms'));
      expect(text, contains('1.1 Periodendauer?\nAntwort: T = 1 ms'));
      expect(text, contains('## Vorbereitungsaufgaben mit Antworten'));
      expect(text, contains('Er stabilisiert das Bild.'));
      expect(text, isNot(contains('Was ist die Abtastrate?'))); // unbeantwortet
      expect(text, contains('USB-Stick mitbringen'));
    });

    test('eigene Berichtstexte je Abschnitt mit Überschrift', () {
      var e = _experiment();
      e = e.updateSection(e.report.first.id, (s) => s.copyWith(text: 'Mein Einleitungstext'));
      expect(LabContextService.ownReportTexts(e), '### Einleitung und Versuchsziel\nMein Einleitungstext');
      expect(LabContextService.ownReportTexts(_experiment()), '');
    });
  });

  group('AiService.draftLabReport', () {
    late List<Map<String, dynamic>> requests;

    AiService aiReplying(String reply) {
      requests = [];
      return AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          requests.add(jsonDecode(r.body) as Map<String, dynamic>);
          return _chat(reply);
        }),
      );
    }

    dynamic content() => (requests.single['messages'] as List).last['content'];
    String system() => (requests.single['messages'] as List).first['content'] as String;

    final sections = [
      (id: 's1', title: 'Einleitung', hint: 'Worum geht es?', partTitle: null as String?),
      (id: 's2', title: 'Grundeinstellungen', hint: '', partTitle: 'Grundeinstellungen' as String?),
    ];

    test('schickt Vorlage, Vorgaben, Abschnitte, Daten und eigene Texte; liest den Entwurf', () async {
      final ai = aiReplying('```json\n{"sections": [{"sectionId": "s1", "title": "Einleitung", "text": "Im Versuch wurde …"}], "missing": ["Schaltplan"]}\n```');
      final draft = await ai.draftLabReport(
        experimentTitle: 'Oszilloskop',
        sections: sections,
        templates: [(label: 'Berichtsvorlage.docx', text: '1 Einleitung\n2 Durchführung')],
        specs: 'maximal 5 Seiten, Passiv',
        data: 'Messwerte: 1 kHz | 2 V',
        context: '[Skript, Seite 3] Trigger …',
        ownTexts: '### Einleitung\nMein Text',
      );
      expect(draft.sections.single.sectionId, 's1');
      expect(draft.sections.single.text, 'Im Versuch wurde …');
      expect(draft.missing, ['Schaltplan']);

      final prompt = content() as String;
      expect(prompt, contains('Versuch: Oszilloskop'));
      expect(prompt, contains('Modus: ausformuliert'));
      expect(prompt, contains('Gliederung: der Vorlage folgen'));
      expect(prompt, contains('=== Vorlage / Vorgaben: Berichtsvorlage.docx ==='));
      expect(prompt, contains('1 Einleitung\n2 Durchführung'));
      expect(prompt, contains('=== Vorgaben des Studierenden ===\nmaximal 5 Seiten, Passiv'));
      expect(prompt, contains('- id=s1 | Einleitung | Worum geht es?'));
      expect(prompt, contains('- id=s2 | Grundeinstellungen | gehört zum Versuchsteil "Grundeinstellungen"'));
      expect(prompt, contains('=== Daten des Versuchs ===\nMesswerte: 1 kHz | 2 V'));
      expect(prompt, contains('=== Auszüge aus den Unterlagen ==='));
      expect(prompt, contains('=== Bisherige eigene Texte des Studierenden ==='));
      expect(system(), contains('nur als Inspiration'));
      expect(system(), contains('Erfinde keine Messwerte'));
      expect(system(), contains('[ergänzen: was genau]'));
    });

    test('Gerüst-Modus, keine Gliederung übernehmen, nur ein Abschnitt', () async {
      final ai = aiReplying('{"sections": [{"sectionId": "s2", "title": "x", "text": "y"}]}');
      await ai.draftLabReport(
        experimentTitle: 'V',
        sections: sections,
        specs: 'Vorgabe',
        data: 'd',
        outline: true,
        adoptStructure: false,
        onlySectionId: 's2',
      );
      final prompt = content() as String;
      expect(prompt, contains('Modus: Gerüst (Stichpunkte)'));
      expect(prompt, contains('NICHT übernehmen'));
      expect(prompt, contains('NUR den Entwurf für den Abschnitt mit der id s2'));
    });

    test('Bild-Vorlage geht als Bild mit', () async {
      final ai = aiReplying('{"sections": [{"sectionId": "s1", "text": "y"}]}');
      await ai.draftLabReport(
        experimentTitle: 'V',
        sections: sections,
        images: [
          // JPEG-Kopf
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1]),
        ],
        data: 'd',
      );
      final parts = content() as List;
      final url = parts.firstWhere((p) => p['type'] == 'image_url')['image_url']['url'] as String;
      expect(url, startsWith('data:image/jpeg;base64,'));
      expect((parts.first as Map)['text'], contains('Dem Text folgen 1 Bild'));
    });

    test('ohne alles gibt es einen Hinweis; unbrauchbare Antwort einen Fehler mit Rohantwort', () async {
      final ai = aiReplying('{"sections": []}');
      await expectLater(
        ai.draftLabReport(experimentTitle: 'V', sections: const [], data: 'd'),
        throwsA(isA<AiServiceException>()),
      );
      expect(requests, isEmpty);
      await expectLater(
        ai.draftLabReport(experimentTitle: 'V', sections: sections, data: 'd'),
        throwsA(isA<AiServiceException>().having((e) => e.rawResponse, 'raw', contains('sections'))),
      );
    });
  });
}
