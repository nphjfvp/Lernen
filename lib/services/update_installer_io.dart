import 'dart:io';

import 'package:http/http.dart' as http;

/// Windows: das Setup (Lernen-Setup.exe) lässt sich direkt aus der App
/// herunterladen und still installieren.
bool get canInstallUpdateInApp => Platform.isWindows;

/// Lädt das Setup ins Temp-Verzeichnis und startet es still
/// (Fortschrittsfenster, keine Fragen). Die App beendet sich danach selbst,
/// damit ihre Dateien ersetzt werden können; das Setup startet sie nach der
/// Installation wieder (siehe windows/installer/lernen.iss). `false`, wenn
/// Download oder Start scheitern – dann bleibt die App offen.
Future<bool> installUpdate(String setupUrl, {http.Client? client, void Function(double progress)? onProgress}) async {
  if (!Platform.isWindows) return false;
  final File setup;
  try {
    final dir = await Directory.systemTemp.createTemp('lernen-update-');
    setup = await downloadSetup(setupUrl, dir, client: client, onProgress: onProgress);
  } catch (_) {
    return false;
  }
  try {
    await Process.start(
      setup.path,
      const ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
  } catch (_) {
    return false;
  }
  exit(0);
}

/// Lädt das Setup nach [dir] und prüft grob, dass wirklich ein Programm
/// ankam (Windows-Programme beginnen mit "MZ") und keine Fehlerseite.
Future<File> downloadSetup(
  String url,
  Directory dir, {
  http.Client? client,
  void Function(double progress)? onProgress,
}) async {
  final http0 = client ?? http.Client();
  final response = await http0.send(http.Request('GET', Uri.parse(url)));
  if (response.statusCode != 200) {
    throw HttpException('Download fehlgeschlagen (${response.statusCode})', uri: Uri.parse(url));
  }
  final file = File('${dir.path}${Platform.pathSeparator}Lernen-Setup.exe');
  final sink = file.openWrite();
  final total = response.contentLength ?? 0;
  var received = 0;
  final head = <int>[];
  try {
    await for (final chunk in response.stream) {
      if (head.length < 2) head.addAll(chunk.take(2 - head.length));
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
  } finally {
    await sink.close();
  }
  if (head.length < 2 || head[0] != 0x4D || head[1] != 0x5A) {
    await file.delete();
    throw const FormatException('Die heruntergeladene Datei ist kein Windows-Programm.');
  }
  return file;
}
