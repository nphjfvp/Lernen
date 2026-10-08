import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../models/sketch_task.dart';
import '../../services/fsrs_service.dart';
import '../../services/sketch_checker.dart';
import '../../theme/app_colors.dart';
import '../study/study_aids.dart';
import '../widgets/math_text.dart';
import '../widgets/zoomable_image.dart';
import 'sketch_canvas.dart';

/// Diagramm skizzieren ([QuestionType.sketch]): in vorgegebene Achsen eine
/// Kurve zeichnen und Kennwerte markieren. Die App prüft grob die Merkmale
/// (SketchChecker) und blendet danach die Musterkurve zum Vergleich ein.
///
/// Bewertung beim "Weiter": ohne Fehlversuch und Tipp = gewusst, sonst
/// Schwer; Lösung angesehen oder aufgelöst = Nochmal. Probeklausur: keine
/// Rückmeldung, "Antwort abgeben" wertet.
class SketchTaskView extends StatefulWidget {
  const SketchTaskView({
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
  final SketchTask task;
  final bool isNew;
  final bool examMode;
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;
  final VoidCallback? onSkip;
  final bool canGiveUp;

  @override
  State<SketchTaskView> createState() => _SketchTaskViewState();
}

class _SketchTaskViewState extends State<SketchTaskView> {
  final List<List<SketchPoint>> _strokes = [];
  final Map<String, SketchPoint> _marks = {};
  late final List<SketchMark> _referenceMarks = SketchChecker.referenceMarks(widget.task);
  late final List<String> _hints = SketchChecker.hints(widget.task);
  late String? _label = widget.task.marks.firstOrNull?.label;
  bool _markMode = false;
  SketchVerdict? _verdict;
  bool _solved = false;
  bool _revealed = false;
  bool _gaveUp = false;
  bool _submitted = false;
  int _wrong = 0;
  int _hintsShown = 0;

  bool get _finished => _solved || _revealed || _gaveUp;
  List<SketchMark> get _markList => [for (final e in _marks.entries) SketchMark(e.key, e.value)];

  void _submit({Grade? selfGrade, bool? isCorrect}) {
    if (_submitted) return;
    _submitted = true;
    widget.onComplete(selfGrade: selfGrade, isCorrect: isCorrect);
  }

  void _finish() {
    if (_gaveUp || _revealed) return _submit(isCorrect: false);
    if (_wrong == 0 && _hintsShown == 0) return _submit(isCorrect: true);
    _submit(isCorrect: true, selfGrade: Grade.hard);
  }

  void _check() {
    final v = SketchChecker.check(widget.task, _strokes, _markList);
    if (widget.examMode) return _submit(isCorrect: v.ok);
    setState(() {
      _verdict = v;
      if (v.ok) {
        _solved = true;
      } else {
        _wrong++;
      }
    });
  }

  void _changed(VoidCallback change) => setState(() {
    change();
    _verdict = null;
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = widget.card;
    final task = widget.task;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final hasMarks = task.marks.isNotEmpty;

    final canvas = SketchCanvas(
      key: const ValueKey('sketch-canvas'),
      task: task,
      height: wide ? 420 : 300,
      strokes: _strokes,
      marks: _markList,
      showReference: _finished && !widget.examMode,
      referenceMarks: _referenceMarks,
      onStrokeStart: _finished || _markMode ? null : (p) => _changed(() => _strokes.add([p])),
      onStrokeUpdate: _finished || _markMode
          ? null
          : (p) => setState(() {
              if (_strokes.isNotEmpty) _strokes.last.add(p);
            }),
      onStrokeEnd: () {},
      onTapPoint: _finished || !_markMode || _label == null ? null : (p) => _changed(() => _marks[_label!] = p),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (widget.isNew)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(20)),
              child: Text(
                'NEU',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.warn),
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      QuestionType.sketch.label,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accentOnSoft),
                    ),
                  ),
                  const Spacer(),
                  if (!widget.examMode) SourceLinkButton(card: card),
                ],
              ),
              const SizedBox(height: 10),
              if (card.imageBase64 != null) _image(card.imageBase64!),
              MathText(card.front, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.45)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (hasMarks && !_finished) ...[
          SegmentedButton<bool>(
            key: const ValueKey('sketch-mode'),
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.gesture, size: 18), label: Text('Zeichnen')),
              ButtonSegment(value: true, icon: Icon(Icons.place_outlined, size: 18), label: Text('Markieren')),
            ],
            selected: {_markMode},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _markMode = v.first),
          ),
          if (_markMode) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, m) in task.marks.indexed)
                  ChoiceChip(
                    key: ValueKey('sketch-label-$i'),
                    label: Text(m.label),
                    selected: _label == m.label,
                    avatar: _marks.containsKey(m.label) ? Icon(Icons.check, size: 16, color: c.good) : null,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _label = m.label),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
        Text(
          _finished
              ? 'Grün gestrichelt: die Musterkurve zum Vergleich.'
              : _markMode
              ? 'Wähle oben einen Kennwert und tippe die Stelle im Diagramm an.'
              : 'Zeichne die Kurve mit dem Finger bzw. der Maus – ein Sprung darf ein neuer Strich sein.',
          style: TextStyle(fontSize: 12.5, color: c.inkMuted),
        ),
        const SizedBox(height: 6),
        canvas,
        const SizedBox(height: 8),
        if (!_finished)
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey('sketch-undo'),
                onPressed: _strokes.isEmpty ? null : () => _changed(_strokes.removeLast),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Rückgängig'),
              ),
              TextButton.icon(
                key: const ValueKey('sketch-clear'),
                onPressed: _strokes.isEmpty && _marks.isEmpty
                    ? null
                    : () => _changed(() {
                        _strokes.clear();
                        _marks.clear();
                      }),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Alles löschen'),
              ),
            ],
          ),
        if (_verdict != null && !widget.examMode) ...[const SizedBox(height: 6), _verdictBox(c, _verdict!)],
        if (_revealed || _gaveUp) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('sketch-solution'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(14)),
            child: Text(SketchChecker.solutionText(task), style: const TextStyle(fontSize: 13.5, height: 1.45)),
          ),
        ],
        if (!widget.examMode)
          for (var h = 0; h < _hintsShown && h < _hints.length; h++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                key: ValueKey('sketch-hint-$h'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 18, color: c.warn),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_hints[h], style: const TextStyle(fontSize: 13.5, height: 1.4))),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 12),
        ..._buttons(c),
      ],
    );
  }

  Widget _image(String base64) {
    try {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ZoomableImage(bytes: base64Decode(base64)),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _verdictBox(AppColors c, SketchVerdict v) => Container(
    key: const ValueKey('sketch-verdict'),
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: v.ok ? c.goodSoft : c.dangerSoft, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          v.summary,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: v.ok ? c.good : c.danger),
        ),
        const SizedBox(height: 6),
        for (final (i, r) in v.results.indexed)
          Padding(
            key: ValueKey('sketch-result-$i'),
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  r.ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 17,
                  color: r.ok ? c.good : c.danger,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(r.message, style: const TextStyle(fontSize: 13.5, height: 1.35))),
              ],
            ),
          ),
      ],
    ),
  );

  List<Widget> _buttons(AppColors c) {
    if (widget.examMode) {
      return [
        FilledButton(key: const ValueKey('sketch-submit'), onPressed: _check, child: const Text('Antwort abgeben')),
      ];
    }
    if (_finished) {
      final clean = _solved && _wrong == 0 && _hintsShown == 0;
      return [
        Container(
          key: const ValueKey('sketch-finished'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: clean ? c.goodSoft : (_solved ? c.accentSoft : c.warnSoft),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _gaveUp
                ? 'Aufgelöst – zählt als nicht gewusst'
                : _revealed
                ? 'Mit angesehener Lösung – zählt als „Nochmal“'
                : (clean ? 'Gelöst – ohne Hilfe' : 'Gelöst – mit Hilfe, zählt als „Schwer“'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(key: const ValueKey('sketch-next'), onPressed: _finish, child: const Text('Weiter')),
      ];
    }
    return [
      Row(
        children: [
          OutlinedButton.icon(
            key: const ValueKey('sketch-hint-button'),
            onPressed: _hintsShown >= _hints.length ? null : () => setState(() => _hintsShown++),
            icon: const Icon(Icons.lightbulb_outline, size: 18),
            label: const Text('Tipp'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(key: const ValueKey('sketch-check'), onPressed: _check, child: const Text('Prüfen')),
          ),
        ],
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton(
            key: const ValueKey('sketch-reveal'),
            onPressed: () => setState(() => _revealed = true),
            child: const Text('Lösung zeigen'),
          ),
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
              onPressed: () => setState(() => _gaveUp = true),
              child: const Text('Auflösen'),
            ),
        ],
      ),
    ];
  }
}
