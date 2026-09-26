import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/concept.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/lecture_unit.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/models/summary.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/module_export_service.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  final module = Module(
    id: 'mod1',
    name: 'Werkstoffkunde',
    colorValue: 0xFF112233,
    icon: '🔧',
    examDate: DateTime(2026, 7, 1),
    createdAt: DateTime(2026, 1, 1),
  );
  final unit = LectureUnit(
    id: 'unit1',
    moduleId: 'mod1',
    title: 'Einheit 1',
    covered: true,
    createdAt: DateTime(2026, 1, 2),
    notes: const ['Merksatz'],
  );
  final material = MaterialItem(
    id: 'mat1',
    moduleId: 'mod1',
    fileName: 'Folien.pdf',
    kind: MaterialKind.slide,
    extractedText: 'Inhalt der Folien',
    createdAt: DateTime(2026, 1, 3),
    fileBytesBase64: 'QUJD',
    unitId: 'unit1',
  );
  final concept = Concept(
    id: 'concept1',
    moduleId: 'mod1',
    title: 'Werkstoffgruppen',
    explanation: 'Die vier Werkstoffgruppen ...',
    sourceMaterialIds: const ['mat1'],
    createdAt: DateTime(2026, 1, 4),
    unitId: 'unit1',
    linkedMaterialId: 'mat1',
    linkedPageNumber: 3,
  );
  final flashcard = Flashcard(
    id: 'card1',
    moduleId: 'mod1',
    conceptId: 'concept1',
    front: 'Was ist ein Werkstoff?',
    back: 'Ein fester Stoff für den Bau von Maschinen.',
    createdAt: DateTime(2026, 1, 5),
    due: DateTime(2026, 1, 6),
    unitId: 'unit1',
  );

  Map<String, dynamic> buildFullPayload() => ModuleExportService.buildPayload(
        module: module,
        lectureUnits: [unit],
        materialsWithBytes: [material],
        concepts: [concept],
        flashcards: [flashcard],
      );

  group('ModuleExportService.buildPayload', () {
    test('enthält Formatversion, Modul und alle Listen', () {
      final payload = buildFullPayload();
      expect(payload['formatVersion'], moduleExportFormatVersion);
      expect(payload['exportedAt'], isNotNull);
      expect(payload['module']['name'], 'Werkstoffkunde');
      expect(payload['lectureUnits'], hasLength(1));
      expect(payload['materials'], hasLength(1));
      expect(payload['concepts'], hasLength(1));
      expect(payload['flashcards'], hasLength(1));
    });
  });

  group('ModuleExportService.parse', () {
    test('vergibt frische IDs, behält aber Inhalt + Querverweise konsistent', () {
      final payload = buildFullPayload();
      final imported = ModuleExportService.parse(payload);

      expect(imported.module.id, isNot('mod1'));
      expect(imported.module.name, 'Werkstoffkunde');
      expect(imported.module.colorValue, 0xFF112233);
      expect(imported.module.examDate, DateTime(2026, 7, 1));

      final importedUnit = imported.lectureUnits.single;
      expect(importedUnit.id, isNot('unit1'));
      expect(importedUnit.moduleId, imported.module.id);
      expect(importedUnit.title, 'Einheit 1');
      expect(importedUnit.notes, ['Merksatz']);

      final importedMaterial = imported.materials.single;
      expect(importedMaterial.id, isNot('mat1'));
      expect(importedMaterial.moduleId, imported.module.id);
      expect(importedMaterial.fileBytesBase64, 'QUJD');
      expect(importedMaterial.filePath, isNull);
      expect(importedMaterial.unitId, importedUnit.id);

      final importedConcept = imported.concepts.single;
      expect(importedConcept.id, isNot('concept1'));
      expect(importedConcept.moduleId, imported.module.id);
      expect(importedConcept.unitId, importedUnit.id);
      expect(importedConcept.sourceMaterialIds, [importedMaterial.id]);
      expect(importedConcept.linkedMaterialId, importedMaterial.id);
      expect(importedConcept.linkedPageNumber, 3);

      final importedCard = imported.flashcards.single;
      expect(importedCard.id, isNot('card1'));
      expect(importedCard.moduleId, imported.module.id);
      expect(importedCard.unitId, importedUnit.id);
      expect(importedCard.conceptId, importedConcept.id);
      expect(importedCard.front, 'Was ist ein Werkstoff?');
    });

    test('zwei Importe derselben Datei erzeugen unabhängige, kollisionsfreie IDs', () {
      final payload = buildFullPayload();
      final first = ModuleExportService.parse(payload);
      final second = ModuleExportService.parse(payload);

      expect(first.module.id, isNot(second.module.id));
      expect(first.materials.single.id, isNot(second.materials.single.id));
      expect(first.flashcards.single.id, isNot(second.flashcards.single.id));
    });

    test('Querverweis auf ein nicht mit-exportiertes Ziel wird zu null statt zu crashen', () {
      final payload = ModuleExportService.buildPayload(
        module: module,
        lectureUnits: const [],
        materialsWithBytes: const [],
        concepts: [concept], // referenziert unitId/linkedMaterialId, die es hier nicht gibt
        flashcards: const [],
      );
      final imported = ModuleExportService.parse(payload);
      final importedConcept = imported.concepts.single;
      expect(importedConcept.unitId, isNull);
      expect(importedConcept.linkedMaterialId, isNull);
      expect(importedConcept.sourceMaterialIds, isEmpty);
    });

    test('lehnt eine Datei aus einer neueren, unbekannten Formatversion ab', () {
      final payload = buildFullPayload();
      payload['formatVersion'] = moduleExportFormatVersion + 1;
      expect(() => ModuleExportService.parse(payload), throwsFormatException);
    });

    test('wirft bei fehlendem "module"-Feld eine klare Fehlermeldung', () {
      expect(() => ModuleExportService.parse({'formatVersion': 1}), throwsFormatException);
    });
  });

  group('ModuleExportService – Zusammenfassungen, Transaktion, Lernstand', () {
    final summary = Summary(
      id: 'sum1',
      moduleId: 'mod1',
      sourceMaterialIds: const ['mat1', 'fehlt'],
      title: 'Überblick',
      overview: 'Worum es geht',
      keyPoints: const ['Punkt'],
      createdAt: DateTime(2026, 1, 7),
      unitId: 'unit1',
    );

    test('Zusammenfassungen reisen mit und zeigen auf die neuen IDs', () {
      final payload = ModuleExportService.buildPayload(
        module: module,
        lectureUnits: [unit],
        materialsWithBytes: [material],
        concepts: [concept],
        flashcards: [flashcard],
        summaries: [summary],
      );
      final imported = ModuleExportService.parse(payload);
      final s = imported.summaries.single;
      expect(s.id, isNot('sum1'));
      expect(s.moduleId, imported.module.id);
      expect(s.unitId, imported.lectureUnits.single.id);
      expect(s.sourceMaterialIds, [imported.materials.single.id]);
      expect(s.title, 'Überblick');
    });

    test('ältere Exportdateien ohne Zusammenfassungen bleiben lesbar', () {
      expect(ModuleExportService.parse(buildFullPayload()).summaries, isEmpty);
    });

    test('saveImported schreibt alles in eine Datenbank', () async {
      final db = await databaseFactoryMemory.openDatabase('import_${DateTime.now().microsecondsSinceEpoch}');
      addTearDown(db.close);
      final imported = ModuleExportService.parse(ModuleExportService.buildPayload(
        module: module,
        lectureUnits: [unit],
        materialsWithBytes: [material],
        concepts: [concept],
        flashcards: [flashcard],
        summaries: [summary],
      ));
      await db.transaction((txn) => ModuleExportService.saveImported(txn, imported));
      expect(await DatabaseService.modules.count(db), 1);
      expect(await DatabaseService.lectureUnits.count(db), 1);
      expect(await DatabaseService.materials.count(db), 1);
      expect(await DatabaseService.summaries.count(db), 1);
      expect(await DatabaseService.concepts.count(db), 1);
      expect(await DatabaseService.flashcards.count(db), 1);
    });

    test('ohne Lernstand: Karte wieder neu, Kette beginnt bei der leichtesten Stufe', () {
      final learned = Flashcard(
        id: 'c',
        moduleId: 'mod1',
        front: 'Schwer?',
        back: '',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 5, 1),
        type: QuestionType.freeText,
        correctText: 'A',
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
        variantLevel: 2,
        variantHistory: const [
          VariantSnapshot(type: QuestionType.singleChoice, front: 'Leicht?', back: ''),
          VariantSnapshot(type: QuestionType.fillBlank, front: 'Mittel ___', back: ''),
        ],
        masteryBox: 4,
        reps: 9,
        lapses: 2,
        stability: 30,
        state: 'review',
        lastReview: DateTime(2026, 4, 1),
      );
      final reset = ModuleExportService.resetLearningState(learned);
      expect(reset.reps, 0);
      expect(reset.lapses, 0);
      expect(reset.masteryBox, 0);
      expect(reset.lastReview, isNull);
      expect(reset.state, 'new');
      expect(reset.variantLevel, 0);
      expect(reset.front, 'Leicht?');
      expect(reset.type, QuestionType.singleChoice);
      expect(reset.variantHistory, isNull);
      expect(reset.pendingVariants!.map((v) => v.front), ['Mittel ___', 'Schwer?']);
    });
  });
}
