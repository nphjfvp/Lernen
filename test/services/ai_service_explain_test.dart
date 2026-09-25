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

  group('AiService.explainAnswer', () {
    test('schickt Frage, Lösung und die falsche Antwort mit und liefert den Text', () async {
      final ai = aiReplying('  Weil Paris die Hauptstadt ist.  ');
      final text = await ai.explainAnswer(
        question: 'Hauptstadt von Frankreich?',
        correctAnswer: 'Paris',
        userAnswer: 'Lyon',
        wasCorrect: false,
      );
      expect(text, 'Weil Paris die Hauptstadt ist.');
      expect(userPrompt(), contains('Hauptstadt von Frankreich?'));
      expect(userPrompt(), contains('Richtige Lösung: Paris'));
      expect(userPrompt(), contains('Antwort des Lernenden: Lyon'));
      expect(userPrompt(), contains('falsch'));
    });

    test('mit vorheriger Erklärung: einfachere Neufassung', () async {
      final ai = aiReplying('Einfach gesagt: …');
      await ai.explainAnswer(
        question: 'F',
        correctAnswer: 'A',
        previousExplanation: 'Komplizierte Erklärung',
      );
      expect(userPrompt(), contains('Komplizierte Erklärung'));
      expect(systemPrompt(), contains('VIEL'));
    });
  });

  group('AiService.generateHint', () {
    test('gibt die Lösung nur als Hintergrund mit und liefert den Tipp', () async {
      final ai = aiReplying('Denk an die Seine.');
      final hint = await ai.generateHint(question: 'Hauptstadt von Frankreich?', correctAnswer: 'Paris');
      expect(hint, 'Denk an die Seine.');
      expect(userPrompt(), contains('NICHT verraten'));
      expect(systemPrompt(), contains('ohne die Lösung zu'));
    });
  });
}
