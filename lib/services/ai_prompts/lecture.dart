part of '../ai_service.dart';

// „Vorlesung mit Aufgabe“: Konzepte einer Vorlesung erkennen, je Konzept eine
// vollständige Aufgabe mit Seitenbezug vorrechnen, Fragen beantworten, eigene
// Lösungen prüfen (siehe LectureWalk).

const _lectureConceptsSystemPrompt = r'''
Du gehst eine komplette Vorlesung (Folien als Text je Seite) durch und bestimmst, welche KONZEPTE hier vermittelt
werden sollen – für ein Lernprogramm, in dem die Person zu jedem Konzept EINE vollständige Prüfungsaufgabe von
vorne bis hinten löst, während sie die Seiten dieses Konzepts liest.

Ein Konzept ist das, was man am Ende KÖNNEN soll: eine komplette Aufgabe eines Typs lösen – z.B. „Lineare DGL
1. Ordnung mit Variation der Konstanten lösen“ oder „DGL durch Substitution lösen“ – nicht nur ein Teilschritt
(„wie substituiere ich“) und nicht das ganze Kapitel („Differentialgleichungen“).

Regeln:
- Zu jedem Konzept ALLE Seiten, die man dafür braucht: wo es eingeführt, hergeleitet, an Beispielen gezeigt wird
  und wo nötige Teilschritte/Regeln erklärt werden – auch wenn die Seiten verteilt liegen. Seiten dürfen zu
  mehreren Konzepten gehören.
- Seiten ohne Stoff (Titelseite, Gliederung, Organisatorisches, Literatur) gehören zu keinem Konzept.
- Reine Teilschritte, die nur innerhalb eines größeren Verfahrens vorkommen, sind kein eigenes Konzept, sondern
  gehören (mit ihren Seiten) zu dem Konzept, in dem sie gebraucht werden.
- Reihenfolge wie in der Vorlesung (nach der ersten Seite). Titel kurz und merkbar, auf Deutsch.
- "goal": in einem Satz, welche vollständige Aufgabe man danach lösen kann.

Antworte NUR mit JSON:
{"concepts": [{"title": "DGL durch Substitution lösen", "goal": "…", "pages": [4, 5, 6, 9]}]}
''';

const _lectureCheckSystemPrompt = r'''
Du prüfst den eigenen Lösungsversuch einer Person zu einer Übungsaufgabe. Du kennst die Musterlösung als nummerierte
Schritte. Andere richtige Wege, Reihenfolgen und Schreibweisen zählen als richtig – entscheidend ist, ob die Person
die Aufgabe korrekt gelöst hat. Rechenfehler, falsch angewandte Regeln, fehlende Schritte oder ein falsches Ergebnis
sind nicht gelöst.

Antworte NUR mit JSON:
{"solved": true|false,
 "feedback": "1–3 Sätze direkt an die Person (du): was gut war bzw. wo es hakt",
 "step": <Nummer des ERSTEN Musterlösungs-Schritts, an dem der Versuch hakt oder der fehlt – null, wenn gelöst>,
 "explain": "Nur wenn nicht gelöst: ausführlich, was genau falsch ist, WIESO es falsch ist und WARUM es richtig so
geht – Schritt für Schritt, Formeln mit $…$"}
''';

extension LectureWalkAi on AiService {
  /// Die Konzepte einer Vorlesung – jedes mit allen Seiten, auf denen es
  /// erklärt wird.
  Future<List<LectureConcept>> lectureConcepts({required String title, required List<String> pageTexts}) async {
    if (pageTexts.every((t) => t.trim().isEmpty)) {
      throw AiServiceException('Die PDF hat keinen lesbaren Text – Konzepte lassen sich so nicht erkennen.');
    }
    final perPage = (80000 ~/ (pageTexts.isEmpty ? 1 : pageTexts.length)).clamp(250, 1500);
    final text = StringBuffer()
      ..writeln('Vorlesung: $title')
      ..writeln('Seiten: ${pageTexts.length}')
      ..writeln();
    for (var i = 0; i < pageTexts.length; i++) {
      text
        ..writeln('--- Seite ${i + 1} ---')
        ..writeln(AiService._cap(pageTexts[i].trim().isEmpty ? '(kein Text – Bild)' : pageTexts[i].trim(), perPage));
    }
    final raw = await _complete(_lectureConceptsSystemPrompt, text.toString(), temperature: 0.2);
    final json = await _json(raw);
    final concepts = json['concepts'] ?? json['konzepte'] ?? json['topics'];
    final parsed = LectureConcept.tidy([
      for (final t in concepts is List ? concepts : const []) ?LectureConcept.fromMap(t),
    ], pageTexts.length);
    if (parsed.isEmpty) {
      throw AiServiceException('Die KI hat keine Konzepte erkannt – bitte erneut versuchen.', rawResponse: raw);
    }
    return parsed;
  }

  /// Eine vollständige, prüfungsnahe Aufgabe zu [concept] (nicht aus der
  /// Vorlesung), vorgerechnet wie an der Tafel – jeder Schritt mit der Seite,
  /// auf der sein Wissen erklärt wird, und seinen neuen Formeln.
  Future<LectureTask> lectureConceptTask({
    required String lectureTitle,
    required LectureConcept concept,
    required List<String> pageTexts,
    List<String> otherConcepts = const [],
    List<LectureFormula> known = const [],
  }) async {
    final pages = concept.pages;
    final text = StringBuffer()
      ..writeln('Vorlesung: $lectureTitle')
      ..writeln('Konzept: ${concept.title}')
      ..writeln(concept.goal.isEmpty ? '' : 'Ziel: ${concept.goal}')
      ..writeln('Seiten des Konzepts: ${pages.join(', ')}')
      ..writeln()
      ..writeln(
        'AUFTRAG: Erfinde EINE vollständige, schwere, prüfungsnahe Aufgabe zu genau diesem Konzept, die man '
        'nur lösen kann, wenn man das GANZE Konzept beherrscht – von vorne bis hinten (z.B. nicht nur „substituiere“, '
        'sondern die komplette Aufgabe inklusive Ansatz, allen Umformungen, Rücksubstitution, Anfangsbedingung und '
        'Ergebnis/Probe). Übernimm KEINE Aufgabe und kein Beispiel aus der Vorlesung – eigene Zahlen/Funktionen, '
        'sauber lösbar. Die Beispiele der Vorlesung zeigen meist nur Teile; deine Aufgabe verbindet alles.',
      )
      ..writeln(
        'Rechne sie vollständig vor wie an der Tafel (Format unten), Detailgrad regulär. Taschenrechner: ja – '
        'gib "calc" an, wo man ihn in einer Prüfung benutzen würde (Zahlenwerte, Kontrolle).',
      )
      ..writeln('Zusätzlich:')
      ..writeln('- "problem": der Aufgabentext (Formeln mit \$…\$).')
      ..writeln(
        '- je Schritt "page": eine Seite aus [${pages.join(', ')}], auf der das Wissen erklärt wird, das dieser '
        'Schritt braucht. Die Person liest die Seiten der Reihe nach; ein Schritt erscheint erst, wenn seine Seite '
        'gelesen ist. Verteile die Schritte so über die Seiten, dass die Aufgabe mit dem Lesen voranschreitet – nie '
        'früher als die Erklärung, die Seiten der Schritte steigen nicht.',
      )
      ..writeln(
        '- je Schritt "formulas": Formeln/Regeln, die dieser Schritt NEU benutzt (noch nicht in der '
        'Formelsammlung): [{"name": "Kettenregel", "latex": "(f(g(x)))\' = f\'(g(x))\\\\cdot g\'(x)", "note": "wann '
        'man sie benutzt"}] – sonst [].',
      )
      ..writeln(
        '- "say" jedes Schritts knüpft an die Vorlesung an (z.B. „Auf Seite 5 kam die Kettenregel – genau die '
        'brauchen wir jetzt“).',
      );
    if (otherConcepts.isNotEmpty) {
      text.writeln('Andere Konzepte der Vorlesung (die haben eigene Aufgaben): ${otherConcepts.join('; ')}');
    }
    if (known.isNotEmpty) {
      text
        ..writeln()
        ..writeln('Schon in der Formelsammlung (nicht erneut aufnehmen):');
      for (final f in known.take(40)) {
        text.writeln('- ${f.name}: ${f.latex}');
      }
    }
    text
      ..writeln()
      ..writeln('Seiten des Konzepts:');
    final valid = [
      for (final p in pages)
        if (p >= 1 && p <= pageTexts.length) p,
    ];
    final perPage = (36000 ~/ (valid.isEmpty ? 1 : valid.length)).clamp(400, 3000);
    for (final p in valid) {
      text
        ..writeln('--- Seite $p ---')
        ..writeln(
          AiService._cap(pageTexts[p - 1].trim().isEmpty ? '(kein Text – Bild)' : pageTexts[p - 1].trim(), perPage),
        );
    }
    final raw = await _complete(AiService._workedSystemPrompt, text.toString(), temperature: 0.4);
    final json = await _json(raw);
    final task = LectureTask.fromMap(json, pages: pages);
    if (task == null) {
      throw AiServiceException('Die KI hat keine Aufgabe geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return task;
  }

  /// Frage zur gemeinsamen Aufgabe oder zu einer Formel der Formelsammlung.
  Future<String> askLectureWalk({
    required String concept,
    required String problem,
    required List<String> boardSoFar,
    String pageText = '',
    LectureFormula? formula,
    List<({bool user, String text})> history = const [],
    required String question,
  }) async {
    if (question.trim().isEmpty) throw AiServiceException('Stell eine Frage.');
    final context = StringBuffer()
      ..writeln('Konzept der Vorlesung: $concept')
      ..writeln(
        pageText.trim().isEmpty ? '' : 'Aktuelle Seite der Vorlesung:\n${AiService._cap(pageText.trim(), 3000)}',
      );
    return discussWorkedStep(
      problem: problem,
      boardSoFar: boardSoFar,
      stepTitle: formula == null ? 'Gemeinsame Aufgabe zur Vorlesung' : 'Formel: ${formula.name}',
      stepText: formula == null ? context.toString() : '\$${formula.latex}\$ ${formula.note}\n$context',
      history: history,
      question: question,
    );
  }

  /// Eigenen Lösungsversuch prüfen: geschafft – oder an welchem Schritt der
  /// Musterlösung es hakt, mit ausführlicher Erklärung.
  Future<LectureAttempt> checkLectureAttempt({required LectureTask task, required String attempt}) async {
    if (attempt.trim().isEmpty) throw AiServiceException('Schreib zuerst deine Lösung auf.');
    final text = StringBuffer()
      ..writeln('Aufgabe:')
      ..writeln(AiService._cap(task.problem, 4000))
      ..writeln()
      ..writeln('Musterlösung:');
    for (final (i, s) in task.steps.indexed) {
      final line = [
        if (s.step.title.isNotEmpty) s.step.title,
        if (s.step.to.isNotEmpty) s.step.to else if (s.step.content.isNotEmpty) s.step.content,
      ].join(': ');
      text.writeln('${i + 1}. ${AiService._cap(line, 400)}');
    }
    if (task.answer.isNotEmpty) text.writeln('Ergebnis: ${task.answer}');
    text
      ..writeln()
      ..writeln('Lösungsversuch der Person:')
      ..writeln(AiService._cap(attempt.trim(), 6000));
    final raw = await _complete(_lectureCheckSystemPrompt, text.toString(), temperature: 0.1);
    final json = await _json(raw);
    final solved = json['solved'] == true;
    final step = json['step'];
    final index = step is num ? (step.toInt() - 1).clamp(0, task.steps.length - 1) : null;
    return LectureAttempt(
      solved: solved,
      feedback: '${json['feedback'] ?? ''}'.trim(),
      explain: solved ? '' : '${json['explain'] ?? ''}'.trim(),
      step: solved ? null : index,
      at: DateTime.now(),
    );
  }
}
