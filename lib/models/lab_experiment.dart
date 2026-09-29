import 'package:uuid/uuid.dart';

/// Einschätzung der KI zu einer selbst geschriebenen Antwort oder einem
/// Berichtsabschnitt (siehe AiService.reviewLabAnswer/reviewReportSection).
/// [forText] merkt den Wortlaut, auf den sich die Einschätzung bezieht – wurde
/// der Text danach geändert, ist sie veraltet ([isStaleFor]).
class LabFeedback {
  const LabFeedback({
    required this.verdict,
    required this.summary,
    this.missing = const [],
    this.hints = const [],
    this.forText = '',
    required this.at,
  });

  /// `gut`, `teilweise`, `unklar` oder `leer` (noch nichts geschrieben).
  final String verdict;
  final String summary;

  /// Was in der Antwort noch fehlt bzw. nicht stimmt.
  final List<String> missing;

  /// Hinweise, wo bzw. was nachzuschlagen ist – bewusst keine Musterlösung.
  final List<String> hints;
  final String forText;
  final DateTime at;

  bool isStaleFor(String text) => forText.trim() != text.trim();

  Map<String, dynamic> toMap() => {
        'verdict': verdict,
        'summary': summary,
        'missing': missing,
        'hints': hints,
        'forText': forText,
        'at': at.toIso8601String(),
      };

  static LabFeedback? fromMap(Object? raw) {
    if (raw is! Map) return null;
    List<String> strings(Object? v) => [
          if (v is List)
            for (final e in v)
              if (e.toString().trim().isNotEmpty) e.toString().trim(),
        ];
    return LabFeedback(
      verdict: (raw['verdict'] ?? 'unklar').toString(),
      summary: (raw['summary'] ?? '').toString(),
      missing: strings(raw['missing']),
      hints: strings(raw['hints']),
      forText: (raw['forText'] ?? '').toString(),
      at: DateTime.tryParse('${raw['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Eine Frage des Versuchs (Vorbereitungs- oder Auswertungsfrage) mit der
/// eigenen Antwort.
class LabQuestion {
  const LabQuestion({
    required this.id,
    required this.number,
    required this.text,
    this.answer = '',
    this.feedback,
  });

  final String id;

  /// Nummer wie im Skript ("1a", "3", "2.4.1").
  final String number;
  final String text;
  final String answer;
  final LabFeedback? feedback;

  bool get answered => answer.trim().isNotEmpty;

  LabQuestion copyWith({String? answer, LabFeedback? feedback, bool clearFeedback = false}) => LabQuestion(
        id: id,
        number: number,
        text: text,
        answer: answer ?? this.answer,
        feedback: clearFeedback ? null : (feedback ?? this.feedback),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'number': number,
        'text': text,
        'answer': answer,
        'feedback': feedback?.toMap(),
      };

  factory LabQuestion.fromMap(Map<String, dynamic> map) => LabQuestion(
        id: (map['id'] ?? const Uuid().v4()).toString(),
        number: (map['number'] ?? '').toString(),
        text: (map['text'] ?? '').toString(),
        answer: (map['answer'] ?? '').toString(),
        feedback: LabFeedback.fromMap(map['feedback']),
      );
}

/// Ein Schritt der Versuchsdurchführung mit Häkchen.
class LabStep {
  const LabStep({required this.text, this.done = false});

  final String text;
  final bool done;

  LabStep copyWith({bool? done}) => LabStep(text: text, done: done ?? this.done);

  Map<String, dynamic> toMap() => {'text': text, 'done': done};

  factory LabStep.fromMap(Map<String, dynamic> map) =>
      LabStep(text: (map['text'] ?? '').toString(), done: map['done'] == true);
}

/// Messwerttabelle eines Versuchsteils. Was im Skript schon eingetragen ist
/// (Vorgaben, Kopfzeile), bleibt fest; leere Zellen sind zum Ausfüllen.
class LabTable {
  const LabTable({required this.title, required this.columns, required this.rows, required this.editable});

  final String title;
  final List<String> columns;
  final List<List<String>> rows;

  /// Je Zelle: darf sie ausgefüllt werden (im Skript leer)? Bleibt auch dann
  /// bestehen, wenn die Zelle später befüllt wird.
  final List<List<bool>> editable;

  int get editableCount => editable.fold(0, (sum, row) => sum + row.where((e) => e).length);

  int get filledCount {
    var n = 0;
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        if (editable[r][c] && rows[r][c].trim().isNotEmpty) n++;
      }
    }
    return n;
  }

  LabTable withCell(int row, int col, String value) {
    if (row < 0 || row >= rows.length || col < 0 || col >= rows[row].length || !editable[row][col]) return this;
    final next = [for (final r in rows) [...r]];
    next[row][col] = value;
    return LabTable(title: title, columns: columns, rows: next, editable: editable);
  }

  /// Als Text (eine Zeile je Tabellenzeile) – für die KI und den Export.
  String asText() {
    final lines = <String>[
      if (title.trim().isNotEmpty) title.trim(),
      columns.join(' | '),
      for (final row in rows) row.map((c) => c.trim().isEmpty ? '–' : c.trim()).join(' | '),
    ];
    return lines.join('\n');
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'columns': columns,
        'rows': rows,
        'editable': editable,
      };

  /// Tolerant gelesen: ungleich lange Zeilen werden aufgefüllt, fehlende
  /// Angaben zu "editable" heißen "leer = ausfüllbar".
  factory LabTable.fromMap(Map<String, dynamic> map) {
    final columns = [for (final c in (map['columns'] as List? ?? const [])) c.toString()];
    final width = columns.length;
    final rawRows = (map['rows'] as List? ?? const []);
    final rows = <List<String>>[];
    final editable = <List<bool>>[];
    final rawEditable = map['editable'] as List?;
    for (var r = 0; r < rawRows.length; r++) {
      final cells = [for (final c in (rawRows[r] is List ? rawRows[r] as List : const [])) (c ?? '').toString()];
      while (cells.length < width) {
        cells.add('');
      }
      final flags = rawEditable != null && r < rawEditable.length && rawEditable[r] is List
          ? [for (final f in rawEditable[r] as List) f == true]
          : <bool>[];
      while (flags.length < cells.length) {
        flags.add(rawEditable == null ? cells[flags.length].trim().isEmpty : false);
      }
      rows.add(cells);
      editable.add(flags.sublist(0, cells.length));
    }
    return LabTable(title: (map['title'] ?? '').toString(), columns: columns, rows: rows, editable: editable);
  }

  /// Aus der KI-Antwort: leere Zellen sind zum Ausfüllen (die Kopfzeile ist
  /// [columns] und zählt nicht dazu).
  factory LabTable.fromAi(Map<String, dynamic> map) => LabTable.fromMap({...map, 'editable': null});
}

/// Ein Versuchsteil des Skripts: Ziel, Schritte, Messwerttabellen und
/// Auswertungsfragen.
class LabPart {
  const LabPart({
    required this.id,
    required this.title,
    this.goals = const [],
    this.steps = const [],
    this.tables = const [],
    this.questions = const [],
    this.notes = '',
  });

  final String id;
  final String title;
  final List<String> goals;
  final List<LabStep> steps;
  final List<LabTable> tables;

  /// Auswertungsfragen dieses Teils.
  final List<LabQuestion> questions;

  /// Eigene Notizen während des Versuchs (Einstellungen, Auffälligkeiten).
  final String notes;

  LabPart copyWith({List<LabStep>? steps, List<LabTable>? tables, List<LabQuestion>? questions, String? notes}) =>
      LabPart(
        id: id,
        title: title,
        goals: goals,
        steps: steps ?? this.steps,
        tables: tables ?? this.tables,
        questions: questions ?? this.questions,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'goals': goals,
        'steps': [for (final s in steps) s.toMap()],
        'tables': [for (final t in tables) t.toMap()],
        'questions': [for (final q in questions) q.toMap()],
        'notes': notes,
      };

  factory LabPart.fromMap(Map<String, dynamic> map) => LabPart(
        id: (map['id'] ?? const Uuid().v4()).toString(),
        title: (map['title'] ?? '').toString(),
        goals: [for (final g in (map['goals'] as List? ?? const [])) g.toString()],
        steps: [
          for (final s in (map['steps'] as List? ?? const []))
            if (s is Map) LabStep.fromMap(Map<String, dynamic>.from(s)),
        ],
        tables: [
          for (final t in (map['tables'] as List? ?? const []))
            if (t is Map) LabTable.fromMap(Map<String, dynamic>.from(t)),
        ],
        questions: [
          for (final q in (map['questions'] as List? ?? const []))
            if (q is Map) LabQuestion.fromMap(Map<String, dynamic>.from(q)),
        ],
        notes: (map['notes'] ?? '').toString(),
      );
}

/// Ein Abschnitt des Berichts mit dem selbst geschriebenen Text.
class LabReportSection {
  const LabReportSection({
    required this.id,
    required this.title,
    this.hint = '',
    this.text = '',
    this.feedback,
    this.partId,
  });

  final String id;
  final String title;

  /// Was in den Abschnitt gehört (z.B. die Auswertungsfragen des Teils).
  final String hint;
  final String text;
  final LabFeedback? feedback;

  /// Der Versuchsteil, zu dem der Abschnitt gehört (Messwerte, Fragen für
  /// das Gegenlesen); null bei Einleitung und Fazit.
  final String? partId;

  /// Ab so vielen Zeichen gilt ein Abschnitt als begonnen.
  static const writtenThreshold = 40;
  bool get written => text.trim().length >= writtenThreshold;

  LabReportSection copyWith({String? text, LabFeedback? feedback, bool clearFeedback = false}) => LabReportSection(
        id: id,
        title: title,
        hint: hint,
        text: text ?? this.text,
        feedback: clearFeedback ? null : (feedback ?? this.feedback),
        partId: partId,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'hint': hint,
        'text': text,
        'feedback': feedback?.toMap(),
        'partId': partId,
      };

  factory LabReportSection.fromMap(Map<String, dynamic> map) => LabReportSection(
        id: (map['id'] ?? const Uuid().v4()).toString(),
        title: (map['title'] ?? '').toString(),
        hint: (map['hint'] ?? '').toString(),
        text: (map['text'] ?? '').toString(),
        feedback: LabFeedback.fromMap(map['feedback']),
        partId: map['partId']?.toString(),
      );
}

/// Wo ein Versuch gerade steht.
enum LabPhase { preparation, labDay, report, done }

/// Ein Laborversuch eines Fachs: Vorbereitung (Fragen mit eigenen Antworten),
/// Durchführung (Schritte, Messwerte, Auswertungsfragen) und Bericht. Entsteht
/// aus der Versuchsanleitung (siehe AiService.structureLabExperiment) und
/// bleibt danach vollständig von Hand bearbeitbar.
class LabExperiment {
  const LabExperiment({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.createdAt,
    this.labDate,
    this.reportDue,
    this.guideMaterialIds = const [],
    this.theoryMaterialIds = const [],
    this.prep = const [],
    this.parts = const [],
    this.report = const [],
    this.hints = const [],
    this.finished = false,
  });

  final String id;
  final String moduleId;
  final String title;
  final DateTime createdAt;

  /// Termin des Versuchs.
  final DateTime? labDate;

  /// Abgabe des Berichts.
  final DateTime? reportDue;

  /// Versuchsanleitung(en) und Theorie-Skript(e) im Fach (MaterialItem.id).
  final List<String> guideMaterialIds;
  final List<String> theoryMaterialIds;
  final List<LabQuestion> prep;
  final List<LabPart> parts;
  final List<LabReportSection> report;

  /// Weitere Hinweise aus der Anleitung (z.B. "USB-Stick mitbringen").
  final List<String> hints;

  /// Bericht abgegeben.
  final bool finished;

  // -- Fortschritt ----------------------------------------------------------

  int get prepTotal => prep.length;
  int get prepAnswered => prep.where((q) => q.answered).length;
  bool get prepComplete => prepTotal > 0 && prepAnswered == prepTotal;

  Iterable<LabStep> get allSteps => parts.expand((p) => p.steps);
  int get stepsTotal => allSteps.length;
  int get stepsDone => allSteps.where((s) => s.done).length;

  int get cellsTotal => parts.expand((p) => p.tables).fold(0, (sum, t) => sum + t.editableCount);
  int get cellsFilled => parts.expand((p) => p.tables).fold(0, (sum, t) => sum + t.filledCount);

  Iterable<LabQuestion> get evaluationQuestions => parts.expand((p) => p.questions);
  int get evaluationTotal => evaluationQuestions.length;
  int get evaluationAnswered => evaluationQuestions.where((q) => q.answered).length;

  int get reportTotal => report.length;
  int get reportWritten => report.where((s) => s.written).length;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Ganze Kalendertage bis zum Versuch (0 = heute, negativ = vorbei).
  int? daysUntilLab(DateTime now) => labDate == null ? null : _calendarDays(_day(now), _day(labDate!));

  int? daysUntilReport(DateTime now) => reportDue == null ? null : _calendarDays(_day(now), _day(reportDue!));

  static int _calendarDays(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  LabPhase phase(DateTime now) {
    if (finished) return LabPhase.done;
    final days = daysUntilLab(now);
    if (days == null || days > 0) return LabPhase.preparation;
    return days == 0 ? LabPhase.labDay : LabPhase.report;
  }

  /// Bald ([withinDays]) oder heute Versuch, aber die Vorbereitung ist noch
  /// nicht komplett beantwortet.
  bool preparationOverdue(DateTime now, {int withinDays = 14}) {
    if (finished || prepTotal == 0 || prepComplete) return false;
    final days = daysUntilLab(now);
    return days != null && days >= 0 && days <= withinDays;
  }

  // -- Ändern (unveränderlich) ----------------------------------------------

  LabExperiment copyWith({
    String? title,
    DateTime? labDate,
    bool clearLabDate = false,
    DateTime? reportDue,
    bool clearReportDue = false,
    List<String>? guideMaterialIds,
    List<String>? theoryMaterialIds,
    List<LabQuestion>? prep,
    List<LabPart>? parts,
    List<LabReportSection>? report,
    List<String>? hints,
    bool? finished,
  }) =>
      LabExperiment(
        id: id,
        moduleId: moduleId,
        title: title ?? this.title,
        createdAt: createdAt,
        labDate: clearLabDate ? null : (labDate ?? this.labDate),
        reportDue: clearReportDue ? null : (reportDue ?? this.reportDue),
        guideMaterialIds: guideMaterialIds ?? this.guideMaterialIds,
        theoryMaterialIds: theoryMaterialIds ?? this.theoryMaterialIds,
        prep: prep ?? this.prep,
        parts: parts ?? this.parts,
        report: report ?? this.report,
        hints: hints ?? this.hints,
        finished: finished ?? this.finished,
      );

  /// Ersetzt die Frage [id] (Vorbereitung oder Auswertung) mit [change].
  LabExperiment updateQuestion(String id, LabQuestion Function(LabQuestion) change) => copyWith(
        prep: [for (final q in prep) q.id == id ? change(q) : q],
        parts: [
          for (final p in parts) p.copyWith(questions: [for (final q in p.questions) q.id == id ? change(q) : q]),
        ],
      );

  LabExperiment updatePart(String partId, LabPart Function(LabPart) change) =>
      copyWith(parts: [for (final p in parts) p.id == partId ? change(p) : p]);

  LabExperiment updateSection(String sectionId, LabReportSection Function(LabReportSection) change) =>
      copyWith(report: [for (final s in report) s.id == sectionId ? change(s) : s]);

  LabQuestion? questionById(String id) {
    for (final q in [...prep, ...evaluationQuestions]) {
      if (q.id == id) return q;
    }
    return null;
  }

  LabPart? partById(String? id) {
    for (final p in parts) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Derselbe Versuch, aber ohne alles Eigene – Antworten, Häkchen, Messwerte,
  /// Notizen, Berichtstexte, Einschätzungen und Termine: für ein
  /// weitergegebenes Fach, das die empfangende Person selbst durcharbeitet.
  LabExperiment withoutProgress() => LabExperiment(
        id: id,
        moduleId: moduleId,
        title: title,
        createdAt: createdAt,
        guideMaterialIds: guideMaterialIds,
        theoryMaterialIds: theoryMaterialIds,
        prep: [for (final q in prep) q.copyWith(answer: '', clearFeedback: true)],
        parts: [
          for (final p in parts)
            LabPart(
              id: p.id,
              title: p.title,
              goals: p.goals,
              steps: [for (final s in p.steps) s.copyWith(done: false)],
              tables: [
                for (final t in p.tables)
                  LabTable(
                    title: t.title,
                    columns: t.columns,
                    rows: [
                      for (var r = 0; r < t.rows.length; r++)
                        [for (var c = 0; c < t.rows[r].length; c++) t.editable[r][c] ? '' : t.rows[r][c]],
                    ],
                    editable: t.editable,
                  ),
              ],
              questions: [for (final q in p.questions) q.copyWith(answer: '', clearFeedback: true)],
            ),
        ],
        report: [for (final s in report) s.copyWith(text: '', clearFeedback: true)],
        hints: hints,
      );

  /// Für den Fach-Import: neue Kennungen für Versuch, Fach und Materialien
  /// ([materialIds] übersetzt alte in neue; nicht mit-exportierte fallen weg).
  LabExperiment reassigned({
    required String newId,
    required String newModuleId,
    required Map<String, String> materialIds,
  }) =>
      LabExperiment(
        id: newId,
        moduleId: newModuleId,
        title: title,
        createdAt: createdAt,
        labDate: labDate,
        reportDue: reportDue,
        guideMaterialIds: [for (final m in guideMaterialIds) ?materialIds[m]],
        theoryMaterialIds: [for (final m in theoryMaterialIds) ?materialIds[m]],
        prep: prep,
        parts: parts,
        report: report,
        hints: hints,
        finished: finished,
      );

  // -- Speichern ------------------------------------------------------------

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'labDate': labDate?.toIso8601String(),
        'reportDue': reportDue?.toIso8601String(),
        'guideMaterialIds': guideMaterialIds,
        'theoryMaterialIds': theoryMaterialIds,
        'prep': [for (final q in prep) q.toMap()],
        'parts': [for (final p in parts) p.toMap()],
        'report': [for (final s in report) s.toMap()],
        'hints': hints,
        'finished': finished,
      };

  factory LabExperiment.fromMap(Map<String, dynamic> map) => LabExperiment(
        id: (map['id'] ?? const Uuid().v4()).toString(),
        moduleId: (map['moduleId'] ?? '').toString(),
        title: (map['title'] ?? '').toString(),
        createdAt: DateTime.tryParse('${map['createdAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        labDate: DateTime.tryParse('${map['labDate']}'),
        reportDue: DateTime.tryParse('${map['reportDue']}'),
        guideMaterialIds: [for (final e in (map['guideMaterialIds'] as List? ?? const [])) e.toString()],
        theoryMaterialIds: [for (final e in (map['theoryMaterialIds'] as List? ?? const [])) e.toString()],
        prep: [
          for (final q in (map['prep'] as List? ?? const []))
            if (q is Map) LabQuestion.fromMap(Map<String, dynamic>.from(q)),
        ],
        parts: [
          for (final p in (map['parts'] as List? ?? const []))
            if (p is Map) LabPart.fromMap(Map<String, dynamic>.from(p)),
        ],
        report: [
          for (final s in (map['report'] as List? ?? const []))
            if (s is Map) LabReportSection.fromMap(Map<String, dynamic>.from(s)),
        ],
        hints: [for (final h in (map['hints'] as List? ?? const [])) h.toString()],
        finished: map['finished'] == true,
      );

  // -- Aus der KI-Antwort ---------------------------------------------------

  /// Baut einen Versuch aus der Struktur, die die KI aus der Anleitung gelesen
  /// hat (siehe AiService.structureLabExperiment): `title`, `prepQuestions`
  /// (`number`, `question`), `parts` (`title`, `goals`, `steps`, `tables`,
  /// `evaluationQuestions`) und `hints`. Fehlendes bleibt leer, Unbrauchbares
  /// fällt weg. Der Bericht bekommt Einleitung, je Versuchsteil einen
  /// Abschnitt und ein Fazit.
  factory LabExperiment.fromStructure(
    Map<String, dynamic> json, {
    required String moduleId,
    required DateTime now,
    String? id,
    String fallbackTitle = 'Laborversuch',
    List<String> guideMaterialIds = const [],
    List<String> theoryMaterialIds = const [],
    DateTime? labDate,
    DateTime? reportDue,
  }) {
    const uuid = Uuid();
    String text(Object? v) => (v ?? '').toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    List<String> texts(Object? v) => [
          if (v is List)
            for (final e in v)
              if (text(e).isNotEmpty) text(e),
        ];
    Map<String, dynamic>? asMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

    /// Fragen als Text oder als {number, question}; fehlende Nummern zählen
    /// fortlaufend ([prefix] für Auswertungsfragen: "2.").
    List<LabQuestion> questions(Object? raw, {String prefix = ''}) {
      final result = <LabQuestion>[];
      if (raw is! List) return result;
      for (final e in raw) {
        final map = asMap(e);
        final question = text(map == null ? e : (map['question'] ?? map['text']));
        if (question.isEmpty) continue;
        final number = map == null ? '' : text(map['number']);
        result.add(LabQuestion(
          id: uuid.v4(),
          number: number.isNotEmpty ? number : '$prefix${result.length + 1}',
          text: question,
        ));
      }
      return result;
    }

    final parts = <LabPart>[];
    final rawParts = json['parts'];
    for (final (i, e) in (rawParts is List ? rawParts : const []).indexed) {
      final map = asMap(e);
      if (map == null) continue;
      final title = text(map['title']);
      final rawTables = map['tables'] ?? (map['table'] == null ? null : [map['table']]);
      final tables = <LabTable>[
        for (final t in (rawTables is List ? rawTables : const []))
          if (asMap(t) case final tm?)
            if (LabTable.fromAi(tm) case final table when table.columns.isNotEmpty || table.rows.isNotEmpty) table,
      ];
      final part = LabPart(
        id: uuid.v4(),
        title: title.isEmpty ? 'Versuchsteil ${i + 1}' : title,
        goals: texts(map['goals']),
        steps: [for (final s in texts(map['steps'])) LabStep(text: s)],
        tables: tables,
        questions: questions(map['evaluationQuestions'] ?? map['questions'], prefix: '${parts.length + 1}.'),
      );
      if (part.steps.isEmpty && part.tables.isEmpty && part.questions.isEmpty && part.goals.isEmpty) continue;
      parts.add(part);
    }

    final title = text(json['title']);
    final report = <LabReportSection>[
      LabReportSection(
        id: uuid.v4(),
        title: 'Einleitung und Versuchsziel',
        hint: 'Worum geht es in dem Versuch, was soll er zeigen? Kurz und in eigenen Worten.',
      ),
      for (final part in parts)
        LabReportSection(
          id: uuid.v4(),
          title: part.title,
          partId: part.id,
          hint: [
            'Aufbau, Durchführung und Messergebnisse dieses Teils – nachvollziehbar, mit Einheiten.',
            if (part.questions.isNotEmpty)
              'Beantworte dabei: ${part.questions.map((q) => '${q.number} ${q.text}').join(' · ')}',
          ].join('\n'),
        ),
      LabReportSection(
        id: uuid.v4(),
        title: 'Diskussion und Fazit',
        hint: 'Was hast du gelernt? Wo weichen Messwerte von der Erwartung ab, und woran kann das liegen?',
      ),
    ];

    return LabExperiment(
      id: id ?? uuid.v4(),
      moduleId: moduleId,
      title: title.isEmpty ? fallbackTitle : title,
      createdAt: now,
      labDate: labDate,
      reportDue: reportDue,
      guideMaterialIds: guideMaterialIds,
      theoryMaterialIds: theoryMaterialIds,
      prep: questions(json['prepQuestions'] ?? json['prep']),
      parts: parts,
      report: report,
      hints: texts(json['hints']),
    );
  }
}
