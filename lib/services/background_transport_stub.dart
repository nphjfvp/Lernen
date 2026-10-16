import 'package:http/http.dart' as http;

import 'background_transport_base.dart';

/// Platzhalter ohne dart:io (Web): keine Hintergrund-Übertragung.
class BackgroundTransport {
  BackgroundTransport._();

  static Future<http.Response> send(Uri url, Map<String, String> headers, String body, String label) =>
      throw BackgroundTransportException('Hintergrund-Übertragung gibt es hier nicht.');
}

/// Platzhalter ohne dart:io (Web).
class AiCrashGuard {
  AiCrashGuard._();

  static Future<List<PendingAiRequest>> takePending() async => const [];

  static Future<Object?> mark({required String label, required int bytes, required String via}) async => null;

  static Future<void> clear(Object? marker) async {}
}
