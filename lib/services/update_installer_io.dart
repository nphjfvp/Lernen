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
      // Erlaubnis zum Installieren fehlte – aber nur, wenn die Datei
      // VOLLSTÄNDIG ist: Eine abgebrochene würde Android bei jedem Versuch
      // mit „Problem mit der App-Datei“ ablehnen.
      final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
      final name = 'Lernen-${buildNumber ?? 'neu'}.apk';
      final existing = File('${dir.path}/$name');
      final apk = buildNumber != null && await isCompleteApk(existing)
          ? existing
          : await () async {
              if (await dir.exists()) await dir.delete(recursive: true);
              await dir.create(recursive: true);
              return downloadUpdateFile(url, dir,
                  fileName: name, magic: apkMagic, validate: isCompleteApk, client: client, onProgress: onProgress);
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

/// Ist [file] eine vollständige APK? Eine APK ist ein ZIP – dessen
/// Inhaltsverzeichnis endet mit dem Abschluss-Eintrag („PK\x05\x06“, 22 Bytes
/// plus Kommentar) genau am Dateiende. Fehlt er, ist die Datei abgeschnitten
/// (abgebrochener Download).
Future<bool> isCompleteApk(File file) async {
  if (!await hasMagic(file, apkMagic)) return false;
  const record = 22, maxComment = 65535;
  final length = await file.length();
  if (length < record) return false;
  final start = length > record + maxComment ? length - record - maxComment : 0;
  final tail = await file.openRead(start, length).expand((b) => b).toList();
  for (var i = tail.length - record; i >= 0; i--) {
    if (tail[i] == 0x50 && tail[i + 1] == 0x4B && tail[i + 2] == 0x05 && tail[i + 3] == 0x06) {
      final comment = tail[i + 20] | (tail[i + 21] << 8);
      if (i + record + comment == tail.length) return true;
    }
  }
  return false;
}

/// Lädt [url] als [fileName] nach [dir] und prüft, dass wirklich die
/// erwartete Datei VOLLSTÄNDIG ankam: die ersten Bytes ([magic], keine
/// Fehlerseite), die angekündigte Länge und – falls angegeben – [validate].
/// Geladen wird in eine „.part“-Datei; unter [fileName] liegt nie etwas
/// Halbes. Scheitert etwas, bleibt nichts zurück.
Future<File> downloadUpdateFile(
  String url,
  Directory dir, {
  required String fileName,
  required List<int> magic,
  Future<bool> Function(File file)? validate,
  http.Client? client,
  void Function(double progress)? onProgress,
}) async {
  final httpClient = client ?? http.Client();
  final response = await httpClient.send(http.Request('GET', Uri.parse(url)));
  if (response.statusCode != 200) {
    throw HttpException('Download fehlgeschlagen (${response.statusCode})', uri: Uri.parse(url));
  }
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  final part = File('${file.path}.part');
  final total = response.contentLength ?? 0;
  var received = 0;
  try {
    final sink = part.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
    if (total > 0 && received != total) {
      throw HttpException('Download unvollständig ($received von $total Bytes)', uri: Uri.parse(url));
    }
    if (!await hasMagic(part, magic)) {
      throw const FormatException('Die heruntergeladene Datei ist nicht das erwartete Update.');
    }
    if (validate != null && !await validate(part)) {
      throw const FormatException('Die heruntergeladene Datei ist unvollständig oder beschädigt.');
    }
    if (await file.exists()) await file.delete();
    return await part.rename(file.path);
  } catch (_) {
    if (await part.exists()) await part.delete();
    rethrow;
  }
}
