import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  group('AiService.answerPageQuestion', () {
    test('sendet Text UND Bild als Content-Parts und liefert die Antwort zurück', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse('Die Antwort steht im zweiten Absatz.');
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);
      final imageBytes = Uint8List.fromList([1, 2, 3, 4]);

      final answer = await ai.answerPageQuestion(
        question: 'Was bedeutet dieses Symbol?',
        pageImageBytes: imageBytes,
        pageNumber: 3,
        totalPages: 12,
        documentText: 'Volltext des Dokuments.',
      );

      expect(answer, 'Die Antwort steht im zweiten Absatz.');
      expect(capturedBody!['model'], 'vision-model');
      final messages = capturedBody!['messages'] as List;
      final userContent = messages[1]['content'] as List;
      expect(userContent, hasLength(2));
      expect(userContent[0]['type'], 'text');
      expect((userContent[0]['text'] as String).contains('Seite: 3 von 12'), isTrue);
      expect((userContent[0]['text'] as String).contains('Was bedeutet dieses Symbol?'), isTrue);
      expect(userContent[1]['type'], 'image_url');
      expect(userContent[1]['image_url']['url'], 'data:image/png;base64,${base64Encode(imageBytes)}');
    });

    test('kürzt einen sehr langen Dokumenttext', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse('ok');
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      await ai.answerPageQuestion(
        question: 'Frage',
        pageImageBytes: Uint8List.fromList([0]),
        pageNumber: 1,
        totalPages: 1,
        documentText: 'x' * 50000,
      );

      final userContent = (capturedBody!['messages'] as List)[1]['content'] as List;
      final text = userContent[0]['text'] as String;
      expect(text.contains('gekürzt'), isTrue);
    });

    test('gibt den Gesprächsverlauf mit', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _chatResponse('ok');
      });
      final ai = AiService(apiKey: 'key', model: 'vision-model', client: client);

      await ai.answerPageQuestion(
        question: 'Und was folgt daraus?',
        pageImageBytes: Uint8List.fromList([0]),
        pageNumber: 1,
        totalPages: 1,
        documentText: 'Text',
        history: const [(isUser: true, content: 'Was zeigt das Diagramm?'), (isUser: false, content: 'Einen Kreislauf.')],
      );

      final text = ((capturedBody!['messages'] as List)[1]['content'] as List)[0]['text'] as String;
      expect(text.contains('Was zeigt das Diagramm?'), isTrue);
      expect(text.contains('Einen Kreislauf.'), isTrue);
    });
  });
}
