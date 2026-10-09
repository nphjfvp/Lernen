import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../models/phase_task.dart';
import '../../models/sketch_task.dart';
import '../../services/fsrs_service.dart';
import '../../services/phase_calculator.dart';
import '../../services/sketch_checker.dart';
import '../../theme/app_colors.dart';
import '../study/study_aids.dart';
import '../widgets/math_text.dart';
import '../widgets/zoomable_image.dart';
import 'phase_diagram_canvas.dart';
import 'sketch_canvas.dart';

/// Stand einer Teilaufgabe.
class _PartState {
  final Set<String> phases = {};
  final Map<String, TextEditingController> fields = {};
  final Map<int, PhaseRegion?> regions = {};
  PhasePoint? tapped;

  /// Abkühlkurven: Striche je Kurve, gerade gezeichnete Kurve.
  Map<String, List<List<SketchPoint>>> cooling = {};
  String? coolingCurrent;
  PhaseCheck? verdict;
  bool solved = false;
  bool revealed = false;
  int wrong = 0;
  int hintsShown = 0;

  TextEditingController field(String key) => fields.putIfAbsent(key, TextEditingController.new);
  double? number(String key) => double.tryParse((fields[key]?.text ?? '').trim().replaceAll(',', '.'));

  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
  }
}

/// Zustandsdiagramm üben ([QuestionType.phase]): die App zeichnet das
/// Zweistoffsystem aus den Eckdaten; je Teilaufgabe werden Phasen gewählt,
/// der Hebel eingezeichnet (zweimal antippen) bzw. Werte eingetragen,
/// Abkühlkurven skizziert oder Gebiete benannt – die App rechnet alles
/// selbst nach (PhaseCalculator).
///
/// Bewertung beim "Weiter": ohne Fehlversuch und Tipp = gewusst, sonst
/// Schwer; Lösung angesehen oder aufgelöst = Nochmal. Probeklausur: keine
/// Rückmeldung, "Antwort abgeben" wertet alle Teile.
class PhaseTaskView extends StatefulWidget {
  const PhaseTaskView({
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
  final PhaseTask task;
  final bool isNew;
  final bool examMode;
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;
  final VoidCallback? onSkip;
  final bool canGiveUp;

  @override
  State<PhaseTaskView> createState() => _PhaseTaskViewState();
}

class _PhaseTaskViewState extends State<PhaseTaskView> {
  late final PhaseCalculator _calc = PhaseCalculator(widget.task);
  late final List<_PartState> _parts = [for (final _ in widget.task.parts) _PartState()];
  final Map<int, SketchTask> _coolingSketches = {};
  int _current = 0;
  bool _gaveUp = false;
  bool _submitted = false;

  PhasePart get _part => widget.task.parts[_current];
  _PartState get _state => _parts[_current];
  bool get _allDone => _gaveUp || _parts.every((p) => p.solved || p.revealed);

  SketchTask _sketchFor(int i) =>
      _coolingSketches.putIfAbsent(i, () => _calc.coolingSketch(widget.task.parts[i].compositions));

  @override
  void dispose() {
    for (final p in _parts) {
      p.dispose();
    }
    super.dispose();
  }

  void _submit({Grade? selfGrade, bool? isCorrect}) {
    if (_submitted) return;
    _submitted = true;
    widget.onComplete(selfGrade: selfGrade, isCorrect: isCorrect);
  }

  void _finish() {
    if (_gaveUp || _parts.any((p) => p.revealed)) return _submit(isCorrect: false);
    final clean = _parts.every((p) => p.wrong == 0 && p.hintsShown == 0);
    if (clean) return _submit(isCorrect: true);
    _submit(isCorrect: true, selfGrade: Grade.hard);
  }

  void _changed() {
    if (_state.verdict != null) setState(() => _state.verdict = null);
  }

  PhaseCheck _judge(int i) {
    final p = widget.task.parts[i], s = _parts[i];
    switch (p.kind) {
      case PhasePartKind.phases:
        return _calc.checkPhases(p, s.phases);
      case PhasePartKind.lever:
        return _calc.checkLever(p, c1: s.number('c1'), c2: s.number('c2'), f1: s.number('f1'), f2: s.number('f2'));
      case PhasePartKind.structure:
        return _calc.checkStructure(p, primary: s.number('primary'), eutectic: s.number('eutectic'));
      case PhasePartKind.composition:
        return _calc.checkComposition(p, [s.number('x1'), s.number('x2')]);
      case PhasePartKind.solubility:
        return _calc.checkSolubility(p, value: s.number('value'), t: s.number('t'));
      case PhasePartKind.eutecticLine:
        return _calc.checkEutecticLine(from: s.number('from'), to: s.number('to'));
      case PhasePartKind.regions:
        return _calc.checkRegions(s.regions);
      case PhasePartKind.pickRegion:
        return _calc.checkPick(p, s.tapped);
      case PhasePartKind.cooling:
        final sketch = _sketchFor(i);
        final v = SketchChecker.check(
          sketch,
          s.cooling[sketch.curves.first.name] ?? const [],
          const [],
          byCurve: s.cooling,
        );
        return PhaseCheck(v.ok, [
          v.summary,
          for (final r in v.results)
            if (!r.ok) r.message,
        ]);
    }
  }

  void _check() {
    if (widget.examMode) {
      _submit(isCorrect: [for (var i = 0; i < _parts.length; i++) _judge(i).ok].every((b) => b));
      return;
    }
    final v = _judge(_current);
    setState(() {
      _state.verdict = v;
      if (v.ok) {
        _state.solved = true;
      } else {
        _state.wrong++;
      }
    });
  }

  /// Antippen im Diagramm: Hebel (erst links, dann rechts) bzw. Gebiet zeigen.
  void _tap(PhasePoint p) {
    final s = _state;
    if (s.solved || s.revealed || _gaveUp) return;
    setState(() {
      s.verdict = null;
      if (_part.kind == PhasePartKind.lever) {
        final first = s.field('c1'), second = s.field('c2');
        final value = PhaseCalculator.fmt(p.c);
        if (first.text.trim().isEmpty || second.text.trim().isNotEmpty) {
          first.text = value;
          second.clear();
        } else {
          final a = double.tryParse(first.text.replaceAll(',', '.'));
          // Links und rechts sortieren.
          if (a != null && p.c < a) {
            second.text = first.text;
            first.text = value;
          } else {
            second.text = value;
          }
        }
      } else if (_part.kind == PhasePartKind.pickRegion) {
        s.tapped = p;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Anzeige
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = widget.card;
    final part = _part, s = _state;
    final hints = _calc.hints(part);
    final finishedPart = s.solved || s.revealed || _gaveUp;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final nextIndex = [
      for (var i = 0; i < _parts.length; i++)
        if (i != _current && !_parts[i].solved && !_parts[i].revealed) i,
    ].firstOrNull;
    final tappable = !finishedPart && (part.kind == PhasePartKind.lever || part.kind == PhasePartKind.pickRegion);

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
                      QuestionType.phase.label,
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
        PhaseDiagramCanvas(
          key: const ValueKey('phase-diagram'),
          calc: _calc,
          height: wide ? 420 : 300,
          showRegionNames: !{PhasePartKind.phases, PhasePartKind.regions, PhasePartKind.pickRegion}.contains(part.kind),
          numbered: part.kind == PhasePartKind.regions,
          markers: [
            if (part.c != null && part.t != null) PhaseMarker(PhasePoint(part.c!, part.t!), c.danger),
            if (s.tapped != null) PhaseMarker(s.tapped!, c.accent, label: '?'),
          ],
          ties: [
            if (part.kind == PhasePartKind.lever && part.t != null)
              PhaseTie(part.t!, s.number('c1'), s.number('c2'), c.accent),
            if (part.kind == PhasePartKind.lever && finishedPart)
              if (_calc.lever(part.c!, part.t!) case final l?) PhaseTie(part.t!, l.c1, l.c2, c.good),
          ],
          onTap: tappable ? _tap : null,
        ),
        const SizedBox(height: 12),
        if (widget.task.parts.length > 1) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, p) in widget.task.parts.indexed)
                ChoiceChip(
                  key: ValueKey('phase-part-$i'),
                  selected: i == _current,
                  showCheckmark: false,
                  avatar: _parts[i].solved && !widget.examMode
                      ? Icon(Icons.check_circle, size: 16, color: c.good)
                      : (_parts[i].revealed ? Icon(Icons.visibility_outlined, size: 16, color: c.warn) : null),
                  label: Text('${String.fromCharCode(97 + i)}  ${p.kind.label}'),
                  onSelected: (_) => setState(() => _current = i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Container(
          key: const ValueKey('phase-prompt'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
          child: Text(
            '${_calc.promptText(part)}${tappable ? '\n${part.kind == PhasePartKind.lever ? 'Tippe im Diagramm die beiden Enden des Hebels an (oder trag die Werte ein).' : 'Tippe die Stelle im Diagramm an.'}' : ''}',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),
        ..._inputs(c, part, s, finishedPart),
        if (s.revealed || (_gaveUp && !s.solved)) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('phase-solution'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(14)),
            child: Text(
              '${_gaveUp ? 'Aufgelöst – zählt als nicht gewusst.' : 'Lösung angesehen – zählt als „Nochmal“.'}\n${_calc.solutionText(part)}',
              style: const TextStyle(fontSize: 13.5, height: 1.45),
            ),
          ),
        ],
        if (s.verdict != null && !widget.examMode) ...[const SizedBox(height: 10), _verdictBox(c, s.verdict!)],
        if (!widget.examMode)
          for (var h = 0; h < s.hintsShown && h < hints.length; h++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                key: ValueKey('phase-hint-$h'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 18, color: c.warn),
                    const SizedBox(width: 8),
                    Expanded(child: Text(hints[h], style: const TextStyle(fontSize: 13.5, height: 1.4))),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 12),
        ..._buttons(c, hints.length, finishedPart, nextIndex),
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

  Widget _number(_PartState s, String key, String label, bool locked, {String suffix = ''}) => SizedBox(
    width: 150,
    child: TextField(
      key: ValueKey('phase-$_current-$key'),
      controller: s.field(key),
      enabled: !locked,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _changed(),
    ),
  );

  List<Widget> _inputs(AppColors c, PhasePart part, _PartState s, bool locked) {
    final sys = _calc.s;
    final pct = '% ${sys.b}';
    switch (part.kind) {
      case PhasePartKind.phases:
        return [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, name) in sys.allPhases.indexed)
                FilterChip(
                  key: ValueKey('phase-choice-$i'),
                  label: Text(name),
                  selected: s.phases.contains(name),
                  onSelected: locked
                      ? null
                      : (on) => setState(() {
                          on ? s.phases.add(name) : s.phases.remove(name);
                          s.verdict = null;
                        }),
                ),
            ],
          ),
        ];
      case PhasePartKind.lever:
        final l = _calc.lever(part.c!, part.t!);
        final left = l?.phase1 ?? 'Phase 1', right = l?.phase2 ?? 'Phase 2';
        return [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _number(s, 'c1', 'c($left)', locked, suffix: pct),
              _number(s, 'c2', 'c($right)', locked, suffix: pct),
              _number(s, 'f1', 'Anteil $left', locked, suffix: '%'),
              _number(s, 'f2', 'Anteil $right', locked, suffix: '%'),
            ],
          ),
        ];
      case PhasePartKind.structure:
        final st = _calc.structure(part.c!);
        final primary = st.primary.isEmpty ? (part.c! < sys.eutecticC ? sys.alpha : sys.beta) : st.primary;
        return [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _number(s, 'primary', 'primär $primary', locked, suffix: '%'),
              _number(s, 'eutectic', sys.eutecticName, locked, suffix: '%'),
            ],
          ),
        ];
      case PhasePartKind.composition:
        return [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _number(s, 'x1', '1. Legierung', locked, suffix: pct),
              _number(s, 'x2', '2. Legierung', locked, suffix: pct),
            ],
          ),
          const SizedBox(height: 4),
          Text('Gibt es nur eine, lass das zweite Feld leer.', style: TextStyle(fontSize: 12, color: c.inkMuted)),
        ];
      case PhasePartKind.solubility:
        return [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _number(s, 'value', 'maximal', locked, suffix: '%'),
              _number(s, 't', 'bei', locked, suffix: '°C'),
            ],
          ),
        ];
      case PhasePartKind.eutecticLine:
        return [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _number(s, 'from', 'von', locked, suffix: pct),
              _number(s, 'to', 'bis', locked, suffix: pct),
            ],
          ),
        ];
      case PhasePartKind.regions:
        final names = [for (final r in PhaseRegion.values) r];
        return [
          for (final (i, _) in _calc.regionLabels().indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: c.accent,
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButton<PhaseRegion>(
                      key: ValueKey('phase-region-$i'),
                      isExpanded: true,
                      value: s.regions[i],
                      hint: const Text('Gebiet wählen'),
                      items: [for (final r in names) DropdownMenuItem(value: r, child: Text(sys.regionName(r)))],
                      onChanged: locked
                          ? null
                          : (r) => setState(() {
                              s.regions[i] = r;
                              s.verdict = null;
                            }),
                    ),
                  ),
                ],
              ),
            ),
        ];
      case PhasePartKind.pickRegion:
        return [
          if (s.tapped != null)
            Text(
              'Angetippt: ${PhaseCalculator.fmt(s.tapped!.c)} $pct, ${PhaseCalculator.fmt(s.tapped!.t, digits: 0)} °C',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            ),
        ];
      case PhasePartKind.cooling:
        final sketch = _sketchFor(_current);
        for (final curve in sketch.curves) {
          s.cooling.putIfAbsent(curve.name, () => []);
        }
        s.coolingCurrent ??= sketch.curves.first.name;
        final strokes = s.cooling[s.coolingCurrent]!;
        return [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, curve) in sketch.curves.indexed)
                ChoiceChip(
                  key: ValueKey('phase-curve-$i'),
                  avatar: CircleAvatar(radius: 6, backgroundColor: SketchCanvas.colorOf(sketch, curve.name, c.accent)),
                  label: Text(curve.name),
                  selected: s.coolingCurrent == curve.name,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => s.coolingCurrent = curve.name),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SketchCanvas(
            key: const ValueKey('phase-cooling-canvas'),
            task: sketch,
            height: 300,
            strokesByCurve: s.cooling,
            showReference: s.revealed || s.solved || _gaveUp,
            onStrokeStart: locked
                ? null
                : (p) => setState(() {
                    strokes.add([p]);
                    s.verdict = null;
                  }),
            onStrokeUpdate: locked
                ? null
                : (p) => setState(() {
                    if (strokes.isNotEmpty) strokes.last.add(p);
                  }),
            onStrokeEnd: () {},
          ),
          if (!locked)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('phase-cooling-undo'),
                onPressed: strokes.isEmpty
                    ? null
                    : () => setState(() {
                        strokes.removeLast();
                        s.verdict = null;
                      }),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Rückgängig'),
              ),
            ),
        ];
    }
  }

  Widget _verdictBox(AppColors c, PhaseCheck v) => Container(
    key: const ValueKey('phase-verdict'),
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: v.ok ? c.goodSoft : c.dangerSoft, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in v.messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(m, style: TextStyle(fontSize: 13.5, height: 1.4, color: v.ok ? c.good : c.danger)),
          ),
      ],
    ),
  );

  List<Widget> _buttons(AppColors c, int hintCount, bool finishedPart, int? nextIndex) {
    final s = _state;
    if (widget.examMode) {
      return [
        if (_parts.length > 1)
          OutlinedButton(
            key: const ValueKey('phase-next-part'),
            onPressed: () => setState(() => _current = (_current + 1) % _parts.length),
            child: const Text('Nächste Teilaufgabe'),
          ),
        const SizedBox(height: 8),
        FilledButton(key: const ValueKey('phase-submit'), onPressed: _check, child: const Text('Antwort abgeben')),
      ];
    }
    if (_allDone) {
      final anyRevealed = _gaveUp || _parts.any((p) => p.revealed);
      final clean = !anyRevealed && _parts.every((p) => p.wrong == 0 && p.hintsShown == 0);
      return [
        Container(
          key: const ValueKey('phase-finished'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: clean ? c.goodSoft : (anyRevealed ? c.warnSoft : c.accentSoft),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _gaveUp
                ? 'Aufgelöst – zählt als nicht gewusst'
                : anyRevealed
                ? 'Mit angesehener Lösung – zählt als „Nochmal“'
                : (clean ? 'Alles gelöst – ohne Hilfe' : 'Alles gelöst – mit Hilfe, zählt als „Schwer“'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(key: const ValueKey('phase-next'), onPressed: _finish, child: const Text('Weiter')),
      ];
    }
    if (finishedPart) {
      return [
        FilledButton(
          key: const ValueKey('phase-next-part'),
          onPressed: nextIndex == null ? null : () => setState(() => _current = nextIndex),
          child: Text(
            nextIndex == null
                ? 'Weiter'
                : 'Weiter zu ${String.fromCharCode(97 + nextIndex)}  ${widget.task.parts[nextIndex].kind.label}',
          ),
        ),
      ];
    }
    return [
      Row(
        children: [
          OutlinedButton.icon(
            key: const ValueKey('phase-hint-button'),
            onPressed: s.hintsShown >= hintCount ? null : () => setState(() => s.hintsShown++),
            icon: const Icon(Icons.lightbulb_outline, size: 18),
            label: const Text('Tipp'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(key: const ValueKey('phase-check'), onPressed: _check, child: const Text('Prüfen')),
          ),
        ],
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton(
            key: const ValueKey('phase-reveal'),
            onPressed: () => setState(() => s.revealed = true),
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
              onPressed: () => setState(() {
                _gaveUp = true;
                for (final p in _parts) {
                  if (!p.solved) p.revealed = true;
                }
              }),
              child: const Text('Auflösen'),
            ),
        ],
      ),
    ];
  }
}
