import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/services/database_service.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await databaseFactoryMemory.openDatabase('cascade_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() => db.close());

  group('LectureUnitRepository.deleteCascade', () {
    test('löscht die Einheit und entfernt ihre Zuordnung überall, ohne andere Einheiten anzufassen', () async {
      await DatabaseService.lectureUnits.record('u1').put(db, {'id': 'u1', 'moduleId': 'm1'});
      await DatabaseService.materials.record('mat1').put(db, {'id': 'mat1', 'unitId': 'u1'});
      await DatabaseService.materials.record('mat2').put(db, {'id': 'mat2', 'unitId': 'u2'});
      await DatabaseService.concepts.record('c1').put(db, {'id': 'c1', 'unitId': 'u1'});
      await DatabaseService.summaries.record('s1').put(db, {'id': 's1', 'unitId': 'u1'});
      await DatabaseService.flashcards.record('f1').put(db, {'id': 'f1', 'unitId': 'u1'});

      await db.transaction((txn) => LectureUnitRepository.deleteCascade(txn, 'u1'));

      expect(await DatabaseService.lectureUnits.record('u1').get(db), isNull);
      expect((await DatabaseService.materials.record('mat1').get(db))!['unitId'], isNull);
      expect((await DatabaseService.materials.record('mat2').get(db))!['unitId'], 'u2');
      expect((await DatabaseService.concepts.record('c1').get(db))!['unitId'], isNull);
      expect((await DatabaseService.summaries.record('s1').get(db))!['unitId'], isNull);
      expect((await DatabaseService.flashcards.record('f1').get(db))!['unitId'], isNull);
    });
  });

  group('ModuleRepository.deleteCascade', () {
    test('entfernt auch Einheiten und Chat-Verlauf und liefert PDF-Pfade zum Aufräumen', () async {
      await DatabaseService.modules.record('m1').put(db, {'id': 'm1'});
      await DatabaseService.materials.record('mat1').put(db, {'id': 'mat1', 'moduleId': 'm1', 'filePath': '/pdf/a.pdf'});
      await DatabaseService.materials.record('mat2').put(db, {'id': 'mat2', 'moduleId': 'm1'});
      await DatabaseService.lectureUnits.record('u1').put(db, {'id': 'u1', 'moduleId': 'm1'});
      await DatabaseService.chatMessages.record('ch1').put(db, {'id': 'ch1', 'moduleId': 'm1'});
      await DatabaseService.flashcards.record('f1').put(db, {'id': 'f1', 'moduleId': 'm1'});
      await DatabaseService.flashcards.record('f2').put(db, {'id': 'f2', 'moduleId': 'm2'});

      final paths = await db.transaction((txn) => ModuleRepository.deleteCascade(txn, 'm1'));

      expect(paths, ['/pdf/a.pdf']);
      expect(await DatabaseService.modules.record('m1').get(db), isNull);
      expect(await DatabaseService.materials.count(db), 0);
      expect(await DatabaseService.lectureUnits.count(db), 0);
      expect(await DatabaseService.chatMessages.count(db), 0);
      expect(await DatabaseService.flashcards.record('f1').get(db), isNull);
      expect(await DatabaseService.flashcards.record('f2').get(db), isNotNull);
    });
  });
}
