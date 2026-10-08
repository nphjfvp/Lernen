import 'bom_task.dart';
import 'crystal_task.dart';
import 'flashcard.dart';
import 'gantt_task.dart';
import 'step_task.dart';

/// Welche interaktive Aufgabe aus einer Übungsaufgabe wird.
enum InteractiveKind {
  steps('Rechenweg', QuestionType.steps),
  gantt('Terminierung', QuestionType.gantt),
  crystal('Kristallgitter', QuestionType.crystal),
  bom('Stückliste', QuestionType.bom);

  const InteractiveKind(this.label, this.type);
  final String label;
  final QuestionType type;
}

InteractiveKind? interactiveKindFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase();
  if (v.contains('gantt') || v.contains('termin') || v.contains('schedul')) return InteractiveKind.gantt;
  if (v.contains('crystal') || v.contains('kristall') || v.contains('miller') || v.contains('würfel') || v.contains('wuerfel')) {
    return InteractiveKind.crystal;
  }
  if (v.contains('bom') || v.contains('stückliste') || v.contains('stueckliste') || v.contains('stuckliste') || v.contains('erzeugnis')) {
    return InteractiveKind.bom;
  }
  if (v.contains('step') || v.contains('rechen') || v.contains('schritt')) return InteractiveKind.steps;
  return null;
}

/// Was die KI aus einer (Teil-)Aufgabe gemacht hat (siehe
/// AiService.buildInteractiveTasks) – noch nicht gespeichert; der Nutzer
/// prüft und bearbeitet es vorher.
class InteractiveTaskDraft {
  const InteractiveTaskDraft({
    required this.kind,
    this.front = '',
    this.back = '',
    this.steps,
    this.gantt,
    this.crystal,
    this.bom,
    this.reason = '',
    this.needs = '',
    this.incomplete = false,
    this.asQuestion = false,
    this.questionType = '',
  });

  /// null = die Aufgabe passt (noch) nicht als interaktive Aufgabe.
  final InteractiveKind? kind;

  /// Die Aufgabe wortgetreu.
  final String front;

  /// Lösungsweg als Text (bei Terminierung schreibt ihn die App).
  final String back;
  final StepTask? steps;
  final GanttTask? gantt;
  final CrystalTask? crystal;
  final BomTask? bom;

  /// Warum nicht geeignet (bei [kind] null).
  final String reason;

  /// Welche Bedienart fehlt, damit es ginge ("Kurve in Diagramm zeichnen").
  final String needs;

  /// Die KI hat eine Art genannt, die Daten aber nicht vollständig geliefert
  /// (dann gehört die Aufgabe nicht auf die Sammelliste – erneut versuchen).
  final bool incomplete;

  /// Passt nicht interaktiv, aber als normale Quizfrage (Freitext, Auswahl,
  /// Zuordnen, Tabelle, Bild markieren …) – die App hat dafür schon
  /// Fragetypen; gehört dann NICHT auf die Sammelliste.
  final bool asQuestion;

  /// Vorschlag der KI für den Fragetyp (z.B. "free_text"), nur zur Anzeige.
  final String questionType;

  bool get isUsable => switch (kind) {
        InteractiveKind.steps => steps?.isUsable ?? false,
        InteractiveKind.gantt => gantt != null,
        InteractiveKind.crystal => crystal?.isUsable ?? false,
        InteractiveKind.bom => bom?.isUsable ?? false,
        null => false,
      };

  Map<String, dynamic>? get taskData => switch (kind) {
        InteractiveKind.steps => steps?.toMap(),
        InteractiveKind.gantt => gantt?.toMap(),
        InteractiveKind.crystal => crystal?.toMap(),
        InteractiveKind.bom => bom?.toMap(),
        null => null,
      };
}
