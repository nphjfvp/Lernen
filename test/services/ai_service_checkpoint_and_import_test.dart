import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart' show ChunkGranularity;
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
  group('AiService.generateCheckpointQuiz', () {
    test('schickt den Seitenabschnitt und liefert die generierten Karten zurück', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({
          'flashcards': [
            {
              'type': 'single_choice',
              'front': 'Was ist X?',
              'options': [
                {'text': 'A', 'isCorrect': true},
                {'text': 'B', 'isCorrect': false},
              ],
            },
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'question-model', client: client);

      final cards = await ai.generateCheckpointQuiz('Text der zuletzt gelesenen Seiten.');

      expect(cards, hasLength(1));
      expect(cards.first['front'], 'Was ist X?');
      final userContent = (capturedBody!['messages'] as List)[1]['content'] as String;
      expect(userContent.contains('Text der zuletzt gelesenen Seiten.'), isTrue);
    });

    test('hängt eine mitgegebene Übungsklausur als Stil-Referenz an', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'flashcards': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'question-model', client: client);

      await ai.generateCheckpointQuiz('Abschnitt', examContext: 'Alte Klausur Inhalt XYZ');

      final userContent = (capturedBody!['messages'] as List)[1]['content'] as String;
      expect(userContent.contains('Alte Klausur Inhalt XYZ'), isTrue);
    });

    test('ohne Übungsklausur-Kontext erscheint auch kein Stil-Referenz-Hinweis', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'flashcards': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'question-model', client: client);

      await ai.generateCheckpointQuiz('Abschnitt');

      final userContent = (capturedBody!['messages'] as List)[1]['content'] as String;
      expect(userContent.contains('Stil-Referenz'), isFalse);
    });
  });

  group('AiService.importQuestionsFromExercises', () {
    test('übernimmt die im Dokument gefundenen Fragen unverändert als Karteikarten', () async {
      final client = MockClient((request) async {
        return _chatResponse(jsonEncode({
          'flashcards': [
            {'type': 'free_text', 'front': 'Berechne 2+2', 'correctText': '4'},
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'question-model', client: client);

      final imported = await ai.importQuestionsFromExercises('Alte Klausur:\n1) Berechne 2+2\nLösung: 4');

      expect(imported, hasLength(1));
      expect(imported.first['front'], 'Berechne 2+2');
      expect(imported.first['correctText'], '4');
    });

    test('meldet Fortschritt über mehrere Chunks, wenn das Dokument lang ist', () async {
      final client = MockClient((request) async {
        return _chatResponse(jsonEncode({'flashcards': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'question-model', client: client);

      final progressCalls = <(int, int)>[];
      await ai.importQuestionsFromExercises(
        'x' * 200000,
        granularity: ChunkGranularity.fine,
        onProgress: (done, total) => progressCalls.add((done, total)),
      );

      expect(progressCalls, isNotEmpty);
      expect(progressCalls.last.$1, progressCalls.last.$2);
    });
  });

  group('AiService.generateConceptsAndFlashcards mit examContext', () {
    test('hängt die Übungsklausur als Stil-Referenz an das Prompt-Material an', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'concepts': [], 'flashcards': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'question-model', client: client);

      await ai.generateConceptsAndFlashcards(
        slidesText: 'Folieninhalt',
        exercisesText: '',
        examContext: 'Klausur-Referenztext',
      );

      final userContent = (capturedBody!['messages'] as List)[1]['content'] as String;
      expect(userContent.contains('Klausur-Referenztext'), isTrue);
      expect(userContent.contains('STIL-REFERENZ'), isTrue);
    });

    test('funktioniert ohne Übungsaufgaben (nur Folien)', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'concepts': [], 'flashcards': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'question-model', client: client);

      final result = await ai.generateConceptsAndFlashcards(slidesText: 'Nur Folien, keine Übungen.', exercisesText: '');

      expect(result, isNotNull);
      final userContent = (capturedBody!['messages'] as List)[1]['content'] as String;
      expect(userContent.contains('keine hochgeladen'), isTrue);
    });
  });
}
