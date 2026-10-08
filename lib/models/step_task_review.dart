import 'step_task.dart';

/// Einschätzung der KI zu den Unstimmigkeiten, die die App in einem Rechenweg
/// gefunden hat (siehe AiService.reviewStepTask, StepTaskReviewSheet).
enum StepReviewVerdict {
  /// Die Aufgabe und die Musterlösung stimmen, die Meldung ist harmlos.
  ok('Aufgabe stimmt'),

  /// Nur hinterlegte Fehler-Rückmeldungen o.ä. sind falsch – die Lösung selbst stimmt.
  feedbackWrong('Nur eine Rückmeldung ist falsch'),

  /// Die Musterlösung (eine erwartete Antwort) ist falsch.
  solutionWrong('Musterlösung fehlerhaft'),
  unclear('Unklar');

  const StepReviewVerdict(this.label);
  final String label;
}

StepReviewVerdict stepReviewVerdictFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase();
  if (v.contains('loesung') || v.contains('lösung') || v.contains('solution')) return StepReviewVerdict.solutionWrong;
  if (v.contains('rueckmeldung') || v.contains('rückmeldung') || v.contains('feedback') || v.contains('fehler')) {
    return StepReviewVerdict.feedbackWrong;
  }
  if (v == 'ok' || v.contains('stimmt') || v.contains('korrekt')) return StepReviewVerdict.ok;
  return StepReviewVerdict.unclear;
}

class StepTaskReview {
  const StepTaskReview({required this.answer, this.verdict = StepReviewVerdict.unclear, this.corrected});

  /// Erklärung in einfachen Worten (LaTeX in $…$).
  final String answer;
  final StepReviewVerdict verdict;

  /// Korrigierte Aufgabe, falls die KI etwas ändern würde (sonst null).
  final StepTask? corrected;

  static StepTaskReview fromJson(Map<String, dynamic> json) => StepTaskReview(
        answer: '${json['answer'] ?? json['erklaerung'] ?? json['erklärung'] ?? ''}'.trim(),
        verdict: stepReviewVerdictFrom(json['verdict'] ?? json['urteil']),
        corrected: json['corrected'] is Map ? StepTask.fromMap(json['corrected']) : null,
      );
}
