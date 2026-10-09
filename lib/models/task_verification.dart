/// Urteil der zweiten KI über eine übernommene Aufgabe bzw. Frage (siehe
/// AiService.verifyTask).
enum TaskVerdict {
  ok('KI: stimmt'),
  wrong('KI: Fehler gefunden'),
  unclear('KI: bitte selbst prüfen');

  const TaskVerdict(this.label);
  final String label;
}

TaskVerdict taskVerdictFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase().trim();
  if (v == 'ok' || v.contains('stimmt') || v.contains('korrekt') || v.contains('richtig')) return TaskVerdict.ok;
  if (v.contains('fehler') || v.contains('falsch') || v.contains('wrong') || v.contains('error')) {
    return TaskVerdict.wrong;
  }
  return TaskVerdict.unclear;
}

class TaskVerification {
  const TaskVerification({required this.verdict, this.comment = '', this.corrected});

  final TaskVerdict verdict;

  /// Was falsch ist und was richtig wäre (LaTeX in $…$).
  final String comment;

  /// Vollständig korrigierte Daten (taskData bzw. Frage) – sonst null.
  final Map<String, dynamic>? corrected;

  static TaskVerification fromJson(Map<String, dynamic> json) {
    final corrected = json['corrected'] ?? json['korrigiert'];
    return TaskVerification(
      verdict: taskVerdictFrom(json['verdict'] ?? json['urteil']),
      comment: '${json['comment'] ?? json['kommentar'] ?? json['answer'] ?? ''}'.trim(),
      corrected: corrected is Map ? Map<String, dynamic>.from(corrected) : null,
    );
  }
}
