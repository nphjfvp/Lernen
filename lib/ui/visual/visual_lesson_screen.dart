import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../models/step_task.dart';
import '../../models/visual_lesson.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/visual_math.dart';
import '../../theme/app_colors.dart';
import '../tasks/step_task_view.dart';
import '../widgets/math_text.dart';
import 'visual_scene.dart';

/// KI für Rückfragen in „Visuell lernen“ (Hilfe-Modell) – null ohne Key.
AiService? visualAi(BuildContext context) {
  final settings = context.read<SettingsRepository?>()?.settings;
  if (settings == null || !settings.hasApiKey) return null;
  return VisualLessonScreen.aiFactory?.call(settings.openRouterApiKey!, settings.effectiveHelpModelId) ??
      AiService(apiKey: settings.openRouterApiKey!, model: settings.effectiveHelpModelId);
}

/// Eine Lektion aus „Visuell lernen“ abspielen: Schritt für Schritt mit
/// Simulation (Auto, Graph, Umformung), zu jedem Schritt eine Rückfrage
/// (visuell, schriftlich oder beides), das Ergebnis simuliert und am Ende eine
/// Übung wie ein Rechenweg – eine falsche Antwort lässt sich neben der
/// richtigen simulieren und erklären.
class VisualLessonScreen extends StatefulWidget {
  const VisualLessonScreen({super.key, required this.lesson});

  final VisualLesson lesson;

  /// Test-Hook statt OpenRouter.
  static AiService? Function(String apiKey, String model)? aiFactory;

  @override
  State<VisualLessonScreen> createState() => _VisualLessonScreenState();
}

enum _PageKind { step, result, exercise }

class _VisualLessonScreenState extends State<VisualLessonScreen> {
  late final VisualMath _math = VisualMath(widget.lesson);
  int _page = 0;

  /// Letzte falsche Antwort in der Übung.
  ({StepField field, String input})? _wrong;
  bool _exerciseDone = false;

  VisualLesson get _l => widget.lesson;

  List<({_PageKind kind, VisualStep? step, String label})> get _pages => [
    for (final (i, s) in _l.steps.indexed) (kind: _PageKind.step, step: s, label: '${i + 1}'),
    if (_l.result != null) (kind: _PageKind.result, step: _l.result, label: 'Ergebnis'),
    if (_l.exercise != null) (kind: _PageKind.exercise, step: null, label: 'Übung'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pages = _pages;
    final page = pages[_page.clamp(0, pages.length - 1)];
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(_l.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    children: [
                      for (final (i, p) in pages.indexed)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            key: ValueKey('visual-page-$i'),
                            label: Text(p.label),
                            selected: i == _page,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _page = i),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: page.kind == _PageKind.exercise
                      ? _exercise(c)
                      : ListView(
                          key: ValueKey('visual-page-body-$_page'),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          children: [
                            if (_page == 0 && _l.intro.isNotEmpty) ...[
                              Container(
                                key: const ValueKey('visual-intro'),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14)),
                                child: MathText(_l.intro, style: const TextStyle(fontSize: 14.5, height: 1.45)),
                              ),
                              const SizedBox(height: 14),
                            ],
                            ..._stepBody(c, page.step!, isResult: page.kind == _PageKind.result),
                          ],
                        ),
                ),
                _nav(c, pages.length),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _stepBody(AppColors c, VisualStep step, {required bool isResult}) => [
    Text(
      step.title,
      key: const ValueKey('visual-step-title'),
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    if (step.text.isNotEmpty) MathText(step.text, style: const TextStyle(fontSize: 14.5, height: 1.5)),
    if (step.formula.isNotEmpty) ...[
      const SizedBox(height: 10),
      Container(
        key: const ValueKey('visual-formula'),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(12)),
        child: MathText('\$\$${step.formula}\$\$', style: const TextStyle(fontSize: 17)),
      ),
    ],
    if (step.show.transform.isNotEmpty) ...[
      const SizedBox(height: 12),
      EquationTransformView(key: ValueKey('visual-transform-$_page'), states: step.show.transform),
    ],
    if (VisualSceneView.hasScene(step.show)) ...[
      const SizedBox(height: 12),
      VisualSceneView(key: ValueKey('visual-scene-$_page'), math: _math, show: step.show),
    ],
    const SizedBox(height: 12),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const ValueKey('visual-ask'),
        onPressed: () => _ask(step: step),
        icon: const Icon(Icons.help_outline, size: 18),
        label: Text(isResult ? 'Frage zum Ergebnis' : 'Frage zu diesem Schritt'),
      ),
    ),
  ];

  Widget _nav(AppColors c, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Row(
      children: [
        OutlinedButton.icon(
          key: const ValueKey('visual-prev'),
          onPressed: _page == 0 ? null : () => setState(() => _page--),
          icon: const Icon(Icons.chevron_left),
          label: const Text('Zurück'),
        ),
        const Spacer(),
        if (_page < count - 1)
          FilledButton.icon(
            key: const ValueKey('visual-next'),
            onPressed: () => setState(() => _page++),
            icon: const Icon(Icons.chevron_right),
            label: Text(_pages[_page + 1].kind == _PageKind.exercise ? 'Jetzt du' : 'Weiter'),
          ),
      ],
    ),
  );

  // -------------------------------------------------------------------------
  // Übung
  // -------------------------------------------------------------------------

  Widget _exercise(AppColors c) {
    final card = Flashcard(
      id: 'visual-${_l.id}',
      moduleId: _l.moduleId,
      front: _l.exerciseFront.isEmpty ? 'Übung' : _l.exerciseFront,
      back: '',
      createdAt: _l.createdAt,
      due: _l.createdAt,
      type: QuestionType.steps,
      taskData: _l.exercise!.toMap(),
    );
    return Column(
      children: [
        Expanded(
          child: StepTaskView(
            key: const ValueKey('visual-exercise'),
            card: card,
            task: _l.exercise!,
            isNew: false,
            onComplete: ({selfGrade, isCorrect}) {
              setState(() => _exerciseDone = true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isCorrect == true
                        ? 'Übung geschafft – stark!'
                        : 'Übung beendet. Schau dir die Schritte nochmal an.',
                  ),
                ),
              );
            },
            onWrongAnswer: (field, input) => setState(() => _wrong = (field: field, input: input)),
          ),
        ),
        if (_wrong != null && !_exerciseDone)
          Container(
            key: const ValueKey('visual-wrong-bar'),
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(14)),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  'Deine Antwort: ${_wrong!.input}',
                  style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('visual-simulate-wrong'),
                  onPressed: _simulateWrong,
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('Simulieren'),
                ),
                TextButton.icon(
                  key: const ValueKey('visual-why-wrong'),
                  onPressed: () => _ask(wrong: _wrong),
                  icon: const Icon(Icons.help_outline, size: 18),
                  label: const Text('Warum falsch?'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Die falsche Antwort neben der richtigen: im Graphen und – wenn die
  /// Lektion es vorsieht – als zweites Auto.
  void _simulateWrong() {
    final wrong = _wrong;
    if (wrong == null) return;
    final v = _l.variable;
    final right = VisualCurve.tryParse(wrong.field.answer, v);
    final mine = VisualCurve.tryParse(wrong.input, v);
    final sim = _l.simulation;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final c = ctx.colors;
        if (right == null || mine == null) {
          final r = right?.at(_l.domainMin), m = mine?.at(_l.domainMin);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Text(
              m != null && r != null
                  ? 'Deine Antwort ergibt ${VisualMath.fmt(m)}, richtig wäre ${VisualMath.fmt(r)}.'
                  : 'Diese Antwort lässt sich nicht als Funktion von $v simulieren – „Warum falsch?“ erklärt den Fehler.',
              key: const ValueKey('visual-simulate-text'),
            ),
          );
        }
        final derived = _l.withFunctions(
          _l.functions,
          extra: [
            VisualFunction(key: '__richtig', expr: wrong.field.answer, label: 'richtig'),
            VisualFunction(key: '__deine', expr: wrong.input, label: 'deine Antwort'),
          ],
        );
        final math = VisualMath(derived);
        final source = sim == ExerciseSimulation.velocity ? CarSource.velocity : CarSource.position;
        final withCar = sim != ExerciseSimulation.graph;
        final show = VisualShow(
          car: withCar ? '__richtig' : null,
          carSource: source,
          plot: const ['__richtig', '__deine'],
        );
        final end = _l.domainMax;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('Deine Antwort simuliert', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Am Ende ($v = ${VisualMath.fmt(end)}): deine Antwort ${VisualMath.fmt(mine.at(end))}, '
                'richtig ${VisualMath.fmt(right.at(end))}.',
                key: const ValueKey('visual-simulate-text'),
                style: TextStyle(color: c.inkMuted),
              ),
              const SizedBox(height: 10),
              VisualSceneView(
                math: math,
                show: show,
                ghost: withCar ? GhostCar(label: 'Deine Antwort', curve: mine, source: source) : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _ask({VisualStep? step, ({StepField field, String input})? wrong}) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => VisualAskSheet(lesson: _l, step: step, wrong: wrong, ai: visualAi(context)),
  );
}

/// Rückfrage zu einem Schritt bzw. „Warum ist meine Antwort falsch?“ – der
/// Nutzer wählt visuell, schriftlich oder beides.
class VisualAskSheet extends StatefulWidget {
  const VisualAskSheet({super.key, required this.lesson, this.step, this.wrong, this.ai});

  final VisualLesson lesson;
  final VisualStep? step;
  final ({StepField field, String input})? wrong;
  final AiService? ai;

  @override
  State<VisualAskSheet> createState() => _VisualAskSheetState();
}

class _VisualAskSheetState extends State<VisualAskSheet> {
  final _question = TextEditingController();
  String _mode = 'both';
  bool _busy = false;
  String? _error;
  String _text = '';
  List<TransformState> _transform = const [];
  VisualMath? _math;
  VisualShow _show = const VisualShow();

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ai = widget.ai;
    if (ai == null) {
      setState(() => _error = 'Für Rückfragen braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final wrong = widget.wrong;
      final json = await ai.explainVisual(
        lesson: widget.lesson.toMap(),
        stepTitle: widget.step?.title ?? '',
        stepText: [widget.step?.text ?? '', widget.step?.formula ?? ''].where((s) => s.isNotEmpty).join('\n'),
        question: _question.text,
        mode: _mode,
        wrongAnswer: wrong?.input ?? '',
        expectedAnswer: wrong?.field.answer ?? '',
        fieldLabel: wrong?.field.label ?? '',
      );
      if (!mounted) return;
      final extra = [
        if (json['functions'] is List)
          for (final f in json['functions'] as List) ?VisualFunction.fromMap(f),
      ];
      final derived = widget.lesson.withFunctions(widget.lesson.functions, extra: extra);
      final known = {for (final f in derived.functions) f.key};
      setState(() {
        _text = '${json['text'] ?? ''}'.trim();
        _transform = [
          if (json['transform'] is List)
            for (final t in json['transform'] as List) ?TransformState.fromRaw(t),
        ];
        _show = VisualShow.fromMap(json['show']).restrictedTo(known);
        _math = VisualMath(derived);
      });
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Die Erklärung hat nicht geklappt: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wrong = widget.wrong;
    final math = _math;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            wrong != null ? 'Warum ist das falsch?' : 'Frage zu „${widget.step?.title ?? ''}“',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (wrong != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Deine Antwort: ${wrong.input}', style: TextStyle(color: c.danger)),
            ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('visual-question'),
            controller: _question,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: wrong != null
                  ? 'Was verstehst du nicht? (optional)'
                  : 'Deine Frage, z.B. „Warum ist y′ = dy/dx?“',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            key: const ValueKey('visual-mode'),
            segments: const [
              ButtonSegment(value: 'visual', label: Text('Visuell'), icon: Icon(Icons.animation)),
              ButtonSegment(value: 'text', label: Text('Schriftlich'), icon: Icon(Icons.notes)),
              ButtonSegment(value: 'both', label: Text('Beides')),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('visual-ask-send'),
            onPressed: _busy ? null : _send,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send, size: 18),
            label: Text(_busy ? 'Einen Moment …' : 'Erklären'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const ValueKey('visual-ask-error'),
              style: TextStyle(color: c.danger),
            ),
          ],
          if (_text.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              key: const ValueKey('visual-answer-text'),
              child: MathText(_text, style: const TextStyle(fontSize: 14.5, height: 1.5)),
            ),
          ],
          if (_transform.isNotEmpty) ...[
            const SizedBox(height: 12),
            EquationTransformView(states: _transform, autoplay: true),
          ],
          if (math != null && VisualSceneView.hasScene(_show)) ...[
            const SizedBox(height: 12),
            VisualSceneView(key: const ValueKey('visual-answer-scene'), math: math, show: _show),
          ],
        ],
      ),
    );
  }
}
