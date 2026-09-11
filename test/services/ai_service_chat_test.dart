import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';

http.Response _chatResponse(String content) {
  return http.Response(
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
}

void main() {
  group('AiService.answerQuestion', () {
    test('gibt die Modellantwort als reinen Text zurück (kein JSON-Parsing)', () async {
      final client = MockClient((request) async {
        return _chatResponse('Das erklärt sich so, weil ...');
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final answer = await ai.answerQuestion(
        question: 'Warum ist das so?',
        materialsContext: '--- [Behandelt] folie1.pdf (Folien) ---\nInhalt',
      );

      expect(answer, 'Das erklärt sich so, weil ...');
    });

    test('sendet Frage, Material-Kontext und Verlauf im Prompt an das Modell', () async {
      late Map<String, dynamic> sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse('Antwort');
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      await ai.answerQuestion(
        question: 'Wie hängt das mit letzter Woche zusammen?',
        materialsContext: '--- [Behandelt] woche1.pdf (Folien) ---\nInhalt Woche 1',
        history: const [(isUser: true, content: 'Was war Thema 1?')],
      );

      final userMessage = (sentBody['messages'] as List).last['content'] as String;
      expect(userMessage.contains('woche1.pdf'), isTrue);
      expect(userMessage.contains('Was war Thema 1?'), isTrue);
      expect(userMessage.contains('Wie hängt das mit letzter Woche zusammen?'), isTrue);
    });

    test('wirft AiServiceException ohne API-Key, ohne die KI aufzurufen', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return _chatResponse('Antwort');
      });
      final ai = AiService(apiKey: '', model: 'test-model', client: client);

      await expectLater(
        () => ai.answerQuestion(question: 'Frage?', materialsContext: 'Kontext'),
        throwsA(isA<AiServiceException>()),
      );
      expect(called, isFalse);
    });
  });
}
