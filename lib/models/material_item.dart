enum MaterialKind { slide, exercise }

MaterialKind materialKindFromString(String value) =>
    MaterialKind.values.firstWhere((e) => e.name == value);

/// Eine hochgeladene Datei (Foliensatz oder Übungsaufgabe) samt extrahiertem
/// Text, der als Grundlage für Vorbereiten-/Nachbereiten-Modus dient.
class MaterialItem {
  final String id;
  final String moduleId;
  final String fileName;
  final MaterialKind kind;
  final String extractedText;
  final DateTime createdAt;

  const MaterialItem({
    required this.id,
    required this.moduleId,
    required this.fileName,
    required this.kind,
    required this.extractedText,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'fileName': fileName,
        'kind': kind.name,
        'extractedText': extractedText,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MaterialItem.fromMap(Map<String, dynamic> map) => MaterialItem(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        fileName: map['fileName'] as String,
        kind: materialKindFromString(map['kind'] as String),
        extractedText: map['extractedText'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
