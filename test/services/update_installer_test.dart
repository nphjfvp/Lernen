import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
    final file = await downloadSetup(
      'https://example.org/Lernen-Setup.exe',
      dir,
      client: client,
      onProgress: progress.add,
    );
    expect(file.path, endsWith('Lernen-Setup.exe'));
    expect(file.readAsBytesSync(), bytes);
    expect(progress.last, 1.0);
  });

  test('Fehlerseite oder HTTP-Fehler statt Programm wird abgelehnt', () async {
    final html = MockClient((_) async => http.Response('<html>Not Found</html>', 200));
    await expectLater(downloadSetup('https://example.org/x.exe', dir, client: html), throwsFormatException);
    expect(dir.listSync(), isEmpty);

    final notFound = MockClient((_) async => http.Response('nope', 404));
    await expectLater(downloadSetup('https://example.org/x.exe', dir, client: notFound), throwsA(isA<HttpException>()));
  });

  test('außerhalb von Windows keine Installation aus der App', () async {
    expect(canInstallUpdateInApp, Platform.isWindows);
    if (!Platform.isWindows) expect(await installUpdate('https://example.org/x.exe'), isFalse);
  });
}
