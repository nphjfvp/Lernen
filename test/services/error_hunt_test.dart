import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/error_hunt.dart';
import 'package:lernen/services/ai_service.dart';

void main() {
  test('Aussagen tolerant lesen: Schreibweisen, Text-Wahrheitswerte, nur bekannte Karten', () {
    final list = ErrorHuntStatement.listFrom(
      {
        'statements': [
          {'card': 'a', 'text': 'kfz hat 12 Nachbarn.', 'true': true, 'explanation': 'Koordinationszahl 12.'},
          {'cardId': 'b', 'statement': 'Härten macht Stahl weicher.', 'wahr': 'falsch'},
          {'id': 'x', 'aussage': 'Unbekannte Karte', 'isTrue': 'ja'},
          {'card': 'a', 'text': '', 'true': true},
          {'card': 'a', 'text': 'Ohne Wahrheitswert'},
        ],
      },
      knownIds: {'a', 'b'},
    );
    expect(list, hasLength(3));
    expect(list[0].isTrue, isTrue);
    expect(list[0].explanation, 'Koordinationszahl 12.');
    expect(list[1].isTrue, isFalse);
    expect(list[1].cardId, 'b');
    expect(list[2].cardId, isNull);
    expect(ErrorHuntStatement.listFrom('kaputt', knownIds: {}), isEmpty);
  });

  test('KI-Aufruf: Karten gehen mit, Anzahl wird begrenzt, leere Antwort ist ein Fehler', () async {
    String? sent;
    AiService ai(String content) => AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((req) async {
        sent = (jsonDecode(req.body)['messages'] as List).last['content'] as String;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final statements = jsonEncode({
      'statements': [
        for (var i = 0; i < 5; i++) {'card': 'a', 'text': 'Aussage $i', 'true': i.isEven},
      ],
    });
    final result = await ai(statements)
        .generateErrorHunt([(id: 'a', question: 'Was ist kfz?', answer: 'kubisch-flächenzentriert')], count: 3);
    expect(result, hasLength(3));
    expect(sent, contains('Anzahl Aussagen: 3'));
    expect(sent, contains('kubisch-flächenzentriert'));
    await expectLater(
      ai('{"statements": []}').generateErrorHunt([(id: 'a', question: 'q', answer: 'a')]),
      throwsA(isA<AiServiceException>()),
    );
  });
}
