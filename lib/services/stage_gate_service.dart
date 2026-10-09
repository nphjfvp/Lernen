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

  /// Gewicht 0 (siehe Flashcard.isMuted): kommt nie dran und zählt für die
  /// Stufen ihrer Gruppe nicht mit.
  muted,
}

extension StageStatusLabel on StageStatus {
  String get label => switch (this) {
        StageStatus.active => 'Aktiv',
        StageStatus.locked => 'Wartet auf leichtere Stufe',
        StageStatus.done => 'Stufe geschafft',
        StageStatus.muted => 'Stummgeschaltet – kommt nie dran',
      };
}

/// Ein Ordner der Kartenliste: alle Karten einer Stufen-Gruppe (mindestens
/// zwei), sortiert von Leicht nach Schwer.
class StageFolder {
  const StageFolder({required this.key, required this.cards, this.name});

  /// Gruppenschlüssel (siehe [StageGate.groupOf]).
  final String key;

  /// Die Karten, leichteste Stufe zuerst.
  final List<Flashcard> cards;

  /// Anzeigename der Gruppe (Sachverhalt bzw. Konzept) oder null – dann
  /// zeigt die Liste die schwerste Frage als Titel.
  final String? name;

  /// Die schwerste Frage – sie steht für den ganzen Ordner.
  Flashcard get hardest => cards.last;

  /// Nur nach Konzept zusammengefasst (niemand hat geprüft, ob die Fragen
  /// wirklich dasselbe abfragen).
  bool get byConceptOnly => cards.every((c) => (c.stageGroup ?? '').trim().isEmpty);
}

/// Ein Eintrag der Kartenliste: eine einzelne Karte oder ein Ordner.
typedef StageListEntry = ({Flashcard? card, StageFolder? folder});

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

  /// Aufgaben statt Fragen (Lernen, Rechenweg, Terminierung, Kristallgitter,
  /// Stückliste, Skizze): keine Stufen, keine Ordner.
  static bool isTaskType(QuestionType type) =>
      type == QuestionType.learn ||
      type == QuestionType.steps ||
      type == QuestionType.gantt ||
      type == QuestionType.crystal ||
      type == QuestionType.bom ||
      type == QuestionType.sketch ||
      type == QuestionType.phase;

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
        QuestionType.freeText ||
        QuestionType.html ||
        QuestionType.table ||
        QuestionType.learn ||
        QuestionType.steps ||
        QuestionType.gantt ||
        QuestionType.crystal ||
        QuestionType.bom ||
        QuestionType.sketch ||
        QuestionType.phase =>
          StageLevel.schwer,
      };

  static StageLevel? levelFromIndex(int? index) =>
      index == null || index < 0 || index >= StageLevel.values.length ? null : StageLevel.values[index];

  /// Stufe einer Karte: gesetzt (beim Erstellen, per KI oder von Hand, siehe
  /// [Flashcard.stageLevel]) oder aus dem Fragetyp abgeleitet.
  static StageLevel levelOf(Flashcard card) => levelFromIndex(card.stageLevel) ?? levelOfType(card.type);

  /// Gruppenschlüssel oder null (eigene Gruppe). Pro Fach getrennt.
  static String? groupOf(Flashcard card) {
    // Lern-, Rechenweg- und Terminierungsaufgaben stehen für sich: sie sind
    // keine Stufe eines Sachverhalts.
    if (isTaskType(card.type)) return null;
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
    final result = <String, StageStatus>{};
    for (final card in cards) {
      // Stumme Karten kommen nie dran und halten auch keine Stufe auf.
      if (card.isMuted) {
        result[card.id] = StageStatus.muted;
        continue;
      }
      final key = groupOf(card);
      if (key != null) groups.putIfAbsent(key, () => []).add(card);
    }
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
          if ((c.variantChain?.length ?? 0) < 2 && !isTaskType(c.type)) c,
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

  /// Lesbarer Name der Gruppe einer Karte: der von der KI bzw. von Hand
  /// vergebene Name (ohne angehängte Laufkennung) oder – bei der Gruppe aus
  /// dem Konzept – dessen Titel aus [conceptTitles]. Null für unbenannte
  /// Gruppen.
  static String? groupName(Flashcard card, {Map<String, String> conceptTitles = const {}}) {
    final stored = card.stageGroup?.trim() ?? '';
    if (stored.isEmpty || stored == card.conceptId) {
      final title = conceptTitles[card.conceptId]?.trim();
      return title == null || title.isEmpty ? null : title;
    }
    if (stored.startsWith('manuell-') || stored.startsWith('einzeln-')) return null;
    final hash = stored.lastIndexOf('#');
    final name = (hash > 0 ? stored.substring(0, hash) : stored).trim();
    return name.isEmpty ? null : name;
  }

  /// Karten sortiert von Leicht nach Schwer (bei gleicher Stufe nach
  /// Erstellung).
  static List<Flashcard> byLevel(Iterable<Flashcard> cards) => cards.toList()
    ..sort((a, b) {
      final byLevel = levelOf(a).index.compareTo(levelOf(b).index);
      return byLevel != 0 ? byLevel : a.createdAt.compareTo(b.createdAt);
    });

  /// Die Kartenliste als Ordner: Karten einer Gruppe mit mindestens zwei
  /// Karten (gezählt in [allCards], also dem ganzen Fach) landen gemeinsam
  /// in einem Ordner an der Stelle ihrer ersten Karte; alle anderen bleiben
  /// einzeln. [visible] ist die (ggf. per Suche gefilterte) Auswahl – ein
  /// Ordner enthält nur die sichtbaren Karten.
  static List<StageListEntry> listEntries(
    List<Flashcard> allCards,
    List<Flashcard> visible, {
    Map<String, String> conceptTitles = const {},
  }) {
    final sizes = <String, int>{};
    for (final c in allCards) {
      final key = groupOf(c);
      if (key != null) sizes[key] = (sizes[key] ?? 0) + 1;
    }
    final members = <String, List<Flashcard>>{};
    final order = <Object>[];
    for (final c in visible) {
      final key = groupOf(c);
      if (key == null || (sizes[key] ?? 0) < 2) {
        order.add(c);
        continue;
      }
      if (!members.containsKey(key)) order.add(key);
      members.putIfAbsent(key, () => []).add(c);
    }
    return [
      for (final item in order)
        if (item is Flashcard)
          (card: item, folder: null)
        else
          (
            card: null,
            folder: () {
              final cards = byLevel(members[item]!);
              String? name;
              for (final c in cards.reversed) {
                name = groupName(c, conceptTitles: conceptTitles);
                if (name != null) break;
              }
              return StageFolder(key: item as String, cards: cards, name: name);
            }(),
          ),
    ];
  }

  /// Für die Probeklausur: aus jedem ausdrücklich gebildeten Ordner (KI
  /// oder von Hand, [Flashcard.stageGroup]) nur die Fragen der schwersten
  /// Stufe – dasselbe Wissen soll nicht dreimal verschieden schwer drankommen.
  /// Ordner, die nur aus dem Konzept stammen, bleiben vollständig (dort ist
  /// nicht sicher, dass die Fragen dasselbe abfragen).
  static List<Flashcard> hardestPerFolder(List<Flashcard> cards) {
    String? explicitKey(Flashcard c) {
      final stored = c.stageGroup?.trim() ?? '';
      if (stored.isEmpty || stored == c.conceptId || stored.startsWith('einzeln-')) return null;
      return groupOf(c);
    }

    final top = <String, int>{};
    for (final c in cards) {
      final key = explicitKey(c);
      if (key != null) top[key] = max(top[key] ?? 0, levelOf(c).index);
    }
    return [
      for (final c in cards)
        if (explicitKey(c) == null || levelOf(c).index == top[explicitKey(c)]) c,
    ];
  }

  /// Rückfall nach wiederholten Fehlern auf [card]: die nächstleichtere
  /// vorhandene Stufe ihrer Gruppe kommt zurück in den Plan – deren Karten
  /// gelten wieder als "noch nicht sicher" (knapp unter grün) und sind
  /// spätestens heute fällig. Leer, wenn es keine leichtere Stufe gibt.
  static List<Flashcard> reactivateEasier(Iterable<Flashcard> moduleCards, Flashcard card, {DateTime? now}) {
    final key = groupOf(card);
    if (key == null) return const [];
    final own = levelOf(card).index;
    final lower = moduleCards
        .where((c) => !c.isMuted && c.id != card.id && groupOf(c) == key && levelOf(c).index < own)
        .toList();
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
