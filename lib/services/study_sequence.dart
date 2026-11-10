import '../models/flashcard.dart';
import '../models/study_sequence.dart';
import 'stage_gate_service.dart';

/// Logik für „Der Reihe nach“: Reihenfolge der Aufgaben einer Einheit/PDF,
/// welche in einer Runde drankommen und wie eine Antwort den Stand ändert.
///
/// Beispiel: 1–7 gelöst, 8 nicht, 9–11 gelöst → die nächste Runde beginnt
/// bei 8 und überspringt 9–11.
class StudySequence {
  const StudySequence._();

  /// Die Aufgaben von [source] in Dokument-Reihenfolge: nach Material
  /// ([materialOrder] = Reihenfolge der Materialien im Fach), Seite und
  /// Import-Zeitpunkt (der hält die Reihenfolge innerhalb einer PDF).
  static List<Flashcard> ordered(
    List<Flashcard> moduleCards,
    StudySequenceSource source, {
    List<String> materialOrder = const [],
    StudySequenceOrder order = StudySequenceOrder.document,
  }) {
    final cards = [
      for (final c in moduleCards)
        if (source.kind == StudySequenceKind.unit ? c.unitId == source.id : c.sourceMaterialId == source.id) c,
    ];
    int rank(Flashcard c) {
      final i = c.sourceMaterialId == null ? -1 : materialOrder.indexOf(c.sourceMaterialId!);
      return i < 0 ? materialOrder.length : i;
    }

    cards.sort((a, b) {
      final byMaterial = rank(a).compareTo(rank(b));
      if (byMaterial != 0) return byMaterial;
      if (a.sourceMaterialId == b.sourceMaterialId) {
        final byPage = (a.sourcePage ?? 0).compareTo(b.sourcePage ?? 0);
        if (byPage != 0) return byPage;
      }
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    if (order == StudySequenceOrder.difficulty) {
      // Nach Stufe (leicht, mittel, schwer – siehe StageGate.levelOf), innerhalb
      // einer Stufe bleibt die Dokument-Reihenfolge.
      return [
        for (final level in StageLevel.values)
          for (final c in cards)
            if (StageGate.levelOf(c) == level) c,
      ];
    }
    return cards;
  }

  /// Noch offene Aufgaben (nicht gelöst und nicht übersprungen).
  static List<Flashcard> open(List<Flashcard> ordered, StudySequenceProgress progress) => [
    for (final c in ordered)
      if (!progress.isDone(c.id)) c,
  ];

  /// Was in der laufenden Runde noch drankommt: ab [StudySequenceProgress.nextId]
  /// alle offenen Aufgaben; ist die Runde beendet, alle offenen von vorn.
  static List<Flashcard> round(List<Flashcard> ordered, StudySequenceProgress progress) {
    final start = progress.nextId == null ? -1 : ordered.indexWhere((c) => c.id == progress.nextId);
    final from = start < 0 ? 0 : start;
    return [
      for (final c in ordered.skip(from))
        if (!progress.isDone(c.id)) c,
    ];
  }

  /// Position (1-basiert) der nächsten Aufgabe, null wenn alles erledigt.
  static int? nextPosition(List<Flashcard> ordered, StudySequenceProgress progress) {
    final next = round(ordered, progress).firstOrNull;
    return next == null ? null : ordered.indexOf(next) + 1;
  }

  /// Antwort bzw. „Kann ich schon“ für [cardId]: Stand setzen, die Runde geht
  /// mit der nächsten offenen Aufgabe DAHINTER weiter (keine mehr → Runde
  /// beendet).
  static StudySequenceProgress record(
    List<Flashcard> ordered,
    StudySequenceProgress progress,
    String cardId,
    StudySequenceStatus status,
  ) {
    final updated = {...progress.status, cardId: status};
    final at = ordered.indexWhere((c) => c.id == cardId);
    String? next;
    for (final c in ordered.skip(at + 1)) {
      final s = updated[c.id];
      if (s != StudySequenceStatus.solved && s != StudySequenceStatus.skipped) {
        next = c.id;
        break;
      }
    }
    return progress.copyWith(status: updated, nextId: next, clearNext: next == null);
  }

  /// Neustart ab Aufgabe [index] (0-basiert): alles davor gilt als erledigt
  /// (bereits Gelöstes bleibt gelöst), ab hier ist alles wieder offen.
  static StudySequenceProgress restartAt(List<Flashcard> ordered, StudySequenceProgress progress, int index) {
    final i = index.clamp(0, ordered.length);
    final updated = <String, StudySequenceStatus>{
      for (final c in ordered.take(i))
        c.id: progress.status[c.id] == StudySequenceStatus.solved
            ? StudySequenceStatus.solved
            : StudySequenceStatus.skipped,
    };
    return progress.copyWith(
      status: updated,
      nextId: i < ordered.length ? ordered[i].id : null,
      clearNext: i >= ordered.length,
    );
  }

  /// Eine Aufgabe als verstanden markieren bzw. wieder öffnen.
  static StudySequenceProgress setUnderstood(StudySequenceProgress progress, String cardId, bool understood) {
    final updated = {...progress.status};
    if (understood) {
      updated[cardId] = StudySequenceStatus.skipped;
    } else {
      updated.remove(cardId);
    }
    return progress.copyWith(status: updated);
  }
}
