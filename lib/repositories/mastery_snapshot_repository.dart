import 'package:sembast/sembast.dart';

import '../models/mastery_snapshot.dart';
import '../services/database_service.dart';

/// Speichert/lädt die täglichen Ampel-Schnappschüsse (siehe MasterySnapshot)
/// – bewusst kein ChangeNotifier: wird nur einmalig beim Laden von
/// StatsScreen aufgerufen, kein reaktiver State nötig.
class MasterySnapshotRepository {
  /// Schreibt (bzw. überschreibt) den Schnappschuss für [snapshot.date] –
  /// mehrfaches Aufrufen am selben Tag ist sicher (idempotent), da
  /// [MasterySnapshot.dateKey] als Datensatz-Schlüssel dient.
  Future<void> recordToday(MasterySnapshot snapshot) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.masterySnapshots.record(snapshot.dateKey).put(db, snapshot.toMap());
  }

  /// Alle Schnappschüsse der letzten [days] Tage (inkl. heute, falls
  /// vorhanden), älteste zuerst.
  Future<List<MasterySnapshot>> loadRecent(int days, {DateTime? now}) async {
    final db = await DatabaseService.instance.database;
    final today = now ?? DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day - days);
    final records = await DatabaseService.masterySnapshots.find(
      db,
      finder: Finder(
        filter: Filter.greaterThanOrEquals('date', cutoff.toIso8601String()),
        sortOrders: [SortOrder('date')],
      ),
    );
    return records.map((r) => MasterySnapshot.fromMap(r.value)).toList();
  }
}
