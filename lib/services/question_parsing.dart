import '../models/flashcard.dart';
import 'html_question_contract.dart';

/// Gemeinsame Parsing-Hilfen für von der KI generierte Fragen-JSON-Objekte
/// (siehe AiService.generateConceptsAndFlashcards / generateHarderVariant) –
/// wird sowohl beim initialen Erstellen (ReviewScreen) als auch bei der
/// Schwierigkeits-Eskalation (DailyQuizScreen) gebraucht.
class QuestionParsing {
  QuestionParsing._();

  // Die parse*-Funktionen verarbeiten ungeprüfte KI-Ausgabe: ein einzelnes
  // abweichend geformtes Element (Option als reiner String, "isCorrect":
  // "true", fehlendes Feld) darf nicht per TypeError die gesamte
  // Generierung abbrechen – unbrauchbare Elemente werden übersprungen,
  // [normalizeGeneratedFlashcard] entscheidet danach über Rettung/Verwerfen.

  static List<QuizOption>? parseOptions(dynamic raw) {
    if (raw is! List) return null;
    final options = <QuizOption>[];
    for (final o in raw) {
      if (o is Map) {
        final text = o['text'];
        if (text == null) continue;
        final isCorrect = o['isCorrect'];
        options.add(QuizOption(
          text: text.toString(),
          isCorrect: isCorrect == true || isCorrect == 1 || const {'true', '1'}.contains(isCorrect.toString().toLowerCase()),
        ));
      } else if (o != null) {
        options.add(QuizOption(text: o.toString(), isCorrect: false));
      }
    }
    return options;
  }

  static List<String>? parseBlanks(dynamic raw) {
    if (raw is! List) return null;
    return raw.where((b) => b != null).map((b) => b.toString()).toList();
  }

  static List<DragPair>? parseDragPairs(dynamic raw) {
    if (raw is! List) return null;
    return [
      for (final p in raw)
        if (p is Map && p['source'] != null && p['target'] != null)
          DragPair(source: p['source'].toString(), target: p['target'].toString()),
    ];
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
    'html': QuestionType.html,
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

    final type = parseType(raw['type']?.toString());
    if (_isComplete(raw, type)) return _withStringFields(raw);

    final fallbackAnswer = _bestAvailableAnswer(raw);
    if (fallbackAnswer == null) return null;
    return {
      'type': 'flashcard',
      'front': front,
      'back': fallbackAnswer,
      if (raw['conceptTitle'] != null) 'conceptTitle': raw['conceptTitle'],
    };
  }

  /// Aufrufer lesen diese Felder per `as String?` – eine Zahl oder ein Bool
  /// von der KI (z.B. `"correctText": 42`) würde dort sonst crashen.
  static Map<String, dynamic> _withStringFields(Map<String, dynamic> raw) => {
        ...raw,
        for (final key in const ['type', 'front', 'back', 'correctText', 'htmlContent', 'conceptTitle'])
          if (raw[key] != null && raw[key] is! String) key: raw[key].toString(),
      };

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
      case QuestionType.html:
        final html = (raw['htmlContent'] ?? '').toString();
        // Grobe Vertragsprüfung: die Seite muss den JS-Rückkanal tatsächlich
        // ansprechen, sonst bekäme die App nie ein Ergebnis zurück – ohne
        // brauchbaren Fallback-Inhalt (siehe _bestAvailableAnswer) wird ein
        // solcher Eintrag dann komplett verworfen statt als kaputte
        // interaktive Seite gespeichert zu werden.
        return html.trim().isNotEmpty && html.contains(htmlAnswerChannelName);
    }
  }

  /// Ordnet eine von der KI mitgelieferte "conceptTitle" (siehe
  /// AiService.generateConceptsAndFlashcards) der ID des passenden, gerade
  /// neu gespeicherten Konzepts zu – Grundlage für [Flashcard.conceptId].
  /// [conceptIdByTitle] erwartet bereits normalisierte Schlüssel (siehe
  /// Aufrufer in ReviewScreen). Case-/Whitespace-tolerant, da die KI den
  /// Titel nicht immer exakt wiederholt. Liefert `null`, wenn kein Titel
  /// angegeben wurde oder keiner passt – die Karte bleibt dann wie bisher
  /// ohne Konzept-Verknüpfung, statt einen Fehler zu werfen.
  static String? matchConceptId(String? conceptTitle, Map<String, String> conceptIdByTitle) {
    final normalized = conceptTitle?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    return conceptIdByTitle[normalized];
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
