import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../models/unsupported_task.dart';
import '../services/database_service.dart';

/// Die Sammelliste "Noch nicht interaktiv" (alle Fächer, wird mit
/// synchronisiert und beim Löschen eines Fachs mit gelöscht).
class UnsupportedTaskRepository extends ChangeNotifier {
  List<UnsupportedTask> _all = const [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Neueste zuerst.
  List<UnsupportedTask> get all => List.unmodifiable(_all);

  List<UnsupportedTask> forModule(String moduleId) => [for (final t in _all) if (t.moduleId == moduleId) t];

  Future<void> load() async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.unsupportedTasks.find(db);
    _all = records.map((r) => UnsupportedTask.fromMap(r.value)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _loaded = true;
    notifyListeners();
  }

  /// Fügt eine Aufgabe hinzu – steht dieselbe Aufgabe (gleicher Text im
  /// selben Fach) schon da, wird nur Begründung/Bedienart aktualisiert.
  /// Liefert den gespeicherten Eintrag.
  Future<UnsupportedTask> add({
    required String moduleId,
    required String text,
    String reason = '',
    String needs = '',
    String? sourceMaterialId,
    int? sourcePage,
    DateTime? now,
  }) async {
    if (!_loaded) await load();
    final key = UnsupportedTask.sameKey(text);
    final existing = _all.where((t) => t.moduleId == moduleId && UnsupportedTask.sameKey(t.text) == key).firstOrNull;
    final entry = existing != null
        ? existing.copyWith(
            reason: reason.trim().isEmpty ? null : reason.trim(),
            needs: needs.trim().isEmpty ? null : needs.trim(),
            sourceMaterialId: sourceMaterialId,
            sourcePage: sourcePage,
          )
        : UnsupportedTask(
            id: const Uuid().v4(),
            moduleId: moduleId,
            text: text.trim(),
            reason: reason.trim(),
            needs: needs.trim(),
            sourceMaterialId: sourceMaterialId,
            sourcePage: sourcePage,
            createdAt: now ?? DateTime.now(),
          );
    final db = await DatabaseService.instance.database;
    await DatabaseService.unsupportedTasks.record(entry.id).put(db, entry.toMap());
    await load();
    return entry;
  }

  Future<void> delete(String id) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.unsupportedTasks.record(id).delete(db);
    await load();
  }

  /// Entfernt die Einträge mit diesem Aufgabentext (z.B. nachdem die Aufgabe
  /// doch noch interaktiv gespeichert wurde).
  Future<void> removeText(String moduleId, String text) async {
    if (!_loaded) await load();
    final key = UnsupportedTask.sameKey(text);
    final db = await DatabaseService.instance.database;
    for (final t in _all.where((t) => t.moduleId == moduleId && UnsupportedTask.sameKey(t.text) == key)) {
      await DatabaseService.unsupportedTasks.record(t.id).delete(db);
    }
    await load();
  }

  Future<void> clear({String? moduleId}) async {
    final db = await DatabaseService.instance.database;
    for (final t in moduleId == null ? _all : forModule(moduleId)) {
      await DatabaseService.unsupportedTasks.record(t.id).delete(db);
    }
    await load();
  }
}
