import 'worked_solution.dart';

/// Vorlesung mit Aufgabe: Vor dem Lesen geht die KI die ganze Vorlesung durch
/// und bestimmt, welche Konzepte vermittelt werden – jedes mit allen Seiten,
/// auf denen es erklärt wird (auch verteilt). Zu jedem Konzept gibt es EINE
/// vollständige, prüfungsnahe Aufgabe (nicht aus der Vorlesung), die über
/// genau diese Seiten Schritt für Schritt gelöst wird – an der Tafel wie bei
/// „Vorrechnen“. Neue Formeln landen in einer Formelsammlung. Am Ende löst man
/// die Aufgaben selbst; bei einem Fehler weiß die App, auf welcher Seite der
/// Haken erklärt wird.
class LectureWalk {
  const LectureWalk({
    required this.materialId,
    required this.moduleId,
    required this.title,
    required this.pageCount,
    this.concepts = const [],
    this.tasks = const {},
    this.page = 1,
    this.maxPage = 1,
    this.current = -1,
    this.formulas = const [],
    this.attempts = const {},
    this.updatedAt,
  });

  /// Gespeichertes Format – ältere Stände werden neu vorbereitet.
  static const version = 2;

  final String materialId;
  final String moduleId;
  final String title;
  final int pageCount;

  /// Konzepte der Vorlesung mit ihren Seiten (von der KI erkannt).
  final List<LectureConcept> concepts;

  /// Aufgabe je Konzept (Index in [concepts]).
  final Map<int, LectureTask> tasks;

  /// Aktuelle und am weitesten erreichte Seite (1-basiert).
  final int page;
  final int maxPage;

  /// Das Konzept, dessen Aufgabe gerade an der Tafel steht (-1 = keins).
  final int current;

  /// Formelsammlung: in der Reihenfolge, in der die Formeln drankamen.
  final List<LectureFormula> formulas;

  /// Selbst gelöst je Konzept.
  final Map<int, LectureAttempt> attempts;
  final DateTime? updatedAt;

  /// Einmal ganz durch – dann kann man die Aufgaben selbst lösen.
  bool get finished => pageCount > 0 && maxPage >= pageCount;

  /// Alle Aufgaben vorbereitet?
  bool get prepared => concepts.isNotEmpty && tasks.length >= concepts.length;

  /// Konzepte, die auf Seite [page] erklärt werden.
  List<int> conceptsOn(int page) => [
    for (var i = 0; i < concepts.length; i++)
      if (concepts[i].pages.contains(page)) i,
  ];

  /// Wie viele Schritte der Aufgabe zu Konzept [concept] schon an der Tafel
  /// stehen: der Reihe nach alle, deren Seite schon erreicht ist.
  int revealedCount(int concept) {
    final task = tasks[concept];
    if (task == null) return 0;
    var n = 0;
    for (final s in task.steps) {
      if (s.page > maxPage) break;
      n++;
    }
    return n;
  }

  /// Seite erreicht: [maxPage] wächst, die Tafel wechselt zu dem Konzept, bei
  /// dem es weitergeht (sonst zu einem, das auf der Seite erklärt wird), neue
  /// Formeln kommen in die Formelsammlung.
  LectureWalk withPage(int page) {
    final clamped = page.clamp(1, pageCount < 1 ? 1 : pageCount);
    final reached = clamped > maxPage ? clamped : maxPage;
    final moved = copyWith(page: clamped, maxPage: reached);
    final advanced = [
      for (var i = 0; i < concepts.length; i++)
        if (moved.revealedCount(i) > revealedCount(i)) i,
    ];
    final on = conceptsOn(clamped);
    final next = advanced.isNotEmpty
        ? advanced.first
        : on.contains(current)
        ? current
        : on.isNotEmpty
        ? on.first
        : current;
    return moved.copyWith(current: next).withRevealedFormulas();
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
    List<LectureConcept>? concepts,
    Map<int, LectureTask>? tasks,
    int? page,
    int? maxPage,
    int? current,
    List<LectureFormula>? formulas,
    Map<int, LectureAttempt>? attempts,
    DateTime? updatedAt,
  }) => LectureWalk(
    materialId: materialId,
    moduleId: moduleId,
    title: title,
    pageCount: pageCount,
    concepts: concepts ?? this.concepts,
    tasks: tasks ?? this.tasks,
    page: page ?? this.page,
    maxPage: maxPage ?? this.maxPage,
    current: current ?? this.current,
    formulas: formulas ?? this.formulas,
    attempts: attempts ?? this.attempts,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'version': version,
    'materialId': materialId,
    'moduleId': moduleId,
    'title': title,
    'pageCount': pageCount,
    'concepts': [for (final t in concepts) t.toMap()],
    'tasks': {for (final e in tasks.entries) '${e.key}': e.value.toMap()},
    'page': page,
    'maxPage': maxPage,
    'current': current,
    'formulas': [for (final f in formulas) f.toMap()],
    'attempts': {for (final e in attempts.entries) '${e.key}': e.value.toMap()},
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static LectureWalk? fromMap(Object? raw) {
    if (raw is! Map || raw['version'] != version) return null;
    final id = '${raw['materialId'] ?? ''}';
    if (id.isEmpty) return null;
    int number(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    final pageCount = number(raw['pageCount'], 0);
    final concepts = raw['concepts'];
    final tasks = raw['tasks'];
    final formulas = raw['formulas'];
    final attempts = raw['attempts'];
    return LectureWalk(
      materialId: id,
      moduleId: '${raw['moduleId'] ?? ''}',
      title: '${raw['title'] ?? ''}',
      pageCount: pageCount,
      concepts: [
        if (concepts is List)
          for (final t in concepts) ?LectureConcept.fromMap(t),
      ],
      tasks: {
        if (tasks is Map)
          for (final e in tasks.entries) ?int.tryParse('${e.key}'): ?LectureTask.fromMap(e.value),
      },
      page: number(raw['page'], 1),
      maxPage: number(raw['maxPage'], 1),
      current: number(raw['current'], -1),
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

/// Ein Konzept der Vorlesung (z.B. „DGL durch Substitution lösen“): was man am
/// Ende können soll und alle Seiten, auf denen es erklärt wird.
class LectureConcept {
  const LectureConcept({required this.title, required this.pages, this.goal = ''});

  final String title;

  /// Was man am Ende können soll (eine Aufgabe von vorne bis hinten lösen).
  final String goal;

  /// Seiten, auf denen das Konzept erklärt wird – aufsteigend, auch verteilt.
  final List<int> pages;

  int get from => pages.isEmpty ? 0 : pages.first;
  int get to => pages.isEmpty ? 0 : pages.last;

  /// „S. 3–5, 9“.
  String get pagesLabel {
    final parts = <String>[];
    var i = 0;
    while (i < pages.length) {
      var j = i;
      while (j + 1 < pages.length && pages[j + 1] == pages[j] + 1) {
        j++;
      }
      parts.add(i == j ? '${pages[i]}' : '${pages[i]}–${pages[j]}');
      i = j + 1;
    }
    return 'S. ${parts.join(', ')}';
  }

  Map<String, dynamic> toMap() => {'title': title, if (goal.isNotEmpty) 'goal': goal, 'pages': pages};

  static LectureConcept? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final title = '${raw['title'] ?? raw['konzept'] ?? ''}'.trim();
    final pages = raw['pages'] ?? raw['seiten'];
    final from = raw['from'] ?? raw['von'];
    final to = raw['to'] ?? raw['bis'];
    final list = <int>{
      if (pages is List)
        for (final p in pages)
          if (p is num) p.toInt(),
      if (pages is! List && from is num)
        for (var p = from.toInt(); p <= (to is num && to.toInt() >= from.toInt() ? to.toInt() : from.toInt()); p++) p,
    }.toList()..sort();
    if (title.isEmpty || list.isEmpty) return null;
    return LectureConcept(title: title, goal: '${raw['goal'] ?? raw['ziel'] ?? ''}'.trim(), pages: list);
  }

  /// Konzepte der KI aufräumen: Seiten innerhalb der PDF, ohne Doppelte,
  /// sortiert nach der ersten Seite.
  static List<LectureConcept> tidy(List<LectureConcept> raw, int pageCount) {
    final out = <LectureConcept>[];
    for (final c in raw) {
      final pages = {
        for (final p in c.pages)
          if (p >= 1 && p <= pageCount) p,
      }.toList()..sort();
      if (pages.isEmpty || out.any((o) => o.title.toLowerCase() == c.title.toLowerCase())) continue;
      out.add(LectureConcept(title: c.title, goal: c.goal, pages: pages));
    }
    out.sort((a, b) => a.from.compareTo(b.from));
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

  /// [page] auf die nächste erlaubte Seite (≥ page, sonst die letzte).
  static int snap(int page, List<int> pages) {
    if (pages.isEmpty) return page < 1 ? 1 : page;
    for (final p in pages) {
      if (p >= page) return p;
    }
    return pages.last;
  }

  final WorkStep step;
  final int page;
  final List<LectureFormula> formulas;

  Map<String, dynamic> toMap() => {
    ...step.toMap(),
    'page': page,
    'formulas': [for (final f in formulas) f.toMap()],
  };

  /// [pages]: erlaubte Seiten (die des Konzepts) – die Seite rastet auf die
  /// nächste erlaubte ein.
  static LectureTaskStep? fromMap(Object? raw, {List<int> pages = const []}) {
    final step = WorkStep.fromMap(raw);
    if (step == null || raw is! Map) return null;
    final page = raw['page'] ?? raw['seite'];
    final formulas = raw['formulas'] ?? raw['formeln'];
    return LectureTaskStep(
      step: step,
      page: snap(page is num ? page.toInt() : 0, pages),
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

  /// Als Vorrechnen-Lösung (für die Tafel).
  WorkedSolution toWorked({required String id, required String moduleId, String fallbackTitle = ''}) => WorkedSolution(
    id: id,
    moduleId: moduleId,
    problem: problem,
    detail: WorkDetail.normal,
    steps: [for (final s in steps) s.step],
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    title: title.isEmpty ? fallbackTitle : title,
    answer: answer,
    withCalculator: steps.any((s) => s.step.calc != null),
  );

  /// Schritt [index] wurde an der Tafel in [parts] feinere Schritte geteilt –
  /// sie bekommen dessen Seite (Formeln beim ersten).
  LectureTask withRefined(int index, List<WorkStep> parts) {
    if (index < 0 || index >= steps.length || parts.isEmpty) return this;
    final old = steps[index];
    final replaced = [
      for (final (i, p) in parts.indexed)
        LectureTaskStep(step: p, page: old.page, formulas: i == 0 ? old.formulas : const []),
    ];
    return LectureTask(
      title: title,
      problem: problem,
      answer: answer,
      steps: [...steps]..replaceRange(index, index + 1, replaced),
    );
  }

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

  static LectureTask? fromMap(Object? raw, {List<int> pages = const []}) {
    if (raw is! Map) return null;
    final problem = '${raw['problem'] ?? raw['aufgabe'] ?? ''}'.trim();
    final steps = raw['steps'] ?? raw['schritte'];
    if (problem.isEmpty || steps is! List) return null;
    final parsed = [for (final s in steps) ?LectureTaskStep.fromMap(s, pages: pages)];
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
