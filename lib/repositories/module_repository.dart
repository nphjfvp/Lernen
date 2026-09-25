import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/module.dart';
import '../services/database_service.dart';
import '../services/material_file_store.dart';

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
    final pdfPaths = await db.transaction((txn) => deleteCascade(txn, id));
    for (final path in pdfPaths) {
      await MaterialFileStore.delete(filePath: path);
    }
    await load();
  }

  /// Löscht das Fach samt ALLER zugehörigen Datensätze (auch Einheiten und
  /// Chat-Verlauf, die sonst verwaist in der DB liegen blieben). Liefert die
  /// Pfade gespeicherter PDF-Dateien der gelöschten Materialien zurück – das
  /// Löschen der Dateien selbst passiert außerhalb der DB-Transaktion.
  static Future<List<String>> deleteCascade(DatabaseClient client, String moduleId) async {
    final byModule = Finder(filter: Filter.equals('moduleId', moduleId));
    final materials = await DatabaseService.materials.find(client, finder: byModule);
    final pdfPaths = materials.map((r) => r.value['filePath']).whereType<String>().toList();

    await DatabaseService.modules.record(moduleId).delete(client);
    await DatabaseService.materials.delete(client, finder: byModule);
    await DatabaseService.summaries.delete(client, finder: byModule);
    await DatabaseService.concepts.delete(client, finder: byModule);
    await DatabaseService.flashcards.delete(client, finder: byModule);
    await DatabaseService.lectureUnits.delete(client, finder: byModule);
    await DatabaseService.chatMessages.delete(client, finder: byModule);
    return pdfPaths;
  }
}
