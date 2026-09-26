import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/pdf_storage_config.dart';

class PdfCloudStoreException implements Exception {
  PdfCloudStoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Eigener Dateispeicher des Nutzers für die Original-PDFs (siehe
/// PdfStorageConfig). Bewusst ohne SDK – reine HTTP-Aufrufe, damit es auf
/// allen Plattformen gleich funktioniert (im Web muss der Speicher dafür
/// CORS erlauben).
abstract class PdfCloudStore {
  Future<void> put(String key, Uint8List bytes);

  /// null, wenn es die Datei dort nicht gibt.
  Future<Uint8List?> get(String key);

  Future<void> delete(String key);

  /// Prüft Erreichbarkeit und Zugangsdaten; wirft [PdfCloudStoreException]
  /// mit verständlicher Meldung.
  Future<void> testConnection();

  static PdfCloudStore? fromConfig(PdfStorageConfig config, {http.Client? client}) {
    if (!config.isConfigured) return null;
    return switch (config.type) {
      PdfStorageType.s3 => S3PdfCloudStore(config, client: client),
      PdfStorageType.webdav => WebDavPdfCloudStore(config, client: client),
      PdfStorageType.none => null,
    };
  }

  /// Objektname einer Material-PDF im Speicher.
  static String keyForMaterial(String materialId) => 'lernen-pdfs/$materialId.pdf';
}

String _statusHint(int status) => switch (status) {
      401 || 403 => 'Zugriff verweigert – Zugangsdaten prüfen',
      404 => 'nicht gefunden – Adresse/Bucket prüfen',
      _ => 'HTTP $status',
    };

// ---------------------------------------------------------------------------
// S3-kompatibel (AWS Signature Version 4)
// ---------------------------------------------------------------------------

/// Signiert S3-Anfragen nach AWS Signature Version 4 – rein, testbar gegen
/// die offiziellen Beispielwerte aus der AWS-Dokumentation.
class S3Signer {
  S3Signer({required this.accessKey, required this.secretKey, required this.region, this.service = 's3'});

  final String accessKey;
  final String secretKey;
  final String region;
  final String service;

  static const emptyPayloadHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  static String hashPayload(List<int> body) => sha256.convert(body).toString();

  /// URI-Kodierung nach AWS-Vorgabe: alles außer A-Z a-z 0-9 - _ . ~ wird
  /// kodiert; `/` bleibt im Pfad erhalten.
  static String encodePath(String path) => path.split('/').map(_encodeSegment).join('/');

  static String _encodeSegment(String segment) {
    final buffer = StringBuffer();
    for (final byte in utf8.encode(segment)) {
      final c = String.fromCharCode(byte);
      if (RegExp(r'[A-Za-z0-9\-_.~]').hasMatch(c)) {
        buffer.write(c);
      } else {
        buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return buffer.toString();
  }

  static String amzDate(DateTime utc) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  /// Liefert die zu setzenden Header inkl. `Authorization`. [headers] muss
  /// `host`, `x-amz-date` und `x-amz-content-sha256` enthalten; alle
  /// übergebenen Header werden mitsigniert.
  Map<String, String> sign({
    required String method,
    required String canonicalPath,
    required Map<String, String> headers,
    required String payloadHash,
  }) {
    final lower = {for (final e in headers.entries) e.key.toLowerCase(): e.value.trim()};
    final names = lower.keys.toList()..sort();
    final canonicalHeaders = names.map((n) => '$n:${lower[n]}\n').join();
    final signedHeaders = names.join(';');
    final canonicalRequest = [method, canonicalPath, '', canonicalHeaders, signedHeaders, payloadHash].join('\n');

    final dateTime = lower['x-amz-date']!;
    final date = dateTime.substring(0, 8);
    final scope = '$date/$region/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      dateTime,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    List<int> hmac(List<int> key, String data) => Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    final kDate = hmac(utf8.encode('AWS4$secretKey'), date);
    final kRegion = hmac(kDate, region);
    final kService = hmac(kRegion, service);
    final kSigning = hmac(kService, 'aws4_request');
    final signature = Hmac(sha256, kSigning).convert(utf8.encode(stringToSign)).toString();

    return {
      ...headers,
      'Authorization': 'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    };
  }
}

class S3PdfCloudStore implements PdfCloudStore {
  S3PdfCloudStore(this.config, {http.Client? client, DateTime Function()? clock})
      : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final PdfStorageConfig config;
  final http.Client _client;
  final DateTime Function() _clock;

  Uri _uriFor(String key) {
    final base = Uri.parse(config.endpoint.trim());
    final bucket = config.bucket.trim();
    final basePath = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
    if (config.pathStyle) {
      return base.replace(path: '$basePath/$bucket/$key');
    }
    return base.replace(host: '$bucket.${base.host}', path: '$basePath/$key');
  }

  Future<http.Response> _send(String method, String key, {Uint8List? body}) async {
    final uri = _uriFor(key);
    final payloadHash = body == null ? S3Signer.emptyPayloadHash : S3Signer.hashPayload(body);
    final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    final signer = S3Signer(
      accessKey: config.accessKey.trim(),
      secretKey: config.secret,
      region: config.region.trim().isEmpty ? 'auto' : config.region.trim(),
    );
    final signed = signer.sign(
      method: method,
      canonicalPath: S3Signer.encodePath(uri.path),
      headers: {
        'host': host,
        'x-amz-date': S3Signer.amzDate(_clock().toUtc()),
        'x-amz-content-sha256': payloadHash,
      },
      payloadHash: payloadHash,
    );
    // "host" setzt der HTTP-Client selbst (im Browser ist das Setzen sogar
    // verboten) – nur mitsigniert, nicht mitgeschickt.
    final headers = Map.of(signed)..remove('host');
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) {
      request
        ..bodyBytes = body
        ..headers['content-type'] = 'application/pdf';
    }
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (e) {
      throw PdfCloudStoreException('Speicher nicht erreichbar: ${e.message}');
    }
  }

  @override
  Future<void> put(String key, Uint8List bytes) async {
    final response = await _send('PUT', key, body: bytes);
    if (response.statusCode >= 300) {
      throw PdfCloudStoreException('Hochladen fehlgeschlagen (${_statusHint(response.statusCode)}).');
    }
  }

  @override
  Future<Uint8List?> get(String key) async {
    final response = await _send('GET', key);
    if (response.statusCode == 404) return null;
    if (response.statusCode >= 300) {
      throw PdfCloudStoreException('Herunterladen fehlgeschlagen (${_statusHint(response.statusCode)}).');
    }
    return response.bodyBytes;
  }

  @override
  Future<void> delete(String key) async {
    final response = await _send('DELETE', key);
    if (response.statusCode >= 300 && response.statusCode != 404) {
      throw PdfCloudStoreException('Löschen fehlgeschlagen (${_statusHint(response.statusCode)}).');
    }
  }

  @override
  Future<void> testConnection() async {
    // Nicht existierende Datei abfragen: 404 = Zugang ok, 403 = Schlüssel falsch.
    final response = await _send('HEAD', 'lernen-pdfs/.verbindungstest');
    if (response.statusCode == 404 || response.statusCode < 300) return;
    throw PdfCloudStoreException('Verbindung fehlgeschlagen (${_statusHint(response.statusCode)}).');
  }
}

// ---------------------------------------------------------------------------
// WebDAV (Nextcloud, Uni-Cloud, …)
// ---------------------------------------------------------------------------

class WebDavPdfCloudStore implements PdfCloudStore {
  WebDavPdfCloudStore(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final PdfStorageConfig config;
  final http.Client _client;

  String get _base {
    final url = config.endpoint.trim();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Uri _uriFor(String path) => Uri.parse('$_base/${path.split('/').map(Uri.encodeComponent).join('/')}');

  Map<String, String> get _auth => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('${config.accessKey.trim()}:${config.secret}'))}',
      };

  Future<http.Response> _send(String method, String path, {Uint8List? body, Map<String, String>? headers}) async {
    final request = http.Request(method, _uriFor(path))..headers.addAll({..._auth, ...?headers});
    if (body != null) request.bodyBytes = body;
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (e) {
      throw PdfCloudStoreException('Speicher nicht erreichbar: ${e.message}');
    }
  }

  @override
  Future<void> put(String key, Uint8List bytes) async {
    var response = await _send('PUT', key, body: bytes, headers: {'content-type': 'application/pdf'});
    if (response.statusCode == 404 || response.statusCode == 409) {
      // Zielordner fehlt – anlegen (MKCOL), dann erneut versuchen.
      final segments = key.split('/')..removeLast();
      for (var i = 1; i <= segments.length; i++) {
        await _send('MKCOL', segments.take(i).join('/'));
      }
      response = await _send('PUT', key, body: bytes, headers: {'content-type': 'application/pdf'});
    }
    if (response.statusCode >= 300) {
      throw PdfCloudStoreException('Hochladen fehlgeschlagen (${_statusHint(response.statusCode)}).');
    }
  }

  @override
  Future<Uint8List?> get(String key) async {
    final response = await _send('GET', key);
    if (response.statusCode == 404) return null;
    if (response.statusCode >= 300) {
      throw PdfCloudStoreException('Herunterladen fehlgeschlagen (${_statusHint(response.statusCode)}).');
    }
    return response.bodyBytes;
  }

  @override
  Future<void> delete(String key) async {
    final response = await _send('DELETE', key);
    if (response.statusCode >= 300 && response.statusCode != 404) {
      throw PdfCloudStoreException('Löschen fehlgeschlagen (${_statusHint(response.statusCode)}).');
    }
  }

  @override
  Future<void> testConnection() async {
    final request = http.Request('PROPFIND', Uri.parse('$_base/'))..headers.addAll({..._auth, 'Depth': '0'});
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (e) {
      throw PdfCloudStoreException('Speicher nicht erreichbar: ${e.message}');
    }
    if (response.statusCode == 207 || response.statusCode < 300) return;
    throw PdfCloudStoreException('Verbindung fehlgeschlagen (${_statusHint(response.statusCode)}).');
  }
}
