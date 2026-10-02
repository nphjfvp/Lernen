/// Wie weit ein Eintrag der Formelsammlung "unter" dem Thema der Vorlesung
/// liegt – daraus ergibt sich, bei welcher Genauigkeit er erscheint (siehe
/// [FormulaDetail.includes]).
enum FormulaLevel {
  /// Wird in den Folien neu eingeführt oder zentral behandelt (z.B.
  /// Stammfunktionen, Integrationsregeln in einer Vorlesung zur
  /// Integralrechnung). Auch eine sonst "frühere" Regel gehört hierher, wenn die
  /// Folien sie neu einführen.
  kern,

  /// Regeln aus früheren Themen, die man für die Aufgaben dieses Themas
  /// anwenden können muss, die die Folien aber nicht neu einführen (z.B.
  /// Ableitungsregeln für partielle Integration und Substitution).
  hilfsregel,

  /// Elementare Rechenregeln, auf denen alles aufbaut (Bruchrechnung, Potenz-,
  /// Wurzel-, Logarithmusgesetze, binomische Formeln …).
  rechenregel;

  String get label => switch (this) {
        FormulaLevel.kern => 'Kernstoff',
        FormulaLevel.hilfsregel => 'Hilfsregel',
        FormulaLevel.rechenregel => 'Rechenregel',
      };

  static FormulaLevel parse(Object? raw) {
    final s = '${raw ?? ''}'.trim().toLowerCase();
    if (s.startsWith('hilf')) return FormulaLevel.hilfsregel;
    if (s.startsWith('rechen') || s.startsWith('grundregel') || s.startsWith('basis')) return FormulaLevel.rechenregel;
    // Unbekannt/fehlend: lieber im groben Überblick zeigen als verlieren.
    return FormulaLevel.kern;
  }
}

/// Genauigkeit der Formelsammlung: Grob = nur der Kernstoff, Mittel = dazu die
/// Hilfsregeln aus früheren Themen, Fein = alles, was man braucht, auch die
/// elementaren Rechenregeln.
enum FormulaDetail {
  grob,
  mittel,
  fein;

  String get label => switch (this) {
        FormulaDetail.grob => 'Grob',
        FormulaDetail.mittel => 'Mittel',
        FormulaDetail.fein => 'Fein',
      };

  /// Ein Satz, was bei dieser Genauigkeit dabei ist.
  String get description => switch (this) {
        FormulaDetail.grob => 'Nur das, was in den Folien neu ist – ohne Rechen- und Ableitungsregeln, '
            'die man schon kennen sollte.',
        FormulaDetail.mittel => 'Das Neue plus die Regeln aus früheren Themen, die man dafür braucht '
            '(z.B. Ableitungsregeln für partielle Integration) – ohne elementare Rechenregeln.',
        FormulaDetail.fein => 'Alles, was man braucht: auch Bruch-, Potenz- und Logarithmusregeln.',
      };

  bool includes(FormulaLevel level) => switch (this) {
        FormulaDetail.grob => level == FormulaLevel.kern,
        FormulaDetail.mittel => level != FormulaLevel.rechenregel,
        FormulaDetail.fein => true,
      };

  static FormulaDetail parse(Object? raw) {
    final s = '${raw ?? ''}'.trim().toLowerCase();
    for (final d in FormulaDetail.values) {
      if (d.name == s) return d;
    }
    return FormulaDetail.mittel;
  }
}

/// Eine Formel, ein Satz oder eine Regel der Formelsammlung.
class FormulaEntry {
  const FormulaEntry({
    required this.name,
    required this.formula,
    this.note = '',
    this.level = FormulaLevel.kern,
    this.supplemented = false,
  });

  /// "Partielle Integration", "Potenzgesetz".
  final String name;

  /// LaTeX ohne umgebende Dollarzeichen.
  final String formula;

  /// Bedingungen oder Hinweise zur Anwendung ("u, v stetig differenzierbar").
  final String note;
  final FormulaLevel level;

  /// Stand nicht in den Folien, sondern wurde von der KI als Standardregel
  /// ergänzt – zum Gegenprüfen markiert.
  final bool supplemented;

  FormulaEntry copyWith({
    String? name,
    String? formula,
    String? note,
    FormulaLevel? level,
    bool? supplemented,
  }) =>
      FormulaEntry(
        name: name ?? this.name,
        formula: formula ?? this.formula,
        note: note ?? this.note,
        level: level ?? this.level,
        supplemented: supplemented ?? this.supplemented,
      );

  /// Für das Zusammenführen mehrerer Abschnitte: dieselbe Formel, egal wie sie
  /// geschrieben ist (Leerzeichen, Dollarzeichen, `\left`/`\right`, `\cdot`).
  String get dedupeKey => normalizeFormula(formula).isNotEmpty ? normalizeFormula(formula) : name.toLowerCase().trim();

  Map<String, dynamic> toMap() => {
        'name': name,
        'formula': formula,
        'note': note,
        'level': level.name,
        'supplemented': supplemented,
      };

  factory FormulaEntry.fromMap(Map<String, dynamic> map) => FormulaEntry(
        name: (map['name'] ?? '').toString().trim(),
        formula: stripMathDelimiters((map['formula'] ?? '').toString()),
        note: (map['note'] ?? '').toString().trim(),
        level: FormulaLevel.parse(map['level']),
        supplemented: map['supplemented'] == true ||
            const {'ergaenzt', 'ergänzt'}.contains('${map['source'] ?? ''}'.trim().toLowerCase()),
      );

  /// Entfernt umgebende `$…$`, `$$…$$`, `\(…\)`, `\[…\]` und Leerraum – im
  /// Eintrag steht reines LaTeX, die Anzeige setzt die Begrenzer selbst.
  static String stripMathDelimiters(String raw) {
    var s = raw.trim();
    for (final pair in const [(r'$$', r'$$'), (r'$', r'$'), (r'\[', r'\]'), (r'\(', r'\)')]) {
      if (s.length > pair.$1.length + pair.$2.length && s.startsWith(pair.$1) && s.endsWith(pair.$2)) {
        s = s.substring(pair.$1.length, s.length - pair.$2.length).trim();
        break;
      }
    }
    return s;
  }

  static String normalizeFormula(String formula) => stripMathDelimiters(formula)
      .replaceAll(RegExp(r'\\(left|right|,|;|!|quad|qquad)'), '')
      .replaceAll(r'\cdot', '*')
      .replaceAll(r'\dfrac', r'\frac')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();
}

/// Ein Themenabschnitt der Formelsammlung ("Grundintegrale", "Ableitungsregeln").
class FormulaSection {
  const FormulaSection({required this.title, this.entries = const []});

  final String title;
  final List<FormulaEntry> entries;

  FormulaSection copyWith({String? title, List<FormulaEntry>? entries}) =>
      FormulaSection(title: title ?? this.title, entries: entries ?? this.entries);

  Map<String, dynamic> toMap() => {'title': title, 'entries': [for (final e in entries) e.toMap()]};

  factory FormulaSection.fromMap(Map<String, dynamic> map) => FormulaSection(
        title: (map['title'] ?? '').toString().trim(),
        entries: [
          for (final e in (map['entries'] ?? map['formulas'] ?? const []) as List)
            if (e is Map && FormulaEntry.fromMap(Map<String, dynamic>.from(e)).formula.isNotEmpty)
              FormulaEntry.fromMap(Map<String, dynamic>.from(e)),
        ],
      );
}

/// Eine Formelsammlung zu Vorlesungsfolien. Gespeichert wird IMMER alles samt
/// Stufe ([FormulaLevel]); [detail] ist nur die gewählte Ansicht – die
/// Genauigkeit lässt sich also jederzeit wechseln, ohne die KI noch einmal zu
/// fragen.
class FormulaSheet {
  const FormulaSheet({this.detail = FormulaDetail.mittel, this.sections = const []});

  final FormulaDetail detail;
  final List<FormulaSection> sections;

  int get totalCount => sections.fold(0, (n, s) => n + s.entries.length);

  /// Die bei [detail] sichtbaren Abschnitte (leere fallen weg).
  List<FormulaSection> visibleSections([FormulaDetail? at]) {
    final d = at ?? detail;
    return [
      for (final s in sections)
        if (s.entries.any((e) => d.includes(e.level)))
          s.copyWith(entries: [for (final e in s.entries) if (d.includes(e.level)) e]),
    ];
  }

  int visibleCount([FormulaDetail? at]) => visibleSections(at).fold(0, (n, s) => n + s.entries.length);

  FormulaSheet withDetail(FormulaDetail d) => FormulaSheet(detail: d, sections: sections);

  FormulaSheet withSections(List<FormulaSection> next) => FormulaSheet(detail: detail, sections: next);

  /// Fügt [other] zu diesem Stand hinzu (mehrere Folienabschnitte): Abschnitte
  /// gleichen Titels werden zusammengelegt, schon vorhandene Formeln nicht noch
  /// einmal aufgenommen. Bei einer Doppelung gewinnt die höhere Stufe (Kernstoff
  /// vor Hilfsregel vor Rechenregel) und "aus den Folien" vor "ergänzt".
  FormulaSheet merged(FormulaSheet other) {
    final result = <FormulaSection>[for (final s in sections) s];
    final seen = <String, (int, int)>{
      for (var i = 0; i < result.length; i++)
        for (var j = 0; j < result[i].entries.length; j++) result[i].entries[j].dedupeKey: (i, j),
    };
    String titleKey(String t) => t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüß]+'), '');
    for (final section in other.sections) {
      var index = result.indexWhere((s) => titleKey(s.title) == titleKey(section.title));
      for (final entry in section.entries) {
        final known = seen[entry.dedupeKey];
        if (known != null) {
          final old = result[known.$1].entries[known.$2];
          final better = entry.level.index < old.level.index || (old.supplemented && !entry.supplemented);
          if (better) {
            final list = [...result[known.$1].entries];
            list[known.$2] = old.copyWith(
              level: entry.level.index < old.level.index ? entry.level : old.level,
              supplemented: old.supplemented && entry.supplemented,
            );
            result[known.$1] = result[known.$1].copyWith(entries: list);
          }
          continue;
        }
        if (index < 0) {
          result.add(FormulaSection(title: section.title));
          index = result.length - 1;
        }
        result[index] = result[index].copyWith(entries: [...result[index].entries, entry]);
        seen[entry.dedupeKey] = (index, result[index].entries.length - 1);
      }
    }
    return FormulaSheet(detail: detail, sections: result);
  }

  /// Als Text zum Kopieren (Markdown mit `$$…$$`) – nur, was bei [detail]
  /// sichtbar ist.
  String asText({String title = ''}) {
    final b = StringBuffer();
    if (title.trim().isNotEmpty) b.writeln('# ${title.trim()} (${detail.label})\n');
    for (final s in visibleSections()) {
      b.writeln('## ${s.title}\n');
      for (final e in s.entries) {
        b.writeln('- **${e.name}**${e.supplemented ? ' (ergänzt)' : ''}: \$\$${e.formula}\$\$');
        if (e.note.isNotEmpty) b.writeln('  ${e.note}');
      }
      b.writeln();
    }
    return b.toString().trim();
  }

  Map<String, dynamic> toMap() => {
        'detail': detail.name,
        'sections': [for (final s in sections) s.toMap()],
      };

  /// Tolerant gelesen (ältere/importierte Daten, Modellantworten).
  factory FormulaSheet.fromMap(Map<String, dynamic> map) => FormulaSheet(
        detail: FormulaDetail.parse(map['detail']),
        sections: [
          for (final s in (map['sections'] as List? ?? const []))
            if (s is Map) FormulaSection.fromMap(Map<String, dynamic>.from(s)),
        ].where((s) => s.entries.isNotEmpty).toList(),
      );

  static FormulaSheet? tryFromMap(Object? raw) =>
      raw is Map ? FormulaSheet.fromMap(Map<String, dynamic>.from(raw)) : null;
}
