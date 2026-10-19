import 'dart:convert';

import 'package:sembast/sembast.dart';

import 'database_service.dart';
import 'pdf_blob_store.dart';

/// Holt im Browser früher gespeicherte PDFs (Base64 direkt am Material) aus
/// der App-Datenbank in den [PdfBlobStore] – danach lädt der Start sie nicht
/// mehr jedes Mal komplett in den Arbeitsspeicher. Einmalig je Material;
/// geht etwas schief, bleibt das Material wie es war (lesbar ist beides).
class PdfBlobMigration {
  PdfBlobMigration._();

  /// Gibt zurück, wie viele PDFs umgezogen sind.
  static Future<int> run(Database db, PdfBlobStore store) async {
    final records = await DatabaseService.materials.find(db, finder: Finder(filter: Filter.notNull('fileBytesBase64')));
    var moved = 0;
    for (final r in records) {
      final base64 = r.value['fileBytesBase64'];
      if (base64 is! String || base64.isEmpty) continue;
      try {
        await store.put(r.key, base64Decode(base64));
        await DatabaseService.materials.record(r.key).update(db, {
          'filePath': PdfBlobStore.pathFor(r.key),
          'fileBytesBase64': FieldValue.delete,
        });
        moved++;
      } catch (_) {
        // Bleibt als Base64 liegen und wird beim nächsten Start erneut versucht.
      }
    }
    return moved;
  }
}
