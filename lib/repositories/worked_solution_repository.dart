import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/worked_solution.dart';
import '../services/database_service.dart';

/// Vorgerechnete Aufgaben („Vorrechnen“) – nur lokal, liest immer frisch.
class WorkedSolutionRepository extends ChangeNotifier {
  /// [openDatabase]: nur für Tests.
  WorkedSolutionRepository({Future<DatabaseClient> Function()? openDatabase})
    : _open = openDatabase ?? (() => DatabaseService.instance.database);

  final Future<DatabaseClient> Function() _open;

  /// Die eines Fachs, neueste zuerst.
  Future<List<WorkedSolution>> forModule(String moduleId) async {
    final db = await _open();
    final records = await DatabaseService.workedSolutions.find(
      db,
      finder: Finder(filter: Filter.equals('moduleId', moduleId)),
    );
    final list = [for (final r in records) ?WorkedSolution.fromMap(r.value)];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Die zuletzt zu einer Rechenweg-Karte vorgerechnete Lösung.
  Future<WorkedSolution?> forCard(String cardId) async {
    final db = await _open();
    final records = await DatabaseService.workedSolutions.find(
      db,
      finder: Finder(filter: Filter.equals('cardId', cardId)),
    );
    final list = [for (final r in records) ?WorkedSolution.fromMap(r.value)];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.firstOrNull;
  }

  Future<void> save(WorkedSolution solution) async {
    final db = await _open();
    await DatabaseService.workedSolutions.record(solution.id).put(db, solution.toMap());
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final db = await _open();
    await DatabaseService.workedSolutions.record(id).delete(db);
    notifyListeners();
  }
}
