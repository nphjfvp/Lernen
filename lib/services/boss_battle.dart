import '../models/flashcard.dart';
import 'mastery_service.dart';

/// Ergebnis einer Antwort im Boss-Kampf.
enum BossHit { hit, miss }

/// Spiellogik des Boss-Kampfs (siehe BossBattleScreen), ohne Oberfläche:
/// Der Boss eines Fachs hat so viele Lebenspunkte wie Karten im Kampf. Jede
/// richtig beantwortete Karte trifft ihn einmal; eine falsche kostet ein
/// Herz und kommt [retryGap] Karten später noch einmal – so wird falsch
/// Beantwortetes zeitnah wiederholt, bis es sitzt. Besiegt ist der Boss,
/// wenn jede Karte einmal richtig war; sind die Herzen weg, entkommt er.
///
/// Jede Antwort zählt fürs Lernen (der Screen verbucht sie wie im Daily
/// Quiz) – das Spiel ist nur die Verpackung.
class BossBattle {
  BossBattle(List<Flashcard> cards, {this.hearts = defaultHearts})
    : _queue = List.of(cards),
      _allCards = List.unmodifiable(cards),
      maxHp = cards.length;

  static const defaultHearts = 5;
  static const retryGap = 3;
  static const maxCards = 10;
  static const minCards = 3;

  /// Karten für einen Kampf: die schwächsten zuerst (Ampel rot, dann gelb,
  /// dann grün), höchstens [maxCards]. [shuffle] mischt innerhalb einer
  /// Ampelfarbe (Tests geben eine feste Reihenfolge vor).
  static List<Flashcard> pickCards(
    List<Flashcard> cards, {
    MasteryService? mastery,
    void Function(List<Flashcard>)? shuffle,
  }) {
    final m = mastery ?? MasteryService();
    final byLevel = <MasteryLevel, List<Flashcard>>{};
    for (final c in cards) {
      byLevel.putIfAbsent(m.levelFor(c), () => []).add(c);
    }
    final picked = <Flashcard>[];
    for (final level in [MasteryLevel.red, MasteryLevel.yellow, MasteryLevel.green]) {
      final group = byLevel[level] ?? [];
      (shuffle ?? (l) => l.shuffle())(group);
      picked.addAll(group);
    }
    return picked.take(maxCards).toList();
  }

  final int maxHp;
  int hearts;
  final List<Flashcard> _queue;
  final List<Flashcard> _allCards;
  final Set<String> _defeated = {};
  final Map<String, int> _misses = {};
  int combo = 0;
  int bestCombo = 0;
  int answered = 0;

  int get hp => maxHp - _defeated.length;
  bool get won => hp <= 0;
  bool get lost => !won && hearts <= 0;
  bool get over => won || lost;

  /// Die gerade gestellte Karte (null, wenn der Kampf vorbei ist).
  Flashcard? get current => over || _queue.isEmpty ? null : _queue.first;

  /// Wie oft eine Karte in diesem Kampf falsch war.
  int missesOf(String cardId) => _misses[cardId] ?? 0;

  /// Karten, die nicht (oder erst nach Fehlern) saßen – fürs Ergebnis.
  List<Flashcard> get toReview => [
    for (final c in _allCards)
      if (missesOf(c.id) > 0) c,
  ];

  /// Wertet die Antwort auf [current] aus.
  BossHit answer({required bool correct}) {
    final card = current;
    if (card == null) throw StateError('Kampf ist vorbei');
    answered++;
    _queue.removeAt(0);
    if (correct) {
      _defeated.add(card.id);
      combo++;
      if (combo > bestCombo) bestCombo = combo;
      return BossHit.hit;
    }
    combo = 0;
    hearts--;
    _misses[card.id] = missesOf(card.id) + 1;
    _queue.insert(_queue.length < retryGap ? _queue.length : retryGap, card);
    return BossHit.miss;
  }

  /// Überspringen: die Karte wandert ans Ende, ohne Treffer oder Fehler.
  void skip() {
    if (_queue.length < 2) return;
    _queue.add(_queue.removeAt(0));
  }
}
