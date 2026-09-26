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
  ///
  /// "Behandelt" heißt hier: abgehakt ODER Termin erreicht (siehe
  /// [LectureUnit.isCoveredOn]).
  Future<Map<String, bool>> loadAllCoveredById({DateTime? now}) async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.lectureUnits.find(db);
    final at = now ?? DateTime.now();
    return {for (final r in records) r.key: LectureUnit.fromMap(r.value).isCoveredOn(at)};
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

  /// Häkchen entfernen bei einer Einheit, deren Termin schon erreicht ist,
  /// entfernt auch den Termin – sonst bliebe sie über den Termin trotzdem
  /// "behandelt" und das Häkchen ließe sich nicht wirksam abwählen.
  /// Ein Termin in der Zukunft bleibt dabei stehen.
  Future<void> setCovered(String id, String moduleId, bool covered, {DateTime? now}) async {
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) => setCoveredIn(txn, id, covered, now: now ?? DateTime.now()));
    await loadForModule(moduleId);
  }

  /// Kern von [setCovered] – rein auf der DB, testbar.
  static Future<void> setCoveredIn(DatabaseClient client, String id, bool covered, {required DateTime now}) async {
    final ref = DatabaseService.lectureUnits.record(id);
    final current = await ref.get(client);
    if (current == null) return;
    final unit = LectureUnit.fromMap(current);
    final today = DateTime(now.year, now.month, now.day);
    final date = unit.scheduledDate;
    final dateReached = date != null && !DateTime(date.year, date.month, date.day).isAfter(today);
    await ref.update(client, {'covered': covered, if (!covered && dateReached) 'scheduledDate': null});
  }

  Future<void> setScheduledDate(String id, String moduleId, DateTime? date) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.lectureUnits.record(id).update(db, {'scheduledDate': date?.toIso8601String()});
    await loadForModule(moduleId);
  }

  /// Speichert mehrere Einheiten auf einmal (z.B. KI-Vorschläge oder Termine
  /// aus dem Vorlesungsplan).
  Future<void> saveAll(List<LectureUnit> units) async {
    if (units.isEmpty) return;
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) async {
      for (final u in units) {
        await DatabaseService.lectureUnits.record(u.id).put(txn, u.toMap());
      }
    });
    await loadForModule(units.first.moduleId);
  }

  Future<void> setNotes(String id, String moduleId, List<String> notes) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.lectureUnits.record(id).update(db, {'notes': notes});
    await loadForModule(moduleId);
  }

  /// Aufrufer, die Materialien/Konzepte/Karteikarten/Zusammenfassungen des
  /// Fachs im Speicher halten, müssen deren Repositories danach neu laden –
  /// deren `unitId` wurde hier direkt in der DB entfernt.
  Future<void> delete(String id, String moduleId) async {
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) => deleteCascade(txn, id));
    await loadForModule(moduleId);
  }

  /// Löscht die Einheit UND entfernt ihre Zuordnung aus allen Datensätzen,
  /// die auf sie zeigen – sonst hinge an Materialien eine unitId ohne
  /// existierende Einheit, und das Modul-Detail zeigte sie weder unter einer
  /// Einheit noch unter "Ohne Einheit" an.
  static Future<void> deleteCascade(DatabaseClient client, String unitId) async {
    final byUnit = Finder(filter: Filter.equals('unitId', unitId));
    final clearUnit = <String, Object?>{'unitId': FieldValue.delete};
    await DatabaseService.lectureUnits.record(unitId).delete(client);
    await DatabaseService.materials.update(client, clearUnit, finder: byUnit);
    await DatabaseService.concepts.update(client, clearUnit, finder: byUnit);
    await DatabaseService.summaries.update(client, clearUnit, finder: byUnit);
    await DatabaseService.flashcards.update(client, clearUnit, finder: byUnit);
  }
}
