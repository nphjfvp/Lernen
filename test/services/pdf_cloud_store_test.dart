import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/pdf_storage_config.dart';
import 'package:lernen/services/pdf_cloud_store.dart';

void main() {
  group('S3Signer (AWS Signature V4)', () {
    test('entspricht dem offiziellen AWS-Beispiel "GET Object"', () {
      // Beispielwerte aus der AWS-Dokumentation (Signature V4, S3 GET Object).
      final signer = S3Signer(
        accessKey: 'AKIAIOSFODNN7EXAMPLE',
        secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        region: 'us-east-1',
      );
      final headers = signer.sign(
        method: 'GET',
        canonicalPath: '/test.txt',
        headers: {
          'Host': 'examplebucket.s3.amazonaws.com',
          'Range': 'bytes=0-9',
          'x-amz-content-sha256': S3Signer.emptyPayloadHash,
          'x-amz-date': '20130524T000000Z',
        },
        payloadHash: S3Signer.emptyPayloadHash,
      );
      expect(
        headers['Authorization'],
        'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, '
        'SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, '
        'Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
      );
    });

    test('Pfad-Kodierung nach AWS-Regeln', () {
      expect(S3Signer.encodePath('/bucket/ordner mit leer/ä(1).pdf'), '/bucket/ordner%20mit%20leer/%C3%A4%281%29.pdf');
    });
  });

  group('S3PdfCloudStore', () {
    test('lädt pfad-basiert mit Signatur hoch und liest wieder', () async {
      final stored = <String, Uint8List>{};
      final requests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (request.method == 'PUT') {
          stored[path] = request.bodyBytes;
          return http.Response('', 200);
        }
        if (request.method == 'GET') {
          final data = stored[path];
          return data == null ? http.Response('', 404) : http.Response.bytes(data, 200);
        }
        return http.Response('', 204);
      });
      final store = S3PdfCloudStore(
        const PdfStorageConfig(
          type: PdfStorageType.s3,
          endpoint: 'https://konto.r2.cloudflarestorage.com',
          bucket: 'lernen',
          accessKey: 'AK',
          secret: 'SK',
        ),
        client: client,
        clock: () => DateTime.utc(2026, 9, 26, 12),
      );

      await store.put('lernen-pdfs/a.pdf', Uint8List.fromList([1, 2, 3]));
      expect(await store.get('lernen-pdfs/a.pdf'), [1, 2, 3]);
      expect(await store.get('lernen-pdfs/fehlt.pdf'), isNull);

      final put = requests.first;
      expect(put.url.toString(), 'https://konto.r2.cloudflarestorage.com/lernen/lernen-pdfs/a.pdf');
      expect(put.headers['Authorization'], startsWith('AWS4-HMAC-SHA256 Credential=AK/20260926/auto/s3/aws4_request'));
      expect(put.headers['x-amz-date'], '20260926T120000Z');
      expect(put.headers.containsKey('host'), isFalse);
    });

    test('verständliche Fehlermeldung bei falschen Zugangsdaten', () async {
      final store = S3PdfCloudStore(
        const PdfStorageConfig(type: PdfStorageType.s3, endpoint: 'https://s3.example.com', bucket: 'b', accessKey: 'a', secret: 's'),
        client: MockClient((_) async => http.Response('', 403)),
      );
      expect(
        store.testConnection,
        throwsA(isA<PdfCloudStoreException>().having((e) => e.message, 'message', contains('Zugangsdaten'))),
      );
    });
  });

  group('WebDavPdfCloudStore', () {
    test('legt fehlenden Ordner an und nutzt Basic-Auth', () async {
      final calls = <String>[];
      var folderExists = false;
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        expect(request.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('nutzer:pw'))}');
        if (request.method == 'MKCOL') {
          folderExists = true;
          return http.Response('', 201);
        }
        if (request.method == 'PUT') return http.Response('', folderExists ? 201 : 409);
        return http.Response('', 200);
      });
      final store = WebDavPdfCloudStore(
        const PdfStorageConfig(
          type: PdfStorageType.webdav,
          endpoint: 'https://cloud.example.de/remote.php/dav/files/nutzer/Lernen/',
          accessKey: 'nutzer',
          secret: 'pw',
        ),
        client: client,
      );
      await store.put('lernen-pdfs/a.pdf', Uint8List.fromList([9]));
      expect(calls, [
        'PUT /remote.php/dav/files/nutzer/Lernen/lernen-pdfs/a.pdf',
        'MKCOL /remote.php/dav/files/nutzer/Lernen/lernen-pdfs',
        'PUT /remote.php/dav/files/nutzer/Lernen/lernen-pdfs/a.pdf',
      ]);
    });
  });

  test('ohne vollständige Zugangsdaten gibt es keinen Speicher', () {
    expect(PdfCloudStore.fromConfig(const PdfStorageConfig()), isNull);
    expect(PdfCloudStore.fromConfig(const PdfStorageConfig(type: PdfStorageType.s3, endpoint: 'https://x', accessKey: 'a', secret: 's')), isNull);
    expect(
      PdfCloudStore.fromConfig(const PdfStorageConfig(type: PdfStorageType.webdav, endpoint: 'https://x', accessKey: 'a', secret: 's')),
      isA<WebDavPdfCloudStore>(),
    );
  });
}
