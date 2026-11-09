import 'bom_task.dart';
import 'crystal_task.dart';
import 'drawing_task.dart';
import 'flashcard.dart';
import 'gantt_task.dart';
import 'phase_task.dart';
import 'sketch_task.dart';
import 'step_task.dart';

/// Welche interaktive Aufgabe aus einer Übungsaufgabe wird.
enum InteractiveKind {
  steps('Rechenweg', QuestionType.steps),
  gantt('Terminierung', QuestionType.gantt),
  crystal('Kristallgitter', QuestionType.crystal),
  bom('Stückliste', QuestionType.bom),
  sketch('Diagramm skizzieren', QuestionType.sketch),
  phase('Zustandsdiagramm', QuestionType.phase),
  drawing('Freihand-Skizze', QuestionType.drawing);

  const InteractiveKind(this.label, this.type);
  final String label;
  final QuestionType type;
}

InteractiveKind? interactiveKindFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase();
  // Vor "skizze" (Diagramm): Freihand, Gefüge zeichnen.
  if (v.contains('drawing') || v.contains('freihand') || v.contains('gefüge') || v.contains('gefuege') || v.contains('zeichnung')) {
    return InteractiveKind.drawing;
  }
  // Vor "diagramm" (Skizze): Zustandsdiagramm, Phasendiagramm, Zweistoffsystem.
  if (v.contains('phase') || v.contains('zustand') || v.contains('zweistoff') || v.contains('eutekt') || v.contains('hebelgesetz')) {
    return InteractiveKind.phase;
  }
  if (v.contains('gantt') || v.contains('termin') || v.contains('schedul')) return InteractiveKind.gantt;
  if (v.contains('crystal') || v.contains('kristall') || v.contains('miller') || v.contains('würfel') || v.contains('wuerfel')) {
    return InteractiveKind.crystal;
  }
  if (v.contains('bom') || v.contains('stückliste') || v.contains('stueckliste') || v.contains('stuckliste') || v.contains('erzeugnis')) {
    return InteractiveKind.bom;
  }
  if (v.contains('sketch') || v.contains('skizz') || v.contains('diagramm') || v.contains('kurve')) {
    return InteractiveKind.sketch;
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
    this.sketch,
    this.phase,
    this.drawing,
    this.reason = '',
    this.needs = '',
    this.incomplete = false,
    this.asQuestion = false,
    this.questionType = '',
    this.page,
    this.questionData,
    this.taskBox,
    this.solutionBoxes = const [],
  });

  /// Bereich der Aufgabenstellung auf ihrer Seite `[links, oben, rechts,
  /// unten]` (0–1) – das Aufgabenbild zeigt nur ihn, nie die Lösung.
  final List<double>? taskBox;

  /// Bereiche mit Lösung/Musterlösung auf der Seite – im Bild abgedeckt.
  final List<List<double>> solutionBoxes;

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
  final SketchTask? sketch;
  final PhaseTask? phase;
  final DrawingTask? drawing;

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

  /// Seite im Dokument (1-basiert), wenn ein ganzes Dokument gelesen wurde.
  final int? page;

  /// Fertige Quizfrage (normalisiert, siehe
  /// QuestionParsing.normalizeGeneratedFlashcard) – z.B. aus der JSON-Datei
  /// einer externen KI. Dann muss die App-KI die Frage nicht erst bauen.
  final Map<String, dynamic>? questionData;

  InteractiveTaskDraft withPage(int? page) => _copy(page: page);

  InteractiveTaskDraft withBoxes({List<double>? taskBox, List<List<double>> solutionBoxes = const []}) =>
      _copy(taskBox: taskBox, solutionBoxes: solutionBoxes);

  /// `[l, o, r, u]` mit Werten 0–1 aus der KI-Antwort, sonst null.
  static List<double>? boxOf(Object? raw) {
    if (raw is! List || raw.length != 4 || raw.any((v) => v is! num)) return null;
    final b = [for (final v in raw) (v as num).toDouble().clamp(0.0, 1.0)];
    return b[2] > b[0] && b[3] > b[1] ? b : null;
  }

  InteractiveTaskDraft withQuestionData(Map<String, dynamic>? data) => _copy(questionData: data);

  InteractiveTaskDraft _copy({
    Object? page = _keep,
    Object? questionData = _keep,
    Object? taskBox = _keep,
    Object? solutionBoxes = _keep,
  }) => InteractiveTaskDraft(
        kind: kind,
        front: front,
        back: back,
        steps: steps,
        gantt: gantt,
        crystal: crystal,
        bom: bom,
        sketch: sketch,
        phase: phase,
        drawing: drawing,
        reason: reason,
        needs: needs,
        incomplete: incomplete,
        asQuestion: asQuestion,
        questionType: questionType,
        page: page == _keep ? this.page : page as int?,
        questionData: questionData == _keep ? this.questionData : questionData as Map<String, dynamic>?,
        taskBox: taskBox == _keep ? this.taskBox : taskBox as List<double>?,
        solutionBoxes: solutionBoxes == _keep ? this.solutionBoxes : solutionBoxes as List<List<double>>,
      );

  static const _keep = Object();

  bool get isUsable => switch (kind) {
        InteractiveKind.steps => steps?.isUsable ?? false,
        InteractiveKind.gantt => gantt != null,
        InteractiveKind.crystal => crystal?.isUsable ?? false,
        InteractiveKind.bom => bom?.isUsable ?? false,
        InteractiveKind.sketch => sketch?.isUsable ?? false,
        InteractiveKind.phase => phase?.isUsable ?? false,
        InteractiveKind.drawing => drawing?.isUsable ?? false,
        null => false,
      };

  Map<String, dynamic>? get taskData => switch (kind) {
        InteractiveKind.steps => steps?.toMap(),
        InteractiveKind.gantt => gantt?.toMap(),
        InteractiveKind.crystal => crystal?.toMap(),
        InteractiveKind.bom => bom?.toMap(),
        InteractiveKind.sketch => sketch?.toMap(),
        InteractiveKind.phase => phase?.toMap(),
        InteractiveKind.drawing => drawing?.toMap(),
        null => null,
      };
}
