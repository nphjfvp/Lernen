@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_browser.dart' show idbFactoryBrowser;
import 'package:lernen/services/pdf_blob_store.dart';

void main() {
  test('Im echten Browser: PDF-Bytes kommen unverändert aus der IndexedDB zurück', () async {
    final store = PdfBlobStore(idbFactoryBrowser, dbName: 'lernen_pdfs_test');
    final bytes = Uint8List.fromList(List.generate(300000, (i) => (i * 7) % 256));
    await store.put('m1', bytes);
    expect(await store.get('m1'), bytes);
    await store.delete('m1');
    expect(await store.get('m1'), isNull);
  });
}
