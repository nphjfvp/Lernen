import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/update_install_result.dart';
import 'package:lernen/services/update_installer_io.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('lernen_update_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('lädt das Setup herunter und meldet den Fortschritt', () async {
    final bytes = Uint8List.fromList([0x4D, 0x5A, ...List.filled(5000, 7)]);
    final progress = <double>[];
    final client = MockClient.streaming((request, _) async {
      expect(request.url.toString(), endsWith('/Lernen-Setup.exe'));
      return http.StreamedResponse(
        Stream.fromIterable([bytes.sublist(0, 1), bytes.sublist(1, 2000), bytes.sublist(2000)]),
        200,
        contentLength: bytes.length,
      );
    });
    final file = await downloadUpdateFile(
      'https://example.org/Lernen-Setup.exe',
      dir,
      fileName: 'Lernen-Setup.exe',
      magic: windowsExeMagic,
      client: client,
      onProgress: progress.add,
    );
    expect(file.path, endsWith('Lernen-Setup.exe'));
    expect(file.readAsBytesSync(), bytes);
    expect(progress.last, 1.0);
  });

  test('Fehlerseite oder HTTP-Fehler statt Programm wird abgelehnt', () async {
    final html = MockClient((_) async => http.Response('<html>Not Found</html>', 200));
    await expectLater(
      downloadUpdateFile('https://example.org/x.exe', dir, fileName: 'x.exe', magic: windowsExeMagic, client: html),
      throwsFormatException,
    );
    expect(dir.listSync(), isEmpty);

    final notFound = MockClient((_) async => http.Response('nope', 404));
    await expectLater(
      downloadUpdateFile('https://example.org/x.exe', dir, fileName: 'x.exe', magic: windowsExeMagic, client: notFound),
      throwsA(isA<HttpException>()),
    );
  });

  test('APK: am "PK"-Anfang erkannt, ein Setup gilt nicht als APK', () async {
    final apk = MockClient((_) async => http.Response.bytes([0x50, 0x4B, 3, 4, 1, 2, 3], 200));
    final file = await downloadUpdateFile('https://example.org/app.apk', dir,
        fileName: 'Lernen-60.apk', magic: apkMagic, client: apk);
    expect(await hasMagic(file, apkMagic), isTrue);
    expect(await hasMagic(file, windowsExeMagic), isFalse);
    expect(await hasMagic(File('${dir.path}/fehlt.apk'), apkMagic), isFalse);
  });

  test('nur Windows und Android installieren aus der App', () async {
    expect(canInstallUpdateInApp, Platform.isWindows || Platform.isAndroid);
    if (!canInstallUpdateInApp) {
      expect(await installUpdate('https://example.org/x.exe'), UpdateInstallResult.failed);
    }
  });
}
