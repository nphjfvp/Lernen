import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/models/lab_photo.dart';
import 'package:lernen/repositories/lab_experiment_repository.dart';
import 'package:lernen/repositories/lab_photo_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/services/database_service.dart';
import 'package:sembast/sembast_memory.dart';

LabPhoto _photo(String id, String experimentId, {String moduleId = 'm1', int minute = 0}) => LabPhoto(
      id: id,
      experimentId: experimentId,
      moduleId: moduleId,
      base64: 'AAAA',
      createdAt: DateTime(2026, 9, 1, 10, minute),
      partId: 'p1',
      description: 'Protokoll',
    );

void main() {
  late Database db;
  late LabPhotoRepository repo;

  setUp(() async {
    db = await databaseFactoryMemory.openDatabase('lab_photos_${DateTime.now().microsecondsSinceEpoch}');
    repo = LabPhotoRepository(openDatabase: () async => db);
  });

  tearDown(() => db.close());

  test('Fotos eines Versuchs, nach Zeit sortiert; Zählen, Löschen, Version steigt', () async {
    await repo.add(_photo('b', 'e1', minute: 5));
    await repo.add(_photo('a', 'e1', minute: 1));
    await repo.add(_photo('c', 'e2'));
    expect((await repo.forExperiment('e1')).map((p) => p.id), ['a', 'b']);
    expect(await repo.countForExperiment('e2'), 1);
    final before = repo.version;
    await repo.delete('a');
    expect(repo.version, greaterThan(before));
    expect((await repo.forExperiment('e1')).map((p) => p.id), ['b']);
    await repo.deleteForExperiment('e1');
    expect(await repo.forExperiment('e1'), isEmpty);
    expect(await repo.countForExperiment('e2'), 1);
  });

  test('Foto: Speichern und Lesen, kaputte Felder verkraften', () {
    final photo = LabPhoto.fromMap(_photo('x', 'e1').toMap());
    expect(photo.partId, 'p1');
    expect(photo.description, 'Protokoll');
    final broken = LabPhoto.fromMap({'id': 'y'});
    expect(broken.experimentId, '');
    expect(broken.partId, isNull);
  });

  test('Versuch löschen entfernt seine Fotos', () async {
    final labs = LabExperimentRepository(openDatabase: () async => db);
    await labs.save(LabExperiment(id: 'e1', moduleId: 'm1', title: 'V', createdAt: DateTime(2026, 9, 1)));
    await repo.add(_photo('a', 'e1'));
    await repo.add(_photo('b', 'e2'));
    await labs.delete('e1');
    expect(await repo.forExperiment('e1'), isEmpty);
    expect(await repo.forExperiment('e2'), hasLength(1));
  });

  test('Fach löschen entfernt die Fotos des Fachs', () async {
    await DatabaseService.modules.record('m1').put(db, {'id': 'm1'});
    await repo.add(_photo('a', 'e1'));
    await repo.add(_photo('b', 'e2', moduleId: 'm2'));
    await db.transaction((txn) => ModuleRepository.deleteCascade(txn, 'm1'));
    expect(await repo.forExperiment('e1'), isEmpty);
    expect(await repo.forExperiment('e2'), hasLength(1));
  });
}
