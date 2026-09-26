/// Ergebnis des Vorbereiten-Modus: strukturierte Zusammenfassung von
/// Vorlesungsfolien mit hervorgehobenen Kernkonzepten für den schnellen
/// Überblick vor der Vorlesung/Übung.
class Summary {
  final String id;
  final String moduleId;
  final List<String> sourceMaterialIds;
  final String title;
  final String overview;
  final List<String> keyPoints;
  final DateTime createdAt;

  /// Welcher Vorlesungseinheit (siehe LectureUnit) diese Zusammenfassung
  /// zugeordnet ist – übernommen von der beim Vorbereiten gewählten
  /// Einheit. Null = keine Einheit gewählt (z.B. ältere Zusammenfassungen
  /// vor Einführung der Einheiten).
  final String? unitId;

  const Summary({
    required this.id,
    required this.moduleId,
    required this.sourceMaterialIds,
    required this.title,
    required this.overview,
    required this.keyPoints,
    required this.createdAt,
    this.unitId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'sourceMaterialIds': sourceMaterialIds,
        'title': title,
        'overview': overview,
        'keyPoints': keyPoints,
        'createdAt': createdAt.toIso8601String(),
        'unitId': unitId,
      };

  /// Tolerant gegenüber importierten/älteren Datensätzen (fehlende Felder,
  /// Zahlen statt Texte) statt beim Laden abzustürzen.
  factory Summary.fromMap(Map<String, dynamic> map) => Summary(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        sourceMaterialIds: [for (final id in map['sourceMaterialIds'] as List? ?? const []) id.toString()],
        title: map['title']?.toString() ?? '',
        overview: map['overview']?.toString() ?? '',
        keyPoints: [for (final p in map['keyPoints'] as List? ?? const []) p.toString()],
        createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime(2000),
        unitId: map['unitId'] as String?,
      );
}
