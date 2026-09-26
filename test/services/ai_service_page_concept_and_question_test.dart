import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/flashcard.dart' show QuestionType;
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/question_parsing.dart';

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
    List<dynamic> userContentOf(Map<String, dynamic> body) => (body['messages'] as List)[1]['content'] as List;
    String systemOf(Map<String, dynamic> body) => (body['messages'] as List)[0]['content'] as String;

    test('sendet Bild + Text, nennt die Stufen und liefert je Frage die Karten', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({
          'questions': [
            {
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
            },
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      final groups = await ai.generateQuestionsFromPage(
        pageImageBytes: Uint8List.fromList([9, 9, 9]),
        pageText: 'Seitentext',
        tiers: const [
          (level: 'Leicht', type: QuestionType.singleChoice),
          (level: 'Schwer', type: QuestionType.freeText),
        ],
      );

      expect(groups, hasLength(1));
      expect(groups.single, hasLength(2));
      expect(capturedBody!['model'], 'vision-model');
      final content = userContentOf(capturedBody!);
      expect(content, hasLength(2));
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
      final system = systemOf(capturedBody!);
      expect(system, contains('1. Stufe "Leicht": Typ single_choice'));
      expect(system, contains('2. Stufe "Schwer": Typ free_text'));
      expect(system, contains('GENAU 1 Frage(n)'));
      // Nur die Formatvorgaben der vorgegebenen Typen.
      expect(system, contains('Zieltyp "single_choice"'));
      expect(system, contains('Zieltyp "free_text"'));
      expect(system, isNot(contains('Zieltyp "drag_category"')));
      expect(system, isNot(contains('{{')));
    });

    test('Stufe ohne Typ: KI wählt frei und bekommt alle Formatvorgaben', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'questions': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      await ai.generateQuestionsFromPage(
        pageImageBytes: Uint8List.fromList([1]),
        pageText: 'Seitentext',
        tiers: const [
          (level: 'Leicht', type: null),
          (level: 'Mittel', type: QuestionType.fillBlank),
        ],
      );

      final system = systemOf(capturedBody!);
      expect(system, contains('1. Stufe "Leicht": Typ frei wählbar'));
      expect(system, contains('2. Stufe "Mittel": Typ fill_blank'));
      for (final type in AiService.pageQuestionTypes) {
        expect(system, contains('Zieltyp "${QuestionParsing.aiTypeName(type)}"'));
      }
      expect(system, isNot(contains('Zieltyp "html"')));
    });

    test('zwei Fragen: Anzahl steht im Prompt, beide Gruppen kommen zurück', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({
          'questions': [
            {
              'flashcards': [
                {'type': 'flashcard', 'front': 'F1', 'back': 'A1'},
              ],
            },
            {
              'flashcards': [
                {'type': 'flashcard', 'front': 'F2', 'back': 'A2'},
              ],
            },
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      final groups = await ai.generateQuestionsFromPage(
        pageImageBytes: Uint8List.fromList([1]),
        pageText: 'Seitentext',
        tiers: const [(level: 'Leicht', type: null)],
        questionCount: 2,
      );

      expect(groups.map((g) => g.single['front']), ['F1', 'F2']);
      expect(systemOf(capturedBody!), contains('GENAU 2 Frage(n)'));
    });

    test('markierter Bereich geht als zweites Bild mit, Text-Fokus als verbindliche Vorgabe', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'questions': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      await ai.generateQuestionsFromPage(
        pageImageBytes: Uint8List.fromList([1]),
        pageText: 'Seitentext',
        tiers: const [(level: 'Leicht', type: QuestionType.singleChoice)],
        focusImageBytes: Uint8List.fromList([7, 7]),
        focusText: 'Was ist ein Werkstoff?',
        answerText: 'Ein fester Stoff für den Bau von Maschinen.',
      );

      final content = userContentOf(capturedBody!);
      expect(content, hasLength(4));
      expect(content[1]['type'], 'image_url');
      expect(content[2]['type'], 'text');
      expect(content[3]['type'], 'image_url');
      expect(content[3]['image_url']['url'], 'data:image/png;base64,${base64Encode([7, 7])}');
      final text = content[0]['text'] as String;
      expect(text, contains('VERBINDLICHE Grundlage'));
      expect(text, contains('Markierter Bereich der Seite'));
      expect(text, contains('Was ist ein Werkstoff?'));
      expect(text, contains('Ein fester Stoff für den Bau von Maschinen.'));
    });

    test('ohne Fokus keine Vorgabe und nur das Seitenbild', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'questions': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      await ai.generateQuestionsFromPage(
        pageImageBytes: Uint8List.fromList([1]),
        pageText: 'Seitentext',
        tiers: const [(level: 'Leicht', type: null)],
        focusText: '   ',
      );

      final content = userContentOf(capturedBody!);
      expect(content, hasLength(2));
      expect(content[0]['text'] as String, isNot(contains('VERBINDLICHE')));
    });

    test('hängt eine Übungsklausur als Stil-Referenz an', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'questions': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      await ai.generateQuestionsFromPage(
        pageImageBytes: Uint8List.fromList([1]),
        pageText: 'Seitentext',
        tiers: const [(level: 'Leicht', type: QuestionType.singleChoice)],
        examContext: 'Alte-Klausur-Inhalt',
      );

      expect(userContentOf(capturedBody!)[0]['text'] as String, contains('Alte-Klausur-Inhalt'));
    });

    test('Überarbeitung schickt bereits erstellte Fragen + Anweisung mit', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse(jsonEncode({'questions': []}));
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      await ai.generateQuestionsFromPage(
        pageImageBytes: Uint8List.fromList([1]),
        pageText: 'Seitentext',
        tiers: const [(level: 'Leicht', type: QuestionType.singleChoice)],
        previousQuestions: const [
          [
            {'type': 'single_choice', 'front': 'Komplizierte Frage?'},
          ],
        ],
        instruction: 'einfacher formulieren',
      );

      final text = userContentOf(capturedBody!)[0]['text'] as String;
      expect(text, contains('Komplizierte Frage?'));
      expect(text, contains('einfacher formulieren'));
    });
  });

  group('AiService.parsePageQuestionGroups', () {
    test('liest das Format mit mehreren Fragen und lässt leere weg', () {
      final groups = AiService.parsePageQuestionGroups({
        'questions': [
          {
            'flashcards': [
              {'front': 'A'},
              {'front': 'B'},
            ],
          },
          {'flashcards': []},
          'Unsinn',
          {
            'flashcards': [
              {'front': 'C'},
              42,
            ],
          },
        ],
      });
      expect(groups.map((g) => g.map((c) => c['front']).toList()).toList(), [
        ['A', 'B'],
        ['C'],
      ]);
    });

    test('älteres flaches Format zählt als eine Frage', () {
      final groups = AiService.parsePageQuestionGroups({
        'flashcards': [
          {'front': 'A'},
        ],
      });
      expect(groups, hasLength(1));
      expect(AiService.parsePageQuestionGroups(const {}), isEmpty);
    });
  });
}
