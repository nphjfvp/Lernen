import 'package:sembast/sembast.dart';

import '../services/database_service.dart';
import '../services/mock_exam_service.dart';

/// Verlauf der Probeklausuren (Note, Trefferquote), geräte-lokal.
class MockExamRepository {
  static const _recordKey = 'mock_exam_results';
  static const _maxResults = 100;

  Future<List<MockExamResult>> forModule(String moduleId) async {
    final db = await DatabaseService.instance.database;
    return (await loadFrom(db)).where((r) => r.moduleId == moduleId).toList();
  }

  Future<void> add(MockExamResult result) async {
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) => addIn(txn, result));
  }

  /// Neueste zuerst.
  static Future<List<MockExamResult>> loadFrom(DatabaseClient client) async {
    final record = await DatabaseService.settings.record(_recordKey).get(client);
    final list = (record?['results'] as List?) ?? const [];
    return [for (final m in list) MockExamResult.fromMap(Map<String, dynamic>.from(m as Map))];
  }

  static Future<void> addIn(DatabaseClient client, MockExamResult result) async {
    final existing = await loadFrom(client);
    final updated = [result, ...existing].take(_maxResults).map((r) => r.toMap()).toList();
    await DatabaseService.settings.record(_recordKey).put(client, {'results': updated});
  }
}
