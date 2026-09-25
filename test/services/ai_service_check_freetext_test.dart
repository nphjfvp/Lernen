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
  group('AiService.checkFreeTextAnswer', () {
    test('liefert true, wenn die KI die Antwort als richtig einstuft', () async {
      final client = MockClient((request) async => _chatResponse(jsonEncode({'correct': true})));
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final result = await ai.checkFreeTextAnswer(
        question: 'Was ist die Hauptstadt von Frankreich?',
        correctAnswer: 'Paris',
        userAnswer: 'Das ist die Stadt Paris, glaube ich.',
      );

      expect(result, isTrue);
    });

    test('liefert false, wenn die KI die Antwort als falsch einstuft', () async {
      final client = MockClient((request) async => _chatResponse(jsonEncode({'correct': false})));
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final result = await ai.checkFreeTextAnswer(
        question: 'Was ist die Hauptstadt von Frankreich?',
        correctAnswer: 'Paris',
        userAnswer: 'Berlin',
      );

      expect(result, isFalse);
    });

    test('wirft AiServiceException bei kaputtem JSON, statt still false zurückzugeben', () async {
      final client = MockClient((request) async => _chatResponse('kein JSON'));
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      expect(
        () => ai.checkFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'B'),
        throwsA(isA<AiServiceException>()),
      );
    });
  });

  test('ein Netzwerkfehler kommt als AiServiceException an, nicht als roher ClientException', () async {
    final client = MockClient((request) async => throw http.ClientException('offline'));
    final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

    expect(
      () => ai.checkFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'B'),
      throwsA(isA<AiServiceException>()),
    );
  });
}
