import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';

http.Response _chatResponse(String content, {int statusCode = 200}) {
  // http.Response encodiert den Body nach Content-Type: ohne expliziten
  // 'application/json'-Header würde bei Umlauten im Testinhalt auf
  // Latin-1 zurückgefallen, was ai_service.dart (erwartet UTF-8) zerlegt.
  return http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'content': content},
        },
      ],
    }),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  group('AiService – JSON-Extraktion aus KI-Antworten', () {
    test('parst sauberes JSON direkt', () async {
      final client = MockClient((request) async {
        return _chatResponse(jsonEncode({
          'title': 'Regression',
          'overview': 'Kurze Übersicht.',
          'key_points': ['Punkt 1', 'Punkt 2'],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final result = await ai.generateSummary('Foliensatz-Text');

      expect(result['title'], 'Regression');
      expect(result['key_points'], ['Punkt 1', 'Punkt 2']);
    });

    test('entfernt Markdown-Codefences ```json ... ```', () async {
      final client = MockClient((request) async {
        return _chatResponse('Hier ist die Zusammenfassung:\n```json\n'
            '${jsonEncode({
                  'title': 'Titel',
                  'overview': 'Text',
                  'key_points': [],
                })}\n```');
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final result = await ai.generateSummary('Text');

      expect(result['title'], 'Titel');
    });

    test('extrahiert das äußerste JSON-Objekt trotz Text davor/danach', () async {
      final client = MockClient((request) async {
        return _chatResponse('Klar, hier ist es: '
            '${jsonEncode({
                  'concepts': [
                    {'title': 'Konzept A', 'explanation': 'Erklärung'},
                  ],
                  'flashcards': [
                    {'front': 'F', 'back': 'B'},
                  ],
                })} Ich hoffe das hilft!');
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final result = await ai.generateConceptsAndFlashcards(
        slidesText: 'Folien',
        exercisesText: 'Übungen',
      );

      expect((result['concepts'] as List).length, 1);
      expect((result['flashcards'] as List).length, 1);
    });

    test('wirft AiServiceException mit Rohantwort bei kaputtem JSON', () async {
      final client = MockClient((request) async {
        return _chatResponse('Das ist leider gar kein JSON.');
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      expect(
        () => ai.generateSummary('Text'),
        throwsA(isA<AiServiceException>().having(
          (e) => e.rawResponse,
          'rawResponse',
          isNotNull,
        )),
      );
    });

    test('wirft AiServiceException bei HTTP-Fehlerstatus', () async {
      final client = MockClient((request) async {
        return http.Response('Server-Fehler', 500);
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      expect(() => ai.generateSummary('Text'), throwsA(isA<AiServiceException>()));
    });

    test('ruft OpenRouter ohne API-Key gar nicht erst auf', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return _chatResponse('{}');
      });
      final ai = AiService(apiKey: '', model: 'test-model', client: client);

      await expectLater(() => ai.generateSummary('Text'), throwsA(isA<AiServiceException>()));
      expect(called, isFalse);
    });
  });
}
