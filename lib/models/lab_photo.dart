import 'dart:convert';
import 'dart:typed_data';

/// Ein Foto zu einem Laborversuch (Messprotokoll, Geräteanzeige, Aufbau …),
/// optional einem Versuchsteil zugeordnet. Die Bilder liegen nur auf diesem
/// Gerät (eigener Speicher, siehe LabPhotoRepository) – die ausgelesenen Werte
/// stehen im Versuch selbst und reisen mit dem Sync.
class LabPhoto {
  const LabPhoto({
    required this.id,
    required this.experimentId,
    required this.moduleId,
    required this.base64,
    required this.createdAt,
    this.partId,
    this.description = '',
  });

  final String id;
  final String experimentId;
  final String moduleId;
  final String base64;
  final DateTime createdAt;

  /// Versuchsteil, zu dem das Foto gehört (null: zum ganzen Versuch).
  final String? partId;

  /// Was auf dem Foto zu sehen ist (von der KI, änderbar).
  final String description;

  Uint8List get bytes => base64Decode(base64);

  Map<String, dynamic> toMap() => {
    'id': id,
    'experimentId': experimentId,
    'moduleId': moduleId,
    'base64': base64,
    'createdAt': createdAt.toIso8601String(),
    'partId': partId,
    'description': description,
  };

  factory LabPhoto.fromMap(Map<String, dynamic> map) => LabPhoto(
    id: map['id'].toString(),
    experimentId: (map['experimentId'] ?? '').toString(),
    moduleId: (map['moduleId'] ?? '').toString(),
    base64: (map['base64'] ?? '').toString(),
    createdAt: DateTime.tryParse('${map['createdAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    partId: map['partId']?.toString(),
    description: (map['description'] ?? '').toString(),
  );
}
