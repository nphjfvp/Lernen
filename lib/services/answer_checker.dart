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

  /// Die Lücken, die tatsächlich eine Lösung haben – eine leere Lösung wäre
  /// nie zu treffen und machte die ganze Frage unlösbar.
  static List<String> solvableBlanks(Flashcard q) =>
      (q.blanks ?? const []).where((b) => b.trim().isNotEmpty).toList();

  /// [answers] in derselben Reihenfolge wie [solvableBlanks].
  static AnswerCheckResult checkFillBlank(Flashcard q, List<String> answers) =>
      fillBlankResult(q, fillBlankHits(q, answers));

  /// Je Lücke (Reihenfolge wie [solvableBlanks]), ob die Eingabe lokal
  /// passt – exakt, mit kleinem Tippfehler oder als eine der per ";"
  /// hinterlegten Varianten.
  static List<bool> fillBlankHits(Flashcard q, List<String> answers) {
    final blanks = solvableBlanks(q);
    return [
      for (var i = 0; i < blanks.length; i++) i < answers.length && answerMatches(answers[i], blanks[i]),
    ];
  }

  /// Gesamtergebnis aus den Treffern je Lücke – lokal ([fillBlankHits]) oder
  /// nach der KI-Zweitmeinung (siehe QuestionAnswerView).
  static AnswerCheckResult fillBlankResult(Flashcard q, List<bool> hits) {
    final blanks = solvableBlanks(q);
    return AnswerCheckResult(
      isCorrect: blanks.isNotEmpty && hits.length == blanks.length && hits.every((h) => h),
      correctAnswerLabel: blanks.map(solutionLabel).join(' | '),
    );
  }

  /// Eine Lösung zum Anzeigen: mehrere akzeptierte Varianten ("a; b")
  /// als "a / b".
  static String solutionLabel(String solution) =>
      solution.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).join(' / ');

  /// Ob [answer] einer der Varianten von [correct] genau entspricht (bis auf
  /// Groß-/Kleinschreibung und Leerzeichen) – anders als [answerMatches]
  /// ohne Tippfehler-Toleranz. Zeigt an, ob die hinterlegte Schreibweise
  /// noch einmal eingeblendet werden sollte.
  static bool answerExactlyMatches(String answer, String correct) {
    final a = _normalize(answer);
    return a.isNotEmpty && correct.split(';').map(_normalize).any((c) => c == a);
  }

  /// Begriffe/Ziele mit Inhalt – leere Einträge ließen sich nicht sinnvoll
  /// ziehen bzw. treffen.
  static List<DragPair> usableDragPairs(Flashcard q) => [
        for (final p in q.dragPairs ?? const <DragPair>[])
          if (p.source.trim().isNotEmpty && p.target.trim().isNotEmpty) p,
      ];

  /// Eine Zuordnen-Frage, bei der mehrere Begriffe zum selben Ziel gehören
  /// (die KI schreibt dann dasselbe Ziel mehrfach), ist in Wahrheit eine
  /// Kategorien-Frage – so wird sie angezeigt und geprüft, sonst ließen
  /// sich die gleichnamigen Ziele nicht unterscheiden.
  static bool isCategoryDrag(Flashcard q) {
    if (q.type == QuestionType.dragCategory) return true;
    if (q.type != QuestionType.dragDrop) return false;
    final targets = usableDragPairs(q).map((p) => p.target.trim()).toList();
    return targets.toSet().length < targets.length;
  }

  /// Die Kategorien einer Kategorien-Frage in der Reihenfolge ihres ersten
  /// Auftretens.
  static List<String> dragCategories(Flashcard q) {
    final seen = <String>{};
    return [
      for (final p in usableDragPairs(q))
        if (seen.add(p.target.trim())) p.target.trim(),
    ];
  }

  /// Zuordnen: ob auf Ziel [zone] (Index in [usableDragPairs]) der richtige
  /// Begriff liegt – [source] ist der Index des abgelegten Begriffs. Gleich
  /// lautende Begriffe sind austauschbar, deshalb zählt der Text.
  static bool dragZoneCorrect(Flashcard q, int zone, int? source) {
    final pairs = usableDragPairs(q);
    if (source == null || zone < 0 || zone >= pairs.length || source < 0 || source >= pairs.length) {
      return false;
    }
    return pairs[source].source.trim() == pairs[zone].source.trim();
  }

  /// Zuordnen: [zoneToSource] – für jedes Ziel (Index in [usableDragPairs])
  /// der Index des dort abgelegten Begriffs.
  static AnswerCheckResult checkDragDrop(Flashcard q, Map<int, int> zoneToSource) {
    final pairs = usableDragPairs(q);
    if (pairs.isEmpty) return const AnswerCheckResult(isCorrect: false, correctAnswerLabel: '');
    var hits = 0;
    for (var zone = 0; zone < pairs.length; zone++) {
      if (dragZoneCorrect(q, zone, zoneToSource[zone])) hits++;
    }
    return AnswerCheckResult(
      isCorrect: hits == pairs.length,
      correctAnswerLabel: pairs.map((p) => '${p.source} → ${p.target}').join(', '),
    );
  }

  /// Kategorien: welche abgelegten Begriffe (Indizes in [usableDragPairs])
  /// richtig liegen. Gleich lautende Begriffe werden gegen die erwarteten
  /// Paare verrechnet – jedes erwartete Paar zählt nur einmal.
  static Set<int> correctCategoryPlacements(Flashcard q, Map<int, String> sourceToCategory) {
    final pairs = usableDragPairs(q);
    String key(String source, String category) => '${source.trim()}\u0000${category.trim()}';
    final remaining = <String, int>{};
    for (final p in pairs) {
      remaining.update(key(p.source, p.target), (n) => n + 1, ifAbsent: () => 1);
    }
    final correct = <int>{};
    final placed = sourceToCategory.keys.toList()..sort();
    for (final source in placed) {
      if (source < 0 || source >= pairs.length) continue;
      final k = key(pairs[source].source, sourceToCategory[source]!);
      final left = remaining[k] ?? 0;
      if (left > 0) {
        remaining[k] = left - 1;
        correct.add(source);
      }
    }
    return correct;
  }

  /// Kategorien: [sourceToCategory] – für jeden Begriff (Index in
  /// [usableDragPairs]) die gewählte Kategorie. Richtig, wenn jeder Begriff
  /// in seiner Kategorie liegt.
  static AnswerCheckResult checkDragCategory(Flashcard q, Map<int, String> sourceToCategory) {
    final pairs = usableDragPairs(q);
    if (pairs.isEmpty) return const AnswerCheckResult(isCorrect: false, correctAnswerLabel: '');
    final correct = correctCategoryPlacements(q, sourceToCategory);
    return AnswerCheckResult(
      isCorrect: correct.length == pairs.length,
      correctAnswerLabel: [
        for (final category in dragCategories(q))
          '$category: ${pairs.where((p) => p.target.trim() == category).map((p) => p.source).join(', ')}',
      ].join(' · '),
    );
  }

  /// Ob sich die Frage in ihrem Typ überhaupt beantworten lässt. Karten mit
  /// kaputten Daten (keine richtige Option, leere Lösung, keine Paare …)
  /// zeigt die Oberfläche stattdessen als Karteikarte zum Selbstbewerten, statt
  /// sie unlösbar – und damit immer falsch – abzufragen.
  static bool isAnswerable(Flashcard q) {
    switch (q.type) {
      case QuestionType.flashcard:
      case QuestionType.html:
        return true;
      case QuestionType.singleChoice:
      case QuestionType.multipleChoice:
        final options = q.options ?? const [];
        return options.length >= 2 && options.any((o) => o.isCorrect);
      case QuestionType.freeText:
        return (q.correctText ?? '').split(';').any((c) => c.trim().isNotEmpty);
      case QuestionType.fillBlank:
        return solvableBlanks(q).isNotEmpty;
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        return usableDragPairs(q).isNotEmpty;
    }
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
