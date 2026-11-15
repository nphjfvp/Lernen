import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/learn_credit.dart';
import '../models/unlock_block.dart';
import '../services/database_service.dart';
import 'learn_credit_repository.dart';

/// Entsperr-Blöcke (reisen mit dem Abgleich). Gutschriften landen im
/// Lernguthaben ([LearnCredit.bonus]) – je Block und Art nur einmal.
class UnlockBlockRepository {
  /// [openDatabase]: nur für Tests.
  UnlockBlockRepository({Future<DatabaseClient> Function()? openDatabase})
    : _open = openDatabase ?? (() => DatabaseService.instance.database);

  final Future<DatabaseClient> Function() _open;

  /// Meldet Änderungen (Liste neu laden).
  static final changes = ValueNotifier<int>(0);

  Future<List<UnlockBlock>> all() async {
    final records = await DatabaseService.unlockBlocks.find(await _open());
    final list = [for (final r in records) ?UnlockBlock.fromMap(r.value)];
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Future<List<UnlockBlock>> forModule(String moduleId) async => [
    for (final b in await all())
      if (b.moduleId == moduleId) b,
  ];

  Future<void> save(UnlockBlock block) async {
    await DatabaseService.unlockBlocks.record(block.id).put(await _open(), block.toMap());
    changes.value++;
  }

  Future<void> delete(String id) async {
    await DatabaseService.unlockBlocks.record(id).delete(await _open());
    changes.value++;
  }

  /// Gutschrift für [block]: abgeschlossene Übungseinheit und/oder beide
  /// Aufgaben ohne Hilfe gelöst (zusammen höchstens [LearnCreditRules.blockMinutes]).
  /// Liefert die neu gutgeschriebenen Minuten und den gespeicherten Block.
  Future<({int minutes, UnlockBlock block})> reward(UnlockBlock block, {DateTime? now}) async {
    final db = await _open();
    final rules = await LearnCreditRepository.loadRulesFrom(db);
    final when = now ?? DateTime.now();
    var credit = await LearnCreditRepository.loadFrom(db);
    var updated = block;
    var minutes = 0;
    if (block.practice?.completed == true && !block.rewardedPractice && !block.solved) {
      final m = rules.practiceMinutes.clamp(0, rules.blockMinutes);
      credit = credit.withBonus('unlock:${block.id}:practice', m, when, rules.dayStartHour);
      updated = updated.copyWith(rewardedPractice: true);
      minutes += m;
    }
    if (block.solved && !block.rewardedSolved) {
      final already = updated.rewardedPractice ? rules.practiceMinutes.clamp(0, rules.blockMinutes) : 0;
      final m = rules.blockMinutes - already;
      credit = credit.withBonus('unlock:${block.id}:solved', m, when, rules.dayStartHour);
      updated = updated.copyWith(rewardedSolved: true);
      minutes += m;
    }
    if (minutes > 0) {
      await LearnCreditRepository.saveIn(db, credit);
      LearnCreditRepository.changes.value++;
      LearnCreditRepository.localChanges.value++;
    }
    if (!identical(updated, block)) await save(updated);
    return (minutes: minutes, block: updated);
  }
}
