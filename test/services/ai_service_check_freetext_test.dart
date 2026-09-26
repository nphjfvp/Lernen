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

  group('AiService.checkFillBlankAnswers', () {
    test('liefert je Lücke das Urteil der KI und schickt Lösung und Eingabe je Lücke', () async {
      String? sent;
      final client = MockClient((request) async {
        sent = request.body;
        return _chatResponse(jsonEncode({
          'correct': [true, false],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final result = await ai.checkFillBlankAnswers(
        text: 'Die ___ liefert ___.',
        solutions: const ['Mitochondrium', 'ATP'],
        answers: const ['Kraftwerk der Zelle', 'Zucker'],
      );

      expect(result, [true, false]);
      final user = (jsonDecode(sent!)['messages'] as List)[1]['content'] as String;
      expect(user, contains('Lücke 1: Lösung "Mitochondrium" – Eingabe "Kraftwerk der Zelle"'));
      expect(user, contains('Lücke 2: Lösung "ATP" – Eingabe "Zucker"'));
    });

    test('parseBlankVerdicts ist tolerant: zu kurze Liste, Strings, Einzelwert', () {
      expect(AiService.parseBlankVerdicts({'correct': [true]}, 2), [true, false]);
      expect(AiService.parseBlankVerdicts({'correct': ['true', 'nein']}, 2), [true, false]);
      expect(AiService.parseBlankVerdicts({'correct': true}, 3), [true, true, true]);
      expect(AiService.parseBlankVerdicts({'correct': 'vielleicht'}, 2), [false, false]);
      expect(AiService.parseBlankVerdicts(const {}, 2), [false, false]);
    });
  });
}
