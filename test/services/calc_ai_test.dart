import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/calc_plan.dart';

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

const _plan = r'''
{"title": "Ohmsches Gesetz",
 "given": [{"symbol": "U", "name": "Spannung", "raw": "12,3 V", "values": [12.3], "unit": "V"},
           {"symbol": "I", "name": "Strom", "raw": "450 mA", "values": [0.45], "unit": "A"}],
 "steps": [{"symbol": "R", "name": "Widerstand", "latex": "$R = \frac{U}{I}$", "expression": "U / I", "unit": "Ω",
            "explanation": "Ohmsches Gesetz"}],
 "result": ["R"], "assumptions": ["ideale Messgeräte"], "notes": [], "missing": []}
''';

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

  dynamic userContent() => (requests.single['messages'] as List).last['content'];
  String systemPrompt() => (requests.single['messages'] as List).first['content'] as String;

  group('AiService.planCalculation', () {
    test('Text und Werte gehen als Text, der Plan wird gelesen (auch mit einfachen Backslashes in LaTeX)', () async {
      final ai = aiReplying('```json\n$_plan\n```');
      final plan = await ai.planCalculation(
        task: 'Berechne den Widerstand.',
        values: 'U = 12,3 V\nI = 450 mA',
        context: 'Messwerte des Versuchs …',
      );
      expect(plan.title, 'Ohmsches Gesetz');
      expect(plan.given.map((g) => g.symbol), ['U', 'I']);
      expect(plan.steps.single.latex, r'R = \frac{U}{I}');
      final results = plan.evaluate();
      expect(results.single.values!.single, closeTo(27.3333, 1e-3));

      expect(userContent(), isA<String>());
      final prompt = userContent() as String;
      expect(prompt, contains('Aufgabe / Wunsch:\nBerechne den Widerstand.'));
      expect(prompt, contains('Werte (vom Nutzer eingegeben):\nU = 12,3 V'));
      expect(prompt, contains('Weitere Angaben zum Versuch:\nMesswerte des Versuchs'));
      expect(requests.single['temperature'], 0);
    });

    test('Das Prompt sagt, dass die App rechnet, und nennt die erlaubten Funktionen', () async {
      final ai = aiReplying(_plan);
      await ai.planCalculation(task: 'x');
      final system = systemPrompt();
      expect(system, contains('die\nApp rechnet selbst'));
      expect(system, contains('NIE Ergebnisse'));
      expect(system, contains('sqrt'));
      expect(system, contains('slope'));
      expect(system, contains('"uncertain": true'));
      expect(system, isNot(contains('{{FUNCTIONS}}')));
    });

    test('Bilder gehen als Bild-Teile mit passendem Typ (PNG, JPEG)', () async {
      final ai = aiReplying(_plan);
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2]);
      await ai.planCalculation(task: 'Lies die Tabelle ab', images: [png, jpeg]);
      final parts = userContent() as List;
      expect(parts.first['type'], 'text');
      expect(parts.first['text'], contains('Dem Text folgen 2 Bilder.'));
      final urls = [
        for (final p in parts)
          if (p['type'] == 'image_url') (p['image_url'] as Map)['url'] as String,
      ];
      expect(urls, hasLength(2));
      expect(urls[0], startsWith('data:image/png;base64,'));
      expect(urls[1], startsWith('data:image/jpeg;base64,'));
      expect(parts.where((p) => p['type'] == 'text' && '${p['text']}'.startsWith('Bild 2 von 2')), hasLength(1));
    });

    test('Überarbeitung schickt den bisherigen Plan und den Wunsch mit', () async {
      final ai = aiReplying(_plan);
      final previous = CalcPlan.fromJson(jsonDecode(_plan.replaceAll(r'\frac', r'\\frac')) as Map<String, dynamic>);
      await ai.planCalculation(previous: previous, instruction: 'Rechne zusätzlich die Leistung.');
      final prompt = userContent() as String;
      expect(prompt, contains('Bisheriger Plan (JSON):'));
      expect(prompt, contains('"symbol":"R"'));
      expect(prompt, contains('Wunsch des Nutzers zur Überarbeitung:\nRechne zusätzlich die Leistung.'));
    });

    test('ohne Aufgabe, Werte und Bild gibt es einen Hinweis statt einer Anfrage', () async {
      final ai = aiReplying(_plan);
      await expectLater(ai.planCalculation(), throwsA(isA<AiServiceException>()));
      expect(requests, isEmpty);
    });

    test('unbrauchbare Antwort: verständlicher Fehler mit Rohantwort', () async {
      final ai = aiReplying('{"title": "nichts", "given": [], "steps": []}');
      await expectLater(
        ai.planCalculation(task: 'x'),
        throwsA(isA<AiServiceException>().having((e) => e.rawResponse, 'raw', contains('nichts'))),
      );
    });

    test('nur "fehlt" ist eine gültige Antwort (der Nutzer erfährt, was fehlt)', () async {
      final ai = aiReplying('{"title": "t", "given": [], "steps": [], "missing": ["Die Länge fehlt"]}');
      final plan = await ai.planCalculation(task: 'x');
      expect(plan.missing, ['Die Länge fehlt']);
    });
  });
}
