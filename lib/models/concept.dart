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
  });

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
      };

  factory Concept.fromMap(Map<String, dynamic> map) => Concept(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        title: map['title'] as String,
        explanation: map['explanation'] as String,
        sourceMaterialIds: List<String>.from(map['sourceMaterialIds'] as List),
        createdAt: DateTime.parse(map['createdAt'] as String),
        unitId: map['unitId'] as String?,
        linkedMaterialId: map['linkedMaterialId'] as String?,
        linkedPageNumber: map['linkedPageNumber'] as int?,
      );
}
