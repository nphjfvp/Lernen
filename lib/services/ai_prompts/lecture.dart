part of '../ai_service.dart';

// „Vorlesung mit Aufgabe“: Themen einer Vorlesung erkennen, je Thema eine
// schwere Aufgabe mit Seitenbezug vorrechnen, Fragen beantworten, eigene
// Lösungen prüfen (siehe LectureWalk).

const _lectureTopicsSystemPrompt = r'''
Du gliederst eine Vorlesung (Folien als Text je Seite) in THEMEN für ein Lernprogramm. Zu jedem Thema rechnet die
Person später EINE schwere Übungsaufgabe, während sie die Seiten des Themas durchgeht.

Ein Thema ist fein abgegrenzt: eine Methode, ein Verfahren oder ein Konzept, zu dem man eine eigene Aufgabe stellen
kann – z.B. unter „Differentialgleichungen“ sind „Variablen trennen“, „Substitution“ und „Variation der Konstanten“
je ein eigenes Thema, nicht „Differentialgleichungen“ als Ganzes.

Regeln:
- Seiten ohne Stoff (Titelseite, Gliederung, Organisatorisches, Literatur) gehören zu keinem Thema.
- Reine Motivation/Einleitung ohne eigene Aufgabe: dem folgenden Thema zuschlagen.
- Themen in der Reihenfolge der Vorlesung, Seiten zusammenhängend, ohne Überlappung.
- Titel kurz und merkbar (2–5 Wörter), auf Deutsch.

Antworte NUR mit JSON: {"topics": [{"title": "Variablen trennen", "from": 3, "to": 7}]}
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
  /// Die Themen einer Vorlesung mit ihren Seiten.
  Future<List<LectureTopic>> lectureTopics({required String title, required List<String> pageTexts}) async {
    if (pageTexts.every((t) => t.trim().isEmpty)) {
      throw AiServiceException('Die PDF hat keinen lesbaren Text – Themen lassen sich so nicht erkennen.');
    }
    final perPage = (70000 ~/ (pageTexts.isEmpty ? 1 : pageTexts.length)).clamp(200, 1200);
    final text = StringBuffer()
      ..writeln('Vorlesung: $title')
      ..writeln('Seiten: ${pageTexts.length}')
      ..writeln();
    for (var i = 0; i < pageTexts.length; i++) {
      text
        ..writeln('--- Seite ${i + 1} ---')
        ..writeln(AiService._cap(pageTexts[i].trim().isEmpty ? '(kein Text – Bild)' : pageTexts[i].trim(), perPage));
    }
    final raw = await _complete(_lectureTopicsSystemPrompt, text.toString(), temperature: 0.2);
    final json = await _json(raw);
    final topics = json['topics'] ?? json['themen'];
    final parsed = LectureTopic.tidy([
      for (final t in topics is List ? topics : const []) ?LectureTopic.fromMap(t),
    ], pageTexts.length);
    if (parsed.isEmpty) {
      throw AiServiceException('Die KI hat keine Themen erkannt – bitte erneut versuchen.', rawResponse: raw);
    }
    return parsed;
  }

  /// Eine schwere Aufgabe zu [topic], vorgerechnet wie an der Tafel – jeder
  /// Schritt mit der Seite, auf der sein Wissen erklärt wird, und seinen neuen
  /// Formeln.
  Future<LectureTask> lectureTopicTask({
    required String lectureTitle,
    required LectureTopic topic,
    required List<String> pageTexts,
    List<LectureFormula> known = const [],
  }) async {
    final text = StringBuffer()
      ..writeln('Vorlesung: $lectureTitle')
      ..writeln('Thema: ${topic.title} (Seiten ${topic.from}–${topic.to})')
      ..writeln()
      ..writeln(
        'AUFTRAG: Erfinde EINE schwere, prüfungsnahe Übungsaufgabe zu genau diesem Thema, die möglichst alles '
        'nutzt, was auf diesen Seiten erklärt wird (Zahlen/Funktionen selbst gewählt, sauber lösbar). Die Person '
        'bekommt sie am Anfang des Themas und rechnet sie gemeinsam mit dir, während sie die Seiten durchgeht. '
        'Rechne sie vor wie an der Tafel (Format unten), Detailgrad regulär, ohne Taschenrechner (kein "calc").',
      )
      ..writeln('Zusätzlich:')
      ..writeln('- "problem": der Aufgabentext (Formeln mit \$…\$).')
      ..writeln(
        '- je Schritt "page": die Seite (${topic.from}–${topic.to}), auf der das Wissen erklärt wird, das dieser '
        'Schritt braucht. Ein Schritt wird erst aufgedeckt, wenn diese Seite gelesen ist – also nie früher als die '
        'Erklärung; die Seiten der Schritte steigen nicht.',
      )
      ..writeln(
        '- je Schritt "formulas": Formeln/Regeln, die dieser Schritt NEU benutzt (noch nicht in der '
        'Formelsammlung): [{"name": "Kettenregel", "latex": "(f(g(x)))\' = f\'(g(x))\\\\cdot g\'(x)", "note": "wann man '
        'sie benutzt"}] – sonst [].',
      )
      ..writeln(
        '- "say" jedes Schritts knüpft an die Vorlesung an (z.B. „Auf Seite 5 kam die Kettenregel – genau die '
        'brauchen wir jetzt“).',
      );
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
      ..writeln('Seiten des Themas:');
    final pages = [for (var p = topic.from; p <= topic.to && p <= pageTexts.length; p++) p];
    final perPage = (30000 ~/ (pages.isEmpty ? 1 : pages.length)).clamp(400, 3000);
    for (final p in pages) {
      text
        ..writeln('--- Seite $p ---')
        ..writeln(
          AiService._cap(pageTexts[p - 1].trim().isEmpty ? '(kein Text – Bild)' : pageTexts[p - 1].trim(), perPage),
        );
    }
    final raw = await _complete(AiService._workedSystemPrompt, text.toString(), temperature: 0.4);
    final json = await _json(raw);
    final task = LectureTask.fromMap(json, from: topic.from, to: topic.to);
    if (task == null) {
      throw AiServiceException('Die KI hat keine Aufgabe geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return task;
  }

  /// Frage zur gemeinsamen Aufgabe oder zu einer Formel der Formelsammlung.
  Future<String> askLectureWalk({
    required String topic,
    required String problem,
    required List<String> boardSoFar,
    String pageText = '',
    LectureFormula? formula,
    List<({bool user, String text})> history = const [],
    required String question,
  }) async {
    if (question.trim().isEmpty) throw AiServiceException('Stell eine Frage.');
    final context = StringBuffer()
      ..writeln('Thema der Vorlesung: $topic')
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
