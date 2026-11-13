import 'package:sembast/sembast.dart';

import '../models/model_test_result.dart';
import '../services/database_service.dart';

/// Ergebnisse der Modell-Tests. Nur zum Vergleichen gedacht: ohne „Behalten“
/// verschwindet ein Ergebnis nach [ModelTestResult.keepFor]. Bleibt auf dem
/// Gerät (wird nicht synchronisiert).
class ModelTestRepository {
  ModelTestRepository({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Alle noch gültigen Ergebnisse, jüngste zuerst; abgelaufene werden dabei
  /// gelöscht. Mit [kind] nur die eines Tests.
  Future<List<ModelTestResult>> all({ModelTestKind? kind}) async {
    final db = await DatabaseService.instance.database;
    final now = _clock();
    final records = await DatabaseService.modelTests.find(db);
    final results = <ModelTestResult>[];
    final expired = <String>[];
    for (final r in records) {
      final result = ModelTestResult.fromMap(r.value);
      if (result == null || result.isExpired(now)) {
        expired.add(r.key);
      } else if (kind == null || result.kind == kind) {
        results.add(result);
      }
    }
    if (expired.isNotEmpty) await DatabaseService.modelTests.records(expired).delete(db);
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  Future<void> save(ModelTestResult result) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.modelTests.record(result.id).put(db, result.toMap());
  }

  /// Dauerhaft behalten (true) oder wieder nach 30 Minuten löschen.
  Future<void> setPinned(String id, bool pinned) async {
    final db = await DatabaseService.instance.database;
    final record = DatabaseService.modelTests.record(id);
    final current = ModelTestResult.fromMap(await record.get(db));
    if (current == null) return;
    await record.put(db, current.copyWith(pinned: pinned).toMap());
  }

  Future<void> delete(String id) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.modelTests.record(id).delete(db);
  }

  /// Löscht alle Ergebnisse eines Tests, behaltene eingeschlossen.
  Future<void> clear(ModelTestKind kind) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.modelTests.delete(db, finder: Finder(filter: Filter.equals('kind', kind.name)));
  }
}
