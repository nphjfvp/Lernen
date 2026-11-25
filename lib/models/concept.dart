/// Ergebnis des Nachbereiten-Modus: ein gezieltes Lernkonzept, das aus der
/// gemeinsamen Analyse von Folien UND Übungsaufgaben entstanden ist – der
/// Fokus liegt auf der tiefen Durchdringung der Übungen, nicht nur auf
/// Theorie-Wiedergabe.
class Concept {
  final String id;
  final String moduleId;
  final String title;
  final String explanation;
  final List<String> sourceMaterialIds;
  final DateTime createdAt;

  /// Welcher Vorlesungseinheit (siehe LectureUnit) dieses Konzept
  /// zugeordnet ist – übernommen von der beim Nachbereiten gewählten
  /// Einheit. Null = keine Einheit gewählt.
  final String? unitId;

  /// Quasi-Link zurück zur genauen Stelle, an der dieses Konzept entstanden
  /// ist (siehe MaterialViewerScreen-Button "Konzept speichern" im
  /// Lernmodus): [linkedMaterialId] + [linkedPageNumber] erlauben es, direkt
  /// zu dieser Seite zu springen. Beide null = kein direkter Seitenbezug
  /// (z.B. ein aus Nachbereiten entstandenes Konzept über mehrere Materialien
  /// hinweg, siehe [sourceMaterialIds]).
  final String? linkedMaterialId;
  final int? linkedPageNumber;

  /// Konzepte desselben Fachs, auf denen dieses direkt aufbaut (per KI
  /// bestimmt oder von Hand). Neue Karten dieses Konzepts kommen im Daily
  /// Quiz erst, wenn die Voraussetzungen sitzen (siehe PrerequisiteGate).
  final List<String> prerequisiteIds;

  const Concept({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.explanation,
    required this.sourceMaterialIds,
    required this.createdAt,
    this.unitId,
    this.linkedMaterialId,
    this.linkedPageNumber,
    this.prerequisiteIds = const [],
  });

  Concept copyWith({String? title, String? explanation, List<String>? prerequisiteIds}) => Concept(
        id: id,
        moduleId: moduleId,
        title: title ?? this.title,
        explanation: explanation ?? this.explanation,
        sourceMaterialIds: sourceMaterialIds,
        createdAt: createdAt,
        unitId: unitId,
        linkedMaterialId: linkedMaterialId,
        linkedPageNumber: linkedPageNumber,
        prerequisiteIds: prerequisiteIds ?? this.prerequisiteIds,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'title': title,
        'explanation': explanation,
        'sourceMaterialIds': sourceMaterialIds,
        'createdAt': createdAt.toIso8601String(),
        'unitId': unitId,
        'linkedMaterialId': linkedMaterialId,
        'linkedPageNumber': linkedPageNumber,
        if (prerequisiteIds.isNotEmpty) 'prerequisiteIds': prerequisiteIds,
      };

  factory Concept.fromMap(Map<String, dynamic> map) => Concept(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        title: map['title']?.toString() ?? '',
        explanation: map['explanation']?.toString() ?? '',
        sourceMaterialIds: [for (final id in map['sourceMaterialIds'] as List? ?? const []) id.toString()],
        createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime(2000),
        unitId: map['unitId'] as String?,
        linkedMaterialId: map['linkedMaterialId'] as String?,
        linkedPageNumber: (map['linkedPageNumber'] as num?)?.toInt(),
        prerequisiteIds: [
          for (final id in map['prerequisiteIds'] as List? ?? const [])
            if (id != null && '$id'.isNotEmpty && '$id' != map['id']) '$id',
        ],
      );
}
