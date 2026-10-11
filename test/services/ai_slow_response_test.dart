import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/ui/widgets/slow_ai_dialog.dart';

/// OpenRouter antwortet erst nach [delay].
AiService _slowAi(Duration delay, {void Function()? onRequest}) => AiService(
  apiKey: 'sk-test',
  model: 'm',
  client: MockClient((_) async {
    onRequest?.call();
    await Future<void>.delayed(delay);
    return http.Response(
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
  }),
);

void main() {
  final original = AiService.requestTimeout;

  setUp(() => AiService.requestTimeout = const Duration(milliseconds: 40));

  tearDown(() {
    AiService.requestTimeout = original;
    AiService.onSlowResponse = null;
  });

  test('Ohne Rückfrage-Hook: Abbruch nach der Wartezeit wie bisher', () async {
    await expectLater(
      _slowAi(const Duration(milliseconds: 300)).explainVisual(lesson: const {}),
      throwsA(isA<AiServiceException>().having((e) => e.message, 'message', contains('Keine Antwort von OpenRouter'))),
    );
  });

  test('„Weiter warten“: dieselbe Anfrage läuft weiter, kein zweiter Aufruf', () async {
    var requests = 0;
    final asked = <Duration>[];
    AiService.onSlowResponse = (waited, done) async {
      asked.add(waited);
      return true;
    };
    final reply = await _slowAi(
      const Duration(milliseconds: 150),
      onRequest: () => requests++,
    ).explainVisual(lesson: const {});
    expect(reply['text'], 'fertig');
    expect(requests, 1);
    expect(asked, isNotEmpty);
    expect(asked.first, const Duration(milliseconds: 40));
    if (asked.length > 1) expect(asked[1], const Duration(milliseconds: 80), reason: 'Wartezeit summiert sich');
  });

  test('„Abbrechen“: verständliche Meldung statt Antwort', () async {
    AiService.onSlowResponse = (_, _) async => false;
    await expectLater(
      _slowAi(const Duration(milliseconds: 300)).explainVisual(lesson: const {}),
      throwsA(isA<AiServiceException>().having((e) => e.message, 'message', startsWith('Abgebrochen'))),
    );
  });

  testWidgets('Dialog: Weiter warten / Abbrechen, schließt sich bei später Antwort selbst', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: const Scaffold(body: Text('App')),
      ),
    );

    // Weiter warten.
    final never = Completer<void>();
    final first = SlowAiPrompt.ask(const Duration(minutes: 3), never.future);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-slow-dialog')), findsOneWidget);
    expect(find.textContaining('seit 3 Minuten'), findsOneWidget);
    // Eine zweite Anfrage teilt sich den offenen Dialog.
    final second = SlowAiPrompt.ask(const Duration(minutes: 3), never.future);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-slow-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-slow-wait')));
    await tester.pumpAndSettle();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(find.byKey(const ValueKey('ai-slow-dialog')), findsNothing);

    // Abbrechen.
    final cancelled = SlowAiPrompt.ask(const Duration(minutes: 6), never.future);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-slow-cancel')));
    await tester.pumpAndSettle();
    expect(await cancelled, isFalse);

    // Antwort kommt, während der Dialog offen ist → schließt sich (= weiter).
    final answered = Completer<void>();
    final late = SlowAiPrompt.ask(const Duration(minutes: 3), answered.future);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-slow-dialog')), findsOneWidget);
    answered.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-slow-dialog')), findsNothing);
    expect(await late, isTrue);
    expect(find.text('App'), findsOneWidget);
  });
}
