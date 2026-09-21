import '../models/flashcard.dart';
import 'fsrs_service.dart';

/// Ampel-Einstufung einer Karte: macht den ohnehin vorhandenen FSRS-Zustand
/// (Stabilität/Retrievability) auf einen Blick sichtbar, statt nur intern
/// die Fälligkeit zu steuern. [neu] = noch nie wiederholt (keine Einstufung
/// möglich), [red]/[yellow]/[green] nach geschätzter aktueller
/// Erinnerungswahrscheinlichkeit.
enum MasteryLevel { neu, red, yellow, green }

extension MasteryLevelLabel on MasteryLevel {
  String get label => switch (this) {
        MasteryLevel.neu => 'Neu',
        MasteryLevel.red => 'Schwach',
        MasteryLevel.yellow => 'Mittel',
        MasteryLevel.green => 'Gut',
      };
}

/// Leitet aus [Flashcard.masteryBox] (primär) und der FSRS-Retrievability
/// (sekundär, nur als Verfalls-Signal für bereits gemeisterte Karten) eine
/// simple Rot/Gelb/Grün-Einstufung ab. Bewusst NICHT primär auf reiner
/// Retrievability – die ist direkt nach jeder Wiederholung (egal ob richtig
/// oder falsch) immer ~100%, würde also frisch falsch beantwortete Karten
/// fälschlich nicht sofort als "Rot" zeigen (siehe [levelFor]).
class MasteryService {
  MasteryService({FsrsService? fsrs}) : _fsrs = fsrs ?? FsrsService();

  final FsrsService _fsrs;

  /// Unter dieser geschätzten Behaltensrate gilt eine Karte als "schwach"
  /// (rot) – spürbar unter dem 90%-Zielwert des Schedulers.
  static const double redThreshold = 0.7;

  /// Unter dieser Schwelle (aber über [redThreshold]) gilt eine Karte als
  /// "mittel" (gelb); darüber als "gut" (grün).
  static const double yellowThreshold = 0.9;

  MasteryLevel levelFor(Flashcard card, {DateTime? now}) {
    if (card.reps == 0) return MasteryLevel.neu;
    // masteryBox ist die PRIMÄRE Grundlage, nicht die momentane
    // Retrievability: die ist direkt nach JEDER Wiederholung (egal ob
    // richtig oder falsch beantwortet) per Definition ~100%, da die
    // Vergessenskurve bei Elapsed-Zeit 0 immer bei 1 startet. Würde man
    // stattdessen zuerst nach Retrievability filtern, würde eine gerade
    // komplett falsch beantwortete Karte (masteryBox fällt auf 0) sofort
    // danach fälschlich als "Gelb" statt "Rot" erscheinen. masteryBox <= 0
    // heißt: kein einziger bestätigter Kenntnisstand vorhanden -> Rot,
    // unabhängig von der (hier bedeutungslosen) Retrievability.
    if (card.masteryBox <= 0) return MasteryLevel.red;
    // Retrievability dient hier nur noch als VERFALLS-Signal für bereits
    // einmal erfolgreich gelernte Karten: wurde eine Karte lange nicht mehr
    // wiederholt und ist ihre geschätzte Behaltensrate stark gesunken, soll
    // sie trotz vorhandener masteryBox-Historie wieder als "Schwach" gelten
    // (vermutlich inzwischen vergessen).
    final r = _fsrs.currentRetrievability(card, now: now);
    if (r < redThreshold) return MasteryLevel.red;
    // "Grün" braucht zusätzlich zur ausreichenden Retrievability mehrfach
    // über die Zeit bestätigtes Wissen (masteryBox am Cap) – sonst würden
    // zwei schnell hintereinander (ggf. geratene) richtige Antworten schon
    // reichen.
    return (card.masteryBox >= Flashcard.masteryBoxCap && r >= yellowThreshold)
        ? MasteryLevel.green
        : MasteryLevel.yellow;
  }

  /// Anzahl Karten je Ampel-Stufe – Grundlage für Übersichten (Modul-Detail,
  /// Statistik), ohne dass die UI selbst FSRS-Berechnungen anstellen muss.
  Map<MasteryLevel, int> breakdown(List<Flashcard> cards, {DateTime? now}) {
    final counts = {for (final l in MasteryLevel.values) l: 0};
    for (final card in cards) {
      final level = levelFor(card, now: now);
      counts[level] = counts[level]! + 1;
    }
    return counts;
  }
}
