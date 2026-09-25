import 'dart:math';

import '../models/flashcard.dart';

/// Bewertung einer Karteikarte nach dem Umdrehen (Anki-Konvention).
enum Grade { again, hard, good, easy }

extension on Grade {
  int get value => index + 1; // Again=1 .. Easy=4
}

/// FSRS-4.5-Scheduler (Free Spaced Repetition Scheduler), portiert nach Dart.
///
/// Referenzimplementierung: https://github.com/open-spaced-repetition/fsrs4anki
/// Diese App ist eine tägliche Lernsession (kein Intraday-Anki-Klon), daher
/// wird bewusst auf die "same-day learning steps" (kurzfristige
/// Minuten/Stunden-Intervalle) verzichtet: jede Bewertung – auch "Nochmal" –
/// resultiert in einem Intervall von mindestens einem Tag, damit die Karte
/// beim nächsten Daily Quiz wieder auftaucht statt noch am selben Tag.
class FsrsService {
  FsrsService({this.requestRetention = 0.9});

  /// Ziel-Erinnerungswahrscheinlichkeit, auf die das nächste Intervall hin
  /// geplant wird (Standard 90%, wie bei Anki/FSRS üblich).
  final double requestRetention;

  static const double _decay = -0.5;
  static final double _factor = pow(0.9, 1 / _decay) - 1;

  // FSRS-4.5 Default-Gewichte (w0..w18).
  static const List<double> _w = [
    0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0234, 1.616,
    0.1544, 1.0824, 1.9813, 0.0953, 0.2975, 2.2042, 0.2407, 2.9466, 0.5034,
    0.6567,
  ];

  double _clampDifficulty(double d) => d.clamp(1.0, 10.0);

  double _initialStability(Grade g) => max(_w[g.value - 1], 0.1);

  double _initialDifficulty(Grade g) {
    final d = _w[4] - (g.value - 3) * _w[5];
    return _clampDifficulty(d);
  }

  double _nextDifficulty(double d, Grade g) {
    final base = _w[4]; // D0(Easy=4) reference for mean reversion
    final deltaD = d - (g.value - 3) * _w[6];
    final reverted = _w[7] * base + (1 - _w[7]) * deltaD;
    return _clampDifficulty(reverted);
  }

  double _retrievability(int elapsedDays, double stability) {
    if (stability <= 0) return 0;
    return pow(1 + _factor * elapsedDays / stability, _decay).toDouble();
  }

  double _nextStabilityOnRecall(
      double d, double s, double r, Grade g) {
    final hardPenalty = g == Grade.hard ? _w[15] : 1.0;
    final easyBonus = g == Grade.easy ? _w[16] : 1.0;
    final growth = exp(_w[8]) *
            (11 - d) *
            pow(s, -_w[9]) *
            (exp((1 - r) * _w[10]) - 1) *
            hardPenalty *
            easyBonus +
        1;
    return s * growth;
  }

  double _nextStabilityOnLapse(double d, double s, double r) {
    return _w[11] *
        pow(d, -_w[12]) *
        (pow(s + 1, _w[13]) - 1) *
        exp((1 - r) * _w[14]);
  }

  /// Intervall in Tagen, nach dem die Karte bei [stability] auf
  /// [requestRetention] abgesunken ist. Wird auf mindestens 1 Tag begrenzt.
  int intervalDays(double stability) {
    final raw = stability /
        _factor *
        (pow(requestRetention, 1 / _decay) - 1);
    return max(1, raw.round());
  }

  /// Wendet eine Bewertung auf eine Karteikarte an und liefert den Datensatz
  /// mit aktualisiertem Spaced-Repetition-Zustand zurück.
  Flashcard review(Flashcard card, Grade grade, {DateTime? now}) {
    final reviewedAt = now ?? DateTime.now();
    final isNew = card.reps == 0;

    double difficulty;
    double stability;

    if (isNew) {
      difficulty = _initialDifficulty(grade);
      stability = _initialStability(grade);
    } else {
      final elapsed = card.lastReview == null
          ? 0
          : reviewedAt.difference(card.lastReview!).inDays;
      final r = _retrievability(elapsed, card.stability);
      difficulty = _nextDifficulty(card.difficulty, grade);
      stability = grade == Grade.again
          ? _nextStabilityOnLapse(card.difficulty, card.stability, r)
          : _nextStabilityOnRecall(card.difficulty, card.stability, r, grade);
    }

    final scheduled = intervalDays(stability);
    final due = DateTime(reviewedAt.year, reviewedAt.month, reviewedAt.day)
        .add(Duration(days: scheduled));

    // Generischer Mastery-Box-Zähler für die Ampel (siehe Flashcard.masteryBox
    // Doc-Kommentar): "gewusst" (good/easy) steigt ihn, alles andere
    // (again/hard, also auch ein bloß mühsam Erratenes) senkt ihn wieder.
    // Steigen nur einmal pro Kalendertag: wird dieselbe Karte am selben Tag
    // mehrfach richtig beantwortet (Üben-Modus, Wiederholungsrunde im Daily
    // Quiz), ist das Kurzzeitgedächtnis, kein über mehrere Sessions
    // nachgewiesenes Wissen – sonst wäre "Grün" in wenigen Minuten erreichbar.
    final knewIt = grade == Grade.good || grade == Grade.easy;
    final lastReview = card.lastReview;
    final alreadyReviewedToday = lastReview != null &&
        lastReview.year == reviewedAt.year &&
        lastReview.month == reviewedAt.month &&
        lastReview.day == reviewedAt.day;
    final masteryBox = knewIt
        ? (alreadyReviewedToday ? card.masteryBox : (card.masteryBox + 1).clamp(0, Flashcard.masteryBoxCap))
        : (card.masteryBox - 1).clamp(0, Flashcard.masteryBoxCap);

    return card.copyWithReview(
      due: due,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: card.lastReview == null
          ? 0
          : reviewedAt.difference(card.lastReview!).inDays,
      scheduledDays: scheduled,
      reps: card.reps + 1,
      lapses: grade == Grade.again ? card.lapses + 1 : card.lapses,
      state: grade == Grade.again ? 'relearning' : 'review',
      lastReview: reviewedAt,
      masteryBox: masteryBox,
    );
  }

  /// Aktuelle geschätzte Erinnerungswahrscheinlichkeit einer Karte "heute".
  double currentRetrievability(Flashcard card, {DateTime? now}) {
    if (card.reps == 0 || card.lastReview == null) return 0;
    final elapsed = (now ?? DateTime.now()).difference(card.lastReview!).inDays;
    return _retrievability(elapsed, card.stability);
  }

  /// Leitet für automatisch auswertbare Fragetypen (Single-/Multiple-Choice,
  /// Freitext, Lückentext, Zuordnen – siehe AnswerChecker) eine FSRS-
  /// Bewertung aus der reinen Korrektheit ab, statt den Nutzer selbst
  /// einschätzen zu lassen (das bleibt dem offenen `flashcard`-Typ
  /// vorbehalten). Binär wie von FSRS für Zwei-Tasten-Bewertung empfohlen:
  ///  - falsch -> Again: in FSRS ist "Hard" ein ERFOLGREICHER Abruf
  ///    (Stabilität wächst, Intervall wird länger) – eine falsch beantwortete
  ///    Frage käme damit später statt früher wieder.
  ///  - richtig -> Good: "Easy" hieße mühelos gewusst, was eine automatische
  ///    Prüfung nicht erkennen kann – bei einer neuen Karte wären das sofort
  ///    ~15 Tage Pause, auch nach einer bloß geratenen Single-Choice-Antwort.
  Grade gradeFromResult(bool isCorrect) => isCorrect ? Grade.good : Grade.again;
}
