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

/// Leitet aus dem FSRS-Zustand einer Karte (siehe FsrsService) eine simple
/// Rot/Gelb/Grün-Einstufung ab – die Grundlage ist dieselbe geschätzte
/// Erinnerungswahrscheinlichkeit, die auch der Scheduler nutzt, nur direkt
/// für den Nutzer sichtbar gemacht statt nur intern zur Fälligkeitsberechnung
/// zu dienen.
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
    final r = _fsrs.currentRetrievability(card, now: now);
    if (r < redThreshold) return MasteryLevel.red;
    if (r < yellowThreshold) return MasteryLevel.yellow;
    // "Grün" braucht zusätzlich zur momentanen Retrievability (die direkt
    // nach JEDER Wiederholung per Definition ~100% beträgt, siehe
    // Flashcard.masteryBox Doc-Kommentar) mehrfach über die Zeit bestätigtes
    // Wissen – sonst würden zwei schnell hintereinander (ggf. geratene)
    // richtige Antworten schon reichen.
    return card.masteryBox >= Flashcard.masteryBoxCap ? MasteryLevel.green : MasteryLevel.yellow;
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
