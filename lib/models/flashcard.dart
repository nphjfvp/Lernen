import 'dart:math';

/// Die Darstellungsform einer Karte. `flashcard` ist die ursprüngliche
/// offene Vorderseite/Rückseite-Karte (selbst bewertet); alle anderen sind
/// automatisch auswertbare Fragetypen (siehe AnswerChecker).
enum QuestionType {
  flashcard,
  singleChoice,
  multipleChoice,
  freeText,
  fillBlank,
  dragDrop,
  dragCategory,
  html,

  /// Bild beschriften: Beschriftungen auf die richtigen Stellen eines Bildes
  /// ziehen (aus der Vorgänger-App, dort `diagram_label`).
  diagramLabel,

  /// Bild markieren: die richtige Stelle im Bild antippen (Vorgänger-App:
  /// `mark_image`).
  markImage,

  /// Tabelle ausfüllen: vorgegebene Zellen stehen fest, die übrigen werden
  /// eingetippt (siehe [QuestionTableCell], [Flashcard.tableRows]).
  table,

  /// Aufgabe zum Verstehen: für Aufgaben, die sich in einer Quiz-App nicht
  /// prüfen lassen (zeichnen, entwerfen, lange Rechen- und Herleitungswege,
  /// programmieren …). [Flashcard.front] ist die Aufgabe 1:1 wie im
  /// Dokument, [Flashcard.back] die Erklärung/der Lösungsweg der KI – der
  /// Lernende bewertet selbst, wie gut er es verstanden hat. Alle dieser
  /// Aufgaben liegen zusätzlich dauerhaft im Aufgaben-Ordner des Fachs.
  learn,

  /// Rechenweg: eine Rechenaufgabe in Schritten (Auswahl, Formeln, Zahlen) –
  /// die App rechnet jede Antwort selbst nach (Einsetzen an Stützstellen,
  /// Probe), siehe StepTask (step_task.dart) in [Flashcard.taskData].
  steps,

  /// Terminierung: Vorwärts-/Rückwärtsterminierung im Gantt-Diagramm mit
  /// Start-/Endterminen und Liegezeiten – die App rechnet die Lösung selbst,
  /// siehe GanttTask (gantt_task.dart) in [Flashcard.taskData].
  gantt,

  /// Kristallgitter: Richtungen und Ebenen im Einheitswürfel einzeichnen oder
  /// ablesen, Familien, Atome in einer Ebene – die App prüft selbst, siehe
  /// CrystalTask (crystal_task.dart) in [Flashcard.taskData].
  crystal,

  /// Stückliste: aus einem Erzeugnisbaum Mengenübersichts-, Struktur- oder
  /// Baukastenstückliste aufstellen – die App rechnet die Listen selbst,
  /// siehe BomTask (bom_task.dart) in [Flashcard.taskData].
  bom,

  /// Diagramm skizzieren: in vorgegebene Achsen eine Kurve zeichnen und
  /// Kennwerte markieren – die App prüft grob die Merkmale (Sprung, Maximum
  /// …), siehe SketchTask (sketch_task.dart) in [Flashcard.taskData].
  sketch,

  /// Zustandsdiagramm: Zweistoffsystem mit Eutektikum/Eutektoid – Phasen,
  /// Hebelgesetz, Gefügeanteile, Abkühlkurven, Gebiete; die App rechnet aus
  /// den Eckdaten selbst, siehe PhaseTask (phase_task.dart) in
  /// [Flashcard.taskData].
  phase,
}

/// Interaktive Aufgabentypen, deren Daten (`taskData`) ihren Typ als `kind`
/// mitführen.
const _taskTypes = {
  QuestionType.steps,
  QuestionType.gantt,
  QuestionType.crystal,
  QuestionType.bom,
  QuestionType.sketch,
  QuestionType.phase,
};

/// Typ einer gespeicherten Karte. Eine ältere App-Version kennt neue
/// Aufgabentypen nicht, zeigt sie als Karteikarte und speichert sie beim
/// Lernen auch so (über den Sync landet das auf allen Geräten) – die
/// Aufgabendaten bleiben dabei erhalten. Steht dort ein bekannter
/// Aufgabentyp, wird die Karte wieder zur interaktiven Aufgabe.
QuestionType _storedType(Map<String, dynamic> map) {
  final type = questionTypeFromString(map['type'] as String?);
  final data = map['taskData'];
  if (type != QuestionType.flashcard || data is! Map) return type;
  final kind = '${data['kind'] ?? ''}';
  return _taskTypes.where((t) => t.name == kind).firstOrNull ?? type;
}

QuestionType questionTypeFromString(String? value) => QuestionType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => QuestionType.flashcard,
    );

extension QuestionTypeLabel on QuestionType {
  String get label => switch (this) {
        QuestionType.flashcard => 'Karteikarte',
        QuestionType.singleChoice => 'Single Choice',
        QuestionType.multipleChoice => 'Multiple Choice',
        QuestionType.freeText => 'Freitext',
        QuestionType.fillBlank => 'Lückentext',
        QuestionType.dragDrop => 'Zuordnen',
        QuestionType.dragCategory => 'Kategorien',
        QuestionType.html => 'Interaktiv',
        QuestionType.diagramLabel => 'Bild beschriften',
        QuestionType.markImage => 'Bild markieren',
        QuestionType.table => 'Tabelle',
        QuestionType.learn => 'Lernen',
        QuestionType.steps => 'Rechenweg',
        QuestionType.gantt => 'Terminierung',
        QuestionType.crystal => 'Kristallgitter',
        QuestionType.bom => 'Stückliste',
        QuestionType.sketch => 'Diagramm skizzieren',
        QuestionType.phase => 'Zustandsdiagramm',
      };
}

/// Ein Ziel auf dem Bild einer Bildfrage ([QuestionType.diagramLabel]/
/// [QuestionType.markImage]) in Koordinaten relativ zum Bild (0..1, Ursprung
/// oben links). Beim Beschriften ein Punkt ([x]/[y]) mit [label] – dorthin
/// gehört die Beschriftung; beim Markieren ein Bereich der Größe [w]×[h] um
/// den Mittelpunkt [x]/[y], in den getippt werden muss. Beim Beschriften
/// kann [w]×[h] die Fläche der (abgedeckten) Original-Beschriftung sein –
/// dort sitzt dann das Ablagefeld.
class ImageTarget {
  const ImageTarget({
    required this.x,
    required this.y,
    this.w = 0,
    this.h = 0,
    this.label = '',
    this.group = '',
  });

  final double x;
  final double y;
  final double w;
  final double h;
  final String label;

  /// Beschriften: Stellen mit derselben (nicht leeren) Gruppe sind
  /// austauschbar – z.B. fünf Eingänge eines Prozesses, deren Reihenfolge
  /// egal ist. Jede Beschriftung der Gruppe darf dann auf jeder ihrer
  /// Stellen stehen, solange jede genau einmal vorkommt.
  final String group;

  /// Liegt der Punkt [px]/[py] im Bereich (plus [tolerance] je Seite)?
  bool contains(double px, double py, {double tolerance = 0.02}) =>
      (px - x).abs() <= w / 2 + tolerance && (py - y).abs() <= h / 2 + tolerance;

  ImageTarget copyWith({double? x, double? y, double? w, double? h, String? label, String? group}) => ImageTarget(
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        label: label ?? this.label,
        group: group ?? this.group,
      );

  Map<String, dynamic> toMap() => {
        'x': x,
        'y': y,
        if (w > 0) 'w': w,
        if (h > 0) 'h': h,
        if (label.isNotEmpty) 'label': label,
        if (group.isNotEmpty) 'group': group,
      };

  /// Tolerant: Zahlen auch als Text, Werte auf 0..1 begrenzt; ein Kreis der
  /// Vorgänger-App (`radius`) wird zum umschließenden Quadrat. Die KI darf
  /// statt eines Punkts den Kasten der Beschriftung liefern (`box` =
  /// [links, oben, rechts, unten]). Koordinaten in Prozent (0..100) oder
  /// Promille (0..1000, z.B. Gemini) werden erkannt und umgerechnet.
  factory ImageTarget.fromMap(Map<String, dynamic> map) {
    double? number(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    final box = map['box'] is List ? [for (final v in map['box'] as List) number(v)] : null;
    final raw = [
      for (final key in const ['x', 'y', 'w', 'h', 'radius']) number(map[key]),
      ...?box,
    ].whereType<double>();
    final largest = raw.isEmpty ? 0.0 : raw.map((v) => v.abs()).reduce(max);
    // Knapp über 1 ist Rundungsüberschuss (wird begrenzt), erst deutlich
    // größere Werte sind Prozent bzw. Promille.
    final scale = largest <= 2.0 ? 1.0 : (largest <= 100 ? 100.0 : 1000.0);
    double norm(double? v) => ((v ?? 0) / scale).clamp(0.0, 1.0).toDouble();
    double read(String key) => norm(number(map[key]));

    final label = (map['label'] ?? map['text'] ?? '').toString().trim();
    final group = (map['group'] ?? '').toString().trim();
    if (box != null && box.length == 4 && box.every((v) => v != null)) {
      final left = min(norm(box[0]), norm(box[2])), right = max(norm(box[0]), norm(box[2]));
      final top = min(norm(box[1]), norm(box[3])), bottom = max(norm(box[1]), norm(box[3]));
      return ImageTarget(
        x: (left + right) / 2,
        y: (top + bottom) / 2,
        w: right - left,
        h: bottom - top,
        label: label,
        group: group,
      );
    }
    // Vieleck der Vorgänger-App: umschließendes Rechteck.
    final points = map['points'];
    if (points is List && points.isNotEmpty) {
      final xs = <double>[];
      final ys = <double>[];
      for (final p in points) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          xs.add((p[0] as num).toDouble().clamp(0.0, 1.0));
          ys.add((p[1] as num).toDouble().clamp(0.0, 1.0));
        }
      }
      if (xs.isNotEmpty) {
        final left = xs.reduce(min), right = xs.reduce(max), top = ys.reduce(min), bottom = ys.reduce(max);
        return ImageTarget(
          x: (left + right) / 2,
          y: (top + bottom) / 2,
          w: right - left,
          h: bottom - top,
          label: label,
          group: group,
        );
      }
    }
    final radius = read('radius');
    return ImageTarget(
      x: read('x'),
      y: read('y'),
      w: map.containsKey('w') ? read('w') : radius * 2,
      h: map.containsKey('h') ? read('h') : radius * 2,
      label: label,
      group: group,
    );
  }
}

/// Eine Antwortmöglichkeit bei Single-/Multiple-Choice.
class QuizOption {
  const QuizOption({required this.text, required this.isCorrect});

  final String text;
  final bool isCorrect;

  Map<String, dynamic> toMap() => {'text': text, 'isCorrect': isCorrect};

  /// Tolerant gegenüber importierten/älteren Daten (fehlender Text,
  /// `isCorrect` als 1 oder "true") statt beim Laden abzustürzen.
  factory QuizOption.fromMap(Map<String, dynamic> map) {
    final isCorrect = map['isCorrect'];
    return QuizOption(
      text: map['text']?.toString() ?? '',
      isCorrect: isCorrect == true || isCorrect == 1 || const {'true', '1'}.contains(isCorrect?.toString()),
    );
  }
}

/// Ein Zuordnungspaar bei drag_drop (Begriff -> Ziel) bzw. drag_category
/// (Begriff -> Kategoriename).
class DragPair {
  const DragPair({required this.source, required this.target});

  final String source;
  final String target;

  Map<String, dynamic> toMap() => {'source': source, 'target': target};

  factory DragPair.fromMap(Map<String, dynamic> map) => DragPair(
        source: map['source']?.toString() ?? '',
        target: map['target']?.toString() ?? '',
      );
}

/// Eine Zelle einer Tabellen-Frage ([QuestionType.table]): vorgegeben
/// ([given], wird angezeigt) oder auszufüllen – dann ist [text] die Lösung,
/// mehrere akzeptierte Schreibweisen durch ";" getrennt.
class QuestionTableCell {
  const QuestionTableCell({required this.text, this.given = true});

  final String text;
  final bool given;

  Map<String, dynamic> toMap() => {'t': text, if (!given) 'fill': true};

  /// Tolerant für gespeicherte Daten und KI-Antworten: ein Text ist
  /// vorgegeben, "[[Lösung]]" auszufüllen; als Objekt zählt `fill: true`,
  /// `given: false` oder ein Feld `answer`/`solution` als auszufüllen.
  factory QuestionTableCell.parse(Object? raw) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final answer = map['answer'] ?? map['solution'] ?? map['loesung'] ?? map['lösung'];
      final text = (answer ?? map['t'] ?? map['text'] ?? map['value'] ?? '').toString().trim();
      final fill = answer != null || map['fill'] == true || map['given'] == false || map['blank'] == true;
      return QuestionTableCell(text: text, given: !fill);
    }
    final text = (raw ?? '').toString().trim();
    final marked = RegExp(r'^\[\[(.*)\]\]$', dotAll: true).firstMatch(text);
    if (marked != null) return QuestionTableCell(text: marked.group(1)!.trim(), given: false);
    return QuestionTableCell(text: text);
  }
}

/// Liest die Zeilen einer Tabellen-Frage tolerant; leere Zeilen fallen weg,
/// `null`, wenn keine Zeile übrig bleibt. Zeilen dürfen verschieden lang
/// sein (die Anzeige füllt auf).
List<List<QuestionTableCell>>? parseTableRows(Object? raw) {
  if (raw is! List) return null;
  final rows = [
    for (final row in raw)
      if (row is List && row.isNotEmpty) [for (final cell in row) QuestionTableCell.parse(cell)],
  ];
  return rows.isEmpty ? null : rows;
}

List<List<Map<String, dynamic>>>? _tableRowsToMap(List<List<QuestionTableCell>>? rows) =>
    rows?.map((r) => r.map((c) => c.toMap()).toList()).toList();

/// Liest die Daten einer interaktiven Aufgabe ([Flashcard.taskData])
/// tolerant: nur eine Map zählt, sonst `null`.
Map<String, dynamic>? parseTaskData(Object? raw) => raw is Map && raw.isNotEmpty ? Map<String, dynamic>.from(raw) : null;

/// Momentaufnahme des Karten-Inhalts EINER Eskalationsstufe, angelegt kurz
/// bevor [Flashcard.copyWithPromotedVariant] ihn durch die nächste
/// (schwerere) Stufe überschreibt. Grundlage für
/// [Flashcard.copyWithDemotedVariant]: hält ein Nutzer eine Stufe dauerhaft
/// nicht mehr, kommt so wieder GENAU der alte Wortlaut zurück, ohne dafür
/// erneut die KI bemühen zu müssen.
class VariantSnapshot {
  const VariantSnapshot({
    required this.type,
    required this.front,
    required this.back,
    this.options,
    this.correctText,
    this.blanks,
    this.dragPairs,
    this.htmlContent,
    this.imageBase64,
    this.imageTargets,
    this.tableRows,
    this.taskData,
  });

  final QuestionType type;
  final String front;
  final String back;
  final List<QuizOption>? options;
  final String? correctText;
  final List<String>? blanks;
  final List<DragPair>? dragPairs;
  final String? htmlContent;
  final String? imageBase64;
  final List<ImageTarget>? imageTargets;
  final List<List<QuestionTableCell>>? tableRows;
  final Map<String, dynamic>? taskData;

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'front': front,
        'back': back,
        'options': options?.map((o) => o.toMap()).toList(),
        'correctText': correctText,
        'blanks': blanks,
        'dragPairs': dragPairs?.map((p) => p.toMap()).toList(),
        'htmlContent': htmlContent,
        'imageBase64': imageBase64,
        'imageTargets': imageTargets?.map((t) => t.toMap()).toList(),
        'tableRows': _tableRowsToMap(tableRows),
        'taskData': taskData,
      };

  factory VariantSnapshot.fromMap(Map<String, dynamic> map) => VariantSnapshot(
        type: questionTypeFromString(map['type'] as String?),
        front: map['front']?.toString() ?? '',
        back: map['back']?.toString() ?? '',
        options: (map['options'] as List?)
            ?.map((o) => QuizOption.fromMap(Map<String, dynamic>.from(o as Map)))
            .toList(),
        correctText: map['correctText'] as String?,
        blanks: (map['blanks'] as List?)?.map((b) => b.toString()).toList(),
        dragPairs: (map['dragPairs'] as List?)
            ?.map((p) => DragPair.fromMap(Map<String, dynamic>.from(p as Map)))
            .toList(),
        htmlContent: map['htmlContent'] as String?,
        imageBase64: map['imageBase64'] as String?,
        imageTargets: parseImageTargets(map['imageTargets']),
        tableRows: parseTableRows(map['tableRows']),
        taskData: parseTaskData(map['taskData']),
      );
}

/// Liest eine Liste von [ImageTarget]s tolerant; `null`, wenn keine da sind.
List<ImageTarget>? parseImageTargets(Object? raw) {
  if (raw is! List) return null;
  final targets = [
    for (final t in raw)
      if (t is Map) ImageTarget.fromMap(Map<String, dynamic>.from(t)),
  ];
  return targets.isEmpty ? null : targets;
}

/// Eine Karteikarte/Frage fürs Daily Quiz. Trägt ihren eigenen Spaced-
/// Repetition-Zustand direkt auf dem Datensatz (statt einer separaten
/// Review-Tabelle), das hält die App schlank.
///
/// [front] ist bei allen Fragetypen die Fragestellung; was als "Antwort"
/// zählt, hängt vom [type] ab: bei `flashcard` ist es [back] (offen, selbst
/// bewertet), bei den übrigen Typen [options]/[correctText]/[blanks]/
/// [dragPairs] (automatisch ausgewertet, siehe AnswerChecker).
///
/// [variantChain] macht eine Frage Teil einer Schwierigkeits-Eskalation
/// (z.B. Single-Choice -> Lückentext -> Freitext): ist die aktuelle Stufe in
/// der Ampel grün, wird die Frage in den nächsten Typ der Kette umgewandelt
/// (Inhalt aus [pendingVariants] oder lazy per KI) und [variantLevel]
/// erhöht. Nach mehreren Fehlversuchen in Folge wird automatisch eine
/// Stufe zurückgestuft (siehe [copyWithBoxUpdate]/[copyWithDemotedVariant])
/// – Adaptivität in BEIDE Richtungen statt nur aufwärts. `null` bei
/// [variantChain] bedeutet: kein Eskalations-Typ, die Frage bleibt
/// dauerhaft in ihrem [type].
class Flashcard {
  final String id;
  final String moduleId;
  final String? conceptId;
  final String front;
  final String back;
  final DateTime createdAt;

  final QuestionType type;
  final List<QuizOption>? options;
  final String? correctText;
  final List<String>? blanks;
  final List<DragPair>? dragPairs;

  /// Selbstständige HTML/CSS/JS-Seite für [QuestionType.html] (siehe
  /// AiService-Prompts für den genauen Vertrag: die Seite prüft ihre eigene
  /// Antwort und meldet das Ergebnis über einen JavaScript-Kanal zurück,
  /// die App muss dafür nicht online sein). Nur auf Plattformen mit
  /// WebView-Unterstützung (Android/iOS) tatsächlich interaktiv gerendert;
  /// [front]/[back] dienen überall sonst (Windows/Web/Fehlerfall) als
  /// Fallback-Anzeige mit manueller Selbstbewertung wie beim einfachen
  /// `flashcard`-Typ (siehe QuestionAnswerView).
  final String? htmlContent;

  /// Base64-kodierter Screenshot der Vorlesungsseite, aus der diese Frage
  /// erzeugt wurde (siehe PageQuestionCreationSheet/
  /// AiService.generateQuestionsFromPage) – NICHT bei jeder Karte gesetzt,
  /// sondern nur, wenn das Vision-Modell die Seite selbst als "needsImage"
  /// markiert hat (z.B. ein Diagramm/eine Grafik, ohne die die Frage keinen
  /// Sinn ergibt) – rein textbasierte Fragen bekommen bewusst KEIN Bild
  /// angehängt, um die lokale Datenbank nicht unnötig aufzublähen. Wird in
  /// [QuestionAnswerView] oberhalb der Frage angezeigt, wenn gesetzt.
  final String? imageBase64;

  /// Ziele auf [imageBase64] für die Bildfragen ([QuestionType.diagramLabel]:
  /// Beschriftungen mit Position, [QuestionType.markImage]: Bereiche).
  final List<ImageTarget>? imageTargets;

  /// Zeilen einer Tabellen-Frage ([QuestionType.table]); die erste Zeile ist
  /// meist die Kopfzeile (lauter vorgegebene Zellen).
  final List<List<QuestionTableCell>>? tableRows;

  /// Daten einer interaktiven Aufgabe: Rechenweg ([QuestionType.steps],
  /// StepTask), Terminierung ([QuestionType.gantt], GanttTask) bzw.
  /// Kristallgitter ([QuestionType.crystal], CrystalTask) bzw. Stückliste
  /// ([QuestionType.bom], BomTask) bzw. Skizze ([QuestionType.sketch],
  /// SketchTask) – als Map
  /// gespeichert, damit Sync, Export und Kopien sie unverändert mitnehmen.
  final Map<String, dynamic>? taskData;

  final List<QuestionType>? variantChain;
  final int variantLevel;

  /// Richtige Antworten in Folge auf der aktuellen Stufe (falsch: −1). Nur
  /// noch informativ – über die Beförderung entscheidet die Ampel
  /// ([masteryBox], siehe [copyWithBoxUpdate]).
  final int variantBox;

  /// Inhalt jeder bereits verlassenen, leichteren Eskalationsstufe, in der
  /// Reihenfolge, in der sie durchlaufen wurden (letzter Eintrag = zuletzt
  /// verlassene Stufe, direkt unter der aktuellen). Wird bei jeder
  /// Beförderung um einen Eintrag länger, bei jeder Rückstufung um einen
  /// kürzer.
  final List<VariantSnapshot>? variantHistory;

  /// Bereits vorbereiteter (aber noch nicht erreichter) Inhalt für die
  /// NÄCHSTEN Eskalationsstufen, in der Reihenfolge, in der sie als Nächstes
  /// erreicht werden (erster Eintrag = direkt nächste Stufe). Nur gesetzt,
  /// wenn der komplette Inhalt aller Stufen schon beim Erstellen bekannt war
  /// (siehe PageQuestionCreationSheet: EIN KI-Aufruf erzeugt dort direkt alle
  /// gewählten Schwierigkeitsgrade auf einmal, jeweils gegründet auf
  /// denselben Seiten-Screenshot). [copyWithBoxUpdate] nutzt diesen Inhalt
  /// dann bei einer Beförderung direkt, OHNE weiteren (schwächer
  /// gegründeten, nur textbasierten) KI-Aufruf wie sonst über
  /// AiService.generateHarderVariant. Wird bei einer Rückstufung
  /// ([copyWithDemotedVariant]) automatisch um die gerade verlassene Stufe
  /// ergänzt (Spiegelbild zu [variantHistory]), damit ein späteres
  /// Wiedererreichen erneut denselben, bereits bekannten Inhalt nutzt statt
  /// die KI erneut zu bemühen.
  final List<VariantSnapshot>? pendingVariants;

  /// Anzahl FALSCHER Antworten in Folge auf der aktuellen Stufe (jede
  /// richtige Antwort setzt ihn auf 0 zurück) – für ALLE Karten, nicht nur
  /// Stufenketten. Steuert die Fehler-Leiter: ab [hintMissStreak] eine
  /// KI-Hilfestellung, ab [secondHintMissStreak] eine zweite, ab
  /// [fallbackMissStreak] zurück zur leichteren Stufe (siehe
  /// [copyWithBoxUpdate] bzw. StageGate.reactivateEasier).
  final int variantMissStreak;

  /// Generischer Leitner-Zähler für die Wissensstand-Ampel (siehe
  /// MasteryService), UNABHÄNGIG von [variantBox] (das ist rein für die
  /// Typ-Eskalationskette reserviert). Steigt bei jeder Antwort, die als
  /// "gewusst" zählt (FSRS-Grade good/easy) um 1 (Obergrenze
  /// [masteryBoxCap]), sinkt sonst um 1 (Boden 0) – siehe FsrsService.review.
  /// Grund: die reine FSRS-Retrievability ist direkt nach jeder Wiederholung
  /// per Definition ~100% (Vergessenskurve bei Elapsed-Zeit 0), zwei schnell
  /// aufeinanderfolgende (ggf. geratene) richtige Antworten würden sonst
  /// sofort als "Gut" (grün) durchgehen. Erst mehrere, tatsächlich über
  /// mehrere Sessions verteilte erfolgreiche Wiederholungen zählen als
  /// nachgewiesenes Wissen (analog zur "mature"-Einstufung der Vorgänger-App).
  final int masteryBox;

  // FSRS-Zustand
  final DateTime due;
  final double stability;
  final double difficulty;
  final int elapsedDays;
  final int scheduledDays;
  final int reps;
  final int lapses;
  final String state; // new | learning | review | relearning
  final DateTime? lastReview;

  /// Welcher Vorlesungseinheit (siehe LectureUnit) diese Karte zugeordnet
  /// ist – übernommen vom Konzept/Material, aus dem sie generiert wurde.
  /// Null = keine Einheit (ältere Karten, oder ohne Einheiten-Auswahl
  /// generiert) – solche Karten bleiben immer verfügbar. Ist eine Einheit
  /// gesetzt, aber (noch) nicht als "behandelt" markiert, lässt der
  /// DailyScheduler die Karte aus (siehe DailySchedulerService.buildPlan) –
  /// AUSSER [priorityIntroduction] ist gesetzt.
  final String? unitId;

  /// true für Karten, die der Nutzer gezielt JETZT beim Betrachten einer
  /// Seite selbst erstellt hat (siehe PageQuestionCreationSheet/"Frage
  /// erstellen"), statt aus einer Bulk-Generierung (Nachbereiten-Modus)
  /// hervorzugehen. Zwei Konsequenzen in [DailySchedulerService.buildPlan]:
  /// (1) umgeht das Einheiten-"behandelt"-Gate, das eigentlich verhindern
  /// soll, dass automatisch generierter Stoff künftiger (noch nicht
  /// gehaltener) Vorlesungen ungefragt im Daily Quiz auftaucht – eine
  /// einzelne, bewusst gerade jetzt gestellte Frage ist per Definition schon
  /// "aktuell relevant", unabhängig vom Einheiten-Status. (2) wird beim
  /// Auffüllen des Tages-Budgets VOR der reinen createdAt-Reihenfolge
  /// einsortiert, damit eine frisch erstellte Frage nicht hinter einem
  /// großen Altbestand noch nicht eingeführter Karten verschwindet und erst
  /// nach Tagen drankommt.
  final bool priorityIntroduction;

  /// Rechenaufgabe: zur Lösung braucht man Taschenrechner bzw. echtes Rechnen
  /// (nicht 2·3). `true`/`false` = von der KI beim Erstellen gesetzt oder von
  /// Hand festgelegt; `null` = unbekannt, dann entscheidet die Erkennung im
  /// Text (siehe CalcTaskDetector). Grundlage für den Schalter "Rechenaufgaben"
  /// in Daily Quiz, Üben, Sprint und Speedrun.
  final bool? needsCalculator;

  /// Seit wann diese Rechenaufgabe zurückgestellt ist, weil ohne Rechenaufgaben
  /// gelernt wurde (Schalter aus). Sobald sie wieder dabei sind, kommen solche
  /// Karten zuerst und zusätzlich zum Tagesbudget dran; beim Beantworten wird
  /// das Feld wieder gelöscht.
  final DateTime? calcDeferredAt;

  /// Wo die Frage in den Lernunterlagen steht: Material (siehe MaterialItem)
  /// und Seite (1-basiert) – gesetzt, wenn die Karte aus einer bestimmten
  /// Seite entstanden ist (Frage erstellen, PDF-Import) oder die Stelle
  /// später gefunden wurde (siehe SourceLocator). Grundlage für "Im Skript
  /// ansehen".
  final String? sourceMaterialId;
  final int? sourcePage;

  /// Wo im SKRIPT (Vorlesungsfolien) die Erklärung bzw. Lösung zu dieser
  /// Frage steht – gefunden per Abgleich nach dem Erstellen (siehe
  /// ScriptMatchService). Nötig, weil [sourceMaterialId] bei Fragen aus
  /// Übungsblättern nur aufs Übungsblatt zeigt. [scriptPage] 0 = gesucht,
  /// aber nichts gefunden (dann nicht bei jedem Lauf erneut suchen); null =
  /// noch nicht gesucht.
  final String? scriptMaterialId;
  final int? scriptPage;

  /// Eine Fundstelle im Skript ist bekannt.
  bool get hasScript => scriptMaterialId != null && (scriptPage ?? 0) > 0;

  /// Der Abgleich mit dem Skript ist schon gelaufen (mit oder ohne Treffer).
  bool get scriptSearched => scriptPage != null;

  /// Einmal erzeugte kurze Lerneinheit zur Frage (siehe
  /// AiService.generateMiniLesson) – gespeichert, damit sie beim nächsten
  /// Mal sofort da ist und mit synchronisiert.
  final String? miniLesson;

  /// Wie oft diese Karte im Vergleich zu anderen drankommen soll: skaliert
  /// das von FsrsService.review() berechnete Wiederholungsintervall (höheres
  /// Gewicht -> kürzeres Intervall -> die Karte wird häufiger fällig). Neu
  /// erzeugte Karten bekommen automatisch einen sinnvollen Standardwert nach
  /// ihrer Quelle (siehe `defaultFlashcardWeightFor` in material_item.dart:
  /// Folien-Fragen 1.0, Übungsaufgaben aus Übungsblättern 1.5), lässt sich
  /// aber jederzeit von Hand in der Kartenliste anpassen (siehe
  /// [copyWithWeight]). Wirkt zusammen mit [Module.weight] multiplikativ
  /// (siehe CardReviewMixin.recordReview). Bei 0 ist die Karte
  /// stummgeschaltet (siehe [isMuted]).
  final double weight;

  /// Schwierigkeitsstufe innerhalb der Gruppe (0 = leicht, 1 = mittel,
  /// 2 = schwer), gesetzt beim Erstellen, per KI-Zuordnung oder von Hand.
  /// Null = aus dem Fragetyp abgeleitet (siehe StageGate.levelOf).
  final int? stageLevel;

  /// Welche Karten Leicht/Mittel/Schwer DERSELBEN Frage bzw. desselben Themas
  /// sind (siehe StageGate): gesetzt per KI-Zuordnung oder von Hand. Null =
  /// das Konzept der Karte ([conceptId]); ohne beides steht die Karte allein.
  final String? stageGroup;

  /// KI-Hilfestellungen für die aktuelle Stufe, erzeugt nach wiederholten
  /// Fehlern (siehe [hintMissStreak]) und gespeichert, damit sie beim
  /// nächsten Mal sofort (auch offline) da sind. Bei einem Stufenwechsel
  /// verworfen – sie gehören zu genau dieser Fragestellung.
  final List<String>? aiHints;

  const Flashcard({
    required this.id,
    required this.moduleId,
    this.conceptId,
    required this.front,
    required this.back,
    required this.createdAt,
    required this.due,
    this.type = QuestionType.flashcard,
    this.options,
    this.correctText,
    this.blanks,
    this.dragPairs,
    this.htmlContent,
    this.imageBase64,
    this.imageTargets,
    this.tableRows,
    this.taskData,
    this.variantChain,
    this.variantLevel = 0,
    this.variantBox = 0,
    this.variantHistory,
    this.pendingVariants,
    this.variantMissStreak = 0,
    this.masteryBox = 0,
    this.stability = 0,
    this.difficulty = 0,
    this.elapsedDays = 0,
    this.scheduledDays = 0,
    this.reps = 0,
    this.lapses = 0,
    this.state = 'new',
    this.lastReview,
    this.unitId,
    this.priorityIntroduction = false,
    this.needsCalculator,
    this.calcDeferredAt,
    this.sourceMaterialId,
    this.sourcePage,
    this.scriptMaterialId,
    this.scriptPage,
    this.miniLesson,
    this.weight = 1.0,
    this.stageLevel,
    this.stageGroup,
    this.aiHints,
  });

  /// Kanonische Antwort-Darstellung, unabhängig vom Fragetyp - Grundlage,
  /// wenn eine harte Variante daraus erzeugt wird (siehe
  /// AiService.generateHarderVariant), damit sich der geprüfte Fakt dabei
  /// nicht ändert.
  /// Die Frage so, wie sie beim Lernen zu sehen ist, als Text für KI-
  /// Hilfen (Tipp, Erklärung, Sokrates): bei Auswahlfragen mit den Optionen,
  /// bei Tabellen mit der Tabelle ("___" = auszufüllen) – der Fragetext
  /// allein ("Fülle die Tabelle aus") gäbe der KI zu wenig Zusammenhang.
  String get promptText => switch (type) {
        QuestionType.singleChoice || QuestionType.multipleChoice when (options ?? const []).isNotEmpty =>
          '$front\nAntwortoptionen: ${options!.map((o) => o.text).join(' | ')}',
        QuestionType.dragDrop || QuestionType.dragCategory when (dragPairs ?? const []).isNotEmpty =>
          '$front\nBegriffe: ${dragPairs!.map((p) => p.source).where((s) => s.trim().isNotEmpty).join(' | ')}',
        QuestionType.table when (tableRows ?? const []).isNotEmpty => [
            front,
            for (final row in tableRows!) row.map((c) => c.given ? c.text : '___').join(' | '),
          ].join('\n'),
        _ => front,
      };

  String get answerSummary => switch (type) {
        // Rechenweg/Terminierung: back ist der lesbare Lösungsweg (beim
        // Erstellen/Bearbeiten aus der Aufgabe geschrieben).
        QuestionType.flashcard ||
        QuestionType.learn ||
        QuestionType.steps ||
        QuestionType.gantt ||
        QuestionType.crystal ||
        QuestionType.bom ||
        QuestionType.sketch ||
        QuestionType.phase =>
          back,
        QuestionType.singleChoice ||
        QuestionType.multipleChoice =>
          (options ?? const []).where((o) => o.isCorrect).map((o) => o.text).join('; '),
        QuestionType.freeText => correctText ?? '',
        // Varianten einer Lücke ("a; b") als "a / b" – sonst wären sie von
        // den übrigen Lücken nicht zu unterscheiden.
        QuestionType.fillBlank => (blanks ?? const [])
            .map((b) => b.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).join(' / '))
            .where((b) => b.isNotEmpty)
            .join('; '),
        QuestionType.dragDrop ||
        QuestionType.dragCategory =>
          (dragPairs ?? const []).map((p) => '${p.source} -> ${p.target}').join('; '),
        // Die Antwort-Prüfung steckt in htmlContent selbst (siehe dort) -
        // back dient hier nur als textuelle Kurzfassung/Fallback-Anzeige.
        QuestionType.html => back,
        QuestionType.diagramLabel =>
          (imageTargets ?? const []).map((t) => t.label).where((l) => l.isNotEmpty).join(', '),
        QuestionType.markImage => back.trim().isNotEmpty ? back : 'die markierte Stelle im Bild',
        QuestionType.table => [
            for (final row in tableRows ?? const <List<QuestionTableCell>>[])
              for (final cell in row)
                if (!cell.given && cell.text.trim().isNotEmpty)
                  cell.text.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).join(' / '),
          ].join('; '),
      };

  Flashcard copyWithReview({
    required DateTime due,
    required double stability,
    required double difficulty,
    required int elapsedDays,
    required int scheduledDays,
    required int reps,
    required int lapses,
    required String state,
    required DateTime lastReview,
    int? masteryBox,
  }) {
    return Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: front,
      back: back,
      createdAt: createdAt,
      due: due,
      type: type,
      options: options,
      correctText: correctText,
      blanks: blanks,
      dragPairs: dragPairs,
      htmlContent: htmlContent,
      imageBase64: imageBase64,
      imageTargets: imageTargets,
      tableRows: tableRows,
      taskData: taskData,
      variantChain: variantChain,
      variantLevel: variantLevel,
      variantBox: variantBox,
      variantHistory: variantHistory,
      pendingVariants: pendingVariants,
      variantMissStreak: variantMissStreak,
      masteryBox: masteryBox ?? this.masteryBox,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
      needsCalculator: needsCalculator,
      calcDeferredAt: null,
      sourceMaterialId: sourceMaterialId,
      sourcePage: sourcePage,
      scriptMaterialId: scriptMaterialId,
      scriptPage: scriptPage,
      miniLesson: miniLesson,
      weight: weight,
      stageLevel: stageLevel,
      stageGroup: stageGroup,
      aiHints: aiHints,
    );
  }

  /// Für manuelle Textkorrekturen (siehe FlashcardListScreen) – der
  /// Spaced-Repetition-Zustand bleibt dabei unverändert.
  Flashcard copyWithText({required String front, required String back}) => copyWithContent(front: front, back: back);

  /// Bild (bearbeitet: abgedeckt/beschriftet) und bei Bildfragen die Ziele
  /// bzw. die Frage ersetzen – der Lernstand bleibt. [clearImage] entfernt
  /// das Bild.
  Flashcard copyWithImage({
    String? imageBase64,
    bool clearImage = false,
    List<ImageTarget>? imageTargets,
    String? front,
    String? back,
  }) =>
      copyWithContent(
        imageBase64: imageBase64,
        clearImage: clearImage,
        imageTargets: imageTargets,
        front: front,
        back: back,
      );

  /// Inhalt der Frage von Hand korrigieren (Kartenliste: Frage, Optionen,
  /// Musterantwort, Lücken, Paare, Bild) – Typ, Lernstand und Stufenkette
  /// bleiben unverändert. Nicht angegebene Felder bleiben, wie sie sind.
  Flashcard copyWithContent({
    String? front,
    String? back,
    List<QuizOption>? options,
    String? correctText,
    List<String>? blanks,
    List<DragPair>? dragPairs,
    String? imageBase64,
    bool clearImage = false,
    List<ImageTarget>? imageTargets,
    List<List<QuestionTableCell>>? tableRows,
    Map<String, dynamic>? taskData,
  }) {
    final updated = Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: front ?? this.front,
      back: back ?? this.back,
      createdAt: createdAt,
      due: due,
      type: type,
      options: options ?? this.options,
      correctText: correctText ?? this.correctText,
      blanks: blanks ?? this.blanks,
      dragPairs: dragPairs ?? this.dragPairs,
      htmlContent: htmlContent,
      imageBase64: clearImage ? null : (imageBase64 ?? this.imageBase64),
      imageTargets: imageTargets ?? this.imageTargets,
      tableRows: tableRows ?? this.tableRows,
      taskData: taskData ?? this.taskData,
      variantChain: variantChain,
      variantLevel: variantLevel,
      variantBox: variantBox,
      variantHistory: variantHistory,
      pendingVariants: pendingVariants,
      variantMissStreak: variantMissStreak,
      masteryBox: masteryBox,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
      needsCalculator: needsCalculator,
      calcDeferredAt: calcDeferredAt,
      sourceMaterialId: sourceMaterialId,
      sourcePage: sourcePage,
      scriptMaterialId: scriptMaterialId,
      scriptPage: scriptPage,
      miniLesson: miniLesson,
      weight: weight,
      stageLevel: stageLevel,
      stageGroup: stageGroup,
      aiHints: aiHints,
    );
    // Gespeicherte KI-Hilfestellungen passen nach einer geänderten Frage
    // bzw. Lösung nicht mehr – beim nächsten Bedarf neu erzeugen.
    final contentChanged = updated.front != this.front || updated.answerSummary != answerSummary;
    return contentChanged && aiHints != null ? Flashcard.fromMap({...updated.toMap(), 'aiHints': null}) : updated;
  }

  /// Lernhilfen nachtragen: gefundene Stelle in den Unterlagen bzw. eine
  /// erzeugte Lerneinheit. Lernstand und Inhalt bleiben unverändert.
  Flashcard copyWithStudyAids({String? sourceMaterialId, int? sourcePage, String? miniLesson}) {
    final map = toMap();
    if (sourceMaterialId != null) {
      map['sourceMaterialId'] = sourceMaterialId;
      map['sourcePage'] = sourcePage;
    }
    if (miniLesson != null) map['miniLesson'] = miniLesson;
    return Flashcard.fromMap(map);
  }

  /// Fundstelle der Erklärung im Skript setzen (siehe [scriptMaterialId]);
  /// [materialId] null mit [page] 0 hält fest, dass nichts gefunden wurde.
  /// Alles andere bleibt unverändert.
  Flashcard copyWithScript({String? materialId, required int page}) =>
      Flashcard.fromMap({...toMap(), 'scriptMaterialId': materialId, 'scriptPage': page});

  /// Gewichtung von Hand ändern (siehe [weight], Kartenliste) – Inhalt,
  /// Lernstand und Stufenkette bleiben unverändert. Wird auf
  /// [minWeight]..[maxWeight] begrenzt.
  Flashcard copyWithWeight(double weight) => Flashcard.fromMap({...toMap(), 'weight': weight});

  /// Stufe/Gruppe setzen (siehe [stageLevel], [stageGroup]) – beim
  /// Erstellen, per KI-Zuordnung oder von Hand. [clearLevel]/[clearGroup]
  /// gehen zurück auf "aus dem Fragetyp" bzw. "Konzept der Karte".
  Flashcard copyWithStage({int? level, String? group, bool clearLevel = false, bool clearGroup = false}) {
    final map = toMap();
    if (clearLevel) {
      map['stageLevel'] = null;
    } else if (level != null) {
      map['stageLevel'] = level;
    }
    if (clearGroup) {
      map['stageGroup'] = null;
    } else if (group != null) {
      map['stageGroup'] = group;
    }
    return Flashcard.fromMap(map);
  }

  /// Einer Vorlesungseinheit zuordnen (null = keine), z.B. per
  /// Sammel-Bearbeiten in der Kartenliste. Lernstand bleibt.
  Flashcard copyWithUnit(String? unitId) => Flashcard.fromMap({...toMap(), 'unitId': unitId});

  /// Rechenaufgabe festlegen (`null` = wieder automatisch erkennen).
  Flashcard copyWithCalculator(bool? needsCalculator) =>
      Flashcard.fromMap({...toMap(), 'needsCalculator': needsCalculator});

  /// Als zurückgestellte Rechenaufgabe markieren bzw. (`null`) die Markierung löschen.
  Flashcard copyWithCalcDeferred(DateTime? at) =>
      Flashcard.fromMap({...toMap(), 'calcDeferredAt': at?.toIso8601String()});

  /// Gespeicherte KI-Hilfestellungen ersetzen (siehe [aiHints]).
  Flashcard copyWithHints(List<String> hints) => Flashcard.fromMap({...toMap(), 'aiHints': hints});

  /// Fehler-Leiter neu setzen (siehe [variantMissStreak]), z.B. nach einem
  /// Rückfall auf die leichteren Karten der Gruppe.
  Flashcard copyWithMissStreak(int streak) => Flashcard.fromMap({...toMap(), 'variantMissStreak': streak});

  /// Holt eine ruhende, leichtere Stufe zurück in den Plan (siehe
  /// StageGate.reactivateEasier): knapp unter grün, spätestens [dueBy]
  /// fällig, Fehler-Leiter von vorn. Senkt nie einen ohnehin niedrigeren
  /// Stand und schiebt keine frühere Fälligkeit nach hinten.
  Flashcard copyWithStageReopened({required DateTime dueBy}) => Flashcard.fromMap({
        ...toMap(),
        'masteryBox': masteryBox < masteryBoxCap - 1 ? masteryBox : masteryBoxCap - 1,
        'due': (due.isAfter(dueBy) ? dueBy : due).toIso8601String(),
        'variantMissStreak': 0,
      });

  /// Fehler-Leiter (siehe [variantMissStreak]): ab so vielen falschen
  /// Antworten in Folge erscheint vor dem Antworten eine KI-Hilfestellung …
  static const int hintMissStreak = 2;

  /// … ab so vielen eine zweite, deutlichere …
  static const int secondHintMissStreak = 3;

  /// … und ab so vielen kommt die leichtere Stufe zurück: bei einer
  /// Stufenkette die vorige Stufe ([copyWithDemotedVariant]), bei getrennten
  /// Karten die leichteren Karten der Gruppe (StageGate.reactivateEasier).
  static const int fallbackMissStreak = 4;

  /// Wie viele der gespeicherten [aiHints] bei [missStreak] Fehlern in Folge
  /// vor dem Antworten gezeigt werden sollen (0, 1 oder 2).
  static int hintsDueFor(int missStreak) => missStreak >= secondHintMissStreak
      ? 2
      : missStreak >= hintMissStreak
          ? 1
          : 0;

  /// Nach einer Antwort: Fehler-Leiter und Stufenkette fortschreiben – in
  /// BEIDE Richtungen. Ist die aktuelle Stufe grün ([masteryBox] am Cap), die
  /// Antwort ohne Hilfe gewusst ([promotable]) und eine nächste Stufe in
  /// [variantChain] vorhanden, wird befördert: liegt ihr Inhalt bereits
  /// fertig in [pendingVariants] vor, SOFORT ohne KI-Aufruf
  /// ([needsGeneration] = false); sonst wird nur die Ziel-Stufe über
  /// [nextType] signalisiert ([needsGeneration] = true) – die KI ruft der
  /// Aufrufer, damit dieses Modell frei von I/O bleibt. Umgekehrt: erreicht
  /// [variantMissStreak] [fallbackMissStreak], geht eine Stufenkette sofort
  /// eine Stufe zurück ([copyWithDemotedVariant], alter Wortlaut liegt in
  /// [variantHistory]).
  ({Flashcard card, QuestionType? nextType, bool needsGeneration}) copyWithBoxUpdate({
    required bool isCorrect,
    bool promotable = true,
  }) {
    final chain = variantChain;
    // Befördert wird, sobald die aktuelle Stufe grün ist: masteryBox am Cap
    // heißt an [masteryBoxCap] verschiedenen Tagen richtig beantwortet
    // (siehe FsrsService.review). Aufrufer wenden FsrsService.review VOR
    // dieser Methode an, masteryBox enthält die aktuelle Antwort also schon.
    final canPromote = chain != null &&
        variantLevel < chain.length - 1 &&
        masteryBox >= Flashcard.masteryBoxCap &&
        isCorrect &&
        promotable;
    if (canPromote) {
      final pending = pendingVariants;
      if (pending != null && pending.isNotEmpty) {
        final promoted = copyWithPromotedVariantFromPending();
        return (card: promoted, nextType: promoted.type, needsGeneration: false);
      }
      final updated = Flashcard(
        id: id,
        moduleId: moduleId,
        conceptId: conceptId,
        front: front,
        back: back,
        createdAt: createdAt,
        due: due,
        type: type,
        options: options,
        correctText: correctText,
        blanks: blanks,
        dragPairs: dragPairs,
        htmlContent: htmlContent,
        imageBase64: imageBase64,
        imageTargets: imageTargets,
        tableRows: tableRows,
        taskData: taskData,
        variantChain: chain,
        variantLevel: variantLevel,
        variantBox: 0,
        variantHistory: variantHistory,
        pendingVariants: pendingVariants,
        variantMissStreak: 0,
        masteryBox: masteryBox,
        stability: stability,
        difficulty: difficulty,
        elapsedDays: elapsedDays,
        scheduledDays: scheduledDays,
        reps: reps,
        lapses: lapses,
        state: state,
        lastReview: lastReview,
        unitId: unitId,
        priorityIntroduction: priorityIntroduction,
        needsCalculator: needsCalculator,
        calcDeferredAt: calcDeferredAt,
        sourceMaterialId: sourceMaterialId,
        sourcePage: sourcePage,
        scriptMaterialId: scriptMaterialId,
        scriptPage: scriptPage,
        miniLesson: miniLesson,
        weight: weight,
        stageLevel: stageLevel,
        stageGroup: stageGroup,
        aiHints: aiHints,
      );
      return (card: updated, nextType: chain[variantLevel + 1], needsGeneration: true);
    }

    final missStreak = isCorrect ? 0 : variantMissStreak + 1;
    final isOnLastStage = chain != null && variantLevel >= chain.length - 1;
    final canDemote = !isCorrect &&
        variantLevel > 0 &&
        missStreak >= fallbackMissStreak &&
        (variantHistory?.isNotEmpty ?? false);
    if (canDemote) {
      final demoted = copyWithDemotedVariant(
        // Gibt beim Rückfall von der schwersten Stufe einen Vertrauens-
        // vorschuss (gelb statt rot/leer) – die Karte war ja nachgewiesen
        // gut gelernt, ein Rückfall soll nicht komplett bei Null anfangen.
        masteryBoxOverride: isOnLastStage ? Flashcard.masteryBoxCap - 1 : null,
      );
      return (card: demoted, nextType: null, needsGeneration: false);
    }

    final newBox = isCorrect ? variantBox + 1 : (variantBox - 1).clamp(0, 999);
    final updated = Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: front,
      back: back,
      createdAt: createdAt,
      due: due,
      type: type,
      options: options,
      correctText: correctText,
      blanks: blanks,
      dragPairs: dragPairs,
      htmlContent: htmlContent,
      imageBase64: imageBase64,
      imageTargets: imageTargets,
      tableRows: tableRows,
      taskData: taskData,
      variantChain: variantChain,
      variantLevel: variantLevel,
      variantBox: newBox,
      variantHistory: variantHistory,
      pendingVariants: pendingVariants,
      variantMissStreak: missStreak,
      masteryBox: masteryBox,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
      needsCalculator: needsCalculator,
      calcDeferredAt: calcDeferredAt,
      sourceMaterialId: sourceMaterialId,
      sourcePage: sourcePage,
      scriptMaterialId: scriptMaterialId,
      scriptPage: scriptPage,
      miniLesson: miniLesson,
      weight: weight,
      stageLevel: stageLevel,
      stageGroup: stageGroup,
      aiHints: aiHints,
    );
    return (card: updated, nextType: null, needsGeneration: false);
  }

  /// Ersetzt Typ/Inhalt durch die nächste (schwerere) Eskalationsstufe -
  /// aufgerufen, nachdem [copyWithBoxUpdate] eine mögliche Beförderung
  /// signalisiert hat und der Aufrufer die neuen Inhalte per KI erzeugt hat.
  /// Sichert den bisherigen (leichteren) Inhalt in [variantHistory], bevor
  /// er überschrieben wird – Grundlage für eine spätere Rückstufung.
  Flashcard copyWithPromotedVariant({
    required QuestionType newType,
    required String front,
    String back = '',
    List<QuizOption>? options,
    String? correctText,
    List<String>? blanks,
    List<DragPair>? dragPairs,
    String? htmlContent,
    String? imageBase64,
    List<ImageTarget>? imageTargets,
    List<List<QuestionTableCell>>? tableRows,
    Map<String, dynamic>? taskData,
    List<VariantSnapshot>? pendingVariants,
  }) {
    final snapshot = VariantSnapshot(
      type: type,
      front: this.front,
      back: this.back,
      options: this.options,
      correctText: this.correctText,
      blanks: this.blanks,
      dragPairs: this.dragPairs,
      htmlContent: this.htmlContent,
      imageBase64: this.imageBase64,
      imageTargets: this.imageTargets,
      tableRows: this.tableRows,
      taskData: this.taskData,
    );
    return Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: front,
      back: back,
      createdAt: createdAt,
      due: due,
      type: newType,
      options: options,
      correctText: correctText,
      blanks: blanks,
      dragPairs: dragPairs,
      htmlContent: htmlContent,
      imageBase64: imageBase64,
      imageTargets: imageTargets,
      tableRows: tableRows,
      taskData: taskData,
      variantChain: variantChain,
      variantLevel: variantLevel + 1,
      variantBox: 0,
      variantHistory: [...?variantHistory, snapshot],
      pendingVariants: pendingVariants ?? this.pendingVariants,
      variantMissStreak: 0,
      masteryBox: masteryBox,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
      needsCalculator: needsCalculator,
      calcDeferredAt: calcDeferredAt,
      sourceMaterialId: sourceMaterialId,
      sourcePage: sourcePage,
      scriptMaterialId: scriptMaterialId,
      scriptPage: scriptPage,
      miniLesson: miniLesson,
      weight: weight,
      stageLevel: stageLevel,
      stageGroup: stageGroup,
    );
  }

  /// Wie [copyWithPromotedVariant], nutzt aber den bereits vorbereiteten
  /// Inhalt der nächsten Stufe aus [pendingVariants] statt Parametern des
  /// Aufrufers – KEIN KI-Aufruf nötig (siehe Doc-Kommentar dort). Nur
  /// sinnvoll aufzurufen, wenn [pendingVariants] nicht leer ist;
  /// [copyWithBoxUpdate] prüft das bereits, diese Methode ist aber auch
  /// eigenständig sicher aufrufbar (ohne Wirkung, wenn nichts vorbereitet ist).
  Flashcard copyWithPromotedVariantFromPending() {
    final pending = pendingVariants;
    if (pending == null || pending.isEmpty) return this;
    final next = pending.first;
    final remaining = pending.sublist(1);
    return copyWithPromotedVariant(
      newType: next.type,
      front: next.front,
      back: next.back,
      options: next.options,
      correctText: next.correctText,
      blanks: next.blanks,
      dragPairs: next.dragPairs,
      htmlContent: next.htmlContent,
      imageBase64: next.imageBase64,
      imageTargets: next.imageTargets,
      tableRows: next.tableRows,
      taskData: next.taskData,
      pendingVariants: remaining,
    );
  }

  /// Kehrt zur vorherigen (leichteren) Eskalationsstufe zurück, deren
  /// Inhalt bereits in [variantHistory] liegt – kein KI-Aufruf nötig. Ohne
  /// Historie (leere Liste) bleibt die Karte unverändert; der Aufrufer
  /// prüft das bereits über [copyWithBoxUpdate], diese Methode ist aber
  /// auch eigenständig sicher aufrufbar. Die gerade verlassene (schwerere)
  /// Stufe wandert dabei in [pendingVariants] (Spiegelbild zu
  /// [variantHistory]) – wird sie später erneut erreicht, steht ihr Inhalt
  /// sofort wieder zur Verfügung, ohne erneuten KI-Aufruf.
  /// [masteryBoxOverride] setzt bei Bedarf einen abweichenden Ampel-Stand
  /// (siehe [copyWithBoxUpdate]: ein Rückfall von der schwersten Stufe
  /// bekommt einen Vertrauensvorschuss statt bei Null anzufangen).
  Flashcard copyWithDemotedVariant({int? masteryBoxOverride}) {
    final history = variantHistory;
    if (history == null || history.isEmpty) return this;
    final previous = history.last;
    final remaining = history.sublist(0, history.length - 1);
    final vacated = VariantSnapshot(
      type: type,
      front: front,
      back: back,
      options: options,
      correctText: correctText,
      blanks: blanks,
      dragPairs: dragPairs,
      htmlContent: htmlContent,
      imageBase64: imageBase64,
      imageTargets: imageTargets,
      tableRows: tableRows,
      taskData: taskData,
    );
    return Flashcard(
      id: id,
      moduleId: moduleId,
      conceptId: conceptId,
      front: previous.front,
      back: previous.back,
      createdAt: createdAt,
      due: due,
      type: previous.type,
      options: previous.options,
      correctText: previous.correctText,
      blanks: previous.blanks,
      dragPairs: previous.dragPairs,
      htmlContent: previous.htmlContent,
      imageBase64: previous.imageBase64,
      imageTargets: previous.imageTargets,
      tableRows: previous.tableRows,
      taskData: previous.taskData,
      variantChain: variantChain,
      variantLevel: variantLevel - 1,
      variantBox: 0,
      variantHistory: remaining,
      pendingVariants: [vacated, ...?pendingVariants],
      variantMissStreak: 0,
      masteryBox: masteryBoxOverride ?? masteryBox,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      state: state,
      lastReview: lastReview,
      unitId: unitId,
      priorityIntroduction: priorityIntroduction,
      needsCalculator: needsCalculator,
      calcDeferredAt: calcDeferredAt,
      sourceMaterialId: sourceMaterialId,
      sourcePage: sourcePage,
      scriptMaterialId: scriptMaterialId,
      scriptPage: scriptPage,
      miniLesson: miniLesson,
      weight: weight,
      stageLevel: stageLevel,
      stageGroup: stageGroup,
    );
  }

  /// Obergrenze für [masteryBox] – ab hier zählt eine Karte für die Ampel
  /// als nachgewiesen gut gelernt (siehe MasteryService), weiteres Wachstum
  /// bringt keinen zusätzlichen Nutzen mehr.
  static const int masteryBoxCap = 4;

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'conceptId': conceptId,
        'front': front,
        'back': back,
        'createdAt': createdAt.toIso8601String(),
        'due': due.toIso8601String(),
        'type': type.name,
        'options': options?.map((o) => o.toMap()).toList(),
        'correctText': correctText,
        'blanks': blanks,
        'dragPairs': dragPairs?.map((p) => p.toMap()).toList(),
        'htmlContent': htmlContent,
        'imageBase64': imageBase64,
        'imageTargets': imageTargets?.map((t) => t.toMap()).toList(),
        'tableRows': _tableRowsToMap(tableRows),
        'taskData': taskData,
        'variantChain': variantChain?.map((t) => t.name).toList(),
        'variantLevel': variantLevel,
        'variantBox': variantBox,
        'variantHistory': variantHistory?.map((v) => v.toMap()).toList(),
        'pendingVariants': pendingVariants?.map((v) => v.toMap()).toList(),
        'variantMissStreak': variantMissStreak,
        'masteryBox': masteryBox,
        'stability': stability,
        'difficulty': difficulty,
        'elapsedDays': elapsedDays,
        'scheduledDays': scheduledDays,
        'reps': reps,
        'lapses': lapses,
        'state': state,
        'lastReview': lastReview?.toIso8601String(),
        'unitId': unitId,
        'priorityIntroduction': priorityIntroduction,
        'needsCalculator': needsCalculator,
        'calcDeferredAt': calcDeferredAt?.toIso8601String(),
        'sourceMaterialId': sourceMaterialId,
        'sourcePage': sourcePage,
        'scriptMaterialId': scriptMaterialId,
        'scriptPage': scriptPage,
        'miniLesson': miniLesson,
        'weight': weight,
        'stageLevel': stageLevel,
        'stageGroup': stageGroup,
        'aiHints': aiHints,
      };

  factory Flashcard.fromMap(Map<String, dynamic> map) => Flashcard(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        conceptId: map['conceptId'] as String?,
        front: map['front'] as String? ?? '',
        back: map['back'] as String? ?? '',
        createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime(2000),
        due: DateTime.tryParse(map['due']?.toString() ?? '') ?? DateTime(2000),
        type: _storedType(map),
        options: (map['options'] as List?)
            ?.map((o) => QuizOption.fromMap(Map<String, dynamic>.from(o as Map)))
            .toList(),
        correctText: map['correctText'] as String?,
        blanks: (map['blanks'] as List?)?.map((b) => b.toString()).toList(),
        dragPairs: (map['dragPairs'] as List?)
            ?.map((p) => DragPair.fromMap(Map<String, dynamic>.from(p as Map)))
            .toList(),
        htmlContent: map['htmlContent'] as String?,
        imageBase64: map['imageBase64'] as String?,
        imageTargets: parseImageTargets(map['imageTargets']),
        tableRows: parseTableRows(map['tableRows']),
        taskData: parseTaskData(map['taskData']),
        variantChain:
            (map['variantChain'] as List?)?.map((t) => questionTypeFromString(t.toString())).toList(),
        variantLevel: (map['variantLevel'] as num?)?.toInt() ?? 0,
        variantBox: (map['variantBox'] as num?)?.toInt() ?? 0,
        variantHistory: (map['variantHistory'] as List?)
            ?.map((v) => VariantSnapshot.fromMap(Map<String, dynamic>.from(v as Map)))
            .toList(),
        pendingVariants: (map['pendingVariants'] as List?)
            ?.map((v) => VariantSnapshot.fromMap(Map<String, dynamic>.from(v as Map)))
            .toList(),
        variantMissStreak: (map['variantMissStreak'] as num?)?.toInt() ?? 0,
        masteryBox: (map['masteryBox'] as num?)?.toInt() ?? 0,
        // Defaults + num statt int: fremde/ältere/importierte Datensätze
        // (z.B. JSON mit 3.0 statt 3) sollen nicht abstürzen.
        stability: (map['stability'] as num?)?.toDouble() ?? 0,
        difficulty: (map['difficulty'] as num?)?.toDouble() ?? 0,
        elapsedDays: (map['elapsedDays'] as num?)?.toInt() ?? 0,
        scheduledDays: (map['scheduledDays'] as num?)?.toInt() ?? 0,
        reps: (map['reps'] as num?)?.toInt() ?? 0,
        lapses: (map['lapses'] as num?)?.toInt() ?? 0,
        state: map['state'] as String? ?? 'new',
        lastReview: DateTime.tryParse(map['lastReview']?.toString() ?? ''),
        unitId: map['unitId'] as String?,
        priorityIntroduction: map['priorityIntroduction'] as bool? ?? false,
        needsCalculator: map['needsCalculator'] is bool ? map['needsCalculator'] as bool : null,
        calcDeferredAt: DateTime.tryParse('${map['calcDeferredAt'] ?? ''}'),
        sourceMaterialId: map['sourceMaterialId'] as String?,
        sourcePage: (map['sourcePage'] as num?)?.toInt(),
        scriptMaterialId: map['scriptMaterialId'] as String?,
        scriptPage: (map['scriptPage'] as num?)?.toInt(),
        miniLesson: map['miniLesson'] as String?,
        // Ältere Datensätze ohne Gewicht zählen einfach (1.0); ein kaputter
        // Wert (0, negativ) würde die Intervall-Skalierung aushebeln.
        weight: _sanitizeWeight((map['weight'] as num?)?.toDouble()),
        stageLevel: _sanitizeStageLevel((map['stageLevel'] as num?)?.toInt()),
        stageGroup: (map['stageGroup'] as String?)?.trim().isEmpty ?? true ? null : (map['stageGroup'] as String).trim(),
        aiHints: (map['aiHints'] as List?)?.map((h) => h.toString()).where((h) => h.trim().isNotEmpty).toList(),
      );

  static int? _sanitizeStageLevel(int? value) => value == null || value < 0 || value > 2 ? null : value;

  /// Erlaubter Bereich für [weight] (siehe dort): 0 heißt "stumm" (kommt nie
  /// dran, siehe [isMuted]), sonst von [minWeight] bis [maxWeight] – schützt
  /// die Intervall-Skalierung in FsrsService.review() vor negativen Werten und
  /// vor absurden Extremen aus manuell bearbeiteten/importierten Daten.
  static const double minWeight = 0.25;
  static const double maxWeight = 4.0;

  /// Gewicht einer stummgeschalteten Karte.
  static const double mutedWeight = 0.0;

  /// Gewicht 0: die Karte ist stummgeschaltet und kommt nirgends dran – nicht
  /// im Daily Quiz, Üben, Sprint, in der Probeklausur oder bei den
  /// Schwachstellen – und zählt nicht für Ampel und Statistik. Sie bleibt in
  /// der Kartenliste und lässt sich dort jederzeit wieder einschalten.
  bool get isMuted => weight <= 0;

  static double _sanitizeWeight(double? value) {
    if (value == null || value.isNaN) return 1.0;
    if (value <= 0) return mutedWeight;
    return value.clamp(minWeight, maxWeight).toDouble();
  }
}
