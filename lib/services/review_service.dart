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
  });

  /// Der fertig fortgeschriebene Datensatz – so zu speichern.
  final Flashcard card;

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

  /// Genau eines von [selfGrade] (offene Karteikarte, selbst bewertet) oder
  /// [isCorrect] (automatisch geprüfter Fragetyp) ist gesetzt.
  ReviewOutcome evaluate(Flashcard card, {Grade? selfGrade, bool? isCorrect, DateTime? now}) {
    assert(selfGrade != null || isCorrect != null, 'selfGrade oder isCorrect muss gesetzt sein');
    final grade = selfGrade ?? _fsrs.gradeFromResult(isCorrect!);
    final wasWrong = isCorrect == false || selfGrade == Grade.again;
    var updated = _fsrs.review(card, grade, now: now);

    // Die Eskalationskette gibt es nur bei automatisch geprüften Typen.
    if (isCorrect == null || updated.variantChain == null) {
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
      if (change == LevelChange.promoted) updated = _fsrs.restartForNewStage(updated, now: now);
    } else if (updated.variantLevel < beforeLevel) {
      change = LevelChange.demoted;
      target = updated.type;
    } else {
      change = LevelChange.none;
    }
    return ReviewOutcome(card: updated, wasWrong: wasWrong, levelChange: change, targetType: target);
  }

  /// Erzeugt per KI den Inhalt der nächsten (schwereren) Stufe und liefert
  /// die beförderte, auf der neuen Stufe neu gestartete Karte zurück (siehe
  /// FsrsService.restartForNewStage). Wirft bei KI-Fehlern – der Aufrufer
  /// entscheidet, ob er das still schluckt (die Karte bleibt dann auf ihrer
  /// Stufe, der nächste richtige Versuch probiert es erneut).
  static Future<Flashcard> generatePromotion(
    AiService ai,
    Flashcard card,
    QuestionType nextType, {
    DateTime? now,
  }) async {
    final result = await ai.generateHarderVariant(
      questionText: card.front,
      currentAnswer: card.answerSummary,
      targetType: nextType,
    );
    final promoted = card.copyWithPromotedVariant(
      newType: nextType,
      front: (result['front'] ?? card.front).toString(),
      back: (result['back'] ?? '').toString(),
      options: QuestionParsing.parseOptions(result['options']),
      correctText: result['correctText']?.toString(),
      blanks: QuestionParsing.parseBlanks(result['blanks']),
      dragPairs: QuestionParsing.parseDragPairs(result['dragPairs']),
    );
    return FsrsService().restartForNewStage(promoted, now: now);
  }
}
