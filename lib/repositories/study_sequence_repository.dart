import 'package:sembast/sembast.dart';

import '../models/study_sequence.dart';
import '../services/database_service.dart';

/// Stand von „Der Reihe nach“ je Einheit/PDF – wird mit synchronisiert.
class StudySequenceRepository {
  Future<StudySequenceProgress> load(String moduleId, StudySequenceSource source) async {
    final db = await DatabaseService.instance.database;
    final id = '$moduleId|${source.key}';
    return StudySequenceProgress.fromMap(await DatabaseService.studySequences.record(id).get(db)) ??
        StudySequenceProgress(moduleId: moduleId, key: source.key, updatedAt: DateTime.now());
  }

  /// Alle gespeicherten Stände (für „Weiter lernen“).
  Future<List<StudySequenceProgress>> all() async {
    final db = await DatabaseService.instance.database;
    return [for (final r in await DatabaseService.studySequences.find(db)) ?StudySequenceProgress.fromMap(r.value)];
  }

  Future<void> save(StudySequenceProgress progress) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.studySequences.record(progress.id).put(db, progress.toMap());
  }
}
