import 'package:sembast/sembast.dart';

import '../models/lecture_walk.dart';
import '../services/database_service.dart';

/// „Vorlesung mit Aufgabe“ je PDF – nur lokal, Schlüssel = Material-ID.
class LectureWalkRepository {
  /// [openDatabase]: nur für Tests.
  LectureWalkRepository({Future<DatabaseClient> Function()? openDatabase})
    : _open = openDatabase ?? (() => DatabaseService.instance.database);

  final Future<DatabaseClient> Function() _open;

  Future<LectureWalk?> load(String materialId) async =>
      LectureWalk.fromMap(await DatabaseService.lectureWalks.record(materialId).get(await _open()));

  Future<void> save(LectureWalk walk) async => DatabaseService.lectureWalks
      .record(walk.materialId)
      .put(await _open(), walk.copyWith(updatedAt: DateTime.now()).toMap());

  Future<void> delete(String materialId) async => DatabaseService.lectureWalks.record(materialId).delete(await _open());
}
