import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/visual_course.dart';
import '../services/database_service.dart';

/// Lernpfade aus „Visuell lernen“ – liest immer frisch aus der Datenbank
/// (nach einem Abgleich ist so nichts veraltet).
class VisualCourseRepository extends ChangeNotifier {
  /// [openDatabase]: nur für Tests.
  VisualCourseRepository({Future<DatabaseClient> Function()? openDatabase})
    : _open = openDatabase ?? (() => DatabaseService.instance.database);

  final Future<DatabaseClient> Function() _open;

  /// Die Lernpfade eines Fachs, neueste zuerst.
  Future<List<VisualCourse>> forModule(String moduleId) async {
    final db = await _open();
    final records = await DatabaseService.visualCourses.find(
      db,
      finder: Finder(filter: Filter.equals('moduleId', moduleId)),
    );
    final courses = [for (final r in records) ?VisualCourse.fromMap(r.value)];
    courses.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return courses;
  }

  Future<VisualCourse?> byId(String id) async {
    final db = await _open();
    return VisualCourse.fromMap(await DatabaseService.visualCourses.record(id).get(db));
  }

  Future<void> save(VisualCourse course) async {
    final db = await _open();
    await DatabaseService.visualCourses.record(course.id).put(db, course.toMap());
    notifyListeners();
  }

  /// Löscht den Lernpfad samt seiner Lektionen.
  Future<void> delete(String id) async {
    final db = await _open();
    await DatabaseService.visualCourses.record(id).delete(db);
    await DatabaseService.visualLessons.delete(db, finder: Finder(filter: Filter.equals('courseId', id)));
    notifyListeners();
  }
}
