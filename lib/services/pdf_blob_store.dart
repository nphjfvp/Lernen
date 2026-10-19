import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

/// PDF-Dateien im Browser: eine eigene IndexedDB nur für die Bytes, getrennt
/// von der App-Datenbank. Sembast hält seine Datenbank komplett im
/// Arbeitsspeicher – lägen die PDFs (als Base64) dort, würde jede Vorlesung
/// beim Start mitgeladen, bis Safari auf dem iPad die Seite beendet. Hier
/// wird eine Datei erst gelesen, wenn sie gebraucht wird.
///
/// Im Material steht dann [pathFor] als `filePath` (siehe MaterialFileStore).
class PdfBlobStore {
  PdfBlobStore(this._factory, {this.dbName = 'lernen_pdfs'});

  final IdbFactory _factory;
  final String dbName;

  static const _store = 'pdfs';

  /// Kennzeichen eines `filePath`, der auf diesen Speicher zeigt.
  static const prefix = 'idb:';

  static String pathFor(String materialId) => '$prefix$materialId';

  static bool isBlobPath(String? filePath) => filePath != null && filePath.startsWith(prefix);

  static String idOf(String filePath) => filePath.substring(prefix.length);

  Database? _db;

  Future<Database> _open() async => _db ??= await _factory.open(
    dbName,
    version: 1,
    onUpgradeNeeded: (e) {
      if (!e.database.objectStoreNames.contains(_store)) e.database.createObjectStore(_store);
    },
  );

  Future<void> put(String id, Uint8List bytes) async {
    final db = await _open();
    final txn = db.transaction(_store, idbModeReadWrite);
    await txn.objectStore(_store).put(bytes, id);
    await txn.completed;
  }

  Future<Uint8List?> get(String id) async {
    final db = await _open();
    final txn = db.transaction(_store, idbModeReadOnly);
    final value = await txn.objectStore(_store).getObject(id);
    await txn.completed;
    if (value is Uint8List) return value;
    if (value is ByteBuffer) return value.asUint8List();
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return null;
  }

  Future<void> delete(String id) async {
    final db = await _open();
    final txn = db.transaction(_store, idbModeReadWrite);
    await txn.objectStore(_store).delete(id);
    await txn.completed;
  }
}
