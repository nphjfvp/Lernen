import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/concept.dart';
import '../models/flashcard.dart';
import '../models/lecture_unit.dart';
import '../models/material_item.dart';
import '../models/module.dart';
import 'material_file_store.dart';

/// Aktuelle Export-Formatversion – bei inkompatiblen Strukturänderungen
/// hochzählen; [ModuleExportService.parse] prüft dagegen und lehnt eine
/// Datei aus einer NEUEREN (unbekannten) Version ab, statt sie stillschweigend
/// falsch zu interpretieren.
const moduleExportFormatVersion = 1;

/// Ergebnis von [ModuleExportService.parse]: ein vollständig eigenständiges
/// Fach mit frisch vergebenen IDs (siehe dort), bereit zum Speichern über die
/// jeweiligen Repositories.
class ImportedModule {
  const ImportedModule({
    required this.module,
    required this.lectureUnits,
    required this.materials,
    required this.concepts,
    required this.flashcards,
  });

  final Module module;
  final List<LectureUnit> lectureUnits;
  final List<MaterialItem> materials;
  final List<Concept> concepts;
  final List<Flashcard> flashcards;
}

/// Export/Import eines kompletten Fachs (Modul + Einheiten + Materialien +
/// Konzepte + Karteikarten) als eigenständige, portable JSON-Datei – z.B. um
/// ein Fach lokal zu sichern oder auf ein anderes Gerät/an eine andere Person
/// weiterzugeben, ohne den (Firebase-basierten) Cloud-Sync zu nutzen. Bewusst
/// NICHT enthalten: Chat-Verlauf (ChatMessage) und Mastery-Snapshots – beides
/// geräte-/sitzungsbezogene Verlaufsdaten ohne Bezug zum eigentlichen
/// Fach-Inhalt, kein Datenverlust beim Fach selbst.
class ModuleExportService {
  ModuleExportService._();

  /// Lädt für Materialien mit Original-PDF-Bytes, die (auf IO-Plattformen)
  /// nur als [MaterialItem.filePath] vorliegen, den tatsächlichen Inhalt
  /// nach und bettet ihn als Base64 ein (wie es [MaterialItem.fileBytesBase64]
  /// auf Web ohnehin schon tut) – nur so ist die Export-Datei über
  /// Geräte/Plattformen hinweg komplett eigenständig lesbar. Bewusst
  /// getrennt von [buildPayload]: einzig dieser Schritt braucht Datei-I/O,
  /// der Rest bleibt synchron und testbar.
  static Future<List<MaterialItem>> embedBytes(List<MaterialItem> materials) async {
    final result = <MaterialItem>[];
    for (final m in materials) {
      if (!m.hasViewablePdf || m.fileBytesBase64 != null) {
        result.add(m);
        continue;
      }
      final bytes = await MaterialFileStore.load(filePath: m.filePath, fileBytesBase64: m.fileBytesBase64);
      if (bytes == null) {
        result.add(m);
        continue;
      }
      result.add(MaterialItem(
        id: m.id,
        moduleId: m.moduleId,
        fileName: m.fileName,
        kind: m.kind,
        extractedText: m.extractedText,
        createdAt: m.createdAt,
        covered: m.covered,
        topicIndex: m.topicIndex,
        filePath: null,
        fileBytesBase64: base64Encode(bytes),
        highlights: m.highlights,
        notes: m.notes,
        unitId: m.unitId,
      ));
    }
    return result;
  }

  /// Baut das exportierbare JSON für EIN Fach. [materialsWithBytes] sollte
  /// zuvor durch [embedBytes] gelaufen sein, damit PDF-Inhalte plattform-
  /// unabhängig eingebettet sind. Rein synchron/pure – keine Datei-I/O.
  static Map<String, dynamic> buildPayload({
    required Module module,
    required List<LectureUnit> lectureUnits,
    required List<MaterialItem> materialsWithBytes,
    required List<Concept> concepts,
    required List<Flashcard> flashcards,
  }) {
    return {
      'formatVersion': moduleExportFormatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'module': module.toMap(),
      'lectureUnits': lectureUnits.map((u) => u.toMap()).toList(),
      'materials': materialsWithBytes.map((m) => m.toMap()).toList(),
      'concepts': concepts.map((c) => c.toMap()).toList(),
      'flashcards': flashcards.map((f) => f.toMap()).toList(),
    };
  }

  /// Liest ein zuvor exportiertes Fach wieder ein und vergibt dabei
  /// durchgängig FRISCHE IDs (Modul, Einheiten, Materialien, Konzepte,
  /// Karteikarten) statt der exportierten Original-IDs – so lässt sich
  /// dieselbe Datei beliebig oft (auch auf demselben Gerät, auch neben dem
  /// Original) importieren, ohne IDs mit vorhandenen oder früher
  /// importierten Daten zu kollidieren. Alle Querverweise (unitId,
  /// conceptId, sourceMaterialIds, linkedMaterialId) werden dabei
  /// konsistent mitübersetzt; ein Verweis auf ein NICHT mit-exportiertes
  /// Ziel (z.B. durch eine unvollständige/manuell bearbeitete Datei) wird
  /// stillschweigend zu null statt einen Fehler zu werfen.
  static ImportedModule parse(Map<String, dynamic> json) {
    final formatVersion = (json['formatVersion'] as num?)?.toInt() ?? 1;
    if (formatVersion > moduleExportFormatVersion) {
      throw FormatException(
          'Diese Datei wurde mit einer neueren App-Version exportiert (Format $formatVersion, unterstützt bis $moduleExportFormatVersion).');
    }

    final moduleMap = json['module'];
    if (moduleMap is! Map) {
      throw const FormatException('Keine gültige Fach-Export-Datei (Feld "module" fehlt).');
    }
    final oldModule = Module.fromMap(Map<String, dynamic>.from(moduleMap));
    final newModuleId = const Uuid().v4();
    final module = Module(
      id: newModuleId,
      name: oldModule.name,
      colorValue: oldModule.colorValue,
      icon: oldModule.icon,
      examDate: oldModule.examDate,
      createdAt: oldModule.createdAt,
      lectureSlots: oldModule.lectureSlots,
    );

    final unitIdMap = <String, String>{};
    final lectureUnits = ((json['lectureUnits'] as List?) ?? const [])
        .map((e) => LectureUnit.fromMap(Map<String, dynamic>.from(e as Map)))
        .map((u) {
      final newId = const Uuid().v4();
      unitIdMap[u.id] = newId;
      return LectureUnit(
        id: newId,
        moduleId: newModuleId,
        title: u.title,
        covered: u.covered,
        createdAt: u.createdAt,
        notes: u.notes,
      );
    }).toList();

    final materialIdMap = <String, String>{};
    final materials = ((json['materials'] as List?) ?? const [])
        .map((e) => MaterialItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .map((m) {
      final newId = const Uuid().v4();
      materialIdMap[m.id] = newId;
      return MaterialItem(
        id: newId,
        moduleId: newModuleId,
        fileName: m.fileName,
        kind: m.kind,
        extractedText: m.extractedText,
        createdAt: m.createdAt,
        covered: m.covered,
        topicIndex: m.topicIndex,
        filePath: null,
        fileBytesBase64: m.fileBytesBase64,
        highlights: m.highlights,
        notes: m.notes,
        unitId: m.unitId == null ? null : unitIdMap[m.unitId],
      );
    }).toList();

    final conceptIdMap = <String, String>{};
    final concepts = ((json['concepts'] as List?) ?? const [])
        .map((e) => Concept.fromMap(Map<String, dynamic>.from(e as Map)))
        .map((cpt) {
      final newId = const Uuid().v4();
      conceptIdMap[cpt.id] = newId;
      return Concept(
        id: newId,
        moduleId: newModuleId,
        title: cpt.title,
        explanation: cpt.explanation,
        sourceMaterialIds:
            cpt.sourceMaterialIds.map((id) => materialIdMap[id]).whereType<String>().toList(),
        createdAt: cpt.createdAt,
        unitId: cpt.unitId == null ? null : unitIdMap[cpt.unitId],
        linkedMaterialId: cpt.linkedMaterialId == null ? null : materialIdMap[cpt.linkedMaterialId],
        linkedPageNumber: cpt.linkedPageNumber,
      );
    }).toList();

    final flashcards = ((json['flashcards'] as List?) ?? const [])
        .map((e) => Flashcard.fromMap(Map<String, dynamic>.from(e as Map)))
        .map((f) => Flashcard(
              id: const Uuid().v4(),
              moduleId: newModuleId,
              conceptId: f.conceptId == null ? null : conceptIdMap[f.conceptId],
              front: f.front,
              back: f.back,
              createdAt: f.createdAt,
              due: f.due,
              type: f.type,
              options: f.options,
              correctText: f.correctText,
              blanks: f.blanks,
              dragPairs: f.dragPairs,
              htmlContent: f.htmlContent,
              imageBase64: f.imageBase64,
              variantChain: f.variantChain,
              variantLevel: f.variantLevel,
              variantBox: f.variantBox,
              variantHistory: f.variantHistory,
              pendingVariants: f.pendingVariants,
              variantMissStreak: f.variantMissStreak,
              masteryBox: f.masteryBox,
              priorityIntroduction: f.priorityIntroduction,
              stability: f.stability,
              difficulty: f.difficulty,
              elapsedDays: f.elapsedDays,
              scheduledDays: f.scheduledDays,
              reps: f.reps,
              lapses: f.lapses,
              state: f.state,
              lastReview: f.lastReview,
              unitId: f.unitId == null ? null : unitIdMap[f.unitId],
            ))
        .toList();

    return ImportedModule(
      module: module,
      lectureUnits: lectureUnits,
      materials: materials,
      concepts: concepts,
      flashcards: flashcards,
    );
  }
}
