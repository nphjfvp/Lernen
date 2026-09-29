import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/daily_scheduler_service.dart';
import 'package:lernen/services/mastery_service.dart';
import 'package:lernen/services/mock_exam_service.dart';
import 'package:lernen/services/stage_gate_service.dart';
import 'package:lernen/services/stats_service.dart';
import 'package:lernen/services/task_folder_service.dart';
import 'package:lernen/services/weakness_service.dart';

/// Gewicht 0 = stummgeschaltet: die Frage kommt nirgends dran und zählt nicht.
Module _module(String id) => Module(
      id: id,
      name: id,
      colorValue: 0xFF000000,
      icon: '📘',
      examDate: null,
      createdAt: DateTime(2026, 1, 1),
    );

final _today = DateTime(2026, 9, 29, 10);

Flashcard _card(
  String id, {
  double weight = 1.0,
  int reps = 0,
  DateTime? due,
  String? group,
  int? level,
  QuestionType type = QuestionType.flashcard,
  int lapses = 0,
  int masteryBox = 0,
}) =>
    Flashcard(
      id: id,
      moduleId: 'm1',
      front: 'F$id',
      back: 'B$id',
      createdAt: DateTime(2026, 9, 1),
      due: due ?? DateTime(2026, 9, 1),
      weight: weight,
      reps: reps,
      stageGroup: group,
      stageLevel: level,
      type: type,
      lapses: lapses,
      masteryBox: masteryBox,
      lastReview: reps > 0 ? DateTime(2026, 9, 28) : null,
    );

void main() {
  group('Stufen-Ablauf', () {
    test('eine stumme Karte hält ihre Gruppe nicht auf: die nächste Stufe ist dran', () {
      final easy = _card('easy', group: 'Ohm', level: 0, weight: 0);
      final medium = _card('medium', group: 'Ohm', level: 1);
      final hard = _card('hard', group: 'Ohm', level: 2);
      final statuses = StageGate.statuses([easy, medium, hard]);
      expect(statuses['easy'], StageStatus.muted);
      expect(statuses.containsKey('medium'), isFalse); // aktiv
      expect(statuses['hard'], StageStatus.locked);
      expect(StageGate.learnable([easy, medium, hard]).map((c) => c.id), ['medium']);
    });

    test('auch eine einzelne Karte ohne Gruppe ist stumm; wieder einschalten macht sie aktiv', () {
      final single = _card('single', weight: 0);
      expect(StageGate.statuses([single])['single'], StageStatus.muted);
      expect(StageGate.learnable([single]), isEmpty);
      expect(StageGate.learnable([single.copyWithWeight(1.0)]).map((c) => c.id), ['single']);
      expect(StageStatus.muted.label, contains('nie dran'));
    });

    test('der Rückfall holt keine stumme leichtere Stufe zurück', () {
      final easy = _card('easy', group: 'Ohm', level: 0, weight: 0, reps: 3, masteryBox: 3);
      final medium = _card('medium', group: 'Ohm', level: 1, reps: 3, masteryBox: 3);
      final hard = _card('hard', group: 'Ohm', level: 2, reps: 3);
      final reopened = StageGate.reactivateEasier([easy, medium, hard], hard);
      expect(reopened.map((c) => c.id), ['medium']);
      // Nur die stumme wäre leichter: nichts kommt zurück.
      expect(StageGate.reactivateEasier([easy, hard], hard), isEmpty);
    });
  });

  group('Daily Quiz', () {
    test('stumme Karten sind weder neu noch fällig im Plan', () {
      final cards = [
        _card('new-ok'),
        _card('new-muted', weight: 0),
        _card('due-ok', reps: 2, due: DateTime(2026, 9, 28)),
        _card('due-muted', reps: 2, due: DateTime(2026, 9, 28), weight: 0),
      ];
      final plan = DailySchedulerService().buildPlan(modules: [_module('m1')], allCards: cards, now: _today);
      expect(plan.dueCards.map((c) => c.id), ['due-ok']);
      expect(plan.newCards.map((c) => c.id), ['new-ok']);
    });

    test('auch "Freiwillig weiterlernen" lässt sie aus', () {
      final cards = [
        _card('a'),
        _card('muted', weight: 0),
        _card('due-muted', reps: 1, due: DateTime(2026, 9, 30), weight: 0),
      ];
      final batch = DailySchedulerService()
          .buildExtraBatch(modules: [_module('m1')], allCards: cards, excludeIds: const {}, now: _today);
      expect([...batch.newCards, ...batch.dueCards].map((c) => c.id), ['a']);
    });
  });

  group('Ampel, Statistik, Schwachstellen, Probeklausur, Aufgaben', () {
    test('stumme Karten zählen nicht in die Ampel', () {
      final cards = [
        _card('red', reps: 2, masteryBox: 0),
        _card('muted-red', reps: 2, masteryBox: 0, weight: 0),
        _card('new'),
        _card('muted-new', weight: 0),
      ];
      final breakdown = MasteryService().breakdown(cards, now: _today);
      expect(breakdown[MasteryLevel.red], 1);
      expect(breakdown[MasteryLevel.neu], 1);
      expect(breakdown.values.fold<int>(0, (a, b) => a + b), 2);
      expect(MasteryService().levelFor(cards[1], stage: StageStatus.muted), MasteryLevel.neu);
    });

    test('Statistik je Fach ohne stumme Karten', () {
      final cards = [_card('a'), _card('b', reps: 1), _card('muted', weight: 0), _card('muted2', reps: 1, weight: 0)];
      final stats = StatsService().compute(modules: [_module('m1')], allCards: cards, now: _today);
      final module = stats.moduleStats.single;
      expect(module.totalCards, 2);
      expect(module.newCards, 1);
      expect(module.reviewedCards, 1);
    });

    test('das Fehlertagebuch führt keine stumme Karte', () {
      final weak = _card('weak', reps: 3, lapses: 2);
      final muted = _card('muted-weak', reps: 3, lapses: 2, weight: 0);
      expect(WeaknessService().rank([weak, muted], now: _today).map((w) => w.card.id), ['weak']);
    });

    test('die Probeklausur zieht keine stumme Karte', () {
      final cards = [_card('a'), _card('b'), _card('muted', weight: 0)];
      expect(MockExamService.eligible(cards).map((c) => c.id), ['a', 'b']);
      expect(
        MockExamService.selectQuestions(cards, count: 10).map((c) => c.id).toSet(),
        {'a', 'b'},
      );
    });

    test('eine stumme Lernaufgabe steht nicht im Aufgaben-Ordner', () {
      final task = _card('task', type: QuestionType.learn);
      final mutedTask = _card('muted-task', type: QuestionType.learn, weight: 0);
      expect(TaskFolderService.tasksOf([task, mutedTask]).map((c) => c.id), ['task']);
    });
  });
}
