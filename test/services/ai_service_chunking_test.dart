import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
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
  group('AiService – Chunking mit Rolling Context', () {
    test('generateSummary ruft die KI nur einmal auf, wenn der Text kurz ist', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _chatResponse(jsonEncode({
          'title': 'Titel',
          'overview': 'Übersicht',
          'key_points': ['A'],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      await ai.generateSummary('kurzer Text', granularity: ChunkGranularity.auto);

      expect(calls, 1);
    });

    test('generateSummary zerlegt langen Text in mehrere Anfragen und führt Ergebnisse zusammen', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _chatResponse(jsonEncode({
          'title': 'Abschnitt $calls',
          'overview': 'Übersicht Abschnitt $calls',
          'key_points': ['Punkt $calls', 'Gemeinsamer Punkt'],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final longText = ('Ein langer Satz mit genug Inhalt, um mehrere Chunks zu erzwingen. ' * 400);
      final progressCalls = <List<int>>[];
      final result = await ai.generateSummary(
        longText,
        granularity: ChunkGranularity.fine,
        onProgress: (done, total) => progressCalls.add([done, total]),
      );

      expect(calls, greaterThan(1));
      // Erster Chunk bestimmt den Titel.
      expect(result['title'], 'Abschnitt 1');
      // Übersichten aus allen Abschnitten werden zusammengeführt.
      final overview = result['overview'] as String;
      expect(overview.contains('Abschnitt 1'), isTrue);
      expect(overview.contains('Abschnitt $calls'), isTrue);
      // Doppelte Kernkonzepte (Rolling Context) werden nicht wiederholt.
      final keyPoints = (result['key_points'] as List).cast<String>();
      expect(keyPoints.where((p) => p == 'Gemeinsamer Punkt').length, 1);
      expect(progressCalls.last, [calls, calls]);
    });

    test('rollingContext=false verhindert trotzdem keine Deduplizierung der Kernkonzepte', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        // Prüft, dass ohne Rolling Context KEIN Kontext-Hinweis im Prompt steht.
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final userMessage = (body['messages'] as List).last['content'] as String;
        expect(userMessage.contains('Bereits erfasste Kernkonzepte'), isFalse);
        return _chatResponse(jsonEncode({
          'title': 'T',
          'overview': 'O$calls',
          'key_points': ['P'],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final longText = ('Ein langer Satz mit genug Inhalt, um mehrere Chunks zu erzwingen. ' * 400);
      await ai.generateSummary(longText, granularity: ChunkGranularity.fine, rollingContext: false);

      expect(calls, greaterThan(1));
    });

    test('generateConceptsAndFlashcards führt Konzepte/Karteikarten über Chunks hinweg zusammen', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _chatResponse(jsonEncode({
          'concepts': [
            {'title': 'Gemeinsames Konzept', 'explanation': 'E$calls'},
            {'title': 'Konzept $calls', 'explanation': 'E$calls'},
          ],
          'flashcards': [
            {'front': 'F$calls', 'back': 'B$calls'},
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'test-model', client: client);

      final longSlides = 'Folieninhalt. ' * 400;
      final longExercises = 'Übungsinhalt. ' * 400;
      final result = await ai.generateConceptsAndFlashcards(
        slidesText: longSlides,
        exercisesText: longExercises,
        granularity: ChunkGranularity.fine,
      );

      expect(calls, greaterThan(1));
      final concepts = (result['concepts'] as List);
      final titles = concepts.map((c) => c['title']).toList();
      // "Gemeinsames Konzept" taucht trotz mehrfacher Nennung nur einmal auf.
      expect(titles.where((t) => t == 'Gemeinsames Konzept').length, 1);
      // Karteikarten werden nicht dedupliziert (können absichtlich ähnlich sein).
      expect((result['flashcards'] as List).length, calls);
    });
  });

  group('AiService – Crosscheck', () {
    test('crosscheckConceptsAndFlashcards parst Issues aus der Antwort', () async {
      final client = MockClient((request) async {
        return _chatResponse(jsonEncode({
          'ok': false,
          'issues': [
            {'title': 'Konzept A', 'problem': 'Fehlerhaft', 'suggestion': 'Korrektur'},
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'crosscheck-model', client: client);

      final result = await ai.crosscheckConceptsAndFlashcards(
        slidesText: 'Folien',
        exercisesText: 'Übungen',
        generated: {'concepts': [], 'flashcards': []},
      );

      expect(result['ok'], false);
      expect((result['issues'] as List).length, 1);
    });
  });
}
