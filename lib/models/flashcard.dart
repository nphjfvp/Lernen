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
/// [variantLevel] erhöht. `null` bedeutet: kein Eskalations-Typ, die Frage
/// bleibt dauerhaft in ihrem [type].
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

  /// Nach einer Antwort: Leitner-Box fortschreiben (rein für die
  /// Varianten-Eskalation, unabhängig vom FSRS-Zustand). Erreicht die Box
  /// die "grüne" Schwelle und ist eine nächste Stufe in [variantChain]
  /// vorhanden, wird das über die zurückgegebene [nextType] signalisiert -
  /// das eigentliche Umwandeln (KI-Aufruf) übernimmt der Aufrufer, damit
  /// dieses Modell frei von I/O bleibt.
  ({Flashcard card, QuestionType? nextType}) copyWithBoxUpdate({required bool isCorrect}) {
    final newBox = isCorrect ? variantBox + 1 : (variantBox - 1).clamp(0, 999);
    final chain = variantChain;
    final canPromote = chain != null &&
        variantLevel < chain.length - 1 &&
        newBox >= Flashcard.promotionThreshold;

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
      variantBox: canPromote ? 0 : newBox,
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
    return (card: updated, nextType: canPromote ? chain[variantLevel + 1] : null);
  }

  /// Ersetzt Typ/Inhalt durch die nächste (schwerere) Eskalationsstufe -
  /// aufgerufen, nachdem [copyWithBoxUpdate] eine mögliche Beförderung
  /// signalisiert hat und der Aufrufer die neuen Inhalte per KI erzeugt hat.
  Flashcard copyWithPromotedVariant({
    required QuestionType newType,
    required String front,
    String back = '',
    List<QuizOption>? options,
    String? correctText,
    List<String>? blanks,
    List<DragPair>? dragPairs,
  }) {
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
