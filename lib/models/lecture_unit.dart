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

  const LectureUnit({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.createdAt,
    this.covered = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'title': title,
        'covered': covered,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LectureUnit.fromMap(Map<String, dynamic> map) => LectureUnit(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        title: map['title'] as String,
        covered: map['covered'] as bool? ?? false,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
