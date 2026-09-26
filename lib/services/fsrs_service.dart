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

  /// Höchstabstand in Tagen auf einer leichten/mittleren Stufe einer
  /// Eskalationskette (siehe [review]).
  static const int transitStageMaxIntervalDays = 7;

  /// Vergangene KALENDERTAGE zwischen zwei Zeitpunkten. Die App plant in
  /// ganzen Tagen ("morgen fällig") – abends lernen und am nächsten Morgen
  /// wiederholen ist ein Tag Abstand, auch wenn keine 24 Stunden vergangen
  /// sind (mit `difference().inDays` wären es 0 Tage: keine Stabilitäts-
  /// zunahme, das Intervall wüchse nicht). Über UTC-Daten gerechnet, damit
  /// die Zeitumstellung (23-/25-Stunden-Tag) nichts verschiebt.
  static int calendarDaysBetween(DateTime from, DateTime to) => max(
        0,
        DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays,
      );

  /// Mitternacht [days] Kalendertage nach [at] – ohne Stunden-Addition, die
  /// an der Zeitumstellung eine Stunde daneben läge.
  static DateTime _startOfDayPlus(DateTime at, int days) => DateTime(at.year, at.month, at.day + days);

  static bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  /// Ob [grade] ein ERNEUTER Fehlversuch am selben Tag wäre: die Karte wurde
  /// heute schon beantwortet, und zwar falsch (Zustand learning/relearning) –
  /// z.B. in der Wiederholungsrunde des Daily Quiz oder beim Üben. Das ist
  /// dieselbe Wissenslücke wie beim ersten Fehlversuch, kein neues Vergessen:
  /// [review] und ReviewService.evaluate verbuchen sie deshalb nicht noch
  /// einmal – spiegelbildlich zum Aufstieg, der auch nur einmal pro Tag zählt.
  static bool isRepeatFailureToday(Flashcard card, Grade grade, DateTime at) =>
      grade == Grade.again &&
      card.reps > 0 &&
      _sameDay(card.lastReview, at) &&
      (card.state == 'learning' || card.state == 'relearning');

  /// Startet eine gerade beförderte Karte auf ihrer neuen, schwereren Stufe
  /// neu: morgen fällig, Anfangs-Stabilität wie nach einem ersten "Gut",
  /// Ampel bei Gelb (masteryBox 1 – "angefangen, noch nicht gefestigt").
  /// Ohne das würde die neue Stufe den langen Abstand der alten erben und
  /// erst Wochen später zum ersten Mal drankommen, und sie stünde sofort
  /// auf Grün, obwohl sie noch nie beantwortet wurde.
  Flashcard restartForNewStage(Flashcard card, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return card.copyWithReview(
      due: _startOfDayPlus(at, 1),
      stability: _initialStability(Grade.good),
      difficulty: card.difficulty,
      elapsedDays: card.elapsedDays,
      scheduledDays: 1,
      reps: card.reps,
      lapses: card.lapses,
      state: 'review',
      lastReview: card.lastReview ?? at,
      masteryBox: 1,
    );
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
    final repeatFailure = isRepeatFailureToday(card, grade, reviewedAt);

    double difficulty;
    double stability;

    if (isNew) {
      difficulty = _initialDifficulty(grade);
      stability = _initialStability(grade);
    } else if (repeatFailure) {
      // Siehe [isRepeatFailureToday]: Stabilität und Schwierigkeit wurden
      // beim ersten Fehlversuch heute schon angepasst.
      difficulty = card.difficulty;
      stability = card.stability;
    } else {
      final elapsed = card.lastReview == null ? 0 : calendarDaysBetween(card.lastReview!, reviewedAt);
      final r = _retrievability(elapsed, card.stability);
      difficulty = _nextDifficulty(card.difficulty, grade);
      stability = grade == Grade.again
          ? _nextStabilityOnLapse(card.difficulty, card.stability, r)
          : _nextStabilityOnRecall(card.difficulty, card.stability, r, grade);
    }

    // Leichte und mittlere Stufen einer Eskalationskette sind Durchgangs-
    // stufen: sie sollen regelmäßig drankommen, bis sie grün sind und die
    // nächste Stufe freischalten – erst die schwerste Stufe bekommt die
    // vollen, weit auseinanderliegenden Spaced-Repetition-Abstände. Ohne
    // Deckel läge zwischen den vier nötigen Lerntagen einer Stufe schnell
    // ein Monat, die schwere Stufe käme dann erst nach dem Semester dran.
    final chain = card.variantChain;
    final isTransitStage = chain != null && card.variantLevel < chain.length - 1;
    final rawInterval = intervalDays(stability);
    final scheduled = isTransitStage ? min(rawInterval, transitStageMaxIntervalDays) : rawInterval;
    final due = _startOfDayPlus(reviewedAt, scheduled);

    // Generischer Mastery-Box-Zähler für die Ampel (siehe Flashcard.masteryBox
    // Doc-Kommentar): "gewusst" (good/easy) steigt ihn, "Nochmal" senkt ihn.
    // "Schwer" lässt ihn stehen: die Antwort war richtig, nur mühsam – das
    // ist kein Rückschritt, aber auch noch kein sicheres Wissen.
    // Steigen nur einmal pro Kalendertag: wird dieselbe Karte am selben Tag
    // mehrfach richtig beantwortet (Üben-Modus, Wiederholungsrunde im Daily
    // Quiz), ist das Kurzzeitgedächtnis, kein über mehrere Sessions
    // nachgewiesenes Wissen – sonst wäre "Grün" in wenigen Minuten erreichbar.
    // Sinken ebenso nur einmal pro Tag (siehe [isRepeatFailureToday]) – sonst
    // würde aus Grün in einer einzigen Wiederholungsrunde Rot.
    final alreadyReviewedToday = _sameDay(card.lastReview, reviewedAt);
    final masteryBox = switch (grade) {
      Grade.good || Grade.easy =>
        alreadyReviewedToday ? card.masteryBox : (card.masteryBox + 1).clamp(0, Flashcard.masteryBoxCap),
      Grade.hard => card.masteryBox,
      Grade.again => repeatFailure ? card.masteryBox : (card.masteryBox - 1).clamp(0, Flashcard.masteryBoxCap),
    };

    return card.copyWithReview(
      due: due,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: card.lastReview == null ? 0 : calendarDaysBetween(card.lastReview!, reviewedAt),
      scheduledDays: scheduled,
      reps: card.reps + 1,
      // Ein Lapse ist das Vergessen einer schon GELERNTEN Karte – eine neue
      // Karte beim ersten Versuch nicht zu wissen, zählt nicht dazu (sonst
      // stünde sie im Fehlertagebuch als "1× vergessen"), ein erneuter
      // Fehlversuch am selben Tag ebenso wenig.
      lapses: grade == Grade.again && !isNew && !repeatFailure ? card.lapses + 1 : card.lapses,
      state: grade == Grade.again
          ? (repeatFailure ? card.state : (isNew ? 'learning' : 'relearning'))
          : 'review',
      lastReview: reviewedAt,
      masteryBox: masteryBox,
    );
  }

  /// Aktuelle geschätzte Erinnerungswahrscheinlichkeit einer Karte "heute".
  double currentRetrievability(Flashcard card, {DateTime? now}) {
    if (card.reps == 0 || card.lastReview == null) return 0;
    return _retrievability(calendarDaysBetween(card.lastReview!, now ?? DateTime.now()), card.stability);
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
