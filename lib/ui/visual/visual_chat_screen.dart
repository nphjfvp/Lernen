import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/visual_chat.dart';
import '../../models/visual_lesson.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/visual_chat_repository.dart';
import '../../repositories/visual_lesson_repository.dart';
import '../../services/ai_service.dart';
import '../../services/visual_math.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';
import 'visual_lesson_screen.dart';
import 'visual_show_view.dart';

/// Visueller Chat: frei fragen – ohne PDF. Die KI antwortet je nach Wahl
/// visuell (Szene, 3D, Graph, Fahrzeug, Umformung), schriftlich oder beides;
/// Rückfragen beziehen sich aufs Gespräch. Aus einem Gespräch lässt sich eine
/// richtige Lektion machen.
class VisualChatScreen extends StatefulWidget {
  const VisualChatScreen({super.key, required this.moduleId, this.moduleName = '', this.chat});

  final String moduleId;
  final String moduleName;

  /// Ein gespeichertes Gespräch fortsetzen (null = neues).
  final VisualChat? chat;

  /// Test-Hook statt OpenRouter.
  static AiService? Function(String apiKey, String model)? aiFactory;

  /// Vorschläge, wenn das Gespräch eine Aufgabe vertieft (siehe
  /// VisualChat.context) – sie landen im Eingabefeld zum Anpassen.
  static const taskSuggestions = [
    'Lass uns das an einem einfachen Beispiel durchgehen',
    'Markiere jede Größe in einer eigenen Farbe, z.B. alles mit dem Weg grün und alles mit der Zeit rot, und zeig, '
        'wie sie sich durch die Rechnung zieht',
    'Was passiert dabei anschaulich? Zeig es als Animation',
    'Erklär mir den schwierigsten Schritt kleinschrittiger',
    'Welche typischen Fehler macht man bei dieser Aufgabe?',
  ];

  /// Vorschläge im Lern-Chat (VisualChat.learn) – werden direkt gefragt.
  static const learnSuggestions = [
    'Worum geht es in dieser Aufgabe überhaupt?',
    'Welche Begriffe und Konzepte muss ich dafür kennen?',
    'Erklär mir den wichtigsten Begriff von Grund auf',
    'Zeig mir das Konzept an einem einfachen Beispiel – nicht an der Aufgabe',
    'Wie hängen die Größen zusammen? Visualisier es',
  ];

  static const suggestions = [
    'Wie funktioniert ein Hebel?',
    'Zeig mir, warum die Ableitung von x² gleich 2x ist',
    'Wie sieht eine kfz-Elementarzelle aus?',
    'Was passiert beim Abschrecken von Stahl?',
  ];

  @override
  State<VisualChatScreen> createState() => _VisualChatScreenState();
}

class _VisualChatScreenState extends State<VisualChatScreen> {
  late VisualChat _chat =
      widget.chat ?? VisualChat(id: const Uuid().v4(), moduleId: widget.moduleId, createdAt: DateTime.now());
  final _input = TextEditingController();
  final _scroll = ScrollController();
  VisualChatMode _mode = VisualChatMode.both;
  bool _busy = false;
  String _busyText = '';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  AiService? _ai() {
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings == null || !settings.hasApiKey) return null;
    return VisualChatScreen.aiFactory?.call(settings.openRouterApiKey!, settings.questionModelId) ??
        AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  Future<void> _send([String? preset]) async {
    final question = (preset ?? _input.text).trim();
    if (question.isEmpty || _busy) return;
    final ai = _ai();
    if (ai == null) {
      setState(() => _error = 'Für den visuellen Chat braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final repo = context.read<VisualChatRepository>();
    final history = [for (final m in _chat.messages) (user: m.user, text: m.text)];
    setState(() {
      _error = null;
      _busy = true;
      _busyText = 'Die KI denkt nach …';
      _chat = _chat.withMessage(VisualChatMessage(user: true, text: question, mode: _mode, createdAt: DateTime.now()));
      _input.clear();
    });
    _scrollDown();
    try {
      final json = await ai.visualChat(
        question: question,
        history: history,
        mode: _mode.name,
        subject: widget.moduleName,
        context: _chat.context,
        learn: _chat.learn,
      );
      final visual = <String, dynamic>{
        for (final k in const ['variable', 'domain', 'functions', 'show', 'transform'])
          if (json[k] != null) k: json[k],
      };
      // Manche Modelle setzen Szene/Graph direkt neben den Text statt unter "show".
      if (visual['show'] == null) {
        final loose = {
          for (final k in const ['scene', 'scene3d', 'car', 'carFrom', 'vehicle', 'plot', 'tangent', 'area'])
            if (json[k] != null) k: json[k],
        };
        if (loose.isNotEmpty) visual['show'] = loose;
      }
      final answer = VisualChatMessage(
        user: false,
        text: '${json['text'] ?? ''}'.trim(),
        mode: _mode,
        visual: visual.containsKey('show') || visual.containsKey('transform') ? visual : null,
        createdAt: DateTime.now(),
      );
      if (!mounted) return;
      setState(() => _chat = _chat.withMessage(answer, title: '${json['title'] ?? ''}'.trim()));
      await repo.save(_chat);
      _scrollDown();
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Das hat nicht geklappt: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// „Als Lektion speichern“: Normalerweise genau das, was im Chat zu sehen
  /// war – ohne neue Anfrage. Auf Wunsch baut die KI daraus eine Lektion mit
  /// Übung (kostet eine weitere Anfrage, die Darstellungen entstehen neu).
  Future<void> _saveAsLesson() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('visual-chat-save'),
        title: const Text('Als Lektion speichern'),
        content: const Text(
          'So speichern: Jede Antwort wird ein Schritt – mit genau dem Text und der Darstellung, die du hier '
          'siehst. Das kostet nichts.\n\n'
          'Von der KI ausbauen: Sie schreibt aus dem Gespräch eine neue Lektion mit Übung. Das kostet eine '
          'weitere Anfrage, und die Darstellungen werden neu erzeugt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          TextButton(
            key: const ValueKey('visual-chat-save-ai'),
            onPressed: () => Navigator.of(ctx).pop('ai'),
            child: const Text('Von der KI ausbauen'),
          ),
          FilledButton(
            key: const ValueKey('visual-chat-save-direct'),
            onPressed: () => Navigator.of(ctx).pop('direct'),
            child: const Text('So speichern'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'ai') return _toLesson();
    final repo = context.read<VisualLessonRepository>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final lessons = _chat
        .toLessons(newId: () => const Uuid().v4())
        .map(VisualMath.sanitize)
        .where((l) => l.isUsable)
        .toList();
    if (lessons.isEmpty) {
      setState(() => _error = 'Hier gibt es noch keine Antwort, die sich speichern lässt.');
      return;
    }
    await repo.saveAll(lessons);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          lessons.length == 1
              ? 'Als Lektion gespeichert – ohne neue Anfrage.'
              : 'Als ${lessons.length} Lektionen gespeichert – ohne neue Anfrage.',
        ),
      ),
    );
    await navigator.push(MaterialPageRoute<void>(builder: (_) => VisualLessonScreen(lesson: lessons.first)));
  }

  /// Aus dem Gespräch von der KI eine richtige Lektion (Schritte, Übung) machen.
  Future<void> _toLesson() async {
    final ai = _ai();
    if (ai == null) return;
    final repo = context.read<VisualLessonRepository>();
    final navigator = Navigator.of(context);
    final staged = context.read<SettingsRepository?>()?.settings.stagedLessons ?? true;
    final transcript = [for (final m in _chat.messages) '${m.user ? 'Frage' : 'Antwort'}: ${m.text}'].join('\n');
    setState(() {
      _busy = true;
      _busyText = 'Die KI baut eine Lektion aus dem Gespräch …';
      _error = null;
    });
    try {
      final raws = await ai.generateVisualLessons(
        topic:
            'Mach aus diesem Gespräch eine Lektion – genau zu dem, was gefragt und erklärt wurde, mit Übung:\n'
            '$transcript',
        staged: staged,
        // Die Lektion öffnet sich gleich – ihr Bildschirm zeichnet die Szenen.
        drawScenes: false,
      );
      final lesson = [
        for (final raw in raws)
          ?VisualLesson.fromMap(
            raw,
            id: const Uuid().v4(),
            moduleId: widget.moduleId,
            createdAt: DateTime.now(),
            source: 'Visueller Chat: ${_chat.displayTitle}',
          ),
      ].map(VisualMath.sanitize).where((l) => l.isUsable).firstOrNull;
      if (lesson == null) {
        throw AiServiceException('Die KI-Antwort ließ sich nicht als Lektion lesen – bitte erneut versuchen.');
      }
      await repo.save(lesson);
      if (!mounted) return;
      setState(() => _busy = false);
      await navigator.push(MaterialPageRoute<void>(builder: (_) => VisualLessonScreen(lesson: lesson)));
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Das hat nicht geklappt: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    await context.read<VisualChatRepository>().delete(_chat.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasAnswer = _chat.messages.any((m) => !m.user);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(_chat.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('visual-chat-lesson'),
            tooltip: 'Als Lektion speichern',
            onPressed: hasAnswer && !_busy ? _saveAsLesson : null,
            icon: const Icon(Icons.school_outlined),
          ),
          if (!_chat.learn)
            IconButton(
              key: const ValueKey('visual-chat-new'),
              tooltip: 'Neuer Chat',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _chat = VisualChat(id: const Uuid().v4(), moduleId: widget.moduleId, createdAt: DateTime.now());
                      _error = null;
                    }),
              icon: const Icon(Icons.add_comment_outlined),
            ),
          if (_chat.messages.isNotEmpty)
            IconButton(
              key: const ValueKey('visual-chat-delete'),
              tooltip: 'Gespräch löschen',
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      if (_chat.messages.isEmpty) ..._empty(c),
                      for (final (i, m) in _chat.messages.indexed) _message(c, i, m),
                      if (_busy)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 10),
                              Text(_busyText, style: TextStyle(color: c.inkMuted)),
                            ],
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _error!,
                            key: const ValueKey('visual-chat-error'),
                            style: TextStyle(color: c.danger),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_chat.learn) _solveBar(c),
                _composer(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _empty(AppColors c) => _chat.learn
      ? _emptyForLearn(c)
      : _chat.context.isNotEmpty
      ? _emptyForTask(c)
      : _emptyFree(c);

  /// Lern-Chat: „Ich bin bereit“ führt zurück in die Aufgabe (Ergebnis true).
  Widget _solveBar(AppColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        key: const ValueKey('visual-chat-solve'),
        onPressed: _busy ? null : () => Navigator.of(context).pop(true),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Ich hab’s verstanden – jetzt lösen'),
      ),
    ),
  );

  Widget _contextCard(AppColors c, String heading) => Container(
    key: const ValueKey('visual-chat-context'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: TextStyle(fontWeight: FontWeight.w600, color: c.accentOnSoft),
        ),
        const SizedBox(height: 6),
        MathText(
          _chat.context.split('\n\n').first,
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.ink, height: 1.4),
        ),
      ],
    ),
  );

  /// Lern-Chat: erst Begriffe und Ideen klären, ohne Lösung.
  List<Widget> _emptyForLearn(AppColors c) => [
    _contextCard(c, 'Erst verstehen, dann lösen'),
    const SizedBox(height: 14),
    Text(
      'Frag alles, was du für diese Aufgabe wissen willst – Begriffe, die du noch nie gehört hast, Ideen, '
      'Hintergründe. Die KI erklärt und zeigt es dir, verrät aber die Lösung nicht. Wenn du bereit bist: „Jetzt lösen“.',
      style: TextStyle(color: c.inkMuted, height: 1.4),
    ),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (i, s) in VisualChatScreen.learnSuggestions.indexed)
          ActionChip(
            key: ValueKey('visual-chat-learn-suggest-$i'),
            label: Text(s, maxLines: 2, overflow: TextOverflow.ellipsis),
            onPressed: _busy ? null : () => _send(s),
          ),
      ],
    ),
  ];

  /// Gespräch zu einer Aufgabe: die Aufgabe oben, Vorschläge zum Vertiefen.
  List<Widget> _emptyForTask(AppColors c) => [
    _contextCard(c, 'Darauf bezieht sich das Gespräch'),
    const SizedBox(height: 14),
    Text(
      'Frag nach, lass dir etwas an einem Beispiel zeigen oder Größen farbig markieren – die KI kennt die Aufgabe '
      'und den Lösungsweg.',
      style: TextStyle(color: c.inkMuted, height: 1.4),
    ),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (i, s) in VisualChatScreen.taskSuggestions.indexed)
          ActionChip(
            key: ValueKey('visual-chat-task-suggest-$i'),
            label: Text(s, maxLines: 2, overflow: TextOverflow.ellipsis),
            onPressed: () => setState(
              () => _input
                ..text = s
                ..selection = TextSelection.collapsed(offset: s.length),
            ),
          ),
      ],
    ),
  ];

  List<Widget> _emptyFree(AppColors c) => [
    const SizedBox(height: 12),
    Icon(Icons.forum_outlined, size: 40, color: c.accent),
    const SizedBox(height: 8),
    Text(
      'Frag einfach – die KI erklärt mit Bildern',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 4),
    Text(
      'Ohne PDF: Szenen, 3D-Modelle, Graphen, Umformungen – oder nur Text. Unten wählst du, wie.',
      textAlign: TextAlign.center,
      style: TextStyle(color: c.inkMuted),
    ),
    const SizedBox(height: 14),
    Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (i, s) in VisualChatScreen.suggestions.indexed)
          ActionChip(key: ValueKey('visual-chat-suggest-$i'), label: Text(s), onPressed: () => _send(s)),
      ],
    ),
  ];

  Widget _message(AppColors c, int i, VisualChatMessage m) {
    if (m.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          key: ValueKey('visual-chat-msg-$i'),
          constraints: const BoxConstraints(maxWidth: 600),
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(16)),
          child: MathText(m.text, style: const TextStyle(fontSize: 14.5, height: 1.4)),
        ),
      );
    }
    final lesson = m.visualLesson;
    final show = lesson?.steps.single.show;
    return Container(
      key: ValueKey('visual-chat-msg-$i'),
      margin: const EdgeInsets.only(bottom: 12, right: 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (m.text.isNotEmpty) MathText(m.text, style: const TextStyle(fontSize: 14.5, height: 1.5)),
          if (lesson != null && show != null && VisualShowView.hasContent(show)) ...[
            if (m.text.isNotEmpty) const SizedBox(height: 12),
            VisualShowView(key: ValueKey('visual-chat-visual-$i'), math: VisualMath(lesson), show: show),
          ],
          // Darstellung angefordert, aber (teils) nicht ladbar: sagen statt verschweigen.
          if (m.visual != null && (show == null || show.broken.isNotEmpty || !VisualShowView.hasContent(show)))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.broken_image_outlined, size: 18, color: c.warn),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Darstellung ließ sich ${show != null && VisualShowView.hasContent(show) ? 'nicht ganz' : 'nicht'} '
                      'laden${show != null && show.broken.isNotEmpty ? ' (${show.broken})' : ''}.',
                      key: ValueKey('visual-chat-broken-$i'),
                      style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                    ),
                  ),
                  TextButton(
                    key: ValueKey('visual-chat-retry-$i'),
                    onPressed: _busy
                        ? null
                        : () => _send('Zeig die Darstellung zur letzten Antwort bitte noch einmal neu.'),
                    child: const Text('Nochmal zeigen'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _composer(AppColors c) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
    decoration: BoxDecoration(
      color: c.surface,
      border: Border(top: BorderSide(color: c.border)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<VisualChatMode>(
          key: const ValueKey('visual-chat-mode'),
          segments: const [
            ButtonSegment(value: VisualChatMode.visual, label: Text('Visuell'), icon: Icon(Icons.animation)),
            ButtonSegment(value: VisualChatMode.text, label: Text('Schriftlich'), icon: Icon(Icons.notes)),
            ButtonSegment(value: VisualChatMode.both, label: Text('Beides')),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('visual-chat-input'),
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Frag etwas – z.B. „Zeig mir, wie ein Getriebe übersetzt“',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const ValueKey('visual-chat-send'),
              tooltip: 'Senden',
              onPressed: _busy ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ],
    ),
  );
}
