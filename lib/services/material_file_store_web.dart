import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart' show idbFactoryBrowser;
import 'package:sembast/sembast.dart';

import 'pdf_blob_migration.dart';
import 'pdf_blob_store.dart';

/// Im Browser liegen PDFs in einer eigenen IndexedDB (siehe [PdfBlobStore]),
/// nicht in der App-Datenbank.
final _store = PdfBlobStore(idbFactoryBrowser);

Future<(String?, String?)> storePdfBytes(String materialId, Uint8List bytes) async {
  try {
    await _store.put(materialId, bytes);
    return (PdfBlobStore.pathFor(materialId), null);
  } catch (_) {
    // IndexedDB nicht nutzbar (z.B. privates Fenster) – wie früher am Material.
    return (null, base64Encode(bytes));
  }
}

Future<Uint8List?> loadPdfBytes(String filePath) async {
  if (!PdfBlobStore.isBlobPath(filePath)) return null;
  try {
    return await _store.get(PdfBlobStore.idOf(filePath));
  } catch (_) {
    return null;
  }
}

Future<void> deletePdfFile(String? filePath) async {
  if (!PdfBlobStore.isBlobPath(filePath)) return;
  try {
    await _store.delete(PdfBlobStore.idOf(filePath!));
  } catch (_) {}
}

Future<int> migrateLegacyPdfs(Database db) => PdfBlobMigration.run(db, _store);
