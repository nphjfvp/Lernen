import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/material_item.dart';
import '../services/database_service.dart';

class MaterialRepository extends ChangeNotifier {
  final Map<String, List<MaterialItem>> _byModule = {};

  List<MaterialItem> forModule(String moduleId) =>
      List.unmodifiable(_byModule[moduleId] ?? const []);

  Future<void> loadForModule(String moduleId) async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.materials.find(
      db,
      finder: Finder(
        filter: Filter.equals('moduleId', moduleId),
        sortOrders: [SortOrder('createdAt', false)],
      ),
    );
    _byModule[moduleId] =
        records.map((r) => MaterialItem.fromMap(r.value)).toList();
    notifyListeners();
  }

  Future<void> save(MaterialItem item) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.materials.record(item.id).put(db, item.toMap());
    await loadForModule(item.moduleId);
  }

  Future<List<MaterialItem>> byIds(List<String> ids) async {
    final db = await DatabaseService.instance.database;
    final result = <MaterialItem>[];
    for (final id in ids) {
      final record = await DatabaseService.materials.record(id).get(db);
      if (record != null) result.add(MaterialItem.fromMap(record));
    }
    return result;
  }

  Future<void> delete(String id, String moduleId) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.materials.record(id).delete(db);
    await loadForModule(moduleId);
  }
}
