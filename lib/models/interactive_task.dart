import 'flashcard.dart';
import 'gantt_task.dart';
import 'step_task.dart';

/// Welche interaktive Aufgabe aus einer Übungsaufgabe wird.
enum InteractiveKind {
  steps('Rechenweg', QuestionType.steps),
  gantt('Terminierung', QuestionType.gantt);

  const InteractiveKind(this.label, this.type);
  final String label;
  final QuestionType type;
}

InteractiveKind? interactiveKindFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase();
  if (v.contains('gantt') || v.contains('termin') || v.contains('schedul')) return InteractiveKind.gantt;
  if (v.contains('step') || v.contains('rechen') || v.contains('schritt')) return InteractiveKind.steps;
  return null;
}

/// Was die KI aus einer Übungsaufgabe gemacht hat (siehe
/// AiService.buildInteractiveTask) – noch nicht gespeichert; der Nutzer
/// prüft und bearbeitet es vorher.
class InteractiveTaskDraft {
  const InteractiveTaskDraft({
    required this.kind,
    this.front = '',
    this.back = '',
    this.steps,
    this.gantt,
    this.reason = '',
  });

  /// null = die Aufgabe passt weder als Rechenweg noch als Terminierung.
  final InteractiveKind? kind;

  /// Die Aufgabe wortgetreu.
  final String front;

  /// Lösungsweg als Text (bei Terminierung schreibt ihn die App).
  final String back;
  final StepTask? steps;
  final GanttTask? gantt;

  /// Warum nicht geeignet (bei [kind] null).
  final String reason;

  bool get isUsable =>
      (kind == InteractiveKind.steps && (steps?.isUsable ?? false)) || (kind == InteractiveKind.gantt && gantt != null);

  Map<String, dynamic>? get taskData => switch (kind) {
        InteractiveKind.steps => steps?.toMap(),
        InteractiveKind.gantt => gantt?.toMap(),
        null => null,
      };
}
