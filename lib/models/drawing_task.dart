/// Freihand zeichnen ([QuestionType.drawing]): z.B. ein Gefüge skizzieren
/// (Korngefüge vor und nach dem Walzen, primäre und sekundäre
/// Rekristallisation, Perlit), eine Versetzung oder ein einfaches Schema.
/// Man zeichnet in eine oder mehrere Flächen ([panels]) oder lädt ein Foto
/// der Papier-Skizze hoch; eine Bild-KI prüft die Zeichnung an den
/// [criteria], ohne KI hakt man die Kriterien selbst ab.
library;

/// Ein Merkmal, das die Zeichnung zeigen soll.
class DrawingCriterion {
  const DrawingCriterion({required this.text, this.panel = '', this.required = true});

  /// Was zu sehen sein soll (z.B. "Körner in Walzrichtung gestreckt").
  final String text;

  /// Name der Fläche, auf die es sich bezieht ('' = alle bzw. die einzige).
  final String panel;

  /// Muss erfüllt sein, damit die Zeichnung als richtig zählt (sonst nur
  /// ein Hinweis, z.B. "Walzrichtung als Pfeil eingezeichnet").
  final bool required;

  DrawingCriterion copyWith({String? text, String? panel, bool? required}) =>
      DrawingCriterion(text: text ?? this.text, panel: panel ?? this.panel, required: required ?? this.required);

  Map<String, dynamic> toMap() => {
    'text': text,
    if (panel.isNotEmpty) 'panel': panel,
    if (!required) 'required': false,
  };

  static DrawingCriterion? fromRaw(Object? raw) {
    if (raw is String) return raw.trim().isEmpty ? null : DrawingCriterion(text: raw.trim());
    if (raw is! Map) return null;
    final text = '${raw['text'] ?? raw['criterion'] ?? raw['kriterium'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    final req = raw['required'] ?? raw['pflicht'];
    return DrawingCriterion(
      text: text,
      panel: '${raw['panel'] ?? raw['flaeche'] ?? raw['fläche'] ?? ''}'.trim(),
      required: !(req == false || '$req'.toLowerCase() == 'false'),
    );
  }
}

/// Die ganze Aufgabe.
class DrawingTask {
  const DrawingTask({this.panels = const [], required this.criteria, this.solution = '', this.uncertain = false});

  /// Namen der Zeichenflächen (z.B. "vor dem Walzen", "nach dem Walzen");
  /// leer = eine Fläche ohne Namen.
  final List<String> panels;
  final List<DrawingCriterion> criteria;

  /// Beschreibung der Musterskizze (für „Lösung zeigen“ und die KI).
  final String solution;

  /// Von der KI unsicher übernommen – vor dem Speichern prüfen.
  final bool uncertain;

  /// Die Flächen zum Zeichnen (mindestens eine).
  List<String> get surfaces => panels.isEmpty ? const [''] : panels;

  bool get isUsable =>
      criteria.isNotEmpty && criteria.every((c) => c.text.trim().isNotEmpty) && criteria.any((c) => c.required);

  /// Die Kriterien einer Fläche (inklusive der für alle Flächen).
  List<DrawingCriterion> criteriaFor(String panel) => [
    for (final c in criteria)
      if (c.panel.isEmpty || c.panel == panel) c,
  ];

  DrawingTask confirmed() => copyWith(uncertain: false);

  DrawingTask copyWith({List<String>? panels, List<DrawingCriterion>? criteria, String? solution, bool? uncertain}) =>
      DrawingTask(
        panels: panels ?? this.panels,
        criteria: criteria ?? this.criteria,
        solution: solution ?? this.solution,
        uncertain: uncertain ?? this.uncertain,
      );

  /// Musterlösung als Text (Rückseite der Karte).
  String solutionText() => [
    if (solution.trim().isNotEmpty) solution.trim(),
    'Die Zeichnung sollte zeigen:',
    for (final c in criteria) '• ${c.panel.isEmpty ? '' : '${c.panel}: '}${c.text}${c.required ? '' : ' (optional)'}',
  ].join('\n');

  String describe() =>
      'Freihand-Skizze: ${criteria.length} Kriterien'
      '${panels.length > 1 ? ' in ${panels.length} Flächen' : ''}';

  Map<String, dynamic> toMap() => {
    'kind': 'drawing',
    if (panels.isNotEmpty) 'panels': panels,
    'criteria': [for (final c in criteria) c.toMap()],
    if (solution.trim().isNotEmpty) 'solution': solution.trim(),
    if (uncertain) 'uncertain': true,
  };

  static DrawingTask? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final criteria = raw['criteria'] ?? raw['kriterien'] ?? raw['checklist'];
    if (criteria is! List) return null;
    final panels = raw['panels'] ?? raw['flaechen'] ?? raw['flächen'];
    final u = raw['uncertain'] ?? raw['unsicher'];
    return DrawingTask(
      panels: [
        if (panels is List)
          for (final p in panels)
            if ('$p'.trim().isNotEmpty) '$p'.trim(),
      ],
      criteria: [for (final c in criteria) ?DrawingCriterion.fromRaw(c)],
      solution: '${raw['solution'] ?? raw['loesung'] ?? raw['lösung'] ?? raw['description'] ?? ''}'.trim(),
      uncertain: u == true || '$u'.toLowerCase() == 'true',
    );
  }
}

/// Urteil der KI zu einem Kriterium: erfüllt, nicht erfüllt, nicht erkennbar.
enum DrawingMark { met, missing, unclear }

/// Bewertung einer Zeichnung durch die Bild-KI.
class DrawingReview {
  const DrawingReview({required this.marks, required this.comments, this.feedback = ''});

  /// Je Kriterium (gleiche Reihenfolge wie [DrawingTask.criteria]).
  final List<DrawingMark> marks;
  final List<String> comments;

  /// Gesamtrückmeldung.
  final String feedback;

  /// Alle Pflicht-Kriterien erfüllt.
  bool passes(DrawingTask task) {
    for (final (i, c) in task.criteria.indexed) {
      if (c.required && (i >= marks.length || marks[i] != DrawingMark.met)) return false;
    }
    return true;
  }

  static DrawingMark _mark(Object? raw) {
    if (raw == true) return DrawingMark.met;
    if (raw == false) return DrawingMark.missing;
    final v = '${raw ?? ''}'.toLowerCase().trim();
    if (const {'met', 'ja', 'yes', 'erfuellt', 'erfüllt', 'ok', 'true'}.contains(v)) return DrawingMark.met;
    if (const {'missing', 'nein', 'no', 'fehlt', 'falsch', 'false', 'wrong'}.contains(v)) return DrawingMark.missing;
    return DrawingMark.unclear;
  }

  /// Liest `{"results": [{"n": 1, "met": "ja"|"nein"|"unklar", "comment": "…"}], "feedback": "…"}`.
  static DrawingReview fromJson(Map<String, dynamic> json, int count) {
    final marks = List.filled(count, DrawingMark.unclear);
    final comments = List.filled(count, '');
    final results = json['results'] ?? json['criteria'] ?? json['kriterien'];
    if (results is List) {
      for (final (i, r) in results.indexed) {
        if (r is! Map) continue;
        final n = (r['n'] is num ? (r['n'] as num).toInt() - 1 : null) ?? i;
        if (n < 0 || n >= count) continue;
        marks[n] = _mark(r['met'] ?? r['status'] ?? r['ok']);
        comments[n] = '${r['comment'] ?? r['kommentar'] ?? ''}'.trim();
      }
    }
    return DrawingReview(
      marks: marks,
      comments: comments,
      feedback: '${json['feedback'] ?? json['comment'] ?? ''}'.trim(),
    );
  }
}
