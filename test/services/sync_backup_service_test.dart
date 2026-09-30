import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/sync_backup_service.dart';
import 'package:lernen/services/sync_service.dart';
import 'package:sembast/sembast_memory.dart';

Module _module(String id, String name) =>
    Module(id: id, name: name, colorValue: 0xFF112233, icon: '📘', examDate: null, createdAt: DateTime(2026, 1, 1));

Flashcard _card(String id, String moduleId, String front) => Flashcard(
      id: id,
      moduleId: moduleId,
      front: front,
      back: 'Antwort',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
    );

void main() {
  late Database db;

  setUp(() async {
    db = await databaseFactoryMemory.openDatabase('backup_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() => db.close());

  Future<void> putModule(String id, String name) => DatabaseService.modules.record(id).put(db, _module(id, name).toMap());
  Future<void> putCard(String id, String moduleId, String front) =>
      DatabaseService.flashcards.record(id).put(db, _card(id, moduleId, front).toMap());

  Future<List<String>> moduleNames() async =>
      [for (final r in await DatabaseService.modules.find(db)) r.value['name'] as String]..sort();
  Future<List<String>> cardFronts() async =>
      [for (final r in await DatabaseService.flashcards.find(db)) r.value['front'] as String]..sort();

  test('ohne Fächer und Karten gibt es nichts zu sichern', () async {
    expect(await SyncBackupService.create(db, kind: SyncBackupService.kindPull, reason: 'x'), isNull);
    expect(await SyncBackupService.list(db), isEmpty);
  });

  test('Sicherung und Wiederherstellung: Stand zurück, vorher wird der jetzige gesichert', () async {
    await putModule('m1', 'Elektrotechnik');
    await putCard('c1', 'm1', 'Was ist Strom?');
    await putCard('c2', 'm1', 'Was ist Spannung?');
    final backup = await SyncBackupService.create(
      db,
      kind: SyncBackupService.kindPull,
      reason: 'Vor dem Herunterladen',
      now: DateTime(2026, 9, 29, 10),
    );
    expect(backup, isNotNull);
    expect((backup!.modules, backup.flashcards), (1, 2));
    expect(backup.bytes, greaterThan(0));

    // Danach wird alles anders (etwa ein Download eines alten Stands).
    await DatabaseService.flashcards.delete(db);
    await putModule('m2', 'Fremdes Fach');
    await putCard('c9', 'm2', 'Etwas ganz anderes');
    expect(await cardFronts(), ['Etwas ganz anderes']);

    await SyncBackupService.restore(db, backup.id, now: DateTime(2026, 9, 30, 8));
    expect(await moduleNames(), ['Elektrotechnik']);
    expect(await cardFronts(), ['Was ist Spannung?', 'Was ist Strom?']);

    final backups = await SyncBackupService.list(db);
    expect(backups.map((b) => b.kind), [SyncBackupService.kindRestore, SyncBackupService.kindPull]);
    expect(backups.first.reason, 'Vor dem Wiederherstellen');
    // Und das Wiederherstellen selbst lässt sich zurücknehmen.
    await SyncBackupService.restore(db, backups.first.id);
    expect(await moduleNames(), ['Elektrotechnik', 'Fremdes Fach']);
    expect(await cardFronts(), ['Etwas ganz anderes']);
  });

  test('lokale PDFs überleben die Wiederherstellung (die Sicherung enthält sie bewusst nicht)', () async {
    await putModule('m1', 'ET');
    await DatabaseService.materials.record('mat1').put(
          db,
          MaterialItem(
            id: 'mat1',
            moduleId: 'm1',
            fileName: 'Folien.pdf',
            kind: MaterialKind.slide,
            extractedText: 'Text',
            createdAt: DateTime(2026, 1, 1),
            filePath: '/lokal/Folien.pdf',
          ).toMap(),
        );
    final backup = await SyncBackupService.create(db, kind: SyncBackupService.kindDaily, reason: 'x');
    await SyncBackupService.restore(db, backup!.id);
    final material = await DatabaseService.materials.record('mat1').get(db);
    expect(material!['filePath'], '/lokal/Folien.pdf');
    expect(material['extractedText'], 'Text');
  });

  test('je Art werden nur die neuesten Sicherungen aufgehoben', () async {
    await putModule('m1', 'ET');
    for (var i = 0; i < 8; i++) {
      await SyncBackupService.create(
        db,
        kind: SyncBackupService.kindPull,
        reason: 'Download $i',
        now: DateTime(2026, 9, 1 + i),
      );
    }
    await SyncBackupService.create(db, kind: SyncBackupService.kindDaily, reason: 'täglich', now: DateTime(2026, 9, 1));
    final backups = await SyncBackupService.list(db);
    final pulls = backups.where((b) => b.kind == SyncBackupService.kindPull).toList();
    expect(pulls, hasLength(SyncBackupService.keepPerKind[SyncBackupService.kindPull]!));
    expect(pulls.first.reason, 'Download 7'); // neueste zuerst
    expect(pulls.last.reason, 'Download 3');
    expect(backups.where((b) => b.kind == SyncBackupService.kindDaily), hasLength(1));
    // Die Daten der aussortierten sind mit weg.
    expect(await DatabaseService.syncBackupData.count(db), backups.length);
  });

  test('tägliche Sicherung: höchstens alle 20 Stunden, ein Download-Backup zählt mit', () async {
    await putModule('m1', 'ET');
    final start = DateTime(2026, 9, 30, 8);
    expect(await SyncBackupService.ensureDaily(db, now: start), isNotNull);
    expect(await SyncBackupService.ensureDaily(db, now: start.add(const Duration(hours: 5))), isNull);
    expect(await SyncBackupService.ensureDaily(db, now: start.add(const Duration(hours: 21))), isNotNull);
    await SyncBackupService.create(
      db,
      kind: SyncBackupService.kindPull,
      reason: 'x',
      now: start.add(const Duration(hours: 30)),
    );
    expect(await SyncBackupService.ensureDaily(db, now: start.add(const Duration(hours: 40))), isNull);
  });

  test('eine fehlende Sicherung meldet einen Fehler, ohne etwas zu ändern', () async {
    await putModule('m1', 'ET');
    await expectLater(SyncBackupService.restore(db, 'gibt-es-nicht'), throwsA(isA<StateError>()));
    expect(await moduleNames(), ['ET']);
    expect(await SyncBackupService.list(db), isEmpty);
  });

  test('Sicherung löschen entfernt Kopf und Daten', () async {
    await putModule('m1', 'ET');
    final backup = await SyncBackupService.create(db, kind: SyncBackupService.kindDaily, reason: 'x');
    await SyncBackupService.delete(db, backup!.id);
    expect(await SyncBackupService.list(db), isEmpty);
    expect(await DatabaseService.syncBackupData.count(db), 0);
  });

  test('applySyncPayload/buildSyncPayload: ein Stand lässt sich auf ein anderes "Gerät" übertragen', () async {
    await putModule('m1', 'Von Windows');
    await putCard('c1', 'm1', 'Frage vom PC');
    final payload = await buildSyncPayload(db);

    final other = await databaseFactoryMemory.openDatabase('other_${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(other.close);
    await DatabaseService.modules.record('alt').put(other, _module('alt', 'Alter Stand').toMap());
    await other.transaction((txn) => applySyncPayload(txn, payload));
    expect([for (final r in await DatabaseService.modules.find(other)) r.value['name']], ['Von Windows']);
    expect([for (final r in await DatabaseService.flashcards.find(other)) r.value['front']], ['Frage vom PC']);
  });
}
