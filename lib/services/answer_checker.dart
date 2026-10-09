import 'dart:math' as math;

import '../models/bom_task.dart';
import '../models/phase_task.dart';
import '../models/crystal_task.dart';
import '../models/sketch_task.dart';
import '../models/flashcard.dart';
import '../models/gantt_task.dart';
import '../models/step_task.dart';
import 'crystal_geometry.dart';

/// Ergebnis einer automatischen Antwortprüfung.
class AnswerCheckResult {
  const AnswerCheckResult({required this.isCorrect, required this.correctAnswerLabel});

  final bool isCorrect;

  /// Die richtige Antwort als lesbarer Text, für die Anzeige nach dem
  /// Beantworten (z.B. "Paris" oder "Hund -> Tier, Rose -> Pflanze").
  final String correctAnswerLabel;
}

/// Bild beschriften, je Stelle: ob sie stimmt und welche Beschriftungen dort
/// richtig (gewesen) wären – bei austauschbaren Stellen die noch offenen der
/// Gruppe, sonst genau eine.
typedef LabelZoneResult = ({bool correct, List<String> allowed});

/// Prüft eine Nutzer-Antwort automatisch gegen die hinterlegte Lösung, je
/// nach Fragetyp – reine Logik, keine Seiteneffekte. Portiert aus der
/// Vorgänger-App (quiz-engine.js), inklusive der Tippfehlertoleranz für
/// Freitext-/Lückentext-Antworten (kleine Fehler sollen nicht als falsch
/// zählen). Den Formel-Fragetyp (math_formula) der Vorgänger-App gibt es
/// hier bewusst nicht.
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

  /// Bild beschriften: die Stellen mit Beschriftung, in Ziel-Reihenfolge
  /// (Nummern 1..n in der Anzeige).
  static List<ImageTarget> labelTargets(Flashcard q) => [
        for (final t in q.imageTargets ?? const <ImageTarget>[])
          if (t.label.trim().isNotEmpty) t,
      ];

  /// Kleinste Größe eines Markier-Bereichs – ein Punkt ohne Ausdehnung wäre
  /// kaum zu treffen.
  static const minRegionSide = 0.08;

  /// Bild markieren: die Bereiche, in die getippt werden muss.
  static List<ImageTarget> markRegions(Flashcard q) => [
        for (final t in q.imageTargets ?? const <ImageTarget>[])
          t.copyWith(w: math.max(t.w, minRegionSide), h: math.max(t.h, minRegionSide)),
      ];

  static bool _hasImage(Flashcard q) => (q.imageBase64 ?? '').isNotEmpty;

  /// Bild beschriften: wertet die Antworten je Stelle aus ([answers]: Index
  /// in [labelTargets] -> Text). Stellen derselben [ImageTarget.group] sind
  /// austauschbar – jede Beschriftung der Gruppe zählt auf jeder ihrer
  /// Stellen, aber nur einmal. Gleich lautende Beschriftungen sind ohnehin
  /// austauschbar (es zählt der Text). [tolerant] (beim Eintippen) lässt
  /// kleine Tippfehler gelten, sonst zählt der genaue Text (Zuordnen).
  /// Liefert je Stelle, ob sie stimmt und was dort richtig gewesen wäre.
  static List<LabelZoneResult> diagramLabelZones(Flashcard q, Map<int, String> answers, {bool tolerant = false}) {
    final targets = labelTargets(q);
    final results = List<LabelZoneResult>.generate(
      targets.length,
      (i) => (correct: false, allowed: [targets[i].label.trim()]),
    );
    // Gruppen: benannte Gruppe oder jede Stelle für sich.
    final groups = <String, List<int>>{};
    for (var i = 0; i < targets.length; i++) {
      final group = targets[i].group.trim();
      groups.putIfAbsent(group.isEmpty ? '\u0000$i' : group, () => []).add(i);
    }
    for (final zones in groups.values) {
      final open = [for (final z in zones) targets[z].label.trim()];
      final pending = [...zones];
      // Erst genaue Treffer vergeben, dann (beim Eintippen) Tippfehler – so
      // nimmt ein ungenauer Treffer keinem genauen die Beschriftung weg.
      for (final exact in [true, if (tolerant) false]) {
        for (final zone in [...pending]) {
          final answer = answers[zone] ?? '';
          final hit = open.indexWhere(
              (label) => exact ? answerExactlyMatches(answer, label) : answerMatches(answer, label));
          if (hit < 0) continue;
          results[zone] = (correct: true, allowed: [open[hit]]);
          open.removeAt(hit);
          pending.remove(zone);
        }
      }
      // Was an den falschen Stellen richtig gewesen wäre: bei einer Gruppe
      // eine der noch offenen Beschriftungen.
      for (final zone in pending) {
        if (zones.length > 1) results[zone] = (correct: false, allowed: List.of(open));
      }
    }
    return results;
  }

  /// "1 = Zellkern, 2 = Mitochondrium" – die Nummern der Stellen im Bild;
  /// austauschbare Stellen zusammen: "3/4 = Eingang, Ausgang (beliebig)".
  static String diagramLabelSolution(Flashcard q) {
    final targets = labelTargets(q);
    final parts = <String>[];
    final seenGroups = <String>{};
    for (var i = 0; i < targets.length; i++) {
      final group = targets[i].group.trim();
      if (group.isEmpty) {
        parts.add('${i + 1} = ${targets[i].label}');
        continue;
      }
      if (!seenGroups.add(group)) continue;
      final members = [
        for (var j = 0; j < targets.length; j++)
          if (targets[j].group.trim() == group) j,
      ];
      if (members.length == 1) {
        parts.add('${i + 1} = ${targets[i].label}');
      } else {
        parts.add('${members.map((m) => m + 1).join('/')} = '
            '${members.map((m) => targets[m].label).join(', ')} (beliebige Reihenfolge)');
      }
    }
    return parts.join(', ');
  }

  /// Bild beschriften per Zuordnen: [zoneToLabel] – für jede Stelle (Index
  /// in [labelTargets]) der Index der dort abgelegten Beschriftung.
  static AnswerCheckResult checkDiagramLabel(Flashcard q, Map<int, int> zoneToLabel) {
    final targets = labelTargets(q);
    return checkDiagramLabelTexts(q, {
      for (final e in zoneToLabel.entries)
        if (e.value >= 0 && e.value < targets.length) e.key: targets[e.value].label,
    });
  }

  /// Bild beschriften mit Text je Stelle; [tolerant] fürs Eintippen.
  static AnswerCheckResult checkDiagramLabelTexts(Flashcard q, Map<int, String> answers, {bool tolerant = false}) {
    final zones = diagramLabelZones(q, answers, tolerant: tolerant);
    return AnswerCheckResult(
      isCorrect: zones.isNotEmpty && zones.every((z) => z.correct),
      correctAnswerLabel: diagramLabelSolution(q),
    );
  }

  /// Bild markieren: richtig, wenn der Tipp ([x]/[y] relativ zum Bild) in
  /// einem der Bereiche liegt.
  static AnswerCheckResult checkMarkImage(Flashcard q, double? x, double? y) {
    final hit = x != null && y != null && markRegions(q).any((r) => r.contains(x, y));
    return AnswerCheckResult(isCorrect: hit, correctAnswerLabel: q.answerSummary);
  }

  /// Die auszufüllenden Zellen einer Tabellen-Frage (Zeile, Spalte, Lösung)
  /// – ohne leere Lösungen, die nie zu treffen wären.
  static List<({int row, int col, String solution})> tableBlanks(Flashcard q) => [
        for (var r = 0; r < (q.tableRows ?? const []).length; r++)
          for (var c = 0; c < q.tableRows![r].length; c++)
            if (!q.tableRows![r][c].given && q.tableRows![r][c].text.trim().isNotEmpty)
              (row: r, col: c, solution: q.tableRows![r][c].text),
      ];

  /// Ab diesem Anteil richtiger Zellen zählt eine Tabelle als "fast
  /// richtig": kein Fehler, aber die Ampel steigt nicht (wie mit Tipp).
  static const double tablePartialShare = 0.8;

  /// Je auszufüllender Zelle (Reihenfolge wie [tableBlanks]), ob die Eingabe
  /// passt – mit Tippfehler-Toleranz und per ";" hinterlegten Varianten.
  static List<bool> tableHits(Flashcard q, List<String> answers) {
    final blanks = tableBlanks(q);
    return [
      for (var i = 0; i < blanks.length; i++) i < answers.length && answerMatches(answers[i], blanks[i].solution),
    ];
  }

  /// Ergebnis einer Tabelle: [isCorrect] nur bei allen Zellen richtig,
  /// [partial] bei mindestens [tablePartialShare] (dann als "Schwer" zu
  /// verbuchen), [share] der Anteil richtiger Zellen.
  static ({AnswerCheckResult result, bool partial, double share}) tableResult(Flashcard q, List<bool> hits) {
    final blanks = tableBlanks(q);
    final right = hits.where((h) => h).length;
    final share = blanks.isEmpty ? 0.0 : right / blanks.length;
    final all = blanks.isNotEmpty && right == blanks.length;
    return (
      result: AnswerCheckResult(
        isCorrect: all,
        correctAnswerLabel: blanks.map((b) => solutionLabel(b.solution)).join(' | '),
      ),
      partial: !all && share >= tablePartialShare,
      share: share,
    );
  }

  /// Eine Zuordnen-/Kategorien-Frage, die man nicht falsch machen kann: nur
  /// ein Paar oder alle Begriffe gehören zum selben (einzigen) Ziel. Sie wird
  /// stattdessen als Karteikarte abgefragt (siehe [isAnswerable]) – dann
  /// muss man die Zuordnung selbst wissen.
  static bool isTrivialDrag(Flashcard q) {
    final pairs = usableDragPairs(q);
    final targets = {for (final p in pairs) p.target.trim().toLowerCase()};
    return pairs.length < 2 || targets.length < 2;
  }

  /// Ob sich die Frage in ihrem Typ überhaupt beantworten lässt. Karten mit
  /// kaputten Daten (keine richtige Option, leere Lösung, keine Paare …)
  /// zeigt die Oberfläche stattdessen als Karteikarte zum Selbstbewerten, statt
  /// sie unlösbar – und damit immer falsch – abzufragen.
  static bool isAnswerable(Flashcard q) {
    switch (q.type) {
      case QuestionType.flashcard:
      case QuestionType.learn:
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
        return !isTrivialDrag(q);
      case QuestionType.diagramLabel:
        return _hasImage(q) && labelTargets(q).isNotEmpty;
      case QuestionType.markImage:
        return _hasImage(q) && markRegions(q).isNotEmpty;
      case QuestionType.table:
        return tableBlanks(q).isNotEmpty;
      case QuestionType.steps:
        return StepTask.fromMap(q.taskData)?.isUsable ?? false;
      case QuestionType.gantt:
        return GanttTask.fromMap(q.taskData) != null;
      case QuestionType.crystal:
        final crystal = CrystalTask.fromMap(q.taskData);
        return crystal != null && CrystalGeometry.playable(crystal);
      case QuestionType.bom:
        return BomTask.fromMap(q.taskData)?.isUsable ?? false;
      case QuestionType.sketch:
        return SketchTask.fromMap(q.taskData)?.isUsable ?? false;
      case QuestionType.phase:
        return PhaseTask.fromMap(q.taskData)?.isUsable ?? false;
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
      if (a == c || _isTypo(a, c)) return true;
    }
    return false;
  }

  /// Kleiner Tippfehler statt einer anderen Antwort: bis 1 Zeichen ab 5,
  /// bis 2 ab 9 Zeichen Abweichung. Nie bei Zahlen (eine andere Ziffer ist
  /// ein anderes Ergebnis) und nie, wenn nur eine Vorsilbe fehlt oder
  /// dazukommt ("homogen"/"inhomogen", "reversibel"/"irreversibel" – das
  /// dreht die Bedeutung um).
  static bool _isTypo(String a, String c) {
    final allowed = c.length >= 9 ? 2 : (c.length >= 5 ? 1 : 0);
    if (allowed == 0) return false;
    if (_digits(a) != _digits(c)) return false;
    if (a.endsWith(c) || c.endsWith(a)) return false;
    return _levenshtein(a, c) <= allowed;
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// Vergleichsform: klein, einfache Leerzeichen, ohne Satzzeichen am Rand;
  /// Dezimalpunkt wie Dezimalkomma ("3.5" = "3,5").
  static String _normalize(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'(?<=\d)\.(?=\d)'), ',')
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
