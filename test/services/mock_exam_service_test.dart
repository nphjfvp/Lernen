import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/mock_exam_service.dart';

Flashcard _card(String id, {String? unitId, bool priority = false}) => Flashcard(
      id: id,
      moduleId: 'm1',
      front: 'F$id',
      back: 'B$id',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      unitId: unitId,
      priorityIntroduction: priority,
    );

void main() {
  group('MockExamService.germanGrade', () {
    test('Hochschulskala: 95 % → 1,0, 50 % → 4,0, darunter 5,0', () {
      expect(MockExamService.germanGrade(1.0), 1.0);
      expect(MockExamService.germanGrade(0.95), 1.0);
      expect(MockExamService.germanGrade(0.9), 1.3);
      expect(MockExamService.germanGrade(0.7), 2.7);
      expect(MockExamService.germanGrade(0.5), 4.0);
      expect(MockExamService.germanGrade(0.49), 5.0);
      expect(MockExamService.germanGrade(0), 5.0);
    });

    test('14 von 20 ergibt exakt 2,7 (keine Rundungsfehler an der Grenze)', () {
      expect(MockExamService.germanGrade(14 / 20), 2.7);
      expect(MockExamService.formatGrade(2.7), '2,7');
    });
  });

  group('MockExamService.selectQuestions', () {
    test('nur behandelter Stoff, höchstens count Fragen', () {
      final cards = [
        _card('a', unitId: 'u1'),
        _card('b', unitId: 'u2'),
        _card('c'),
        _card('d', unitId: 'u2', priority: true),
      ];
      final picked = MockExamService.selectQuestions(
        cards,
        count: 10,
        unitCoveredById: const {'u1': true, 'u2': false},
        random: Random(1),
      );
      expect(picked.map((c) => c.id).toSet(), {'a', 'c', 'd'});
      expect(
        MockExamService.selectQuestions(cards, count: 2, random: Random(1)),
        hasLength(2),
      );
    });

    test('Fragenanzahl-Optionen werden auf das Verfügbare gedeckelt', () {
      expect(MockExamService.questionCountOptions(50), [10, 20, 30]);
      expect(MockExamService.questionCountOptions(15), [10, 15]);
      expect(MockExamService.questionCountOptions(4), [4]);
      expect(MockExamService.questionCountOptions(0), isEmpty);
    });
  });

  test('unitBreakdown: schwächste Einheit zuerst', () {
    final questions = [
      _card('a', unitId: 'u1'),
      _card('b', unitId: 'u1'),
      _card('c', unitId: 'u2'),
      _card('d', unitId: 'u2'),
      _card('e'),
    ];
    final scores = MockExamService.unitBreakdown(questions, {
      'a': true,
      'b': true,
      'c': false,
      'd': true,
      'e': false,
    });
    expect(scores.map((s) => s.unitId).toList(), [null, 'u2', 'u1']);
    expect(scores.last.correct, 2);
  });

  test('MockExamResult übersteht toMap/fromMap', () {
    final result = MockExamResult(
      moduleId: 'm1',
      takenAt: DateTime(2026, 9, 25, 14),
      correct: 17,
      total: 20,
      durationSeconds: 1234,
    );
    final restored = MockExamResult.fromMap(result.toMap());
    expect(restored.correct, 17);
    expect(restored.total, 20);
    expect(restored.grade, 1.7);
    expect(restored.takenAt, DateTime(2026, 9, 25, 14));
  });
}
