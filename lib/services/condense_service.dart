import '../models/condense.dart';

/// Reine Logik hinter "Kürzen" (kein KI-Aufruf, keine PDF-Bibliothek): eine
/// Vorlesung in Seiten und Blöcke zerlegen, in Abschnitte für die KI gruppieren,
/// ihre Auswahl ("behalte 12.1–12.4") einlesen und daraus das gekürzte
/// Dokument zusammensetzen. Die KI wählt nur aus – der Text kommt immer 1:1 aus
/// dem Original, es kann also nichts dazuerfunden werden.
class CondenseService {
  CondenseService._();

  /// Ungefähre Blockgröße in Zeichen: groß genug, dass die Kennungen den
  /// Prompt nicht aufblähen, klein genug, dass eine Folie nicht ganz oder gar
  /// nicht behalten werden muss.
  static const targetBlockChars = 240;

  // -- Zerlegen -------------------------------------------------------------

  /// Zerlegt den Text einer Seite in Blöcke: aufeinanderfolgende Zeilen bis etwa
  /// [targetBlockChars] Zeichen; eine Überschrift (kurze Zeile ohne Satzzeichen
  /// nach einem fertigen Satz) beginnt einen neuen Block.
  static List<CondenseBlock> blocksOfPage(int page, String text) {
    final lines = [
      for (final l in text.replaceAll('\r', '').split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    final blocks = <CondenseBlock>[];
    final buffer = StringBuffer();
    var length = 0;
    String? previous;

    void flush() {
      if (buffer.isEmpty) return;
      blocks.add(CondenseBlock(page: page, index: blocks.length + 1, text: buffer.toString()));
      buffer.clear();
      length = 0;
    }

    for (final line in lines) {
      final startsHeading = length >= 100 && previous != null && _endsSentence(previous) && _looksLikeHeading(line);
      if (length >= targetBlockChars || startsHeading) flush();
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(line);
      length += line.length + 1;
      previous = line;
    }
    flush();
    return blocks;
  }

  static bool _endsSentence(String line) => RegExp(r'[.!?:)]$').hasMatch(line);

  static bool _looksLikeHeading(String line) =>
      line.length <= 70 && !RegExp(r'[.,;:!?)]$').hasMatch(line) && RegExp(r'^[A-ZÄÖÜ0-9]').hasMatch(line);

  /// Seiten aus den Texten je PDF-Seite (Index 0 = Seite 1). Leere Seiten
  /// bleiben als Seite ohne Blöcke erhalten, damit die Nummern stimmen.
  static List<CondensePage> pagesFromPageTexts(List<String> texts, {String label = 'Seite'}) => [
        for (var i = 0; i < texts.length; i++)
          CondensePage(number: i + 1, label: label, blocks: blocksOfPage(i + 1, texts[i])),
      ];

  /// Seiten aus einem Fließtext ohne PDF-Seiten: PowerPoint-Text trägt
  /// "--- Folie N ---"-Marken (siehe OfficeTextExtractor), sonst wird der Text an
  /// Absatzgrenzen in Abschnitte von etwa [sectionChars] Zeichen geteilt.
  static List<CondensePage> pagesFromText(String text, {int sectionChars = 2400}) {
    final marker = RegExp(r'^---\s*Folie\s+(\d+)\s*---\s*$', multiLine: true);
    final matches = marker.allMatches(text).toList();
    if (matches.isNotEmpty) {
      return [
        for (var i = 0; i < matches.length; i++)
          () {
            final number = int.tryParse(matches[i].group(1)!) ?? i + 1;
            final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
            return CondensePage(
              number: number,
              label: 'Folie',
              blocks: blocksOfPage(number, text.substring(matches[i].end, end)),
            );
          }(),
      ];
    }
    final sections = <String>[];
    final buffer = StringBuffer();
    for (final paragraph in text.replaceAll('\r', '').split(RegExp(r'\n\s*\n'))) {
      if (paragraph.trim().isEmpty) continue;
      if (buffer.length + paragraph.length > sectionChars && buffer.isNotEmpty) {
        sections.add(buffer.toString());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(paragraph.trim());
    }
    if (buffer.isNotEmpty) sections.add(buffer.toString());
    return pagesFromPageTexts(sections, label: 'Abschnitt');
  }

  /// Fasst aufeinanderfolgende Seiten zu Abschnitten für je einen KI-Aufruf
  /// zusammen (höchstens [chunkChars] Zeichen; eine einzelne große Seite bleibt
  /// allein). `null` = alles in einem Aufruf.
  static List<List<CondensePage>> group(List<CondensePage> pages, int? chunkChars) {
    final withText = [for (final p in pages) if (p.blocks.isNotEmpty) p];
    if (withText.isEmpty) return const [];
    if (chunkChars == null) return [withText];
    final groups = <List<CondensePage>>[];
    var current = <CondensePage>[];
    var size = 0;
    for (final page in withText) {
      // Die Kennungen kosten je Block etwa 8 Zeichen.
      final cost = page.length + page.blocks.length * 8 + 16;
      if (current.isNotEmpty && size + cost > chunkChars) {
        groups.add(current);
        current = [];
        size = 0;
      }
      current.add(page);
      size += cost;
    }
    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  /// Der Text für die KI: je Seite eine Kopfzeile, je Block "[Kennung] Text".
  static String render(List<CondensePage> pages) {
    final b = StringBuffer();
    for (final page in pages) {
      b.writeln('=== ${page.label} ${page.number} ===');
      for (final block in page.blocks) {
        b.writeln('[${block.id}] ${block.text}');
      }
      b.writeln();
    }
    return b.toString().trimRight();
  }

  /// Kennungen aller Blöcke in Dokumentreihenfolge.
  static List<String> idsOf(List<CondensePage> pages) => [
        for (final p in pages)
          for (final b in p.blocks) b.id,
      ];

  // -- Auswahl einlesen -------------------------------------------------------

  static final _number = RegExp(r'\d+(?:[.,]\d+)?');

  /// Liest die Blockangaben der KI: einzelne Kennungen ("12.3"), Bereiche
  /// ("12.1-12.4", auch über Seitengrenzen) und ganze Seiten ("12" bzw.
  /// "12-14"). Gültig sind nur Kennungen aus [ordered] (den Blöcken dieses
  /// Aufrufs, in Dokumentreihenfolge); Unbekanntes fällt weg, das Ergebnis ist
  /// ohne Doppelte in Dokumentreihenfolge.
  static List<String> parseBlockRefs(Object? raw, List<String> ordered) {
    final tokens = switch (raw) {
      List l => [for (final e in l) '$e'],
      String s => s.replaceAll(', ', ' ').split(RegExp(r'[;\s]+')),
      _ => const <String>[],
    };
    final position = {for (var i = 0; i < ordered.length; i++) ordered[i]: i};
    final pageStart = <int, int>{};
    final pageEnd = <int, int>{};
    for (var i = 0; i < ordered.length; i++) {
      final page = int.tryParse(ordered[i].split('.').first);
      if (page == null) continue;
      pageStart.putIfAbsent(page, () => i);
      pageEnd[page] = i;
    }

    int? locate(String match, {required bool end}) {
      final normalized = match.replaceAll(',', '.');
      if (normalized.contains('.')) return position[normalized];
      final page = int.tryParse(normalized);
      return page == null ? null : (end ? pageEnd[page] : pageStart[page]);
    }

    final chosen = <int>{};
    for (final token in tokens) {
      final matches = _number.allMatches(token).map((m) => m.group(0)!).toList();
      if (matches.isEmpty) continue;
      // Ohne Bindestrich/"bis" sind mehrere Zahlen eine Aufzählung ("12.1,12.3"),
      // kein Bereich.
      final isRange = matches.length > 1 && RegExp(r'[-–—]|bis').hasMatch(token);
      final spans = isRange
          ? [(matches.first, matches.last)]
          : [for (final m in matches) (m, m)];
      for (final (first, last) in spans) {
        final from = locate(first, end: false);
        final to = locate(last, end: true);
        if (from == null && to == null) continue;
        final a = from ?? to!;
        final b = to ?? from!;
        for (var i = a <= b ? a : b; i <= (a <= b ? b : a); i++) {
          chosen.add(i);
        }
      }
    }
    return [for (final i in (chosen.toList()..sort())) ordered[i]];
  }

  /// Ein Abschnitt aus der KI-Antwort; `null`, wenn er keinen gültigen Block
  /// enthält.
  static CondenseSection? parseSection(Object? raw, List<String> ordered) {
    if (raw is! Map) return null;
    final ids = parseBlockRefs(raw['blocks'] ?? raw['bloecke'] ?? raw['blöcke'] ?? raw['keep'], ordered);
    if (ids.isEmpty) return null;
    final title = '${raw['title'] ?? raw['titel'] ?? ''}'.trim();
    final covers = raw['covers'] ?? raw['deckt'];
    return CondenseSection(
      title: title.isEmpty ? 'Abschnitt' : title,
      kind: condenseKindFromString(raw['kind'] ?? raw['art']),
      why: '${raw['why'] ?? raw['grund'] ?? ''}'.trim(),
      blockIds: ids,
      covers: [
        if (covers is List)
          for (final c in covers)
            if ('$c'.trim().isNotEmpty) '$c'.trim().toLowerCase(),
      ],
    );
  }

  // -- Zusammensetzen ----------------------------------------------------------

  /// Die behaltenen Blöcke in Dokumentreihenfolge, ohne Doppelte, jeweils mit
  /// der Überschrift des ersten Abschnitts, der sie behalten hat.
  static List<({CondenseBlock block, String title})> keptBlocks(
    List<CondensePage> pages,
    List<CondenseSection> sections,
  ) {
    final owner = <String, String>{};
    for (final s in sections) {
      for (final id in s.blockIds) {
        owner.putIfAbsent(id, () => s.title);
      }
    }
    return [
      for (final p in pages)
        for (final b in p.blocks)
          if (owner.containsKey(b.id)) (block: b, title: owner[b.id]!),
    ];
  }

  /// Die behaltenen Seiten (aufsteigend) – jede Seite mit mindestens einem
  /// behaltenen Block.
  static List<int> keptPageNumbers(List<CondensePage> pages, List<CondenseSection> sections) {
    final kept = keptBlocks(pages, sections);
    return ({for (final k in kept) k.block.page}.toList()..sort());
  }

  /// Zusammenhängende Stücke behaltener Blöcke je Seite (Block-Nummern von/bis) –
  /// an ihrem Anfang steht die Markierung "ab hier relevant". Eine Seite, die
  /// komplett behalten wird, bekommt keine (es gibt nichts zu zeigen).
  static Map<int, List<({int from, int to, String title})>> runsByPage(
    List<CondensePage> pages,
    List<CondenseSection> sections,
  ) {
    final kept = keptBlocks(pages, sections);
    final byPage = <int, List<({CondenseBlock block, String title})>>{};
    for (final k in kept) {
      byPage.putIfAbsent(k.block.page, () => []).add(k);
    }
    final result = <int, List<({int from, int to, String title})>>{};
    for (final page in pages) {
      final blocks = byPage[page.number];
      if (blocks == null) continue;
      final runs = <({int from, int to, String title})>[];
      var from = blocks.first.block.index, to = from, title = blocks.first.title;
      for (final k in blocks.skip(1)) {
        if (k.block.index == to + 1) {
          to = k.block.index;
        } else {
          runs.add((from: from, to: to, title: title));
          from = to = k.block.index;
          title = k.title;
        }
      }
      runs.add((from: from, to: to, title: title));
      final wholePage = runs.length == 1 && runs.first.from == 1 && runs.first.to == page.blocks.length;
      if (!wholePage) result[page.number] = runs;
    }
    return result;
  }

  /// Das gekürzte Dokument als Text: Kopf mit Auftrag und Umfang, dann je Seite
  /// die behaltenen Blöcke mit der Überschrift des Abschnitts.
  static String textDocument({
    required String sourceName,
    required String prompt,
    required List<CondensePage> pages,
    required List<CondenseSection> sections,
  }) {
    final kept = keptBlocks(pages, sections);
    final keptPages = ({for (final k in kept) k.block.page}.toList()..sort());
    final label = pages.isEmpty ? 'Seite' : pages.first.label;
    final b = StringBuffer()
      ..writeln('Gekürzte Fassung: $sourceName')
      ..writeln('Auftrag: ${prompt.trim().isEmpty ? '–' : prompt.trim()}')
      ..writeln('Behalten: ${condensePageRanges(keptPages, label: label)} von ${pages.length}');
    final byPage = <int, List<({CondenseBlock block, String title})>>{};
    for (final k in kept) {
      byPage.putIfAbsent(k.block.page, () => []).add(k);
    }
    for (final page in pages) {
      final blocks = byPage[page.number];
      if (blocks == null) continue;
      final titles = <String>[];
      for (final k in blocks) {
        if (!titles.contains(k.title)) titles.add(k.title);
      }
      b
        ..writeln()
        ..writeln('## ${page.label} ${page.number} · ${titles.join(' / ')}');
      for (final k in blocks) {
        b.writeln(k.block.text);
      }
    }
    return b.toString().trimRight();
  }

  /// Kopf für die Seitenzahlen "Original S. 12" in der gekürzten PDF.
  static String stampText(String label, int number) => 'Original: ${label == 'Seite' ? 'S.' : label} $number';

  /// Mischt die Ergebnisse mehrerer Aufrufe: Anforderungen, die die KI mehrfach
  /// (leicht anders geschrieben) nennt, werden einmal geführt; die Kennungen
  /// laufen neu durch (n1, n2 …).
  static List<CondenseNeed> mergeNeeds(Iterable<String> texts, {int limit = 60}) {
    final seen = <String>{};
    final needs = <CondenseNeed>[];
    for (final t in texts) {
      final text = t.trim();
      final key = text.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß0-9]+'), ' ').trim();
      if (key.isEmpty || !seen.add(key)) continue;
      needs.add(CondenseNeed(id: 'n${needs.length + 1}', text: text));
      if (needs.length >= limit) break;
    }
    return needs;
  }
}
