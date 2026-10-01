import '../models/flashcard.dart';

/// Erkennt Rechenaufgaben – Karten, für die man einen Taschenrechner bzw.
/// echtes Rechnen braucht (nicht "2 + 3"). Grundlage für den Schalter
/// "Rechenaufgaben" in Daily Quiz, Üben und Sprint.
///
/// Vorrang hat [Flashcard.needsCalculator] (von der KI beim Erstellen gesetzt
/// oder von Hand festgelegt). Ohne diese Angabe entscheidet der Text: eine
/// Rechenaufforderung ("Berechne", "Bestimme den Wert", "Wie groß ist …") oder
/// eine Zahl mit Einheit als Lösung, dazu mehrere echte Größen in der Aufgabe
/// (Zahlen mit Einheit, Kommazahlen, Zehnerpotenzen, mehrstellige Zahlen).
/// Einstellige Zahlen ohne Einheit zählen nicht – "Was ist 2 + 3?" ist keine
/// Rechenaufgabe in diesem Sinn.
class CalcTaskDetector {
  CalcTaskDetector._();

  static bool isCalcTask(Flashcard card) => card.needsCalculator ?? looksLikeCalc(card);

  static final _cue = RegExp(
    r'(berechne|berechnen|berechnet|berechnung|errechne|ausrechn|rechne |rechnen sie|bestimme[n]? (sie )?(den|die|das) (wert|betrag|größe)|'
    r'ermittle|ermitteln sie|wie groß (ist|sind|wird)|wie viel (beträgt|ist)|wie hoch (ist|wird)|welche[nrs]? (wert|spannung|strom|leistung|kraft|energie|frequenz|widerstand|geschwindigkeit|masse|temperatur|druck)|'
    r'calculate|compute|determine the value)',
    caseSensitive: false,
  );

  static const _units = r'(?:m|k|M|G|µ|u|n|p)?(?:A|V|Ω|Ohm|W|Wh|Hz|s|F|H|T|Wb|C|J|N|Pa|bar|K|°C|°|m|g|l|L|mol|rad|VA|var|S)'
      r'|cm|mm|km|kg|mg|min|h|%|‰|dB|m/s|km/h|m²|m³|cm²|mm²|kWh|°';

  /// Eine Größe im Text: Zahl (mit Komma/Punkt, ggf. Zehnerpotenz) und optional Einheit.
  static final _quantity = RegExp(
    r'(?<![A-Za-z_\d])(-?\d+(?:[.,]\d+)?)(\s*(?:·|\*|x|×)\s*10\^?\{?\(?[-−]?\d+\)?\}?|[eE][-+]?\d+)?\s*(' + _units + r')?(?![A-Za-z\d])',
  );

  static final _numericAnswer = RegExp(
    r'^[\s≈~=]*[-−]?\d+(?:[.,]\d+)?(?:\s*(?:·|\*|x|×)\s*10\^?\{?\(?[-−]?\d+\)?\}?|[eE][-+]?\d+)?\s*[A-Za-zΩµ°%/²³·\s]{0,12}$',
  );

  /// Wie viele echte Größen [text] nennt (siehe Klassenkommentar).
  static int quantityCount(String text) {
    var n = 0;
    for (final m in _quantity.allMatches(text.replaceAll('−', '-'))) {
      final number = m.group(1)!;
      final power = m.group(2) != null;
      final unit = m.group(3) != null;
      final decimal = number.contains(',') || number.contains('.');
      final digits = number.replaceAll(RegExp(r'[^0-9]'), '').length;
      if (unit || power || decimal || digits >= 2) n++;
    }
    return n;
  }

  /// Ob [text] eine Zahl (mit Einheit) als Lösung ist.
  static bool isNumericAnswer(String text) {
    final t = text.trim().replaceAll(RegExp(r'\$'), '');
    return t.isNotEmpty && _numericAnswer.hasMatch(t);
  }

  static bool looksLikeCalc(Flashcard card) {
    final question = card.promptText;
    final cue = _cue.hasMatch(question);
    final quantities = quantityCount(question);
    final answers = switch (card.type) {
      QuestionType.fillBlank => card.blanks ?? const <String>[],
      QuestionType.singleChoice || QuestionType.multipleChoice => [
          for (final o in card.options ?? const <QuizOption>[])
            if (o.isCorrect) o.text,
        ],
      _ => [card.answerSummary],
    };
    final numericAnswer = answers.isNotEmpty && answers.every(isNumericAnswer);
    if (cue && quantities >= 2) return true;
    if (numericAnswer && quantities >= 2) return true;
    if (cue && numericAnswer && quantities >= 1) return true;
    return false;
  }
}
