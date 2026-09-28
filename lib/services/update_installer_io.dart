import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_install_result.dart';

/// Windows (Setup, siehe windows/installer/lernen.iss) und Android (APK)
/// lassen sich direkt aus der App aktualisieren.
bool get canInstallUpdateInApp => Platform.isWindows || Platform.isAndroid;

const _androidChannel = MethodChannel('lernen/update');

/// Lädt das Update herunter und installiert es:
/// - Windows: Setup still starten und die App beenden, damit ihre Dateien
///   ersetzt werden können; das Setup startet sie danach wieder.
/// - Android: APK an den System-Installer übergeben ("Aktualisieren?"). Die
///   APK ist immer mit demselben Schlüssel signiert (android/app/
///   debug.keystore), deshalb installiert sie über die alte App, die Daten
///   bleiben.
Future<UpdateInstallResult> installUpdate(
  String url, {
  int? buildNumber,
  http.Client? client,
  void Function(double progress)? onProgress,
}) async {
  if (Platform.isWindows) {
    final File setup;
    try {
      final dir = await Directory.systemTemp.createTemp('lernen-update-');
      setup = await downloadUpdateFile(url, dir,
          fileName: 'Lernen-Setup.exe', magic: windowsExeMagic, client: client, onProgress: onProgress);
    } catch (_) {
      return UpdateInstallResult.failed;
    }
    try {
      await Process.start(
        setup.path,
        const ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      return UpdateInstallResult.failed;
    }
    exit(0);
  }
  if (Platform.isAndroid) {
    try {
      // Im Cache-Ordner (siehe android/app/src/main/res/xml/update_paths.xml);
      // derselbe Build wird nicht doppelt geladen, z.B. wenn erst noch die
      // Erlaubnis zum Installieren fehlte.
      final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
      final name = 'Lernen-${buildNumber ?? 'neu'}.apk';
      final existing = File('${dir.path}/$name');
      final apk = buildNumber != null && await hasMagic(existing, apkMagic)
          ? existing
          : await () async {
              if (await dir.exists()) await dir.delete(recursive: true);
              await dir.create(recursive: true);
              return downloadUpdateFile(url, dir,
                  fileName: name, magic: apkMagic, client: client, onProgress: onProgress);
            }();
      final status = await _androidChannel.invokeMethod<String>('installApk', {'path': apk.path});
      return switch (status) {
        'started' => UpdateInstallResult.started,
        'needsPermission' => UpdateInstallResult.needsPermission,
        _ => UpdateInstallResult.failed,
      };
    } catch (_) {
      return UpdateInstallResult.failed;
    }
  }
  return UpdateInstallResult.failed;
}

/// Windows-Programme beginnen mit "MZ", APKs (ZIP) mit "PK".
const windowsExeMagic = [0x4D, 0x5A];
const apkMagic = [0x50, 0x4B];

Future<bool> hasMagic(File file, List<int> magic) async {
  if (!await file.exists()) return false;
  final head = await file.openRead(0, magic.length).expand((b) => b).toList();
  return head.length == magic.length && [for (var i = 0; i < magic.length; i++) head[i] == magic[i]].every((b) => b);
}

/// Lädt [url] als [fileName] nach [dir] und prüft über die ersten Bytes
/// ([magic]), dass wirklich die erwartete Datei ankam und keine Fehlerseite.
Future<File> downloadUpdateFile(
  String url,
  Directory dir, {
  required String fileName,
  required List<int> magic,
  http.Client? client,
  void Function(double progress)? onProgress,
}) async {
  final httpClient = client ?? http.Client();
  final response = await httpClient.send(http.Request('GET', Uri.parse(url)));
  if (response.statusCode != 200) {
    throw HttpException('Download fehlgeschlagen (${response.statusCode})', uri: Uri.parse(url));
  }
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  final sink = file.openWrite();
  final total = response.contentLength ?? 0;
  var received = 0;
  try {
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
  } finally {
    await sink.close();
  }
  if (!await hasMagic(file, magic)) {
    await file.delete();
    throw const FormatException('Die heruntergeladene Datei ist nicht das erwartete Update.');
  }
  return file;
}
