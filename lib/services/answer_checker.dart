import 'dart:math' as math;

import '../models/flashcard.dart';

/// Ergebnis einer automatischen Antwortprüfung.
class AnswerCheckResult {
  const AnswerCheckResult({required this.isCorrect, required this.correctAnswerLabel});

  final bool isCorrect;

  /// Die richtige Antwort als lesbarer Text, für die Anzeige nach dem
  /// Beantworten (z.B. "Paris" oder "Hund -> Tier, Rose -> Pflanze").
  final String correctAnswerLabel;
}

/// Prüft eine Nutzer-Antwort automatisch gegen die hinterlegte Lösung, je
/// nach Fragetyp – reine Logik, keine Seiteneffekte. Portiert aus der
/// Vorgänger-App (quiz-engine.js), inklusive der Tippfehlertoleranz für
/// Freitext-/Lückentext-Antworten (kleine Fehler sollen nicht als falsch
/// zählen). Deckt bewusst nur die Typen ab, die diese App unterstützt –
/// math_formula, diagram_label und mark_image aus der Vorgänger-App fehlen
/// hier absichtlich.
class AnswerChecker {
  AnswerChecker._();

  /// Jede als richtig markierte Option zählt – die UI hebt nach dem Prüfen
  /// ebenfalls ALLE `isCorrect`-Optionen grün hervor; markiert die KI bei
  /// einer Single-Choice-Frage versehentlich zwei Optionen als richtig, darf
  /// die grün angezeigte Wahl nicht als falsch gewertet werden.
  static AnswerCheckResult checkSingleChoice(Flashcard q, int? selectedIndex) {
    final options = q.options ?? const [];
    final ok = selectedIndex != null &&
        selectedIndex >= 0 &&
        selectedIndex < options.length &&
        options[selectedIndex].isCorrect;
    return AnswerCheckResult(
      isCorrect: ok,
      correctAnswerLabel: options.where((o) => o.isCorrect).map((o) => o.text).join(', '),
    );
  }

  static AnswerCheckResult checkMultipleChoice(Flashcard q, Set<int> selectedIndices) {
    final options = q.options ?? const [];
    final correctSet = <int>{
      for (var i = 0; i < options.length; i++)
        if (options[i].isCorrect) i,
    };
    final ok = correctSet.length == selectedIndices.length && correctSet.containsAll(selectedIndices);
    return AnswerCheckResult(
      isCorrect: ok,
      correctAnswerLabel: correctSet.map((i) => options[i].text).join(', '),
    );
  }

  static AnswerCheckResult checkFreeText(Flashcard q, String answer) {
    final ok = answerMatches(answer, q.correctText ?? '');
    return AnswerCheckResult(isCorrect: ok, correctAnswerLabel: q.correctText ?? '');
  }

  /// [answers] in derselben Reihenfolge wie [Flashcard.blanks].
  static AnswerCheckResult checkFillBlank(Flashcard q, List<String> answers) {
    final blanks = q.blanks ?? const [];
    if (blanks.isEmpty) return const AnswerCheckResult(isCorrect: false, correctAnswerLabel: '');
    var hits = 0;
    for (var i = 0; i < blanks.length && i < answers.length; i++) {
      if (answerMatches(answers[i], blanks[i])) hits++;
    }
    return AnswerCheckResult(isCorrect: hits == blanks.length, correctAnswerLabel: blanks.join(' | '));
  }

  /// [targetToSource]: für jedes Ziel (Zuordnungspunkt), welcher Begriff
  /// dort abgelegt wurde.
  static AnswerCheckResult checkDragDrop(Flashcard q, Map<String, String> targetToSource) {
    final pairs = q.dragPairs ?? const [];
    if (pairs.isEmpty) return const AnswerCheckResult(isCorrect: false, correctAnswerLabel: '');
    final hits = pairs.where((p) => targetToSource[p.target] == p.source).length;
    return AnswerCheckResult(
      isCorrect: hits == pairs.length,
      correctAnswerLabel: pairs.map((p) => '${p.source} → ${p.target}').join(', '),
    );
  }

  /// [sourceToTarget]: für jeden Begriff, welcher Kategorie er zugeordnet
  /// wurde.
  static AnswerCheckResult checkDragCategory(Flashcard q, Map<String, String> sourceToTarget) {
    final pairs = q.dragPairs ?? const [];
    if (pairs.isEmpty) return const AnswerCheckResult(isCorrect: false, correctAnswerLabel: '');
    final hits = pairs.where((p) => sourceToTarget[p.source] == p.target).length;
    return AnswerCheckResult(
      isCorrect: hits == pairs.length,
      correctAnswerLabel: pairs.map((p) => '${p.source} → ${p.target}').join(', '),
    );
  }

  /// Vergleicht eine Antwort gegen eine Lösung (mehrere durch ';' getrennte
  /// Varianten möglich) – toleriert kleine Tippfehler (Levenshtein-Distanz 1
  /// ab 5 Zeichen Länge, 2 ab 9 Zeichen), analog zur Vorgänger-App.
  static bool answerMatches(String answer, String correct) {
    final a = _normalize(answer);
    if (a.isEmpty) return false;
    final candidates = correct.split(';').map(_normalize).where((c) => c.isNotEmpty);
    for (final c in candidates) {
      if (a == c) return true;
      final allowed = c.length >= 9 ? 2 : (c.length >= 5 ? 1 : 0);
      if (allowed > 0 && _levenshtein(a, c) <= allowed) return true;
    }
    return false;
  }

  static String _normalize(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[.,;:!?]+|[.,;:!?]+$'), '');

  static int _levenshtein(String a, String b) {
    final m = a.length;
    final n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    var prev = List<int>.generate(n + 1, (i) => i);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
      }
      prev = cur;
    }
    return prev[n];
  }
}
