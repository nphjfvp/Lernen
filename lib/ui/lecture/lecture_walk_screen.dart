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
import '../visual/worked_solution_screen.dart';
import '../widgets/math_text.dart';
import '../widgets/safe_set_state.dart';
import 'lecture_board.dart';

/// Öffnet „Vorlesung mit Aufgabe“ für eine PDF.
Future<void> openLectureWalk(BuildContext context, MaterialItem material) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LectureWalkScreen(material: material)));

/// Vorlesung mit Aufgabe: links (am Handy oben) die Vorlesung Seite für
/// Seite, rechts (unten) die Tafel. Zu jedem Thema gibt es am Anfang eine
/// schwere Aufgabe; nach jeder Seite, die das Thema weiter erklärt, geht es
/// damit weiter („Okay, lass uns mit unserer Aufgabe weitermachen“). Neue
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
  bool _busy = false;
  String _busyText = '';
  String? _error;
  String _coach = '';
  int _freshFormulas = 0;
  final _chat = <({bool user, String text})>[];

  /// Schritt, an dem es beim Selbstlösen hakte (Tafel zeigt bis dorthin).
  int? _highlight;
  int? _highlightTopic;

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
      });
      if (walk.topics.isEmpty) await _detectTopics();
      await _ensureTask(announce: true);
    } catch (e) {
      _update(() {
        _loading = false;
        _error = e is AiServiceException ? e.message : '$e';
      });
    }
  }

  Future<void> _save() async {
    final walk = _walk;
    if (walk != null) await _repo.save(walk);
  }

  Future<void> _detectTopics() async {
    final walk = _walk;
    final ai = _ai();
    if (walk == null) return;
    if (ai == null) {
      _update(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    _update(() {
      _busy = true;
      _busyText = 'Die KI liest die Vorlesung und erkennt die Themen …';
      _error = null;
    });
    try {
      final topics = await ai.lectureTopics(title: walk.title, pageTexts: _pageTexts);
      _walk = walk.copyWith(topics: topics);
      await _save();
      _update(() {
        _coach =
            'Ich habe ${topics.length} ${topics.length == 1 ? 'Thema' : 'Themen'} gefunden: '
            '${topics.map((t) => '„${t.title}“').join(', ')}. Zu jedem bekommst du am Anfang eine schwere Aufgabe – '
            'die lösen wir gemeinsam, während du die Seiten liest.';
      });
    } catch (e) {
      _update(() => _error = e is AiServiceException ? e.message : 'Themen erkennen fehlgeschlagen: $e');
    } finally {
      _update(() => _busy = false);
    }
  }

  /// Aufgabe für das Thema der aktuellen Seite holen, falls es noch keine gibt.
  Future<void> _ensureTask({bool announce = false}) async {
    final walk = _walk;
    if (walk == null || walk.topics.isEmpty) return;
    final topic = walk.topicAt(walk.page);
    if (topic < 0) {
      final first = walk.topics.first;
      _update(() => _coach = 'Blättere weiter – das erste Thema „${first.title}“ beginnt auf Seite ${first.from}.');
      return;
    }
    if (walk.tasks.containsKey(topic)) {
      if (announce && _coach.isEmpty) {
        _update(() => _coach = 'Weiter mit unserer Aufgabe zu „${walk.topics[topic].title}“.');
      }
      return;
    }
    final ai = _ai();
    if (ai == null) {
      _update(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final info = walk.topics[topic];
    _update(() {
      _busy = true;
      _busyText = 'Neue Aufgabe zu „${info.title}“ …';
      _error = null;
    });
    try {
      final task = await ai.lectureTopicTask(
        lectureTitle: walk.title,
        topic: info,
        pageTexts: _pageTexts,
        known: walk.formulas,
      );
      final current = _walk ?? walk;
      final before = current.formulas.length;
      final next = current.copyWith(tasks: {...current.tasks, topic: task}).withRevealedFormulas();
      _walk = next;
      await _save();
      _update(() {
        _freshFormulas = next.formulas.length - before;
        _coach =
            '${topic == 0 ? 'Los geht’s' : 'Neues Thema'}: „${info.title}“. Hier ist unsere Aufgabe – wir lösen sie '
            'gemeinsam, Seite für Seite. Lies los!';
      });
    } catch (e) {
      _update(() => _error = e is AiServiceException ? e.message : 'Aufgabe erstellen fehlgeschlagen: $e');
    } finally {
      _update(() => _busy = false);
    }
  }

  /// Neue Seite: weiter mit der Aufgabe, neue Formeln an die Tafel, neues Thema.
  void _onPage(int page) {
    final old = _walk;
    if (old == null || page == old.page) return;
    final oldTopic = old.topicAt(old.page);
    final walk = old.withPage(page);
    final topic = walk.topicAt(page);
    final keepHighlight = _jumpTarget == page;
    _jumpTarget = null;
    var coach = _coach;
    var fresh = 0;
    if (keepHighlight) {
      // Sprung zum Haken: dessen Erklärung bleibt stehen.
    } else if (topic >= 0 && topic != oldTopic) {
      coach = walk.tasks.containsKey(topic) ? 'Weiter mit „${walk.topics[topic].title}“.' : coach;
    } else if (topic >= 0) {
      final before = old.revealedCount(topic);
      final after = walk.revealedCount(topic);
      if (after > before) {
        final task = walk.tasks[topic]!;
        final first = task.steps[before].step;
        final say = first.say.trim().isNotEmpty ? first.say.trim() : first.title;
        coach = 'Okay, lass uns mit unserer Aufgabe weitermachen: $say';
        if (after == task.steps.length) {
          coach += task.answer.isNotEmpty
              ? ' Damit ist sie gelöst: ${task.answer}'
              : ' Damit ist unsere Aufgabe gelöst.';
        }
      }
    }
    fresh = walk.formulas.length - old.formulas.length;
    if (walk.finished && !old.finished) {
      coach += ' Du bist einmal durch die Vorlesung! Jetzt kannst du die Aufgaben selbst lösen – oben „Selbst lösen“.';
    }
    _walk = walk;
    _update(() {
      _coach = coach;
      _freshFormulas = fresh;
      if (!keepHighlight) {
        _highlight = null;
        _highlightTopic = null;
      }
    });
    unawaited(_save());
    if (topic >= 0 && !walk.tasks.containsKey(topic)) unawaited(_ensureTask());
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
    final topic = walk.topicAt(walk.page);
    final task = topic >= 0 ? walk.tasks[topic] : null;
    final history = [..._chat];
    _update(() {
      _chat.add((user: true, text: question));
      _busy = true;
      _busyText = 'Die KI antwortet …';
      _error = null;
    });
    try {
      final answer = await ai.askLectureWalk(
        topic: topic >= 0 ? walk.topics[topic].title : walk.title,
        problem: task?.problem ?? '',
        boardSoFar: task == null ? const [] : _boardLines(task, walk.revealedCount(topic)),
        pageText: walk.page - 1 < _pageTexts.length ? _pageTexts[walk.page - 1] : '',
        formula: formula != null && formula < walk.formulas.length ? walk.formulas[formula] : null,
        history: history,
        question: question,
      );
      _update(() => _chat.add((user: false, text: answer)));
    } catch (e) {
      _update(() => _error = e is AiServiceException ? e.message : 'Frage fehlgeschlagen: $e');
    } finally {
      _update(() => _busy = false);
    }
  }

  LectureBoardState get _boardState {
    final walk = _walk;
    if (walk == null) return LectureBoardState(busy: _busy || _loading, busyText: _busyText, error: _error);
    final topic = walk.topicAt(walk.page);
    final task = topic >= 0 ? walk.tasks[topic] : null;
    return LectureBoardState(
      topicTitle: topic >= 0 ? walk.topics[topic].title : '',
      topicNumber: topic + 1,
      topicCount: walk.topics.length,
      pageLabel: 'Seite ${walk.page}/${walk.pageCount}',
      problem: task?.problem ?? '',
      steps: [for (final s in task?.steps ?? const <LectureTaskStep>[]) s.step],
      revealed: topic >= 0 ? walk.revealedCount(topic) : 0,
      current: _highlightTopic == topic ? _highlight : null,
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
    final window = await LectureBoardWindow.open(
      onAction: (action) {
        if (action['type'] == 'ask') {
          final formula = action['formula'];
          unawaited(_ask('${action['text'] ?? ''}', formula: formula is int ? formula : null));
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
    final result = await Navigator.of(context).push<({int topic, LectureAttempt attempt})>(
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
    _showHook(result.topic, result.attempt);
  }

  /// Zur Seite mit dem Haken springen und dort genau erklären.
  void _showHook(int topic, LectureAttempt attempt) {
    final walk = _walk;
    final step = attempt.step;
    final task = walk?.tasks[topic];
    if (walk == null || task == null || step == null) return;
    final page = task.steps[step].page;
    _update(() {
      _highlightTopic = topic;
      _highlight = step;
      _coach =
          'Hier hakt es – auf Seite $page wird genau das erklärt. ${attempt.feedback} Schau dir die Seite an, die '
          'Tafel zeigt unsere Lösung bis zu diesem Schritt.';
      if (attempt.explain.isNotEmpty) _chat.add((user: false, text: attempt.explain));
    });
    if (page != walk.page) {
      _jumpTarget = page;
      _goTo(page);
    }
  }

  void _workedSolution(int topic) {
    final walk = _walk;
    final task = walk?.tasks[topic];
    if (walk == null || task == null) return;
    final solution = WorkedSolution(
      id: 'lecture-${walk.materialId}-$topic',
      moduleId: walk.moduleId,
      problem: task.problem,
      detail: WorkDetail.normal,
      steps: [for (final s in task.steps) s.step],
      createdAt: DateTime.now(),
      title: task.title.isEmpty ? walk.topics[topic].title : task.title,
      answer: task.answer,
      withCalculator: false,
    );
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkedSolutionScreen(moduleId: walk.moduleId, problem: task.problem, solution: solution),
        ),
      ),
    );
  }

  void _visual(int topic, int step) {
    final walk = _walk;
    final task = walk?.tasks[topic];
    if (walk == null || task == null) return;
    final s = task.steps[step];
    final attempt = walk.attempts[topic];
    final now = DateTime.now();
    final card = Flashcard(
      id: 'lecture-${walk.materialId}-$topic-$step',
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
    final topic = walk?.topicAt(walk.page) ?? -1;
    final hooked = _highlight != null && _highlightTopic == topic;
    final board = LectureBoardView(
      state: _boardState,
      onAsk: (q, {formula}) => unawaited(_ask(q, formula: formula)),
      onDetach: LectureBoardWindow.supported && _window == null ? _detach : null,
      actions: [
        if (walk != null && topic >= 0 && walk.tasks.containsKey(topic))
          OutlinedButton.icon(
            key: const ValueKey('lecture-worked'),
            onPressed: () => _workedSolution(topic),
            icon: const Icon(Icons.co_present_outlined, size: 18),
            label: const Text('An der Tafel vorrechnen'),
          ),
        if (hooked)
          OutlinedButton.icon(
            key: const ValueKey('lecture-visual'),
            onPressed: () => _visual(topic, _highlight!),
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
          if (walk != null && walk.finished)
            TextButton.icon(
              key: const ValueKey('lecture-self-solve'),
              onPressed: _selfSolve,
              icon: const Icon(Icons.edit_note),
              label: const Text('Selbst lösen'),
            ),
          if (walk != null && walk.topics.isNotEmpty)
            PopupMenuButton<int>(
              key: const ValueKey('lecture-topics'),
              tooltip: 'Themen',
              icon: const Icon(Icons.list_alt),
              onSelected: (i) => _goTo(walk.topics[i].from),
              itemBuilder: (_) => [
                for (final (i, t) in walk.topics.indexed)
                  PopupMenuItem(value: i, child: Text('${i + 1}. ${t.title} (S. ${t.from}–${t.to})')),
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
                if (constraints.maxWidth >= 900) {
                  return Row(
                    children: [
                      Expanded(child: pages),
                      VerticalDivider(width: 1, color: c.border),
                      SizedBox(width: (constraints.maxWidth * 0.42).clamp(360.0, 620.0), child: board),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(flex: 5, child: pages),
                    Divider(height: 1, color: c.border),
                    Expanded(flex: 6, child: board),
                  ],
                );
              },
            ),
    );
  }

  Widget _pagePane(AppColors c, LectureWalk walk) {
    final topic = walk.topicAt(walk.page);
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
                    topic >= 0
                        ? 'Seite ${walk.page}/${walk.pageCount} · ${walk.topics[topic].title}'
                        : 'Seite ${walk.page}/${walk.pageCount}',
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
  int? _topic;
  final _answer = TextEditingController();
  bool _busy = false;
  String? _error;
  LectureAttempt? _result;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _open(int topic) async {
    setState(() {
      _topic = topic;
      _result = null;
      _error = null;
      _answer.clear();
    });
    if (_walk.tasks.containsKey(topic)) return;
    setState(() => _busy = true);
    try {
      final task = await widget.ai.lectureTopicTask(
        lectureTitle: _walk.title,
        topic: _walk.topics[topic],
        pageTexts: widget.pageTexts,
        known: _walk.formulas,
      );
      _walk = _walk.copyWith(tasks: {..._walk.tasks, topic: task}).withRevealedFormulas();
      widget.onSaved(_walk);
    } catch (e) {
      _error = e is AiServiceException ? e.message : '$e';
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final topic = _topic;
    final task = topic == null ? null : _walk.tasks[topic];
    if (topic == null || task == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.ai.checkLectureAttempt(task: task, attempt: _answer.text);
      _walk = _walk.copyWith(attempts: {..._walk.attempts, topic: result});
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
    final topic = _topic;
    final task = topic == null ? null : _walk.tasks[topic];
    final result = _result;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(topic == null ? 'Selbst lösen' : _walk.topics[topic].title),
        leading: topic == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _topic = null)),
      ),
      body: topic == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Du hast die Vorlesung einmal durch. Jetzt löst du jede Aufgabe ohne Hilfe – klappt es nicht, weiß '
                  'die App, wo der Haken ist, und springt zur passenden Seite.',
                  style: TextStyle(color: c.inkMuted, height: 1.4),
                ),
                const SizedBox(height: 12),
                for (final (i, t) in _walk.topics.indexed)
                  ListTile(
                    key: ValueKey('self-topic-$i'),
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
                    subtitle: Text('Seiten ${t.from}–${t.to}'),
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
                            onPressed: () => Navigator.of(context).pop((topic: topic, attempt: result)),
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
