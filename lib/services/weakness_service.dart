import '../models/flashcard.dart';
import 'mastery_service.dart';

/// Eine Karte im Fehlertagebuch plus die Gründe, warum sie dort steht.
class WeakCard {
  const WeakCard({required this.card, required this.level, required this.score, required this.reasons});

  final Flashcard card;
  final MasteryLevel level;

  /// Je höher, desto dringender (Sortierung).
  final int score;

  /// Kurze, anzeigbare Gründe, z.B. "3× vergessen".
  final List<String> reasons;
}

/// Fehlertagebuch: sammelt die Karten, mit denen man sich schwertut, aus
/// dem ohnehin vorhandenen Lernzustand (kein eigenes Protokoll nötig):
/// wie oft eine schon gelernte Karte wieder vergessen wurde ([Flashcard.lapses]),
/// ob sie gerade rot ist, ob sie in der letzten Wiederholung falsch war
/// (`relearning`/`learning`) und ob sie auf ihrer Schwierigkeitsstufe gerade mehrfach
/// in Folge scheitert ([Flashcard.variantMissStreak]).
class WeaknessService {
  WeaknessService({MasteryService? mastery}) : _mastery = mastery ?? MasteryService();

  final MasteryService _mastery;

  List<WeakCard> rank(List<Flashcard> cards, {DateTime? now, int? limit}) {
    final result = <WeakCard>[];
    for (final card in cards) {
      if (card.reps == 0) continue; // noch nie geübt – keine Schwäche, nur neu
      final level = _mastery.levelFor(card, now: now);
      var score = 0;
      final reasons = <String>[];
      if (card.lapses > 0) {
        score += card.lapses * 2;
        reasons.add('${card.lapses}× vergessen');
      }
      // relearning: gelernte Karte zuletzt falsch; learning: neue Karte
      // schon beim ersten Versuch falsch (siehe FsrsService.review).
      if (card.state == 'relearning' || card.state == 'learning') {
        score += 2;
        reasons.add('zuletzt falsch');
      }
      if (card.variantMissStreak > 0) {
        score += card.variantMissStreak;
        reasons.add('${card.variantMissStreak}× in Folge falsch auf dieser Stufe');
      }
      if (level == MasteryLevel.red) {
        score += 3;
        if (reasons.isEmpty) reasons.add('Ampel rot');
      }
      if (score == 0) continue;
      result.add(WeakCard(card: card, level: level, score: score, reasons: reasons));
    }
    result.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Bei Gleichstand: zuletzt geübte zuerst (frischer Fehler).
      final aLast = a.card.lastReview ?? DateTime(1970);
      final bLast = b.card.lastReview ?? DateTime(1970);
      return bLast.compareTo(aLast);
    });
    return limit == null ? result : result.take(limit).toList();
  }
}
