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

  /// Vorlesungstermin dieser Einheit (nur das Datum zählt). Ist er erreicht,
  /// gilt die Einheit automatisch als behandelt ([isCoveredOn]) – sonst
  /// hängt das Daily Quiz daran, dass man nach jeder Vorlesung an das
  /// Häkchen denkt, und vergessene Häkchen hielten deren Karten komplett
  /// zurück.
  final DateTime? scheduledDate;

  const LectureUnit({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.createdAt,
    this.covered = false,
    this.notes = const [],
    this.scheduledDate,
  });

  /// Behandelt = von Hand abgehakt ODER der Termin ist (spätestens heute)
  /// erreicht.
  bool isCoveredOn(DateTime now) {
    if (covered) return true;
    final date = scheduledDate;
    if (date == null) return false;
    return !DateTime(date.year, date.month, date.day).isAfter(DateTime(now.year, now.month, now.day));
  }

  LectureUnit copyWith({
    String? title,
    bool? covered,
    List<String>? notes,
    DateTime? scheduledDate,
    bool clearScheduledDate = false,
  }) =>
      LectureUnit(
        id: id,
        moduleId: moduleId,
        title: title ?? this.title,
        createdAt: createdAt,
        covered: covered ?? this.covered,
        notes: notes ?? this.notes,
        scheduledDate: clearScheduledDate ? null : (scheduledDate ?? this.scheduledDate),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'title': title,
        'covered': covered,
        'createdAt': createdAt.toIso8601String(),
        'notes': notes,
        'scheduledDate': scheduledDate?.toIso8601String(),
      };

  factory LectureUnit.fromMap(Map<String, dynamic> map) => LectureUnit(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        title: map['title'] as String,
        covered: map['covered'] as bool? ?? false,
        createdAt: DateTime.parse(map['createdAt'] as String),
        notes: (map['notes'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        scheduledDate: DateTime.tryParse(map['scheduledDate']?.toString() ?? ''),
      );
}
