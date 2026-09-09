import 'package:flutter/foundation.dart' hide Summary;
import 'package:sembast/sembast.dart';

import '../models/summary.dart';
import '../services/database_service.dart';

class SummaryRepository extends ChangeNotifier {
  final Map<String, List<Summary>> _byModule = {};

  List<Summary> forModule(String moduleId) =>
      List.unmodifiable(_byModule[moduleId] ?? const []);

  Future<void> loadForModule(String moduleId) async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.summaries.find(
      db,
      finder: Finder(
        filter: Filter.equals('moduleId', moduleId),
        sortOrders: [SortOrder('createdAt', false)],
      ),
    );
    _byModule[moduleId] =
        records.map((r) => Summary.fromMap(r.value)).toList();
    notifyListeners();
  }

  Future<void> save(Summary summary) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.summaries.record(summary.id).put(db, summary.toMap());
    await loadForModule(summary.moduleId);
  }

  Future<void> delete(String id, String moduleId) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.summaries.record(id).delete(db);
    await loadForModule(moduleId);
  }
}
