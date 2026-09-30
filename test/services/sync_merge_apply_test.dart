import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/sync_backup_service.dart';
import 'package:lernen/services/sync_base_store.dart';
import 'package:lernen/services/sync_merge_apply.dart';
import 'package:lernen/services/sync_service.dart';
import 'package:sembast/sembast_memory.dart';

Module _module(String id, String name) =>
    Module(id: id, name: name, colorValue: 0xFF112233, icon: '📘', examDate: null, createdAt: DateTime(2026, 1, 1));

Flashcard _card(String id, String moduleId, String front, {int reps = 0, DateTime? lastReview}) => Flashcard(
      id: id,
      moduleId: moduleId,
      front: front,
      back: 'Antwort',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      reps: reps,
      lastReview: lastReview,
    );

void main() {
  late Database local;
  late Database phone;
  var n = 0;

  setUp(() async {
    n++;
    local = await databaseFactoryMemory.openDatabase('merge_local_$n');
    phone = await databaseFactoryMemory.openDatabase('merge_phone_$n');
  });

  tearDown(() async {
    await local.close();
    await phone.close();
  });

  Future<void> putModule(Database db, String id, String name) =>
      DatabaseService.modules.record(id).put(db, _module(id, name).toMap());
  Future<void> putCard(Database db, Flashcard c) => DatabaseService.flashcards.record(c.id).put(db, c.toMap());
  Future<List<String>> moduleNames() async =>
      [for (final r in await DatabaseService.modules.find(local)) r.value['name'] as String]..sort();
  Future<Map<String, Flashcard>> cards() async => {
        for (final r in await DatabaseService.flashcards.find(local)) r.key: Flashcard.fromMap(r.value),
      };

  test('neuer Kurs vom Handy und ein alter Kurs vom PC: beides ist danach da, vorher gibt es eine Sicherung', () async {
    await putModule(local, 'alt', 'Alter Kurs');
    await putCard(local, _card('c1', 'alt', 'Alte Frage', reps: 6, lastReview: DateTime(2026, 9, 29)));
    await putModule(phone, 'neu', 'Neuer Kurs');
    await putCard(phone, _card('c9', 'neu', 'Neue Frage'));

    final result = await mergeRemoteIntoLocal(local, await buildSyncPayload(phone));

    expect(await moduleNames(), ['Alter Kurs', 'Neuer Kurs']);
    expect((await cards()).keys, unorderedEquals(['c1', 'c9']));
    expect(result.changedLocally, greaterThan(0));
    expect(result.changedRemotely, greaterThan(0));
    final backups = await SyncBackupService.list(local);
    expect(backups.map((b) => b.kind), [SyncBackupService.kindMerge]);
  });

  test('derselbe Kurs, am PC weiter gelernt, am Handy älter: der weitere Stand bleibt', () async {
    for (final db in [local, phone]) {
      await putModule(db, 'm', 'Kurs');
    }
    await putCard(local, _card('c', 'm', 'Frage', reps: 8, lastReview: DateTime(2026, 9, 29, 20)));
    await putCard(phone, _card('c', 'm', 'Frage', reps: 2, lastReview: DateTime(2026, 9, 20)));

    final result = await mergeRemoteIntoLocal(local, await buildSyncPayload(phone));

    expect((await cards())['c']!.reps, 8);
    expect(result.changedLocally, 0);
    expect(result.changedRemotely, greaterThan(0)); // die Cloud muss nachziehen
    expect(await SyncBackupService.list(local), isEmpty); // lokal ändert sich nichts → keine Sicherung
  });

  test('am Handy weiter gelernt: der Stand kommt auf den PC', () async {
    for (final db in [local, phone]) {
      await putModule(db, 'm', 'Kurs');
    }
    await putCard(local, _card('c', 'm', 'Frage', reps: 1, lastReview: DateTime(2026, 9, 1)));
    await putCard(phone, _card('c', 'm', 'Frage', reps: 5, lastReview: DateTime(2026, 9, 28)));

    await mergeRemoteIntoLocal(local, await buildSyncPayload(phone));
    expect((await cards())['c']!.reps, 5);
  });

  test('am Handy gelöscht (Basisstand bekannt): die Karte fällt auch am PC weg', () async {
    for (final db in [local, phone]) {
      await putModule(db, 'm', 'Kurs');
      await putCard(db, _card('c1', 'm', 'Bleibt'));
      await putCard(db, _card('c2', 'm', 'Wird gelöscht'));
    }
    await SyncBaseStore.save(local, await buildSyncPayload(local)); // beide hatten das zuletzt gemeinsam
    await DatabaseService.flashcards.record('c2').delete(phone);

    final result = await mergeRemoteIntoLocal(local, await buildSyncPayload(phone));
    expect((await cards()).keys, ['c1']);
    expect(result.changedLocally, greaterThan(0));
  });

  test('ohne Basisstand wird nie gelöscht, nur ergänzt', () async {
    await putModule(local, 'm', 'Kurs');
    await putCard(local, _card('c1', 'm', 'Nur hier'));
    await putModule(phone, 'm', 'Kurs');
    await putCard(phone, _card('c2', 'm', 'Nur dort'));

    await mergeRemoteIntoLocal(local, await buildSyncPayload(phone));
    expect((await cards()).keys, unorderedEquals(['c1', 'c2']));
  });

  test('lokal gelöscht, in der Cloud unverändert: bleibt gelöscht und die Cloud muss nachziehen', () async {
    for (final db in [local, phone]) {
      await putModule(db, 'm', 'Kurs');
      await putCard(db, _card('c1', 'm', 'Bleibt'));
      await putCard(db, _card('c2', 'm', 'Hier gelöscht'));
    }
    await SyncBaseStore.save(local, await buildSyncPayload(local));
    await DatabaseService.flashcards.record('c2').delete(local);

    final result = await mergeRemoteIntoLocal(local, await buildSyncPayload(phone));
    expect((await cards()).keys, ['c1']);
    expect(result.changedRemotely, greaterThan(0));
  });

  test('eine lokal vorhandene PDF überlebt das Zusammenführen', () async {
    await putModule(local, 'm', 'Kurs');
    await DatabaseService.materials.record('mat').put(local, {
      'id': 'mat',
      'moduleId': 'm',
      'kind': 'slides',
      'fileName': 'skript.pdf',
      'extractedText': 'Text',
      'uploadedAt': DateTime(2026, 1, 1).toIso8601String(),
      'filePath': '/pfad/skript.pdf',
    });
    await putModule(phone, 'm2', 'Anderer Kurs');

    await mergeRemoteIntoLocal(local, await buildSyncPayload(phone));
    final material = await DatabaseService.materials.record('mat').get(local);
    expect(material?['filePath'], '/pfad/skript.pdf');
    expect(await moduleNames(), ['Anderer Kurs', 'Kurs']);
  });

  test('ein unbrauchbarer Cloud-Stand verändert nichts', () async {
    await putModule(local, 'm', 'Kurs');
    await expectLater(mergeRemoteIntoLocal(local, {'nichts': true}), throwsA(isA<SyncException>()));
    expect(await moduleNames(), ['Kurs']);
  });

  group('Basisstand', () {
    test('speichern, laden, löschen', () async {
      expect(await SyncBaseStore.load(local), isEmpty);
      await putModule(local, 'm', 'Kurs');
      await putCard(local, _card('c1', 'm', 'F'));
      await SyncBaseStore.save(local, await buildSyncPayload(local));
      final base = await SyncBaseStore.load(local);
      expect(base['flashcards']!.keys, ['c1']);
      expect(base['modules']!.keys, ['m']);
      await SyncBaseStore.clear(local);
      expect(await SyncBaseStore.load(local), isEmpty);
    });

    test('eine wiederhergestellte Sicherung löscht den Basisstand (sonst sähe Neueres wie "gelöscht" aus)', () async {
      await putModule(local, 'm', 'Kurs');
      await putCard(local, _card('c1', 'm', 'F'));
      final backup = await SyncBackupService.create(local, kind: SyncBackupService.kindPull, reason: 'x');
      await SyncBaseStore.save(local, await buildSyncPayload(local));
      expect(await SyncBaseStore.load(local), isNotEmpty);

      await SyncBackupService.restore(local, backup!.id);
      expect(await SyncBaseStore.load(local), isEmpty);
    });
  });
}
