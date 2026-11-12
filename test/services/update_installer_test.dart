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

  /// Kleinstes gültiges ZIP-Ende: Abschluss-Eintrag mit [comment] Bytes Kommentar.
  List<int> zipEnd({int comment = 0}) => [
    0x50, 0x4B, 0x05, 0x06, ...List.filled(16, 0), comment & 0xff, comment >> 8, ...List.filled(comment, 0x20), //
  ];

  test('abgebrochener Download: nichts bleibt liegen, der nächste Versuch lädt neu', () async {
    final full = Uint8List.fromList([0x50, 0x4B, 3, 4, ...List.filled(4000, 9), ...zipEnd()]);
    // Die Verbindung liefert weniger, als angekündigt war.
    final cut = MockClient.streaming(
      (_, _) async => http.StreamedResponse(Stream.value(full.sublist(0, 1500)), 200, contentLength: full.length),
    );
    await expectLater(
      downloadUpdateFile(
        'https://example.org/app.apk',
        dir,
        fileName: 'Lernen-159.apk',
        magic: apkMagic,
        validate: isCompleteApk,
        client: cut,
      ),
      throwsA(isA<HttpException>()),
    );
    expect(dir.listSync(), isEmpty, reason: 'keine halbe Datei, die später als fertig gilt');

    // Ohne angekündigte Länge: am fehlenden ZIP-Ende erkannt.
    final noLength = MockClient.streaming(
      (_, _) async => http.StreamedResponse(Stream.value(full.sublist(0, 1500)), 200),
    );
    await expectLater(
      downloadUpdateFile(
        'https://example.org/app.apk',
        dir,
        fileName: 'Lernen-159.apk',
        magic: apkMagic,
        validate: isCompleteApk,
        client: noLength,
      ),
      throwsFormatException,
    );
    expect(dir.listSync(), isEmpty);

    // Bricht der Strom mit einem Fehler ab, bleibt ebenfalls nichts zurück.
    final broken = MockClient.streaming(
      (_, _) async => http.StreamedResponse(
        Stream.fromFutures([Future.value(full.sublist(0, 1500)), Future.error(const SocketException('weg'))]),
        200,
        contentLength: full.length,
      ),
    );
    await expectLater(
      downloadUpdateFile('https://example.org/app.apk', dir, fileName: 'Lernen-159.apk', magic: apkMagic, client: broken),
      throwsA(isA<SocketException>()),
    );
    expect(dir.listSync(), isEmpty);

    final ok = MockClient.streaming(
      (_, _) async => http.StreamedResponse(Stream.value(full), 200, contentLength: full.length),
    );
    final file = await downloadUpdateFile(
      'https://example.org/app.apk',
      dir,
      fileName: 'Lernen-159.apk',
      magic: apkMagic,
      validate: isCompleteApk,
      client: ok,
    );
    expect(file.readAsBytesSync(), full);
    expect(dir.listSync().map((f) => f.path.split(Platform.pathSeparator).last), ['Lernen-159.apk']);
  });

  test('vollständige APK: ZIP-Ende genau am Dateiende – abgeschnittene Dateien gelten nicht', () async {
    File write(String name, List<int> bytes) => File('${dir.path}/$name')..writeAsBytesSync(bytes);
    final body = [0x50, 0x4B, 3, 4, ...List.filled(300, 1)];
    expect(await isCompleteApk(write('ganz.apk', [...body, ...zipEnd()])), isTrue);
    expect(await isCompleteApk(write('kommentar.apk', [...body, ...zipEnd(comment: 12)])), isTrue);
    // Abgeschnitten: beginnt mit „PK“, aber das Ende fehlt.
    expect(await isCompleteApk(write('halb.apk', body)), isFalse);
    expect(await isCompleteApk(write('fast.apk', [...body, ...zipEnd().sublist(0, 20)])), isFalse);
    // Ein Ende mitten in der Datei zählt nicht.
    expect(await isCompleteApk(write('mitte.apk', [...body, ...zipEnd(), 1, 2, 3])), isFalse);
    expect(await isCompleteApk(write('setup.exe', [0x4D, 0x5A, ...zipEnd()])), isFalse);
    expect(await isCompleteApk(File('${dir.path}/fehlt.apk')), isFalse);
    // Große Datei: nur das Ende wird gelesen.
    expect(await isCompleteApk(write('gross.apk', [...body, ...List.filled(200000, 5), ...zipEnd()])), isTrue);
  });

  test('nur Windows und Android installieren aus der App', () async {
    expect(canInstallUpdateInApp, Platform.isWindows || Platform.isAndroid);
    if (!canInstallUpdateInApp) {
      expect(await installUpdate('https://example.org/x.exe'), UpdateInstallResult.failed);
    }
  });
}
