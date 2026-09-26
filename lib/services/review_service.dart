import '../models/flashcard.dart';
import 'ai_service.dart';
import 'fsrs_service.dart';
import 'question_parsing.dart';

/// Was eine Antwort an der Schwierigkeits-Eskalationskette einer Karte
/// verändert hat (siehe [Flashcard.copyWithBoxUpdate]).
enum LevelChange {
  /// Keine Auf- oder Abstufung.
  none,

  /// Sofort befördert – der Inhalt der nächsten Stufe lag bereits vor
  /// (siehe [Flashcard.pendingVariants]).
  promoted,

  /// Beförderung fällig, der Inhalt der nächsten Stufe muss aber erst per KI
  /// erzeugt werden (siehe [ReviewService.generatePromotion]).
  promotionPending,

  /// Nach wiederholten Fehlversuchen auf die leichtere Stufe zurückgestuft.
  demoted,
}

/// Ergebnis von [ReviewService.evaluate]: der neue Kartenstand plus alles,
/// was die Oberfläche daraus ableitet (Feedback, Wiederholungsrunde,
/// Hintergrund-Beförderung).
class ReviewOutcome {
  const ReviewOutcome({
    required this.card,
    required this.wasWrong,
    this.levelChange = LevelChange.none,
    this.targetType,
    this.cardDeleted = false,
  });

  /// Der fertig fortgeschriebene Datensatz – so zu speichern.
  final Flashcard card;

  /// true, wenn die Karte inzwischen gelöscht war und die Antwort deshalb
  /// nicht gespeichert wurde (siehe CardReviewMixin.recordReview) – sie
  /// gehört dann auch in keine Wiederholungsrunde mehr.
  final bool cardDeleted;

  /// true, wenn die Antwort als "nicht gewusst" zählt: eine automatisch
  /// geprüfte Frage falsch beantwortet oder eine offene Karte selbst mit
  /// "Nochmal" bewertet. Grundlage für die Wiederholungsrunde im Daily Quiz.
  final bool wasWrong;

  final LevelChange levelChange;

  /// Bei [LevelChange.promoted]/[LevelChange.promotionPending] der Typ der
  /// nächsten Stufe, bei [LevelChange.demoted] der Typ der Stufe, auf die
  /// zurückgestuft wurde.
  final QuestionType? targetType;

  bool get needsGeneration => levelChange == LevelChange.promotionPending;

  /// Kurze Rückmeldung für eine SnackBar, oder null ohne Stufenwechsel.
  String? get levelChangeMessage => switch (levelChange) {
        LevelChange.none => null,
        LevelChange.promoted => '⬆️ Stufe geschafft – jetzt: ${targetType?.label}',
        LevelChange.promotionPending => '⬆️ Stufe geschafft – nächstes Mal: ${targetType?.label}',
        LevelChange.demoted => '⬇️ Zurück zu: ${targetType?.label}',
      };
}

/// Verbucht eine Antwort auf eine Karte – EINE Stelle für Daily Quiz, Üben
/// und Sprint, damit alle Modi dieselben Regeln für FSRS, Ampel
/// (masteryBox) und Schwierigkeits-Eskalation anwenden. Rein, ohne I/O:
/// Speichern und die KI-Erzeugung einer neuen Stufe übernimmt der Aufrufer
/// (siehe CardReviewMixin).
class ReviewService {
  ReviewService({FsrsService? fsrs}) : _fsrs = fsrs ?? FsrsService();

  final FsrsService _fsrs;

  /// [selfGrade] für eine offene Karteikarte (selbst bewertet), [isCorrect]
  /// für einen automatisch geprüften Fragetyp. Beides zusammen heißt: richtig,
  /// aber nur mit Tipp (siehe QuestionAnswerView) – die Bewertung folgt dann
  /// [selfGrade], und die Eskalationskette bleibt unberührt (mit Hilfe
  /// gelöst ist weder ein Grund zum Aufsteigen noch zum Absteigen).
  ///
  /// [allowLevelChange] false lässt die Eskalationskette ebenfalls in Ruhe –
  /// für eine Antwort auf eine Stufe, die inzwischen nicht mehr gespeichert
  /// ist (die Karte wurde währenddessen befördert oder zurückgestuft).
  ReviewOutcome evaluate(
    Flashcard card, {
    Grade? selfGrade,
    bool? isCorrect,
    DateTime? now,
    bool allowLevelChange = true,
  }) {
    assert(selfGrade != null || isCorrect != null, 'selfGrade oder isCorrect muss gesetzt sein');
    final at = now ?? DateTime.now();
    final grade = selfGrade ?? _fsrs.gradeFromResult(isCorrect!);
    final wasWrong = isCorrect == false || selfGrade == Grade.again;
    // Ein erneuter Fehlversuch am selben Tag (Wiederholungsrunde, Üben)
    // zählt auch für die Rückstufung nicht noch einmal – sonst stufen zwei
    // Fehler innerhalb weniger Minuten zurück, während der Aufstieg vier
    // verschiedene Lerntage braucht (siehe FsrsService.isRepeatFailureToday).
    final repeatFailure = FsrsService.isRepeatFailureToday(card, grade, at);
    var updated = _fsrs.review(card, grade, now: at);

    // Die Eskalationskette gibt es nur bei automatisch geprüften Typen, und
    // nur für Antworten ohne Hilfe.
    if (isCorrect == null ||
        selfGrade != null ||
        updated.variantChain == null ||
        !allowLevelChange ||
        repeatFailure) {
      return ReviewOutcome(card: updated, wasWrong: wasWrong);
    }

    final beforeLevel = updated.variantLevel;
    final boxResult = updated.copyWithBoxUpdate(isCorrect: isCorrect);
    updated = boxResult.card;
    final nextType = boxResult.nextType;
    final LevelChange change;
    QuestionType? target;
    if (nextType != null) {
      change = boxResult.needsGeneration ? LevelChange.promotionPending : LevelChange.promoted;
      target = nextType;
      if (change == LevelChange.promoted) updated = _fsrs.restartForNewStage(updated, now: at);
    } else if (updated.variantLevel < beforeLevel) {
      change = LevelChange.demoted;
      target = updated.type;
    } else {
      change = LevelChange.none;
    }
    return ReviewOutcome(card: updated, wasWrong: wasWrong, levelChange: change, targetType: target);
  }

  /// Holt per KI den Inhalt der nächsten (schwereren) Stufe. Wirft bei
  /// KI-Fehlern – der Aufrufer entscheidet, ob er das still schluckt (die
  /// Karte bleibt dann auf ihrer Stufe, der nächste richtige Versuch
  /// probiert es erneut).
  static Future<Map<String, dynamic>> fetchPromotionContent(
    AiService ai,
    Flashcard card,
    QuestionType nextType,
  ) {
    return ai.generateHarderVariant(
      questionText: card.front,
      currentAnswer: card.answerSummary,
      targetType: nextType,
    );
  }

  /// Wendet per KI erzeugten Stufen-Inhalt auf [card] an und startet die
  /// neue Stufe neu (siehe FsrsService.restartForNewStage). Der Inhalt wird
  /// wie jede KI-Frage geprüft (QuestionParsing.normalizeGeneratedFlashcard):
  /// eine unvollständige oder nur noch als Karteikarte rettbare Stufe wäre
  /// unlösbar bzw. keine echte Steigerung und bliebe über Rück- und
  /// Wiederbeförderung dauerhaft in der Karte hängen – dann wirft diese
  /// Methode ([FormatException]), die Karte bleibt auf ihrer Stufe und der
  /// nächste richtige Versuch probiert es erneut. Das Bild einer Karte
  /// (Diagramm o.ä.) gilt für denselben Fakt weiter.
  static Flashcard applyPromotion(
    Flashcard card,
    QuestionType nextType,
    Map<String, dynamic> result, {
    DateTime? now,
  }) {
    final fixed = QuestionParsing.normalizeGeneratedFlashcard({
      ...result,
      'front': (result['front'] ?? card.front).toString(),
      'type': QuestionParsing.aiTypeName(nextType),
    });
    final type = fixed == null ? null : QuestionParsing.parseType(fixed['type'] as String?);
    if (fixed == null || (type == QuestionType.flashcard && nextType != QuestionType.flashcard)) {
      throw const FormatException('Die KI hat keine brauchbare nächste Stufe geliefert.');
    }
    final promoted = card.copyWithPromotedVariant(
      newType: type!,
      front: (fixed['front'] ?? card.front).toString(),
      back: (fixed['back'] ?? '').toString(),
      options: QuestionParsing.parseOptions(fixed['options']),
      correctText: fixed['correctText'] as String?,
      blanks: QuestionParsing.parseBlanks(fixed['blanks']),
      dragPairs: QuestionParsing.parseDragPairs(fixed['dragPairs']),
      imageBase64: card.imageBase64,
    );
    return FsrsService().restartForNewStage(promoted, now: now);
  }

  static Future<Flashcard> generatePromotion(
    AiService ai,
    Flashcard card,
    QuestionType nextType, {
    DateTime? now,
  }) async {
    return applyPromotion(card, nextType, await fetchPromotionContent(ai, card, nextType), now: now);
  }
}
