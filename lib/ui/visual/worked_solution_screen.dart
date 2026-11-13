import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/worked_solution.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/worked_solution_repository.dart';
import '../../services/ai_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';
import '../widgets/raw_response_dialog.dart';
import '../widgets/safe_set_state.dart';
import 'calculator_sim.dart';
import 'worked_board.dart';

/// „Vorrechnen“: eine Aufgabe Schritt für Schritt an der Tafel lösen lassen –
/// grob, regulär oder fein. Jede Umformung ist zu sehen (Umformung rechts
/// neben der Gleichung, was dazukommt grün, was wegfällt rot, woran
/// gearbeitet wird blau), Regeln werden benannt; zu jedem Schritt lassen sich
/// Fragen stellen, Herleitungen wünschen oder feinere Schritte holen. Daneben
/// ein simulierter Taschenrechner, den die App bedient.
class WorkedSolutionScreen extends StatefulWidget {
  const WorkedSolutionScreen({
    super.key,
    required this.moduleId,
    this.problem = '',
    this.reference = '',
    this.image,
    this.cardId,
    this.solution,
  });

  final String moduleId;

  /// Vorbelegte Aufgabe (z.B. aus einer Rechenweg-Karte).
  final String problem;

  /// Vorhandene Musterlösung – die KI richtet sich danach.
  final String reference;
  final Uint8List? image;
  final String? cardId;

  /// Schon vorgerechnet – gleich abspielen.
  final WorkedSolution? solution;

  /// Test-Hook statt OpenRouter.
  static AiService? Function(String apiKey, String model)? aiFactory;

  /// Takt bei „Automatisch“.
  static Duration autoDelay = const Duration(milliseconds: 2800);

  @override
  State<WorkedSolutionScreen> createState() => _WorkedSolutionScreenState();
}

class _WorkedSolutionScreenState extends State<WorkedSolutionScreen> with SafeSetState<WorkedSolutionScreen> {
  late final _problem = TextEditingController(text: widget.problem);
  WorkDetail _detail = WorkDetail.normal;
  bool _calculator = true;
  bool _busy = false;
  String? _error;
  String? _raw;
  WorkedSolution? _solution;
  List<WorkedSolution> _saved = const [];

  int _t = 0;
  Timer? _auto;
  bool _showCalc = true;
  final Map<int, List<({bool user, String text})>> _chats = {};

  @override
  void initState() {
    super.initState();
    _solution = widget.solution;
    if (_solution != null) {
      _detail = _solution!.detail;
      _calculator = _solution!.withCalculator;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _auto?.cancel();
    _problem.dispose();
    super.dispose();
  }

  WorkedSolutionRepository? get _repo => context.read<WorkedSolutionRepository?>();

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    if (_solution == null && widget.cardId != null) {
      final existing = await repo.forCard(widget.cardId!);
      if (existing != null) {
        setState(() {
          _solution = existing;
          _detail = existing.detail;
          _calculator = existing.withCalculator;
        });
      }
    }
    if (widget.cardId == null) {
      final saved = await repo.forModule(widget.moduleId);
      setState(() => _saved = saved);
    }
  }

  AiService? _ai({bool vision = false}) {
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings == null || !settings.hasApiKey) return null;
    final model = vision ? settings.visionModelId : settings.questionModelId;
    return WorkedSolutionScreen.aiFactory?.call(settings.openRouterApiKey!, model) ??
        AiService(apiKey: settings.openRouterApiKey!, model: model);
  }

  // ---------------------------------------------------------------------------
  // Vorrechnen lassen
  // ---------------------------------------------------------------------------

  Future<void> _start() async {
    final ai = _ai(vision: widget.image != null);
    if (ai == null) {
      setState(() => _error = 'Zum Vorrechnen braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _raw = null;
    });
    try {
      final json = await ai.solveWorked(
        problem: _problem.text,
        detail: _detail,
        reference: widget.reference,
        calculator: _calculator,
        image: widget.image,
      );
      final solution = WorkedSolution.fromAi(
        json,
        id: const Uuid().v4(),
        moduleId: widget.moduleId,
        problem: _problem.text.trim(),
        detail: _detail,
        now: DateTime.now(),
        cardId: widget.cardId,
        withCalculator: _calculator,
      );
      if (solution.steps.isEmpty) {
        throw AiServiceException('Die KI hat keine lesbaren Schritte geliefert.', rawResponse: '$json');
      }
      await _repo?.save(solution);
      setState(() {
        _solution = solution;
        _t = 0;
        _chats.clear();
      });
    } on AiServiceException catch (e) {
      setState(() {
        _error = e.message;
        _raw = e.rawResponse;
      });
    } catch (e) {
      setState(() => _error = 'Vorrechnen fehlgeschlagen: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Abspielen
  // ---------------------------------------------------------------------------

  WorkPlayback get _playback => WorkPlayback(_solution!.steps);

  void _go(int t) {
    final len = _playback.length;
    setState(() => _t = t.clamp(0, len - 1));
  }

  void _next() {
    if (_t >= _playback.length - 1) {
      _stopAuto();
      return;
    }
    _go(_t + 1);
  }

  void _prev() {
    _stopAuto();
    _go(_t - 1);
  }

  void _toggleAuto() {
    if (_auto != null) {
      _stopAuto();
      return;
    }
    if (_t >= _playback.length - 1) _go(0);
    _auto = Timer.periodic(WorkedSolutionScreen.autoDelay, (_) => _next());
    setState(() {});
  }

  void _stopAuto() {
    _auto?.cancel();
    _auto = null;
    if (mounted) setState(() {});
  }

  bool get _atEnd => _solution != null && _t >= _playback.length - 1;

  // ---------------------------------------------------------------------------
  // Fragen, Herleitung, feiner
  // ---------------------------------------------------------------------------

  List<String> _boardTexts(int step, int phase) => [
    for (final l in _playback.board(step, phase)) WorkMarkup.toTex(l.tex, colored: false),
  ];

  Future<void> _ask(int step, {String? preset}) async {
    _stopAuto();
    final s = _solution!.steps[step];
    final (_, phase) = _playback.at(_t);
    final history = _chats.putIfAbsent(step, () => []);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StepChat(
        title: s.title,
        history: history,
        preset: preset,
        ai: _ai(),
        send: (ai, question) => ai.discussWorkedStep(
          problem: _solution!.problem,
          boardSoFar: _boardTexts(step, phase),
          stepTitle: s.title,
          stepText: [
            s.say,
            if (s.op.isNotEmpty) 'Umformung: | ${s.op}',
            if (s.work.isNotEmpty) 'Markiert: ${s.work}',
            if (s.to.isNotEmpty) 'Ergebnis: ${s.to}',
          ].join('\n'),
          rule: s.rule == null ? '' : '${s.rule!.name}: ${s.rule!.formula}',
          history: List.of(history),
          question: question,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _refine(int step) async {
    _stopAuto();
    final ai = _ai();
    if (ai == null) {
      setState(() => _error = 'Für feinere Schritte braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final solution = _solution!;
    final s = solution.steps[step];
    final before = _playback.board(step, 0).lastOrNull?.tex ?? '';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final raw = await ai.refineWorkedStep(
        problem: solution.problem,
        before: WorkMarkup.toTex(before, colored: false),
        step: s.toMap(),
        calculator: solution.withCalculator,
      );
      final parts = [for (final r in raw) ?WorkStep.fromMap(r)];
      if (parts.isEmpty) throw AiServiceException('Die KI hat den Schritt nicht aufgeteilt.');
      // Die Tafel soll genau dort weitergehen, wo der Schritt aufhörte.
      final fixed = [
        for (final (i, p) in parts.indexed)
          i == parts.length - 1 && s.to.isNotEmpty && p.to.isEmpty
              ? WorkStep(
                  title: p.title,
                  say: p.say,
                  from: p.from,
                  op: p.op,
                  work: p.work,
                  to: s.to,
                  rule: p.rule,
                  calc: p.calc,
                )
              : p,
      ];
      final steps = [...solution.steps]..replaceRange(step, step + 1, fixed);
      final updated = solution.copyWith(steps: steps);
      await _repo?.save(updated);
      setState(() {
        _solution = updated;
        _t = WorkPlayback(steps).startOf(step);
        // Gespräche hängen an Schrittnummern – nach dem Einfügen verschieben.
        final moved = {for (final e in _chats.entries) (e.key > step ? e.key + fixed.length - 1 : e.key): e.value};
        _chats
          ..clear()
          ..addAll(moved);
      });
    } on AiServiceException catch (e) {
      setState(() {
        _error = e.message;
        _raw = e.rawResponse;
      });
    } catch (e) {
      setState(() => _error = 'Feiner aufteilen fehlgeschlagen: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _restart() async {
    _stopAuto();
    setState(() {
      _solution = null;
      _t = 0;
      _chats.clear();
    });
    await _load();
  }

  // ---------------------------------------------------------------------------
  // Anzeige
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final solution = _solution;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(solution == null ? 'Vorrechnen lassen' : solution.displayTitle, overflow: TextOverflow.ellipsis),
        actions: [
          if (solution != null)
            IconButton(
              key: const ValueKey('worked-new'),
              tooltip: 'Neu vorrechnen (anderer Detailgrad)',
              onPressed: _busy ? null : _restart,
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: SafeArea(child: solution == null ? _buildStart(c) : _buildPlayer(c, solution)),
    );
  }

  Widget _buildStart(AppColors c) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            'Die KI rechnet die Aufgabe an der Tafel vor – jede Umformung sichtbar: was auf beiden Seiten passiert '
            '(„| −5x“), was dazukommt (grün), was wegfällt (rot), welche Regel gilt. Du gehst Schritt für Schritt '
            'weiter, fragst nach, lässt dir Regeln herleiten oder einen Schritt feiner zeigen. Daneben bedient die '
            'App einen Taschenrechner, damit du siehst, welche Tasten du drücken würdest.',
            style: TextStyle(color: c.inkMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (widget.image != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(widget.image!, height: 160, fit: BoxFit.contain),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            key: const ValueKey('worked-problem'),
            controller: _problem,
            minLines: 2,
            maxLines: 8,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Aufgabe',
              hintText: 'z.B. Löse ln((48x + 6)²) = 10 nach x auf  oder  Berechne ∫ 2x(x² + 1)³ dx',
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.problem.contains(r'$')) ...[
            const SizedBox(height: 8),
            MathText(widget.problem, style: TextStyle(color: c.inkMuted)),
          ],
          const SizedBox(height: 16),
          Text('Wie genau?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<WorkDetail>(
            key: const ValueKey('worked-detail'),
            segments: [
              for (final d in WorkDetail.values)
                ButtonSegment(
                  value: d,
                  label: Text(d.label, key: ValueKey('worked-detail-${d.name}')),
                ),
            ],
            selected: {_detail},
            showSelectedIcon: false,
            onSelectionChanged: _busy ? null : (s) => setState(() => _detail = s.first),
          ),
          const SizedBox(height: 4),
          Text(_detail.hint, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey('worked-calculator'),
            contentPadding: EdgeInsets.zero,
            value: _calculator,
            onChanged: _busy ? null : (v) => setState(() => _calculator = v),
            title: const Text('Mit Taschenrechner'),
            subtitle: const Text('Die App zeigt Tastenfolgen (Tasten wie fx-991DE X), wo man ihn benutzen würde.'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('worked-start'),
            onPressed: _busy || (_problem.text.trim().isEmpty && widget.image == null) ? null : _start,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_lesson_outlined),
            label: Text(_busy ? 'Die KI rechnet vor …' : 'Vorrechnen'),
          ),
          if (_error != null) _errorBox(c),
          if (_saved.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Schon vorgerechnet', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final (i, s) in _saved.indexed)
              ListTile(
                key: ValueKey('worked-saved-$i'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.functions, color: c.accent),
                title: Text(s.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${s.detail.label} · ${s.steps.length} Schritte'),
                onTap: () => setState(() {
                  _solution = s;
                  _t = 0;
                  _chats.clear();
                }),
                trailing: IconButton(
                  tooltip: 'Löschen',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _repo?.delete(s.id);
                    await _load();
                  },
                ),
              ),
          ],
        ],
      ),
    ),
  );

  Widget _errorBox(AppColors c) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _error!,
          key: const ValueKey('worked-error'),
          style: TextStyle(color: c.danger),
        ),
        if (_raw != null)
          TextButton(onPressed: () => showRawResponseDialog(context, _raw!), child: const Text('KI-Antwort ansehen')),
      ],
    ),
  );

  Widget _buildPlayer(AppColors c, WorkedSolution solution) {
    final playback = _playback;
    final (step, phase) = playback.at(_t);
    final s = solution.steps[step];
    final lines = playback.board(step, phase);
    final calc = solution.withCalculator ? s.calc : null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.space): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _prev,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 980 && solution.withCalculator;
            final main = ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
              children: [
                if (solution.problem.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.border),
                    ),
                    child: MathText(solution.problem, style: const TextStyle(fontSize: 14.5, height: 1.4)),
                  ),
                const SizedBox(height: 10),
                _progress(c, solution, step),
                const SizedBox(height: 10),
                SizedBox(
                  height: wide ? 380 : 260,
                  child: WorkBoard(lines: lines),
                ),
                const SizedBox(height: 10),
                _explanation(c, s, step, phase),
                const SizedBox(height: 8),
                _controls(c, step),
                if (_error != null) _errorBox(c),
                if (_atEnd && solution.answer.isNotEmpty)
                  Container(
                    key: const ValueKey('worked-answer'),
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: c.goodSoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, color: c.good),
                        const SizedBox(width: 10),
                        Text(
                          'Ergebnis: ',
                          style: TextStyle(fontWeight: FontWeight.w700, color: c.good),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Math.tex(
                              WorkMarkup.toTex(solution.answer, colored: false),
                              textStyle: const TextStyle(fontSize: 19),
                              onErrorFallback: (_) => Text(solution.answer),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!wide && solution.withCalculator) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('Taschenrechner', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      TextButton(
                        key: const ValueKey('worked-calc-toggle'),
                        onPressed: () => setState(() => _showCalc = !_showCalc),
                        child: Text(_showCalc ? 'Ausblenden' : 'Zeigen'),
                      ),
                    ],
                  ),
                  if (_showCalc)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: CalculatorSim(key: ValueKey('calc-$step'), calc: calc),
                      ),
                    ),
                ],
              ],
            );
            if (!wide) return main;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: main),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(0, 10, 20, 24),
                    child: CalculatorSim(key: ValueKey('calc-$step'), calc: calc),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _progress(AppColors c, WorkedSolution solution, int step) {
    final len = _playback.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Schritt ${step + 1} von ${solution.steps.length}',
              key: const ValueKey('worked-step-label'),
              style: TextStyle(fontSize: 12.5, color: c.inkMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
              child: Text(solution.detail.label, style: TextStyle(fontSize: 11, color: c.accentOnSoft)),
            ),
            const Spacer(),
            PopupMenuButton<int>(
              key: const ValueKey('worked-jump'),
              tooltip: 'Zu einem Schritt springen',
              icon: const Icon(Icons.format_list_numbered, size: 20),
              onSelected: (i) {
                _stopAuto();
                _go(_playback.startOf(i));
              },
              itemBuilder: (_) => [
                for (final (i, st) in solution.steps.indexed)
                  PopupMenuItem(
                    value: i,
                    child: Text('${i + 1}. ${st.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: len <= 1 ? 1 : _t / (len - 1), minHeight: 5),
        ),
      ],
    );
  }

  Widget _explanation(AppColors c, WorkStep s, int step, int phase) {
    final phaseNote = switch (phase) {
      0 when s.op.isNotEmpty => 'Umformung auf beiden Seiten:',
      1 => 'Grün kommt dazu, rot fällt weg, blau wird umgeformt.',
      2 => 'Neue Zeile.',
      _ => '',
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey('worked-explain-$step'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (s.say.isNotEmpty) ...[
              const SizedBox(height: 6),
              MathText(s.say, style: const TextStyle(fontSize: 14.5, height: 1.45)),
            ],
            if (s.rule != null) ...[
              const SizedBox(height: 10),
              Container(
                key: ValueKey('worked-rule-$step'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.rule!.name,
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.accentOnSoft),
                    ),
                    if (s.rule!.formula.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Math.tex(
                            s.rule!.formula,
                            textStyle: const TextStyle(fontSize: 18),
                            onErrorFallback: (_) => Text(s.rule!.formula),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (phaseNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  Text(
                    phaseNote,
                    style: TextStyle(fontSize: 12.5, color: c.inkMuted, fontStyle: FontStyle.italic),
                  ),
                  if (phase == 0 && s.op.isNotEmpty)
                    Math.tex(
                      '|\\;${s.op}',
                      textStyle: TextStyle(fontSize: 15, color: c.ink),
                      onErrorFallback: (_) => Text('| ${s.op}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _controls(AppColors c, int step) {
    final ai = _ai() != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              key: const ValueKey('worked-prev'),
              onPressed: _t == 0 ? null : _prev,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Zurück'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('worked-next'),
                onPressed: _atEnd
                    ? null
                    : () {
                        _stopAuto();
                        _next();
                      },
                icon: const Icon(Icons.chevron_right),
                label: Text(_atEnd ? 'Fertig' : 'Weiter'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('worked-auto'),
              tooltip: _auto == null ? 'Automatisch abspielen' : 'Anhalten',
              onPressed: _toggleAuto,
              icon: Icon(_auto == null ? Icons.play_arrow : Icons.pause),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ActionChip(
              key: const ValueKey('worked-ask'),
              avatar: const Icon(Icons.forum_outlined, size: 18),
              label: Text(_chats[step]?.isNotEmpty ?? false ? 'Frage (${_chats[step]!.length ~/ 2})' : 'Frage stellen'),
              onPressed: ai ? () => _ask(step) : null,
            ),
            ActionChip(
              key: const ValueKey('worked-derive'),
              avatar: const Icon(Icons.account_tree_outlined, size: 18),
              label: const Text('Herleitung'),
              onPressed: ai
                  ? () => _ask(
                      step,
                      preset: _solution!.steps[step].rule != null
                          ? 'Leite die Regel „${_solution!.steps[step].rule!.name}“ her – warum gilt sie?'
                          : 'Leite diesen Schritt ausführlich her – warum darf man das so machen?',
                    )
                  : null,
            ),
            ActionChip(
              key: const ValueKey('worked-refine'),
              avatar: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.zoom_in, size: 18),
              label: const Text('Diesen Schritt genauer'),
              onPressed: ai && !_busy ? () => _refine(step) : null,
            ),
          ],
        ),
        if (!ai)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Fragen, Herleitungen und feinere Schritte gehen mit deinem OpenRouter-Key (Einstellungen).',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
          ),
      ],
    );
  }
}

/// Gespräch zu einem Schritt: eigene Frage oder Vorschlag („Warum?“,
/// „Herleitung“, „Zahlenbeispiel“). [history] wird fortgeschrieben.
class _StepChat extends StatefulWidget {
  const _StepChat({required this.title, required this.history, required this.ai, required this.send, this.preset});

  final String title;
  final List<({bool user, String text})> history;
  final AiService? ai;
  final Future<String> Function(AiService ai, String question) send;
  final String? preset;

  @override
  State<_StepChat> createState() => _StepChatState();
}

class _StepChatState extends State<_StepChat> with SafeSetState<_StepChat> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    if (preset != null) WidgetsBinding.instance.addPostFrameCallback((_) => _send(preset));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send(String question) async {
    final ai = widget.ai;
    if (question.trim().isEmpty || _busy) return;
    if (ai == null) {
      setState(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _input.clear();
    });
    try {
      final answer = await widget.send(ai, question);
      widget.history
        ..add((user: true, text: question.trim()))
        ..add((user: false, text: answer));
    } on AiServiceException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Fehlgeschlagen: $e';
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final suggestions = [
      'Warum macht man das hier?',
      'Zeig mir ein einfaches Zahlenbeispiel dazu.',
      'Wie hätte ich selbst darauf kommen können?',
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Zu: ${widget.title}', style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final (i, m) in widget.history.indexed)
                    Align(
                      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        key: ValueKey('worked-chat-msg-$i'),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(maxWidth: 620),
                        decoration: BoxDecoration(
                          color: m.user ? c.accentSoft : c.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: m.user ? null : Border.all(color: c.border),
                        ),
                        child: MathText(m.text, style: const TextStyle(fontSize: 14.5, height: 1.45)),
                      ),
                    ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      key: const ValueKey('worked-chat-error'),
                      style: TextStyle(color: c.danger),
                    ),
                  if (widget.history.isEmpty && !_busy)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (i, q) in suggestions.indexed)
                          ActionChip(
                            key: ValueKey('worked-chat-suggest-$i'),
                            label: Text(q),
                            onPressed: () => _send(q),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('worked-chat-input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: const InputDecoration(
                        hintText: 'Deine Frage zu diesem Schritt …',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey('worked-chat-send'),
                    onPressed: _busy ? null : () => _send(_input.text),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
