import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/concept.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/daily_scheduler_service.dart';
import 'package:lernen/services/prerequisite_gate.dart';

Concept _concept(String id, {List<String> needs = const []}) => Concept(
      id: id,
      moduleId: 'm1',
      title: 'Konzept $id',
      explanation: '',
      sourceMaterialIds: const [],
      createdAt: DateTime(2026),
      prerequisiteIds: needs,
    );

Flashcard _card(String id, String concept, {int reps = 0, int box = 0, bool priority = false}) => Flashcard(
      id: id,
      moduleId: 'm1',
      conceptId: concept,
      front: 'Frage $id',
      back: 'Antwort',
      createdAt: DateTime(2026),
      due: DateTime(2026, 3, 1),
      reps: reps,
      masteryBox: box,
      state: reps == 0 ? 'new' : 'review',
      stability: reps == 0 ? 0 : 30,
      lastReview: reps == 0 ? null : DateTime(2026, 3, 1),
      priorityIntroduction: priority,
    );

void main() {
  final now = DateTime(2026, 3, 1, 12);

  test('Konzept wartet, solange die Voraussetzung neu oder rot ist', () {
    final concepts = [_concept('a'), _concept('b', needs: ['a'])];
    expect(PrerequisiteGate.blockedConcepts(concepts, [_card('1', 'a'), _card('2', 'b')], now: now), {'b'});
    expect(PrerequisiteGate.blockedConcepts(concepts, [_card('1', 'a', reps: 1, box: 0), _card('2', 'b')], now: now), {'b'});
    expect(PrerequisiteGate.blockedConcepts(concepts, [_card('1', 'a', reps: 1, box: 1), _card('2', 'b')], now: now), isEmpty);
  });

  test('Kreise und Voraussetzungen ohne lernbare Karten blockieren nicht', () {
    final circle = [_concept('a', needs: ['b']), _concept('b', needs: ['a'])];
    expect(PrerequisiteGate.blockedConcepts(circle, [_card('1', 'a'), _card('2', 'b')], now: now), isEmpty);
    final concepts = [_concept('a'), _concept('b', needs: ['a'])];
    expect(PrerequisiteGate.blockedConcepts(concepts, [_card('2', 'b')], now: now), isEmpty);
  });

  test('Daily Quiz: neue Karten eines wartenden Konzepts kommen nicht, gezielt erstellte schon', () {
    final module = Module(id: 'm1', name: 'Physik', colorValue: 0xFF336699, icon: 'x', examDate: null, createdAt: DateTime(2026));
    final concepts = [_concept('a'), _concept('b', needs: ['a'])];
    final cards = [_card('1', 'a'), _card('2', 'b'), _card('3', 'b', priority: true)];
    final plan = DailySchedulerService().buildPlan(modules: [module], allCards: cards, now: now, concepts: concepts);
    expect(plan.newCards.map((c) => c.id).toSet(), {'1', '3'});
    final without = DailySchedulerService().buildPlan(modules: [module], allCards: cards, now: now);
    expect(without.newCards.map((c) => c.id).toSet(), {'1', '2', '3'});
  });

  test('KI-Antwort: ungültige Nummern und Selbstbezüge fallen weg', () {
    final links = AiService.parsePrerequisites({
      'links': [
        {'n': 1, 'needs': [0, 1, 7]},
        {'n': 9, 'needs': [0]},
      ],
    }, 3);
    expect(links, {1: [0]});
  });

  test('Concept: Voraussetzungen überstehen toMap/fromMap, ohne Selbstbezug', () {
    final c = Concept.fromMap({..._concept('b', needs: ['a', 'b']).toMap()});
    expect(c.prerequisiteIds, ['a']);
  });
}
