import '../models/flashcard.dart';

/// Aufgaben-Ordner eines Fachs: alle Aufgaben zum Verstehen
/// ([QuestionType.learn]) – also die, die sich in einer Quiz-App nicht
/// abfragen lassen und stattdessen erklärt werden. Sie bleiben dauerhaft
/// einsehbar, unabhängig davon, wie weit der Lernplan schon ist; kurz vor
/// der Klausur wird der Ordner rot markiert, damit man sie außerhalb der App
/// durcharbeitet.
class TaskFolderService {
  const TaskFolderService._();

  /// So viele Tage vor der Klausur wird der Ordner rot.
  static const int warnDaysBeforeExam = 20;

  /// Die Aufgaben aus [cards] in der Reihenfolge des Materials: nach Datei,
  /// Seite und Erstellung.
  static List<Flashcard> tasksOf(Iterable<Flashcard> cards) => [
        for (final c in cards)
          // Eine stummgeschaltete Aufgabe (Gewicht 0) will man nicht mehr
          // bearbeiten – sie steht weder im Ordner noch im Klausur-Hinweis.
          if (c.type == QuestionType.learn && !c.isMuted) c,
      ]..sort((a, b) {
          final byMaterial = (a.sourceMaterialId ?? '').compareTo(b.sourceMaterialId ?? '');
          if (byMaterial != 0) return byMaterial;
          final byPage = (a.sourcePage ?? 0).compareTo(b.sourcePage ?? 0);
          return byPage != 0 ? byPage : a.createdAt.compareTo(b.createdAt);
        });

  /// Ganze Kalendertage bis zur Klausur (0 = heute), negativ, wenn sie
  /// vorbei ist; `null` ohne Datum.
  static int? daysUntilExam(DateTime? examDate, {DateTime? now}) {
    if (examDate == null) return null;
    final today = now ?? DateTime.now();
    // Über UTC-Mitternachten gerechnet – Sommerzeit-Wechsel verfälschen die
    // Tageszahl sonst um einen Tag.
    return DateTime.utc(examDate.year, examDate.month, examDate.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;
  }

  /// Ob der Ordner rot markiert ist: es gibt Aufgaben und die Klausur liegt
  /// höchstens [warnDaysBeforeExam] Tage entfernt (heute eingeschlossen,
  /// eine vergangene nicht).
  static bool isWarning({required int taskCount, required DateTime? examDate, DateTime? now}) {
    if (taskCount <= 0) return false;
    final days = daysUntilExam(examDate, now: now);
    return days != null && days >= 0 && days <= warnDaysBeforeExam;
  }
}
