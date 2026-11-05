import 'package:sembast/sembast.dart';

import '../models/visual_task_type.dart';
import '../services/database_service.dart';

/// Aufgabentypen je Fach (siehe VisualTaskCatalog) – nur auf diesem Gerät,
/// sie lassen sich jederzeit neu erkennen.
class VisualTaskTypeRepository {
  Future<VisualTaskCatalog?> load(String moduleId) async {
    final db = await DatabaseService.instance.database;
    return VisualTaskCatalog.fromMap(await DatabaseService.visualTaskTypes.record(moduleId).get(db));
  }

  Future<void> save(VisualTaskCatalog catalog) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.visualTaskTypes.record(catalog.moduleId).put(db, catalog.toMap());
  }
}
