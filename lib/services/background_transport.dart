import 'package:background_downloader/background_downloader.dart';
import 'package:http/http.dart' as http;

/// Die Übertragung selbst ist gescheitert (keine HTTP-Antwort) – dann
/// versucht es [AiService] auf dem normalen Weg.
class BackgroundTransportException implements Exception {
  BackgroundTransportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// KI-Anfragen unter Android über WorkManager (Paket background_downloader):
/// Die Anfrage läuft nativ als Hintergrund-Job weiter, auch wenn Android die
/// App im Hintergrund einfriert (sonst reißt die Verbindung ab, sobald man die
/// App kurz verlässt). Die Antwort kommt beim Zurückkehren an.
class BackgroundTransport {
  BackgroundTransport._();

  static Future<void>? _configured;

  /// Lange Wartezeit erlauben: Große Aufgaben brauchen bei der KI mehrere
  /// Minuten, bevor das erste Byte kommt (Standard wären 60 s).
  static Future<void> configure() => _configured ??= FileDownloader()
      .configure(globalConfig: [(Config.requestTimeout, const Duration(minutes: 15))])
      .then((_) {});

  static Future<http.Response> send(Uri url, Map<String, String> headers, String body) async {
    await configure();
    final task = DataTask(
      url: url.toString(),
      headers: {
        for (final e in headers.entries)
          if (e.key.toLowerCase() != 'content-type') e.key: e.value,
      },
      httpRequestMethod: 'POST',
      post: body,
      contentType: 'application/json',
      displayName: 'KI-Anfrage',
    );
    final result = await FileDownloader().transmit(task);
    final code = result.responseStatusCode;
    if (code == null || code == 0) {
      throw BackgroundTransportException(result.exception?.description ?? 'Übertragung ${result.status.name}');
    }
    return http.Response(result.responseBody ?? '', code, headers: {'content-type': 'application/json; charset=utf-8'});
  }
}
