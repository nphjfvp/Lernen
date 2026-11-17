/// Entsperr-Block der Lernzeit-Sperre: zwei Aufgaben zu einem Thema, das man
/// noch nicht sicher kann – aus Vorlesungen und Übungsaufgaben, angepasst nach
/// Fehlern beim Üben. Beide ohne Hilfe gelöst: volle Handyzeit
/// ([LearnCreditRules.blockMinutes]). Klappt es nicht, gibt es eine
/// Übungseinheit ([UnlockPractice], abgeschlossen: ein paar Minuten vorab) und
/// danach eine neue Aufgabe gleicher Art.
class UnlockBlock {
  const UnlockBlock({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.tasks,
    required this.createdAt,
    this.reason = '',
    this.practice,
    this.rewardedPractice = false,
    this.rewardedSolved = false,
    this.updatedAt,
  });

  final String id;
  final String moduleId;

  /// Thema, z.B. „Integration durch Substitution“.
  final String title;

  /// Warum dieser Block (z.B. „Fehler beim Üben: Rücksubstitution vergessen“).
  final String reason;
  final List<UnlockTask> tasks;

  /// Übungseinheit nach einem Fehlversuch.
  final UnlockPractice? practice;

  /// Minuten schon gutgeschrieben?
  final bool rewardedPractice;
  final bool rewardedSolved;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get solved => tasks.isNotEmpty && tasks.every((t) => t.state == UnlockTaskState.solved);

  /// Noch nichts versucht – darf beim Anpassen ersetzt werden.
  bool get untouched => practice == null && tasks.every((t) => t.state == UnlockTaskState.open && t.attempts == 0);

  UnlockBlock copyWith({
    List<UnlockTask>? tasks,
    UnlockPractice? practice,
    bool clearPractice = false,
    bool? rewardedPractice,
    bool? rewardedSolved,
  }) => UnlockBlock(
    id: id,
    moduleId: moduleId,
    title: title,
    reason: reason,
    tasks: tasks ?? this.tasks,
    practice: clearPractice ? null : practice ?? this.practice,
    rewardedPractice: rewardedPractice ?? this.rewardedPractice,
    rewardedSolved: rewardedSolved ?? this.rewardedSolved,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  /// Aufgabe [index] ersetzen (z.B. durch eine neue gleicher Art).
  UnlockBlock withTask(int index, UnlockTask task) => copyWith(tasks: [...tasks]..[index] = task);

  Map<String, dynamic> toMap() => {
    'id': id,
    'moduleId': moduleId,
    'title': title,
    if (reason.isNotEmpty) 'reason': reason,
    'tasks': [for (final t in tasks) t.toMap()],
    if (practice != null) 'practice': practice!.toMap(),
    'rewardedPractice': rewardedPractice,
    'rewardedSolved': rewardedSolved,
    'createdAt': createdAt.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static UnlockBlock? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}';
    final tasks = raw['tasks'];
    final parsed = [for (final t in tasks is List ? tasks : const []) ?UnlockTask.fromMap(t)];
    if (id.isEmpty || parsed.isEmpty) return null;
    return UnlockBlock(
      id: id,
      moduleId: '${raw['moduleId'] ?? ''}',
      title: '${raw['title'] ?? ''}'.trim(),
      reason: '${raw['reason'] ?? ''}'.trim(),
      tasks: parsed,
      practice: UnlockPractice.fromMap(raw['practice']),
      rewardedPractice: raw['rewardedPractice'] == true,
      rewardedSolved: raw['rewardedSolved'] == true,
      createdAt: DateTime.tryParse('${raw['createdAt'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse('${raw['updatedAt'] ?? ''}'),
    );
  }
}

enum UnlockTaskState { open, failed, solved }

/// Eine Aufgabe des Blocks mit Ergebnis und Musterlösung (für die Prüfung).
class UnlockTask {
  const UnlockTask({
    required this.problem,
    this.answer = '',
    this.solution = '',
    this.state = UnlockTaskState.open,
    this.attempts = 0,
    this.helped = false,
    this.feedback = '',
    this.explain = '',
    this.card,
  });

  final String problem;

  /// Kurzes Endergebnis.
  final String answer;

  /// Musterlösung Schritt für Schritt (mit $…$).
  final String solution;
  final UnlockTaskState state;
  final int attempts;

  /// Hilfe genutzt (Musterlösung angesehen) – dann zählt sie nicht als
  /// „ohne Hilfe gelöst“.
  final bool helped;

  /// Rückmeldung zum letzten Versuch und die Erklärung des Hakens.
  final String feedback;
  final String explain;

  /// Lösbare Karte zur Aufgabe (Flashcard-Map, siehe buildUnlockCard): Mathe als
  /// Rechenweg mit Stift-Blatt und Vorrechnen, sonst die passende Frageart.
  final Map<String, dynamic>? card;

  UnlockTask withCard(Map<String, dynamic> card) => UnlockTask(
    problem: problem,
    answer: answer,
    solution: solution,
    state: state,
    attempts: attempts,
    helped: helped,
    feedback: feedback,
    explain: explain,
    card: card,
  );

  UnlockTask copyWith({UnlockTaskState? state, int? attempts, bool? helped, String? feedback, String? explain}) =>
      UnlockTask(
        problem: problem,
        answer: answer,
        solution: solution,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        helped: helped ?? this.helped,
        feedback: feedback ?? this.feedback,
        explain: explain ?? this.explain,
        card: card,
      );

  Map<String, dynamic> toMap() => {
    'problem': problem,
    if (answer.isNotEmpty) 'answer': answer,
    if (solution.isNotEmpty) 'solution': solution,
    'state': state.name,
    'attempts': attempts,
    'helped': helped,
    if (feedback.isNotEmpty) 'feedback': feedback,
    if (explain.isNotEmpty) 'explain': explain,
    if (card != null) 'card': card,
  };

  static UnlockTask? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final problem = '${raw['problem'] ?? raw['aufgabe'] ?? ''}'.trim();
    if (problem.isEmpty) return null;
    final attempts = raw['attempts'];
    return UnlockTask(
      problem: problem,
      answer: '${raw['answer'] ?? raw['ergebnis'] ?? ''}'.trim(),
      solution: '${raw['solution'] ?? raw['loesung'] ?? raw['lösung'] ?? ''}'.trim(),
      state: UnlockTaskState.values.firstWhere((s) => s.name == raw['state'], orElse: () => UnlockTaskState.open),
      attempts: attempts is num ? attempts.toInt() : 0,
      helped: raw['helped'] == true,
      feedback: '${raw['feedback'] ?? ''}',
      explain: '${raw['explain'] ?? ''}',
      card: raw['card'] is Map ? Map<String, dynamic>.from(raw['card'] as Map) : null,
    );
  }
}

/// Übungseinheit nach einem Fehlversuch: was der Haken war, kleinere
/// Übungsaufgaben (an der Vorrechnen-Tafel, sokratisch) und eine neue Aufgabe
/// gleicher Art für danach.
class UnlockPractice {
  const UnlockPractice({
    required this.task,
    required this.intro,
    required this.exercises,
    this.retry,
    this.finished = const {},
  });

  /// Zu welcher Aufgabe des Blocks.
  final int task;

  /// Erklärung des Hakens.
  final String intro;

  /// Kleinere Übungsaufgaben (Aufgabentexte).
  final List<String> exercises;

  /// Neue Aufgabe gleicher Art (ersetzt die alte, sobald die Einheit fertig ist).
  final UnlockTask? retry;

  /// Bis zum Ende durchgearbeitete Übungsaufgaben.
  final Set<int> finished;

  bool get completed => exercises.isNotEmpty && finished.length >= exercises.length;

  UnlockPractice withFinished(int exercise) =>
      UnlockPractice(task: task, intro: intro, exercises: exercises, retry: retry, finished: {...finished, exercise});

  Map<String, dynamic> toMap() => {
    'task': task,
    'intro': intro,
    'exercises': exercises,
    if (retry != null) 'retry': retry!.toMap(),
    'finished': (finished.toList()..sort()),
  };

  static UnlockPractice? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final exercises = raw['exercises'];
    final finished = raw['finished'];
    final task = raw['task'];
    final list = [
      for (final e in exercises is List ? exercises : const [])
        if (e is Map ? '${e['problem'] ?? ''}'.trim().isNotEmpty : '$e'.trim().isNotEmpty)
          e is Map ? '${e['problem']}'.trim() : '$e'.trim(),
    ];
    if (list.isEmpty) return null;
    return UnlockPractice(
      task: task is num ? task.toInt() : 0,
      intro: '${raw['intro'] ?? ''}'.trim(),
      exercises: list,
      retry: UnlockTask.fromMap(raw['retry']),
      finished: {
        for (final f in finished is List ? finished : const [])
          if (f is num) f.toInt(),
      },
    );
  }
}
