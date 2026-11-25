import '../models/flashcard.dart';
import 'ai_service.dart';
import 'answer_checker.dart';
import 'question_parsing.dart';

/// Wiederholen in neuer Form: Eine eben falsch beantwortete Karte kommt in der
/// Wiederholungsrunde nicht wortgleich wieder (die Antwort steckt dann noch
/// im Kurzzeitgedächtnis), sondern als neu eingekleidete Fassung – gleiches
/// Wissen, andere Situation bzw. Zahlen (siehe AiService.generateRetryVariant).
///
/// Die Fassung ist nur ein Schnappschuss für diese eine Anzeige: dieselbe
/// ID, derselbe Lernstand, nichts davon wird gespeichert. Die Antwort zählt
/// für die gespeicherte Originalkarte (CardReviewMixin.recordReview lädt sie
/// per ID).
class RetryVariantService {
  RetryVariantService._();

  /// Fragetypen, die sich ohne Bild sinnvoll neu einkleiden lassen.
  static const supportedTypes = {
    QuestionType.singleChoice,
    QuestionType.multipleChoice,
    QuestionType.freeText,
    QuestionType.fillBlank,
    QuestionType.flashcard,
  };

  /// Bildfragen bleiben, wie sie sind: das Bild gehört zur Frage.
  static bool supports(Flashcard card) =>
      supportedTypes.contains(card.type) &&
      (card.imageBase64 ?? '').isEmpty &&
      (card.imageTargets?.isEmpty ?? true);

  /// Baut aus der KI-Antwort die neue Fassung – oder null, wenn sie nicht
  /// taugt (anderer Typ, wortgleich, nicht beantwortbar). Ungeprüfte
  /// KI-Ausgabe läuft wie jede KI-Frage durch die Normalisierung.
  static Flashcard? apply(Flashcard original, Map<String, dynamic> json) {
    final fixed = QuestionParsing.normalizeGeneratedFlashcard({
      ...json,
      'type': QuestionParsing.aiTypeName(original.type),
    });
    if (fixed == null) return null;
    if (QuestionParsing.parseType(fixed['type'] as String?) != original.type) return null;
    final front = (fixed['front'] ?? '').toString().trim();
    if (front.isEmpty || front == original.front.trim()) return null;
    final variant = original.copyWithContent(
      front: front,
      back: (fixed['back'] ?? '').toString(),
      options: QuestionParsing.parseOptions(fixed['options']),
      correctText: fixed['correctText'] as String?,
      blanks: QuestionParsing.parseBlanks(fixed['blanks']),
    );
    if (original.type == QuestionType.flashcard && variant.back.trim().isEmpty) return null;
    return AnswerChecker.isAnswerable(variant) ? variant : null;
  }

  /// Erzeugt die neue Fassung per KI; bei jedem Fehler null (dann kommt die
  /// Karte einfach wortgleich wieder).
  static Future<Flashcard?> generate(AiService ai, Flashcard card) async {
    if (!supports(card)) return null;
    try {
      final answer = card.answerSummary.isNotEmpty ? card.answerSummary : card.back;
      final json = await ai.generateRetryVariant(questionText: card.promptText, currentAnswer: answer, type: card.type);
      return apply(card, json);
    } catch (_) {
      return null;
    }
  }
}
