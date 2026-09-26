import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/material_item.dart';
import '../services/database_service.dart';

class MaterialRepository extends ChangeNotifier {
  final Map<String, List<MaterialItem>> _byModule = {};

  List<MaterialItem> forModule(String moduleId) =>
      List.unmodifiable(_byModule[moduleId] ?? const []);

  Future<void> loadForModule(String moduleId) async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.materials.find(
      db,
      finder: Finder(
        filter: Filter.equals('moduleId', moduleId),
        sortOrders: [SortOrder('createdAt', false)],
      ),
    );
    _byModule[moduleId] =
        records.map((r) => MaterialItem.fromMap(r.value)).toList();
    notifyListeners();
  }

  Future<void> save(MaterialItem item) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.materials.record(item.id).put(db, item.toMap());
    await loadForModule(item.moduleId);
  }

  /// Markiert ein Material als (nicht) im Unterricht behandelt. Rein
  /// informativ – blockiert nirgends den Zugriff auf das Material selbst.
  Future<void> setCovered(String id, String moduleId, bool covered) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.materials.record(id).update(db, {'covered': covered});
    await loadForModule(moduleId);
  }

  /// Ersetzt den extrahierten Text (z.B. nach nachgeholter Texterkennung).
  /// Der KI-Kurzindex fürs Chat-Routing passt dann nicht mehr und wird
  /// verworfen (wird beim nächsten Chat neu erstellt).
  Future<void> setExtractedText(String id, String moduleId, String text) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.materials.record(id).update(db, {'extractedText': text, 'topicIndex': null});
    await loadForModule(moduleId);
  }

  /// Ordnet mehrere Materialien einer Einheit zu (z.B. aus den KI-Vorschlägen).
  Future<void> assignUnit(List<String> ids, String moduleId, String unitId) async {
    if (ids.isEmpty) return;
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await DatabaseService.materials.record(id).update(txn, {'unitId': unitId});
      }
    });
    await loadForModule(moduleId);
  }

  /// Speichert den KI-generierten Kurz-Index eines Materials (siehe
  /// [MaterialItem.topicIndex]). Wird einmalig beim ersten Frage-Chat pro
  /// Material nachgeholt und danach dauerhaft gecacht.
  Future<void> setTopicIndex(String id, String moduleId, String topicIndex) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.materials.record(id).update(db, {'topicIndex': topicIndex});
    await loadForModule(moduleId);
  }

  /// Speichert die Markierungen + Notiz eines Materials (siehe
  /// [MaterialViewerScreen]) sowie optional aktualisierte PDF-Bytes (nach
  /// dem Einbetten der Annotationen ins Dokument selbst).
  Future<void> saveHighlights(
    String id,
    String moduleId, {
    required List<MaterialHighlight> highlights,
    required String notes,
    String? filePath,
    String? fileBytesBase64,
  }) async {
    final db = await DatabaseService.instance.database;
    final update = <String, dynamic>{
      'highlights': highlights.map((h) => h.toMap()).toList(),
      'notes': notes,
    };
    if (filePath != null) update['filePath'] = filePath;
    if (fileBytesBase64 != null) update['fileBytesBase64'] = fileBytesBase64;
    // Geänderte PDF: die Kopie im eigenen Cloud-Speicher ist veraltet und
    // wird beim nächsten Sync neu hochgeladen (siehe PdfCloudSyncService).
    if (filePath != null || fileBytesBase64 != null) update['remotePdfKey'] = null;
    await DatabaseService.materials.record(id).update(db, update);
    await loadForModule(moduleId);
  }

  Future<List<MaterialItem>> byIds(List<String> ids) async {
    final db = await DatabaseService.instance.database;
    final result = <MaterialItem>[];
    for (final id in ids) {
      final record = await DatabaseService.materials.record(id).get(db);
      if (record != null) result.add(MaterialItem.fromMap(record));
    }
    return result;
  }

  Future<void> delete(String id, String moduleId) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.materials.record(id).delete(db);
    await loadForModule(moduleId);
  }
}
