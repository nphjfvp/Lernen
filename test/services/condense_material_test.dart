import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/condense.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/chat_context_builder.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/module_export_service.dart';
import 'package:sembast/sembast_memory.dart';

MaterialItem _lecture() => MaterialItem(
      id: 'lec1',
      moduleId: 'mod1',
      fileName: 'Analysis.pdf',
      kind: MaterialKind.slide,
      extractedText: 'Der ganze Skripttext zur Analysis.',
      createdAt: DateTime(2026, 9, 1),
    );

MaterialItem _condensed() => MaterialItem(
      id: 'con1',
      moduleId: 'mod1',
      fileName: 'Analysis – gekürzt.pdf',
      kind: MaterialKind.condensed,
      extractedText: 'Gekürzte Fassung: Analysis.pdf\n## Seite 2 · Partielle Integration\nFormel',
      createdAt: DateTime(2026, 9, 2),
      unitId: 'unit1',
      fileBytesBase64: 'QUJD',
      condensed: const CondensedInfo(
        sourceMaterialId: 'lec1',
        sourceName: 'Analysis.pdf',
        prompt: 'alles zum Lösen',
        exerciseNames: ['Blatt 3.pdf'],
        pages: [2, 4],
        totalPages: 40,
        notFound: ['Laplace'],
        skipped: ['Organisatorisches'],
      ),
    );

void main() {
  group('MaterialItem mit gekürzter Fassung', () {
    test('Rundreise über toMap/fromMap behält Art und Angaben', () {
      final back = MaterialItem.fromMap(_condensed().toMap());
      expect(back.kind, MaterialKind.condensed);
      expect(back.condensed!.sourceMaterialId, 'lec1');
      expect(back.condensed!.pages, [2, 4]);
      expect(back.condensed!.notFound, ['Laplace']);
    });

    test('Material ohne die Angabe (ältere Daten) liest sich weiter, kopieren verliert sie nicht', () {
      final old = _lecture().toMap()..remove('condensed');
      expect(MaterialItem.fromMap(old).condensed, isNull);
      final copy = _condensed().copyWith(notes: 'Merk dir das');
      expect(copy.condensed, isNotNull);
      expect(copy.notes, 'Merk dir das');
    });

    test('eine unbekannte Art (neuere App-Version) bleibt eine Folie', () {
      expect(materialKindFromString('irgendwas'), MaterialKind.slide);
      expect(materialKindFromString('condensed'), MaterialKind.condensed);
    });
  });

  group('Frage-Chat', () {
    test('gekürzte Fassungen doppeln das Original nicht im Kontext', () {
      final materials = [_lecture(), _condensed()];
      final index = ChatContextBuilder.buildIndexContext(materials);
      expect(index, contains('Analysis.pdf'));
      expect(index, isNot(contains('gekürzt')));
      final context = ChatContextBuilder.build(materials, charBudget: 10000);
      expect(context, contains('Der ganze Skripttext'));
      expect(context, isNot(contains('Gekürzte Fassung')));
    });

    test('nur eine gekürzte Fassung: "noch keine Materialien"', () {
      expect(ChatContextBuilder.build([_condensed()], charBudget: 10000), contains('Noch keine Materialien'));
    });
  });

  group('Fach-Export', () {
    final module = Module(
      id: 'mod1',
      name: 'Analysis',
      colorValue: 0xFF112233,
      icon: '📘',
      examDate: null,
      createdAt: DateTime(2026, 1, 1),
    );

    test('Export und Import behalten die gekürzte Fassung samt Verweis auf das neue Original', () async {
      final imported = ModuleExportService.parse(ModuleExportService.buildPayload(
        module: module,
        lectureUnits: const [],
        materialsWithBytes: [_lecture(), _condensed()],
        concepts: const [],
        flashcards: const [],
      ));
      final lecture = imported.materials.firstWhere((m) => m.kind == MaterialKind.slide);
      final condensed = imported.materials.firstWhere((m) => m.kind == MaterialKind.condensed);
      expect(condensed.condensed, isNotNull);
      expect(condensed.condensed!.pages, [2, 4]);
      expect(condensed.condensed!.sourceName, 'Analysis.pdf');
      // Das Original bekommt beim Import eine neue Kennung – der Verweis folgt ihr.
      expect(lecture.id, isNot('lec1'));
      expect(condensed.condensed!.sourceMaterialId, lecture.id);
    });

    test('auch gespeichert bleibt die Angabe erhalten', () async {
      final db = await databaseFactoryMemory.openDatabase('condense_export_${DateTime.now().microsecondsSinceEpoch}');
      addTearDown(db.close);
      final imported = ModuleExportService.parse(ModuleExportService.buildPayload(
        module: module,
        lectureUnits: const [],
        materialsWithBytes: [_lecture(), _condensed()],
        concepts: const [],
        flashcards: const [],
      ));
      await db.transaction((txn) => ModuleExportService.saveImported(txn, imported));
      final records = await DatabaseService.materials.find(db);
      final condensed = records.map((r) => MaterialItem.fromMap(r.value)).firstWhere((m) => m.kind == MaterialKind.condensed);
      expect(condensed.condensed!.totalPages, 40);
    });

    test('embedBytes lässt die Angabe der gekürzten Fassung stehen', () async {
      final result = await ModuleExportService.embedBytes([_condensed()]);
      expect(result.single.condensed!.pages, [2, 4]);
    });
  });
}
