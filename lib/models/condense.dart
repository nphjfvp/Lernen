/// Datenmodell für "Kürzen": eine Vorlesung wird anhand von Übungsaufgaben (und
/// einem Auftrag des Nutzers) auf das Nötige verkürzt. Die KI schreibt dabei
/// NICHTS um – sie wählt nur Textblöcke des Originals aus ([CondenseBlock]),
/// die App setzt daraus das gekürzte Dokument zusammen.
library;

/// Ein Textblock einer Seite (ein paar zusammengehörige Zeilen). Die Kennung
/// "Seite.Nummer" (z.B. "12.3") nennt die KI, wenn sie einen Block behalten
/// will.
class CondenseBlock {
  const CondenseBlock({required this.page, required this.index, required this.text});

  /// Seiten- bzw. Foliennummer, 1-basiert.
  final int page;

  /// Nummer innerhalb der Seite, 1-basiert.
  final int index;
  final String text;

  String get id => '$page.$index';
}

/// Eine Seite (PDF), Folie (PowerPoint) oder – ohne Seitenstruktur – ein
/// Abschnitt der Vorlesung, in Blöcke zerlegt.
class CondensePage {
  const CondensePage({required this.number, required this.blocks, this.label = 'Seite'});

  final int number;
  final List<CondenseBlock> blocks;

  /// "Seite", "Folie" oder "Abschnitt" – so nennt die App die Einheit.
  final String label;

  int get length => blocks.fold(0, (sum, b) => sum + b.text.length);
}

/// Wofür ein behaltener Abschnitt gut ist.
enum CondenseKind {
  /// Erklärung, Definition, Herleitung, Formel, Satz – alles, was zum
  /// Verstehen und Lösen gebraucht wird.
  erklaerung,

  /// Beispielaufgabe bzw. Musterlösung aus der Vorlesung, die man nicht zum
  /// Verstehen braucht, die aber in die Richtung der Aufgaben geht. Lässt sich
  /// über einen Schalter weglassen.
  beispiel,
}

/// Tolerant: unbekannte Werte zählen als Erklärung (lieber zu viel behalten).
CondenseKind condenseKindFromString(Object? value) {
  final v = '$value'.toLowerCase();
  if (v.contains('beispiel') || v.contains('example') || v.contains('aufgabe')) return CondenseKind.beispiel;
  return CondenseKind.erklaerung;
}

/// Wie streng gekürzt wird.
enum CondenseStrictness {
  /// Nur, was die Aufgaben wirklich brauchen.
  knapp('Knapp'),

  /// Das Nötige samt dem Zusammenhang, den man zum Verstehen braucht.
  ausgewogen('Ausgewogen'),

  /// Im Zweifel behalten.
  grosszuegig('Großzügig');

  const CondenseStrictness(this.label);
  final String label;
}

CondenseStrictness condenseStrictnessFromString(String? value) =>
    CondenseStrictness.values.firstWhere((e) => e.name == value, orElse: () => CondenseStrictness.ausgewogen);

/// Etwas, das man zum Lösen der Aufgaben wissen/können muss (Verfahren,
/// Definition, Formel …) – Ergebnis der Auswertung der Übungsaufgaben.
class CondenseNeed {
  const CondenseNeed({required this.id, required this.text});

  /// "n1", "n2" …
  final String id;
  final String text;
}

/// Was die Aufgaben verlangen: die Aufgaben (kurz) und die Anforderungen.
class CondensePlan {
  const CondensePlan({this.tasks = const [], this.needs = const []});

  final List<String> tasks;
  final List<CondenseNeed> needs;

  bool get isEmpty => needs.isEmpty;
}

/// Ein behaltener Abschnitt der Vorlesung: zusammengehörige Blöcke mit
/// Überschrift, Begründung und Art.
class CondenseSection {
  const CondenseSection({
    required this.title,
    required this.blockIds,
    this.kind = CondenseKind.erklaerung,
    this.why = '',
    this.covers = const [],
  });

  final String title;
  final CondenseKind kind;

  /// Wozu der Abschnitt gebraucht wird ("Aufgabe 2 braucht die Substitution").
  final String why;

  /// Kennungen der behaltenen Blöcke in Dokumentreihenfolge.
  final List<String> blockIds;

  /// Welche Anforderungen ([CondenseNeed.id]) der Abschnitt abdeckt.
  final List<String> covers;
}

/// Ergebnis der KI-Auswahl über die ganze Vorlesung.
class CondenseSelection {
  const CondenseSelection({this.sections = const [], this.skipped = const [], this.plan = const CondensePlan()});

  final List<CondenseSection> sections;

  /// Themen, die die KI bewusst weggelassen hat (Organisatorisches, Geschichte …).
  final List<String> skipped;
  final CondensePlan plan;

  /// Abschnitte, wie sie je nach Schalter gelten: ohne Beispielaufgaben nur die
  /// Erklärungen.
  List<CondenseSection> visible({required bool includeExamples}) => [
        for (final s in sections)
          if (includeExamples || s.kind != CondenseKind.beispiel) s,
      ];

  /// Anforderungen, die keine der [visible]en Abschnitte abdeckt – die
  /// Vorlesung erklärt sie nicht (oder nur in einer Beispielaufgabe, die
  /// gerade nicht mitgenommen wird).
  List<CondenseNeed> uncovered({required bool includeExamples}) {
    final covered = {for (final s in visible(includeExamples: includeExamples)) ...s.covers};
    return [
      for (final n in plan.needs)
        if (!covered.contains(n.id)) n,
    ];
  }
}

/// Was zu einem gekürzten Dokument gespeichert wird (am Material, siehe
/// MaterialItem.condensed): woraus, wofür, welche Seiten.
class CondensedInfo {
  const CondensedInfo({
    required this.sourceMaterialId,
    required this.sourceName,
    required this.prompt,
    this.exerciseNames = const [],
    this.pages = const [],
    this.totalPages = 0,
    this.label = 'Seite',
    this.includeExamples = true,
    this.markers = true,
    this.notFound = const [],
    this.skipped = const [],
  });

  final String sourceMaterialId;
  final String sourceName;

  /// Der Auftrag des Nutzers ("alles, was man zum Lösen braucht").
  final String prompt;
  final List<String> exerciseNames;

  /// Behaltene Seiten des Originals (1-basiert, aufsteigend). In der gekürzten
  /// PDF stehen genau diese Seiten in dieser Reihenfolge.
  final List<int> pages;
  final int totalPages;
  final String label;
  final bool includeExamples;

  /// Ob die gekürzte PDF Markierungen (Beginn des relevanten Teils,
  /// Original-Seitenzahl) trägt.
  final bool markers;

  /// Anforderungen aus den Aufgaben, die die Vorlesung nicht abdeckt.
  final List<String> notFound;

  /// Weggelassene Themen.
  final List<String> skipped;

  Map<String, dynamic> toMap() => {
        'sourceMaterialId': sourceMaterialId,
        'sourceName': sourceName,
        'prompt': prompt,
        'exerciseNames': exerciseNames,
        'pages': pages,
        'totalPages': totalPages,
        'label': label,
        'includeExamples': includeExamples,
        'markers': markers,
        'notFound': notFound,
        'skipped': skipped,
      };

  /// Tolerant gelesen (neuere App-Version, Import).
  static CondensedInfo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    List<String> strings(Object? v) => [
          if (v is List)
            for (final e in v)
              if ('$e'.trim().isNotEmpty) '$e'.trim(),
        ];
    return CondensedInfo(
      sourceMaterialId: '${raw['sourceMaterialId'] ?? ''}',
      sourceName: '${raw['sourceName'] ?? ''}',
      prompt: '${raw['prompt'] ?? ''}',
      exerciseNames: strings(raw['exerciseNames']),
      pages: [
        if (raw['pages'] is List)
          for (final p in raw['pages'] as List)
            if (p is num) p.toInt() else if (int.tryParse('$p') != null) int.parse('$p'),
      ],
      totalPages: raw['totalPages'] is num ? (raw['totalPages'] as num).toInt() : int.tryParse('${raw['totalPages']}') ?? 0,
      label: '${raw['label'] ?? 'Seite'}',
      includeExamples: raw['includeExamples'] != false,
      markers: raw['markers'] != false,
      notFound: strings(raw['notFound']),
      skipped: strings(raw['skipped']),
    );
  }

  /// "Seite 3, 5–9" – die behaltenen Seiten kompakt.
  String get pagesText => condensePageRanges(pages, label: label);

  /// "8 von 42 Seiten".
  String get shareText => '${pages.length} von $totalPages ${label == 'Seite' ? 'Seiten' : label == 'Folie' ? 'Folien' : 'Abschnitten'}';
}

/// "Seite 3, 5–9" bzw. "Seiten 3, 5–9" – aufeinanderfolgende Nummern werden
/// zu einem Bereich.
String condensePageRanges(List<int> pages, {String label = 'Seite'}) {
  if (pages.isEmpty) return '';
  final sorted = ({...pages}.toList()..sort());
  final parts = <String>[];
  var start = sorted.first, prev = sorted.first;
  void flush() => parts.add(start == prev ? '$start' : '$start–$prev');
  for (final p in sorted.skip(1)) {
    if (p == prev + 1) {
      prev = p;
    } else {
      flush();
      start = prev = p;
    }
  }
  flush();
  final plural = sorted.length > 1 || parts.length > 1;
  final noun = label == 'Seite' ? (plural ? 'Seiten' : 'Seite') : label == 'Folie' ? (plural ? 'Folien' : 'Folie') : label;
  return '$noun ${parts.join(', ')}';
}
