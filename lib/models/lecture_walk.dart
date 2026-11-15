import 'worked_solution.dart';

/// Vorlesung mit Aufgabe: Man geht eine hochgeladene Vorlesung (PDF) Seite für
/// Seite durch und rechnet dabei je Thema EINE schwere Übungsaufgabe
/// gemeinsam an der Tafel – nach jeder Seite, die das Thema weiter erklärt,
/// geht es mit der Aufgabe weiter. Neue Formeln landen in einer
/// Formelsammlung. Am Ende löst man die Aufgaben selbst; bei einem Fehler
/// weiß die App, auf welcher Seite der Haken erklärt wird.
class LectureWalk {
  const LectureWalk({
    required this.materialId,
    required this.moduleId,
    required this.title,
    required this.pageCount,
    this.topics = const [],
    this.tasks = const {},
    this.page = 1,
    this.maxPage = 1,
    this.formulas = const [],
    this.attempts = const {},
    this.updatedAt,
  });

  final String materialId;
  final String moduleId;
  final String title;
  final int pageCount;

  /// Themen der Vorlesung mit ihren Seiten (von der KI erkannt).
  final List<LectureTopic> topics;

  /// Aufgabe je Thema (Index in [topics]) – entsteht, sobald das Thema dran ist.
  final Map<int, LectureTask> tasks;

  /// Aktuelle und am weitesten erreichte Seite (1-basiert).
  final int page;
  final int maxPage;

  /// Formelsammlung: in der Reihenfolge, in der die Formeln drankamen.
  final List<LectureFormula> formulas;

  /// Selbst gelöst je Thema.
  final Map<int, LectureAttempt> attempts;
  final DateTime? updatedAt;

  /// Einmal ganz durch – dann kann man die Aufgaben selbst lösen.
  bool get finished => pageCount > 0 && maxPage >= pageCount;

  /// Das Thema auf Seite [page]: das, in dessen Seiten sie liegt, sonst das
  /// letzte davor begonnene; -1 = vor dem ersten Thema (z.B. Titelseite).
  int topicAt(int page) {
    var found = -1;
    for (var i = 0; i < topics.length; i++) {
      final t = topics[i];
      if (page >= t.from && page <= t.to) return i;
      if (t.from <= page) found = i;
    }
    return found;
  }

  /// Wie viele Schritte der Aufgabe zu Thema [topic] schon an der Tafel
  /// stehen: der Reihe nach alle, deren Seite schon erreicht ist.
  int revealedCount(int topic) {
    final task = tasks[topic];
    if (task == null) return 0;
    var n = 0;
    for (final s in task.steps) {
      if (s.page > maxPage) break;
      n++;
    }
    return n;
  }

  /// Seite erreicht: [maxPage] wächst, neue Formeln der dadurch
  /// aufgedeckten Schritte kommen in die Formelsammlung.
  LectureWalk withPage(int page) {
    final clamped = page.clamp(1, pageCount < 1 ? 1 : pageCount);
    final reached = clamped > maxPage ? clamped : maxPage;
    return copyWith(page: clamped, maxPage: reached).withRevealedFormulas();
  }

  /// Formeln aller aufgedeckten Schritte in die Formelsammlung (ohne Doppelte).
  LectureWalk withRevealedFormulas() {
    final list = [...formulas];
    bool known(LectureFormula f) => list.any(
      (e) => _norm(e.latex) == _norm(f.latex) || (e.name.isNotEmpty && e.name.toLowerCase() == f.name.toLowerCase()),
    );
    for (final entry in tasks.entries) {
      final shown = revealedCount(entry.key);
      for (final s in entry.value.steps.take(shown)) {
        for (final f in s.formulas) {
          if (f.latex.trim().isEmpty || known(f)) continue;
          list.add(LectureFormula(name: f.name, latex: f.latex, note: f.note, page: s.page));
        }
      }
    }
    return list.length == formulas.length ? this : copyWith(formulas: list);
  }

  static String _norm(String latex) => latex.replaceAll(RegExp(r'\s+'), '');

  LectureWalk copyWith({
    List<LectureTopic>? topics,
    Map<int, LectureTask>? tasks,
    int? page,
    int? maxPage,
    List<LectureFormula>? formulas,
    Map<int, LectureAttempt>? attempts,
    DateTime? updatedAt,
  }) => LectureWalk(
    materialId: materialId,
    moduleId: moduleId,
    title: title,
    pageCount: pageCount,
    topics: topics ?? this.topics,
    tasks: tasks ?? this.tasks,
    page: page ?? this.page,
    maxPage: maxPage ?? this.maxPage,
    formulas: formulas ?? this.formulas,
    attempts: attempts ?? this.attempts,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'materialId': materialId,
    'moduleId': moduleId,
    'title': title,
    'pageCount': pageCount,
    'topics': [for (final t in topics) t.toMap()],
    'tasks': {for (final e in tasks.entries) '${e.key}': e.value.toMap()},
    'page': page,
    'maxPage': maxPage,
    'formulas': [for (final f in formulas) f.toMap()],
    'attempts': {for (final e in attempts.entries) '${e.key}': e.value.toMap()},
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static LectureWalk? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['materialId'] ?? ''}';
    if (id.isEmpty) return null;
    int number(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    final pageCount = number(raw['pageCount'], 0);
    final topics = raw['topics'];
    final tasks = raw['tasks'];
    final formulas = raw['formulas'];
    final attempts = raw['attempts'];
    return LectureWalk(
      materialId: id,
      moduleId: '${raw['moduleId'] ?? ''}',
      title: '${raw['title'] ?? ''}',
      pageCount: pageCount,
      topics: [
        if (topics is List)
          for (final t in topics) ?LectureTopic.fromMap(t),
      ],
      tasks: {
        if (tasks is Map)
          for (final e in tasks.entries) ?int.tryParse('${e.key}'): ?LectureTask.fromMap(e.value),
      },
      page: number(raw['page'], 1),
      maxPage: number(raw['maxPage'], 1),
      formulas: [
        if (formulas is List)
          for (final f in formulas) ?LectureFormula.fromMap(f),
      ],
      attempts: {
        if (attempts is Map)
          for (final e in attempts.entries) ?int.tryParse('${e.key}'): ?LectureAttempt.fromMap(e.value),
      },
      updatedAt: DateTime.tryParse('${raw['updatedAt'] ?? ''}'),
    );
  }
}

/// Ein Thema der Vorlesung (z.B. „Variablen trennen“) mit seinen Seiten.
class LectureTopic {
  const LectureTopic({required this.title, required this.from, required this.to});

  final String title;
  final int from;
  final int to;

  Map<String, dynamic> toMap() => {'title': title, 'from': from, 'to': to};

  static LectureTopic? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final title = '${raw['title'] ?? raw['thema'] ?? ''}'.trim();
    final from = raw['from'] ?? raw['von'];
    final to = raw['to'] ?? raw['bis'];
    if (title.isEmpty || from is! num) return null;
    final start = from.toInt();
    final end = to is num && to.toInt() >= start ? to.toInt() : start;
    return LectureTopic(title: title, from: start, to: end);
  }

  /// Themen der KI aufräumen: sortiert, innerhalb der Seiten, ohne Überlappung.
  static List<LectureTopic> tidy(List<LectureTopic> raw, int pageCount) {
    final sorted = [...raw]..sort((a, b) => a.from.compareTo(b.from));
    final out = <LectureTopic>[];
    for (final t in sorted) {
      var from = t.from.clamp(1, pageCount);
      final to = t.to.clamp(from, pageCount);
      if (out.isNotEmpty && from <= out.last.to) {
        // Überlappung: das neue Thema beginnt nach dem vorigen.
        if (to <= out.last.to) continue;
        from = out.last.to + 1;
      }
      out.add(LectureTopic(title: t.title, from: from, to: to));
    }
    return out;
  }
}

/// Eine Formel der Formelsammlung – mit der Seite, auf der sie drankam.
class LectureFormula {
  const LectureFormula({required this.name, required this.latex, this.note = '', this.page = 0});

  final String name;
  final String latex;
  final String note;
  final int page;

  Map<String, dynamic> toMap() => {'name': name, 'latex': latex, if (note.isNotEmpty) 'note': note, 'page': page};

  static LectureFormula? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final latex = '${raw['latex'] ?? raw['formula'] ?? raw['formel'] ?? ''}'.trim();
    if (latex.isEmpty) return null;
    final page = raw['page'];
    return LectureFormula(
      name: '${raw['name'] ?? ''}'.trim(),
      latex: latex.replaceAll(RegExp(r'^\$+|\$+$'), '').trim(),
      note: '${raw['note'] ?? raw['hinweis'] ?? ''}'.trim(),
      page: page is num ? page.toInt() : 0,
    );
  }
}

/// Ein Schritt der Aufgabe – mit der Seite, auf der das nötige Wissen
/// erklärt wird, und den Formeln, die er neu benutzt.
class LectureTaskStep {
  const LectureTaskStep({required this.step, required this.page, this.formulas = const []});

  final WorkStep step;
  final int page;
  final List<LectureFormula> formulas;

  Map<String, dynamic> toMap() => {
    ...step.toMap(),
    'page': page,
    'formulas': [for (final f in formulas) f.toMap()],
  };

  static LectureTaskStep? fromMap(Object? raw, {int from = 1, int to = 1 << 20}) {
    final step = WorkStep.fromMap(raw);
    if (step == null || raw is! Map) return null;
    final page = raw['page'] ?? raw['seite'];
    final formulas = raw['formulas'] ?? raw['formeln'];
    return LectureTaskStep(
      step: step,
      page: (page is num ? page.toInt() : from).clamp(from, to),
      formulas: [
        if (formulas is List)
          for (final f in formulas) ?LectureFormula.fromMap(f),
      ],
    );
  }
}

/// Die Aufgabe zu einem Thema mit ihrem vorgerechneten Weg.
class LectureTask {
  const LectureTask({required this.title, required this.problem, required this.steps, this.answer = ''});

  final String title;
  final String problem;
  final List<LectureTaskStep> steps;
  final String answer;

  /// Die Seiten der Schritte steigen nie (die Tafel wächst der Reihe nach).
  static List<LectureTaskStep> ordered(List<LectureTaskStep> steps) {
    var floor = 0;
    return [
      for (final s in steps)
        () {
          if (s.page < floor) return LectureTaskStep(step: s.step, page: floor, formulas: s.formulas);
          floor = s.page;
          return s;
        }(),
    ];
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'problem': problem,
    'answer': answer,
    'steps': [for (final s in steps) s.toMap()],
  };

  static LectureTask? fromMap(Object? raw, {int from = 1, int to = 1 << 20}) {
    if (raw is! Map) return null;
    final problem = '${raw['problem'] ?? raw['aufgabe'] ?? ''}'.trim();
    final steps = raw['steps'] ?? raw['schritte'];
    if (problem.isEmpty || steps is! List) return null;
    final parsed = [for (final s in steps) ?LectureTaskStep.fromMap(s, from: from, to: to)];
    if (parsed.isEmpty) return null;
    return LectureTask(
      title: '${raw['title'] ?? ''}'.trim(),
      problem: problem,
      answer: '${raw['answer'] ?? raw['ergebnis'] ?? ''}'.trim(),
      steps: ordered(parsed),
    );
  }
}

/// Ergebnis „Selbst lösen“: geschafft – oder wo der Haken war.
class LectureAttempt {
  const LectureAttempt({required this.solved, this.feedback = '', this.explain = '', this.step, this.at});

  final bool solved;
  final String feedback;

  /// Ausführliche Erklärung zum Haken (was, wieso, warum).
  final String explain;

  /// Erster Schritt der Musterlösung, an dem es hakt.
  final int? step;
  final DateTime? at;

  Map<String, dynamic> toMap() => {
    'solved': solved,
    if (feedback.isNotEmpty) 'feedback': feedback,
    if (explain.isNotEmpty) 'explain': explain,
    if (step != null) 'step': step,
    if (at != null) 'at': at!.toIso8601String(),
  };

  static LectureAttempt? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final step = raw['step'];
    return LectureAttempt(
      solved: raw['solved'] == true,
      feedback: '${raw['feedback'] ?? ''}',
      explain: '${raw['explain'] ?? ''}',
      step: step is num ? step.toInt() : null,
      at: DateTime.tryParse('${raw['at'] ?? ''}'),
    );
  }
}
