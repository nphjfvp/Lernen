import 'fsrs_service.dart';

/// Antwort einer Frage-Ansicht: [selfGrade] (selbst bewertet) bzw.
/// [isCorrect] (automatisch geprüft) plus [signals] (Sicherheit, „Weiß ich
/// nicht“, Tipp-Stufe).
typedef AnswerCallback = void Function({Grade? selfGrade, bool? isCorrect, AnswerSignals? signals});

/// Wie sicher man sich VOR dem Prüfen war (freiwillig, siehe
/// QuestionAnswerView). Ein richtig geratener Treffer ist kein Wissen, eine
/// sichere falsche Antwort deutet auf eine Fehlvorstellung hin.
enum AnswerConfidence {
  guessed('geraten'),
  unsure('eher sicher'),
  sure('sicher');

  const AnswerConfidence(this.label);

  final String label;

  /// Für das Antwort-Protokoll (stabil, nicht der Anzeigetext).
  String get key => name;

  static AnswerConfidence? fromKey(Object? key) {
    for (final c in values) {
      if (c.name == key) return c;
    }
    return null;
  }
}

/// Ursache des ersten Fehlers in einem auf Papier gerechneten Rechenweg
/// (Panik-Modus, siehe PanikPaperView) – fürs Fehlerprotokoll.
enum ErrorCause {
  procedure('Verfahren falsch gewählt'),
  calculation('Rechenfehler'),
  sign('Vorzeichen'),
  formula('Formel/Korrespondenz falsch'),
  missingStep('Schritt vergessen'),
  other('Sonstiges');

  const ErrorCause(this.label);
  final String label;

  static ErrorCause? fromKey(Object? key) => values.where((c) => c.name == key).firstOrNull;
}

/// Stufen der Hilfe-Leiter (siehe [AnswerSignals.hintLevel]): je Klick auf
/// „Tipp“ eine Stufe mehr, von „schau auf die Angabe“ bis „so fängst du an“.
/// Wie viel Hilfe nötig war, bestimmt die Bewertung (siehe
/// [AnswerSignals.gradeFor]).
class HintLadder {
  HintLadder._();

  static const int maxLevel = 5;

  /// Kurzname je Stufe (Index = Stufe − 1).
  static const List<String> names = [
    'Blick auf die Angabe',
    'Art der Aufgabe',
    'Themengebiet',
    'Regel genannt',
    'Ansatz',
  ];

  /// Was die KI auf der jeweiligen Stufe verraten darf (Index = Stufe − 1).
  static const List<String> instructions = [
    'Lenke nur die Aufmerksamkeit auf die entscheidende Stelle der Aufgabe (was ist gegeben, was ist gefragt, welches Wort ist wichtig). Nenne KEINEN Fachbegriff, keine Regel und keine Formel.',
    'Beschreibe, was für eine Art Problem das ist (z.B. „hier wird etwas aus vielen kleinen Teilen zusammengesetzt“), ohne die passende Regel, Formel oder den Fachbegriff zu nennen.',
    'Grenze das Themengebiet bzw. die Begriffsfamilie ein, aus der die Lösung kommt – die Auswahl, WELCHE Regel genau gilt, bleibt beim Lernenden.',
    'Nenne die anzuwendende Regel, Formel oder den Begriff ausdrücklich. Die Anwendung auf die Aufgabe bleibt beim Lernenden.',
    'Skizziere den ersten Schritt bzw. den Ansatz konkret, aber ohne das Endergebnis zu nennen.',
  ];

  static String nameOf(int level) => names[(level.clamp(1, maxLevel)) - 1];

  static String instructionOf(int level) => instructions[(level.clamp(1, maxLevel)) - 1];

  /// Was eine richtige Antwort nach Tipps dieser Stufe noch wert ist.
  static String costOf(int level) {
    if (level <= 1) return 'zählt noch voll';
    if (level <= 3) return 'richtig zählt dann als „Schwer“';
    return 'richtig zählt dann als nicht gewusst';
  }
}

/// Was beim Antworten außer „richtig/falsch“ noch passiert ist: Sicherheit,
/// „Weiß ich nicht“, Tipps, neue Einkleidung. Wird mit der Antwort
/// durchgereicht (QuestionAnswerView → CardReviewMixin.recordReview) und
/// fließt in die Bewertung und das Antwort-Protokoll.
class AnswerSignals {
  const AnswerSignals({
    this.confidence,
    this.dontKnow = false,
    this.hintLevel = 0,
    this.variant = false,
    this.errorCause,
    this.errorStep,
  });

  static const none = AnswerSignals();

  final AnswerConfidence? confidence;

  /// „Weiß ich nicht“: ehrliche Lücke statt Raten – zählt als nicht gewusst,
  /// ist aber keine Fehlvorstellung.
  final bool dontKnow;

  /// Höchste gesehene Stufe der Hilfe-Leiter (0 = keine Hilfe, siehe
  /// [HintLadder]).
  final int hintLevel;

  /// Beantwortet wurde eine neu eingekleidete Fassung der Karte (siehe
  /// Wiederholungsrunde im Daily Quiz) – nur fürs Protokoll.
  final bool variant;

  /// Rechenweg auf Papier: Ursache des ersten Fehlers und in welchem Schritt
  /// (1-basiert) er lag – null, wenn alles stimmte.
  final ErrorCause? errorCause;
  final int? errorStep;

  AnswerSignals copyWith({AnswerConfidence? confidence, bool? dontKnow, int? hintLevel, bool? variant}) =>
      AnswerSignals(
        confidence: confidence ?? this.confidence,
        dontKnow: dontKnow ?? this.dontKnow,
        hintLevel: hintLevel ?? this.hintLevel,
        variant: variant ?? this.variant,
        errorCause: errorCause,
        errorStep: errorStep,
      );

  /// Bewertung einer Antwort aus Ergebnis und Signalen – die EINE Regel für
  /// alle Lernmodi (siehe ReviewService.evaluate):
  /// - „Weiß ich nicht“ oder falsch → Nochmal.
  /// - Tipp Stufe 4–5 (Regel genannt / Ansatz gezeigt) → Nochmal: der Abruf
  ///   selbst ist nicht passiert.
  /// - Tipp Stufe 2–3 oder „geraten“ → höchstens Schwer (die Ampel steigt
  ///   nicht).
  /// - Tipp Stufe 1 (nur Blick auf die Angabe) kostet nichts.
  /// - sonst die Selbstbewertung bzw. Gut.
  static Grade gradeFor({Grade? selfGrade, bool? isCorrect, AnswerSignals signals = none}) {
    if (signals.dontKnow || isCorrect == false) return Grade.again;
    var grade = selfGrade ?? (isCorrect == true ? Grade.good : Grade.again);
    if (grade == Grade.again) return grade;
    if (signals.hintLevel >= 4) return Grade.again;
    if (signals.hintLevel >= 2) grade = _atMostHard(grade);
    if (signals.confidence == AnswerConfidence.guessed) grade = _atMostHard(grade);
    return grade;
  }

  static Grade _atMostHard(Grade g) => g.index > Grade.hard.index ? Grade.hard : g;

  /// Sicher und trotzdem falsch: Hinweis auf eine Fehlvorstellung (nicht nur
  /// eine Lücke).
  static bool isConfidentMiss({bool? isCorrect, required AnswerSignals signals}) =>
      isCorrect == false && !signals.dontKnow && signals.confidence == AnswerConfidence.sure;
}
