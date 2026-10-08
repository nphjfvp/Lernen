import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/zoomable_image.dart';
import '../../models/flashcard.dart';
import '../../models/step_task.dart';
import '../../repositories/settings_repository.dart';
import '../../services/fsrs_service.dart';
import '../../services/step_checker.dart';
import '../../theme/app_colors.dart';
import '../study/explain_chat.dart';
import '../study/study_aids.dart';
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

enum _Mode { steps, result }

/// Rechenweg-Aufgabe beantworten ([QuestionType.steps]): Schritt für Schritt
/// mit Tipps und eigener Rückmeldung je Schritt, oder "Nur Ergebnis" mit
/// Probe. Die App prüft jede Eingabe selbst (StepChecker) – ohne KI. Auf
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
  });

  final Flashcard card;
  final StepTask task;
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

  /// Ergebnis einer Foto-Prüfung, falls der Nutzer von dort bewertet hat.
  Grade? _paperGrade;

  bool get _stepsFinished => _current >= _progress.length;
  bool get _finished =>
      _gaveUp || _paperGrade != null || (_mode == _Mode.steps ? _stepsFinished : (_resultSolved || _resultRevealed));

  bool get _anyRevealed => _gaveUp || _resultRevealed || _progress.any((p) => p.revealed);
  int get _wrongTotal => _progress.fold(0, (n, p) => n + p.wrong) + _resultWrong;

  StepField? get _finalField => widget.task.finalField;

  @override
  void dispose() {
    for (final p in _progress) {
      p.dispose();
    }
    _resultController.dispose();
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

  Future<void> _openPaperCheck() async {
    final outcome = await Navigator.of(context).push<PaperCheckOutcome>(
      MaterialPageRoute(builder: (_) => PaperCheckScreen(card: widget.card, task: widget.task)),
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
                    ButtonSegment(value: _Mode.steps, label: Text('Schritt für Schritt')),
                    ButtonSegment(value: _Mode.result, label: Text('Nur Ergebnis')),
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
        if (_mode == _Mode.steps) ..._buildSteps(c) else ..._buildResult(c),
        if (_finished) ..._buildFinish(c),
        if (!_finished && !widget.examMode) ..._buildFooter(c),
      ],
    );
  }

  Widget _image(String base64) {
    try {
      final bytes = base64Decode(base64);
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ZoomableImage(bytes: bytes),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
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
                  onChanged: () => setState(() {}),
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
              onChanged: () => setState(() {}),
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
