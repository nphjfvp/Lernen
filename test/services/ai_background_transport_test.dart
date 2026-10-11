import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/background_transport.dart';
import 'package:lernen/ui/visual/visual_learn_screen.dart';

http.Response _reply(String text) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {
          'content': jsonEncode({'text': text}),
        },
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  tearDown(() => AiService.backgroundTransport = null);

  test('Hintergrund-Übertragung (Android): Anfrage geht dorthin, mit Key, Modell und Inhalt', () async {
    final sent = <Map<String, dynamic>>[];
    var direct = 0;
    AiService.backgroundTransport = (url, headers, body) async {
      expect(url.toString(), contains('openrouter.ai'));
      expect(headers['Authorization'], 'Bearer sk-test');
      sent.add(jsonDecode(body) as Map<String, dynamic>);
      return _reply('aus dem Hintergrund – äöü');
    };
    final ai = AiService(
      apiKey: 'sk-test',
      model: 'm',
      background: true,
      client: MockClient((_) async {
        direct++;
        return _reply('direkt');
      }),
    );
    final json = await ai.explainVisual(lesson: const {}, question: 'Warum?');
    expect(json['text'], 'aus dem Hintergrund – äöü');
    expect(direct, 0);
    expect(sent.single['model'], 'm');
    expect(jsonEncode(sent.single['messages']), contains('Warum?'));
  });

  test('Scheitert die Hintergrund-Übertragung selbst, geht die Anfrage auf dem normalen Weg raus', () async {
    AiService.backgroundTransport = (_, _, _) async => throw BackgroundTransportException('kein WorkManager');
    final ai = AiService(
      apiKey: 'sk-test',
      model: 'm',
      background: true,
      client: MockClient((_) async => _reply('direkt')),
    );
    expect((await ai.explainVisual(lesson: const {}))['text'], 'direkt');
  });

  test('Echte Fehlerantwort (z.B. 401) kommt durch – kein zweiter Versuch', () async {
    var direct = 0;
    AiService.backgroundTransport = (_, _, _) async => http.Response('{"error":"Key ungültig"}', 401);
    final ai = AiService(
      apiKey: 'sk-test',
      model: 'm',
      background: true,
      client: MockClient((_) async {
        direct++;
        return _reply('direkt');
      }),
    );
    await expectLater(
      ai.explainVisual(lesson: const {}),
      throwsA(isA<AiServiceException>().having((e) => e.message, 'message', contains('401'))),
    );
    expect(direct, 0);
  });

  test('Mit eigenem Client (Tests) bleibt die Hintergrund-Übertragung aus', () async {
    var background = 0;
    AiService.backgroundTransport = (_, _, _) async {
      background++;
      return _reply('hintergrund');
    };
    final ai = AiService(apiKey: 'sk-test', model: 'm', client: MockClient((_) async => _reply('direkt')));
    expect((await ai.explainVisual(lesson: const {}))['text'], 'direkt');
    expect(background, 0);
  });

  test('Themensuche: große PDFs in Abschnitten, Themenzahl wächst mit den Seiten', () {
    final texts = [for (var i = 0; i < 100; i++) 'x' * (i < 50 ? 1000 : 4000)];
    final windows = VisualLearnScreen.topicWindows([for (var p = 1; p <= 100; p++) p], texts);
    expect(windows.expand((w) => w).toList(), [for (var p = 1; p <= 100; p++) p], reason: 'jede Seite genau einmal');
    expect(windows.first, hasLength(30), reason: 'höchstens 30.000 Zeichen je Abschnitt');
    expect(windows.every((w) => w.length <= VisualLearnScreen.topicWindowPages), isTrue);
    expect(windows.length, greaterThan(5));
    final short = [for (var i = 0; i < 80; i++) 'kurz'];
    expect(VisualLearnScreen.topicWindows([for (var p = 1; p <= 80; p++) p], short).map((w) => w.length), [40, 40]);
    expect(VisualLearnScreen.topicWindows([2, 3], short), [
      [2, 3],
    ]);
    expect(VisualLearnScreen.maxTopicsFor(3), 4);
    expect(VisualLearnScreen.maxTopicsFor(20), 10);
    expect(VisualLearnScreen.maxTopicsFor(40), 15);
  });
}
