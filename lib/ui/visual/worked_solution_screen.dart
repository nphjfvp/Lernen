import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/flashcard.dart';
import '../../models/step_task.dart';
import '../../models/visual_task_type.dart';
import '../../models/worked_solution.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/visual_task_type_repository.dart';
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
    this.general = false,
    this.startSocratic = false,
  });

  /// Gleich als Rezept (allgemein, ohne Zahlen) starten.
  final bool general;

  /// Gleich sokratisch: erst selbst überlegen, dann aufdecken.
  final bool startSocratic;

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

  /// Musterlösung einer Karte für die KI: Rückseite und Schritte.
  static String referenceFor(Flashcard card) {
    final task = card.type == QuestionType.steps ? StepTask.fromMap(card.taskData) : null;
    final steps = [
      for (final (i, s) in (task?.steps ?? const <TaskStep>[]).indexed)
        '${i + 1}. ${s.title}${s.resultText.isEmpty ? '' : ': ${s.resultText}'}',
    ].join('\n');
    return [if (card.back.trim().isNotEmpty) card.back.trim(), if (steps.isNotEmpty) steps].join('\n\n');
  }

  /// Aufgabenbild einer Karte.
  static Uint8List? imageOf(Flashcard card) {
    final b64 = card.imageBase64;
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Test-Hook: Aufgabentypen des Fachs (Titel: Beschreibung).
  static Future<List<String>> Function(String moduleId)? taskTypesLoader;

  /// Takt bei „Automatisch“.
  static Duration autoDelay = const Duration(milliseconds: 2800);

  @override
  State<WorkedSolutionScreen> createState() => _WorkedSolutionScreenState();
}

class _WorkedSolutionScreenState extends State<WorkedSolutionScreen> with SafeSetState<WorkedSolutionScreen> {
  late final _problem = TextEditingController(text: widget.problem);

  // Aufgabe aus einer vorhandenen Karte (vorbelegt oder gewählt).
  late String _reference = widget.reference;
  late Uint8List? _image = widget.image;
  late String? _cardId = widget.cardId;
  Flashcard? _pickedCard;
  late bool _general = widget.general;

  /// Sokratisch: vor jedem Schritt erst selbst sagen, was man tun würde.
  late bool _socratic = widget.startSocratic;

  /// Schritt, zu dem gerade ein Vorschlag erwartet wird.
  int? _askStep;
  final Set<int> _known = {};
  final Set<int> _skipped = {};

  /// „Nicht Gewusstes üben“: nur diese Schritte werden abgefragt.
  Set<int>? _practiceOnly;
  final Set<int> _selected = {};
  final _idea = TextEditingController();
  bool _ideaBusy = false;
  ({String verdict, String feedback, String hint})? _ideaResult;

  /// Rückmeldung zum zuletzt richtig vorgeschlagenen Schritt.
  ({int step, String text})? _praise;
  List<String> _taskTypes = const [];
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
    _idea.dispose();
    super.dispose();
  }

  WorkedSolutionRepository? get _repo => context.read<WorkedSolutionRepository?>();

  Future<void> _load({bool openExisting = true}) async {
    final repo = _repo;
    if (repo == null) {
      await _loadTypes();
      if (_solution != null && _socratic && _askStep == null) _beginAsk();
      return;
    }
    if (openExisting && _solution == null && _cardId != null) {
      final existing = await repo.forCard(_cardId!);
      if (existing != null) {
        setState(() {
          _solution = existing;
          _detail = existing.detail;
          _calculator = existing.withCalculator;
          // Eine Rezept-Karte lernt man durch Selbst-Überlegen.
          if (existing.general) _socratic = true;
        });
      }
    }
    if (widget.cardId == null) {
      final saved = await repo.forModule(widget.moduleId);
      setState(() => _saved = saved);
    }
    await _loadTypes();
    if (_solution != null && _socratic && _askStep == null) _beginAsk();
  }

  Future<void> _loadTypes() async {
    final loader = WorkedSolutionScreen.taskTypesLoader ?? (_repo == null ? null : _loadTaskTypes);
    if (loader == null) return;
    try {
      final catalog = await loader(widget.moduleId);
      setState(() => _taskTypes = catalog);
    } catch (_) {
      // Ohne erkannte Aufgabentypen geht es auch.
    }
  }

  static Future<List<String>> _loadTaskTypes(String moduleId) async {
    final catalog = await VisualTaskTypeRepository().load(moduleId);
    return [
      for (final t in catalog?.types ?? const <VisualTaskType>[])
        t.description.isEmpty ? t.title : '${t.title}: ${t.description}',
    ];
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
    final ai = _ai(vision: _image != null);
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
        reference: _reference,
        calculator: _calculator && !_general,
        image: _image,
        general: _general,
      );
      final solution = WorkedSolution.fromAi(
        json,
        id: const Uuid().v4(),
        moduleId: widget.moduleId,
        problem: _problem.text.trim(),
        detail: _detail,
        now: DateTime.now(),
        // Ein Rezept gehört zum Aufgabentyp, nicht zur Beispielaufgabe.
        cardId: _general ? null : _cardId,
        withCalculator: _calculator && !_general,
        general: _general,
      );
      if (solution.steps.isEmpty) {
        throw AiServiceException('Die KI hat keine lesbaren Schritte geliefert.', rawResponse: '$json');
      }
      await _repo?.save(solution);
      setState(() {
        _solution = solution;
        _t = 0;
        _chats.clear();
        _resetSocratic();
      });
      if (_socratic) _beginAsk();
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
    if (_askStep != null) return;
    if (_t >= _playback.length - 1) {
      _stopAuto();
      return;
    }
    // Sokratisch: vor einem neuen Schritt erst selbst überlegen.
    final (current, _) = _playback.at(_t);
    final (next, _) = _playback.at(_t + 1);
    if (_socratic && next != current && _needsAsk(next)) {
      _stopAuto();
      _askFor(next);
      return;
    }
    _go(_t + 1);
  }

  void _prev() {
    _stopAuto();
    if (_askStep != null) {
      setState(() => _askStep = null);
      return;
    }
    _go(_t - 1);
  }

  // ---------------------------------------------------------------------------
  // Sokratisch: selbst überlegen, dann aufdecken
  // ---------------------------------------------------------------------------

  bool _needsAsk(int step) =>
      !_known.contains(step) && !_skipped.contains(step) && (_practiceOnly == null || _practiceOnly!.contains(step));

  void _resetSocratic() {
    _askStep = null;
    _known.clear();
    _skipped.clear();
    _practiceOnly = null;
    _ideaResult = null;
    _praise = null;
    _selected.clear();
    _idea.clear();
  }

  /// Am Anfang bzw. beim Umschalten: den aktuellen Schritt abfragen.
  void _beginAsk() {
    if (_solution == null) return;
    final (step, phase) = _playback.at(_t);
    if (phase == _playback.phasesOf(step).first && _needsAsk(step)) _askFor(step);
  }

  void _askFor(int step) => setState(() {
    _askStep = step;
    _ideaResult = null;
    _selected.clear();
    _idea.clear();
  });

  /// Schritt aufdecken – [known]: selbst richtig vorgeschlagen.
  void _reveal(int step, {required bool known, String praise = ''}) {
    setState(() {
      if (known) {
        _known.add(step);
      } else {
        _skipped.add(step);
      }
      _askStep = null;
      _praise = praise.isEmpty ? null : (step: step, text: praise);
      _t = _playback.startOf(step);
    });
  }

  Future<void> _checkIdea() async {
    final step = _askStep;
    final ai = _ai();
    if (step == null || _idea.text.trim().isEmpty || _ideaBusy) return;
    if (ai == null) {
      setState(() => _error = 'Zum Prüfen deiner Idee braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final solution = _solution!;
    final chunks = _askChunks(step);
    final selection = [
      for (final (i, c) in chunks.indexed)
        if (_selected.contains(i)) c.tex,
    ].join(' ');
    setState(() {
      _ideaBusy = true;
      _error = null;
    });
    try {
      final result = await ai.checkWorkedIdea(
        problem: solution.problem,
        boardSoFar: _boardTexts(step, -1),
        step: solution.steps[step].toMap(),
        selection: selection,
        idea: _idea.text,
        general: solution.general,
      );
      if (!mounted) return;
      if (result.verdict == 'richtig') {
        _reveal(step, known: true, praise: result.feedback.isEmpty ? 'Richtig!' : result.feedback);
      } else {
        setState(() => _ideaResult = result);
      }
    } on AiServiceException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Prüfen fehlgeschlagen: $e');
    } finally {
      setState(() => _ideaBusy = false);
    }
  }

  /// Antippbare Teile der Ausgangszeile des abgefragten Schritts.
  List<({String tex, bool op})> _askChunks(int step) {
    final lines = _playback.board(step, -1);
    if (lines.isEmpty || _solution!.steps[step].kind != WorkKind.math) return const [];
    return LatexChunks.split(lines.last.tex);
  }

  /// Nur die nicht selbst gewussten Schritte noch einmal abfragen.
  void _practiceUnknown() {
    final steps = _solution!.steps;
    final unknown = {
      for (var i = 0; i < steps.length; i++)
        if (!_known.contains(i)) i,
    };
    setState(() {
      _resetSocratic();
      _socratic = true;
      _practiceOnly = unknown;
      _t = 0;
    });
    _beginAsk();
  }

  /// Als Lernkarte speichern: Vorderseite fragt nach dem Vorgehen, Rückseite
  /// sind die Schritte; die Karte öffnet diese Tafel (sokratisch) wieder.
  Future<void> _saveAsCard() async {
    final solution = _solution!;
    final repo = context.read<FlashcardRepository?>();
    if (repo == null) return;
    final now = DateTime.now();
    final title = solution.displayTitle;
    final front = solution.general
        ? 'Wie gehst du vor? ${title.startsWith('Rezept') ? title : 'Rezept: $title'}'
        : 'Wie löst du diese Aufgabe – Schritt für Schritt?\n\n${solution.problem}';
    final back = [
      for (final (i, st) in solution.steps.indexed)
        '${i + 1}. ${st.title}${st.rule == null ? '' : ' – ${st.rule!.name}${st.rule!.formula.isEmpty ? '' : ': \$${st.rule!.formula}\$'}'}',
    ].join('\n');
    final card = Flashcard(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      front: front,
      back: back,
      createdAt: now,
      due: now,
    );
    await repo.saveAll([card]);
    final linked = solution.copyWith(cardId: card.id);
    await _repo?.save(linked);
    if (!mounted) return;
    setState(() => _solution = linked);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Als Lernkarte gespeichert – sie kommt im Daily Quiz; „Vorrechnen“ an der Karte öffnet diese Tafel.',
        ),
      ),
    );
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
    for (final b in _playback.blocks(step, phase))
      ...switch (b) {
        MathBlock(:final lines) => [for (final l in lines) WorkMarkup.toTex(l.tex, colored: false)],
        TextBlock(:final text) => [text],
        FocusBlock(:final marks) => [for (final m in marks) '${m.role}: ${m.text}'],
        TableBlock(:final table) => [table.columns.join(' | '), for (final r in table.rows) r.join(' | ')],
      },
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
          i == parts.length - 1 && s.to.isNotEmpty && p.to.isEmpty && p.kind == WorkKind.math
              ? p.copyWith(to: s.to)
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
      _resetSocratic();
    });
    await _load(openExisting: false);
  }

  /// „Vorhandene Aufgabe wählen“: eine Karte des Fachs übernehmen – schon
  /// vorgerechnet? Dann gleich öffnen.
  Future<void> _pickTask() async {
    final repo = context.read<FlashcardRepository?>();
    final cards = repo == null ? const <Flashcard>[] : await repo.loadModuleCards(widget.moduleId);
    if (!mounted) return;
    final card = await showModalBottomSheet<Flashcard>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TaskPicker(cards: cards),
    );
    if (card == null || !mounted) return;
    setState(() {
      _pickedCard = card;
      _problem.text = card.front;
      _reference = WorkedSolutionScreen.referenceFor(card);
      _image = WorkedSolutionScreen.imageOf(card);
      _cardId = card.id;
      _error = null;
    });
    final existing = await _repo?.forCard(card.id);
    if (existing != null && mounted) {
      setState(() {
        _solution = existing;
        _detail = existing.detail;
        _calculator = existing.withCalculator;
        _t = 0;
        _chats.clear();
        _resetSocratic();
      });
      if (_socratic) _beginAsk();
    }
  }

  void _clearPicked() => setState(() {
    _pickedCard = null;
    _problem.clear();
    _reference = widget.reference;
    _image = widget.image;
    _cardId = widget.cardId;
  });

  // ---------------------------------------------------------------------------
  // Anzeige
  // ---------------------------------------------------------------------------

  /// Sokratisch jeden Schritt selbst gewusst (nichts vorgespult)?
  bool get _selfSolved {
    final steps = _solution?.steps ?? const <WorkStep>[];
    return _socratic && _practiceOnly == null && steps.isNotEmpty && _skipped.isEmpty && _known.length == steps.length;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final solution = _solution;
    // Beim Verlassen: Hat man jeden Schritt selbst gewusst? (Zählt dann nicht
    // als Hilfe – siehe QuestionWithHelp.)
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_selfSolved);
      },
      child: _scaffold(c, solution),
    );
  }

  Widget _scaffold(AppColors c, WorkedSolution? solution) {
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(solution == null ? 'Vorrechnen lassen' : solution.displayTitle, overflow: TextOverflow.ellipsis),
        actions: [
          if (solution != null && solution.cardId == null && context.read<FlashcardRepository?>() != null)
            IconButton(
              key: const ValueKey('worked-save-card'),
              tooltip: 'Als Lernkarte speichern (wie eine Vokabel wiederholen)',
              onPressed: _busy ? null : _saveAsCard,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
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
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            key: const ValueKey('worked-kind'),
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.calculate_outlined, size: 18),
                label: Text('Aufgabe lösen', key: ValueKey('worked-kind-concrete')),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.menu_book_outlined, size: 18),
                label: Text('Rezept (allgemein)', key: ValueKey('worked-kind-general')),
              ),
            ],
            selected: {_general},
            showSelectedIcon: false,
            onSelectionChanged: _busy ? null : (v) => setState(() => _general = v.first),
          ),
          const SizedBox(height: 4),
          Text(
            _general
                ? 'Der Aufgabentyp ohne konkrete Zahlen – die Grundschritte als Rezept, zum Lernen wie Vokabeln. '
                      'Gib einen Aufgabentyp ein, wähle einen erkannten oder eine Beispielaufgabe.'
                : 'Rechnungen, Tabellen, Freitext – die Aufgabe wird Schritt für Schritt gelöst, beginnend mit: '
                      'Was ist gegeben, was ist gesucht?',
            style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35),
          ),
          if (_general && _taskTypes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, t) in _taskTypes.take(12).indexed)
                  ActionChip(
                    key: ValueKey('worked-type-$i'),
                    label: Text(t.split(':').first, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _problem.text = t;
                            _pickedCard = null;
                            _reference = '';
                            _image = null;
                          }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (widget.cardId == null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('worked-pick'),
                  onPressed: _busy ? null : _pickTask,
                  icon: const Icon(Icons.library_books_outlined),
                  label: const Text('Vorhandene Aufgabe wählen'),
                ),
                if (_pickedCard != null)
                  InputChip(
                    key: const ValueKey('worked-picked'),
                    avatar: const Icon(Icons.task_alt, size: 18),
                    label: Text('Aus deinen Aufgaben (${_pickedCard!.type.label})'),
                    onDeleted: _busy ? null : _clearPicked,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _pickedCard == null
                  ? 'Oder unten selbst eine Aufgabe eintippen.'
                  : 'Die Musterlösung der Aufgabe bekommt die KI mit – sie rechnet danach vor.',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            ),
            const SizedBox(height: 12),
          ],
          if (_image != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_image!, height: 160, fit: BoxFit.contain),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            key: const ValueKey('worked-problem'),
            controller: _problem,
            minLines: 2,
            maxLines: 8,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: _general ? 'Aufgabentyp oder Beispielaufgabe' : 'Aufgabe',
              hintText: _general
                  ? 'z.B. DGL mit Trennung der Variablen, Partialbruchzerlegung, Werkstoffe in einer Tabelle vergleichen'
                  : 'z.B. Löse ln((48x + 6)²) = 10 nach x auf  oder  Berechne ∫ 2x(x² + 1)³ dx',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_problem.text.contains(r'$')) ...[
            const SizedBox(height: 8),
            MathText(_problem.text, style: TextStyle(color: c.inkMuted)),
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
            key: const ValueKey('worked-socratic'),
            contentPadding: EdgeInsets.zero,
            value: _socratic,
            onChanged: _busy ? null : (v) => setState(() => _socratic = v),
            title: const Text('Selbst überlegen (sokratisch)'),
            subtitle: const Text(
              'Vor jedem Schritt markierst du, woran du arbeiten würdest, und sagst, was du tun würdest – die KI '
              'sagt, ob die Idee stimmt. Weißt du es nicht, spulst du vor.',
            ),
          ),
          if (!_general)
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
            onPressed: _busy || (_problem.text.trim().isEmpty && _image == null) ? null : _start,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_lesson_outlined),
            label: Text(_busy ? 'Die KI rechnet vor …' : (_general ? 'Rezept erklären' : 'Vorrechnen')),
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
                subtitle: Text('${s.general ? 'Rezept · ' : ''}${s.detail.label} · ${s.steps.length} Schritte'),
                onTap: () {
                  setState(() {
                    _solution = s;
                    _t = 0;
                    _chats.clear();
                    _resetSocratic();
                  });
                  if (_socratic) _beginAsk();
                },
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
    final ask = _askStep;
    final (shownStep, shownPhase) = playback.at(_t);
    final step = ask ?? shownStep;
    final phase = ask == null ? shownPhase : -1;
    final s = solution.steps[step];
    final calc = solution.withCalculator && ask == null ? s.calc : null;
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
                _modeToggle(c),
                const SizedBox(height: 10),
                _progress(c, solution, step),
                const SizedBox(height: 10),
                SizedBox(
                  height: wide ? 380 : 260,
                  child: WorkBoard(blocks: playback.blocks(step, phase)),
                ),
                const SizedBox(height: 10),
                if (ask != null) ...[
                  _askPanel(c, ask),
                ] else ...[
                  if (_praise case final p? when p.step == step)
                    Container(
                      key: const ValueKey('worked-praise'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: c.goodSoft, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: c.good, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: MathText(p.text, style: const TextStyle(fontSize: 13.5, height: 1.35))),
                        ],
                      ),
                    ),
                  _explanation(c, s, step, phase),
                  const SizedBox(height: 8),
                  _controls(c, step),
                ],
                if (_error != null) _errorBox(c),
                if (_atEnd && ask == null && _socratic) _socraticSummary(c, solution),
                if (_atEnd && ask == null && solution.answer.isNotEmpty)
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

  Widget _modeToggle(AppColors c) => SegmentedButton<bool>(
    key: const ValueKey('worked-mode'),
    segments: const [
      ButtonSegment(
        value: false,
        icon: Icon(Icons.slideshow_outlined, size: 18),
        label: Text('Vorrechnen', key: ValueKey('worked-mode-watch')),
      ),
      ButtonSegment(
        value: true,
        icon: Icon(Icons.psychology_outlined, size: 18),
        label: Text('Selbst überlegen', key: ValueKey('worked-mode-socratic')),
      ),
    ],
    selected: {_socratic},
    showSelectedIcon: false,
    onSelectionChanged: (v) {
      _stopAuto();
      setState(() {
        _socratic = v.first;
        if (!_socratic) _askStep = null;
      });
      if (_socratic) _beginAsk();
    },
  );

  /// Sokratisch: Teile der Tafel markieren und sagen, was man tun würde.
  Widget _askPanel(AppColors c, int step) {
    final chunks = _askChunks(step);
    final s = _solution!.steps[step];
    final result = _ideaResult;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final question = switch (s.kind) {
      WorkKind.focus => 'Was ist hier gegeben, was ist gesucht – und was verlangt die Aufgabe genau?',
      WorkKind.text => 'Was gehört als Nächstes in die Antwort?',
      WorkKind.table => 'Was trägst du als Nächstes in die Tabelle ein – und woher weißt du es?',
      WorkKind.math =>
        chunks.isEmpty
            ? 'Was machst du als Nächstes?'
            : 'Tipp an, woran du arbeiten würdest, und schreib, was du damit machst.',
    };
    return Container(
      key: const ValueKey('worked-ask-panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.accent.withAlpha(120), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dein Zug – Schritt ${step + 1}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(question, style: TextStyle(fontSize: 13.5, color: c.inkMuted, height: 1.35)),
          if (chunks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 4,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (i, chunk) in chunks.indexed)
                  InkWell(
                    key: ValueKey('worked-chunk-$i'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _selected.contains(i) ? _selected.remove(i) : _selected.add(i)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: _selected.contains(i) ? c.accent.withAlpha(dark ? 90 : 55) : c.surfaceAlt,
                        border: Border.all(color: _selected.contains(i) ? c.accent : c.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Math.tex(
                        chunk.tex,
                        textStyle: TextStyle(fontSize: 20, color: c.ink),
                        onErrorFallback: (_) => Text(chunk.tex),
                      ),
                    ),
                  ),
                TextButton(
                  key: const ValueKey('worked-chunk-all'),
                  onPressed: () => setState(() {
                    if (_selected.length == chunks.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll([for (var i = 0; i < chunks.length; i++) i]);
                    }
                  }),
                  child: Text(_selected.length == chunks.length ? 'Nichts' : 'Ganze Zeile'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('worked-idea'),
            controller: _idea,
            minLines: 1,
            maxLines: 4,
            enabled: !_ideaBusy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _checkIdea(),
            decoration: InputDecoration(
              hintText: switch (s.kind) {
                WorkKind.math => 'z.B. „y′ wird zu dy/dx“ oder „nach y und x sortieren“',
                WorkKind.focus => 'z.B. „gesucht ist die Geschwindigkeit nach 3 s“',
                _ => 'deine Idee …',
              },
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('worked-idea-result'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: result.verdict == 'teilweise' ? c.warnSoft : c.dangerSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.verdict == 'teilweise' ? 'Fast – die Richtung stimmt' : 'Noch nicht',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (result.feedback.isNotEmpty)
                    MathText(result.feedback, style: const TextStyle(fontSize: 13.5, height: 1.35)),
                  if (result.hint.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: MathText('Tipp: ${result.hint}', style: const TextStyle(fontSize: 13, height: 1.35)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                key: const ValueKey('worked-prev'),
                onPressed: _prev,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Zurück'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('worked-idea-check'),
                  onPressed: _ideaBusy ? null : _checkIdea,
                  icon: _ideaBusy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.task_alt),
                  label: const Text('Prüfen'),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Weiß ich nicht – Schritt zeigen',
                child: OutlinedButton.icon(
                  key: const ValueKey('worked-idea-skip'),
                  onPressed: _ideaBusy ? null : () => _reveal(step, known: false),
                  icon: const Icon(Icons.fast_forward),
                  label: const Text('Vorspulen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _socraticSummary(AppColors c, WorkedSolution solution) {
    final asked = _practiceOnly ?? {for (var i = 0; i < solution.steps.length; i++) i};
    final known = _known.intersection(asked).length;
    final missing = asked.length - known;
    return Container(
      key: const ValueKey('worked-socratic-summary'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: missing == 0 ? c.goodSoft : c.accentSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selbst gewusst: $known von ${asked.length} Schritten',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (missing > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Nicht gewusst: ${[for (final i in asked)
                if (!_known.contains(i)) solution.steps[i].title].join(' · ')}',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const ValueKey('worked-practice-unknown'),
              onPressed: _practiceUnknown,
              icon: const Icon(Icons.replay),
              label: const Text('Nur die nicht gewussten Schritte üben'),
            ),
          ],
        ],
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
              child: Text(
                '${solution.general ? 'Rezept · ' : ''}${solution.detail.label}',
                style: TextStyle(fontSize: 11, color: c.accentOnSoft),
              ),
            ),
            const Spacer(),
            PopupMenuButton<int>(
              key: const ValueKey('worked-jump'),
              tooltip: 'Zu einem Schritt springen',
              icon: const Icon(Icons.format_list_numbered, size: 20),
              onSelected: (i) {
                _stopAuto();
                if (_socratic && _needsAsk(i)) {
                  setState(() => _t = _playback.startOf(i));
                  _askFor(i);
                  return;
                }
                setState(() => _askStep = null);
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
      2 => s.kind == WorkKind.math ? 'Neue Zeile.' : 'Neu an der Tafel (grün).',
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

/// Auswahl einer vorhandenen Aufgabe des Fachs – Rechenwege zuerst, mit Suche.
class _TaskPicker extends StatefulWidget {
  const _TaskPicker({required this.cards});

  final List<Flashcard> cards;

  @override
  State<_TaskPicker> createState() => _TaskPickerState();
}

class _TaskPickerState extends State<_TaskPicker> {
  final _search = TextEditingController();
  late bool _onlySteps = widget.cards.any((c) => c.type == QuestionType.steps);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final query = _search.text.trim().toLowerCase();
    final cards =
        [
          for (final card in widget.cards)
            if ((!_onlySteps || card.type == QuestionType.steps) &&
                card.front.trim().isNotEmpty &&
                (query.isEmpty || card.front.toLowerCase().contains(query) || card.back.toLowerCase().contains(query)))
              card,
        ]..sort((a, b) {
          final sa = a.type == QuestionType.steps ? 0 : 1, sb = b.type == QuestionType.steps ? 0 : 1;
          if (sa != sb) return sa.compareTo(sb);
          return b.createdAt.compareTo(a.createdAt);
        });
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Aufgabe zum Vorrechnen wählen', style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              key: const ValueKey('worked-pick-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Suchen …',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: CheckboxListTile(
              key: const ValueKey('worked-pick-only-steps'),
              value: _onlySteps,
              onChanged: (v) => setState(() => _onlySteps = v ?? false),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Nur Rechenweg-Aufgaben'),
            ),
          ),
          Expanded(
            child: cards.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.cards.isEmpty
                            ? 'In diesem Fach gibt es noch keine Aufgaben.'
                            : 'Keine passende Aufgabe gefunden.',
                        key: const ValueKey('worked-pick-empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.inkMuted),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: cards.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final card = cards[i];
                      return ListTile(
                        key: ValueKey('worked-pick-$i'),
                        leading: Icon(
                          card.type == QuestionType.steps ? Icons.functions : Icons.style_outlined,
                          color: c.accent,
                        ),
                        title: MathText(card.front, maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: Text(card.type.label, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                        trailing: card.imageBase64 == null ? null : const Icon(Icons.image_outlined, size: 18),
                        onTap: () => Navigator.of(context).pop(card),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
