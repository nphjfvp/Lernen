/// Die Darstellungsform einer Karte. `flashcard` ist die ursprüngliche
/// offene Vorderseite/Rückseite-Karte (selbst bewertet); alle anderen sind
/// automatisch auswertbare Fragetypen (siehe AnswerChecker).
enum QuestionType {
  flashcard,
  singleChoice,
  multipleChoice,
  freeText,
  fillBlank,
  dragDrop,
  dragCategory,
}

QuestionType questionTypeFromString(String? value) => QuestionType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => QuestionType.flashcard,
    );

extension QuestionTypeLabel on QuestionType {
  String get label => switch (this) {
        QuestionType.flashcard => 'Karteikarte',
        QuestionType.singleChoice => 'Single Choice',
        QuestionType.multipleChoice => 'Multiple Choice',
        QuestionType.freeText => 'Freitext',
        QuestionType.fillBlank => 'Lückentext',
        QuestionType.dragDrop => 'Zuordnen',
        QuestionType.dragCategory => 'Kategorien',
      };
}

/// Eine Antwortmöglichkeit bei Single-/Multiple-Choice.
class QuizOption {
  const QuizOption({required this.text, required this.isCorrect});

  final String text;
  final bool isCorrect;

  Map<String, dynamic> toMap() => {'text': text, 'isCorrect': isCorrect};

  factory QuizOption.fromMap(Map<String, dynamic> map) => QuizOption(
        text: map['text'] as String,
        isCorrect: map['isCorrect'] as bool? ?? false,
      );
}

/// Ein Zuordnungspaar bei drag_drop (Begriff -> Ziel) bzw. drag_category
/// (Begriff -> Kategoriename).
class DragPair {
  const DragPair({required this.source, required this.target});

  final String source;
  final String target;

  Map<String, dynamic> toMap() => {'source': source, 'target': target};

  factory DragPair.fromMap(Map<String, dynamic> map) => DragPair(
        source: map['source'] as String,
        target: map['target'] as String,
      );
}

/// Momentaufnahme des Karten-Inhalts EINER Eskalationsstufe, angelegt kurz
/// bevor [Flashcard.copyWithPromotedVariant] ihn durch die nächste
/// (schwerere) Stufe überschreibt. Grundlage für
/// [Flashcard.copyWithDemotedVariant]: hält ein Nutzer eine Stufe dauerhaft
/// nicht mehr, kommt so wieder GENAU der alte Wortlaut zurück, ohne dafür
/// erneut die KI bemühen zu müssen.
class VariantSnapshot {
  const VariantSnapshot({
    required this.type,
    required this.front,
    required this.back,
    this.options,
    this.correctText,
    this.blanks,
    this.dragPairs,
  });

  final QuestionType type;
  final String front;
  final String back;
  final List<QuizOption>? options;
  final String? correctText;
  final List<String>? blanks;
  final List<DragPair>? dragPairs;

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'front': front,
        'back': back,
        'options': options?.map((o) => o.toMap()).toList(),
        'correctText': correctText,
        'blanks': blanks,
        'dragPairs': dragPairs?.map((p) => p.toMap()).toList(),
      };

  factory VariantSnapshot.fromMap(Map<String, dynamic> map) => VariantSnapshot(
        type: questionTypeFromString(map['type'] as String?),
        front: map['front'] as String,
        back: map['back'] as String? ?? '',
        options: (map['options'] as List?)
            ?.map((o) => QuizOption.fromMap(Map<String, dynamic>.from(o as Map)))
            .toList(),
        correctText: map['correctText'] as String?,
        blanks: (map['blanks'] as List?)?.map((b) => b.toString()).toList(),
        dragPairs: (map['dragPairs'] as List?)
            ?.map((p) => DragPair.fromMap(Map<String, dynamic>.from(p as Map)))
            .toList(),
      );
}

/// Eine Karteikarte/Frage fürs Daily Quiz. Trägt ihren eigenen Spaced-
/// Repetition-Zustand direkt auf dem Datensatz (statt einer separaten
/// Review-Tabelle), das hält die App schlank.
///
/// [front] ist bei allen Fragetypen die Fragestellung; was als "Antwort"
/// zählt, hängt vom [type] ab: bei `flashcard` ist es [back] (offen, selbst
/// bewertet), bei den übrigen Typen [options]/[correctText]/[blanks]/
/// [dragPairs] (automatisch ausgewertet, siehe AnswerChecker).
///
/// [variantChain] macht eine Frage Teil einer Schwierigkeits-Eskalation
/// (z.B. Single-Choice -> Lückentext -> Freitext): steigt [variantBox] beim
/// wiederholten richtigen Beantworten hoch genug, wird die Frage lazy (nur
/// bei Bedarf, ein KI-Aufruf) in den nächsten Typ der Kette umgewandelt und
/// [variantLevel] erhöht. Sinkt die Box dagegen auf einer Stufe > 0 wieder
/// auf 0 UND es kommt noch ein Fehlversuch dazu, wird automatisch eine
/// Stufe zurückgestuft (siehe [copyWithBoxUpdate]/[copyWithDemotedVariant])
/// – Adaptivität in BEIDE Richtungen statt nur aufwärts. `null` bei
/// [variantChain] bedeutet: kein Eskalations-Typ, die Frage bleibt
/// dauerhaft in ihrem [type].
class Flashcard {
  final String id;
  final String moduleId;
  final String? conceptId;
  final String front;
  final String back;
  final DateTime createdAt;

  final QuestionType type;
  final List<QuizOption>? options;
  final String? correctText;
  final List<String>? blanks;
  final List<DragPair>? dragPairs;

  final List<QuestionType>? variantChain;
  final int variantLevel;
  final int variantBox;

  /// Inhalt jeder bereits verlassenen, leichteren Eskalationsstufe, in der
  /// Reihenfolge, in der sie durchlaufen wurden (letzter Eintrag = zuletzt
  /// verlassene Stufe, direkt unter der aktuellen). Wird bei jeder
  /// Beförderung um einen Eintrag länger, bei jeder Rückstufung um einen
  /// kürzer.
  final List<VariantSnapshot>? variantHistory;

  /// Anzahl FALSCHER Antworten in Folge auf der aktuellen Eskalationsstufe
  /// (jede richtige Antwort setzt ihn auf 0 zurück) – getrennt von
  /// [variantBox] geführt, damit "Box ist gerade frisch auf 0, weil eben
  /// befördert wurde" nicht mit "zwei Fehlversuche in Folge" verwechselt
  /// wird. Erreicht er [demotionMissStreakThreshold], stuft
  /// [copyWithBoxUpdate] automatisch zurück.
  final int variantMissStreak;

  // FSRS-Zustand
  final DateTime due;
  final double stability;
  final double difficulty;
  final int elapsedDays;
  final int scheduledDays;
  final int reps;
  final int lapses;
  final String state; // new | learning | review | relearning
  final DateTime? lastReview;

  /// Welcher Vorlesungseinheit (siehe LectureUnit) diese Karte zugeordnet
  /// ist – übernommen vom Konzept/Material, aus dem sie generiert wurde.
  /// Null = keine Einheit (ältere Karten, oder ohne Einheiten-Auswahl
  /// generiert) – solche Karten bleiben immer verfügbar. Ist eine Einheit
  /// gesetzt, aber (noch) nicht als "behandelt" markiert, lässt der
  /// DailyScheduler die Karte aus (siehe DailySchedulerService.buildPlan).
  final String? unitId;

  const Flashcard({
    required this.id,
    required this.moduleId,
    this.conceptId,
    required this.front,
    required this.back,
    required this.createdAt,
    required this.due,
    this.type = QuestionType.flashcard,
    this.options,
    this.correctText,
    this.blanks,
    this.dragPairs,
    this.variantChain,
    this.variantLevel = 0,
    this.variantBox = 0,
    this.variantHistory,
    this.variantMissStreak = 0,
    this.stability = 0,
    this.difficulty = 0,
    this.elapsedDays = 0,
    this.scheduledDays = 0,
    this.reps = 0,
    this.lapses = 0,
    this.state = 'new',
    this.lastReview,
    this.unitId,
  });

  /// Kanonische Antwort-Darstellung, unabhängig vom Fragetyp - Grundlage,
  /// wenn eine harte Variante daraus erzeugt wird (siehe
  /// AiService.generateHarderVariant), damit sich der geprüfte Fakt dabei
  /// nicht ändert.
  String get answerSummary => switch (type) {
        QuestionType.flashcard => back,
        QuestionType.singleChoice ||
        QuestionType.multipleChoice =>
          (options ?? const []).where((o) => o.isCorrect).map((o) => o.text).join('; '),
        QuestionType.freeText => correctText ?? '',
        QuestionType.fillBlank => (blanks ?? const []).join('; '),
        QuestionType.dragDrop ||
        QuestionType.dragCategory =>
          (dragPairs ?? const []).map((p) => '${p.source} -> ${p.target}').join('; '),
      };

  Flashcard copyWithReview({
    required DateTime due,
    required double stability,
    required double difficulty,
    required int elapsedDays,
    required int scheduledDays,
    required int reps,
    required int lapses,
    required String state,
    required DateTime lastReview,
  }) {
    return Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: front,
      back: back,
      createdAt: createdAt,
      due: due,
      type: type,
      options: options,
      correctText: correctText,
      blanks: blanks,
      dragPairs: dragPairs,
      variantChain: variantChain,
      variantLevel: variantLevel,
      variantBox: variantBox,
      variantHistory: variantHistory,
      variantMissStreak: variantMissStreak,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
    );
  }

  /// Für manuelle Textkorrekturen (siehe FlashcardListScreen) – der
  /// Spaced-Repetition-Zustand bleibt dabei unverändert. Nur für den
  /// einfachen `flashcard`-Typ gedacht (Vorderseite/Rückseite).
  Flashcard copyWithText({required String front, required String back}) {
    return Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: front,
      back: back,
      createdAt: createdAt,
      due: due,
      type: type,
      options: options,
      correctText: correctText,
      blanks: blanks,
      dragPairs: dragPairs,
      variantChain: variantChain,
      variantLevel: variantLevel,
      variantBox: variantBox,
      variantHistory: variantHistory,
      variantMissStreak: variantMissStreak,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
    );
  }

  /// Ab wie vielen FALSCHEN Antworten in Folge auf derselben Eskalationsstufe
  /// [copyWithBoxUpdate] automatisch zurückstuft (siehe [variantMissStreak]).
  static const int demotionMissStreakThreshold = 2;

  /// Nach einer Antwort: Leitner-Box fortschreiben (rein für die
  /// Varianten-Eskalation, unabhängig vom FSRS-Zustand) – in BEIDE
  /// Richtungen. Erreicht die Box die "grüne" Schwelle und ist eine nächste
  /// Stufe in [variantChain] vorhanden, wird das über die zurückgegebene
  /// [nextType] signalisiert - das eigentliche Umwandeln (KI-Aufruf)
  /// übernimmt der Aufrufer, damit dieses Modell frei von I/O bleibt.
  /// Umgekehrt: erreicht [variantMissStreak] (Fehlversuche IN FOLGE auf
  /// dieser Stufe) [demotionMissStreakThreshold], wird sofort zur
  /// vorherigen, leichteren Stufe zurückgestuft (siehe
  /// [copyWithDemotedVariant]) – dafür ist KEIN weiterer KI-Aufruf nötig,
  /// der alte Wortlaut liegt bereits in [variantHistory].
  ({Flashcard card, QuestionType? nextType}) copyWithBoxUpdate({required bool isCorrect}) {
    final chain = variantChain;
    final canPromote =
        chain != null && variantLevel < chain.length - 1 && variantBox + 1 >= Flashcard.promotionThreshold && isCorrect;
    if (canPromote) {
      final updated = Flashcard(
        id: id,
        moduleId: moduleId,
        conceptId: conceptId,
        front: front,
        back: back,
        createdAt: createdAt,
        due: due,
        type: type,
        options: options,
        correctText: correctText,
        blanks: blanks,
        dragPairs: dragPairs,
        variantChain: chain,
        variantLevel: variantLevel,
        variantBox: 0,
        variantHistory: variantHistory,
        variantMissStreak: 0,
        stability: stability,
        difficulty: difficulty,
        elapsedDays: elapsedDays,
        scheduledDays: scheduledDays,
        reps: reps,
        lapses: lapses,
        state: state,
        lastReview: lastReview,
        unitId: unitId,
      );
      return (card: updated, nextType: chain[variantLevel + 1]);
    }

    final missStreak = isCorrect ? 0 : variantMissStreak + 1;
    final canDemote = !isCorrect &&
        variantLevel > 0 &&
        missStreak >= demotionMissStreakThreshold &&
        (variantHistory?.isNotEmpty ?? false);
    if (canDemote) {
      return (card: copyWithDemotedVariant(), nextType: null);
    }

    final newBox = isCorrect ? variantBox + 1 : (variantBox - 1).clamp(0, 999);
    final updated = Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: front,
      back: back,
      createdAt: createdAt,
      due: due,
      type: type,
      options: options,
      correctText: correctText,
      blanks: blanks,
      dragPairs: dragPairs,
      variantChain: variantChain,
      variantLevel: variantLevel,
      variantBox: newBox,
      variantHistory: variantHistory,
      variantMissStreak: missStreak,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
    );
    return (card: updated, nextType: null);
  }

  /// Ersetzt Typ/Inhalt durch die nächste (schwerere) Eskalationsstufe -
  /// aufgerufen, nachdem [copyWithBoxUpdate] eine mögliche Beförderung
  /// signalisiert hat und der Aufrufer die neuen Inhalte per KI erzeugt hat.
  /// Sichert den bisherigen (leichteren) Inhalt in [variantHistory], bevor
  /// er überschrieben wird – Grundlage für eine spätere Rückstufung.
  Flashcard copyWithPromotedVariant({
    required QuestionType newType,
    required String front,
    String back = '',
    List<QuizOption>? options,
    String? correctText,
    List<String>? blanks,
    List<DragPair>? dragPairs,
  }) {
    final snapshot = VariantSnapshot(
      type: type,
      front: this.front,
      back: this.back,
      options: this.options,
      correctText: this.correctText,
      blanks: this.blanks,
      dragPairs: this.dragPairs,
    );
    return Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: front,
      back: back,
      createdAt: createdAt,
      due: due,
      type: newType,
      options: options,
      correctText: correctText,
      blanks: blanks,
      dragPairs: dragPairs,
      variantChain: variantChain,
      variantLevel: variantLevel + 1,
      variantBox: 0,
      variantHistory: [...?variantHistory, snapshot],
      variantMissStreak: 0,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
    );
  }

  /// Kehrt zur vorherigen (leichteren) Eskalationsstufe zurück, deren
  /// Inhalt bereits in [variantHistory] liegt – kein KI-Aufruf nötig. Ohne
  /// Historie (leere Liste) bleibt die Karte unverändert; der Aufrufer
  /// prüft das bereits über [copyWithBoxUpdate], diese Methode ist aber
  /// auch eigenständig sicher aufrufbar.
  Flashcard copyWithDemotedVariant() {
    final history = variantHistory;
    if (history == null || history.isEmpty) return this;
    final previous = history.last;
    final remaining = history.sublist(0, history.length - 1);
    return Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: previous.front,
      back: previous.back,
      createdAt: createdAt,
      due: due,
      type: previous.type,
      options: previous.options,
      correctText: previous.correctText,
      blanks: previous.blanks,
      dragPairs: previous.dragPairs,
      variantChain: variantChain,
      variantLevel: variantLevel - 1,
      variantBox: 0,
      variantHistory: remaining,
      variantMissStreak: 0,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
    );
  }

  /// Anzahl richtiger Antworten in Folge, ab der eine Frage mit
  /// [variantChain] in die nächste Stufe befördert wird.
  static const int promotionThreshold = 3;

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'conceptId': conceptId,
        'front': front,
        'back': back,
        'createdAt': createdAt.toIso8601String(),
        'due': due.toIso8601String(),
        'type': type.name,
        'options': options?.map((o) => o.toMap()).toList(),
        'correctText': correctText,
        'blanks': blanks,
        'dragPairs': dragPairs?.map((p) => p.toMap()).toList(),
        'variantChain': variantChain?.map((t) => t.name).toList(),
        'variantLevel': variantLevel,
        'variantBox': variantBox,
        'variantHistory': variantHistory?.map((v) => v.toMap()).toList(),
        'variantMissStreak': variantMissStreak,
        'stability': stability,
        'difficulty': difficulty,
        'elapsedDays': elapsedDays,
        'scheduledDays': scheduledDays,
        'reps': reps,
        'lapses': lapses,
        'state': state,
        'lastReview': lastReview?.toIso8601String(),
        'unitId': unitId,
      };

  factory Flashcard.fromMap(Map<String, dynamic> map) => Flashcard(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        conceptId: map['conceptId'] as String?,
        front: map['front'] as String,
        back: map['back'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        due: DateTime.parse(map['due'] as String),
        type: questionTypeFromString(map['type'] as String?),
        options: (map['options'] as List?)
            ?.map((o) => QuizOption.fromMap(Map<String, dynamic>.from(o as Map)))
            .toList(),
        correctText: map['correctText'] as String?,
        blanks: (map['blanks'] as List?)?.map((b) => b.toString()).toList(),
        dragPairs: (map['dragPairs'] as List?)
            ?.map((p) => DragPair.fromMap(Map<String, dynamic>.from(p as Map)))
            .toList(),
        variantChain:
            (map['variantChain'] as List?)?.map((t) => questionTypeFromString(t.toString())).toList(),
        variantLevel: map['variantLevel'] as int? ?? 0,
        variantBox: map['variantBox'] as int? ?? 0,
        variantHistory: (map['variantHistory'] as List?)
            ?.map((v) => VariantSnapshot.fromMap(Map<String, dynamic>.from(v as Map)))
            .toList(),
        variantMissStreak: map['variantMissStreak'] as int? ?? 0,
        stability: (map['stability'] as num).toDouble(),
        difficulty: (map['difficulty'] as num).toDouble(),
        elapsedDays: map['elapsedDays'] as int,
        scheduledDays: map['scheduledDays'] as int,
        reps: map['reps'] as int,
        lapses: map['lapses'] as int,
        state: map['state'] as String,
        lastReview: map['lastReview'] == null
            ? null
            : DateTime.parse(map['lastReview'] as String),
        unitId: map['unitId'] as String?,
      );
}
