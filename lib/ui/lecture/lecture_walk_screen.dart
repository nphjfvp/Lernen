import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/flashcard.dart';
import '../../models/lecture_walk.dart';
import '../../models/material_item.dart';
import '../../models/worked_solution.dart';
import '../../repositories/lecture_walk_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/lecture_board_window.dart';
import '../../services/material_file_store.dart';
import '../../services/pdf_service.dart';
import '../../theme/app_colors.dart';
import '../visual/visual_from_card.dart';
import '../widgets/math_text.dart';
import '../widgets/safe_set_state.dart';
import 'lecture_board.dart';

/// Öffnet „Vorlesung mit Aufgabe“ für eine PDF.
Future<void> openLectureWalk(BuildContext context, MaterialItem material) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LectureWalkScreen(material: material)));

/// Vorlesung mit Aufgabe: Beim Öffnen geht die KI die ganze Vorlesung durch
/// und bestimmt die vermittelten Konzepte – jedes mit allen Seiten, auf denen
/// es erklärt wird – und stellt zu jedem eine vollständige Prüfungsaufgabe
/// (nicht aus der Vorlesung). Links (am Handy oben) liest man die Vorlesung,
/// rechts (unten) steht die Tafel wie bei „Vorrechnen“: Nach jeder Seite, die
/// ein Konzept weiter erklärt, geht es mit dessen Aufgabe weiter. Neue
/// Formeln kommen an die Tafel und in die Formelsammlung. Am PC lässt sich die
/// Tafel in ein eigenes Fenster ziehen. Einmal durch: die Aufgaben selbst
/// lösen – bei einem Fehler geht es zur Seite mit dem Haken.
class LectureWalkScreen extends StatefulWidget {
  const LectureWalkScreen({super.key, required this.material, this.repository});

  final MaterialItem material;
  final LectureWalkRepository? repository;

  /// Test-Hooks statt PDF und OpenRouter.
  static Future<({Uint8List? bytes, List<String> pageTexts})> Function(MaterialItem material)? loadHook;
  static AiService? Function()? aiFactory;

  @override
  State<LectureWalkScreen> createState() => _LectureWalkScreenState();
}

class _LectureWalkScreenState extends State<LectureWalkScreen> with SafeSetState<LectureWalkScreen> {
  late final LectureWalkRepository _repo = widget.repository ?? LectureWalkRepository();
  final _pdf = PdfViewerController();
  LectureWalk? _walk;
  Uint8List? _bytes;
  List<String> _pageTexts = const [];
  bool _loading = true;
  bool _preparing = false;
  bool _busy = false;
  String _busyText = '';
  String? _error;
  String _coach = '';
  int _freshFormulas = 0;
  final _chat = <({bool user, String text})>[];

  /// Schritt, an dem es beim Selbstlösen hakte (Tafel springt dorthin).
  int? _focus;

  /// Seite, zu der gerade gesprungen wird (die Hervorhebung bleibt dann).
  int? _jumpTarget;
  LectureBoardWindow? _window;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    unawaited(_window?.close());
    _pdf.dispose();
    super.dispose();
  }

  AiService? _ai() {
    final hook = LectureWalkScreen.aiFactory;
    if (hook != null) return hook();
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings == null || !settings.hasApiKey) return null;
    return AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
  }

  /// Zustand ändern und an das Tafel-Fenster schicken.
  void _update(VoidCallback fn) {
    setState(fn);
    _window?.send(_boardState);
  }

  Future<void> _save() async {
    final walk = _walk;
    if (walk != null) await _repo.save(walk);
  }

  Future<void> _init() async {
    try {
      final hook = LectureWalkScreen.loadHook;
      final Uint8List? bytes;
      final List<String> texts;
      if (hook != null) {
        final loaded = await hook(widget.material);
        bytes = loaded.bytes;
        texts = loaded.pageTexts;
      } else {
        bytes = await MaterialFileStore.load(
          filePath: widget.material.filePath,
          fileBytesBase64: widget.material.fileBytesBase64,
        );
        texts = bytes == null ? const [] : PdfService().extractPageTexts(bytes);
      }
      if (texts.isEmpty) throw StateError('Die PDF konnte nicht gelesen werden.');
      var walk = await _repo.load(widget.material.id);
      if (walk == null || walk.pageCount != texts.length) {
        walk = LectureWalk(
          materialId: widget.material.id,
          moduleId: widget.material.moduleId,
          title: widget.material.fileName,
          pageCount: texts.length,
        );
      }
      _update(() {
        _bytes = bytes;
        _pageTexts = texts;
        _walk = walk;
        _loading = false;
        if (walk!.prepared) {
          _coach = walk.current >= 0
              ? 'Weiter mit „${walk.concepts[walk.current].title}“ – du warst auf Seite ${walk.page}.'
              : 'Alles vorbereitet – lies los.';
        }
      });
      await _prepare();
    } catch (e) {
      _update(() {
        _loading = false;
        _error = e is AiServiceException ? e.message : '$e';
      });
    }
  }

  /// Vorab: Konzepte der ganzen Vorlesung, dann zu jedem die Aufgabe (in
  /// Lesereihenfolge). Lesen geht schon währenddessen.
  Future<void> _prepare() async {
    if (_preparing || _walk == null || _walk!.prepared) return;
    final ai = _ai();
    if (ai == null) {
      _update(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    _preparing = true;
    try {
      if (_walk!.concepts.isEmpty) {
        _update(() {
          _busy = true;
          _busyText = 'Die KI geht die ganze Vorlesung durch: Welche Konzepte sollen hier vermittelt werden?';
          _error = null;
        });
        final concepts = await ai.lectureConcepts(title: _walk!.title, pageTexts: _pageTexts);
        _walk = _walk!.copyWith(concepts: concepts).withPage(_walk!.page);
        await _save();
        _update(() {
          _coach =
              'Diese Vorlesung vermittelt ${concepts.length} ${concepts.length == 1 ? 'Konzept' : 'Konzepte'}: '
              '${concepts.map((c) => '„${c.title}“').join(', ')}. Zu jedem bekommst du eine vollständige Aufgabe – '
              'die lösen wir gemeinsam, während du die Seiten dazu liest.';
        });
      }
      final count = _walk!.concepts.length;
      for (var i = 0; i < count; i++) {
        if (_walk!.tasks.containsKey(i)) continue;
        if (!mounted) return;
        final walk = _walk!;
        final concept = walk.concepts[i];
        _update(() {
          _busy = true;
          _busyText = 'Aufgabe ${i + 1} von $count wird vorbereitet: „${concept.title}“ …';
          _error = null;
        });
        final task = await ai.lectureConceptTask(
          lectureTitle: walk.title,
          concept: concept,
          pageTexts: _pageTexts,
          otherConcepts: [
            for (final (j, c) in walk.concepts.indexed)
              if (j != i) c.title,
          ],
          known: walk.formulas,
        );
        final current = _walk!;
        final before = current.formulas.length;
        var next = current.copyWith(tasks: {...current.tasks, i: task}).withRevealedFormulas();
        if (next.current < 0 || !next.tasks.containsKey(next.current)) {
          if (next.conceptsOn(next.page).contains(i) || next.current < 0) next = next.copyWith(current: i);
        }
        _walk = next;
        await _save();
        _update(() => _freshFormulas = next.formulas.length - before);
      }
      _update(() {
        if (_coach.isEmpty || _coach.startsWith('Diese Vorlesung vermittelt')) {
          _coach =
              '${_coach.isEmpty ? '' : '$_coach '}Alles vorbereitet – lies los. Sobald eine Seite ein Konzept '
              'erklärt, rechnen wir an der Tafel weiter.';
        }
      });
    } catch (e) {
      _update(() => _error = e is AiServiceException ? e.message : 'Vorbereiten fehlgeschlagen: $e');
    } finally {
      _preparing = false;
      _update(() => _busy = false);
    }
  }

  /// Neue Seite: weiter mit der Aufgabe des passenden Konzepts, neue Formeln an
  /// die Tafel.
  void _onPage(int page) {
    final old = _walk;
    if (old == null || page == old.page) return;
    final keepFocus = _jumpTarget == page;
    _jumpTarget = null;
    var walk = old.withPage(page);
    // Beim Sprung zum Haken bleibt dessen Konzept an der Tafel.
    if (keepFocus) walk = walk.copyWith(current: old.current);
    var coach = _coach;
    if (!keepFocus) {
      final advanced = [
        for (var i = 0; i < walk.concepts.length; i++)
          if (walk.revealedCount(i) > old.revealedCount(i)) i,
      ];
      if (advanced.isNotEmpty) {
        final i = advanced.first;
        final task = walk.tasks[i]!;
        final first = task.steps[old.revealedCount(i)].step;
        final say = first.say.trim().isNotEmpty ? first.say.trim() : first.title;
        coach = 'Okay, lass uns mit unserer Aufgabe zu „${walk.concepts[i].title}“ weitermachen: $say';
        if (walk.revealedCount(i) == task.steps.length) {
          coach += task.answer.isNotEmpty ? ' Damit ist sie gelöst: ${task.answer}' : ' Damit ist sie gelöst.';
        }
      } else if (walk.current != old.current && walk.current >= 0) {
        final c = walk.concepts[walk.current];
        coach = walk.tasks.containsKey(walk.current)
            ? 'Jetzt geht es um „${c.title}“ – unsere Aufgabe dazu steht an der Tafel.'
            : 'Die Aufgabe zu „${c.title}“ wird noch vorbereitet …';
      }
      if (walk.finished && !old.finished) {
        coach +=
            ' Du bist einmal durch die Vorlesung! Jetzt kannst du die Aufgaben selbst lösen – oben '
            '„Selbst lösen“.';
      }
    }
    _walk = walk;
    _update(() {
      _coach = coach;
      _freshFormulas = walk.formulas.length - old.formulas.length;
      if (!keepFocus) _focus = null;
    });
    unawaited(_save());
  }

  void _goTo(int page) {
    final walk = _walk;
    if (walk == null) return;
    final target = page.clamp(1, walk.pageCount);
    if (_bytes != null) {
      _pdf.jumpToPage(target);
    } else {
      _onPage(target);
    }
  }

  void _select(int concept) {
    final walk = _walk;
    if (walk == null || concept == walk.current || concept < 0 || concept >= walk.concepts.length) return;
    _walk = walk.copyWith(current: concept);
    _update(() {
      _focus = null;
      _coach = '„${walk.concepts[concept].title}“ – ${walk.concepts[concept].pagesLabel}.';
    });
    unawaited(_save());
  }

  void _refined(int concept, int step, int count, WorkedSolution updated) {
    final walk = _walk;
    final task = walk?.tasks[concept];
    if (walk == null || task == null || step + count > updated.steps.length) return;
    final next = task.withRefined(step, updated.steps.sublist(step, step + count));
    _walk = walk.copyWith(tasks: {...walk.tasks, concept: next});
    _update(() {});
    unawaited(_save());
  }

  List<String> _boardLines(LectureTask task, int count) => [
    for (final s in task.steps.take(count))
      if (s.step.to.isNotEmpty) s.step.to else if (s.step.content.isNotEmpty) s.step.content,
  ];

  Future<void> _ask(String question, {int? formula}) async {
    final walk = _walk;
    final ai = _ai();
    if (walk == null) return;
    if (ai == null) {
      _update(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final concept = walk.current;
    final task = concept >= 0 ? walk.tasks[concept] : null;
    final history = [..._chat];
    _update(() {
      _chat.add((user: true, text: question));
      _busy = true;
      _busyText = 'Die KI antwortet …';
      _error = null;
    });
    try {
      final answer = await ai.askLectureWalk(
        concept: concept >= 0 ? walk.concepts[concept].title : walk.title,
        problem: task?.problem ?? '',
        boardSoFar: task == null ? const [] : _boardLines(task, walk.revealedCount(concept)),
        pageText: walk.page - 1 < _pageTexts.length ? _pageTexts[walk.page - 1] : '',
        formula: formula != null && formula < walk.formulas.length ? walk.formulas[formula] : null,
        history: history,
        question: question,
      );
      _update(() => _chat.add((user: false, text: answer)));
    } catch (e) {
      _update(() => _error = e is AiServiceException ? e.message : 'Frage fehlgeschlagen: $e');
    } finally {
      _update(() => _busy = _preparing);
    }
  }

  LectureBoardState get _boardState {
    final walk = _walk;
    if (walk == null) return LectureBoardState(busy: _busy || _loading, busyText: _busyText, error: _error);
    final concept = walk.current;
    final task = concept >= 0 ? walk.tasks[concept] : null;
    return LectureBoardState(
      concepts: [
        for (final (i, c) in walk.concepts.indexed)
          LectureBoardConcept(
            title: c.title,
            pages: c.pagesLabel,
            revealed: walk.revealedCount(i),
            total: walk.tasks[i]?.steps.length ?? 0,
          ),
      ],
      current: concept,
      solution: task?.toWorked(
        id: 'lecture-${walk.materialId}-$concept',
        moduleId: walk.moduleId,
        fallbackTitle: walk.concepts[concept].title,
      ),
      revealed: concept >= 0 ? walk.revealedCount(concept) : 0,
      focus: _focus,
      pageLabel: 'Seite ${walk.page}/${walk.pageCount}',
      formulas: walk.formulas,
      freshFormulas: _freshFormulas,
      coach: _coach,
      chat: [..._chat],
      busy: _busy,
      busyText: _busyText,
      error: _error,
    );
  }

  Future<void> _detach() async {
    final settings = context.read<SettingsRepository?>()?.settings;
    final window = await LectureBoardWindow.open(
      settings: settings == null
          ? const {}
          : {
              'openRouterApiKey': settings.openRouterApiKey,
              'questionModelId': settings.questionModelId,
              'visionModelId': settings.visionModelId,
            },
      onAction: (action) {
        switch (action['type']) {
          case 'ask':
            final formula = action['formula'];
            unawaited(_ask('${action['text'] ?? ''}', formula: formula is int ? formula : null));
          case 'select':
            final concept = action['concept'];
            if (concept is int) _select(concept);
          case 'refined':
            final solution = WorkedSolution.fromMap(action['solution']);
            final concept = action['concept'];
            final step = action['step'];
            final count = action['count'];
            if (solution != null && concept is int && step is int && count is int) {
              _refined(concept, step, count, solution);
            }
        }
      },
      onClosed: () {
        if (mounted) setState(() => _window = null);
      },
    );
    if (window == null || !mounted) return;
    setState(() => _window = window);
    window.send(_boardState);
  }

  Future<void> _attach() async {
    final window = _window;
    setState(() => _window = null);
    await window?.close();
  }

  // ---------------------------------------------------------------------------
  // Selbst lösen
  // ---------------------------------------------------------------------------

  Future<void> _selfSolve() async {
    final walk = _walk;
    final ai = _ai();
    if (walk == null) return;
    if (ai == null) {
      _update(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final result = await Navigator.of(context).push<({int concept, LectureAttempt attempt})>(
      MaterialPageRoute(
        builder: (_) => _SelfSolveScreen(
          walk: walk,
          ai: ai,
          pageTexts: _pageTexts,
          onSaved: (updated) {
            _walk = updated;
            unawaited(_save());
          },
        ),
      ),
    );
    if (result == null || !mounted) return;
    _showHook(result.concept, result.attempt);
  }

  /// Zur Seite mit dem Haken springen und dort genau erklären.
  void _showHook(int concept, LectureAttempt attempt) {
    final walk = _walk;
    final step = attempt.step;
    final task = walk?.tasks[concept];
    if (walk == null || task == null || step == null) return;
    final page = task.steps[step].page;
    _walk = walk.copyWith(current: concept);
    _update(() {
      _focus = step;
      _coach =
          'Hier hakt es – auf Seite $page wird genau das erklärt. ${attempt.feedback} Die Tafel zeigt unsere Lösung '
          'bis zu diesem Schritt; frag gern nach (am Schritt oder unten in der Formelsammlung).';
      if (attempt.explain.isNotEmpty) _chat.add((user: false, text: attempt.explain));
    });
    if (page != walk.page) {
      _jumpTarget = page;
      _goTo(page);
    }
  }

  void _visual(int concept, int step) {
    final walk = _walk;
    final task = walk?.tasks[concept];
    if (walk == null || task == null) return;
    final s = task.steps[step];
    final attempt = walk.attempts[concept];
    final now = DateTime.now();
    final card = Flashcard(
      id: 'lecture-${walk.materialId}-$concept-$step',
      moduleId: walk.moduleId,
      front: '${task.problem}\n\nSchritt, an dem es hakt: ${s.step.title}',
      back: [
        if (attempt != null && attempt.explain.isNotEmpty) attempt.explain,
        [for (final t in task.steps) t.step.to.isNotEmpty ? t.step.to : t.step.title].join('\n'),
      ].join('\n\n'),
      createdAt: now,
      due: now,
      sourceMaterialId: walk.materialId,
      sourcePage: s.page,
    );
    unawaited(openVisualForCard(context, card));
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final walk = _walk;
    final board = LectureBoardView(
      state: _boardState,
      onAsk: (q, {formula}) => unawaited(_ask(q, formula: formula)),
      onSelect: _select,
      onRefined: _refined,
      onDetach: LectureBoardWindow.supported && _window == null ? _detach : null,
      actions: [
        if (walk != null && _focus != null && walk.current >= 0)
          OutlinedButton.icon(
            key: const ValueKey('lecture-visual'),
            onPressed: () => _visual(walk.current, _focus!),
            icon: const Icon(Icons.animation, size: 18),
            label: const Text('Visuell erklären'),
          ),
      ],
    );
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(widget.material.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (walk != null && walk.finished && walk.tasks.isNotEmpty)
            TextButton.icon(
              key: const ValueKey('lecture-self-solve'),
              onPressed: _selfSolve,
              icon: const Icon(Icons.edit_note),
              label: const Text('Selbst lösen'),
            ),
          if (walk != null && walk.concepts.isNotEmpty)
            PopupMenuButton<int>(
              key: const ValueKey('lecture-concepts-menu'),
              tooltip: 'Konzepte',
              icon: const Icon(Icons.list_alt),
              onSelected: (i) {
                _select(i);
                _goTo(walk.concepts[i].from);
              },
              itemBuilder: (_) => [
                for (final (i, t) in walk.concepts.indexed)
                  PopupMenuItem(value: i, child: Text('${i + 1}. ${t.title} (${t.pagesLabel})')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : walk == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error ?? 'Die Vorlesung konnte nicht geladen werden.', textAlign: TextAlign.center),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final pages = _pagePane(c, walk);
                if (_window != null) {
                  return Column(
                    children: [
                      MaterialBanner(
                        key: const ValueKey('lecture-detached'),
                        content: const Text('Die Tafel ist im eigenen Fenster – zieh es auf den zweiten Bildschirm.'),
                        actions: [TextButton(onPressed: _attach, child: const Text('Zurückholen'))],
                      ),
                      Expanded(child: pages),
                    ],
                  );
                }
                if (constraints.maxWidth >= 1000) {
                  return Row(
                    children: [
                      Expanded(child: pages),
                      VerticalDivider(width: 1, color: c.border),
                      SizedBox(width: (constraints.maxWidth * 0.5).clamp(420.0, 900.0), child: board),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(flex: 4, child: pages),
                    Divider(height: 1, color: c.border),
                    Expanded(flex: 6, child: board),
                  ],
                );
              },
            ),
    );
  }

  Widget _pagePane(AppColors c, LectureWalk walk) {
    final on = walk.conceptsOn(walk.page);
    final bytes = _bytes;
    return Column(
      children: [
        Expanded(
          child: bytes != null
              ? SfPdfViewer.memory(
                  bytes,
                  controller: _pdf,
                  initialPageNumber: walk.page,
                  pageLayoutMode: PdfPageLayoutMode.single,
                  onPageChanged: (d) => _onPage(d.newPageNumber),
                )
              : SingleChildScrollView(
                  key: const ValueKey('lecture-page-text'),
                  padding: const EdgeInsets.all(20),
                  child: Text(walk.page - 1 < _pageTexts.length ? _pageTexts[walk.page - 1] : ''),
                ),
        ),
        Material(
          color: c.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('lecture-prev'),
                  tooltip: 'Vorige Seite',
                  onPressed: walk.page > 1 ? () => _goTo(walk.page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    on.isEmpty
                        ? 'Seite ${walk.page}/${walk.pageCount}'
                        : 'Seite ${walk.page}/${walk.pageCount} · ${on.map((i) => walk.concepts[i].title).join(' · ')}',
                    key: const ValueKey('lecture-page-label'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: const ValueKey('lecture-next'),
                  tooltip: 'Nächste Seite',
                  onPressed: walk.page < walk.pageCount ? () => _goTo(walk.page + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Die Aufgaben der Vorlesung selbst lösen; bei einem Fehler zurück zur Seite
/// mit dem Haken.
class _SelfSolveScreen extends StatefulWidget {
  const _SelfSolveScreen({required this.walk, required this.ai, required this.pageTexts, required this.onSaved});

  final LectureWalk walk;
  final AiService ai;
  final List<String> pageTexts;
  final ValueChanged<LectureWalk> onSaved;

  @override
  State<_SelfSolveScreen> createState() => _SelfSolveScreenState();
}

class _SelfSolveScreenState extends State<_SelfSolveScreen> with SafeSetState<_SelfSolveScreen> {
  late LectureWalk _walk = widget.walk;
  int? _concept;
  final _answer = TextEditingController();
  bool _busy = false;
  String? _error;
  LectureAttempt? _result;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _open(int concept) async {
    setState(() {
      _concept = concept;
      _result = null;
      _error = null;
      _answer.clear();
    });
    if (_walk.tasks.containsKey(concept)) return;
    setState(() => _busy = true);
    try {
      final task = await widget.ai.lectureConceptTask(
        lectureTitle: _walk.title,
        concept: _walk.concepts[concept],
        pageTexts: widget.pageTexts,
        known: _walk.formulas,
      );
      _walk = _walk.copyWith(tasks: {..._walk.tasks, concept: task}).withRevealedFormulas();
      widget.onSaved(_walk);
    } catch (e) {
      _error = e is AiServiceException ? e.message : '$e';
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final concept = _concept;
    final task = concept == null ? null : _walk.tasks[concept];
    if (concept == null || task == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.ai.checkLectureAttempt(task: task, attempt: _answer.text);
      _walk = _walk.copyWith(attempts: {..._walk.attempts, concept: result});
      widget.onSaved(_walk);
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = e is AiServiceException ? e.message : '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final concept = _concept;
    final task = concept == null ? null : _walk.tasks[concept];
    final result = _result;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(concept == null ? 'Selbst lösen' : _walk.concepts[concept].title),
        leading: concept == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _concept = null)),
      ),
      body: concept == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Du hast die Vorlesung einmal durch. Jetzt löst du jede Aufgabe ohne Hilfe von vorne bis hinten – '
                  'klappt es nicht, weiß die App, wo der Haken ist, und springt zur passenden Seite.',
                  style: TextStyle(color: c.inkMuted, height: 1.4),
                ),
                const SizedBox(height: 12),
                for (final (i, t) in _walk.concepts.indexed)
                  ListTile(
                    key: ValueKey('self-concept-$i'),
                    leading: Icon(
                      _walk.attempts[i]?.solved == true
                          ? Icons.check_circle
                          : _walk.attempts[i] != null
                          ? Icons.error_outline
                          : Icons.radio_button_unchecked,
                      color: _walk.attempts[i]?.solved == true
                          ? c.good
                          : _walk.attempts[i] != null
                          ? c.warn
                          : c.inkMuted,
                    ),
                    title: Text(t.title),
                    subtitle: Text(t.goal.isEmpty ? t.pagesLabel : '${t.goal} · ${t.pagesLabel}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(i),
                  ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (task != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
                    child: MathText(task.problem, style: const TextStyle(height: 1.45)),
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('self-answer'),
                  controller: _answer,
                  minLines: 6,
                  maxLines: 16,
                  enabled: task != null && !_busy,
                  decoration: const InputDecoration(
                    hintText:
                        'Dein Lösungsweg, Zeile für Zeile – Formeln gern als LaTeX oder einfach so (x^2, sqrt(x), '
                        'integral …).',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('self-check'),
                  onPressed: task == null || _busy ? null : _check,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fact_check_outlined),
                  label: const Text('Prüfen'),
                ),
                if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(color: c.danger))],
                if (result != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    key: const ValueKey('self-result'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: result.solved ? c.goodSoft : c.warnSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.solved ? 'Sehr gut – geschafft!' : 'Noch nicht ganz.',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        if (result.feedback.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          MathText(result.feedback, style: const TextStyle(height: 1.4)),
                        ],
                        if (!result.solved && result.step != null && task != null) ...[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            key: const ValueKey('self-jump'),
                            onPressed: () => Navigator.of(context).pop((concept: concept, attempt: result)),
                            icon: const Icon(Icons.menu_book_outlined),
                            label: Text('Zu Seite ${task.steps[result.step!].page} – dort genau erklären'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
