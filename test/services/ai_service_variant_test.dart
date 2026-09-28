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

  group('AiService.assignStages', () {
    test('gibt bekannte Ordnernamen mit und liest Stufe und Ordner je Nummer', () async {
      late String sent;
      final client = MockClient((request) async {
        sent = request.body;
        return _chatResponse(jsonEncode({
          'cards': [
            {'n': 1, 'level': 'leicht', 'group': 'Ohmsches  Gesetz'},
            {'n': 2, 'level': 'schwer', 'group': 'Ohmsches Gesetz'},
            {'n': 'x', 'level': 'mittel'},
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);
      final result = await ai.assignStages([
        (n: 1, type: 'Single-Choice', front: 'Was gilt für U?', answer: 'U = R · I'),
        (n: 2, type: 'Freitext', front: 'Leite I her.', answer: 'I = U / R'),
      ], knownGroups: const ['Kirchhoffsche Regeln']);

      expect(sent, contains('Bereits vorhandene Ordner'));
      expect(sent, contains('Kirchhoffsche Regeln'));
      expect(result.length, 2);
      expect(result[1]!.level, 0);
      expect(result[2]!.level, 2);
      // Doppelte Leerzeichen zählen nicht: beide landen im selben Ordner.
      expect(result[1]!.group, result[2]!.group);
    });
  });
}
