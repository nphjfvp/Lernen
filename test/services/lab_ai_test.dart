import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';

http.Response _chatResponse(String content) => http.Response(
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

void main() {
  late List<Map<String, dynamic>> requests;

  AiService aiReplying(String reply) {
    requests = [];
    final client = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _chatResponse(reply);
    });
    return AiService(apiKey: 'key', model: 'test-model', client: client);
  }

  String userPrompt() => (requests.single['messages'] as List).last['content'] as String;
  String systemPrompt() => (requests.single['messages'] as List).first['content'] as String;
  final at = DateTime(2026, 9, 5, 12);

  group('AiService.structureLabExperiment', () {
    test('schickt beide Unterlagen mit Bezeichnung und liest das JSON', () async {
      final ai = aiReplying('```json\n{"title": "Oszilloskop", "prepQuestions": [{"number": "1", "question": "Was ist ein Trigger?"}]}\n```');
      final json = await ai.structureLabExperiment(sources: [
        (label: 'Versuchsanleitung: Durchfuehrung.pdf', text: 'Schritt 1: Tastkopf anschließen'),
        (label: 'Theorie-Skript: Versuch.pdf', text: 'Vorbereitungsaufgabe 1: Was ist ein Trigger?'),
        (label: 'Leer', text: '   '),
      ]);
      expect(json['title'], 'Oszilloskop');
      expect((json['prepQuestions'] as List).single['question'], 'Was ist ein Trigger?');
      final prompt = userPrompt();
      expect(prompt, contains('=== Versuchsanleitung: Durchfuehrung.pdf ==='));
      expect(prompt, contains('Schritt 1: Tastkopf anschließen'));
      expect(prompt, contains('=== Theorie-Skript: Versuch.pdf ==='));
      expect(prompt, isNot(contains('=== Leer ===')));
      expect(systemPrompt(), allOf(contains('prepQuestions'), contains('evaluationQuestions'), contains('"tables"')));
      expect(requests.single['temperature'], 0.1);
    });

    test('zu langer Text wird gekürzt statt abgelehnt', () async {
      final ai = aiReplying('{}');
      await ai.structureLabExperiment(sources: [(label: 'Lang', text: 'x' * (AiService.labSourceCap + 5000))]);
      expect(userPrompt(), contains('gekürzt'));
      expect(userPrompt().length, lessThan(AiService.labSourceCap + 500));
    });

    test('ohne lesbaren Text kein Aufruf', () async {
      final ai = aiReplying('{}');
      await expectLater(
        ai.structureLabExperiment(sources: [(label: 'Leer', text: ' ')]),
        throwsA(isA<AiServiceException>()),
      );
      expect(requests, isEmpty);
    });

    test('kein JSON: Fehler mit Rohantwort', () async {
      final ai = aiReplying('Das ist leider kein JSON.');
      await expectLater(
        ai.structureLabExperiment(sources: [(label: 'A', text: 'Text')]),
        throwsA(isA<AiServiceException>().having((e) => e.rawResponse, 'rawResponse', contains('kein JSON'))),
      );
    });
  });

  group('AiService.reviewLabAnswer', () {
    test('gibt Einschätzung zurück; Prompt enthält Aufgabe, Antwort, Auszug und Messwerte', () async {
      final ai = aiReplying('{"verdict": "teilweise", "summary": "Guter Ansatz.", "missing": ["Pegel"], "hints": ["Kapitel 3"]}');
      final fb = await ai.reviewLabAnswer(
        experimentTitle: 'Oszilloskop',
        number: '1a',
        question: 'Wozu dient der Trigger?',
        answer: 'Er stabilisiert das Bild.',
        context: '[Skript.pdf, Seite 4]\nDer Trigger startet …',
        measurements: 'Frequenz | Amplitude\n1 kHz | 2 V',
        now: at,
      );
      expect(fb.verdict, 'teilweise');
      expect(fb.summary, 'Guter Ansatz.');
      expect(fb.missing, ['Pegel']);
      expect(fb.hints, ['Kapitel 3']);
      expect(fb.forText, 'Er stabilisiert das Bild.');
      expect(fb.at, at);
      final prompt = userPrompt();
      expect(prompt, contains('Aufgabe 1a: Wozu dient der Trigger?'));
      expect(prompt, contains('Er stabilisiert das Bild.'));
      expect(prompt, contains('[Skript.pdf, Seite 4]'));
      expect(prompt, contains('1 kHz | 2 V'));
      // Keine Musterlösung: steht als Regel im System-Prompt.
      expect(systemPrompt(), contains('KEINE Musterlösung'));
      expect(requests.single['temperature'], 0);
    });

    test('leere Antwort: "leer" ohne KI-Aufruf', () async {
      final ai = aiReplying('{}');
      final fb = await ai.reviewLabAnswer(
        experimentTitle: 'V',
        number: '1',
        question: 'F',
        answer: '   ',
        now: at,
      );
      expect(fb.verdict, 'leer');
      expect(requests, isEmpty);
    });
  });

  group('AiService.reviewReportSection', () {
    test('Prompt enthält Abschnitt, Messwerte, Antworten; Ergebnis mit Bezug auf den Text', () async {
      final ai = aiReplying('{"verdict": "unklar", "summary": "Werte fehlen.", "missing": ["Einheit"], "hints": []}');
      final fb = await ai.reviewReportSection(
        experimentTitle: 'Oszilloskop',
        sectionTitle: 'Grundeinstellungen',
        hint: 'Aufbau und Messergebnisse',
        text: 'Wir haben 2 gemessen.',
        measurements: 'Frequenz | Amplitude\n1 kHz | 2 V',
        answers: '2.1 Periodendauer?\nAntwort: 1 ms',
        now: at,
      );
      expect(fb.verdict, 'unklar');
      expect(fb.missing, ['Einheit']);
      expect(fb.forText, 'Wir haben 2 gemessen.');
      final prompt = userPrompt();
      expect(prompt, contains('Abschnitt: Grundeinstellungen'));
      expect(prompt, contains('Was in den Abschnitt gehört: Aufbau und Messergebnisse'));
      expect(prompt, contains('1 kHz | 2 V'));
      expect(prompt, contains('Antwort: 1 ms'));
      expect(prompt, contains('Wir haben 2 gemessen.'));
      expect(systemPrompt(), contains('NICHT um'));
    });

    test('leerer Text: "leer" ohne KI-Aufruf', () async {
      final ai = aiReplying('{}');
      final fb = await ai.reviewReportSection(
        experimentTitle: 'V',
        sectionTitle: 'S',
        hint: '',
        text: '',
        now: at,
      );
      expect(fb.verdict, 'leer');
      expect(requests, isEmpty);
    });
  });

  group('AiService.parseLabFeedback', () {
    test('Urteile werden vereinheitlicht, Unbekanntes wird "unklar"', () {
      String verdict(Object? v) => AiService.parseLabFeedback({'verdict': v}, forText: 't', at: at).verdict;
      expect(verdict('gut'), 'gut');
      expect(verdict(' Good '), 'gut');
      expect(verdict('PARTIAL'), 'teilweise');
      expect(verdict('teilweise'), 'teilweise');
      expect(verdict('leer'), 'leer');
      expect(verdict('falsch'), 'unklar');
      expect(verdict(null), 'unklar');
    });

    test('bei "gut" entfallen Anmerkungen; sonst gekürzt auf 5 bzw. 3 Einträge, Leeres fällt weg', () {
      final good = AiService.parseLabFeedback({
        'verdict': 'gut',
        'summary': ' Alles da. ',
        'missing': ['x'],
        'hints': ['y'],
      }, forText: 't', at: at);
      expect(good.summary, 'Alles da.');
      expect(good.missing, isEmpty);
      expect(good.hints, isEmpty);

      final partial = AiService.parseLabFeedback({
        'verdict': 'teilweise',
        'missing': ['1', '', '2', '3', '4', '5', '6'],
        'hints': 'Nur ein Text statt einer Liste',
      }, forText: 't', at: at);
      expect(partial.missing, ['1', '2', '3', '4', '5']);
      expect(partial.hints, ['Nur ein Text statt einer Liste']);
    });
  });
}
