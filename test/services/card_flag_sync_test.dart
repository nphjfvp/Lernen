import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/card_flag.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/card_flag_repository.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/sync_merge.dart';
import 'package:lernen/services/sync_merge_apply.dart';
import 'package:lernen/services/sync_service.dart';
import 'package:sembast/sembast_memory.dart';

Module _module(String id) =>
    Module(id: id, name: id, colorValue: 0xFF112233, icon: '📘', examDate: null, createdAt: DateTime(2026, 1, 1));

CardFlag _flag(String cardId, String moduleId, CardFlagKind kind, {String note = ''}) => CardFlag(
  cardId: cardId,
  moduleId: moduleId,
  kind: kind,
  note: note,
  front: 'Frage $cardId',
  createdAt: DateTime(2026, 10, 11),
);

void main() {
  test('Markierung: toMap/fromMap, unvollständige fallen weg', () {
    final f = _flag('c1', 'm', CardFlagKind.error, note: 'Option B ist auch richtig');
    final back = CardFlag.fromMap(f.toMap())!;
    expect(back.toMap(), f.toMap());
    expect(back.kindLabel, 'Fehler gemeldet');
    expect(CardFlag.fromMap({'id': 'x'}), isNull);
    expect(CardFlag.fromMap({'id': 'x', 'moduleId': 'm', 'kind': 'quatsch'})!.kind, CardFlagKind.saved);
  });

  test('Repository: setzen, ändern, entfernen, je Fach neueste zuerst', () async {
    final db = await databaseFactoryMemory.openDatabase('flags_repo');
    final repo = CardFlagRepository(openDatabase: () async => db);
    await repo.set(_flag('a', 'm1', CardFlagKind.saved));
    await repo.set(CardFlag(cardId: 'b', moduleId: 'm1', kind: CardFlagKind.error, createdAt: DateTime(2026, 10, 12)));
    await repo.set(_flag('c', 'm2', CardFlagKind.saved));
    expect(repo.list(moduleId: 'm1').map((f) => f.cardId), ['b', 'a']);
    expect(repo.list().length, 3);
    await repo.set(repo.flagOf('a')!.copyWith(kind: CardFlagKind.error, note: 'doch falsch'));

    final fresh = CardFlagRepository(openDatabase: () async => db);
    await fresh.load();
    expect(fresh.flagOf('a')!.note, 'doch falsch');
    await fresh.remove('a');
    expect(fresh.flagOf('a'), isNull);
    expect(await DatabaseService.cardFlags.record('a').get(db), isNull);
    await db.close();
  });

  test('Abgleich: Markierungen beider Geräte bleiben, ohne ihr Fach fallen sie weg', () async {
    final local = await databaseFactoryMemory.openDatabase('flags_local');
    final phone = await databaseFactoryMemory.openDatabase('flags_phone');
    for (final db in [local, phone]) {
      await DatabaseService.modules.record('m').put(db, _module('m').toMap());
    }
    await DatabaseService.cardFlags.record('pc').put(local, _flag('pc', 'm', CardFlagKind.error).toMap());
    await DatabaseService.cardFlags.record('handy').put(phone, _flag('handy', 'm', CardFlagKind.saved).toMap());
    // Auf dem Handy zu einem Fach, das es nicht (mehr) gibt.
    await DatabaseService.cardFlags.record('weg').put(phone, _flag('weg', 'gelöscht', CardFlagKind.saved).toMap());

    final payload = await buildSyncPayload(phone);
    expect(payload['dataVersion'], syncDataVersion);
    expect((payload['cardFlags'] as List), hasLength(2));
    await mergeRemoteIntoLocal(local, payload);
    final ids = [for (final r in await DatabaseService.cardFlags.find(local)) r.key]..sort();
    expect(ids, ['handy', 'pc']);
    await local.close();
    await phone.close();
  });
}
