import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/module.dart';
import '../services/database_service.dart';

class ModuleRepository extends ChangeNotifier {
  List<Module> _modules = [];
  List<Module> get modules => List.unmodifiable(_modules);

  Future<void> load() async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.modules.find(db);
    _modules = records.map((r) => Module.fromMap(r.value)).toList()
      ..sort((a, b) {
        final ad = a.daysUntilExam;
        final bd = b.daysUntilExam;
        if (ad == null && bd == null) return a.name.compareTo(b.name);
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    notifyListeners();
  }

  Module? byId(String id) {
    for (final m in _modules) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> save(Module module) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.modules.record(module.id).put(db, module.toMap());
    await load();
  }

  Future<void> delete(String id) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.modules.record(id).delete(db);

    // Zugehörige Materialien/Konzepte/Karteikarten mit aufräumen.
    await DatabaseService.materials.delete(
      db,
      finder: Finder(filter: Filter.equals('moduleId', id)),
    );
    await DatabaseService.summaries.delete(
      db,
      finder: Finder(filter: Filter.equals('moduleId', id)),
    );
    await DatabaseService.concepts.delete(
      db,
      finder: Finder(filter: Filter.equals('moduleId', id)),
    );
    await DatabaseService.flashcards.delete(
      db,
      finder: Finder(filter: Filter.equals('moduleId', id)),
    );
    await load();
  }
}
