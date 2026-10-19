import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/pdf_blob_migration.dart';
import 'package:lernen/services/pdf_blob_store.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('PDF-Bytes speichern, lesen, löschen – getrennt von der App-Datenbank', () async {
    final store = PdfBlobStore(newIdbFactoryMemory());
    final bytes = Uint8List.fromList(List.generate(5000, (i) => i % 256));
    await store.put('m1', bytes);
    expect(await store.get('m1'), bytes);
    expect(await store.get('fehlt'), isNull);
    await store.delete('m1');
    expect(await store.get('m1'), isNull);

    expect(PdfBlobStore.pathFor('m1'), 'idb:m1');
    expect(PdfBlobStore.isBlobPath('idb:m1'), isTrue);
    expect(PdfBlobStore.isBlobPath('/data/materials/m1.pdf'), isFalse);
    expect(PdfBlobStore.isBlobPath(null), isFalse);
    expect(PdfBlobStore.idOf('idb:m1'), 'm1');
  });

  test('Alte Base64-PDFs ziehen um: Material zeigt dann auf den Speicher, Rest bleibt', () async {
    final db = await newDatabaseFactoryMemory().openDatabase('t.db');
    final store = PdfBlobStore(newIdbFactoryMemory());
    final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 Folien'));
    await DatabaseService.materials.record('alt').put(db, {
      'id': 'alt',
      'moduleId': 'mod',
      'name': 'Vorlesung 1.pdf',
      'fileBytesBase64': base64Encode(pdf),
    });
    await DatabaseService.materials.record('ohne').put(db, {'id': 'ohne', 'moduleId': 'mod', 'name': 'Notiz'});
    await DatabaseService.materials.record('datei').put(db, {
      'id': 'datei',
      'moduleId': 'mod',
      'name': 'x.pdf',
      'filePath': '/data/x.pdf',
    });

    expect(await PdfBlobMigration.run(db, store), 1);
    final moved = (await DatabaseService.materials.record('alt').get(db))!;
    expect(moved['filePath'], 'idb:alt');
    expect(moved.containsKey('fileBytesBase64'), isFalse);
    expect(moved['name'], 'Vorlesung 1.pdf');
    expect(await store.get('alt'), pdf);
    expect(MaterialItem.fromMap(Map<String, dynamic>.from(moved)).hasViewablePdf, isTrue);
    expect((await DatabaseService.materials.record('datei').get(db))!['filePath'], '/data/x.pdf');

    expect(await PdfBlobMigration.run(db, store), 0, reason: 'zweiter Start: nichts mehr zu tun');
    await db.close();
  });
}
