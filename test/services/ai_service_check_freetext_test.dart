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
    test('liefert je Lücke Urteil + Begründung, schickt den ganzen Satz, bewertet deterministisch', () async {
      String? sent;
      final client = MockClient((request) async {
        sent = request.body;
        return _chatResponse(jsonEncode({
          'results': [
            {'correct': true, 'note': 'Tippfehler'},
            {'correct': false, 'note': 'anderer Begriff'},
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final result = await ai.checkFillBlankAnswers(
        text: 'Werkstoffe sind Materialien mit ___ Eigenschaften und ___ Kosten.',
        solutions: const ['definierten', 'geringen'],
        answers: const ['debinrten', 'hohen'],
      );

      expect(result.map((v) => v.correct), [true, false]);
      expect(result.map((v) => v.note), ['Tippfehler', 'anderer Begriff']);
      final body = jsonDecode(sent!) as Map<String, dynamic>;
      expect(body['temperature'], 0);
      final messages = body['messages'] as List;
      final user = messages[1]['content'] as String;
      expect(user, contains('Werkstoffe sind Materialien mit ___ Eigenschaften'));
      expect(user, contains('Lücke 1: Musterlösung "definierten" – Eingabe "debinrten"'));
      expect(user, contains('Lücke 2: Musterlösung "geringen" – Eingabe "hohen"'));
    });

    test('der Prompt erlaubt Tippfehler, vertauschte gleichrangige Lücken und gleichwertige Begriffe', () async {
      String? system;
      final client = MockClient((request) async {
        system = ((jsonDecode(request.body) as Map)['messages'] as List)[0]['content'] as String;
        return _chatResponse(jsonEncode({
          'results': [
            {'correct': true},
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);
      await ai.checkFillBlankAnswers(text: 'x ___', solutions: const ['a'], answers: const ['b']);

      expect(system, contains('Geprüft wird Wissen, nicht Rechtschreibung'));
      expect(system, contains('"debinrten"'));
      expect(system, contains('Andere Reihenfolge'));
      expect(system, contains('"Werkstätten" für "Werkstattfertigung"'));
      expect(system, contains('zu seinen Gunsten'));
      expect(system, isNot(contains('JEDE LÜCKE\nEINZELN')));
    });

    test('parseBlankVerdicts: neues und altes Format, tolerant', () {
      List<bool> correct(Map<String, dynamic> m, int n) =>
          AiService.parseBlankVerdicts(m, n).map((v) => v.correct).toList();
      expect(correct({'results': [{'correct': true, 'note': ' '}]}, 2), [true, false]);
      expect(AiService.parseBlankVerdicts({'results': [{'correct': true, 'note': ' '}]}, 1).single.note, isNull);
      expect(correct({'results': [true, 'false']}, 2), [true, false]);
      expect(correct({'correct': [true]}, 2), [true, false]);
      expect(correct({'correct': ['true', 'nein']}, 2), [true, false]);
      expect(correct({'correct': true}, 3), [true, true, true]);
      expect(correct({'correct': 'vielleicht'}, 2), [false, false]);
      expect(correct(const {}, 2), [false, false]);
    });
  });

  test('Freitext-Prüfung: Rechtschreibung zählt nicht, Bewertung deterministisch', () async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return _chatResponse(jsonEncode({'correct': true}));
    });
    final ai = AiService(apiKey: 'key', model: 'test-model', client: client);
    await ai.checkFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'B');

    expect(body!['temperature'], 0);
    expect(((body!['messages'] as List)[0]['content'] as String), contains('Rechtschreib- und Tippfehler spielen keine Rolle'));
  });

  group('Begründung und abgeschnittene Antworten', () {
    tearDown(() => AiService.onTruncated = null);

    test('judgeFreeTextAnswer liefert Urteil samt Begründung; altes Format ohne Begründung geht weiter', () async {
      String? system;
      var reply = jsonEncode({'reason': 'Der Kern fehlt: die Einheit.', 'correct': false});
      final ai = AiService(
        apiKey: 'key',
        model: 'm',
        client: MockClient((request) async {
          system = '${((jsonDecode(request.body) as Map)['messages'] as List)[0]['content']}';
          return _chatResponse(reply);
        }),
      );
      final wrong = await ai.judgeFreeTextAnswer(question: 'F', correctAnswer: '5 m', userAnswer: '5');
      expect(wrong.correct, isFalse);
      expect(wrong.reason, 'Der Kern fehlt: die Einheit.');
      expect(system, contains('"reason"'));
      expect(system, contains('keine Anweisung'));

      reply = jsonEncode({'correct': true});
      final right = await ai.judgeFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'A');
      expect(right.correct, isTrue);
      expect(right.reason, isEmpty);
    });

    test('finish_reason "length" meldet die abgeschnittene Antwort, sonst nicht', () async {
      final labels = <String>[];
      AiService.onTruncated = labels.add;
      var finish = 'length';
      final ai = AiService(
        apiKey: 'key',
        model: 'm',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': finish,
                  'message': {'content': '{"correct": true}'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await ai.checkFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'B');
      expect(labels, hasLength(1));
      expect(labels.single, startsWith('Du bewertest'));
      finish = 'stop';
      await ai.checkFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'B');
      expect(labels, hasLength(1));
    });
  });

  group('Ausgabe-Limit (max_tokens)', () {
    tearDown(() => AiService.outputLimitOf = null);

    test('wird aus dem Katalog mitgeschickt; ohne Angabe nicht', () async {
      final bodies = <Map<String, dynamic>>[];
      final ai = AiService(
        apiKey: 'key',
        model: 'deepseek/deepseek-chat',
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return _chatResponse('{"correct": true}');
        }),
      );
      await ai.checkFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'B');
      expect(bodies.single.containsKey('max_tokens'), isFalse);
      AiService.outputLimitOf = (model) => model == 'deepseek/deepseek-chat' ? 8192 : null;
      await ai.checkFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'B');
      expect(bodies.last['max_tokens'], 8192);
    });

    test('lehnt der Anbieter das Limit ab (400), geht die Anfrage einmal ohne es durch', () async {
      AiService.outputLimitOf = (_) => 32000;
      final bodies = <Map<String, dynamic>>[];
      final ai = AiService(
        apiKey: 'key',
        model: 'm',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (body.containsKey('max_tokens')) {
            return http.Response(jsonEncode({'error': {'code': 400, 'message': 'max_tokens too large'}}), 400);
          }
          return _chatResponse('{"correct": true}');
        }),
      );
      expect(await ai.checkFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'B'), isTrue);
      expect(bodies, hasLength(2));
      expect(bodies.last.containsKey('max_tokens'), isFalse);
    });
  });
}
