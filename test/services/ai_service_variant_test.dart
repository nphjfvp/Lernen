import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/flashcard.dart';
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
  group('AiService.generateHarderVariant', () {
    test('parst die Antwort für den Zieltyp fill_blank', () async {
      final client = MockClient((request) async {
        return _chatResponse(jsonEncode({
          'front': 'Die Hauptstadt von ___ ist ___.',
          'blanks': ['Frankreich', 'Paris'],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final result = await ai.generateHarderVariant(
        questionText: 'Was ist die Hauptstadt von Frankreich?',
        currentAnswer: 'Paris',
        targetType: QuestionType.fillBlank,
      );

      expect(result['front'], 'Die Hauptstadt von ___ ist ___.');
      expect(result['blanks'], ['Frankreich', 'Paris']);
    });

    test('sendet Ursprungsfrage und bekannte Lösung im Prompt', () async {
      late Map<String, dynamic> sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'front': 'F', 'correctText': 'Paris'}));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      await ai.generateHarderVariant(
        questionText: 'Hauptstadt von Frankreich?',
        currentAnswer: 'Paris',
        targetType: QuestionType.freeText,
      );

      final userMessage = (sentBody['messages'] as List).last['content'] as String;
      expect(userMessage.contains('Hauptstadt von Frankreich?'), isTrue);
      expect(userMessage.contains('Paris'), isTrue);
      final systemMessage = (sentBody['messages'] as List).first['content'] as String;
      expect(systemMessage.contains('free_text'), isTrue);
    });

    test('wirft AiServiceException bei kaputtem JSON', () async {
      final client = MockClient((request) async {
        return _chatResponse('Kein JSON.');
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      expect(
        () => ai.generateHarderVariant(
          questionText: 'F?',
          currentAnswer: 'A',
          targetType: QuestionType.singleChoice,
        ),
        throwsA(isA<AiServiceException>()),
      );
    });
  });
}
