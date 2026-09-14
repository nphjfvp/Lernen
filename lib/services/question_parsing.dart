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

  static const _aiTypeAliases = {
    'flashcard': QuestionType.flashcard,
    'single_choice': QuestionType.singleChoice,
    'multiple_choice': QuestionType.multipleChoice,
    'free_text': QuestionType.freeText,
    'fill_blank': QuestionType.fillBlank,
    'drag_drop': QuestionType.dragDrop,
    'drag_category': QuestionType.dragCategory,
  };

  /// Wandelt den von der KI gelieferten "type"-String (snake_case, siehe
  /// AiService-Prompts, z.B. "single_choice") in [QuestionType] um.
  ///
  /// WICHTIG: bewusst NICHT dasselbe wie [questionTypeFromString] – jene
  /// Funktion vergleicht gegen die camelCase-Enum-Namen (`singleChoice`) wie
  /// sie intern für die DB-Persistierung (`Flashcard.toMap`/`fromMap`)
  /// verwendet werden. Ein von der KI/Crosscheck geliefertes JSON mit
  /// "single_choice" würde dort NIE matchen und still auf `flashcard`
  /// zurückfallen (der eigentliche Grund, warum früher scheinbar nur noch
  /// einfache Karteikarten ohne Rückseite erzeugt wurden) – deshalb hier
  /// eine eigene, für das KI-JSON-Format zuständige Zuordnung.
  static QuestionType parseType(String? value) => _aiTypeAliases[value] ?? QuestionType.flashcard;

  /// Prüft einen von der KI generierten Karteikarten-Eintrag auf
  /// Vollständigkeit für seinen deklarierten Typ und repariert ihn bei
  /// Bedarf: fehlen die für den Typ nötigen Felder, aber es lässt sich
  /// anderswo im Eintrag noch eine brauchbare Antwort finden (z.B. weil das
  /// Modell "correctText" statt "options" geliefert hat), wird der Eintrag
  /// als einfache Karteikarte (type: flashcard) gerettet statt verworfen.
  /// Nur wenn sich GAR keine Antwort finden lässt, wird `null` zurückgegeben
  /// (vom Aufrufer zu verwerfen) – so landen keine stummen
  /// "nur Vorderseite ohne Antwort"-Karten in der App.
  static Map<String, dynamic>? normalizeGeneratedFlashcard(Map<String, dynamic> raw) {
    final front = (raw['front'] ?? '').toString().trim();
    if (front.isEmpty) return null;

    final type = parseType(raw['type'] as String?);
    if (_isComplete(raw, type)) return raw;

    final fallbackAnswer = _bestAvailableAnswer(raw);
    if (fallbackAnswer == null) return null;
    return {'type': 'flashcard', 'front': front, 'back': fallbackAnswer};
  }

  static bool _isComplete(Map<String, dynamic> raw, QuestionType type) {
    switch (type) {
      case QuestionType.flashcard:
        return (raw['back'] ?? '').toString().trim().isNotEmpty;
      case QuestionType.singleChoice:
      case QuestionType.multipleChoice:
        final options = parseOptions(raw['options']);
        return options != null && options.isNotEmpty && options.any((o) => o.isCorrect);
      case QuestionType.fillBlank:
        final blanks = parseBlanks(raw['blanks']);
        return blanks != null && blanks.any((b) => b.trim().isNotEmpty);
      case QuestionType.freeText:
        return (raw['correctText'] ?? '').toString().trim().isNotEmpty;
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        final pairs = parseDragPairs(raw['dragPairs']);
        return pairs != null && pairs.isNotEmpty;
    }
  }

  static String? _bestAvailableAnswer(Map<String, dynamic> raw) {
    final back = (raw['back'] ?? '').toString().trim();
    if (back.isNotEmpty) return back;

    final correctText = (raw['correctText'] ?? '').toString().trim();
    if (correctText.isNotEmpty) return correctText;

    final blanks = parseBlanks(raw['blanks'])?.where((b) => b.trim().isNotEmpty).toList();
    if (blanks != null && blanks.isNotEmpty) return blanks.join(', ');

    final options = parseOptions(raw['options']);
    if (options != null) {
      final correct = options.where((o) => o.isCorrect).map((o) => o.text).where((t) => t.trim().isNotEmpty);
      if (correct.isNotEmpty) return correct.join(', ');
    }

    final pairs = parseDragPairs(raw['dragPairs']);
    if (pairs != null && pairs.isNotEmpty) {
      return pairs.map((p) => '${p.source} → ${p.target}').join(', ');
    }
    return null;
  }
}
