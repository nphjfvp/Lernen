import 'dart:typed_data';

import 'package:sembast/sembast.dart';

import '../models/material_item.dart';
import 'database_service.dart';
import 'material_file_store.dart';
import 'pdf_cloud_store.dart';

/// Bringt die Original-PDFs in den eigenen Cloud-Speicher des Nutzers und
/// holt sie auf anderen Geräten bei Bedarf wieder ab. Der Cloud-Sync der
/// Lerndaten (SyncService) überträgt nur den Verweis ([MaterialItem.remotePdfKey]),
/// nie die Datei selbst.
class PdfCloudSyncService {
  PdfCloudSyncService(this._store);

  final PdfCloudStore _store;

  /// Lädt alle lokal vorhandenen, noch nicht hochgeladenen PDFs hoch und
  /// merkt sich den Speicherort am Material. Liefert die Anzahl. Einzelne
  /// Fehler brechen ab (der nächste Lauf macht dort weiter).
  Future<int> uploadPending({void Function(int done, int total)? onProgress}) async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.materials.find(db);
    final pending = [
      for (final r in records)
        if (_needsUpload(MaterialItem.fromMap(r.value))) MaterialItem.fromMap(r.value),
    ];
    for (var i = 0; i < pending.length; i++) {
      onProgress?.call(i, pending.length);
      final material = pending[i];
      final bytes = await MaterialFileStore.load(filePath: material.filePath, fileBytesBase64: material.fileBytesBase64);
      if (bytes == null) continue;
      final key = PdfCloudStore.keyForMaterial(material.id);
      await _store.put(key, bytes);
      await DatabaseService.materials.record(material.id).update(db, {'remotePdfKey': key});
    }
    onProgress?.call(pending.length, pending.length);
    return pending.length;
  }

  static bool _needsUpload(MaterialItem m) => m.hasViewablePdf && m.remotePdfKey == null;

  /// Wie viele PDFs noch hochgeladen werden müssten.
  static Future<int> countPending() async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.materials.find(db);
    return records.where((r) => _needsUpload(MaterialItem.fromMap(r.value))).length;
  }

  /// Holt die PDF eines Materials aus dem Speicher und legt sie lokal ab
  /// (Datei bzw. im Web in der DB). Liefert das aktualisierte Material oder
  /// null, wenn sie dort nicht (mehr) liegt.
  Future<MaterialItem?> download(MaterialItem material) async {
    final key = material.remotePdfKey;
    if (key == null) return null;
    final Uint8List? bytes = await _store.get(key);
    if (bytes == null) return null;
    final (filePath, fileBytesBase64) = await MaterialFileStore.store(material.id, bytes);
    final db = await DatabaseService.instance.database;
    await DatabaseService.materials.record(material.id).update(db, {
      'filePath': filePath,
      'fileBytesBase64': fileBytesBase64,
    });
    final record = await DatabaseService.materials.record(material.id).get(db);
    return record == null ? null : MaterialItem.fromMap(record);
  }

  /// Entfernt PDFs gelöschter Materialien aus dem Speicher – best effort:
  /// ein Fehler hier soll das lokale Löschen nicht aufhalten.
  Future<void> deleteRemote(Iterable<String> keys) async {
    for (final key in keys) {
      try {
        await _store.delete(key);
      } catch (_) {
        // Siehe Doc-Kommentar.
      }
    }
  }
}
