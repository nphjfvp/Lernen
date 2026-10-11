import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/visual_lesson.dart';
import '../services/database_service.dart';

/// Gespeicherte Lektionen aus „Visuell lernen“. Liest immer frisch aus der
/// Datenbank (kein Zwischenspeicher) – nach einem Abgleich mit der Cloud ist
/// so nichts veraltet.
class VisualLessonRepository extends ChangeNotifier {
  /// [openDatabase]: nur für Tests (z.B. eine Datenbank im Speicher).
  VisualLessonRepository({Future<DatabaseClient> Function()? openDatabase})
    : _open = openDatabase ?? (() => DatabaseService.instance.database);

  final Future<DatabaseClient> Function() _open;

  /// Die Lektionen eines Fachs, neueste zuerst.
  Future<List<VisualLesson>> forModule(String moduleId) async {
    final db = await _open();
    final records = await DatabaseService.visualLessons.find(
      db,
      finder: Finder(filter: Filter.equals('moduleId', moduleId)),
    );
    final lessons = [for (final r in records) ?VisualLesson.fromMap(r.value)];
    lessons.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return lessons;
  }

  /// Die neueste Lektion, die aus der Frage [cardId] erstellt wurde.
  Future<VisualLesson?> forCard(String cardId) async {
    final db = await _open();
    final records = await DatabaseService.visualLessons.find(
      db,
      finder: Finder(filter: Filter.equals('cardId', cardId)),
    );
    final lessons = [for (final r in records) ?VisualLesson.fromMap(r.value)];
    lessons.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return lessons.firstOrNull;
  }

  Future<void> save(VisualLesson lesson) async {
    final db = await _open();
    await DatabaseService.visualLessons.record(lesson.id).put(db, lesson.toMap());
    notifyListeners();
  }

  Future<void> saveAll(List<VisualLesson> lessons) async {
    final db = await _open();
    for (final l in lessons) {
      await DatabaseService.visualLessons.record(l.id).put(db, l.toMap());
    }
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final db = await _open();
    await DatabaseService.visualLessons.record(id).delete(db);
    notifyListeners();
  }
}
