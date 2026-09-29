import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/lab_experiment.dart';
import '../services/database_service.dart';

/// Alle Laborversuche (siehe [LabExperiment]). Es sind wenige und sie werden
/// überall gebraucht (Kalender, Startseite, Fach), deshalb hält das Repository
/// sie komplett im Speicher; [save] aktualisiert den Speicher sofort und
/// schreibt dann in die Datenbank – Eingaben im Versuch (Antworten, Häkchen)
/// bleiben so flüssig.
class LabExperimentRepository extends ChangeNotifier {
  /// [openDatabase]: nur für Tests (z.B. eine Datenbank im Speicher).
  LabExperimentRepository({Future<DatabaseClient> Function()? openDatabase})
      : _open = openDatabase ?? (() => DatabaseService.instance.database);

  final Future<DatabaseClient> Function() _open;
  List<LabExperiment> _all = [];

  List<LabExperiment> get all => List.unmodifiable(_all);

  /// Die Versuche eines Fachs: mit Termin nach Datum, dann die ohne.
  List<LabExperiment> forModule(String moduleId) {
    final list = [for (final e in _all) if (e.moduleId == moduleId) e];
    list.sort((a, b) {
      final da = a.labDate, db = b.labDate;
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  LabExperiment? byId(String id) {
    for (final e in _all) {
      if (e.id == id) return e;
    }
    return null;
  }

  static Future<List<LabExperiment>> loadFrom(DatabaseClient client) async =>
      [for (final r in await DatabaseService.labExperiments.find(client)) LabExperiment.fromMap(r.value)];

  Future<void> loadAll() async {
    final db = await _open();
    _all = await loadFrom(db);
    notifyListeners();
  }

  Future<void> save(LabExperiment experiment) async {
    final index = _all.indexWhere((e) => e.id == experiment.id);
    final next = [..._all];
    if (index < 0) {
      next.add(experiment);
    } else {
      next[index] = experiment;
    }
    _all = next;
    notifyListeners();
    final db = await _open();
    await DatabaseService.labExperiments.record(experiment.id).put(db, experiment.toMap());
  }

  Future<void> delete(String id) async {
    _all = [for (final e in _all) if (e.id != id) e];
    notifyListeners();
    final db = await _open();
    await DatabaseService.labExperiments.record(id).delete(db);
  }
}
