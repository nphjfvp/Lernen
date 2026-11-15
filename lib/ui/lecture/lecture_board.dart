import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/lecture_walk.dart';
import '../../models/worked_solution.dart';
import '../../theme/app_colors.dart';
import '../visual/worked_board.dart';
import '../widgets/math_text.dart';

/// Was die Tafel bei „Vorlesung mit Aufgabe“ zeigt – serialisierbar, damit
/// sie auch im eigenen Fenster (PC, zweiter Bildschirm) gleich aussieht.
class LectureBoardState {
  const LectureBoardState({
    this.topicTitle = '',
    this.topicNumber = 0,
    this.topicCount = 0,
    this.pageLabel = '',
    this.problem = '',
    this.steps = const [],
    this.revealed = 0,
    this.current,
    this.formulas = const [],
    this.freshFormulas = 0,
    this.coach = '',
    this.chat = const [],
    this.busy = false,
    this.busyText = '',
    this.error,
  });

  final String topicTitle;
  final int topicNumber;
  final int topicCount;
  final String pageLabel;
  final String problem;
  final List<WorkStep> steps;

  /// So viele Schritte stehen an der Tafel.
  final int revealed;

  /// Hervorgehobener Schritt (z.B. dort, wo es beim Selbstlösen hakte).
  final int? current;
  final List<LectureFormula> formulas;

  /// Die letzten so vielen Formeln sind gerade neu dazugekommen.
  final int freshFormulas;

  /// Was die KI gerade sagt („Okay, lass uns mit unserer Aufgabe weitermachen …“).
  final String coach;
  final List<({bool user, String text})> chat;
  final bool busy;
  final String busyText;
  final String? error;

  Map<String, dynamic> toMap() => {
    'topicTitle': topicTitle,
    'topicNumber': topicNumber,
    'topicCount': topicCount,
    'pageLabel': pageLabel,
    'problem': problem,
    'steps': [for (final s in steps) s.toMap()],
    'revealed': revealed,
    'current': current,
    'formulas': [for (final f in formulas) f.toMap()],
    'freshFormulas': freshFormulas,
    'coach': coach,
    'chat': [
      for (final m in chat) {'user': m.user, 'text': m.text},
    ],
    'busy': busy,
    'busyText': busyText,
    'error': error,
  };

  static LectureBoardState fromMap(Object? raw) {
    if (raw is! Map) return const LectureBoardState();
    int number(Object? v) => v is num ? v.toInt() : 0;
    final steps = raw['steps'];
    final formulas = raw['formulas'];
    final chat = raw['chat'];
    final current = raw['current'];
    return LectureBoardState(
      topicTitle: '${raw['topicTitle'] ?? ''}',
      topicNumber: number(raw['topicNumber']),
      topicCount: number(raw['topicCount']),
      pageLabel: '${raw['pageLabel'] ?? ''}',
      problem: '${raw['problem'] ?? ''}',
      steps: [for (final s in steps is List ? steps : const []) ?WorkStep.fromMap(s)],
      revealed: number(raw['revealed']),
      current: current is num ? current.toInt() : null,
      formulas: [for (final f in formulas is List ? formulas : const []) ?LectureFormula.fromMap(f)],
      freshFormulas: number(raw['freshFormulas']),
      coach: '${raw['coach'] ?? ''}',
      chat: [
        for (final m in chat is List ? chat : const [])
          if (m is Map) (user: m['user'] == true, text: '${m['text'] ?? ''}'),
      ],
      busy: raw['busy'] == true,
      busyText: '${raw['busyText'] ?? ''}',
      error: raw['error'] == null ? null : '${raw['error']}',
    );
  }
}

/// Die Tafel: Aufgabe, was die KI sagt, die Rechnung (neue Schritte
/// erscheinen nacheinander), neue Formeln und die Formelsammlung, Fragen.
class LectureBoardView extends StatefulWidget {
  const LectureBoardView({super.key, required this.state, required this.onAsk, this.onDetach, this.actions = const []});

  final LectureBoardState state;

  /// Frage stellen – [formula] = Index in der Formelsammlung.
  final void Function(String question, {int? formula}) onAsk;

  /// Tafel in eigenem Fenster (nur am PC).
  final VoidCallback? onDetach;

  /// Weitere Knöpfe unter der Tafel (z.B. Vorrechnen, Visuell erklären).
  final List<Widget> actions;

  /// So lange steht jede Phase, wenn neue Schritte dazukommen.
  static Duration phaseDelay = const Duration(milliseconds: 900);

  @override
  State<LectureBoardView> createState() => _LectureBoardViewState();
}

class _LectureBoardViewState extends State<LectureBoardView> {
  final _question = TextEditingController();
  Timer? _timer;

  /// Gerade gezeigter Takt der Tafel (siehe WorkPlayback).
  int _tick = -1;

  @override
  void initState() {
    super.initState();
    _tick = _target(widget.state);
  }

  @override
  void didUpdateWidget(LectureBoardView old) {
    super.didUpdateWidget(old);
    final target = _target(widget.state);
    final sameTask = old.state.problem == widget.state.problem && old.state.steps.length == widget.state.steps.length;
    if (!sameTask || target < _tick || widget.state.current != null) {
      _timer?.cancel();
      _tick = target;
    } else if (target > _tick) {
      // Neue Schritte: Takt für Takt anschreiben.
      _timer?.cancel();
      _timer = Timer.periodic(LectureBoardView.phaseDelay, (t) {
        if (!mounted) return t.cancel();
        setState(() => _tick++);
        if (_tick >= _target(widget.state)) t.cancel();
      });
      _tick++;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _question.dispose();
    super.dispose();
  }

  /// Letzter Takt der aufgedeckten Schritte (-1 = noch nichts an der Tafel).
  static int _target(LectureBoardState s) {
    final shown = (s.current != null ? s.current! + 1 : s.revealed).clamp(0, s.steps.length);
    if (shown == 0) return -1;
    final playback = WorkPlayback(s.steps);
    return playback.startOf(shown - 1) + playback.phasesOf(shown - 1).length - 1;
  }

  void _ask() {
    final q = _question.text.trim();
    if (q.isEmpty) return;
    _question.clear();
    widget.onAsk(q);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.state;
    final playback = WorkPlayback(s.steps);
    final (step, phase) = _tick >= 0 && s.steps.isNotEmpty ? playback.at(_tick) : (-1, 0);
    final fresh = s.freshFormulas.clamp(0, s.formulas.length);
    return ListView(
      key: const ValueKey('lecture-board'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.topicTitle.isEmpty ? 'Unsere Aufgabe' : 'Thema ${s.topicNumber}/${s.topicCount} · ${s.topicTitle}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (s.pageLabel.isNotEmpty) Text(s.pageLabel, style: TextStyle(color: c.inkMuted, fontSize: 12)),
            if (widget.onDetach != null)
              IconButton(
                key: const ValueKey('lecture-detach'),
                tooltip: 'Tafel in eigenem Fenster (auf den zweiten Bildschirm ziehen)',
                onPressed: widget.onDetach,
                icon: const Icon(Icons.open_in_new),
              ),
          ],
        ),
        if (s.problem.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: MathText(s.problem, style: const TextStyle(height: 1.45)),
          ),
        ],
        if (s.coach.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            key: const ValueKey('lecture-coach'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.record_voice_over_outlined, size: 20, color: c.accent),
              const SizedBox(width: 8),
              Expanded(child: MathText(s.coach, style: const TextStyle(height: 1.45))),
            ],
          ),
        ],
        if (s.busy) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(child: Text(s.busyText.isEmpty ? 'Einen Moment …' : s.busyText)),
            ],
          ),
        ],
        if (s.error != null) ...[const SizedBox(height: 10), Text(s.error!, style: TextStyle(color: c.danger))],
        const SizedBox(height: 12),
        if (fresh > 0)
          Container(
            key: const ValueKey('lecture-new-formulas'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: c.good, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fresh == 1 ? 'Neue Formel' : 'Neue Formeln',
                  style: TextStyle(color: c.good, fontWeight: FontWeight.w700),
                ),
                for (final f in s.formulas.sublist(s.formulas.length - fresh)) _FormulaLine(formula: f),
              ],
            ),
          ),
        if (step < 0)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
            child: Text(
              s.problem.isEmpty ? 'Noch keine Aufgabe.' : 'Noch nichts an der Tafel – lies die nächste Seite.',
              style: TextStyle(color: c.inkMuted),
            ),
          )
        else
          WorkBoard(blocks: playback.blocks(step, phase)),
        if (widget.actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: widget.actions),
        ],
        const SizedBox(height: 14),
        ExpansionTile(
          // Neu aufgebaut, sobald die erste Formel kommt – dann aufgeklappt.
          key: ValueKey('lecture-formulas-${s.formulas.isEmpty}'),
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: s.formulas.isNotEmpty,
          title: Text('Formelsammlung (${s.formulas.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          children: [
            if (s.formulas.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Neue Formeln kommen hierher, sobald sie drankommen.', style: TextStyle(color: c.inkMuted)),
              ),
            for (final (i, f) in s.formulas.indexed)
              _FormulaLine(
                formula: f,
                onAsk: () => widget.onAsk(
                  'Erkläre mir die Formel „${f.name.isEmpty ? f.latex : f.name}“: wofür brauche ich sie, woher kommt '
                  'sie und wie benutze ich sie in unserer Aufgabe?',
                  formula: i,
                ),
                index: i,
              ),
          ],
        ),
        if (s.chat.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final m in s.chat)
            Align(
              alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(10),
                constraints: const BoxConstraints(maxWidth: 560),
                decoration: BoxDecoration(
                  color: m.user ? c.accentSoft : c.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: MathText(m.text, style: const TextStyle(height: 1.4)),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('lecture-question'),
                controller: _question,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _ask(),
                decoration: const InputDecoration(
                  hintText: 'Frage zur Aufgabe, zur Seite oder zu einer Formel …',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('lecture-ask'),
              tooltip: 'Fragen',
              onPressed: s.busy ? null : _ask,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
  }
}

class _FormulaLine extends StatelessWidget {
  const _FormulaLine({required this.formula, this.onAsk, this.index});

  final LectureFormula formula;
  final VoidCallback? onAsk;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (formula.name.isNotEmpty)
                  Text(
                    formula.page > 0 ? '${formula.name} · S. ${formula.page}' : formula.name,
                    style: TextStyle(fontSize: 12, color: c.inkMuted),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Math.tex(
                    formula.latex,
                    textStyle: const TextStyle(fontSize: 18),
                    onErrorFallback: (_) => Text(formula.latex),
                  ),
                ),
                if (formula.note.isNotEmpty)
                  Text(formula.note, style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.35)),
              ],
            ),
          ),
          if (onAsk != null)
            IconButton(
              key: ValueKey('lecture-formula-ask-$index'),
              tooltip: 'Frage zu dieser Formel',
              onPressed: onAsk,
              icon: const Icon(Icons.help_outline, size: 20),
            ),
        ],
      ),
    );
  }
}
