import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/lecture_unit.dart';
import '../services/database_service.dart';

class LectureUnitRepository extends ChangeNotifier {
  final Map<String, List<LectureUnit>> _byModule = {};

  List<LectureUnit> forModule(String moduleId) =>
      List.unmodifiable(_byModule[moduleId] ?? const []);

  /// Alle Einheiten ALLER Fächer als Map unitId -> covered, direkt aus der
  /// DB (analog zu FlashcardRepository.loadAll) – Grundlage für den
  /// DailyScheduler-Filter (siehe DailyQuizScreen), der die Karteikarten
  /// aller Fächer gemeinsam einplant und deshalb nicht modulweise über den
  /// lokalen Cache abfragen kann.
  Future<Map<String, bool>> loadAllCoveredById() async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.lectureUnits.find(db);
    final units = records.map((r) => LectureUnit.fromMap(r.value));
    return {for (final u in units) u.id: u.covered};
  }

  Future<void> loadForModule(String moduleId) async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.lectureUnits.find(
      db,
      finder: Finder(
        filter: Filter.equals('moduleId', moduleId),
        sortOrders: [SortOrder('createdAt')],
      ),
    );
    _byModule[moduleId] = records.map((r) => LectureUnit.fromMap(r.value)).toList();
    notifyListeners();
  }

  Future<void> save(LectureUnit unit) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.lectureUnits.record(unit.id).put(db, unit.toMap());
    await loadForModule(unit.moduleId);
  }

  Future<void> setCovered(String id, String moduleId, bool covered) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.lectureUnits.record(id).update(db, {'covered': covered});
    await loadForModule(moduleId);
  }

  Future<void> delete(String id, String moduleId) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.lectureUnits.record(id).delete(db);
    await loadForModule(moduleId);
  }
}
