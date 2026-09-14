/// Eine Vorlesungseinheit ("Einheit 1", "Woche 3: Diffgleichungen", ...)
/// innerhalb eines Fachs. Bündelt die zu dieser Einheit gehörenden
/// Materialien/Konzepte/Karteikarten (siehe `unitId` auf [MaterialItem],
/// [Concept], [Flashcard]) und trägt selbst den "behandelt"-Status:
///
/// Anders als [MaterialItem.covered] (rein informativ, nur Chat-Kontext)
/// ist [covered] hier das eigentliche Zugriffs-Gate fürs Daily Quiz (siehe
/// DailySchedulerService.buildPlan) – so kann man ruhig den ganzen
/// Semesterstoff im Voraus hochladen (mehrere Einheiten anlegen und mit
/// Material füllen) und schaltet Karteikarten trotzdem erst frei, sobald
/// die jeweilige Einheit in der Vorlesung wirklich dran war.
class LectureUnit {
  final String id;
  final String moduleId;
  final String title;
  final bool covered;
  final DateTime createdAt;

  /// Freie Textnotizen zu dieser Einheit (eigene Zusammenfassung,
  /// Merksätze, offene Fragen, ...) – direkt in der Einheit selbst editierbar
  /// (siehe ModuleDetailScreen), unabhängig von der einzelnen
  /// Material-Notiz (siehe MaterialItem.notes, die an EINE Datei gebunden
  /// ist statt an die ganze Einheit). Leere Liste = alte Einheiten vor
  /// Einführung dieses Felds, oder einfach noch keine Notiz angelegt.
  final List<String> notes;

  const LectureUnit({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.createdAt,
    this.covered = false,
    this.notes = const [],
  });

  LectureUnit copyWith({List<String>? notes}) => LectureUnit(
        id: id,
        moduleId: moduleId,
        title: title,
        createdAt: createdAt,
        covered: covered,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'title': title,
        'covered': covered,
        'createdAt': createdAt.toIso8601String(),
        'notes': notes,
      };

  factory LectureUnit.fromMap(Map<String, dynamic> map) => LectureUnit(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        title: map['title'] as String,
        covered: map['covered'] as bool? ?? false,
        createdAt: DateTime.parse(map['createdAt'] as String),
        notes: (map['notes'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}
