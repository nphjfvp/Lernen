import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../models/step_task.dart';
import '../../models/visual_lesson.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/visual_lesson_repository.dart';
import '../../services/ai_service.dart';
import '../../services/visual_math.dart';
import '../../theme/app_colors.dart';
import '../tasks/step_task_view.dart';
import '../widgets/math_text.dart';
import 'visual_diagram_view.dart';
import 'visual_scene3d_view.dart';
import 'visual_show_view.dart';
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
/// richtigen simulieren und erklären. Wahlweise sokratisch: Jeder Schritt
/// bleibt verdeckt, bis man ihn mit Leitfragen der KI selbst gefunden (oder
/// aufgelöst) hat.
class VisualLessonScreen extends StatefulWidget {
  const VisualLessonScreen({
    super.key,
    required this.lesson,
    this.startShort = false,
    this.onFinished,
    this.finishLabel = 'Thema abschließen',
  });

  final VisualLesson lesson;

  /// Gleich die Kurzfassung zeigen (zum Wiedereinsteigen).
  final bool startShort;

  /// Im Lernpfad: am Ende „Thema abschließen“ (schließt die Lektion).
  final VoidCallback? onFinished;
  final String finishLabel;

  /// Test-Hook statt OpenRouter.
  static AiService? Function(String apiKey, String model)? aiFactory;

  @override
  State<VisualLessonScreen> createState() => _VisualLessonScreenState();
}

enum _PageKind { step, result, exercise }

/// Sokratischer Dialog zu einem Schritt.
class _Socratic {
  final turns = <({bool user, String text})>[];
  final answer = TextEditingController();
  bool reached = false;
  bool revealed = false;
  bool busy = false;
  String? error;

  /// Was die KI zum Beobachten zeigt (null = Standardansicht).
  VisualShow? show;
  VisualMath? math;
  List<TransformState> transform = const [];

  bool get unlocked => reached || revealed;
}

class _VisualLessonScreenState extends State<VisualLessonScreen> {
  /// Die Lektion – „Darstellung ändern“ ersetzt sie.
  late VisualLesson _lesson = widget.lesson;
  late VisualMath _math = VisualMath(_lesson);
  int _page = 0;
  late VisualStyle _style = widget.lesson.style;
  late bool _short = widget.startShort && widget.lesson.shortVersion != null;
  final _socratic = <int, _Socratic>{};

  /// Letzte falsche Antwort in der Übung.
  ({StepField field, String input})? _wrong;
  bool _exerciseDone = false;

  VisualLesson get _l => _lesson;

  @override
  void dispose() {
    for (final s in _socratic.values) {
      s.answer.dispose();
    }
    super.dispose();
  }

  _Socratic _socraticFor(int i) => _socratic.putIfAbsent(i, () {
    final state = _Socratic();
    final guide = _l.steps[i].guide;
    if (guide.isNotEmpty) state.turns.add((user: false, text: guide));
    return state;
  });

  void _setStyle(VisualStyle style) {
    setState(() => _style = style);
    // Wahl merken, damit die Lektion beim nächsten Mal so startet.
    final repo = context.read<VisualLessonRepository?>();
    _lesson = _l.copyWith(style: style);
    if (repo != null && _l.id.isNotEmpty) repo.save(_lesson);
  }

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
                if (_l.shortVersion != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SegmentedButton<bool>(
                      key: const ValueKey('visual-length'),
                      segments: const [
                        ButtonSegment(value: false, label: Text('Ausführlich'), icon: Icon(Icons.subject)),
                        ButtonSegment(value: true, label: Text('Kurzfassung'), icon: Icon(Icons.short_text)),
                      ],
                      selected: {_short},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() => _short = v.first),
                    ),
                  ),
                if (_short)
                  Expanded(child: _shortBody(c))
                else ...[
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: SegmentedButton<VisualStyle>(
                      key: const ValueKey('visual-style'),
                      segments: const [
                        ButtonSegment(
                          value: VisualStyle.explain,
                          label: Text('Erklären'),
                          icon: Icon(Icons.menu_book_outlined),
                        ),
                        ButtonSegment(
                          value: VisualStyle.socratic,
                          label: Text('Sokratisch'),
                          icon: Icon(Icons.psychology_alt_outlined),
                        ),
                      ],
                      selected: {_style},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => _setStyle(s.first),
                    ),
                  ),
                  Expanded(
                    child: page.kind == _PageKind.exercise
                        ? _exercise(c)
                        : ListView(
                            key: ValueKey('visual-page-body-$_page'),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            children: [
                              if (_page == 0 && _l.recap.isNotEmpty) ...[
                                Container(
                                  key: const ValueKey('visual-recap'),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: c.surfaceAlt,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border(left: BorderSide(color: c.accent, width: 4)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Rückblick',
                                        style: TextStyle(fontWeight: FontWeight.w700, color: c.accent),
                                      ),
                                      const SizedBox(height: 4),
                                      MathText(_l.recap, style: const TextStyle(fontSize: 14.5, height: 1.45)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (_page == 0 && _l.intro.isNotEmpty) ...[
                                Container(
                                  key: const ValueKey('visual-intro'),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: c.accentSoft,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: MathText(_l.intro, style: const TextStyle(fontSize: 14.5, height: 1.45)),
                                ),
                                const SizedBox(height: 14),
                              ],
                              if (_style == VisualStyle.socratic && page.kind == _PageKind.step) ...[
                                if (_socraticFor(_page).unlocked) ...[
                                  _unlockedBanner(c, _socratic[_page]!),
                                  const SizedBox(height: 12),
                                  ..._stepBody(c, page.step!, isResult: false),
                                ] else
                                  ..._socraticBody(c, _page, page.step!),
                              ] else
                                ..._stepBody(c, page.step!, isResult: page.kind == _PageKind.result),
                            ],
                          ),
                  ),
                  _nav(c, pages.length),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Hinweis, wenn sich die Darstellung (ganz oder teilweise) nicht laden ließ –
  /// mit „Neu erzeugen“ statt still wegzulassen.
  Widget _brokenNote(AppColors c, VisualShow show, int stepIndex) {
    final nothing = !VisualShowView.hasContent(show);
    return Container(
      key: const ValueKey('visual-broken'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.broken_image_outlined, color: c.warn, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${nothing ? 'Die Darstellung ließ sich nicht laden' : 'Ein Teil der Darstellung fehlt'}: ${show.broken}.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            key: const ValueKey('visual-broken-retry'),
            onPressed: () => _revise(
              stepIndex,
              request:
                  'Die Darstellung dieses Schritts ließ sich nicht laden (${show.broken}). Erzeuge sie neu – genau im '
                  'beschriebenen Format, nur mit vorhandenen Funktionen.',
            ),
            child: const Text('Neu erzeugen'),
          ),
        ],
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
    if (step.show.scene != null) ...[
      const SizedBox(height: 12),
      VisualDiagramView(key: ValueKey('visual-diagram-$_page'), diagram: step.show.scene!),
    ],
    if (step.show.scene3d != null) ...[
      const SizedBox(height: 12),
      VisualScene3DView(key: ValueKey('visual-scene3d-$_page'), scene: step.show.scene3d!),
    ],
    if (VisualSceneView.hasScene(step.show)) ...[
      const SizedBox(height: 12),
      VisualSceneView(key: ValueKey('visual-scene-$_page'), math: _math, show: step.show),
    ],
    if (step.show.broken.isNotEmpty) _brokenNote(c, step.show, isResult ? -1 : _page),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('visual-ask'),
          onPressed: () => _ask(step: step),
          icon: const Icon(Icons.help_outline, size: 18),
          label: Text(isResult ? 'Frage zum Ergebnis' : 'Frage zu diesem Schritt'),
        ),
        TextButton.icon(
          key: const ValueKey('visual-revise'),
          onPressed: () => _revise(isResult ? -1 : _page),
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: const Text('Darstellung ändern'),
        ),
      ],
    ),
  ];

  /// „Darstellung ändern“: Wunsch eingeben, die KI baut den Schritt (oder die
  /// ganze Lektion) um; gespeichert, mit Rückgängig.
  Future<void> _revise(int stepIndex, {String request = ''}) async {
    final repo = context.read<VisualLessonRepository?>();
    final messenger = ScaffoldMessenger.of(context);
    final before = _l;
    final revised = await showModalBottomSheet<VisualLesson>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) =>
          VisualReviseSheet(lesson: before, stepIndex: stepIndex, ai: _reviseAi(context), initialRequest: request),
    );
    if (revised == null || !mounted) return;
    void apply(VisualLesson l) {
      setState(() {
        _lesson = l;
        _math = VisualMath(l);
        _socratic.clear();
        _wrong = null;
        _page = _page.clamp(0, _pages.length - 1);
        if (_short && l.shortVersion == null) _short = false;
      });
      if (repo != null && l.id.isNotEmpty) repo.save(l);
    }

    apply(revised);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Darstellung geändert.'),
        action: SnackBarAction(
          key: const ValueKey('visual-revise-undo'),
          label: 'Rückgängig',
          onPressed: () {
            if (mounted) apply(before);
          },
        ),
      ),
    );
  }

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
          )
        else if (widget.onFinished != null)
          FilledButton.icon(
            key: const ValueKey('visual-finish'),
            onPressed: () {
              widget.onFinished!();
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.check),
            label: Text(widget.finishLabel),
          ),
      ],
    ),
  );

  /// Kurzfassung: Kernpunkte, Formel und die eine Darstellung.
  Widget _shortBody(AppColors c) {
    final s = _l.shortVersion!;
    return ListView(
      key: const ValueKey('visual-short'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(s.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (s.text.isNotEmpty) MathText(s.text, style: const TextStyle(fontSize: 15, height: 1.55)),
        if (s.formula.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(12)),
            child: MathText('\$\$${s.formula}\$\$', style: const TextStyle(fontSize: 17)),
          ),
        ],
        if (s.show.transform.isNotEmpty) ...[
          const SizedBox(height: 12),
          EquationTransformView(states: s.show.transform),
        ],
        if (s.show.scene != null) ...[const SizedBox(height: 12), VisualDiagramView(diagram: s.show.scene!)],
        if (s.show.scene3d != null) ...[const SizedBox(height: 12), VisualScene3DView(scene: s.show.scene3d!)],
        if (VisualSceneView.hasScene(s.show)) ...[
          const SizedBox(height: 12),
          VisualSceneView(math: _math, show: s.show),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton.icon(
              key: const ValueKey('visual-short-revise'),
              onPressed: () => _revise(-2),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Ändern'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              key: const ValueKey('visual-short-full'),
              onPressed: () => setState(() => _short = false),
              icon: const Icon(Icons.subject),
              label: const Text('Ausführlich ansehen'),
            ),
            const Spacer(),
            if (widget.onFinished != null)
              FilledButton.icon(
                key: const ValueKey('visual-short-finish'),
                onPressed: () {
                  widget.onFinished!();
                  Navigator.of(context).maybePop();
                },
                icon: const Icon(Icons.check),
                label: const Text('Erledigt'),
              ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Sokratisch
  // -------------------------------------------------------------------------

  /// Was man beim Nachdenken sieht, ohne dass das Ergebnis verraten wird:
  /// beim ersten Schritt nur das Auto, sonst der Stand des vorigen Schritts.
  VisualShow _thinkingShow(int i) {
    final step = _l.steps[i];
    if (i == 0) {
      return VisualShow(
        car: step.show.car,
        carSource: step.show.carSource,
        vehicle: step.show.vehicle,
        scene: step.show.scene,
        scene3d: step.show.scene3d,
      );
    }
    final prev = _l.steps[i - 1].show;
    return VisualShow(
      car: prev.car,
      carSource: prev.carSource,
      vehicle: prev.vehicle,
      plot: prev.plot,
      tangent: prev.tangent,
      area: prev.area,
      scene: prev.scene,
      scene3d: prev.scene3d,
    );
  }

  List<Widget> _socraticBody(AppColors c, int i, VisualStep step) {
    final s = _socraticFor(i);
    if (s.turns.isEmpty && !s.busy && s.error == null) {
      // Keine Leitfrage gespeichert: die KI eröffnet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && s.turns.isEmpty && !s.busy) _socraticTurn(i);
      });
    }
    final show = s.show ?? _thinkingShow(i);
    final math = s.show != null ? s.math ?? _math : _math;
    return [
      Text(
        step.title,
        key: const ValueKey('visual-step-title'),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text('Finde diesen Schritt selbst heraus – die KI führt dich hin.', style: TextStyle(color: c.inkMuted)),
      if (show.scene != null) ...[
        const SizedBox(height: 12),
        VisualDiagramView(key: ValueKey('socratic-diagram-$i-${s.turns.length}'), diagram: show.scene!),
      ],
      if (show.scene3d != null) ...[
        const SizedBox(height: 12),
        VisualScene3DView(key: ValueKey('socratic-scene3d-$i-${s.turns.length}'), scene: show.scene3d!),
      ],
      if (VisualSceneView.hasScene(show)) ...[
        const SizedBox(height: 12),
        VisualSceneView(key: ValueKey('socratic-scene-$i-${s.turns.length}'), math: math, show: show),
      ],
      const SizedBox(height: 12),
      for (final (j, t) in s.turns.indexed)
        Align(
          alignment: t.user ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            key: ValueKey('socratic-turn-$j'),
            constraints: const BoxConstraints(maxWidth: 620),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: t.user ? c.surfaceAlt : c.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: MathText(t.text, style: const TextStyle(fontSize: 14.5, height: 1.45)),
          ),
        ),
      if (s.transform.isNotEmpty) ...[
        const SizedBox(height: 4),
        EquationTransformView(key: ValueKey('socratic-transform-$i-${s.turns.length}'), states: s.transform),
        const SizedBox(height: 8),
      ],
      if (s.busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      if (s.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            s.error!,
            key: const ValueKey('socratic-error'),
            style: TextStyle(color: c.danger),
          ),
        ),
      TextField(
        key: const ValueKey('socratic-answer'),
        controller: s.answer,
        minLines: 1,
        maxLines: 5,
        enabled: !s.busy,
        decoration: const InputDecoration(
          labelText: 'Deine Überlegung',
          hintText: 'Eigene Worte genügen, Formeln z.B. als v(t) = …',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          FilledButton.icon(
            key: const ValueKey('socratic-send'),
            onPressed: s.busy ? null : () => _socraticTurn(i, answer: s.answer.text),
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Antworten'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('socratic-hint'),
            onPressed: s.busy ? null : () => _socraticTurn(i, hint: true),
            icon: const Icon(Icons.lightbulb_outline, size: 18),
            label: const Text('Tipp'),
          ),
          TextButton.icon(
            key: const ValueKey('socratic-reveal'),
            onPressed: s.busy ? null : () => setState(() => s.revealed = true),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Auflösen'),
          ),
        ],
      ),
    ];
  }

  Widget _unlockedBanner(AppColors c, _Socratic s) {
    final last = s.turns.lastOrNull;
    return Container(
      key: ValueKey(s.reached ? 'socratic-reached' : 'socratic-revealed'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: s.reached ? c.goodSoft : c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.reached ? 'Selbst herausgefunden!' : 'Aufgelöst – so geht der Schritt:',
            style: TextStyle(fontWeight: FontWeight.w700, color: s.reached ? c.good : null),
          ),
          if (s.reached && last != null && !last.user) ...[
            const SizedBox(height: 4),
            MathText(last.text, style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Future<void> _socraticTurn(int i, {String answer = '', bool hint = false}) async {
    final s = _socraticFor(i);
    final ai = visualAi(context);
    if (ai == null) {
      setState(() => s.error = 'Für sokratisches Lernen braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final text = answer.trim();
    if (!hint && text.isEmpty && s.turns.isNotEmpty) return;
    final history = [...s.turns];
    setState(() {
      s.busy = true;
      s.error = null;
      if (text.isNotEmpty) s.turns.add((user: true, text: text));
      if (hint) s.turns.add((user: true, text: 'Kannst du mir einen Tipp geben?'));
      s.answer.clear();
    });
    try {
      final json = await ai.visualSocraticTurn(
        lesson: _l.toMap(),
        stepIndex: i,
        step: _l.steps[i].toMap(),
        history: history,
        answer: text,
        hint: hint,
      );
      if (!mounted) return;
      final extra = [
        if (json['functions'] is List)
          for (final f in json['functions'] as List) ?VisualFunction.fromMap(f),
      ];
      final derived = extra.isEmpty ? _l : _l.withFunctions(_l.functions, extra: extra);
      final known = {for (final f in derived.functions) f.key};
      final show = VisualShow.fromMap(json['show']).restrictedTo(known);
      setState(() {
        s.turns.add((user: false, text: '${json['reply']}'));
        s.reached = json['reached'] == true;
        s.transform = [
          if (json['transform'] is List)
            for (final t in json['transform'] as List) ?TransformState.fromRaw(t),
        ];
        if (VisualSceneView.hasScene(show) || show.scene != null || show.scene3d != null) {
          s.show = show;
          s.math = VisualMath(derived);
        }
      });
    } on AiServiceException catch (e) {
      if (mounted) setState(() => s.error = e.message);
    } catch (e) {
      if (mounted) setState(() => s.error = 'Das hat nicht geklappt: $e');
    } finally {
      if (mounted) setState(() => s.busy = false);
    }
  }

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
          vehicle: _l.vehicle,
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
          if (_show.scene != null) ...[
            const SizedBox(height: 12),
            VisualDiagramView(key: const ValueKey('visual-answer-diagram'), diagram: _show.scene!),
          ],
          if (_show.scene3d != null) ...[
            const SizedBox(height: 12),
            VisualScene3DView(key: const ValueKey('visual-answer-scene3d'), scene: _show.scene3d!),
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

/// KI für „Darstellung ändern“ (Fragen-Modell wie beim Erstellen) – null ohne Key.
AiService? _reviseAi(BuildContext context) {
  final settings = context.read<SettingsRepository?>()?.settings;
  if (settings == null || !settings.hasApiKey) return null;
  return VisualLessonScreen.aiFactory?.call(settings.openRouterApiKey!, settings.questionModelId) ??
      AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
}

/// Wunsch zur Darstellung eingeben – für diesen Schritt oder die ganze
/// Lektion. Gibt die überarbeitete Lektion zurück.
class VisualReviseSheet extends StatefulWidget {
  const VisualReviseSheet({
    super.key,
    required this.lesson,
    required this.stepIndex,
    this.ai,
    this.initialRequest = '',
  });

  /// Vorausgefüllter Wunsch (z.B. „Darstellung neu erzeugen“).
  final String initialRequest;

  final VisualLesson lesson;

  /// Index in steps; -1 Ergebnis, -2 Kurzfassung.
  final int stepIndex;
  final AiService? ai;

  @override
  State<VisualReviseSheet> createState() => _VisualReviseSheetState();
}

class _VisualReviseSheetState extends State<VisualReviseSheet> {
  late final _request = TextEditingController(text: widget.initialRequest);
  bool _all = false;
  bool _busy = false;
  String? _error;

  static const _quick = [
    'Formeln in der Darstellung richtig setzen',
    'Übersichtlicher und größer – nichts überlappt',
    'Anderes, anschaulicheres Beispiel',
    'Rakete statt Auto',
    'Mehr Zwischenschritte zeigen',
    'Als 3D-Modell zeigen',
  ];

  String get _where => switch (widget.stepIndex) {
    -1 => 'das Ergebnis',
    -2 => 'die Kurzfassung',
    final i => 'Schritt ${i + 1}',
  };

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ai = widget.ai;
    if (ai == null) {
      setState(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    if (_request.text.trim().isEmpty) {
      setState(() => _error = 'Schreib, was anders sein soll – oder tippe einen Vorschlag an.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final index = _all ? null : widget.stepIndex;
      final json = await ai.reviseVisualLesson(
        lesson: widget.lesson.toMap(),
        request: _request.text.trim(),
        stepIndex: index,
      );
      final revised = widget.lesson.revisedWith(json, stepIndex: index);
      if (revised == null || !revised.isUsable) {
        throw AiServiceException('Die Überarbeitung ließ sich nicht übernehmen – bitte erneut versuchen.');
      }
      if (mounted) Navigator.of(context).pop(VisualMath.sanitize(revised));
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Das hat nicht geklappt: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Darstellung ändern', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Sag, was anders sein soll – von „Formeln richtig setzen“ bis „mach eine Rakete draus“.',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, q) in _quick.indexed)
                  ActionChip(
                    key: ValueKey('visual-revise-quick-$i'),
                    label: Text(q),
                    onPressed: _busy ? null : () => setState(() => _request.text = q),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('visual-revise-request'),
              controller: _request,
              enabled: !_busy,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Dein Wunsch',
                hintText: 'z.B. „Zeig die Kräfte als Pfeile“ oder „nimm eine Rakete statt des Autos“',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              key: const ValueKey('visual-revise-scope'),
              segments: [
                ButtonSegment(value: false, label: Text('Nur $_where')),
                const ButtonSegment(value: true, label: Text('Ganze Lektion')),
              ],
              selected: {_all},
              showSelectedIcon: false,
              onSelectionChanged: _busy ? null : (v) => setState(() => _all = v.first),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('visual-revise-send'),
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_fix_high, size: 18),
              label: Text(_busy ? 'Die KI baut um …' : 'Ändern'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const ValueKey('visual-revise-error'),
                style: TextStyle(color: c.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
