import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';

http.Response _chatResponse(String content) => http.Response(
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
  late List<Map<String, dynamic>> requests;

  AiService aiReplying(String reply) {
    requests = [];
    final client = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _chatResponse(reply);
    });
    return AiService(apiKey: 'key', model: 'test-model', client: client);
  }

  Object userContent() => (requests.single['messages'] as List).last['content'] as Object;
  String systemPrompt() => (requests.single['messages'] as List).first['content'] as String;

  group('AiService.generateMiniLesson', () {
    test('Grundlage sind Seite und Konzept, Aufbau steht im Prompt', () async {
      final ai = aiReplying('  Worum es geht: Ohm.\n\nMerke: U = R·I  ');
      final lesson = await ai.generateMiniLesson(
        question: 'Wie lautet das Ohmsche Gesetz?',
        correctAnswer: 'U = R · I',
        sourceText: 'Folie 12: Ohmsches Gesetz',
        conceptExplanation: 'Spannung ist proportional zum Strom.',
      );
      expect(lesson, 'Worum es geht: Ohm.\n\nMerke: U = R·I');
      final prompt = userContent() as String;
      expect(prompt, contains('Folie 12: Ohmsches Gesetz'));
      expect(prompt, contains('Spannung ist proportional zum Strom.'));
      expect(prompt, contains('Richtige Lösung: U = R · I'));
      expect(systemPrompt(), allOf(contains('Worum es geht:'), contains('Kern:'), contains('Beispiel:'), contains('Merke:')));
    });

    test('mit Bild als multimodale Nachricht', () async {
      final ai = aiReplying('Lektion');
      await ai.generateMiniLesson(question: 'F', correctAnswer: 'A', image: Uint8List.fromList([1, 2, 3]));
      final parts = userContent() as List;
      expect(parts.last['type'], 'image_url');
      expect(parts.last['image_url']['url'], startsWith('data:image/png;base64,'));
    });
  });

  group('AiService.socraticTurn', () {
    test('erster Schritt: Lösung nur als Hintergrund, falsche Antwort als Ausgangspunkt', () async {
      final ai = aiReplying('Was passiert mit dem Strom, wenn der Widerstand steigt?');
      final turn = await ai.socraticTurn(
        question: 'Wie hängen U, R und I zusammen?',
        correctAnswer: 'U = R · I',
        wrongAnswer: 'U = R / I',
      );
      expect(turn.solved, isFalse);
      expect(turn.reply, 'Was passiert mit dem Strom, wenn der Widerstand steigt?');
      final prompt = userContent() as String;
      expect(prompt, contains('nicht verraten'));
      expect(prompt, contains('Seine letzte falsche Antwort: U = R / I'));
      expect(prompt, contains('Beginne den Dialog'));
      expect(systemPrompt(), contains('[[GELÖST]]'));
    });

    test('Verlauf geht mit, Marker beendet den Dialog und verschwindet aus dem Text', () async {
      final ai = aiReplying('Genau! Mehr Widerstand, weniger Strom.\n[[GELÖST]]');
      final turn = await ai.socraticTurn(
        question: 'F',
        correctAnswer: 'A',
        history: const [
          (isUser: false, content: 'Was passiert mit I?'),
          (isUser: true, content: 'Er wird kleiner, weil R im Nenner steht'),
        ],
      );
      expect(turn.solved, isTrue);
      expect(turn.reply, 'Genau! Mehr Widerstand, weniger Strom.');
      final prompt = userContent() as String;
      expect(prompt, contains('Tutor: Was passiert mit I?'));
      expect(prompt, contains('Lernender: Er wird kleiner'));
      expect(prompt, contains('letzte Nachricht des Lernenden'));
    });
  });
}
