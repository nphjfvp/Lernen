import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/concept.dart';
import '../services/database_service.dart';

class ConceptRepository extends ChangeNotifier {
  final Map<String, List<Concept>> _byModule = {};

  List<Concept> forModule(String moduleId) =>
      List.unmodifiable(_byModule[moduleId] ?? const []);

  Future<void> loadForModule(String moduleId) async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.concepts.find(
      db,
      finder: Finder(
        filter: Filter.equals('moduleId', moduleId),
        sortOrders: [SortOrder('createdAt', false)],
      ),
    );
    _byModule[moduleId] =
        records.map((r) => Concept.fromMap(r.value)).toList();
    notifyListeners();
  }

  Future<void> saveAll(List<Concept> newConcepts) async {
    if (newConcepts.isEmpty) return;
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) async {
      for (final c in newConcepts) {
        await DatabaseService.concepts.record(c.id).put(txn, c.toMap());
      }
    });
    await loadForModule(newConcepts.first.moduleId);
  }

  Future<void> delete(String id, String moduleId) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.concepts.record(id).delete(db);
    await loadForModule(moduleId);
  }
}
