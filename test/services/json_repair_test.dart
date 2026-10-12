import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/json_repair.dart';

http.Response _chat(String content) => http.Response(
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

void main() {
  group('lokale Reparatur', () {
    test('Codefences und Text drumherum', () {
      expect(JsonRepair.decode('Hier ist das JSON:\n```json\n{"a": 1}\n```\nViel Erfolg!'), {'a': 1});
      expect(JsonRepair.decode('Klar! {"a": [1, 2]} – fertig.'), {
        'a': [1, 2],
      });
    });

    test(r'einfache LaTeX-Backslashes ($\frac$, \alpha)', () {
      final d = JsonRepair.decode(r'{"t": "$\frac{a}{b} + \alpha$"}') as Map;
      expect(d['t'], r'$\frac{a}{b} + \alpha$');
    });

    test('echte Zeilenumbrüche und Tabs in Texten', () {
      final d = JsonRepair.decode('{"text": "Zeile 1\nZeile 2\tTab", "n": 2}') as Map;
      expect(d['text'], 'Zeile 1\nZeile 2\tTab');
      expect(d['n'], 2);
    });

    test('Anführungszeichen im Text', () {
      final d = JsonRepair.decode('{"front": "Was besagt das "Hebelgesetz" im Zustandsdiagramm?", "back": "x"}') as Map;
      expect(d['front'], 'Was besagt das "Hebelgesetz" im Zustandsdiagramm?');
      expect(d['back'], 'x');
    });

    test('überzählige Kommas', () {
      expect(JsonRepair.decode('{"a": [1, 2, ], "b": {"c": 3,},}'), {
        'a': [1, 2],
        'b': {'c': 3},
      });
      final d = JsonRepair.decode('{"t": "a, ]b", "x": [1,]}') as Map;
      expect(d['t'], 'a, ]b', reason: 'Kommas in Texten bleiben');
    });

    test('abgeschnittene Antwort: offene Texte und Klammern geschlossen, halber Eintrag fällt weg', () {
      final cut = JsonRepair.decode(
        '{"flashcards": [{"front": "F1", "back": "A1"}, {"front": "F2", "back": "A2"}, {"front": "F3", "ba',
      );
      final cards = (cut as Map)['flashcards'] as List;
      expect(cards.take(2).map((c) => (c as Map)['front']), ['F1', 'F2']);
      expect(cards.length, lessThanOrEqualTo(3));
      expect(
        JsonRepair.decode('```json\n{"lessons": [{"title": "A", "steps": [{"title": "x"}]}, {"title": "B", "steps": ['),
        {'lessons': anyOf(hasLength(2), hasLength(1))},
      );
      expect((JsonRepair.decode('{"a": 1, "b": "halb') as Map)['a'], 1);
    });

    test('wirklich kein JSON → FormatException', () {
      expect(() => JsonRepair.decode('Tut mir leid, das kann ich nicht.'), throwsFormatException);
    });
  });

  group('Rückfrage an die KI', () {
    test('kaputte Antwort → einmal mit Fehlermeldung zurück, korrigiertes JSON wird genutzt', () async {
      final sent = <String>[];
      final ai = AiService(
        apiKey: 'sk',
        model: 'm',
        client: MockClient((r) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          final user = '${(body['messages'] as List)[1]['content']}';
          sent.add(user);
          if (user.startsWith('Fehler beim Einlesen')) return _chat('{"text": "repariert"}');
          return _chat('{"text": "kaputt" "x": }');
        }),
      );
      final json = await ai.explainVisual(lesson: const {});
      expect(json['text'], 'repariert');
      expect(sent, hasLength(2));
      expect(sent.last, contains('Fehler beim Einlesen:'));
      expect(sent.last, contains('{"text": "kaputt" "x": }'), reason: 'die KI bekommt ihre Antwort zurück');
    });

    test('auch die Reparatur scheitert → verständlicher Fehler mit Rohantwort', () async {
      final ai = AiService(
        apiKey: 'sk',
        model: 'm',
        client: MockClient((_) async => _chat('Ich kann leider kein JSON.')),
      );
      await expectLater(
        ai.explainVisual(lesson: const {}),
        throwsA(
          isA<AiServiceException>()
              .having((e) => e.message, 'message', contains('auch nicht nach Reparatur'))
              .having((e) => e.rawResponse, 'raw', 'Ich kann leider kein JSON.'),
        ),
      );
    });

    test('lokal reparierbar → keine zweite Anfrage', () async {
      var calls = 0;
      final ai = AiService(
        apiKey: 'sk',
        model: 'm',
        client: MockClient((_) async {
          calls++;
          return _chat('```json\n{"text": "Zeile\nzwei",}\n```');
        }),
      );
      expect((await ai.explainVisual(lesson: const {}))['text'], 'Zeile\nzwei');
      expect(calls, 1);
    });

    test('eingefügtes JSON reparieren lassen', () async {
      final ai = AiService(apiKey: 'sk', model: 'm', client: MockClient((_) async => _chat('{"tasks": []}')));
      expect(await ai.repairJson('{tasks: [', error: 'Unexpected character'), {'tasks': []});
    });
  });
}
