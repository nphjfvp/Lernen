import 'dart:math' as math;
import 'dart:typed_data';

import '../models/concept.dart';
import '../models/flashcard.dart';
import '../models/material_item.dart';
import 'material_file_store.dart';
import 'pdf_service.dart';

/// Die Stelle einer Frage in den Lernunterlagen.
class CardSource {
  const CardSource({required this.material, required this.page, this.pageText = '', this.guessed = false});

  final MaterialItem material;

  /// 1-basiert.
  final int page;

  /// Text der Seite (leer, wenn er nicht gelesen werden konnte) – Grundlage
  /// für Lerneinheit und Sokrates-Dialog.
  final String pageText;

  /// Über den Textabgleich gefunden statt beim Erstellen gespeichert.
  final bool guessed;
}

/// Findet, wo eine Frage in den Unterlagen ihres Fachs steht. Für "Im Skript"
/// ([preferScript] true, der Standard) zählt die ERKLÄRUNG: die beim
/// Abgleich gefundene Skript-Seite ([Flashcard.scriptPage]), sonst – bei
/// Folien-Fragen – die beim Erstellen gespeicherte Seite, bei Fragen aus
/// einem Übungsblatt eine per Textabgleich vermutete Skript-Seite und erst
/// zuletzt das Übungsblatt selbst. Mit [preferScript] false (die Aufgabe im
/// Original ansehen) kommt zuerst die beim Erstellen gespeicherte Stelle.
/// Weitere Stufen: die Seite des verknüpften Konzepts und ein lokaler
/// Textabgleich (ohne KI). Nur PDFs, die auf dem Gerät liegen, werden
/// durchsucht.
class SourceLocator {
  SourceLocator({Future<Uint8List?> Function(MaterialItem material)? loadBytes, PdfService? pdf})
      : _loadBytes = loadBytes ?? _defaultLoad,
        _pdf = pdf ?? PdfService();

  final Future<Uint8List?> Function(MaterialItem material) _loadBytes;
  final PdfService _pdf;

  /// Seitentexte je Material – das Auslesen einer großen PDF dauert, und
  /// dieselben Materialien werden in einer Lernrunde oft wieder gebraucht.
  static final Map<String, List<String>> _pageTextCache = {};

  static Future<Uint8List?> _defaultLoad(MaterialItem m) =>
      MaterialFileStore.load(filePath: m.filePath, fileBytesBase64: m.fileBytesBase64);

  static bool _isPdf(MaterialItem m) => m.fileName.toLowerCase().endsWith('.pdf');

  /// Die Folien/Skripte, in denen Erklärungen stehen: Vorlesungsmaterial
  /// (keine Übungsblätter oder Altklausuren) als PDF auf diesem Gerät.
  static List<MaterialItem> scriptPdfs(Iterable<MaterialItem> materials) =>
      [for (final m in materials) if (m.kind == MaterialKind.slide && m.hasViewablePdf && _isPdf(m)) m];

  Future<List<String>> pageTextsOf(MaterialItem material) async {
    final cached = _pageTextCache[material.id];
    if (cached != null) return cached;
    if (!material.hasViewablePdf || !_isPdf(material)) return const [];
    try {
      final bytes = await _loadBytes(material);
      if (bytes == null) return const [];
      final texts = _pdf.extractPageTexts(bytes);
      _pageTextCache[material.id] = texts;
      return texts;
    } catch (_) {
      return const [];
    }
  }

  Future<CardSource> _withText(MaterialItem material, int page, {bool guessed = false}) async {
    final texts = await pageTextsOf(material);
    final text = page >= 1 && page <= texts.length ? texts[page - 1] : '';
    return CardSource(material: material, page: page, pageText: text, guessed: guessed);
  }

  Future<CardSource?> locate(
    Flashcard card, {
    required List<MaterialItem> materials,
    List<Concept> concepts = const [],
    bool preferScript = true,
  }) async {
    MaterialItem? byId(String? id) {
      if (id == null) return null;
      for (final m in materials) {
        if (m.id == id) return m;
      }
      return null;
    }

    final query = queryFor(card);

    // 1. Die beim Abgleich gefundene Erklärung im Skript.
    if (preferScript && card.hasScript) {
      final script = byId(card.scriptMaterialId);
      if (script != null) return _withText(script, card.scriptPage!);
    }

    // 2. Beim Erstellen gespeichert. Stammt die Frage aus einem Übungsblatt
    // und soll die Erklärung gezeigt werden, steht sie im Skript.
    final stored = byId(card.sourceMaterialId);
    Concept? concept;
    for (final c in concepts) {
      if (c.id == card.conceptId) concept = c;
    }
    if (stored != null) {
      final fromWorksheet = stored.kind != MaterialKind.slide;
      if (!(preferScript && fromWorksheet)) {
        final page = card.sourcePage ?? (await _bestIn([stored], query))?.page ?? 1;
        return _withText(stored, page);
      }
      final inScript = await _guessInScript(card, materials, concept, query);
      if (inScript != null) return inScript;
      final page = card.sourcePage ?? (await _bestIn([stored], query))?.page ?? 1;
      return _withText(stored, page);
    }

    // 3. Das Konzept der Karte kennt seine Seite.
    final linked = byId(concept?.linkedMaterialId);
    if (linked != null) {
      final page = concept!.linkedPageNumber ?? (await _bestIn([linked], query))?.page ?? 1;
      return _withText(linked, page);
    }

    // 4. Textabgleich.
    return _guessInScript(card, materials, concept, query, allPdfsAsFallback: true);
  }

  /// Textabgleich im Skript – zuerst in den Materialien derselben Einheit
  /// bzw. des Konzepts, dann in allen Folien; mit [allPdfsAsFallback]
  /// zuletzt in jedem PDF des Fachs.
  Future<CardSource?> _guessInScript(
    Flashcard card,
    List<MaterialItem> materials,
    Concept? concept,
    ({List<String> question, List<String> answer}) query, {
    bool allPdfsAsFallback = false,
  }) async {
    final slides = scriptPdfs(materials);
    final anyPdf = materials.where((m) => m.hasViewablePdf && _isPdf(m)).toList();
    bool preferredFor(MaterialItem m) =>
        (card.unitId != null && m.unitId == card.unitId) || (concept?.sourceMaterialIds.contains(m.id) ?? false);
    final preferred = slides.where(preferredFor).toList();
    for (final pool in [
      if (preferred.isNotEmpty) preferred,
      slides,
      if (allPdfsAsFallback) anyPdf,
    ]) {
      final best = await _bestIn(pool, query);
      if (best != null) {
        return CardSource(material: best.material, page: best.page, pageText: best.text, guessed: true);
      }
    }
    return null;
  }

  Future<({MaterialItem material, int page, String text})?> _bestIn(
    List<MaterialItem> pool,
    ({List<String> question, List<String> answer}) query,
  ) async {
    final pages = <({MaterialItem material, int page, String text})>[];
    for (final m in pool) {
      final texts = await pageTextsOf(m);
      for (var i = 0; i < texts.length; i++) {
        pages.add((material: m, page: i + 1, text: texts[i]));
      }
    }
    final best = bestPage(query, [for (final p in pages) p.text]);
    return best == null ? null : pages[best];
  }

  /// Suchbegriffe einer Karte: aus der Frage und (stärker gewichtet) aus der
  /// Lösung.
  static ({List<String> question, List<String> answer}) queryFor(Flashcard card) => (
        question: keywords(card.front),
        answer: keywords([card.answerSummary, card.back].join(' ')),
      );

  static const _stopwords = {
    'aber', 'alle', 'allem', 'allen', 'aller', 'alles', 'also', 'auch', 'beim', 'bitte', 'dann', 'darf',
    'dass', 'dein', 'deine', 'denn', 'dessen', 'diese', 'diesem', 'diesen', 'dieser', 'dieses', 'doch',
    'dort', 'durch', 'eine', 'einem', 'einen', 'einer', 'eines', 'etwa', 'folgende', 'folgenden', 'frage',
    'gibt', 'haben', 'hier', 'ihre', 'immer', 'jede', 'jeder', 'jedes', 'kann', 'kein', 'keine', 'können',
    'mehr', 'muss', 'nach', 'nennen', 'nenne', 'nicht', 'noch', 'nur', 'oder', 'ohne', 'richtig', 'richtige',
    'sein', 'seine', 'sich', 'sind', 'sowie', 'über', 'unter', 'viel', 'vom', 'warum', 'was', 'welche',
    'welchem', 'welchen', 'welcher', 'welches', 'wenn', 'werden', 'wird', 'wieso', 'wurde', 'zwischen',
    'about', 'does', 'from', 'have', 'into', 'that', 'their', 'there', 'these', 'this', 'what',
    'when', 'where', 'which', 'with', 'would', 'true', 'false', 'wahr', 'falsch',
  };

  /// Kleingeschriebene Stämme (die ersten 7 Zeichen reichen, damit
  /// "Spannung" und "Spannungen" zusammenfallen) von Wörtern mit mindestens
  /// 4 Zeichen, ohne Füllwörter; Zahlen mit Einheit o.ä. zählen mit.
  static List<String> keywords(String text) {
    final words = text.toLowerCase().split(RegExp(r'[^a-z0-9äöüß]+'));
    final result = <String>{};
    for (final w in words) {
      if (w.length < 4 || _stopwords.contains(w)) continue;
      result.add(w.length > 7 ? w.substring(0, 7) : w);
    }
    return result.toList();
  }

  /// Index der Seite in [pageTexts], die am besten passt – seltene Begriffe
  /// zählen mehr (IDF), Begriffe der Lösung anderthalbfach. `null`, wenn
  /// keine Seite mindestens zwei Begriffe teilt.
  static int? bestPage(({List<String> question, List<String> answer}) query, List<String> pageTexts) {
    final ranked = PageIndex(pageTexts).rank(query, limit: 1);
    return ranked.isEmpty ? null : ranked.first.index;
  }
}

/// Die Seiten eines oder mehrerer Skripte zum schnellen Durchsuchen: je Seite
/// die Stichwort-Stämme, dazu wie viele Seiten jeden Stamm enthalten (für die
/// Gewichtung seltener Begriffe). Einmal gebaut und für viele Fragen
/// wiederverwendbar.
class PageIndex {
  PageIndex(List<String> pageTexts)
      : _stems = [for (final t in pageTexts) SourceLocator.keywords(t).toSet()] {
    for (final stems in _stems) {
      for (final s in stems) {
        _df[s] = (_df[s] ?? 0) + 1;
      }
    }
  }

  final List<Set<String>> _stems;
  final Map<String, int> _df = {};

  int get length => _stems.length;

  /// Die besten Seiten zur Anfrage, beste zuerst: [index] (0-basiert),
  /// [score] und wie viele Begriffe [hits] die Seite mit der Anfrage teilt.
  /// Nur Seiten mit mindestens zwei gemeinsamen Begriffen. [boost] wertet
  /// bestimmte Seiten auf (z.B. Folien derselben Einheit).
  List<({int index, double score, int hits})> rank(
    ({List<String> question, List<String> answer}) query, {
    int limit = 5,
    double Function(int pageIndex)? boost,
  }) {
    final weights = <String, double>{
      for (final s in query.question) s: 1,
      for (final s in query.answer) s: 1.5,
    };
    if (weights.isEmpty || _stems.isEmpty) return const [];
    final n = _stems.length;
    final idf = {for (final e in weights.entries) e.key: math.log((n + 1) / ((_df[e.key] ?? 0) + 0.5))};
    final result = <({int index, double score, int hits})>[];
    for (var i = 0; i < n; i++) {
      var score = 0.0;
      var hits = 0;
      for (final e in weights.entries) {
        if (!_stems[i].contains(e.key)) continue;
        score += e.value * idf[e.key]!;
        hits++;
      }
      if (hits >= 2 && score > 0) result.add((index: i, score: score * (boost?.call(i) ?? 1), hits: hits));
    }
    result.sort((a, b) => b.score.compareTo(a.score));
    return result.length > limit ? result.sublist(0, limit) : result;
  }
}
