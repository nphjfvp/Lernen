import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/learn_credit.dart';
import 'package:lernen/models/visual_task_type.dart';
import 'package:lernen/repositories/learn_credit_repository.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/sync_merge.dart';
import 'package:sembast/sembast_memory.dart';

Flashcard _card(String id, {String? conceptId, String? unitId}) => Flashcard(
  id: id,
  moduleId: 'm',
  conceptId: conceptId,
  unitId: unitId,
  front: 'F',
  back: 'B',
  createdAt: DateTime(2026),
  due: DateTime(2026),
);

void main() {
  test('Thema einer Karte: Konzept, sonst Aufgabentyp, sonst Einheit', () async {
    final db = await databaseFactoryMemory.openDatabase('learn_credit_${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(db.close);
    await DatabaseService.concepts.record('c1').put(db, {'id': 'c1', 'title': 'Variablen trennen'});
    await DatabaseService.lectureUnits.record('u1').put(db, {'id': 'u1', 'title': 'DGL 1. Ordnung'});
    await DatabaseService.visualTaskTypes
        .record('m')
        .put(
          db,
          VisualTaskCatalog(
            moduleId: 'm',
            types: const [
              VisualTaskType(id: 't', title: 'Substitution', cardIds: ['k2']),
            ],
            updatedAt: DateTime(2026),
          ).toMap(),
        );

    final concept = await LearnCreditRepository.topicOf(db, _card('k1', conceptId: 'c1', unitId: 'u1'));
    expect(concept, (key: 'concept:c1', title: 'Variablen trennen'));
    final type = await LearnCreditRepository.topicOf(db, _card('k2', unitId: 'u1'));
    expect(type, (key: 'type:m:Substitution', title: 'Substitution'));
    final unit = await LearnCreditRepository.topicOf(db, _card('k3', unitId: 'u1'));
    expect(unit, (key: 'unit:u1', title: 'DGL 1. Ordnung'));
    expect(await LearnCreditRepository.topicOf(db, _card('k4')), isNull);
  });

  test('Antworten verbuchen, Daily Quiz, Abgleich mit einem anderen Gerät', () async {
    final db = await databaseFactoryMemory.openDatabase('learn_credit_${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(db.close);
    await DatabaseService.concepts.record('c1').put(db, {'id': 'c1', 'title': 'Variablen trennen'});
    final now = DateTime(2026, 11, 14, 10);
    final card = _card('k1', conceptId: 'c1');

    expect(await LearnCreditRepository.recordAnswerIn(db, card, isCorrect: true, now: now), isNull);
    expect(await LearnCreditRepository.recordAnswerIn(db, card, isCorrect: true, now: now), 'Variablen trennen');
    await LearnCreditRepository.markDailyDoneIn(db, now: now);
    var credit = await LearnCreditRepository.loadFrom(db);
    expect(credit.topicsOn('2026-11-14'), ['Variablen trennen']);
    expect(credit.dailyDays, {'2026-11-14'});
    expect(LearnAllowance.of(credit, const LearnCreditRules(), now).unlimited, isTrue);

    // Auf dem Laptop gelernt – kommt per Abgleich dazu.
    final laptop = LearnCredit(
      earned: {'type:m:Substitution': EarnedTopic(day: '2026-11-14', title: 'Substitution', at: now)},
    );
    await LearnCreditRepository.mergeIn(db, laptop.toSyncMap());
    credit = await LearnCreditRepository.loadFrom(db);
    expect(credit.topicsOn('2026-11-14'), ['Variablen trennen', 'Substitution']);
    expect((await LearnCreditRepository.syncMapFrom(db))['dailyDays'], ['2026-11-14']);

    // Selbst bewertet „Nochmal“ zählt nicht als fehlerfrei.
    await LearnCreditRepository.saveRulesIn(db, const LearnCreditRules(correctInRow: 1));
    final other = _card('k9', conceptId: 'c2');
    expect(await LearnCreditRepository.recordAnswerIn(db, other, selfGrade: Grade.again, now: now), isNull);
    expect(await LearnCreditRepository.recordAnswerIn(db, other, selfGrade: Grade.good, now: now), 'Konzept');
  });

  test('Cloud-Abgleich vereint das Lernguthaben beider Geräte', () {
    Map<String, dynamic> payload(LearnCredit credit) => {
      'modules': const [],
      'flashcards': const [],
      'learnCredit': credit.toSyncMap(),
      'dataVersion': syncDataVersion,
    };
    final day = '2026-11-14';
    final phone = LearnCredit(
      earned: {'a': EarnedTopic(day: day, title: 'A', at: DateTime(2026, 11, 14, 9))},
    );
    final web = LearnCredit(
      earned: {'b': EarnedTopic(day: day, title: 'B', at: DateTime(2026, 11, 14, 11))},
      dailyDays: {day},
    );
    final result = mergeSyncPayloads(local: payload(phone), remote: payload(web), base: const {});
    final merged = LearnCredit.fromMap(result.payload['learnCredit']);
    expect(merged.topicsOn(day), ['A', 'B']);
    expect(merged.dailyDays, {day});
  });

  test('Regeln: die zuletzt geänderten gelten auf allen Geräten', () async {
    final phone = LearnCreditRules(enabled: true, freeMinutes: 20, updatedAt: DateTime(2026, 11, 14, 9));
    final windows = LearnCreditRules(freeMinutes: 45, updatedAt: DateTime(2026, 11, 14, 8));
    expect(LearnCreditRules.fromMap(LearnCreditRules.newer(phone.toMap(), windows.toMap())).freeMinutes, 20);
    expect(LearnCreditRules.fromMap(LearnCreditRules.newer(windows.toMap(), phone.toMap())).freeMinutes, 20);
    expect(LearnCreditRules.newer(null, windows.toMap())?['freeMinutes'], 45);
    expect(
      LearnCreditRules.fromMap(LearnCreditRules.newer(const LearnCreditRules().toMap(), windows.toMap())).freeMinutes,
      45,
      reason: 'nie geänderte Standardwerte verlieren',
    );

    final db = await databaseFactoryMemory.openDatabase('learn_credit_${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(db.close);
    await LearnCreditRepository.saveRulesIn(db, windows);
    await LearnCreditRepository.mergeRulesIn(db, phone.toMap());
    expect((await LearnCreditRepository.loadRulesFrom(db)).freeMinutes, 20);
    // Ältere Regeln vom anderen Gerät überschreiben nichts.
    await LearnCreditRepository.mergeRulesIn(db, windows.toMap());
    expect((await LearnCreditRepository.loadRulesFrom(db)).freeMinutes, 20);
    await LearnCreditRepository.mergeRulesIn(db, const LearnCreditRules(freeMinutes: 5).toMap());
    expect((await LearnCreditRepository.loadRulesFrom(db)).freeMinutes, 20);
  });
}
