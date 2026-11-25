import '../models/flashcard.dart';
import 'stage_gate_service.dart';

/// Eine Stufen-Gruppe, die sich zum Einstufen eignet: die freigeschaltete
/// Stufe ist nicht die schwerste, und die schwereren Stufen sind noch nie
/// gefragt worden.
class PlacementGroup {
  const PlacementGroup({required this.key, required this.cards, required this.activeLevel, required this.probes});

  final String key;

  /// Alle (nicht stummen) Karten der Gruppe.
  final List<Flashcard> cards;
  final StageLevel activeLevel;

  /// Je Stufe ÜBER der freigeschalteten eine Karte zum Fragen, schwerste
  /// zuerst – so wird von oben nach unten eingegrenzt.
  final List<Flashcard> probes;
}

/// Einstufung (nach dem Prinzip „erst messen, dann lehren“): Statt jede
/// Gruppe bei „Leicht“ zu beginnen, wird zuerst die schwerste Stufe gefragt.
/// Sitzt sie sicher und ohne Hilfe, ruhen die leichteren Stufen
/// ([Flashcard.placedOut]); sonst geht es eine Stufe tiefer. Rein und
/// testbar; Fragen und Verbuchen übernimmt der PlacementScreen.
class PlacementService {
  PlacementService._();

  static List<PlacementGroup> candidates(List<Flashcard> moduleCards) {
    final groups = <String, List<Flashcard>>{};
    for (final card in moduleCards) {
      if (card.isMuted) continue;
      final key = StageGate.groupOf(card);
      if (key != null) groups.putIfAbsent(key, () => []).add(card);
    }
    final result = <PlacementGroup>[];
    for (final entry in groups.entries) {
      final group = entry.value;
      final active = StageGate.activeLevel(group);
      if (active == null) continue;
      final higher = group.where((c) => StageGate.levelOf(c).index > active.index).toList();
      // Nichts darüber oder schon gelernt: da gibt es nichts einzustufen.
      if (higher.isEmpty || higher.any((c) => c.reps > 0)) continue;
      final byLevel = <int, Flashcard>{};
      for (final c in higher..sort((a, b) => a.createdAt.compareTo(b.createdAt))) {
        byLevel.putIfAbsent(StageGate.levelOf(c).index, () => c);
      }
      final levels = byLevel.keys.toList()..sort((a, b) => b.compareTo(a));
      result.add(PlacementGroup(
        key: entry.key,
        cards: group,
        activeLevel: active,
        probes: [for (final l in levels) byLevel[l]!],
      ));
    }
    result.sort((a, b) => a.probes.first.createdAt.compareTo(b.probes.first.createdAt));
    return result;
  }

  /// Eine Stufe der Gruppe wurde sicher gewusst: alle LEICHTEREN Karten
  /// ruhen ab jetzt. Liefert nur die geänderten Karten.
  static List<Flashcard> placeOutBelow(PlacementGroup group, StageLevel solved) => [
        for (final c in group.cards)
          if (StageGate.levelOf(c).index < solved.index && !c.placedOut) c.copyWithPlacedOut(true),
      ];
}
