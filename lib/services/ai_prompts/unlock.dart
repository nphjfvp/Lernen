part of '../ai_service.dart';

// Entsperr-Blöcke der Lernzeit-Sperre: aus Vorlesungen, Übungsaufgaben und
// Fehlern beim Üben je Thema zwei Aufgaben planen, Lösungsversuche prüfen,
// nach einem Fehlversuch eine Übungseinheit bauen (siehe UnlockBlock).

const _unlockPlanSystemPrompt = r'''
Du stellst ENTSPERR-BLÖCKE für eine Lern-App zusammen. Ein Block = genau 2 Aufgaben zu EINEM Thema, das die Person
noch nicht (sicher) kann. Wer beide ohne Hilfe löst, bekommt Handyzeit – die Aufgaben müssen also echtes Können
zeigen.

Priorität der Themen:
1. Themen, bei denen die Person beim Üben Fehler gemacht hat (siehe „Fehler beim Üben“) – genau den Haken treffen.
2. Konzepte, die sie noch nicht gelernt hat.
3. Neuer Stoff aus Vorlesungen und Übungsblättern.

Regeln für die Aufgaben:
- prüfungsnah, eigenständig lösbar in je etwa 10–15 Minuten, mit eindeutigem Ergebnis;
- im Stil der Übungsaufgaben, aber KEINE wörtlichen Kopien – eigene Zahlen/Funktionen;
- die zweite Aufgabe etwas anders als die erste (anderer Fall/Zahlen), gleiches Thema;
- "answer": kurzes Endergebnis; "solution": kompakte Musterlösung Schritt für Schritt (Formeln mit $…$).

Offene Blöcke, die noch passen, behältst du ("keep": ihre ids). Neue Blöcke nur für Themen, die noch keinen offenen
Block haben. Höchstens so viele neue Blöcke, wie angegeben.

Antworte NUR mit JSON:
{"keep": ["id1"], "blocks": [{"title": "Integration durch Substitution", "reason": "Fehler beim Üben: …",
  "tasks": [{"problem": "…", "answer": "…", "solution": "…"}, {"problem": "…", "answer": "…", "solution": "…"}]}]}
''';

const _unlockCheckSystemPrompt = r'''
Du prüfst den Lösungsversuch einer Person zu einer Aufgabe. Du kennst Ergebnis und Musterlösung. Andere richtige
Wege, Reihenfolgen und Schreibweisen zählen als richtig. Rechenfehler, falsch angewandte Regeln, fehlende Teile
oder ein falsches Ergebnis zählen als nicht gelöst. Ein bloßes Ergebnis ohne Weg zählt nur, wenn die Aufgabe keinen
Weg verlangt.

Antworte NUR mit JSON:
{"solved": true|false,
 "feedback": "1–3 Sätze direkt an die Person (du)",
 "explain": "Nur wenn nicht gelöst: was genau falsch ist, WIESO, und wie es richtig geht – mit $…$"}
''';

const _unlockPracticeSystemPrompt = r'''
Die Person hat eine Aufgabe eines Entsperr-Blocks nicht ohne Hilfe gelöst. Baue eine kurze ÜBUNGSEINHEIT genau zu
dem Haken:
- "intro": 2–5 Sätze – was der Haken war, die nötige Regel/Idee (mit $…$), worauf man achten muss;
- "exercises": 2–3 kleinere Übungsaufgaben, die genau diesen Haken trainieren (vom Einfachen zum Schwereren, nur
  die Aufgabentexte, Formeln mit $…$);
- "retry": eine NEUE Aufgabe gleicher Art und Schwierigkeit wie die ursprüngliche (andere Zahlen/Funktionen), mit
  "problem", "answer" (kurzes Endergebnis) und "solution" (kompakte Musterlösung).

Antworte NUR mit JSON: {"intro": "…", "exercises": ["…", "…"], "retry": {"problem": "…", "answer": "…",
"solution": "…"}}
''';

extension UnlockBlockAi on AiService {
  /// Entsperr-Blöcke für ein Fach planen bzw. anpassen.
  Future<({List<String> keep, List<UnlockBlock> blocks})> planUnlockBlocks({
    required String moduleId,
    required String moduleName,
    required List<String> notLearned,
    required List<String> learned,
    required List<({String question, String answer, int lapses})> mistakes,
    required List<({String name, String kind, String text})> materials,
    required List<UnlockBlock> open,
    required int maxNew,
    DateTime? now,
  }) async {
    final text = StringBuffer()
      ..writeln('Fach: $moduleName')
      ..writeln('Höchstens neue Blöcke: $maxNew')
      ..writeln();
    if (mistakes.isNotEmpty) {
      text.writeln('Fehler beim Üben (Frage → richtige Lösung, Anzahl Fehler):');
      for (final m in mistakes.take(12)) {
        text.writeln('- ${AiService._cap(m.question, 300)} → ${AiService._cap(m.answer, 200)} (${m.lapses}×)');
      }
      text.writeln();
    }
    if (notLearned.isNotEmpty) text.writeln('Noch nicht gelernte Konzepte: ${notLearned.take(30).join('; ')}');
    if (learned.isNotEmpty) text.writeln('Schon gelernte Themen: ${learned.take(30).join('; ')}');
    if (open.isNotEmpty) {
      text
        ..writeln()
        ..writeln('Offene Blöcke (id: Thema – Grund):');
      for (final b in open) {
        text.writeln('- ${b.id}: ${b.title} – ${b.reason}');
      }
    }
    text
      ..writeln()
      ..writeln('Vorlesungen und Übungsblätter:');
    final perMaterial = (24000 ~/ (materials.isEmpty ? 1 : materials.length)).clamp(600, 6000);
    for (final m in materials) {
      text
        ..writeln('--- ${m.name} (${m.kind}) ---')
        ..writeln(AiService._cap(m.text.trim(), perMaterial));
    }
    final raw = await _complete(_unlockPlanSystemPrompt, text.toString(), temperature: 0.4);
    final json = await _json(raw);
    final keep = [for (final k in json['keep'] is List ? json['keep'] as List : const []) '$k'];
    final when = now ?? DateTime.now();
    final blocks = <UnlockBlock>[];
    for (final (i, b) in (json['blocks'] is List ? json['blocks'] as List : const []).indexed) {
      if (b is! Map || blocks.length >= maxNew) continue;
      final tasks = [for (final t in b['tasks'] is List ? b['tasks'] as List : const []) ?UnlockTask.fromMap(t)];
      final title = '${b['title'] ?? ''}'.trim();
      if (title.isEmpty || tasks.isEmpty) continue;
      blocks.add(
        UnlockBlock(
          id: 'ub-${when.microsecondsSinceEpoch}-$i',
          moduleId: moduleId,
          title: title,
          reason: '${b['reason'] ?? ''}'.trim(),
          tasks: tasks.take(2).toList(),
          createdAt: when,
        ),
      );
    }
    return (keep: keep, blocks: blocks);
  }

  /// Lösungsversuch prüfen.
  Future<({bool solved, String feedback, String explain})> checkUnlockAttempt({
    required UnlockTask task,
    required String attempt,
  }) async {
    if (attempt.trim().isEmpty) throw AiServiceException('Schreib zuerst deine Lösung auf.');
    final text = StringBuffer()
      ..writeln('Aufgabe:')
      ..writeln(AiService._cap(task.problem, 4000))
      ..writeln()
      ..writeln('Ergebnis: ${AiService._cap(task.answer, 600)}')
      ..writeln('Musterlösung:')
      ..writeln(AiService._cap(task.solution, 4000))
      ..writeln()
      ..writeln('Lösungsversuch der Person:')
      ..writeln(AiService._cap(attempt.trim(), 6000));
    final raw = await _complete(_unlockCheckSystemPrompt, text.toString(), temperature: 0.1);
    final json = await _json(raw);
    final solved = json['solved'] == true;
    return (
      solved: solved,
      feedback: '${json['feedback'] ?? ''}'.trim(),
      explain: solved ? '' : '${json['explain'] ?? ''}'.trim(),
    );
  }

  /// Übungseinheit nach einem Fehlversuch bei Aufgabe [index].
  Future<UnlockPractice> planUnlockPractice({required UnlockBlock block, required int index}) async {
    final task = block.tasks[index];
    final text = StringBuffer()
      ..writeln('Thema: ${block.title}')
      ..writeln()
      ..writeln('Ursprüngliche Aufgabe:')
      ..writeln(AiService._cap(task.problem, 3000))
      ..writeln('Ergebnis: ${AiService._cap(task.answer, 600)}')
      ..writeln('Musterlösung:')
      ..writeln(AiService._cap(task.solution, 3000))
      ..writeln();
    if (task.feedback.isNotEmpty || task.explain.isNotEmpty) {
      text
        ..writeln('Was beim Versuch falsch war:')
        ..writeln(AiService._cap('${task.feedback}\n${task.explain}', 3000));
    } else if (task.helped) {
      text.writeln('Die Person hat sich die Musterlösung angesehen, ohne selbst zu lösen.');
    }
    final raw = await _complete(_unlockPracticeSystemPrompt, text.toString(), temperature: 0.4);
    final json = await _json(raw);
    final practice = UnlockPractice.fromMap({...json, 'task': index});
    if (practice == null) {
      throw AiServiceException('Die KI hat keine Übungseinheit geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return practice;
  }
}
