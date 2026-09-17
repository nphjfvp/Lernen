import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/flashcard.dart' show QuestionType;
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
  group('AiService.generatePageConcept', () {
    test('generiert Titel/Erklärung nur aus dem Seitentext, ohne Nachbarn', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'title': 'Formgedächtnislegierungen', 'explanation': 'Erklärung...'}));
      });
      final ai = AiService(apiKey: 'key', model: 'question-model', client: client);

      final result = await ai.generatePageConcept(pageText: 'Text der aktuellen Seite über FGL.');

      expect(result['title'], 'Formgedächtnislegierungen');
      final userContent = (capturedBody!['messages'] as List)[1]['content'] as String;
      expect(userContent.contains('Text der aktuellen Seite über FGL.'), isTrue);
      expect(userContent.contains('VORHERIGEN'), isFalse);
      expect(userContent.contains('NACHFOLGENDEN'), isFalse);
    });

    test('hängt Nachbarseiten-Text als optionalen Kontext an, wenn mitgegeben', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'title': 'X', 'explanation': 'Y'}));
      });
      final ai = AiService(apiKey: 'key', model: 'question-model', client: client);

      await ai.generatePageConcept(
        pageText: 'Seite 5',
        previousPageText: 'Seite 4 Inhalt',
        nextPageText: 'Seite 6 Inhalt',
      );

      final userContent = (capturedBody!['messages'] as List)[1]['content'] as String;
      expect(userContent.contains('Seite 4 Inhalt'), isTrue);
      expect(userContent.contains('Seite 6 Inhalt'), isTrue);
      expect(userContent.contains('nur bei Bedarf nutzen'), isTrue);
    });

    test('Überarbeitung schickt bestehendes Konzept + Anweisung mit', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'title': 'X', 'explanation': 'Kürzere Version'}));
      });
      final ai = AiService(apiKey: 'key', model: 'question-model', client: client);

      await ai.generatePageConcept(
        pageText: 'Seitentext',
        currentTitle: 'Altes Konzept',
        currentExplanation: 'Lange alte Erklärung',
        instruction: 'kürzer bitte',
      );

      final userContent = (capturedBody!['messages'] as List)[1]['content'] as String;
      expect(userContent.contains('Lange alte Erklärung'), isTrue);
      expect(userContent.contains('kürzer bitte'), isTrue);
    });
  });

  group('AiService.generateQuestionsFromPage', () {
    test('sendet Bild + Text und fordert eine Karte je gewünschtem Typ', () async {
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
              ],
            },
            {'type': 'free_text', 'front': 'Was ist X?', 'correctText': 'A'},
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);
      final imageBytes = Uint8List.fromList([9, 9, 9]);

      final cards = await ai.generateQuestionsFromPage(
        pageImageBytes: imageBytes,
        pageText: 'Seitentext',
        types: const [QuestionType.singleChoice, QuestionType.freeText],
      );

      expect(cards, hasLength(2));
      expect(capturedBody!['model'], 'vision-model');
      final userContent = (capturedBody!['messages'] as List)[1]['content'] as List;
      expect(userContent[0]['type'], 'text');
      expect(userContent[1]['type'], 'image_url');
      // Die Typ-Formatvorgaben stecken im System-Prompt (eine Regel je
      // gewünschtem Typ, siehe _variantTypeRule-Wiederverwendung).
      final systemContent = (capturedBody!['messages'] as List)[0]['content'] as String;
      expect(systemContent.contains('single_choice'), isTrue);
      expect(systemContent.contains('free_text'), isTrue);
    });

    test('gibt ein markiertes Frage/Antwort-Paar als verbindliche Grundlage mit', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'flashcards': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      await ai.generateQuestionsFromPage(
        pageImageBytes: Uint8List.fromList([1]),
        pageText: 'Seitentext',
        types: const [QuestionType.singleChoice],
        questionHighlight: 'Was ist ein Werkstoff?',
        answerHighlight: 'Ein fester Stoff für den Bau von Maschinen.',
      );

      final text = ((capturedBody!['messages'] as List)[1]['content'] as List)[0]['text'] as String;
      expect(text.contains('Was ist ein Werkstoff?'), isTrue);
      expect(text.contains('Ein fester Stoff für den Bau von Maschinen.'), isTrue);
      expect(text.contains('VERBINDLICHE Grundlage'), isTrue);
    });

    test('hängt eine Übungsklausur als Stil-Referenz an', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'flashcards': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      await ai.generateQuestionsFromPage(
        pageImageBytes: Uint8List.fromList([1]),
        pageText: 'Seitentext',
        types: const [QuestionType.singleChoice],
        examContext: 'Alte-Klausur-Inhalt',
      );

      final text = ((capturedBody!['messages'] as List)[1]['content'] as List)[0]['text'] as String;
      expect(text.contains('Alte-Klausur-Inhalt'), isTrue);
    });
  });
}
