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

  const Summary({
    required this.id,
    required this.moduleId,
    required this.sourceMaterialIds,
    required this.title,
    required this.overview,
    required this.keyPoints,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'sourceMaterialIds': sourceMaterialIds,
        'title': title,
        'overview': overview,
        'keyPoints': keyPoints,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Summary.fromMap(Map<String, dynamic> map) => Summary(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        sourceMaterialIds: List<String>.from(map['sourceMaterialIds'] as List),
        title: map['title'] as String,
        overview: map['overview'] as String,
        keyPoints: List<String>.from(map['keyPoints'] as List),
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
