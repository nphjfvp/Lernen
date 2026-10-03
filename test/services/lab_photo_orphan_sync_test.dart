import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/models/lab_photo.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/sync_service.dart';
import 'package:sembast/sembast_memory.dart';

LabExperiment _experiment(String id) => LabExperiment.fromStructure(
      {
        'title': 'Versuch $id',
        'parts': [
          {
            'title': 'Teil 1',
            'steps': ['Aufbauen'],
          },
        ],
      },
      moduleId: 'm1',
      now: DateTime(2026, 9, 1),
      id: id,
    );

LabPhoto _photo(String id, String experimentId) => LabPhoto(
      id: id,
      experimentId: experimentId,
      moduleId: 'm1',
      base64: 'AAAA',
      createdAt: DateTime(2026, 9, 2),
    );

/// Code-Analyse 2: Fotos werden nicht synchronisiert – wird ein Versuch auf
/// einem anderen Gerät gelöscht, blieben seine Fotos hier als Altlast liegen.
void main() {
  late Database db;

  setUp(() async {
    db = await databaseFactoryMemory.openDatabase('orphan_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() => db.close());

  test('nach dem Abgleich fallen Fotos weg, deren Versuch es nicht mehr gibt', () async {
    final module = Module(
      id: 'm1',
      name: 'ET',
      colorValue: 0xFF112233,
      icon: '📘',
      examDate: null,
      createdAt: DateTime(2026, 1, 1),
    );
    await DatabaseService.modules.record('m1').put(db, module.toMap());
    for (final id in ['lab-1', 'lab-2']) {
      await DatabaseService.labExperiments.record(id).put(db, _experiment(id).toMap());
    }
    await DatabaseService.labPhotos.record('p1').put(db, _photo('p1', 'lab-1').toMap());
    await DatabaseService.labPhotos.record('p2').put(db, _photo('p2', 'lab-2').toMap());

    // Der andere Stand kennt nur noch "lab-1".
    await db.transaction((txn) => applySyncPayload(txn, {
          'modules': [module.toMap()],
          'labExperiments': [_experiment('lab-1').toMap()],
        }));

    expect(await DatabaseService.labExperiments.findKeys(db), ['lab-1']);
    expect(await DatabaseService.labPhotos.findKeys(db), ['p1']);
  });

  test('ohne Versuche bleibt auch kein Foto übrig', () async {
    final module = Module(
      id: 'm1',
      name: 'ET',
      colorValue: 0xFF112233,
      icon: '📘',
      examDate: null,
      createdAt: DateTime(2026, 1, 1),
    );
    await DatabaseService.labPhotos.record('p1').put(db, _photo('p1', 'lab-1').toMap());
    await db.transaction((txn) => applySyncPayload(txn, {
          'modules': [module.toMap()],
          'labExperiments': const [],
        }));
    expect(await DatabaseService.labPhotos.findKeys(db), isEmpty);
  });
}
