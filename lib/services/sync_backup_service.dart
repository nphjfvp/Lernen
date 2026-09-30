import 'dart:convert';
import 'dart:typed_data';

import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import 'database_service.dart';
import 'sync_codec.dart';
import 'sync_service.dart';

/// Eine lokale Sicherung des Lernstands (nur die Kopfdaten – die Daten selbst
/// liegen getrennt, damit das Auflisten nichts Großes lädt).
class SyncBackup {
  const SyncBackup({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.reason,
    required this.modules,
    required this.flashcards,
    required this.bytes,
  });

  final String id;
  final DateTime createdAt;

  /// [SyncBackupService.kindPull] usw. – bestimmt, wie lange die Sicherung
  /// aufgehoben wird.
  final String kind;
  final String reason;
  final int modules;
  final int flashcards;

  /// Größe der komprimierten Daten.
  final int bytes;

  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'kind': kind,
        'reason': reason,
        'modules': modules,
        'flashcards': flashcards,
        'bytes': bytes,
      };

  factory SyncBackup.fromMap(Map<String, dynamic> map) => SyncBackup(
        id: (map['id'] ?? '').toString(),
        createdAt: DateTime.tryParse('${map['createdAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        kind: (map['kind'] ?? '').toString(),
        reason: (map['reason'] ?? '').toString(),
        modules: (map['modules'] as num?)?.toInt() ?? 0,
        flashcards: (map['flashcards'] as num?)?.toInt() ?? 0,
        bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      );
}

/// Sicherungen des Lernstands auf diesem Gerät – das Netz unter dem Cloud-Sync:
/// ein Download ersetzt alles Lokale, und ein Gerät mit altem Stand kann den
/// Cloud-Stand überschreiben. Vor jedem Download entsteht deshalb automatisch
/// eine Sicherung, dazu einmal täglich eine weitere; jede lässt sich in den
/// Einstellungen wiederherstellen. Liegen in derselben Datenbank (auch im Web),
/// werden nie synchronisiert und überleben einen Download.
class SyncBackupService {
  static const kindPull = 'pull';
  static const kindDaily = 'daily';
  static const kindRestore = 'restore';

  /// Wie viele Sicherungen je Art aufgehoben werden.
  static const keepPerKind = {kindPull: 5, kindDaily: 3, kindRestore: 2};

  /// Frühestens nach so langer Zeit gibt es die nächste tägliche Sicherung.
  static const dailyInterval = Duration(hours: 20);

  /// Sichert den aktuellen Lernstand. `null`, wenn es nichts zu sichern gibt
  /// (noch keine Fächer und Karten).
  static Future<SyncBackup?> create(
    Database db, {
    required String kind,
    required String reason,
    DateTime? now,
  }) async {
    final payload = await buildSyncPayload(db);
    final modules = (payload['modules'] as List).length;
    final flashcards = (payload['flashcards'] as List).length;
    if (modules == 0 && flashcards == 0) return null;
    final builder = BytesBuilder(copy: false);
    for (final part in SyncCodec.encode(payload)) {
      builder.add(part);
    }
    final compressed = builder.takeBytes();
    final backup = SyncBackup(
      id: const Uuid().v4(),
      createdAt: now ?? DateTime.now(),
      kind: kind,
      reason: reason,
      modules: modules,
      flashcards: flashcards,
      bytes: compressed.length,
    );
    await db.transaction((txn) async {
      await DatabaseService.syncBackups.record(backup.id).put(txn, backup.toMap());
      await DatabaseService.syncBackupData.record(backup.id).put(txn, {'data': base64Encode(compressed)});
      await _prune(txn, kind);
    });
    return backup;
  }

  /// Alle Sicherungen, neueste zuerst.
  static Future<List<SyncBackup>> list(DatabaseClient db) async {
    final records = await DatabaseService.syncBackups.find(db);
    final backups = [for (final r in records) SyncBackup.fromMap(r.value)];
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  static Future<void> delete(Database db, String id) async {
    await db.transaction((txn) async {
      await DatabaseService.syncBackups.record(id).delete(txn);
      await DatabaseService.syncBackupData.record(id).delete(txn);
    });
  }

  /// Stellt eine Sicherung wieder her. Vorher entsteht eine Sicherung des
  /// jetzigen Stands, damit sich auch das zurücknehmen lässt.
  static Future<void> restore(Database db, String id, {DateTime? now}) async {
    final record = await DatabaseService.syncBackupData.record(id).get(db);
    final encoded = record?['data'];
    if (encoded is! String) throw StateError('Die Sicherung ist nicht mehr vorhanden.');
    final data = SyncCodec.decode([Uint8List.fromList(base64Decode(encoded))]);
    checkUsablePayload(data);
    await create(db, kind: kindRestore, reason: 'Vor dem Wiederherstellen', now: now);
    await db.transaction((txn) => applySyncPayload(txn, data));
  }

  /// Legt die tägliche Sicherung an, wenn die letzte länger als
  /// [dailyInterval] her ist. Liefert die neue Sicherung oder `null`.
  static Future<SyncBackup?> ensureDaily(Database db, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final existing = await list(db);
    final lastAutomatic = existing.where((b) => b.kind == kindDaily || b.kind == kindPull).firstOrNull;
    if (lastAutomatic != null && at.difference(lastAutomatic.createdAt) < dailyInterval) return null;
    return create(db, kind: kindDaily, reason: 'Tägliche Sicherung', now: at);
  }

  static Future<void> _prune(DatabaseClient txn, String kind) async {
    final keep = keepPerKind[kind] ?? 3;
    final backups = [
      for (final r in await DatabaseService.syncBackups.find(txn))
        if (r.value['kind'] == kind) SyncBackup.fromMap(r.value),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final old in backups.skip(keep)) {
      await DatabaseService.syncBackups.record(old.id).delete(txn);
      await DatabaseService.syncBackupData.record(old.id).delete(txn);
    }
  }
}
