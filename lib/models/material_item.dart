enum MaterialKind { slide, exercise }

MaterialKind materialKindFromString(String value) =>
    MaterialKind.values.firstWhere((e) => e.name == value);

/// Eine hochgeladene Datei (Foliensatz oder Übungsaufgabe) samt extrahiertem
/// Text, der als Grundlage für Vorbereiten-/Nachbereiten-Modus sowie den
/// Frage-Chat dient.
class MaterialItem {
  final String id;
  final String moduleId;
  final String fileName;
  final MaterialKind kind;
  final String extractedText;
  final DateTime createdAt;

  /// Ob dieses Material im Unterricht bereits behandelt wurde. Rein
  /// informativ/manuell gepflegt (kein Zugriffs-Gate): der Nutzer kann
  /// bewusst weiter vorarbeiten, bevor ein Thema dran war – der Status
  /// dient nur als zusätzlicher Kontext für den Frage-Chat (z.B. um
  /// einzuordnen, ob etwas schon in der Vorlesung war oder nur selbst
  /// vorab hochgeladen wurde).
  final bool covered;

  /// Kurzer, von der KI erzeugter Index-Eintrag (Themen + grobe
  /// Kurzfassung) für den Frage-Chat: bevor eine Frage beantwortet wird,
  /// sieht die KI zuerst nur diese Kurzfassungen ALLER Materialien und
  /// entscheidet, welche für die konkrete Frage genauer angesehen werden
  /// müssen – so muss nicht der komplette Foliensatz jedes Mal im Kontext
  /// landen. Null, solange das Material noch nicht indiziert wurde (wird
  /// beim ersten Chat lazy nachgeholt, siehe ModuleChatScreen).
  final String? topicIndex;

  const MaterialItem({
    required this.id,
    required this.moduleId,
    required this.fileName,
    required this.kind,
    required this.extractedText,
    required this.createdAt,
    this.covered = false,
    this.topicIndex,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'fileName': fileName,
        'kind': kind.name,
        'extractedText': extractedText,
        'createdAt': createdAt.toIso8601String(),
        'covered': covered,
        'topicIndex': topicIndex,
      };

  factory MaterialItem.fromMap(Map<String, dynamic> map) => MaterialItem(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        fileName: map['fileName'] as String,
        kind: materialKindFromString(map['kind'] as String),
        extractedText: map['extractedText'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        covered: map['covered'] as bool? ?? false,
        topicIndex: map['topicIndex'] as String?,
      );
}
