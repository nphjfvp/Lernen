import 'package:sembast/sembast.dart';

import '../models/daily_session_state.dart';
import '../models/flashcard.dart';
import '../services/database_service.dart';

/// Speichert den Fortschritt des heutigen Daily Quiz (siehe
/// [DailySessionState]). Geräte-lokal, nicht Teil des Cloud-Syncs.
class DailySessionRepository {
  static const _recordKey = 'daily_session';

  /// Stand für [now]; liegt nur ein Stand von einem früheren Tag vor, kommt
  /// ein leerer zurück.
  Future<DailySessionState> load(DateTime now) async {
    final db = await DatabaseService.instance.database;
    return loadFrom(db, now);
  }

  /// Heute im Daily Quiz eingeführte neue Karten je Fach (siehe
  /// DailySchedulerService.buildPlan).
  Future<Map<String, int>> introducedTodayByModule(List<Flashcard> allCards) async {
    final state = await load(DateTime.now());
    return state.introducedByModule({for (final c in allCards) c.id: c.moduleId});
  }

  Future<void> save(DailySessionState state) async {
    final db = await DatabaseService.instance.database;
    await saveIn(db, state);
  }

  static Future<DailySessionState> loadFrom(DatabaseClient client, DateTime now) async {
    final record = await DatabaseService.settings.record(_recordKey).get(client);
    if (record == null) return DailySessionState.empty(now);
    final state = DailySessionState.fromMap(Map<String, dynamic>.from(record));
    return state.isFor(now) ? state : DailySessionState.empty(now);
  }

  static Future<void> saveIn(DatabaseClient client, DailySessionState state) async {
    await DatabaseService.settings.record(_recordKey).put(client, state.toMap());
  }
}
