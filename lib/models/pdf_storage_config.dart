/// Wo die Original-PDFs geräteübergreifend liegen – im EIGENEN Speicher des
/// Nutzers (analog zum eigenen API-Key): ohne Zugangsdaten bleibt der
/// PDF-Sync einfach aus, Text und Lernstand synchronisieren trotzdem.
enum PdfStorageType { none, s3, webdav }

extension PdfStorageTypeLabel on PdfStorageType {
  String get label => switch (this) {
        PdfStorageType.none => 'Aus',
        PdfStorageType.s3 => 'S3-kompatibel',
        PdfStorageType.webdav => 'WebDAV',
      };
}

/// Zugangsdaten für den eigenen PDF-Speicher.
///  - S3-kompatibel (Cloudflare R2, Backblaze B2, AWS S3, MinIO …):
///    [endpoint] = API-Endpunkt, [bucket], [region] (R2: "auto"),
///    [accessKey]/[secret] = Zugangsschlüssel.
///  - WebDAV (Nextcloud, Uni-Cloud …): [endpoint] = Ordner-URL,
///    [accessKey] = Benutzername, [secret] = (App-)Passwort.
class PdfStorageConfig {
  const PdfStorageConfig({
    this.type = PdfStorageType.none,
    this.endpoint = '',
    this.bucket = '',
    this.region = 'auto',
    this.accessKey = '',
    this.secret = '',
    this.pathStyle = true,
  });

  final PdfStorageType type;
  final String endpoint;
  final String bucket;
  final String region;
  final String accessKey;
  final String secret;

  /// S3: `endpoint/bucket/key` statt `bucket.endpoint/key`. R2, B2 und MinIO
  /// können beides; neue AWS-Buckets brauchen false.
  final bool pathStyle;

  bool get isConfigured {
    if (type == PdfStorageType.none) return false;
    if (endpoint.trim().isEmpty || accessKey.trim().isEmpty || secret.isEmpty) return false;
    return type != PdfStorageType.s3 || bucket.trim().isNotEmpty;
  }

  PdfStorageConfig copyWith({
    PdfStorageType? type,
    String? endpoint,
    String? bucket,
    String? region,
    String? accessKey,
    String? secret,
    bool? pathStyle,
  }) =>
      PdfStorageConfig(
        type: type ?? this.type,
        endpoint: endpoint ?? this.endpoint,
        bucket: bucket ?? this.bucket,
        region: region ?? this.region,
        accessKey: accessKey ?? this.accessKey,
        secret: secret ?? this.secret,
        pathStyle: pathStyle ?? this.pathStyle,
      );

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'endpoint': endpoint,
        'bucket': bucket,
        'region': region,
        'accessKey': accessKey,
        'secret': secret,
        'pathStyle': pathStyle,
      };

  factory PdfStorageConfig.fromMap(Map<String, dynamic> map) => PdfStorageConfig(
        type: PdfStorageType.values.firstWhere((t) => t.name == map['type'], orElse: () => PdfStorageType.none),
        endpoint: map['endpoint']?.toString() ?? '',
        bucket: map['bucket']?.toString() ?? '',
        region: map['region']?.toString() ?? 'auto',
        accessKey: map['accessKey']?.toString() ?? '',
        secret: map['secret']?.toString() ?? '',
        pathStyle: map['pathStyle'] as bool? ?? true,
      );
}
