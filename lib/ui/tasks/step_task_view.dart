import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/zoomable_image.dart';
import '../../models/flashcard.dart';
import '../../models/paper_review.dart';
import '../../models/step_task.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/math_keys.dart';
import '../../services/step_checker.dart';
import '../../theme/app_colors.dart';
import '../study/explain_chat.dart';
import '../study/study_aids.dart';
import '../widgets/image_editor_screen.dart';
import '../widgets/math_text.dart';
import 'math_input_field.dart';
import 'paper_check_screen.dart';

/// Fortschritt eines Schritts.
class _StepProgress {
  _StepProgress(TaskStep step) : controllers = [for (final _ in step.fields) TextEditingController()];

  final List<TextEditingController> controllers;
  int? picked;
  List<FieldVerdict?> verdicts = const [];
  FieldVerdict? choiceVerdict;
  bool solved = false;

  /// Per "Schritt zeigen" aufgedeckt (zählt als nicht gewusst).
  bool revealed = false;

  /// Auf Papier richtig gerechnet (Foto-Prüfung) – zählt als gelöst.
  bool onPaper = false;
  int hintsShown = 0;
  int wrong = 0;

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

enum _Mode { steps, write, result }

/// Rechenweg-Aufgabe beantworten ([QuestionType.steps]): Schritt für Schritt
/// mit Tipps und eigener Rückmeldung je Schritt, „Selbst rechnen“ (eigene
/// Zeilen, beliebig viele, geprüft erst beim Abgeben – auf Wunsch Zeile für
/// Zeile von der KI) oder "Nur Ergebnis" mit Probe. Die App prüft jede Eingabe selbst (StepChecker) – ohne KI. Auf
/// Papier Gerechnetes lässt sich per Foto prüfen (PaperCheckScreen).
///
/// Bewertung beim "Weiter": ohne Fehlversuch und ohne Tipp gelöst = gewusst
/// (Gut), mit Tipps oder Fehlversuchen gelöst = Schwer, ein Schritt
/// aufgedeckt oder aufgelöst = Nochmal.
class StepTaskView extends StatefulWidget {
  const StepTaskView({
    super.key,
    required this.card,
    required this.task,
    required this.isNew,
    required this.onComplete,
    this.examMode = false,
    this.onSkip,
    this.canGiveUp = false,
    this.onWrongAnswer,
    this.onImageEdited,
  });

  final Flashcard card;
  final StepTask task;

  /// Test-Hook statt OpenRouter (Prüfen einer getippten Zeile).
  static AiService? Function(String apiKey, String model)? aiFactory;

  /// Gesetzt, wenn das Aufgabenbild hier bearbeitet werden darf (z.B. eine
  /// mitfotografierte Musterlösung abdecken oder wegschneiden) – bekommt das
  /// neue Bild zum Speichern, null = Bild entfernt.
  final Future<void> Function(Uint8List? bytes)? onImageEdited;

  /// Eine Eingabe war falsch (nicht leer, lesbar) – z.B. um sie in „Visuell
  /// lernen“ zu simulieren.
  final void Function(StepField field, String input)? onWrongAnswer;
  final bool isNew;
  final bool examMode;
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;
  final VoidCallback? onSkip;
  final bool canGiveUp;

  @override
  State<StepTaskView> createState() => _StepTaskViewState();
}

class _StepTaskViewState extends State<StepTaskView> {
  late final List<_StepProgress> _progress = [for (final s in widget.task.steps) _StepProgress(s)];
  late _Mode _mode = widget.examMode ? _Mode.result : _Mode.steps;
  int _current = 0;
  int _hintsUsed = 0;

  final _resultController = TextEditingController();
  FieldVerdict? _resultVerdict;
  ProbeReport? _resultProbe;
  int _resultWrong = 0;
  bool _resultSolved = false;
  bool _resultRevealed = false;

  bool _gaveUp = false;
  bool _submitted = false;

  // Selbst rechnen: eigene Zeilen, geprüft erst beim Abgeben.
  final List<TextEditingController> _lines = [TextEditingController()];
  final List<FocusNode> _lineFocus = [FocusNode()];
  int _focusedLine = 0;
  final _writeResult = TextEditingController();
  FieldVerdict? _writeVerdict;
  ProbeReport? _writeProbe;

  /// Je Zeile: welcher Musterlösungs-Schritt (0-basiert) darin steckt, falls
  /// die App es nachrechnen konnte – nur nach dem Abgeben.
  List<int?> _lineMatches = const [];
  int _writeWrong = 0;

  /// Prüfung je Zeile („Prüfen“ hinter der Zeile) – an den Controller
  /// gebunden, damit sie beim Einfügen/Löschen von Zeilen mitwandert.
  final Map<TextEditingController, PaperLine> _lineChecks = {};
  final Set<TextEditingController> _lineBusy = {};
  final Set<TextEditingController> _lineShowFix = {};
  bool _writeSolved = false;
  bool _writeRevealed = false;


  /// Ergebnis einer Foto-Prüfung, falls der Nutzer von dort bewertet hat.
  Grade? _paperGrade;

  bool get _stepsFinished => _current >= _progress.length;
  bool get _finished =>
      _gaveUp ||
      _paperGrade != null ||
      switch (_mode) {
        _Mode.steps => _stepsFinished,
        _Mode.write => _writeSolved || _writeRevealed,
        _Mode.result => _resultSolved || _resultRevealed,
      };

  bool get _anyRevealed => _gaveUp || _resultRevealed || _writeRevealed || _progress.any((p) => p.revealed);
  int get _wrongTotal => _progress.fold(0, (n, p) => n + p.wrong) + _resultWrong + _writeWrong;

  StepField? get _finalField => widget.task.finalField;

  @override
  void dispose() {
    for (final p in _progress) {
      p.dispose();
    }
    _resultController.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    for (final f in _lineFocus) {
      f.dispose();
    }
    _writeResult.dispose();
    super.dispose();
  }

  void _submit({Grade? selfGrade, bool? isCorrect}) {
    if (_submitted) return;
    _submitted = true;
    widget.onComplete(selfGrade: selfGrade, isCorrect: isCorrect);
  }

  void _finishAndSubmit() {
    final paper = _paperGrade;
    if (paper != null) return _submit(selfGrade: paper);
    if (_anyRevealed) return _submit(isCorrect: false);
    if (_hintsUsed == 0 && _wrongTotal == 0) return _submit(isCorrect: true);
    _submit(isCorrect: true, selfGrade: Grade.hard);
  }

  // -------------------------------------------------------------------------
  // Schritt für Schritt
  // -------------------------------------------------------------------------

  void _checkStep() {
    if (_stepsFinished) return;
    final step = widget.task.steps[_current];
    final p = _progress[_current];
    setState(() {
      if (step.isChoice) {
        final v = StepChecker.checkOption(step, p.picked ?? -1);
        p.choiceVerdict = v;
        if (v.isAttempt) p.wrong++;
        if (v.isCorrect) _complete(p);
        return;
      }
      final verdicts = [
        for (final (i, f) in step.fields.indexed) StepChecker.check(f, p.controllers[i].text),
      ];
      p.verdicts = verdicts;
      for (final (i, v) in verdicts.indexed) {
        if (v.isAttempt && !v.isCorrect) widget.onWrongAnswer?.call(step.fields[i], p.controllers[i].text);
      }
      // Was die App nicht nachrechnen kann, zählt (mit Hinweis) als richtig.
      final ok = verdicts.every((v) => v.isCorrect || v.kind == FieldVerdictKind.uncheckable);
      if (ok) {
        _complete(p);
      } else if (verdicts.any((v) => v.isAttempt)) {
        p.wrong++;
      }
    });
  }

  void _complete(_StepProgress p) {
    p.solved = true;
    _current++;
  }

  void _showHint() {
    final step = widget.task.steps[_current];
    final p = _progress[_current];
    if (p.hintsShown >= step.hints.length) return;
    setState(() {
      p.hintsShown++;
      _hintsUsed++;
    });
  }

  void _revealStep() {
    final p = _progress[_current];
    setState(() {
      p.revealed = true;
      p.solved = true;
      _current++;
    });
  }

  // -------------------------------------------------------------------------
  // Nur Ergebnis
  // -------------------------------------------------------------------------

  void _checkResult() {
    final field = _finalField;
    if (field == null) return;
    final verdict = StepChecker.check(field, _resultController.text);
    if (widget.examMode) {
      _submit(isCorrect: verdict.isCorrect);
      return;
    }
    setState(() {
      _resultVerdict = verdict;
      _resultProbe = verdict.kind == FieldVerdictKind.empty || verdict.kind == FieldVerdictKind.invalid
          ? null
          : StepChecker.probe(widget.task, _resultController.text);
      if (verdict.isCorrect || verdict.kind == FieldVerdictKind.uncheckable) {
        _resultSolved = true;
      } else if (verdict.isAttempt) {
        _resultWrong++;
        widget.onWrongAnswer?.call(field, _resultController.text);
      }
    });
  }

  void _giveUp() {
    setState(() {
      _gaveUp = true;
      for (final p in _progress) {
        if (!p.solved) p.revealed = true;
        p.solved = true;
      }
      _current = _progress.length;
      _mode = _Mode.steps;
    });
  }

  // -------------------------------------------------------------------------
  // Selbst rechnen
  // -------------------------------------------------------------------------

  List<String> get _writtenLines => [
    for (final l in _lines)
      if (l.text.trim().isNotEmpty) l.text.trim(),
  ];

  /// Was als Ergebnis zählt: das Ergebnisfeld, sonst die rechte Seite der
  /// letzten Zeile.
  String get _writtenResult {
    final r = _writeResult.text.trim();
    if (r.isNotEmpty) return r;
    final last = _writtenLines.lastOrNull ?? '';
    return _plainMath(last.split('=').last);
  }

  /// Eingabe geändert: alte Rückmeldung weg (die nächste kommt erst beim
  /// Abgeben), „Abgeben“ ggf. freischalten.
  void _writeChanged() {
    setState(() {
      _writeVerdict = null;
      _writeProbe = null;
      _lineMatches = const [];
    });
  }

  void _addLine({bool focus = true}) {
    final node = FocusNode();
    setState(() {
      _lines.add(TextEditingController());
      _lineFocus.add(node);
      _focusedLine = _lines.length - 1;
    });
    if (focus) WidgetsBinding.instance.addPostFrameCallback((_) => node.requestFocus());
  }

  void _removeLine(int i) {
    if (_lines.length <= 1) return;
    final c = _lines.removeAt(i);
    final f = _lineFocus.removeAt(i);
    _lineEdited(c);
    _lineBusy.remove(c);
    setState(() {
      _focusedLine = _focusedLine.clamp(0, _lines.length - 1);
      _lineMatches = const [];
      _writeVerdict = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c.dispose();
      f.dispose();
    });
  }

  /// Zeichen in die zuletzt angetippte Zeile einfügen.
  void _insertInLine(String text) {
    final i = _focusedLine.clamp(0, _lines.length - 1);
    final c = _lines[i];
    final sel = c.selection;
    final start = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    c.value = TextEditingValue(
      text: c.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _lineFocus[i].requestFocus();
    _lineEdited(c);
    _writeChanged();
  }

  /// Getippte Sonderzeichen in die Schreibweise der App-Prüfung.
  static String _plainMath(String s) =>
      s.replaceAll('−', '-').replaceAll('·', '*').replaceAll('×', '*').replaceAll('⇒', '').trim();

  void _lineEdited(TextEditingController ctrl) {
    _lineChecks.remove(ctrl);
    _lineShowFix.remove(ctrl);
  }

  AiService? _stepAi() {
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings == null || !settings.hasApiKey) return null;
    return StepTaskView.aiFactory?.call(settings.openRouterApiKey!, settings.questionModelId) ??
        AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
  }

  /// „Prüfen“ hinter einer Zeile: erst rechnet die App selbst (entspricht die
  /// Zeile einem Schritt der Musterlösung?), sonst prüft die KI genau diese
  /// Zeile im Zusammenhang der Zeilen davor – ohne Weiteres zu verraten.
  Future<void> _checkLine(int i) async {
    final ctrl = _lines[i];
    final text = ctrl.text.trim();
    if (text.isEmpty || _lineBusy.contains(ctrl)) return;
    final match = _matchLine(text);
    if (match != null) {
      setState(
        () => _lineChecks[ctrl] = PaperLine(
          n: i + 1,
          text: text,
          comment: 'Stimmt – das ist Schritt ${match + 1} der Musterlösung („${widget.task.steps[match].title}“).',
        ),
      );
      return;
    }
    final ai = _stepAi();
    if (ai == null) {
      setState(
        () => _lineChecks[ctrl] = PaperLine(
          n: i + 1,
          text: text,
          status: PaperLineStatus.unclear,
          comment:
              'Diesen Zwischenschritt kann die App nicht selbst nachrechnen – mit deinem OpenRouter-Key '
              '(Einstellungen) prüft ihn die KI.',
        ),
      );
      return;
    }
    setState(() => _lineBusy.add(ctrl));
    PaperLine result;
    try {
      result = await ai.checkTypedStep(
        task: widget.card.front,
        solution: widget.task,
        solutionText: widget.card.back,
        previous: [
          for (final l in _lines.take(i))
            if (l.text.trim().isNotEmpty) l.text.trim(),
        ],
        line: text,
      );
    } on AiServiceException catch (e) {
      result = PaperLine(n: i + 1, text: text, status: PaperLineStatus.unclear, comment: e.message);
    } catch (e) {
      result = PaperLine(n: i + 1, text: text, status: PaperLineStatus.unclear, comment: 'Prüfen fehlgeschlagen: $e');
    }
    if (!mounted) return;
    setState(() {
      _lineBusy.remove(ctrl);
      // Inzwischen geändert oder gelöscht: das Ergebnis gilt nicht mehr.
      if (!_lines.contains(ctrl) || ctrl.text.trim() != text) return;
      _lineChecks[ctrl] = result;
      if (result.status == PaperLineStatus.error) _writeWrong++;
    });
  }

  /// Welcher Musterlösungs-Schritt in einer Zeile steckt (rechte Seite gegen
  /// die Felder jedes Schritts) – null, wenn die App es nicht zuordnen kann.
  int? _matchLine(String line) {
    final rhs = _plainMath(line.split('=').last);
    if (rhs.isEmpty) return null;
    for (final (j, s) in widget.task.steps.indexed) {
      for (final f in s.fields) {
        try {
          if (StepChecker.check(f, rhs).isCorrect) return j;
        } catch (_) {
          // Nicht lesbar – dann eben nicht zuordenbar.
        }
      }
    }
    return null;
  }

  /// „Abgeben“: erst jetzt wird geprüft – das Ergebnis von der App, die
  /// Zeilen, soweit sie sich Schritten der Musterlösung zuordnen lassen.
  void _submitWritten() {
    final field = _finalField;
    final answer = _writtenResult;
    if (answer.isEmpty && _writtenLines.isEmpty) return;
    setState(() {
      _lineMatches = [for (final l in _lines) l.text.trim().isEmpty ? null : _matchLine(l.text)];
      if (field == null) {
        _writeVerdict = const FieldVerdict(FieldVerdictKind.uncheckable, 'Diese Aufgabe hat kein Ergebnisfeld.');
        return;
      }
      final verdict = StepChecker.check(field, answer);
      _writeVerdict = verdict;
      _writeProbe = verdict.kind == FieldVerdictKind.empty || verdict.kind == FieldVerdictKind.invalid
          ? null
          : StepChecker.probe(widget.task, answer);
      if (verdict.isCorrect || verdict.kind == FieldVerdictKind.uncheckable) {
        _writeSolved = true;
      } else if (verdict.isAttempt) {
        _writeWrong++;
        widget.onWrongAnswer?.call(field, answer);
      }
    });
  }

  Future<void> _openPaperCheck({List<String>? typedLines}) async {
    final outcome = await Navigator.of(context).push<PaperCheckOutcome>(
      MaterialPageRoute(
        builder: (_) => PaperCheckScreen(card: widget.card, task: widget.task, typedLines: typedLines),
      ),
    );
    if (outcome == null || !mounted) return;
    setState(() {
      final at = outcome.continueAtStep;
      if (at != null) {
        // Bis zum ersten Fehler auf Papier richtig – ab dort Schritt für Schritt.
        _mode = _Mode.steps;
        final start = at.clamp(0, _progress.length);
        for (var i = 0; i < start; i++) {
          final p = _progress[i];
          if (!p.solved) {
            p.solved = true;
            p.onPaper = true;
          }
        }
        if (_current < start) _current = start;
        // Ein Fehler auf Papier zählt wie ein Fehlversuch.
        if (_current < _progress.length) _progress[_current].wrong++;
      } else if (outcome.grade != null) {
        _paperGrade = outcome.grade;
      }
    });
    if (outcome.grade != null && outcome.continueAtStep == null) _finishAndSubmit();
  }

  // -------------------------------------------------------------------------
  // Anzeige
  // -------------------------------------------------------------------------

  bool get _aiAvailable => context.read<SettingsRepository?>()?.settings.hasApiKey ?? false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = widget.card;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (widget.isNew)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(20)),
              child: Text('NEU', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.warn)),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                child: Text(QuestionType.steps.label,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
              ),
              const SizedBox(height: 12),
              if (card.imageBase64 != null) _image(card.imageBase64!),
              MathText(card.front, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, height: 1.45)),
            ],
          ),
        ),
        if (!widget.examMode) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<_Mode>(
                  key: const ValueKey('step-mode'),
                  segments: const [
                    ButtonSegment(
                      value: _Mode.steps,
                      label: Text('Schritt für Schritt', textAlign: TextAlign.center),
                    ),
                    ButtonSegment(
                      value: _Mode.write,
                      label: Text('Selbst rechnen', key: ValueKey('step-mode-write'), textAlign: TextAlign.center),
                    ),
                    ButtonSegment(value: _Mode.result, label: Text('Nur Ergebnis', textAlign: TextAlign.center)),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: _finished ? null : (s) => setState(() => _mode = s.first),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(alignment: Alignment.centerLeft, child: SourceLinkButton(card: card)),
          ),
        ],
        const SizedBox(height: 8),
        ...switch (_mode) {
          _Mode.steps => _buildSteps(c),
          _Mode.write => _buildWrite(c),
          _Mode.result => _buildResult(c),
        },
        if (_finished) ..._buildFinish(c),
        if (!_finished && !widget.examMode) ..._buildFooter(c),
      ],
    );
  }

  Uint8List? _editedImage;
  bool _imageRemoved = false;

  Future<void> _editImage(Uint8List bytes) async {
    final save = widget.onImageEdited;
    if (save == null) return;
    final result = await showImageEditor(context, bytes, title: 'Aufgabenbild bearbeiten');
    if (result == null || !result.imageChanged || !mounted) return;
    setState(() => _editedImage = result.bytes);
    await save(result.bytes);
  }

  Future<void> _removeImage() async {
    final save = widget.onImageEdited;
    if (save == null) return;
    setState(() => _imageRemoved = true);
    await save(null);
  }

  Widget _image(String base64) {
    final Uint8List bytes;
    try {
      bytes = _editedImage ?? base64Decode(base64);
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (_imageRemoved) return const SizedBox.shrink();
    final canEdit = widget.onImageEdited != null && !widget.examMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          ZoomableImage(bytes: bytes),
          if (canEdit)
            Positioned(
              top: 4,
              right: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    key: const ValueKey('step-image-remove'),
                    tooltip: 'Bild entfernen',
                    visualDensity: VisualDensity.compact,
                    onPressed: _removeImage,
                    icon: const Icon(Icons.hide_image_outlined, size: 18),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    key: const ValueKey('step-image-edit'),
                    tooltip: 'Bild bearbeiten (z.B. Musterlösung abdecken oder wegschneiden)',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editImage(bytes),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSteps(AppColors c) {
    final steps = widget.task.steps;
    final solved = _progress.where((p) => p.solved).length;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text('Schritt ${(_current + 1).clamp(1, steps.length)} von ${steps.length}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: steps.isEmpty ? 0 : solved / steps.length,
                  minHeight: 6,
                  backgroundColor: c.surfaceAlt,
                ),
              ),
            ),
          ],
        ),
      ),
      for (var i = 0; i < steps.length; i++)
        if (i < _current)
          _doneStep(c, i)
        else if (i == _current)
          _activeStep(c, i)
        else
          _lockedStep(c, i),
    ];
  }

  Widget _doneStep(AppColors c, int i) {
    final step = widget.task.steps[i];
    final p = _progress[i];
    final (icon, color, note) = p.revealed
        ? (Icons.visibility_outlined, c.warn, 'aufgedeckt')
        : p.onPaper
            ? (Icons.edit_note, c.good, 'auf Papier gelöst')
            : (Icons.check_circle, c.good, p.wrong > 0 ? '${p.wrong}× daneben' : '');
    return Container(
      key: ValueKey('step-done-$i'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}. ${step.title}${note.isEmpty ? '' : ' · $note'}',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
                const SizedBox(height: 4),
                MathText(step.resultText, style: const TextStyle(fontSize: 15.5)),
                if ((p.revealed || _finished) && step.explanation.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: MathText(step.explanation, style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lockedStep(AppColors c, int i) {
    return Padding(
      key: ValueKey('step-locked-$i'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Icon(Icons.radio_button_unchecked, size: 18, color: c.border),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${i + 1}. ${widget.task.steps[i].title}',
                style: TextStyle(fontSize: 13, color: c.inkMuted.withValues(alpha: 0.75))),
          ),
        ],
      ),
    );
  }

  Widget _activeStep(AppColors c, int i) {
    final step = widget.task.steps[i];
    final p = _progress[i];
    final canCheck = step.isChoice ? p.picked != null : p.controllers.any((ctrl) => ctrl.text.trim().isNotEmpty);
    final hintsLeft = p.hintsShown < step.hints.length;
    return Container(
      key: ValueKey('step-active-$i'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.accent, width: 1.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${i + 1}. ${step.title}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          if (step.prompt.trim().isNotEmpty && step.prompt.trim() != step.title.trim())
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: MathText(step.prompt, style: const TextStyle(fontSize: 14, height: 1.4)),
            ),
          const SizedBox(height: 12),
          if (step.isChoice)
            for (final (k, o) in step.options.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  key: ValueKey('step-option-$i-$k'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() {
                    p.picked = k;
                    p.choiceVerdict = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.picked == k ? c.accentSoft : c.surfaceAlt,
                      border: Border.all(color: p.picked == k ? c.accent : c.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(p.picked == k ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 18, color: p.picked == k ? c.accent : c.inkMuted),
                        const SizedBox(width: 10),
                        Expanded(child: MathText(o.text, style: const TextStyle(fontSize: 14.5))),
                      ],
                    ),
                  ),
                ),
              )
          else
            for (final (k, f) in step.fields.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MathInputField(
                  key: ValueKey('step-field-$i-$k'),
                  fieldKey: ValueKey('step-input-$i-$k'),
                  field: f,
                  controller: p.controllers[k],
                  verdict: k < p.verdicts.length ? p.verdicts[k] : null,
                  autofocus: i > 0 && k == 0,
                  // Alte Rückmeldung weg, sobald weitergetippt wird – die
                  // nächste kommt erst beim Prüfen.
                  onChanged: () => setState(() => p.verdicts = const []),
                  onSubmitted: _checkStep,
                ),
              ),
          if (p.choiceVerdict != null) VerdictBox(verdict: p.choiceVerdict!),
          for (final (k, v) in p.verdicts.indexed)
            if (!v!.isCorrect)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: VerdictBox(
                  verdict: step.fields.length > 1
                      ? FieldVerdict(v.kind, '${_plain(step.fields[k].label)} ${v.message}')
                      : v,
                ),
              ),
          for (var h = 0; h < p.hintsShown; h++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                key: ValueKey('step-hint-$i-$h'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 18, color: c.warn),
                    const SizedBox(width: 8),
                    Expanded(child: MathText(step.hints[h], style: const TextStyle(fontSize: 13.5, height: 1.4))),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                key: ValueKey('step-check-$i'),
                onPressed: canCheck ? _checkStep : null,
                child: const Text('Prüfen'),
              ),
              if (hintsLeft)
                TextButton.icon(
                  key: ValueKey('step-hint-button-$i'),
                  onPressed: _showHint,
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: Text(p.hintsShown == 0 ? 'Tipp' : 'Noch ein Tipp'),
                ),
              if (!hintsLeft || p.wrong > 0)
                TextButton(
                  key: ValueKey('step-reveal-$i'),
                  onPressed: _revealStep,
                  child: const Text('Schritt zeigen'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _plain(String label) => label.replaceAll(r'$', '').trim();

  List<Widget> _buildResult(AppColors c) {
    final field = _finalField;
    if (field == null) {
      return [Text('Diese Aufgabe hat kein Ergebnisfeld.', style: TextStyle(color: c.inkMuted))];
    }
    final label = widget.task.finalLabel.trim().isNotEmpty ? widget.task.finalLabel : field.label;
    final displayField = StepField(
      label: label,
      answer: field.answer,
      kind: field.kind,
      variables: field.variables,
      constants: field.constants,
    );
    final solved = _resultSolved || _resultRevealed;
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.examMode ? 'Dein Ergebnis' : 'Rechne auf Papier und gib nur das Ergebnis ein.',
                style: TextStyle(fontSize: 13, color: c.inkMuted)),
            const SizedBox(height: 10),
            MathInputField(
              key: const ValueKey('step-result-field'),
              fieldKey: const ValueKey('step-result-input'),
              field: displayField,
              controller: _resultController,
              enabled: !solved,
              verdict: widget.examMode ? null : _resultVerdict,
              onChanged: () => setState(() {
                _resultVerdict = null;
                _resultProbe = null;
              }),
              onSubmitted: solved ? null : _checkResult,
            ),
            if (!widget.examMode && _resultVerdict != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: VerdictBox(verdict: _resultVerdict!)),
            if (_resultRevealed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MathText('Lösung: ${field.label} ${field.answer}'.trim(), style: const TextStyle(fontSize: 15)),
              ),
            const SizedBox(height: 10),
            if (!solved)
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: const ValueKey('step-result-check'),
                    onPressed: _resultController.text.trim().isEmpty ? null : _checkResult,
                    child: Text(widget.examMode ? 'Antwort abgeben' : 'Prüfen'),
                  ),
                  if (!widget.examMode && _resultWrong > 0)
                    TextButton(
                      key: const ValueKey('step-result-reveal'),
                      onPressed: () => setState(() => _resultRevealed = true),
                      child: const Text('Lösung zeigen'),
                    ),
                ],
              ),
          ],
        ),
      ),
      if (!widget.examMode && _resultProbe != null && !_resultSolved)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ProbeCard(report: _resultProbe!, title: 'Probe deines Ergebnisses – rechnet die App'),
        ),
    ];
  }

  List<Widget> _buildWrite(AppColors c) {
    final field = _finalField;
    final done = _writeSolved || _writeRevealed;
    final keys = MathKeys.forTask(widget.task, text: widget.card.front);
    final displayField = field == null
        ? null
        : StepField(
            label: widget.task.finalLabel.trim().isNotEmpty ? widget.task.finalLabel : field.label,
            answer: field.answer,
            kind: field.kind,
            variables: field.variables,
            constants: field.constants,
          );
    final matched = {for (final m in _lineMatches) ?m};
    return [
      Container(
        key: const ValueKey('step-write'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rechne selbst – eine Zeile je Rechenschritt, so viele du brauchst. Mit ✓ hinter einer Zeile prüfst du '
              'genau diesen Schritt; „Abgeben“ prüft das Ergebnis.',
              style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.35),
            ),
            const SizedBox(height: 10),
            for (final (i, line) in _lines.indexed) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${i + 1}.',
                        style: TextStyle(fontWeight: FontWeight.w600, color: c.inkMuted),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: ValueKey('step-line-$i'),
                        controller: line,
                        focusNode: _lineFocus[i],
                        enabled: !done,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(fontSize: 15.5),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: i == 0 ? 'z.B. v(t) = ∫ a(t) dt = 2t + C' : 'nächster Schritt',
                          filled: true,
                          fillColor: c.surfaceAlt,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        onTap: () => _focusedLine = i,
                        onChanged: (_) {
                          _focusedLine = i;
                          _lineEdited(line);
                          _writeChanged();
                        },
                        onSubmitted: (_) {
                          if (i == _lines.length - 1 && line.text.trim().isNotEmpty) {
                            _addLine();
                          } else if (i + 1 < _lines.length) {
                            _lineFocus[i + 1].requestFocus();
                          }
                        },
                      ),
                    ),
                    if (!done)
                      _lineBusy.contains(line)
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(
                              key: ValueKey('step-line-check-$i'),
                              tooltip: 'Diesen Schritt prüfen',
                              visualDensity: VisualDensity.compact,
                              onPressed: line.text.trim().isEmpty ? null : () => _checkLine(i),
                              icon: Icon(Icons.task_alt, size: 20, color: c.accent),
                            ),
                    if (i < _lineMatches.length && _lineMatches[i] != null && _lineChecks[line] == null)
                      Tooltip(
                        message: 'Entspricht Schritt ${_lineMatches[i]! + 1} der Musterlösung',
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(Icons.check_circle, key: ValueKey('step-line-ok-$i'), color: c.good, size: 20),
                        ),
                      ),
                    if (_lines.length > 1 && !done)
                      IconButton(
                        key: ValueKey('step-line-remove-$i'),
                        tooltip: 'Zeile entfernen',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeLine(i),
                        icon: Icon(Icons.close, size: 18, color: c.inkMuted),
                      ),
                  ],
                ),
              ),
              if (_lineChecks[line] case final check?) _lineCheckBox(c, i, line, check),
            ],
            if (!done) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('step-line-add'),
                  onPressed: _addLine,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Weiterer Schritt'),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in keys)
                    ActionChip(
                      key: ValueKey('step-line-key-$k'),
                      label: Text(k, style: const TextStyle(fontSize: 13.5)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _insertInLine(k),
                    ),
                ],
              ),
            ],
            if (displayField != null) ...[
              const SizedBox(height: 14),
              Text(
                'Ergebnis (leer = rechte Seite der letzten Zeile)',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted),
              ),
              const SizedBox(height: 6),
              MathInputField(
                key: const ValueKey('step-write-result-field'),
                fieldKey: const ValueKey('step-write-result'),
                field: displayField,
                controller: _writeResult,
                enabled: !done,
                verdict: _writeVerdict,
                onChanged: _writeChanged,
                onSubmitted: done ? null : _submitWritten,
              ),
            ],
            if (_writeVerdict != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: VerdictBox(verdict: _writeVerdict!),
              ),
            if (_lineMatches.isNotEmpty && _writtenLines.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  matched.isEmpty
                      ? 'Deine Zwischenschritte konnte die App keinem Schritt der Musterlösung zuordnen – das heißt nicht, '
                            'dass sie falsch sind. Die KI kann jede Zeile prüfen.'
                      : '${matched.length} von ${widget.task.steps.length} Schritten der Musterlösung stecken in deinen '
                            'Zeilen (✓).',
                  key: const ValueKey('step-write-matches'),
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35),
                ),
              ),
            if (_writeRevealed && field != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MathText('Lösung: ${field.label} ${field.answer}'.trim(), style: const TextStyle(fontSize: 15)),
              ),
            if (!done) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('step-write-submit'),
                    onPressed: _writtenLines.isEmpty && _writeResult.text.trim().isEmpty ? null : _submitWritten,
                    icon: const Icon(Icons.task_alt, size: 18),
                    label: const Text('Abgeben'),
                  ),
                  if (_writeWrong > 0) ...[
                    TextButton(
                      key: const ValueKey('step-write-reveal'),
                      onPressed: () => setState(() => _writeRevealed = true),
                      child: const Text('Lösung zeigen'),
                    ),
                    TextButton(
                      key: const ValueKey('step-write-guided'),
                      onPressed: () => setState(() => _mode = _Mode.steps),
                      child: const Text('Geführt weiter'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
      if (_aiAvailable && _writtenLines.isNotEmpty && _paperGrade == null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton.icon(
            key: const ValueKey('step-write-ai'),
            onPressed: () => _openPaperCheck(typedLines: _writtenLines),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Rechenweg Zeile für Zeile von der KI prüfen lassen'),
          ),
        ),
      if (_writeProbe != null && !_writeSolved)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ProbeCard(report: _writeProbe!, title: 'Probe deines Ergebnisses – rechnet die App'),
        ),
    ];
  }

  /// Ergebnis von „Prüfen“ unter einer Zeile; die Korrektur erst auf Wunsch.
  Widget _lineCheckBox(AppColors c, int i, TextEditingController line, PaperLine check) {
    final (icon, color, bg) = switch (check.status) {
      PaperLineStatus.ok => (Icons.check_circle, c.good, c.goodSoft),
      PaperLineStatus.error => (Icons.cancel_outlined, c.danger, c.dangerSoft),
      PaperLineStatus.follow => (Icons.subdirectory_arrow_right, c.warn, c.warnSoft),
      PaperLineStatus.unclear => (Icons.help_outline, c.inkMuted, c.surfaceAlt),
    };
    final showFix = _lineShowFix.contains(line);
    return Container(
      key: ValueKey('step-line-result-$i'),
      margin: const EdgeInsets.only(left: 26, bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: MathText(
                  check.comment.isEmpty ? check.status.label : check.comment,
                  style: const TextStyle(fontSize: 13.5, height: 1.35),
                ),
              ),
            ],
          ),
          if (check.fix.isNotEmpty && check.status != PaperLineStatus.ok)
            showFix
                ? Padding(
                    padding: const EdgeInsets.only(top: 6, left: 26),
                    child: MathText('Richtig wäre: ${check.fix}', style: const TextStyle(fontSize: 14)),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: ValueKey('step-line-fix-$i'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => setState(() => _lineShowFix.add(line)),
                      child: const Text('Korrektur zeigen'),
                    ),
                  ),
        ],
      ),
    );
  }

  List<Widget> _buildFooter(AppColors c) {
    return [
      const SizedBox(height: 10),
      if (_aiAvailable)
        OutlinedButton.icon(
          key: const ValueKey('step-paper'),
          onPressed: _openPaperCheck,
          icon: const Icon(Icons.photo_camera_outlined, size: 18),
          label: const Text('Auf Papier gerechnet? Foto prüfen lassen'),
        ),
      if (widget.onSkip != null || widget.canGiveUp)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.onSkip != null)
              TextButton(
                key: const ValueKey('question-skip'),
                onPressed: () {
                  if (_submitted) return;
                  _submitted = true;
                  widget.onSkip!();
                },
                child: const Text('Überspringen'),
              ),
            if (widget.canGiveUp)
              TextButton(
                key: const ValueKey('question-give-up'),
                onPressed: _giveUp,
                child: const Text('Auflösen'),
              ),
          ],
        ),
    ];
  }

  List<Widget> _buildFinish(AppColors c) {
    final task = widget.task;
    final field = _finalField;
    final probe = field == null ? null : StepChecker.probe(task, field.answer);
    final title = _gaveUp
        ? 'Aufgelöst – zählt als nicht gewusst'
        : _anyRevealed
            ? 'Mit aufgedecktem Schritt gelöst'
            : (_hintsUsed == 0 && _wrongTotal == 0 ? 'Gelöst – ohne Hilfe' : 'Gelöst – mit Hilfe');
    final good = !_anyRevealed && _hintsUsed == 0 && _wrongTotal == 0;
    return [
      const SizedBox(height: 10),
      Container(
        key: const ValueKey('step-finished'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: good ? c.goodSoft : (_anyRevealed ? c.warnSoft : c.accentSoft),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (field != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: MathText('${field.label} ${field.answer}'.trim(), style: const TextStyle(fontSize: 16)),
              ),
            if (task.domainNote.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: MathText(task.domainNote, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
              ),
            if (_hintsUsed > 0 || _wrongTotal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    if (_wrongTotal > 0) '$_wrongTotal Fehlversuch${_wrongTotal == 1 ? '' : 'e'}',
                    if (_hintsUsed > 0) '$_hintsUsed Tipp${_hintsUsed == 1 ? '' : 's'}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                ),
              ),
          ],
        ),
      ),
      if (probe != null && probe.rows.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 10), child: ProbeCard(report: probe)),
      if (!widget.examMode && _aiAvailable)
        ExplainChat(
          question: widget.card.promptText,
          correctAnswer: widget.card.back.trim().isNotEmpty ? widget.card.back : (field == null ? '' : field.answer),
          wasCorrect: !_anyRevealed,
        ),
      const SizedBox(height: 14),
      FilledButton(
        key: const ValueKey('step-next'),
        onPressed: _finishAndSubmit,
        child: const Text('Weiter'),
      ),
    ];
  }
}
