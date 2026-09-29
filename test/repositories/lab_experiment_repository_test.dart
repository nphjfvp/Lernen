import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/repositories/lab_experiment_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/module_export_service.dart';
import 'package:lernen/models/module.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sembast/sembast_memory.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

LabExperiment _lab(String id, String moduleId, {DateTime? labDate, DateTime? createdAt, List<String> theory = const []}) =>
    LabExperiment(
      id: id,
      moduleId: moduleId,
      title: 'Versuch $id',
      createdAt: createdAt ?? DateTime(2026, 9, 1),
      labDate: labDate,
      theoryMaterialIds: theory,
      prep: const [LabQuestion(id: 'q', number: '1', text: 'Frage', answer: 'Antwort')],
    );

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_lab_repo_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  group('LabExperimentRepository', () {
    test('speichern, nach Fach filtern (Termin zuerst, ohne Termin zuletzt), laden, löschen', () async {
      final repo = LabExperimentRepository();
      var notified = 0;
      repo.addListener(() => notified++);

      await repo.save(_lab('ohne', 'repo-m1', createdAt: DateTime(2026, 9, 3)));
      await repo.save(_lab('spät', 'repo-m1', labDate: DateTime(2026, 10, 5)));
      await repo.save(_lab('früh', 'repo-m1', labDate: DateTime(2026, 9, 20)));
      await repo.save(_lab('fremd', 'repo-m2', labDate: DateTime(2026, 9, 1)));

      expect(notified, greaterThanOrEqualTo(4));
      expect(repo.forModule('repo-m1').map((e) => e.id), ['früh', 'spät', 'ohne']);
      expect(repo.byId('fremd')!.moduleId, 'repo-m2');
      expect(repo.byId('gibt-es-nicht'), isNull);

      // Ein zweites Repository sieht dasselbe aus der Datenbank.
      final other = LabExperimentRepository();
      await other.loadAll();
      expect(other.forModule('repo-m1').map((e) => e.id), ['früh', 'spät', 'ohne']);
      expect(other.byId('früh')!.prep.single.answer, 'Antwort');

      await repo.delete('spät');
      expect(repo.forModule('repo-m1').map((e) => e.id), ['früh', 'ohne']);
      await other.loadAll();
      expect(other.byId('spät'), isNull);
    });

    test('speichern aktualisiert zuerst den Speicher – die Oberfläche sieht die Eingabe sofort', () async {
      final repo = LabExperimentRepository();
      final future = repo.save(_lab('sofort', 'repo-m3'));
      expect(repo.byId('sofort'), isNotNull);
      await future;
    });
  });

  group('Fach löschen / exportieren / importieren', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase('lab_${DateTime.now().microsecondsSinceEpoch}');
    });

    tearDown(() => db.close());

    test('Fach löschen entfernt seine Laborversuche, andere bleiben', () async {
      await DatabaseService.modules.record('m1').put(db, {'id': 'm1'});
      await DatabaseService.labExperiments.record('a').put(db, _lab('a', 'm1').toMap());
      await DatabaseService.labExperiments.record('b').put(db, _lab('b', 'm2').toMap());

      await db.transaction((txn) => ModuleRepository.deleteCascade(txn, 'm1'));

      final remaining = await LabExperimentRepository.loadFrom(db);
      expect(remaining.map((e) => e.id), ['b']);
    });

    Module module() => Module(id: 'm1', name: 'ET', colorValue: 0xFF112233, icon: '⚡', examDate: null, createdAt: DateTime(2026, 1, 1));

    test('Export und Import: neue Kennungen, Material übersetzt, Fortschritt bleibt', () async {
      final payload = ModuleExportService.buildPayload(
        module: module(),
        lectureUnits: const [],
        materialsWithBytes: const [],
        concepts: const [],
        flashcards: const [],
        labExperiments: [_lab('lab1', 'm1', labDate: DateTime(2026, 9, 20), theory: const ['gibt-es-nicht-mehr'])],
      );
      expect(payload['labExperiments'], hasLength(1));

      final imported = ModuleExportService.parse(payload);
      final lab = imported.labExperiments.single;
      expect(lab.id, isNot('lab1'));
      expect(lab.moduleId, imported.module.id);
      expect(lab.title, 'Versuch lab1');
      expect(lab.prep.single.answer, 'Antwort');
      expect(lab.labDate, DateTime(2026, 9, 20));
      expect(lab.theoryMaterialIds, isEmpty);

      await ModuleExportService.saveImported(db, imported);
      final stored = await LabExperimentRepository.loadFrom(db);
      expect(stored.single.id, lab.id);
    });

    test('ohne Lernstand importiert: Antworten und Termine bleiben nicht erhalten', () async {
      final payload = ModuleExportService.buildPayload(
        module: module(),
        lectureUnits: const [],
        materialsWithBytes: const [],
        concepts: const [],
        flashcards: const [],
        labExperiments: [_lab('lab1', 'm1', labDate: DateTime(2026, 9, 20))],
      );
      final lab = ModuleExportService.parse(payload).withoutLearningState().labExperiments.single;
      expect(lab.prep.single.answer, isEmpty);
      expect(lab.prep.single.text, 'Frage');
      expect(lab.labDate, isNull);
    });

    test('ältere Exporte ohne Laborversuche lassen sich weiter importieren', () {
      final payload = ModuleExportService.buildPayload(
        module: module(),
        lectureUnits: const [],
        materialsWithBytes: const [],
        concepts: const [],
        flashcards: const [],
      )..remove('labExperiments');
      expect(ModuleExportService.parse(payload).labExperiments, isEmpty);
    });
  });
}
