import '../models/flashcard.dart';

/// Gemeinsame Parsing-Hilfen für von der KI generierte Fragen-JSON-Objekte
/// (siehe AiService.generateConceptsAndFlashcards / generateHarderVariant) –
/// wird sowohl beim initialen Erstellen (ReviewScreen) als auch bei der
/// Schwierigkeits-Eskalation (DailyQuizScreen) gebraucht.
class QuestionParsing {
  QuestionParsing._();

  static List<QuizOption>? parseOptions(dynamic raw) {
    final list = raw as List?;
    if (list == null) return null;
    return list.map((o) => QuizOption.fromMap(Map<String, dynamic>.from(o as Map))).toList();
  }

  static List<String>? parseBlanks(dynamic raw) {
    final list = raw as List?;
    return list?.map((b) => b.toString()).toList();
  }

  static List<DragPair>? parseDragPairs(dynamic raw) {
    final list = raw as List?;
    if (list == null) return null;
    return list.map((p) => DragPair.fromMap(Map<String, dynamic>.from(p as Map))).toList();
  }

  /// Kette für die Schwierigkeits-Eskalation "einfach -> mittel -> schwer"
  /// (Single-Choice -> Lückentext -> Freitext) – wird gesetzt, wenn die KI
  /// eine Single-Choice-Frage explizit mit `"escalate": true` markiert hat.
  static const escalationChain = [
    QuestionType.singleChoice,
    QuestionType.fillBlank,
    QuestionType.freeText,
  ];
}
