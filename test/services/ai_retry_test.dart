import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/openrouter_errors.dart';

http.Response _ok() => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {
          'content': jsonEncode({'text': 'fertig'}),
        },
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Antwortet der Reihe nach mit [replies] (danach immer mit dem letzten).
AiService _ai(List<http.Response Function()> replies, {void Function()? onCall}) {
  var i = 0;
  return AiService(
    apiKey: 'sk-test',
    model: 'm',
    client: MockClient((_) async {
      onCall?.call();
      final reply = replies[i < replies.length ? i : replies.length - 1];
      i++;
      return reply();
    }),
  );
}

void main() {
  final original = AiService.retryDelays;
  setUp(() => AiService.retryDelays = const [Duration.zero, Duration.zero]);
  tearDown(() => AiService.retryDelays = original);

  test('429 und 503: erneut versucht, die spätere Antwort zählt', () async {
    var calls = 0;
    final ai = _ai([
      () => http.Response('{"error":{"code":429,"message":"Rate limit exceeded"}}', 429),
      () => http.Response('{"error":{"code":503,"message":"No provider"}}', 503),
      _ok,
    ], onCall: () => calls++);
    expect((await ai.explainVisual(lesson: const {}))['text'], 'fertig');
    expect(calls, 3);
  });

  test('Fehler des Anbieters mitten in einer 200-Antwort wird auch wiederholt', () async {
    var calls = 0;
    final ai = _ai([
      () => http.Response('{"error":{"code":502,"message":"Provider returned error"}}', 200),
      _ok,
    ], onCall: () => calls++);
    expect((await ai.explainVisual(lesson: const {}))['text'], 'fertig');
    expect(calls, 2);
  });

  test('Bleibt es bei 429: verständliche Meldung mit Zahl der Versuche, roher Body nur in den Details', () async {
    const body = '{"error":{"code":429,"message":"free-models-per-day limit"}}';
    var calls = 0;
    final ai = _ai([() => http.Response(body, 429)], onCall: () => calls++);
    await expectLater(
      ai.explainVisual(lesson: const {}),
      throwsA(
        isA<AiServiceException>()
            .having((e) => e.message, 'message', allOf(contains('Zu viele Anfragen (429)'), contains('3 Versuchen')))
            .having((e) => e.message, 'message', isNot(contains('{')))
            .having((e) => e.rawResponse, 'rawResponse', body),
      ),
    );
    expect(calls, 3);
  });

  test('Echte Fehler (401, 500) und Verbindungsfehler', () async {
    var calls = 0;
    final denied = _ai([() => http.Response('{"error":{"code":401,"message":"No auth"}}', 401)], onCall: () => calls++);
    await expectLater(
      denied.explainVisual(lesson: const {}),
      throwsA(isA<AiServiceException>().having((e) => e.message, 'message', contains('API-Key'))),
    );
    expect(calls, 1, reason: '401 wird nicht wiederholt');

    calls = 0;
    final broken = _ai([() => http.Response('Server-Fehler', 500)], onCall: () => calls++);
    await expectLater(
      broken.explainVisual(lesson: const {}),
      throwsA(isA<AiServiceException>().having((e) => e.message, 'message', contains('(500): Server-Fehler'))),
    );
    expect(calls, 1);

    calls = 0;
    final flaky = AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((_) async {
        if (++calls == 1) throw http.ClientException('Verbindung abgerissen');
        return _ok();
      }),
    );
    expect((await flaky.explainVisual(lesson: const {}))['text'], 'fertig');
    expect(calls, 2);
  });

  test('Fehlermeldungen und Retry-After', () {
    expect(OpenRouterErrors.codeOf(200, '{"choices":[]}'), isNull);
    expect(OpenRouterErrors.codeOf(200, '{"error":{"code":"502"}}'), 502);
    expect(OpenRouterErrors.codeOf(200, '{"error":"kaputt"}'), 500);
    expect(OpenRouterErrors.codeOf(404, 'nicht da'), 404);
    expect(OpenRouterErrors.message(402, ''), contains('Guthaben'));
    expect(OpenRouterErrors.message(404, '{"error":{"message":"No endpoints found"}}'), contains('No endpoints found'));
    expect(OpenRouterErrors.detailOf('x' * 500), hasLength(201));
    expect(OpenRouterErrors.retryAfter({'retry-after': '5'}), const Duration(seconds: 5));
    expect(OpenRouterErrors.retryAfter({'retry-after': '600'}), const Duration(seconds: 30));
    expect(OpenRouterErrors.retryAfter({'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT'}), isNull);
  });
}
