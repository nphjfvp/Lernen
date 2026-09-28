import 'dart:math';

import '../models/flashcard.dart';

/// Schwierigkeitsstufe einer Frage innerhalb ihrer Gruppe (siehe [StageGate]).
enum StageLevel { leicht, mittel, schwer }

extension StageLevelLabel on StageLevel {
  String get label => switch (this) {
        StageLevel.leicht => 'Leicht',
        StageLevel.mittel => 'Mittel',
        StageLevel.schwer => 'Schwer',
      };
}

/// Wo eine Karte im Stufen-Ablauf ihrer Gruppe gerade steht.
enum StageStatus {
  /// Wird ganz normal gelernt: neu eingeführt bzw. per Spaced Repetition
  /// wiederholt.
  active,

  /// Eine leichtere Stufe derselben Gruppe sitzt noch nicht – diese Karte
  /// kommt erst danach dran.
  locked,

  /// Stufe geschafft, eine schwerere Stufe der Gruppe hat übernommen – die
  /// Karte ruht (die schwerere hält das Wissen per Wiederholung frisch).
  done,
}

extension StageStatusLabel on StageStatus {
  String get label => switch (this) {
        StageStatus.active => 'Aktiv',
        StageStatus.locked => 'Wartet auf leichtere Stufe',
        StageStatus.done => 'Stufe geschafft',
      };
}

/// Leicht → Mittel → Schwer über mehrere GETRENNTE Karten derselben Gruppe
/// (Konzept bzw. [Flashcard.stageGroup]): nur die leichteste Stufe, die noch
/// nicht grün ist, wird gelernt; schwerere warten, leichtere ruhen. Sitzen
/// alle Stufen, bleibt die schwerste in der Wiederholung. Fehlt eine Stufe,
/// rückt die nächste einfach nach; gibt es nur eine, läuft sie ganz normal.
///
/// Karten mit eigener Stufenkette ([Flashcard.variantChain], z.B. aus
/// "Frage erstellen") regeln ihre Stufen selbst (ein Datensatz wechselt den
/// Typ) und gehören keiner Gruppe an.
class StageGate {
  const StageGate._();

  /// Stufe aus dem Fragetyp, wenn keine gesetzt ist: Wiedererkennen ist
  /// leicht, Ergänzen/Zuordnen mittel, frei Formulieren schwer.
  static StageLevel levelOfType(QuestionType type) => switch (type) {
        QuestionType.singleChoice || QuestionType.multipleChoice || QuestionType.markImage => StageLevel.leicht,
        QuestionType.fillBlank ||
        QuestionType.dragDrop ||
        QuestionType.dragCategory ||
        QuestionType.diagramLabel ||
        QuestionType.flashcard =>
          StageLevel.mittel,
        QuestionType.freeText || QuestionType.html || QuestionType.table => StageLevel.schwer,
      };

  static StageLevel? levelFromIndex(int? index) =>
      index == null || index < 0 || index >= StageLevel.values.length ? null : StageLevel.values[index];

  /// Stufe einer Karte: gesetzt (beim Erstellen, per KI oder von Hand, siehe
  /// [Flashcard.stageLevel]) oder aus dem Fragetyp abgeleitet.
  static StageLevel levelOf(Flashcard card) => levelFromIndex(card.stageLevel) ?? levelOfType(card.type);

  /// Gruppenschlüssel oder null (eigene Gruppe). Pro Fach getrennt.
  static String? groupOf(Flashcard card) {
    final chain = card.variantChain;
    if (chain != null && chain.length > 1) return null;
    final key = (card.stageGroup ?? card.conceptId)?.trim();
    if (key == null || key.isEmpty) return null;
    return '${card.moduleId}\u0000${key.toLowerCase()}';
  }

  /// "Sitzt": an [Flashcard.masteryBoxCap] verschiedenen Tagen richtig. Bewusst
  /// ohne die mit der Zeit sinkende Behaltensrate – eine ruhende Karte wird
  /// nicht mehr wiederholt und würde sonst von selbst wieder aufleben.
  static bool isMastered(Flashcard card) => card.masteryBox >= Flashcard.masteryBoxCap;

  /// Die freigeschaltete Stufe einer Gruppe: die leichteste, die noch nicht
  /// komplett sitzt; sitzen alle, die schwerste.
  static StageLevel? activeLevel(Iterable<Flashcard> group) {
    final levels = group.map(levelOf).toSet().toList()..sort((a, b) => a.index.compareTo(b.index));
    if (levels.isEmpty) return null;
    for (final level in levels) {
      if (group.any((c) => levelOf(c) == level && !isMastered(c))) return level;
    }
    return levels.last;
  }

  /// Status aller Karten, die NICHT aktiv sind (fehlt eine Karte in der Map,
  /// ist sie aktiv). [cards] müssen die kompletten Gruppen enthalten – also
  /// alle Karten der betroffenen Fächer, nicht schon eine gefilterte Auswahl.
  static Map<String, StageStatus> statuses(Iterable<Flashcard> cards) {
    final groups = <String, List<Flashcard>>{};
    for (final card in cards) {
      final key = groupOf(card);
      if (key != null) groups.putIfAbsent(key, () => []).add(card);
    }
    final result = <String, StageStatus>{};
    for (final group in groups.values) {
      if (group.length < 2) continue;
      final active = activeLevel(group)!;
      for (final card in group) {
        final level = levelOf(card).index;
        if (level < active.index) {
          result[card.id] = StageStatus.done;
        } else if (level > active.index) {
          result[card.id] = StageStatus.locked;
        }
      }
    }
    return result;
  }

  static StageStatus statusOf(Map<String, StageStatus> statuses, Flashcard card) =>
      statuses[card.id] ?? StageStatus.active;

  /// Nur die gerade dran befindlichen Karten aus [cards]. Die Gruppen werden
  /// über [cards] selbst bestimmt – also die kompletten Fächer übergeben.
  static List<Flashcard> learnable(List<Flashcard> cards) {
    final s = statuses(cards);
    return cards.where((c) => !s.containsKey(c.id)).toList();
  }

  /// Karten, die per KI Stufe und Gruppe bekommen können: alle ohne eigene
  /// Stufenkette, so sortiert, dass Zusammengehöriges (gleiches Konzept,
  /// zeitnah erstellt) beieinander steht – die KI sieht sie in Portionen.
  static List<Flashcard> assignable(List<Flashcard> cards) => [
        for (final c in cards)
          if ((c.variantChain?.length ?? 0) < 2) c,
      ]..sort((a, b) {
          final byConcept = (a.conceptId ?? '').compareTo(b.conceptId ?? '');
          return byConcept != 0 ? byConcept : a.createdAt.compareTo(b.createdAt);
        });

  /// Übernimmt eine KI-Zuordnung: [results] ist 1-basiert nach Position in
  /// [cards]. Gruppen bekommen [runTag] angehängt – gleich benannte Gruppen
  /// aus verschiedenen Portionen desselben Laufs gehören zusammen, alte
  /// Gruppen früherer Läufe nicht. Karten ohne Ergebnis bleiben unverändert.
  static List<Flashcard> applyAssignments(
    List<Flashcard> cards,
    Map<int, ({int? level, String? group})> results, {
    required String runTag,
  }) {
    final updated = <Flashcard>[];
    for (var i = 0; i < cards.length; i++) {
      final result = results[i + 1];
      if (result == null || (result.level == null && result.group == null)) continue;
      final group = result.group;
      updated.add(cards[i].copyWithStage(level: result.level, group: group == null ? null : '$group#$runTag'));
    }
    return updated;
  }

  /// Rückfall nach wiederholten Fehlern auf [card]: die nächstleichtere
  /// vorhandene Stufe ihrer Gruppe kommt zurück in den Plan – deren Karten
  /// gelten wieder als "noch nicht sicher" (knapp unter grün) und sind
  /// spätestens heute fällig. Leer, wenn es keine leichtere Stufe gibt.
  static List<Flashcard> reactivateEasier(Iterable<Flashcard> moduleCards, Flashcard card, {DateTime? now}) {
    final key = groupOf(card);
    if (key == null) return const [];
    final own = levelOf(card).index;
    final lower = moduleCards.where((c) => c.id != card.id && groupOf(c) == key && levelOf(c).index < own).toList();
    if (lower.isEmpty) return const [];
    final target = lower.map((c) => levelOf(c).index).reduce(max);
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    return [
      for (final c in lower)
        if (levelOf(c).index == target) c.copyWithStageReopened(dueBy: today),
    ];
  }
}
