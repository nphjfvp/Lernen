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
  html,
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
        QuestionType.html => 'Interaktiv',
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
    this.htmlContent,
    this.imageBase64,
  });

  final QuestionType type;
  final String front;
  final String back;
  final List<QuizOption>? options;
  final String? correctText;
  final List<String>? blanks;
  final List<DragPair>? dragPairs;
  final String? htmlContent;
  final String? imageBase64;

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'front': front,
        'back': back,
        'options': options?.map((o) => o.toMap()).toList(),
        'correctText': correctText,
        'blanks': blanks,
        'dragPairs': dragPairs?.map((p) => p.toMap()).toList(),
        'htmlContent': htmlContent,
        'imageBase64': imageBase64,
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
        htmlContent: map['htmlContent'] as String?,
        imageBase64: map['imageBase64'] as String?,
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
/// (z.B. Single-Choice -> Lückentext -> Freitext): ist die aktuelle Stufe in
/// der Ampel grün, wird die Frage in den nächsten Typ der Kette umgewandelt
/// (Inhalt aus [pendingVariants] oder lazy per KI) und [variantLevel]
/// erhöht. Nach mehreren Fehlversuchen in Folge wird automatisch eine
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

  /// Selbstständige HTML/CSS/JS-Seite für [QuestionType.html] (siehe
  /// AiService-Prompts für den genauen Vertrag: die Seite prüft ihre eigene
  /// Antwort und meldet das Ergebnis über einen JavaScript-Kanal zurück,
  /// die App muss dafür nicht online sein). Nur auf Plattformen mit
  /// WebView-Unterstützung (Android/iOS) tatsächlich interaktiv gerendert;
  /// [front]/[back] dienen überall sonst (Windows/Web/Fehlerfall) als
  /// Fallback-Anzeige mit manueller Selbstbewertung wie beim einfachen
  /// `flashcard`-Typ (siehe QuestionAnswerView).
  final String? htmlContent;

  /// Base64-kodierter Screenshot der Vorlesungsseite, aus der diese Frage
  /// erzeugt wurde (siehe PageQuestionCreationSheet/
  /// AiService.generateQuestionsFromPage) – NICHT bei jeder Karte gesetzt,
  /// sondern nur, wenn das Vision-Modell die Seite selbst als "needsImage"
  /// markiert hat (z.B. ein Diagramm/eine Grafik, ohne die die Frage keinen
  /// Sinn ergibt) – rein textbasierte Fragen bekommen bewusst KEIN Bild
  /// angehängt, um die lokale Datenbank nicht unnötig aufzublähen. Wird in
  /// [QuestionAnswerView] oberhalb der Frage angezeigt, wenn gesetzt.
  final String? imageBase64;

  final List<QuestionType>? variantChain;
  final int variantLevel;

  /// Richtige Antworten in Folge auf der aktuellen Stufe (falsch: −1). Nur
  /// noch informativ – über die Beförderung entscheidet die Ampel
  /// ([masteryBox], siehe [copyWithBoxUpdate]).
  final int variantBox;

  /// Inhalt jeder bereits verlassenen, leichteren Eskalationsstufe, in der
  /// Reihenfolge, in der sie durchlaufen wurden (letzter Eintrag = zuletzt
  /// verlassene Stufe, direkt unter der aktuellen). Wird bei jeder
  /// Beförderung um einen Eintrag länger, bei jeder Rückstufung um einen
  /// kürzer.
  final List<VariantSnapshot>? variantHistory;

  /// Bereits vorbereiteter (aber noch nicht erreichter) Inhalt für die
  /// NÄCHSTEN Eskalationsstufen, in der Reihenfolge, in der sie als Nächstes
  /// erreicht werden (erster Eintrag = direkt nächste Stufe). Nur gesetzt,
  /// wenn der komplette Inhalt aller Stufen schon beim Erstellen bekannt war
  /// (siehe PageQuestionCreationSheet: EIN KI-Aufruf erzeugt dort direkt alle
  /// gewählten Schwierigkeitsgrade auf einmal, jeweils gegründet auf
  /// denselben Seiten-Screenshot). [copyWithBoxUpdate] nutzt diesen Inhalt
  /// dann bei einer Beförderung direkt, OHNE weiteren (schwächer
  /// gegründeten, nur textbasierten) KI-Aufruf wie sonst über
  /// AiService.generateHarderVariant. Wird bei einer Rückstufung
  /// ([copyWithDemotedVariant]) automatisch um die gerade verlassene Stufe
  /// ergänzt (Spiegelbild zu [variantHistory]), damit ein späteres
  /// Wiedererreichen erneut denselben, bereits bekannten Inhalt nutzt statt
  /// die KI erneut zu bemühen.
  final List<VariantSnapshot>? pendingVariants;

  /// Anzahl FALSCHER Antworten in Folge auf der aktuellen Eskalationsstufe
  /// (jede richtige Antwort setzt ihn auf 0 zurück) – getrennt von
  /// [variantBox] geführt, damit "Box ist gerade frisch auf 0, weil eben
  /// befördert wurde" nicht mit "zwei Fehlversuche in Folge" verwechselt
  /// wird. Erreicht er [demotionMissStreakThreshold], stuft
  /// [copyWithBoxUpdate] automatisch zurück.
  final int variantMissStreak;

  /// Generischer Leitner-Zähler für die Wissensstand-Ampel (siehe
  /// MasteryService), UNABHÄNGIG von [variantBox] (das ist rein für die
  /// Typ-Eskalationskette reserviert). Steigt bei jeder Antwort, die als
  /// "gewusst" zählt (FSRS-Grade good/easy) um 1 (Obergrenze
  /// [masteryBoxCap]), sinkt sonst um 1 (Boden 0) – siehe FsrsService.review.
  /// Grund: die reine FSRS-Retrievability ist direkt nach jeder Wiederholung
  /// per Definition ~100% (Vergessenskurve bei Elapsed-Zeit 0), zwei schnell
  /// aufeinanderfolgende (ggf. geratene) richtige Antworten würden sonst
  /// sofort als "Gut" (grün) durchgehen. Erst mehrere, tatsächlich über
  /// mehrere Sessions verteilte erfolgreiche Wiederholungen zählen als
  /// nachgewiesenes Wissen (analog zur "mature"-Einstufung der Vorgänger-App).
  final int masteryBox;

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
  /// DailyScheduler die Karte aus (siehe DailySchedulerService.buildPlan) –
  /// AUSSER [priorityIntroduction] ist gesetzt.
  final String? unitId;

  /// true für Karten, die der Nutzer gezielt JETZT beim Betrachten einer
  /// Seite selbst erstellt hat (siehe PageQuestionCreationSheet/"Frage
  /// erstellen"), statt aus einer Bulk-Generierung (Nachbereiten-Modus)
  /// hervorzugehen. Zwei Konsequenzen in [DailySchedulerService.buildPlan]:
  /// (1) umgeht das Einheiten-"behandelt"-Gate, das eigentlich verhindern
  /// soll, dass automatisch generierter Stoff künftiger (noch nicht
  /// gehaltener) Vorlesungen ungefragt im Daily Quiz auftaucht – eine
  /// einzelne, bewusst gerade jetzt gestellte Frage ist per Definition schon
  /// "aktuell relevant", unabhängig vom Einheiten-Status. (2) wird beim
  /// Auffüllen des Tages-Budgets VOR der reinen createdAt-Reihenfolge
  /// einsortiert, damit eine frisch erstellte Frage nicht hinter einem
  /// großen Altbestand noch nicht eingeführter Karten verschwindet und erst
  /// nach Tagen drankommt.
  final bool priorityIntroduction;

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
    this.htmlContent,
    this.imageBase64,
    this.variantChain,
    this.variantLevel = 0,
    this.variantBox = 0,
    this.variantHistory,
    this.pendingVariants,
    this.variantMissStreak = 0,
    this.masteryBox = 0,
    this.stability = 0,
    this.difficulty = 0,
    this.elapsedDays = 0,
    this.scheduledDays = 0,
    this.reps = 0,
    this.lapses = 0,
    this.state = 'new',
    this.lastReview,
    this.unitId,
    this.priorityIntroduction = false,
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
        // Die Antwort-Prüfung steckt in htmlContent selbst (siehe dort) -
        // back dient hier nur als textuelle Kurzfassung/Fallback-Anzeige.
        QuestionType.html => back,
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
    int? masteryBox,
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
      htmlContent: htmlContent,
      imageBase64: imageBase64,
      variantChain: variantChain,
      variantLevel: variantLevel,
      variantBox: variantBox,
      variantHistory: variantHistory,
      pendingVariants: pendingVariants,
      variantMissStreak: variantMissStreak,
      masteryBox: masteryBox ?? this.masteryBox,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
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
      htmlContent: htmlContent,
      imageBase64: imageBase64,
      variantChain: variantChain,
      variantLevel: variantLevel,
      variantBox: variantBox,
      variantHistory: variantHistory,
      pendingVariants: pendingVariants,
      variantMissStreak: variantMissStreak,
      masteryBox: masteryBox,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
    );
  }

  /// Ab wie vielen FALSCHEN Antworten in Folge auf derselben Eskalationsstufe
  /// [copyWithBoxUpdate] automatisch zurückstuft (siehe [variantMissStreak]).
  /// Gilt für alle Stufen AUSSER der schwersten (siehe
  /// [demotionMissStreakThresholdOnLastStage]).
  static const int demotionMissStreakThreshold = 2;

  /// Ab wie vielen FALSCHEN Antworten in Folge auf der SCHWERSTEN Stufe der
  /// Kette automatisch zurückgestuft wird – bewusst deutlich höher als
  /// [demotionMissStreakThreshold]: diese Stufe gilt als bereits nachgewiesen
  /// gut gelernt (die Ampel stand hier grün, siehe MasteryService) und wird
  /// durch normale Spaced-Repetition ohnehin nur noch selten wiederholt – ein
  /// einzelner Ausrutscher soll sie nicht sofort zurückwerfen, erst
  /// mehrfaches Vergessen in Folge.
  static const int demotionMissStreakThresholdOnLastStage = 5;

  /// Nach einer Antwort: Eskalationsstufe fortschreiben – in BEIDE
  /// Richtungen. Ist die aktuelle Stufe grün ([masteryBox] am Cap) und eine
  /// nächste Stufe in [variantChain] vorhanden, wird befördert: liegt ihr Inhalt
  /// bereits fertig in [pendingVariants] vor (siehe dort), passiert das
  /// SOFORT, ohne KI-Aufruf ([needsGeneration] = false). Andernfalls wird nur
  /// die Box zurückgesetzt und die Ziel-Stufe über [nextType] signalisiert
  /// ([needsGeneration] = true) – das eigentliche Umwandeln (KI-Aufruf)
  /// übernimmt dann der Aufrufer, damit dieses Modell frei von I/O bleibt.
  /// Umgekehrt: erreicht [variantMissStreak] (Fehlversuche IN FOLGE auf
  /// dieser Stufe) die passende Schwelle ([demotionMissStreakThreshold] bzw.
  /// [demotionMissStreakThresholdOnLastStage] auf der schwersten Stufe), wird
  /// sofort zur vorherigen, leichteren Stufe zurückgestuft (siehe
  /// [copyWithDemotedVariant]) – dafür ist KEIN weiterer KI-Aufruf nötig, der
  /// alte Wortlaut liegt bereits in [variantHistory].
  ({Flashcard card, QuestionType? nextType, bool needsGeneration}) copyWithBoxUpdate({required bool isCorrect}) {
    final chain = variantChain;
    // Befördert wird, sobald die aktuelle Stufe grün ist: masteryBox am Cap
    // heißt an [masteryBoxCap] verschiedenen Tagen richtig beantwortet
    // (siehe FsrsService.review) – "3 richtig in Folge" war dagegen in einer
    // einzigen Übungsrunde erreichbar. Aufrufer wenden FsrsService.review
    // VOR dieser Methode an, masteryBox enthält die aktuelle Antwort also
    // schon.
    final canPromote =
        chain != null && variantLevel < chain.length - 1 && masteryBox >= Flashcard.masteryBoxCap && isCorrect;
    if (canPromote) {
      final pending = pendingVariants;
      if (pending != null && pending.isNotEmpty) {
        final promoted = copyWithPromotedVariantFromPending();
        return (card: promoted, nextType: promoted.type, needsGeneration: false);
      }
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
        htmlContent: htmlContent,
        imageBase64: imageBase64,
        variantChain: chain,
        variantLevel: variantLevel,
        variantBox: 0,
        variantHistory: variantHistory,
        pendingVariants: pendingVariants,
        variantMissStreak: 0,
        masteryBox: masteryBox,
        stability: stability,
        difficulty: difficulty,
        elapsedDays: elapsedDays,
        scheduledDays: scheduledDays,
        reps: reps,
        lapses: lapses,
        state: state,
        lastReview: lastReview,
        unitId: unitId,
        priorityIntroduction: priorityIntroduction,
      );
      return (card: updated, nextType: chain[variantLevel + 1], needsGeneration: true);
    }

    final missStreak = isCorrect ? 0 : variantMissStreak + 1;
    final isOnLastStage = chain != null && variantLevel >= chain.length - 1;
    final effectiveDemotionThreshold =
        isOnLastStage ? demotionMissStreakThresholdOnLastStage : demotionMissStreakThreshold;
    final canDemote = !isCorrect &&
        variantLevel > 0 &&
        missStreak >= effectiveDemotionThreshold &&
        (variantHistory?.isNotEmpty ?? false);
    if (canDemote) {
      final demoted = copyWithDemotedVariant(
        // Gibt beim Rückfall von der schwersten Stufe einen Vertrauens-
        // vorschuss (gelb statt rot/leer) – die Karte war ja nachgewiesen
        // gut gelernt, ein Rückfall soll nicht komplett bei Null anfangen.
        masteryBoxOverride: isOnLastStage ? Flashcard.masteryBoxCap - 1 : null,
      );
      return (card: demoted, nextType: null, needsGeneration: false);
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
      htmlContent: htmlContent,
      imageBase64: imageBase64,
      variantChain: variantChain,
      variantLevel: variantLevel,
      variantBox: newBox,
      variantHistory: variantHistory,
      pendingVariants: pendingVariants,
      variantMissStreak: missStreak,
      masteryBox: masteryBox,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
    );
    return (card: updated, nextType: null, needsGeneration: false);
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
    String? htmlContent,
    String? imageBase64,
    List<VariantSnapshot>? pendingVariants,
  }) {
    final snapshot = VariantSnapshot(
      type: type,
      front: this.front,
      back: this.back,
      options: this.options,
      correctText: this.correctText,
      blanks: this.blanks,
      dragPairs: this.dragPairs,
      htmlContent: this.htmlContent,
      imageBase64: this.imageBase64,
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
      htmlContent: htmlContent,
      imageBase64: imageBase64,
      variantChain: variantChain,
      variantLevel: variantLevel + 1,
      variantBox: 0,
      variantHistory: [...?variantHistory, snapshot],
      pendingVariants: pendingVariants ?? this.pendingVariants,
      variantMissStreak: 0,
      masteryBox: masteryBox,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
    );
  }

  /// Wie [copyWithPromotedVariant], nutzt aber den bereits vorbereiteten
  /// Inhalt der nächsten Stufe aus [pendingVariants] statt Parametern des
  /// Aufrufers – KEIN KI-Aufruf nötig (siehe Doc-Kommentar dort). Nur
  /// sinnvoll aufzurufen, wenn [pendingVariants] nicht leer ist;
  /// [copyWithBoxUpdate] prüft das bereits, diese Methode ist aber auch
  /// eigenständig sicher aufrufbar (ohne Wirkung, wenn nichts vorbereitet ist).
  Flashcard copyWithPromotedVariantFromPending() {
    final pending = pendingVariants;
    if (pending == null || pending.isEmpty) return this;
    final next = pending.first;
    final remaining = pending.sublist(1);
    return copyWithPromotedVariant(
      newType: next.type,
      front: next.front,
      back: next.back,
      options: next.options,
      correctText: next.correctText,
      blanks: next.blanks,
      dragPairs: next.dragPairs,
      htmlContent: next.htmlContent,
      imageBase64: next.imageBase64,
      pendingVariants: remaining,
    );
  }

  /// Kehrt zur vorherigen (leichteren) Eskalationsstufe zurück, deren
  /// Inhalt bereits in [variantHistory] liegt – kein KI-Aufruf nötig. Ohne
  /// Historie (leere Liste) bleibt die Karte unverändert; der Aufrufer
  /// prüft das bereits über [copyWithBoxUpdate], diese Methode ist aber
  /// auch eigenständig sicher aufrufbar. Die gerade verlassene (schwerere)
  /// Stufe wandert dabei in [pendingVariants] (Spiegelbild zu
  /// [variantHistory]) – wird sie später erneut erreicht, steht ihr Inhalt
  /// sofort wieder zur Verfügung, ohne erneuten KI-Aufruf.
  /// [masteryBoxOverride] setzt bei Bedarf einen abweichenden Ampel-Stand
  /// (siehe [copyWithBoxUpdate]: ein Rückfall von der schwersten Stufe
  /// bekommt einen Vertrauensvorschuss statt bei Null anzufangen).
  Flashcard copyWithDemotedVariant({int? masteryBoxOverride}) {
    final history = variantHistory;
    if (history == null || history.isEmpty) return this;
    final previous = history.last;
    final remaining = history.sublist(0, history.length - 1);
    final vacated = VariantSnapshot(
      type: type,
      front: front,
      back: back,
      options: options,
      correctText: correctText,
      blanks: blanks,
      dragPairs: dragPairs,
      htmlContent: htmlContent,
      imageBase64: imageBase64,
    );
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
      htmlContent: previous.htmlContent,
      imageBase64: previous.imageBase64,
      variantChain: variantChain,
      variantLevel: variantLevel - 1,
      variantBox: 0,
      variantHistory: remaining,
      pendingVariants: [vacated, ...?pendingVariants],
      variantMissStreak: 0,
      masteryBox: masteryBoxOverride ?? masteryBox,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
    );
  }

  /// Obergrenze für [masteryBox] – ab hier zählt eine Karte für die Ampel
  /// als nachgewiesen gut gelernt (siehe MasteryService), weiteres Wachstum
  /// bringt keinen zusätzlichen Nutzen mehr.
  static const int masteryBoxCap = 4;

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
        'htmlContent': htmlContent,
        'imageBase64': imageBase64,
        'variantChain': variantChain?.map((t) => t.name).toList(),
        'variantLevel': variantLevel,
        'variantBox': variantBox,
        'variantHistory': variantHistory?.map((v) => v.toMap()).toList(),
        'pendingVariants': pendingVariants?.map((v) => v.toMap()).toList(),
        'variantMissStreak': variantMissStreak,
        'masteryBox': masteryBox,
        'stability': stability,
        'difficulty': difficulty,
        'elapsedDays': elapsedDays,
        'scheduledDays': scheduledDays,
        'reps': reps,
        'lapses': lapses,
        'state': state,
        'lastReview': lastReview?.toIso8601String(),
        'unitId': unitId,
        'priorityIntroduction': priorityIntroduction,
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
        htmlContent: map['htmlContent'] as String?,
        imageBase64: map['imageBase64'] as String?,
        variantChain:
            (map['variantChain'] as List?)?.map((t) => questionTypeFromString(t.toString())).toList(),
        variantLevel: map['variantLevel'] as int? ?? 0,
        variantBox: map['variantBox'] as int? ?? 0,
        variantHistory: (map['variantHistory'] as List?)
            ?.map((v) => VariantSnapshot.fromMap(Map<String, dynamic>.from(v as Map)))
            .toList(),
        pendingVariants: (map['pendingVariants'] as List?)
            ?.map((v) => VariantSnapshot.fromMap(Map<String, dynamic>.from(v as Map)))
            .toList(),
        variantMissStreak: map['variantMissStreak'] as int? ?? 0,
        masteryBox: map['masteryBox'] as int? ?? 0,
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
        priorityIntroduction: map['priorityIntroduction'] as bool? ?? false,
      );
}
