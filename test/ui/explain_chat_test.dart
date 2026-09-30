import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/study/explain_chat.dart';
import 'package:provider/provider.dart';

class _Settings extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

http.Response _chat(String content) => http.Response(
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

void main() {
  tearDown(() => ExplainChat.aiFactory = null);

  Widget app({String? explanation}) => ChangeNotifierProvider<SettingsRepository>.value(
        value: _Settings(),
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExplainChat(
                question: 'Wozu dient der Trigger?',
                correctAnswer: 'Er stabilisiert die Darstellung.',
                userAnswer: 'Er startet die Messung',
                wasCorrect: false,
                explanation: explanation,
              ),
            ),
          ),
        ),
      );

  testWidgets('erst zu, dann auf; Chips füllen Satzanfänge; die KI kennt Frage, Lösung, Antwort, Erklärung und Verlauf',
      (tester) async {
    final prompts = <String>[];
    ExplainChat.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((request) async {
            final messages = jsonDecode(request.body)['messages'] as List;
            prompts.add(messages.last['content'] as String);
            return _chat(prompts.length == 1 ? 'Fast: es fehlt der Pegel.' : 'Der Pegel legt fest, ab wann getriggert wird.');
          }),
        );
    await tester.pumpWidget(app(explanation: 'Der Trigger synchronisiert die Zeitbasis.'));
    expect(find.byKey(const ValueKey('explain-chat')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('explain-chat-open')));
    await tester.pump();
    expect(find.byKey(const ValueKey('explain-chat')), findsOneWidget);

    // "In meinen Worten erklären": der Satzanfang steht schon im Feld.
    await tester.tap(find.byKey(const ValueKey('chip-own-words')));
    await tester.pump();
    var field = tester.widget<TextField>(find.byKey(const ValueKey('explain-chat-input')));
    expect(field.controller!.text, 'Ich erkläre es mal in meinen Worten: ');
    await tester.enterText(
      find.byKey(const ValueKey('explain-chat-input')),
      'Ich erkläre es mal in meinen Worten: Er hält das Bild fest.',
    );
    await tester.tap(find.byKey(const ValueKey('explain-chat-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ich erkläre es mal in meinen Worten: Er hält das Bild fest.'), findsOneWidget);
    expect(find.text('Fast: es fehlt der Pegel.'), findsOneWidget);
    expect(prompts.first, contains('Lernfrage: Wozu dient der Trigger?'));
    expect(prompts.first, contains('Richtige Lösung: Er stabilisiert die Darstellung.'));
    expect(prompts.first, contains('Antwort des Lernenden: Er startet die Messung'));
    expect(prompts.first, contains('Die Antwort war falsch.'));
    expect(prompts.first, contains('Der Trigger synchronisiert die Zeitbasis.'));
    expect(prompts.first, contains('Er hält das Bild fest.'));
    // Das Feld ist nach dem Senden leer.
    field = tester.widget<TextField>(find.byKey(const ValueKey('explain-chat-input')));
    expect(field.controller!.text, isEmpty);

    // Zweite Nachricht: der bisherige Dialog geht mit.
    await tester.tap(find.byKey(const ValueKey('chip-deeper')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('explain-chat-input'))).controller!.text,
        'Geh bitte genauer auf folgenden Punkt ein: ');
    await tester.enterText(
        find.byKey(const ValueKey('explain-chat-input')), 'Geh bitte genauer auf folgenden Punkt ein: den Pegel');
    await tester.tap(find.byKey(const ValueKey('explain-chat-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(prompts.last, contains('Bisheriger Dialog:'));
    expect(prompts.last, contains('Tutor: Fast: es fehlt der Pegel.'));
    expect(prompts.last, contains('Letzte Nachricht des Lernenden:\nGeh bitte genauer auf folgenden Punkt ein: den Pegel'));
    expect(find.text('Der Pegel legt fest, ab wann getriggert wird.'), findsOneWidget);
    // Antworten der KI sind markierbar.
    expect(find.descendant(of: find.byKey(const ValueKey('explain-chat')), matching: find.byType(SelectionArea)), findsOneWidget);
  });

  testWidgets('"Anderes Beispiel" sendet sofort; ein Fehler der KI wird angezeigt und das Gespräch bleibt', (tester) async {
    var calls = 0;
    ExplainChat.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((request) async {
            calls++;
            return http.Response('kaputt', 500);
          }),
        );
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const ValueKey('explain-chat-open')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chip-example')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, 1);
    expect(find.text('Gib mir bitte ein anderes Beispiel dazu.'), findsOneWidget);
    expect(find.textContaining('fehlgeschlagen'), findsOneWidget);
  });

  test('AiService.followUpAnswer: Regeln für Rückfrage, Prüfen in eigenen Worten und Vertiefen stehen im Prompt', () async {
    late Map<String, dynamic> body;
    final ai = AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return _chat('  Antwort  ');
      }),
    );
    final answer = await ai.followUpAnswer(
      question: 'F',
      correctAnswer: 'L',
      message: 'Stimmt das?',
      history: [(isUser: true, content: 'Hallo'), (isUser: false, content: 'Hi')],
    );
    expect(answer, 'Antwort');
    final system = (body['messages'] as List).first['content'] as String;
    expect(system, allOf(contains('EIGENEN WORTEN'), contains('genauer auf einen Punkt'), contains('Widersprich der gegebenen')));
    final user = (body['messages'] as List).last['content'] as String;
    expect(user, contains('Lernender: Hallo'));
    expect(user, contains('Tutor: Hi'));
    expect(user, endsWith('Stimmt das?\n'));
  });
}
