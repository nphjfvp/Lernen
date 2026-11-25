import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';

void main() {
  test('lange System-Prompts werden bei Claude/Gemini zum Zwischenspeichern markiert', () {
    final long = 'x' * AiService.cacheMinChars;
    final claude = AiService.buildMessages('anthropic/claude-sonnet-4.5', long, 'Frage');
    expect(claude.first['content'], isA<List>());
    expect((claude.first['content'] as List).first['cache_control'], {'type': 'ephemeral'});
    expect(AiService.buildMessages('anthropic/claude-sonnet-4.5', 'kurz', 'Frage').first['content'], 'kurz');
    expect(AiService.buildMessages('openai/gpt-5', long, 'Frage').first['content'], long);
    expect(AiService.buildMessages('google/gemini-2.5-pro', long, 'Frage').first['content'], isA<List>());
  });

  test('Quellen aus url_citation, ohne Dubletten', () {
    final sources = WebSource.fromAnnotations([
      {'type': 'url_citation', 'url_citation': {'url': 'https://a.example/x', 'title': 'A'}},
      {'type': 'url_citation', 'url_citation': {'url': 'https://a.example/x', 'title': 'A'}},
      {'type': 'url_citation', 'url_citation': {'url': 'ftp://nope'}},
    ]);
    expect(sources, hasLength(1));
    expect(sources.single.title, 'A');
  });

  test('Web-Erklärung schaltet die Websuche zu und liefert Quellen', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': 'Stell dir einen Wasserschlauch vor …',
                'annotations': [
                  {'type': 'url_citation', 'url_citation': {'url': 'https://lehrbuch.example/strom', 'title': 'Strom'}},
                ],
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final ai = AiService(apiKey: 'k', model: 'openai/gpt-5', client: client);
    final result = await ai.explainWithWebResearch(
      question: 'Was ist Stromstärke?',
      correctAnswer: 'Ladung pro Zeit',
      previousExplanations: const ['I = Q/t'],
    );
    expect(sent!['plugins'], [
      {'id': 'web', 'max_results': 3},
    ]);
    expect(result.text, contains('Wasserschlauch'));
    expect(result.sources.single.url, 'https://lehrbuch.example/strom');
  });
}
