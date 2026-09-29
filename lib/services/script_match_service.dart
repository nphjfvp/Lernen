import '../models/flashcard.dart';
import '../models/material_item.dart';
import 'ai_service.dart';
import 'source_locator.dart';

/// Ergebnis für eine Frage: [materialId] null = im Skript nichts gefunden.
class ScriptMatch {
  const ScriptMatch({required this.cardId, required this.materialId, required this.page});

  final String cardId;
  final String? materialId;

  /// 1-basiert, 0 = nicht gefunden.
  final int page;

  bool get found => materialId != null && page > 0;
}

/// Was ein Lauf gebracht hat.
class ScriptMatchRun {
  const ScriptMatchRun({required this.matches, required this.failedCards});

  /// Für jede bearbeitete Frage ein Eintrag (auch "nichts gefunden").
  final List<ScriptMatch> matches;

  /// Fragen, deren Anfrage fehlschlug – sie bleiben "noch nicht gesucht".
  final int failedCards;

  int get found => matches.where((m) => m.found).length;
}

/// Gleicht Fragen mit dem SKRIPT (den Vorlesungsfolien) ab, um zu finden, wo
/// ihre Erklärung steht. Gebraucht für Fragen aus Übungsblättern: dort
/// verweist "Im Skript" sonst nur aufs Übungsblatt selbst. Zwei Stufen wie
/// bei der Kapitelauswahl im Chat: ein schneller lokaler Textabgleich holt je
/// Frage die besten Kandidaten-Seiten, die KI wählt daraus die Seite, auf
/// der die Erklärung wirklich steht (oder keine).
class ScriptMatchService {
  ScriptMatchService({SourceLocator? locator}) : _locator = locator ?? SourceLocator();

  final SourceLocator _locator;

  /// Kandidaten-Seiten je Frage für die KI.
  static const int candidatesPerCard = 5;

  /// Fragen je KI-Anfrage.
  static const int batchSize = 8;

  /// Ob [card] einen Abgleich braucht: noch nicht gesucht (mit [force] auch
  /// bereits gesuchte), und die Frage stammt aus einem Übungsblatt oder einer
  /// Altklausur – bei Folien-Fragen zeigt die Quelle schon aufs Skript. Fragen
  /// OHNE bekannte Quelle nur mit [includeUnsourced] (die finden ihre Stelle
  /// sonst beim Öffnen per Textabgleich).
  static bool needsMatch(
    Flashcard card,
    Map<String, MaterialItem> materialsById, {
    bool force = false,
    bool includeUnsourced = false,
  }) {
    if (!force && card.scriptSearched) return false;
    final source = materialsById[card.sourceMaterialId];
    if (source == null) return includeUnsourced;
    return source.kind != MaterialKind.slide;
  }

  static List<Flashcard> candidatesFrom(
    Iterable<Flashcard> cards,
    Iterable<MaterialItem> materials, {
    bool force = false,
    bool includeUnsourced = false,
  }) {
    final byId = {for (final m in materials) m.id: m};
    return [
      for (final c in cards)
        if (needsMatch(c, byId, force: force, includeUnsourced: includeUnsourced)) c,
    ];
  }

  /// Sucht für [cards] die Erklärung im Skript von [materials] (nur die
  /// Folien-PDFs auf diesem Gerät zählen). Ohne Folien-PDF oder ohne lesbaren
  /// Text kommt ein leerer Lauf zurück. [onProgress] meldet erledigte Fragen.
  Future<ScriptMatchRun> match(
    List<Flashcard> cards, {
    required List<MaterialItem> materials,
    required AiService ai,
    void Function(int done, int total)? onProgress,
  }) async {
    final scripts = SourceLocator.scriptPdfs(materials);
    final pages = <({MaterialItem material, int page, String text})>[];
    for (final m in scripts) {
      final texts = await _locator.pageTextsOf(m);
      for (var i = 0; i < texts.length; i++) {
        pages.add((material: m, page: i + 1, text: texts[i]));
      }
    }
    if (pages.isEmpty || cards.isEmpty) return const ScriptMatchRun(matches: [], failedCards: 0);

    final index = PageIndex([for (final p in pages) p.text]);
    final matches = <ScriptMatch>[];
    final pending = <({Flashcard card, List<int> pageIndexes})>[];
    for (final card in cards) {
      final ranked = index.rank(
        SourceLocator.queryFor(card),
        limit: candidatesPerCard,
        // Folien derselben Einheit sind wahrscheinlicher.
        boost: (i) => card.unitId != null && pages[i].material.unitId == card.unitId ? 1.25 : 1,
      );
      if (ranked.isEmpty) {
        matches.add(ScriptMatch(cardId: card.id, materialId: null, page: 0));
      } else {
        pending.add((card: card, pageIndexes: [for (final r in ranked) r.index]));
      }
    }

    var done = matches.length;
    var failed = 0;
    onProgress?.call(done, cards.length);
    for (var start = 0; start < pending.length; start += batchSize) {
      final batch = pending.sublist(start, start + batchSize > pending.length ? pending.length : start + batchSize);
      try {
        final answers = await ai.matchCardsToScript([
          for (final (i, entry) in batch.indexed)
            (
              n: i + 1,
              type: entry.card.type.label,
              question: entry.card.promptText,
              answer: entry.card.answerSummary.isNotEmpty ? entry.card.answerSummary : entry.card.back,
              candidates: [
                for (final (k, pi) in entry.pageIndexes.indexed)
                  (
                    id: 'c${k + 1}',
                    label: '${pages[pi].material.fileName}, Seite ${pages[pi].page}',
                    text: pages[pi].text,
                  ),
              ],
            ),
        ]);
        for (final (i, entry) in batch.indexed) {
          final chosen = answers[i + 1];
          final k = chosen == null ? null : int.tryParse(chosen.substring(1));
          if (k == null || k < 1 || k > entry.pageIndexes.length) {
            matches.add(ScriptMatch(cardId: entry.card.id, materialId: null, page: 0));
          } else {
            final picked = pages[entry.pageIndexes[k - 1]];
            matches.add(ScriptMatch(cardId: entry.card.id, materialId: picked.material.id, page: picked.page));
          }
        }
      } catch (_) {
        failed += batch.length;
      }
      done += batch.length;
      onProgress?.call(done, cards.length);
    }
    return ScriptMatchRun(matches: matches, failedCards: failed);
  }
}
