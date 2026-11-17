import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../models/learn_credit.dart';
import '../../models/unlock_block.dart';
import '../../repositories/unlock_block_repository.dart';
import '../../services/ai_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/screen_guard.dart';
import '../../services/unlock_block_service.dart';
import '../../services/unlock_task_card.dart';
import '../../theme/app_colors.dart';
import '../visual/task_help.dart';
import '../visual/worked_solution_screen.dart';
import '../widgets/math_text.dart';
import '../widgets/safe_set_state.dart';

/// Öffnet die Entsperr-Blöcke.
Future<void> openUnlockBlocks(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const UnlockBlocksScreen()));

/// Entsperr-Blöcke: je Block zwei Aufgaben zu einem Thema, das du noch nicht
/// sicher kannst – ohne Hilfe gelöst gibt es Handyzeit.
class UnlockBlocksScreen extends StatefulWidget {
  const UnlockBlocksScreen({super.key, this.repository});

  final UnlockBlockRepository? repository;

  @override
  State<UnlockBlocksScreen> createState() => _UnlockBlocksScreenState();
}

class _UnlockBlocksScreenState extends State<UnlockBlocksScreen> with SafeSetState<UnlockBlocksScreen> {
  late final _repo = widget.repository ?? UnlockBlockRepository();
  List<UnlockBlock>? _blocks;
  Map<String, String> _modules = const {};
  LearnCreditRules _rules = const LearnCreditRules();
  bool _preparing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    UnlockBlockRepository.changes.addListener(_load);
    unawaited(_start());
  }

  @override
  void dispose() {
    UnlockBlockRepository.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _start() async {
    await _load();
    if ((_blocks ?? const []).every((b) => b.solved)) await _prepare();
  }

  Future<void> _load() async {
    final blocks = await _repo.all();
    final rules = await UnlockBlockService.instance.rules().catchError((_) => const LearnCreditRules());
    final modules = await UnlockBlockService.instance.moduleNames().catchError((_) => const <String, String>{});
    setState(() {
      _blocks = blocks;
      _modules = modules;
      _rules = rules;
    });
  }

  Future<void> _prepare() async {
    if (UnlockBlockService.aiFactory?.call() == null) {
      setState(() => _error = 'Für Entsperr-Blöcke braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      await UnlockBlockService.instance.refreshAll(force: true);
    } catch (e) {
      _error = e is AiServiceException ? e.message : '$e';
    } finally {
      setState(() => _preparing = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocks = _blocks;
    final open = [
      for (final b in blocks ?? const <UnlockBlock>[])
        if (!b.solved) b,
    ];
    final done = [
      for (final b in blocks ?? const <UnlockBlock>[])
        if (b.solved) b,
    ];
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Entsperr-Blöcke'),
        actions: [
          IconButton(
            key: const ValueKey('unlock-refresh'),
            tooltip: 'Neu anpassen (nach deinen Fehlern und dem neuen Stoff)',
            onPressed: _preparing ? null : _prepare,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: blocks == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  'Je Block zwei Aufgaben zu einem Thema, das du noch nicht sicher kannst – aus deinen Vorlesungen, '
                  'Übungsaufgaben und Fehlern beim Üben. Beide ohne Hilfe gelöst: +${_rules.blockMinutes} min '
                  'Handyzeit. Klappt es nicht, gibt es eine Übungseinheit (+${_rules.practiceMinutes} min) und danach '
                  'eine neue Aufgabe – gelöst sind es die vollen ${_rules.blockMinutes} min.',
                  style: TextStyle(color: c.inkMuted, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (_preparing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Die KI stellt Blöcke aus deinen Vorlesungen, Übungen und Fehlern zusammen …'),
                        ),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: c.danger)),
                  ),
                if (open.isEmpty && !_preparing)
                  Text(
                    'Gerade keine offenen Blöcke. Sie entstehen, sobald du Vorlesungen oder Übungsblätter hochlädst, '
                    'und passen sich nach dem Üben an.',
                    style: TextStyle(color: c.inkMuted),
                  ),
                for (final b in open) _BlockCard(block: b, module: _modules[b.moduleId] ?? '', rules: _rules),
                if (done.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Erledigt (${done.length})'),
                    children: [
                      for (final b in done.reversed)
                        _BlockCard(block: b, module: _modules[b.moduleId] ?? '', rules: _rules),
                    ],
                  ),
              ],
            ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block, required this.module, required this.rules});

  final UnlockBlock block;
  final String module;
  final LearnCreditRules rules;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reward = block.solved
        ? 'erledigt'
        : block.rewardedPractice
        ? 'noch +${rules.blockMinutes - rules.practiceMinutes} min'
        : '+${rules.blockMinutes} min';
    return Card(
      key: ValueKey('unlock-block-${block.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UnlockBlockScreen(block: block))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                block.solved ? Icons.lock_open_rounded : Icons.lock_clock_outlined,
                color: block.solved ? c.good : c.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (module.isNotEmpty) Text(module, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                    Text(block.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (block.reason.isNotEmpty)
                      Text(block.reason, style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.35)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        for (final t in block.tasks)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              switch (t.state) {
                                UnlockTaskState.solved => Icons.check_circle,
                                UnlockTaskState.failed => Icons.error_outline,
                                UnlockTaskState.open => Icons.radio_button_unchecked,
                              },
                              size: 18,
                              color: switch (t.state) {
                                UnlockTaskState.solved => c.good,
                                UnlockTaskState.failed => c.warn,
                                UnlockTaskState.open => c.inkMuted,
                              },
                            ),
                          ),
                        if (block.practice != null && !block.practice!.completed)
                          Text(' · Übungseinheit offen', style: TextStyle(fontSize: 12, color: c.warn)),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                reward,
                style: TextStyle(fontWeight: FontWeight.w700, color: block.solved ? c.good : c.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein Entsperr-Block: Aufgaben lösen (ohne Hilfe), bei einem Fehlversuch die
/// Übungseinheit und danach eine neue Aufgabe gleicher Art.
class UnlockBlockScreen extends StatefulWidget {
  const UnlockBlockScreen({super.key, required this.block, this.repository});

  final UnlockBlock block;
  final UnlockBlockRepository? repository;

  /// Test-Hook: Übungsaufgabe „durchgearbeitet“ statt Vorrechnen zu öffnen.
  static Future<bool> Function(BuildContext context, String moduleId, String problem)? practiceHook;

  /// Test-Hook: statt die Aufgabe zu lösen, gleich ein Ergebnis.
  static Future<({Grade? selfGrade, bool? isCorrect})?> Function(BuildContext context, Flashcard card)? solveHook;

  @override
  State<UnlockBlockScreen> createState() => _UnlockBlockScreenState();
}

class _UnlockBlockScreenState extends State<UnlockBlockScreen> with SafeSetState<UnlockBlockScreen> {
  late final _repo = widget.repository ?? UnlockBlockRepository();
  late UnlockBlock _block = widget.block;
  final _answers = <int, TextEditingController>{};
  final _showSolution = <int>{};

  /// Aufgaben, zu denen keine Karte gebaut werden konnte – dann das Textfeld.
  final _plainAnswer = <int>{};
  int? _busy;
  bool _practiceBusy = false;
  String? _error;
  LearnCreditRules _rules = const LearnCreditRules();

  @override
  void initState() {
    super.initState();
    unawaited(UnlockBlockService.instance.rules().then((r) => setState(() => _rules = r)).catchError((_) {}));
  }

  @override
  void dispose() {
    for (final c in _answers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _answer(int i) => _answers.putIfAbsent(i, TextEditingController.new);

  AiService? get _ai => UnlockBlockService.aiFactory?.call();

  Future<void> _save(UnlockBlock block) async {
    setState(() => _block = block);
    await _repo.save(block);
    final reward = await _repo.reward(block);
    setState(() => _block = reward.block);
    if (reward.minutes > 0) {
      unawaited(ScreenGuard.push());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('+${reward.minutes} min Handyzeit', key: const ValueKey('unlock-reward')),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _check(int i) async {
    final ai = _ai;
    if (ai == null) {
      setState(() => _error = 'Zum Prüfen braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final task = _block.tasks[i];
    setState(() {
      _busy = i;
      _error = null;
    });
    try {
      final result = await ai.checkUnlockAttempt(task: task, attempt: _answer(i).text);
      final ok = result.solved && !task.helped;
      await _save(
        _block.withTask(
          i,
          task.copyWith(
            state: ok ? UnlockTaskState.solved : UnlockTaskState.failed,
            attempts: task.attempts + 1,
            feedback: result.solved && task.helped
                ? 'Richtig – aber mit angesehener Lösung zählt es nicht als „ohne Hilfe“.'
                : result.feedback,
            explain: result.explain,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e is AiServiceException ? e.message : '$e');
    } finally {
      setState(() => _busy = null);
    }
  }

  /// Lösen wie jede andere Aufgabe: Mathe als Rechenweg (Stift-Blatt oder
  /// getippt, jede Zeile nachgerechnet, Taschenrechner, Vorrechnen an der
  /// Tafel), sonst in der passenden Frageart. Ohne Hilfe richtig = gelöst.
  Future<void> _solve(int i) async {
    var task = _block.tasks[i];
    var raw = task.card;
    if (raw == null) {
      final ai = _ai;
      if (ai == null) {
        setState(() => _error = 'Zum Lösen braucht die App deinen OpenRouter-Key (Einstellungen).');
        return;
      }
      setState(() {
        _busy = i;
        _error = null;
      });
      try {
        final card = await buildUnlockCard(ai, _block, i);
        raw = card.toMap();
        task = task.withCard(raw);
        await _save(_block.withTask(i, task));
      } catch (e) {
        setState(() {
          _plainAnswer.add(i);
          _error =
              'Die Aufgabe ließ sich nicht als Rechenweg aufbereiten (${e is AiServiceException ? e.message : e}) – '
              'schreib deine Lösung hier unten auf.';
        });
        return;
      } finally {
        setState(() => _busy = null);
      }
    }
    if (!mounted) return;
    final card = Flashcard.fromMap(raw);
    final hook = UnlockBlockScreen.solveHook;
    final result = hook != null
        ? await hook(context, card)
        : await Navigator.of(context).push<({Grade? selfGrade, bool? isCorrect})>(
            MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(title: Text('Aufgabe ${i + 1} · ${_block.title}', overflow: TextOverflow.ellipsis)),
                body: QuestionWithHelp(
                  key: ValueKey(card.id),
                  card: card,
                  isNew: false,
                  onComplete: ({Grade? selfGrade, bool? isCorrect}) =>
                      Navigator.of(context).pop((selfGrade: selfGrade, isCorrect: isCorrect)),
                ),
              ),
            ),
          );
    if (result == null || !mounted) return;
    final current = _block.tasks[i];
    final clean = LearnCredit.isClean(selfGrade: result.selfGrade, isCorrect: result.isCorrect) && !current.helped;
    final withHelp = !clean && (result.isCorrect ?? (result.selfGrade != null && result.selfGrade != Grade.again));
    await _save(
      _block.withTask(
        i,
        current.copyWith(
          state: clean ? UnlockTaskState.solved : UnlockTaskState.failed,
          attempts: current.attempts + 1,
          helped: current.helped || withHelp,
          feedback: clean
              ? 'Ohne Hilfe gelöst.'
              : withHelp
              ? 'Richtig – aber mit Hilfe (Tipp, Vorrechnen oder Lösung angesehen). Das zählt nicht als „ohne Hilfe“.'
              : 'Noch nicht richtig.',
          explain: '',
        ),
      ),
    );
  }

  Future<void> _revealSolution(int i) async {
    setState(() => _showSolution.add(i));
    final task = _block.tasks[i];
    if (task.helped) return;
    await _save(_block.withTask(i, task.copyWith(helped: true, state: UnlockTaskState.failed)));
  }

  Future<void> _startPractice(int i) async {
    final ai = _ai;
    if (ai == null) {
      setState(() => _error = 'Für die Übungseinheit braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    setState(() {
      _practiceBusy = true;
      _error = null;
    });
    try {
      final practice = await ai.planUnlockPractice(block: _block, index: i);
      await _save(_block.copyWith(practice: practice));
    } catch (e) {
      setState(() => _error = e is AiServiceException ? e.message : '$e');
    } finally {
      setState(() => _practiceBusy = false);
    }
  }

  Future<void> _practiceExercise(int e) async {
    final practice = _block.practice;
    if (practice == null) return;
    final hook = UnlockBlockScreen.practiceHook;
    var finished = false;
    if (hook != null) {
      finished = await hook(context, _block.moduleId, practice.exercises[e]);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkedSolutionScreen(
            moduleId: _block.moduleId,
            problem: practice.exercises[e],
            startSocratic: true,
            onFinished: () => finished = true,
          ),
        ),
      );
    }
    if (!finished || !mounted) return;
    var next = practice.withFinished(e);
    var block = _block.copyWith(practice: next);
    // Übungseinheit fertig: neue Aufgabe gleicher Art statt der alten.
    if (next.completed && next.retry != null && block.tasks[next.task].state != UnlockTaskState.solved) {
      block = block.withTask(next.task, next.retry!);
      _answer(next.task).clear();
      _showSolution.remove(next.task);
      next = UnlockPractice(task: next.task, intro: next.intro, exercises: next.exercises, finished: next.finished);
      block = block.copyWith(practice: next);
    }
    await _save(block);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final practice = _block.practice;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(_block.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_block.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_block.reason, style: TextStyle(color: c.inkMuted, height: 1.4)),
            ),
          if (_block.solved)
            Container(
              key: const ValueKey('unlock-solved'),
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: c.goodSoft, borderRadius: BorderRadius.circular(12)),
              child: const Text('Geschafft – beide Aufgaben ohne Hilfe gelöst. Die Handyzeit ist gutgeschrieben.'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!, style: TextStyle(color: c.danger)),
            ),
          if (practice != null && !practice.completed) _practiceCard(c, practice),
          for (final (i, t) in _block.tasks.indexed) _taskCard(c, i, t),
          if (practice != null && practice.completed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Übungseinheit abgeschlossen ✓',
                key: const ValueKey('unlock-practice-done'),
                style: TextStyle(color: c.good),
              ),
            ),
        ],
      ),
    );
  }

  Widget _practiceCard(AppColors c, UnlockPractice practice) => Padding(
    key: const ValueKey('unlock-practice'),
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: c.warnSoft,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Übungseinheit', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            MathText(practice.intro, style: const TextStyle(height: 1.45)),
            const SizedBox(height: 8),
            for (final (e, problem) in practice.exercises.indexed)
              ListTile(
                key: ValueKey('unlock-exercise-$e'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  practice.finished.contains(e) ? Icons.check_circle : Icons.co_present_outlined,
                  color: practice.finished.contains(e) ? c.good : c.accent,
                ),
                title: MathText(problem, maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  practice.finished.contains(e) ? 'Durchgearbeitet' : 'An der Tafel üben (selbst überlegen)',
                ),
                onTap: () => _practiceExercise(e),
              ),
            Text(
              'Alle durchgearbeitet: +${_rules.practiceMinutes} min – danach kommt eine neue Aufgabe gleicher Art.',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _taskCard(AppColors c, int i, UnlockTask t) {
    final solved = t.state == UnlockTaskState.solved;
    final failed = t.state == UnlockTaskState.failed;
    return Card(
      key: ValueKey('unlock-task-$i'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Aufgabe ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (solved) Icon(Icons.check_circle, color: c.good),
                if (failed) Icon(Icons.error_outline, color: c.warn),
              ],
            ),
            const SizedBox(height: 8),
            MathText(t.problem, style: const TextStyle(height: 1.45)),
            if (!solved && !_plainAnswer.contains(i)) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: ValueKey('unlock-solve-$i'),
                    onPressed: _busy != null ? null : () => _solve(i),
                    icon: _busy == i
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.edit_note),
                    label: Text(_busy == i ? 'Wird vorbereitet …' : (t.attempts == 0 ? 'Lösen' : 'Nochmal lösen')),
                  ),
                  OutlinedButton.icon(
                    key: ValueKey('unlock-solution-$i'),
                    onPressed: _busy != null ? null : () => _revealSolution(i),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Lösung ansehen (zählt als Hilfe)'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Mathe: Schritt für Schritt oder selbst rechnen – getippt oder mit Stift, jede Zeile wird nachgerechnet, '
                'Taschenrechner dabei. Vorrechnen an der Tafel und Tipps zählen als Hilfe.',
                style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.35),
              ),
            ],
            if (!solved && _plainAnswer.contains(i)) ...[
              const SizedBox(height: 10),
              TextField(
                key: ValueKey('unlock-answer-$i'),
                controller: _answer(i),
                minLines: 4,
                maxLines: 12,
                enabled: _busy == null,
                decoration: const InputDecoration(
                  hintText: 'Dein Lösungsweg – Formeln gern als LaTeX oder einfach so (x^2, sqrt(x) …)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: ValueKey('unlock-check-$i'),
                    onPressed: _busy != null ? null : () => _check(i),
                    icon: _busy == i
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.fact_check_outlined),
                    label: const Text('Prüfen'),
                  ),
                  OutlinedButton.icon(
                    key: ValueKey('unlock-solution-$i'),
                    onPressed: _busy != null ? null : () => _revealSolution(i),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Lösung ansehen (zählt als Hilfe)'),
                  ),
                ],
              ),
            ],
            if (t.feedback.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                key: ValueKey('unlock-feedback-$i'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: solved ? c.goodSoft : c.warnSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MathText(t.feedback, style: const TextStyle(height: 1.4)),
                    if (t.explain.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      MathText(t.explain, style: const TextStyle(height: 1.4)),
                    ],
                  ],
                ),
              ),
            ],
            if (_showSolution.contains(i) && t.solution.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
                child: MathText(
                  '${t.solution}${t.answer.isEmpty ? '' : '\n\nErgebnis: ${t.answer}'}',
                  style: const TextStyle(height: 1.4),
                ),
              ),
            ],
            if (failed && _block.practice == null) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                key: ValueKey('unlock-start-practice-$i'),
                onPressed: _practiceBusy ? null : () => _startPractice(i),
                icon: _practiceBusy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.fitness_center),
                label: const Text('Übungseinheit starten'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
