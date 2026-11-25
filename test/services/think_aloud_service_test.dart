import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/think_aloud_service.dart';

Flashcard _card(String id, String module, {int reps = 0, DateTime? due, int box = 0, QuestionType type = QuestionType.flashcard}) =>
    Flashcard(
      id: id,
      moduleId: module,
      front: 'Frage $id',
      back: 'Antwort $id',
      createdAt: DateTime(2026, 1, int.parse(id.replaceAll(RegExp(r'\D'), '')) % 28 + 1),
      due: due ?? DateTime(2026, 3, 10),
      reps: reps,
      masteryBox: box,
      state: reps == 0 ? 'new' : 'review',
      stability: reps == 0 ? 0 : 5,
      lastReview: reps == 0 ? null : DateTime(2026, 3, 1),
      type: type,
    );

void main() {
  final now = DateTime(2026, 3, 5, 10);

  test('Auswahl: fällig vor wackelig vor neu, Fächer abwechselnd, nur offene Fragetypen', () {
    final cards = [
      _card('1', 'a'),
      _card('2', 'a', reps: 2, due: DateTime(2026, 3, 4)),
      _card('3', 'b', reps: 2, box: 1),
      _card('4', 'b'),
      _card('5', 'a', type: QuestionType.steps),
      _card('6', 'c'),
    ];
    final picked = ThinkAloudService.pick(cards, moduleIds: {'a', 'b'}, now: now, count: 10);
    expect(picked.map((c) => c.id), ['2', '3', '1', '4']);
  });

  test('KI-Urteil wird tolerant gelesen', () {
    final v = ThinkVerdict.fromJson({'status': 'falsch', 'reply': 'Schau auf das Vorzeichen.', 'level': '2', 'error': 'misconception'});
    expect(v.status, ThinkStatus.wrong);
    expect(v.level, 2);
    expect(v.error, ThinkError.misconception);
    final ok = ThinkVerdict.fromJson({'status': 'correct', 'reply': 'Stimmt.', 'level': 3});
    expect(ok.level, 0);
    expect(ThinkVerdict.fromJson({'reply': 'Weiter so?'}).status, ThinkStatus.thinking);
  });

  test('assessThinking schickt den ganzen Verlauf und liest das Urteil', () async {
    String? sent;
    final client = MockClient((request) async {
      sent = (jsonDecode(request.body)['messages'] as List).last['content'] as String;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({'status': 'thinking', 'reply': 'Was ist gegeben?', 'level': 1, 'read': 'rät'}),
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final ai = AiService(apiKey: 'k', model: 'm', client: client);
    final verdict = await ai.assessThinking(
      question: 'Was ist Leistung?',
      correctAnswer: 'Arbeit pro Zeit',
      turns: const [(user: true, text: 'hm irgendwas mit kraft')],
    );
    expect(sent, contains('hm irgendwas mit kraft'));
    expect(verdict.status, ThinkStatus.thinking);
    expect(verdict.level, 1);
  });
}
