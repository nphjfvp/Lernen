import '../models/flashcard.dart';
import 'ai_service.dart';
import 'pdf_question_import_service.dart';
import 'question_parsing.dart';

/// Legt aus einem Aufgabentext normale (nicht interaktive) Karten an – so wie
/// der Fragen-Import: die KI wählt die Aufgabenform (Freitext, Auswahl,
/// Zuordnen, Tabelle, Lernaufgabe mit Lösungsweg …). Genutzt von der
/// Sammelliste „Noch nicht interaktiv“ und beim „Aufgabe übernehmen“, wenn
/// eine Aufgabe besser als normale Frage passt.
class PlainQuestionService {
  PlainQuestionService._();

  static Future<List<Flashcard>> build(
    AiService ai, {
    required String text,
    required String moduleId,
    String? sourceMaterialId,
    int? sourcePage,
    String? unitId,
    DateTime? now,
  }) async {
    final raw = await ai.importQuestionsFromExercises(text);
    final questions = [
      for (final m in raw)
        if (QuestionParsing.normalizeGeneratedFlashcard(m) case final data?)
          ScannedQuestion(page: sourcePage ?? 0, data: data, solutionByAi: true),
    ];
    return PdfQuestionImportService.toFlashcards(
      questions,
      moduleId: moduleId,
      unitId: unitId,
      sourceMaterialId: sourceMaterialId,
      now: now ?? DateTime.now(),
    );
  }
}
