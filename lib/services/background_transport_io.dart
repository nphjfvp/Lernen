import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'background_transport_base.dart';

/// KI-Anfragen unter Android über WorkManager (Paket background_downloader):
/// Die Anfrage läuft nativ als Hintergrund-Job weiter, auch wenn Android die
/// App im Hintergrund einfriert (sonst reißt die Verbindung ab, sobald man die
/// App kurz verlässt). Die Antwort kommt beim Zurückkehren an.
///
/// Wichtig: WorkManager nimmt höchstens 10 KB Daten je Job – größere Anfragen
/// (Lernpfad, PDF-Import …) ließen die App sonst abstürzen. Sie gehen deshalb
/// als Datei-Upload raus (im Job steht nur der Dateipfad).
class BackgroundTransport {
  BackgroundTransport._();

  /// Bis zu so vielen Bytes geht der Inhalt direkt im Job mit (mit Abstand
  /// zur 10-KB-Grenze, weil er dort noch einmal als JSON verpackt wird).
  static const inlineLimit = 3000;

  static Future<void>? _configured;

  /// Lange Wartezeit erlauben: Große Aufgaben brauchen bei der KI mehrere
  /// Minuten, bevor das erste Byte kommt (Standard wären 60 s).
  static Future<void> configure() => _configured ??= FileDownloader()
      .configure(globalConfig: [(Config.requestTimeout, const Duration(minutes: 15))])
      .then((_) {});

  static Future<http.Response> send(Uri url, Map<String, String> headers, String body, String label) async {
    await configure();
    final bytes = utf8.encode(body);
    final cleanHeaders = {
      for (final e in headers.entries)
        if (e.key.toLowerCase() != 'content-type') e.key: e.value,
    };
    final inline = bytes.length <= inlineLimit;
    final marker = await AiCrashGuard.mark(
      label: label,
      bytes: bytes.length,
      via: inline ? 'Hintergrund' : 'Hintergrund (Datei)',
    );
    File? file;
    try {
      final TaskStatusUpdate result;
      if (inline) {
        result = await FileDownloader().transmit(
          DataTask(
            url: url.toString(),
            headers: cleanHeaders,
            httpRequestMethod: 'POST',
            post: body,
            contentType: 'application/json',
            displayName: 'KI-Anfrage',
          ),
        );
      } else {
        final task = UploadTask(
          url: url.toString(),
          filename: 'ki-anfrage-${DateTime.now().microsecondsSinceEpoch}.json',
          baseDirectory: BaseDirectory.temporary,
          // Kein Content-Disposition-Kopf: OpenRouter erwartet reines JSON.
          headers: {...cleanHeaders, 'Content-Disposition': ''},
          httpRequestMethod: 'POST',
          post: 'binary',
          mimeType: 'application/json',
          displayName: 'KI-Anfrage',
        );
        file = File(await task.filePath());
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        result = await FileDownloader().upload(task);
      }
      final code = result.responseStatusCode;
      if (code == null || code == 0) {
        throw BackgroundTransportException(result.exception?.description ?? 'Übertragung ${result.status.name}');
      }
      return http.Response(
        result.responseBody ?? result.exception?.description ?? '',
        code,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    } finally {
      await AiCrashGuard.clear(marker);
      if (file != null) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }
}

/// Merkt sich laufende KI-Anfragen in kleinen Dateien – wird die App mittendrin
/// beendet (z.B. ein Absturz im nativen Hintergrund-Dienst, den Dart nicht
/// abfangen kann), findet der nächste Start die Notiz und kann es klar melden.
class AiCrashGuard {
  AiCrashGuard._();

  static Future<Directory> _dir() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/ai_pending');
    await dir.create(recursive: true);
    return dir;
  }

  /// Notiz für eine laufende Aufgabe ([label]); mit [clear] wieder entfernen.
  static Future<Object?> mark({required String label, required int bytes, required String via}) async {
    try {
      final file = File('${(await _dir()).path}/${DateTime.now().microsecondsSinceEpoch}.json');
      await file.writeAsString(
        jsonEncode({'label': label, 'bytes': bytes, 'via': via, 'startedAt': DateTime.now().toIso8601String()}),
        flush: true,
      );
      return file;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(Object? marker) async {
    try {
      if (marker is File) await marker.delete();
    } catch (_) {}
  }

  /// Notizen vom letzten Lauf (und löscht sie) – leer, wenn alles sauber endete.
  static Future<List<PendingAiRequest>> takePending() async {
    final out = <PendingAiRequest>[];
    try {
      for (final f in (await _dir()).listSync().whereType<File>()) {
        try {
          final m = jsonDecode(await f.readAsString()) as Map;
          out.add((
            label: '${m['label'] ?? ''}',
            bytes: (m['bytes'] as num?)?.toInt() ?? 0,
            via: '${m['via'] ?? ''}',
            startedAt: DateTime.tryParse('${m['startedAt']}') ?? DateTime.now(),
          ));
        } catch (_) {}
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (_) {}
    out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out;
  }
}
