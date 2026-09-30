import 'package:sembast/sembast.dart';

import 'sync_merge.dart';

/// Der Basisstand für das Zusammenführen (siehe mergeSyncPayloads): je Sammlung
/// Kennung → Hash der Einträge, wie sie nach dem letzten Up- oder Download
/// waren. Geräte-lokal, wird nie synchronisiert.
class SyncBaseStore {
  static const _key = 'base';
  static final _store = stringMapStoreFactory.store('sync_base');

  /// Leer, solange dieses Gerät noch nie abgeglichen hat.
  static Future<SyncBase> load(DatabaseClient db) async {
    final record = await _store.record(_key).get(db);
    final raw = record?['hashes'];
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        '${e.key}': {
          if (e.value is Map) for (final h in (e.value as Map).entries) '${h.key}': '${h.value}',
        },
    };
  }

  /// Merkt sich [payload] (der gerade hochgeladene oder heruntergeladene
  /// Stand) als Basis.
  static Future<void> save(DatabaseClient db, Map<String, dynamic> payload) async {
    await _store.record(_key).put(db, {
      'hashes': hashesOfPayload(payload),
      'savedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> clear(DatabaseClient db) => _store.record(_key).delete(db);
}
