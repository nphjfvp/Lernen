import '../models/flashcard.dart';
import '../models/unlock_block.dart';
import 'ai_service.dart';
import 'pdf_question_import_service.dart';
import 'question_parsing.dart';

/// Aus einer Aufgabe eines Entsperr-Blocks eine lösbare Karte: Mathe als
/// Rechenweg (Schritt für Schritt oder selbst rechnen – getippt oder mit Stift,
/// jede Zeile nachgerechnet, Taschenrechner, Vorrechnen an der Tafel), andere
/// Fächer in der passenden Frageart; notfalls Freitext, den die KI bewertet.
Future<Flashcard> buildUnlockCard(AiService ai, UnlockBlock block, int index, {DateTime? now}) async {
  final task = block.tasks[index];
  final when = now ?? DateTime.now();
  final id = 'unlock-${block.id}-$index-${task.problem.hashCode.toUnsigned(32)}';
  final reference = [
    if (task.solution.trim().isNotEmpty) task.solution.trim(),
    if (task.answer.trim().isNotEmpty) 'Ergebnis: ${task.answer.trim()}',
  ].join('\n\n');
  final drafts = await ai.buildInteractiveTasks(text: task.problem, solution: reference, allowEmpty: true);
  final draft = drafts.isEmpty ? null : drafts.first;
  if (draft != null && draft.kind != null && draft.isUsable) {
    return Flashcard(
      id: id,
      moduleId: block.moduleId,
      front: draft.front.trim().isEmpty ? task.problem : draft.front.trim(),
      back: draft.back.trim().isEmpty ? reference : draft.back.trim(),
      createdAt: when,
      due: when,
      type: draft.kind!.type,
      taskData: draft.taskData,
    );
  }
  final data = draft?.questionData;
  if (draft != null && draft.asQuestion && data != null) {
    final normalized = QuestionParsing.normalizeGeneratedFlashcard({
      ...data,
      if ('${data['front'] ?? ''}'.trim().isEmpty) 'front': task.problem,
    });
    if (normalized != null) {
      return PdfQuestionImportService.toFlashcards(
        [ScannedQuestion(page: 0, data: normalized, solutionByAi: false)],
        moduleId: block.moduleId,
        now: when,
      ).single;
    }
  }
  return Flashcard(
    id: id,
    moduleId: block.moduleId,
    front: task.problem,
    back: reference,
    correctText: task.answer.trim().isEmpty ? reference : task.answer.trim(),
    createdAt: when,
    due: when,
    type: QuestionType.freeText,
  );
}
