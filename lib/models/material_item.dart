enum MaterialKind { slide, exercise, practiceExam }

MaterialKind materialKindFromString(String value) =>
    MaterialKind.values.firstWhere((e) => e.name == value);

/// Farbkategorie einer Nutzer- oder KI-Markierung (siehe [MaterialHighlight]):
/// rot = eignet sich als Prüfungsfrage, grün = Antwort/Schlüsselfakt dazu,
/// gelb = sonst einfach wichtig/relevant ohne genauere Zuordnung.
enum HighlightColor { red, green, yellow }

HighlightColor highlightColorFromString(String? value) => HighlightColor.values.firstWhere(
      (e) => e.name == value,
      orElse: () => HighlightColor.yellow,
    );

/// Wer die Markierung erzeugt hat: der Nutzer selbst (durch Textauswahl in
/// [MaterialViewerScreen]) oder die KI (via [AiService.suggestHighlights]).
enum HighlightSource { manual, ai }

HighlightSource highlightSourceFromString(String? value) => HighlightSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => HighlightSource.manual,
    );

/// Eine einzelne markierte Textstelle auf einer hochgeladenen Folie. [text]
/// ist der exakte Original-Textausschnitt (Grundlage sowohl für die visuelle
/// Platzierung im PDF als auch für den an die KI weitergereichten Kontext),
/// unabhängig davon, ob die Stelle im PDF wiedergefunden und visuell als
/// Annotation platziert werden konnte (siehe [pageNumber]).
class MaterialHighlight {
  const MaterialHighlight({
    required this.id,
    required this.text,
    required this.color,
    required this.source,
    this.reason,
    this.pageNumber,
  });

  final String id;
  final String text;
  final HighlightColor color;
  final HighlightSource source;

  /// Kurze Begründung, warum die KI diese Stelle markiert hat (nur bei
  /// [HighlightSource.ai]). Wird dem Nutzer als Kontext gezeigt.
  final String? reason;

  /// 1-basierte PDF-Seitenzahl, auf der die Markierung visuell als
  /// Annotation platziert wurde. Null, wenn die Stelle (z.B. ein KI-Vorschlag
  /// per Paraphrase statt Exakt-Zitat) im PDF-Text nicht wiedergefunden
  /// werden konnte – die Markierung zählt dann trotzdem als "relevant" für
  /// die KI-Weiterverarbeitung, erscheint aber nicht sichtbar im Dokument.
  final int? pageNumber;

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'color': color.name,
        'source': source.name,
        'reason': reason,
        'pageNumber': pageNumber,
      };

  factory MaterialHighlight.fromMap(Map<String, dynamic> map) => MaterialHighlight(
        id: map['id'] as String,
        text: map['text'] as String,
        color: highlightColorFromString(map['color'] as String?),
        source: highlightSourceFromString(map['source'] as String?),
        reason: map['reason'] as String?,
        pageNumber: map['pageNumber'] as int?,
      );
}

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

  /// Pfad zur lokal gespeicherten Original-PDF-Datei (nur für
  /// [MaterialKind.slide] im PDF-Format – ermöglicht die visuelle Ansicht +
  /// Markierung in [MaterialViewerScreen]). Null auf Web (dort in
  /// [fileBytesBase64] gehalten, da es kein Dateisystem gibt) und bei alten
  /// Uploads/anderen Dateiformaten, für die keine visuelle Ansicht existiert.
  final String? filePath;

  /// Base64-kodierte Original-PDF-Bytes – Web-Pendant zu [filePath], da dort
  /// kein Dateisystempfad zur Verfügung steht. Auf anderen Plattformen null.
  final String? fileBytesBase64;

  /// Vom Nutzer und/oder der KI markierte, besonders relevante Textstellen
  /// dieses Materials (siehe [MaterialHighlight]). Fließt als zusätzlicher
  /// "besonders wichtig"-Kontext in Vorbereiten/Nachbereiten/Chat ein.
  final List<MaterialHighlight> highlights;

  /// Kurze freie Notiz des Nutzers zu diesem Material, die ebenfalls als
  /// relevanter Kontext an die KI weitergegeben wird.
  final String notes;

  /// Welcher Vorlesungseinheit (siehe LectureUnit) dieses Material
  /// zugeordnet ist. Null = keine Einheit gewählt (z.B. ältere Uploads vor
  /// Einführung der Einheiten) – solche Materialien/daraus generierte
  /// Karteikarten bleiben immer verfügbar, unabhängig vom
  /// Einheiten-"behandelt"-Status.
  final String? unitId;

  const MaterialItem({
    required this.id,
    required this.moduleId,
    required this.fileName,
    required this.kind,
    required this.extractedText,
    required this.createdAt,
    this.covered = false,
    this.topicIndex,
    this.filePath,
    this.fileBytesBase64,
    this.highlights = const [],
    this.notes = '',
    this.unitId,
  });

  /// Ob dieses Material eine visuelle PDF-Ansicht mit Markier-Funktion
  /// unterstützt (Original-Bytes wurden beim Upload gespeichert).
  bool get hasViewablePdf => filePath != null || fileBytesBase64 != null;

  /// Text der zuerst hochgeladenen Übungsklausur eines Fachs (siehe
  /// [MaterialKind.practiceExam]), falls vorhanden – Stil-Referenz für die
  /// KI-Generierung (siehe AiService.generateConceptsAndFlashcards/
  /// generateCheckpointQuiz, Parameter `examContext`), damit erzeugte
  /// Fragen sich an Art/Schwierigkeit der echten Klausur orientieren.
  static String? practiceExamTextFrom(List<MaterialItem> materials) {
    for (final m in materials) {
      if (m.kind == MaterialKind.practiceExam) return m.extractedText;
    }
    return null;
  }

  MaterialItem copyWith({
    List<MaterialHighlight>? highlights,
    String? notes,
  }) =>
      MaterialItem(
        id: id,
        moduleId: moduleId,
        fileName: fileName,
        kind: kind,
        extractedText: extractedText,
        createdAt: createdAt,
        covered: covered,
        topicIndex: topicIndex,
        filePath: filePath,
        fileBytesBase64: fileBytesBase64,
        highlights: highlights ?? this.highlights,
        notes: notes ?? this.notes,
        unitId: unitId,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'fileName': fileName,
        'kind': kind.name,
        'extractedText': extractedText,
        'createdAt': createdAt.toIso8601String(),
        'covered': covered,
        'topicIndex': topicIndex,
        'filePath': filePath,
        'fileBytesBase64': fileBytesBase64,
        'highlights': highlights.map((h) => h.toMap()).toList(),
        'notes': notes,
        'unitId': unitId,
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
        filePath: map['filePath'] as String?,
        fileBytesBase64: map['fileBytesBase64'] as String?,
        highlights: (map['highlights'] as List?)
                ?.map((h) => MaterialHighlight.fromMap(Map<String, dynamic>.from(h as Map)))
                .toList() ??
            const [],
        notes: map['notes'] as String? ?? '',
        unitId: map['unitId'] as String?,
      );
}
