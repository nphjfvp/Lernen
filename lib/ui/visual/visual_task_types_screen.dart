import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/flashcard.dart';
import '../../models/visual_lesson.dart';
import '../../models/visual_task_type.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/visual_lesson_repository.dart';
import '../../repositories/visual_task_type_repository.dart';
import '../../services/ai_service.dart';
import '../../services/visual_math.dart';
import '../../theme/app_colors.dart';
import 'visual_lesson_screen.dart';

/// „Aufgaben visuell lösen“: Die KI ordnet die Aufgaben und Fragen eines Fachs
/// in Aufgabentypen (z.B. „Weg-Zeit-Funktion aus der Beschleunigung“). Man
/// tippt einen Typ an, wählt Leicht/Mittel/Schwer – die KI stellt eine NEUE
/// Aufgabe dieses Typs und löst sie als visuelle Lektion Schritt für Schritt
/// (Größen farbig markiert). In jedem Schritt führt „Im Gespräch vertiefen“ in
/// einen Chat, der Aufgabe und Lösungsweg kennt.
class VisualTaskTypesScreen extends StatefulWidget {
  const VisualTaskTypesScreen({super.key, required this.moduleId, this.moduleName = ''});

  final String moduleId;
  final String moduleName;

  /// Test-Hook statt OpenRouter.
  static AiService? Function(String apiKey, String model)? aiFactory;

  /// So viele Aufgaben gehen höchstens an die Typ-Erkennung.
  static const maxItems = 120;

  /// So viele Beispiele eines Typs bekommt die KI beim Aufgabe-Stellen.
  static const maxExamples = 3;

  /// Karten für die Typ-Erkennung: zuerst echte Aufgaben (Rechenwege, Freitext
  /// …), dann die übrigen – höchstens [maxItems].
  static List<({String id, String type, String text})> itemsFor(List<Flashcard> cards) {
    final sorted = [...cards]..sort((a, b) => _weight(b).compareTo(_weight(a)));
    return [
      for (final c in sorted.take(maxItems))
        (id: c.id, type: c.type.label, text: c.promptText.trim().isEmpty ? c.front : c.promptText),
    ];
  }

  static int _weight(Flashcard c) => switch (c.type) {
    QuestionType.flashcard || QuestionType.singleChoice || QuestionType.multipleChoice => 0,
    _ => 1,
  };

  @override
  State<VisualTaskTypesScreen> createState() => _VisualTaskTypesScreenState();
}

class _VisualTaskTypesScreenState extends State<VisualTaskTypesScreen> {
  final _repo = VisualTaskTypeRepository();
  VisualTaskCatalog? _catalog;
  bool _loaded = false;
  bool _busy = false;
  String _progress = '';
  String? _error;

  List<Flashcard> get _cards => context.read<FlashcardRepository>().forModule(widget.moduleId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final cards = context.read<FlashcardRepository>();
    await cards.loadForModule(widget.moduleId);
    final catalog = await _repo.load(widget.moduleId);
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _loaded = true;
    });
  }

  AiService? _ai() {
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings == null || !settings.hasApiKey) return null;
    return VisualTaskTypesScreen.aiFactory?.call(settings.openRouterApiKey!, settings.questionModelId) ??
        AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
  }

  Future<void> _run(String progress, Future<void> Function(AiService ai) job) async {
    final ai = _ai();
    if (ai == null) {
      setState(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = progress;
    });
    try {
      await job(ai);
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Das hat nicht geklappt: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _findTypes() async {
    final cards = _cards;
    if (cards.isEmpty) {
      setState(() => _error = 'Im Fach gibt es noch keine Aufgaben oder Fragen – erst Übungen importieren.');
      return;
    }
    await _run('Die KI ordnet die Aufgaben des Fachs in Typen …', (ai) async {
      final types = await ai.findTaskTypes(VisualTaskTypesScreen.itemsFor(cards), subject: widget.moduleName);
      final catalog = VisualTaskCatalog(
        moduleId: widget.moduleId,
        types: types,
        cardCount: cards.length,
        updatedAt: DateTime.now(),
      );
      await _repo.save(catalog);
      if (mounted) setState(() => _catalog = catalog);
    });
  }

  Future<void> _customType() async {
    var value = '';
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eigener Aufgabentyp'),
        content: TextField(
          key: const ValueKey('task-custom-field'),
          onChanged: (v) => value = v,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'z.B. Weg-Zeit-Funktion aus der Beschleunigung'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(
            key: const ValueKey('task-custom-ok'),
            onPressed: () => Navigator.of(ctx).pop(value),
            child: const Text('Weiter'),
          ),
        ],
      ),
    );
    final t = title?.trim() ?? '';
    if (t.isEmpty || !mounted) return;
    await _open(VisualTaskType(id: 'eigen', title: t));
  }

  Future<void> _open(VisualTaskType type) async {
    final choice = await showModalBottomSheet<({VisualTaskLevel level, VisualStyle style})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StartSheet(type: type),
    );
    if (choice == null || !mounted) return;
    await _solve(type, choice.level, choice.style);
  }

  Future<void> _solve(VisualTaskType type, VisualTaskLevel level, VisualStyle style) async {
    final lessons = context.read<VisualLessonRepository>();
    final byId = {for (final c in _cards) c.id: c};
    final examples = [for (final id in type.cardIds) ?byId[id]]..shuffle(Random());
    final what = switch (level) {
      VisualTaskLevel.easy => 'leichte',
      VisualTaskLevel.medium => 'mittelschwere',
      VisualTaskLevel.hard => 'schwere',
    };
    await _run('Die KI stellt eine $what Aufgabe und löst sie Schritt für Schritt …', (ai) async {
      final raws = await ai.generateVisualLessons(
        topic: AiService.visualTaskTopic(
          type: type,
          level: level,
          examples: [
            for (final c in examples.take(VisualTaskTypesScreen.maxExamples))
              (front: c.promptText.trim().isEmpty ? c.front : c.promptText, back: c.back),
          ],
        ),
        detail: 'ausführlich',
        socratic: style == VisualStyle.socratic,
      );
      final lesson = [
        for (final raw in raws)
          ?VisualLesson.fromMap(
            raw,
            id: const Uuid().v4(),
            moduleId: widget.moduleId,
            createdAt: DateTime.now(),
            source: 'Aufgabentyp: ${type.title} · ${level.label}',
            detail: 'ausführlich',
            style: style,
          ),
      ].map(VisualMath.sanitize).where((l) => l.isUsable).firstOrNull;
      if (lesson == null) {
        throw AiServiceException('Die KI-Antwort ließ sich nicht als Aufgabe lesen – bitte erneut versuchen.');
      }
      await lessons.save(lesson);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VisualLessonScreen(lesson: lesson)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final catalog = _catalog;
    final cardCount = context.watch<FlashcardRepository>().forModule(widget.moduleId).length;
    final stale = catalog != null && cardCount > catalog.cardCount + 5;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Aufgaben visuell lösen')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Die KI kennt die Aufgaben dieses Fachs und ordnet sie in Aufgabentypen. Tippe einen Typ an und wähle '
                  'Leicht, Mittel oder Schwer: Sie stellt dir eine neue Aufgabe und löst sie Schritt für Schritt mit '
                  'Animationen – gleiche Größen haben überall dieselbe Farbe. In jedem Schritt kannst du „Im Gespräch '
                  'vertiefen“: z.B. „Markier alles mit Weg grün und alles mit Zeit rot“.',
                  style: TextStyle(color: c.inkMuted, height: 1.45),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('task-types-find'),
                      onPressed: _busy ? null : _findTypes,
                      icon: const Icon(Icons.category_outlined, size: 18),
                      label: Text(catalog == null ? 'Aufgabentypen erkennen' : 'Neu erkennen'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('task-type-custom'),
                      onPressed: _busy ? null : _customType,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Eigener Typ'),
                    ),
                  ],
                ),
                if (stale)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Seit dem Erkennen sind ${cardCount - catalog.cardCount} Aufgaben dazugekommen – „Neu erkennen“ '
                      'nimmt sie mit auf.',
                      key: const ValueKey('task-types-stale'),
                      style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                    ),
                  ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_progress, key: const ValueKey('task-progress'))),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const ValueKey('task-error'),
                    style: TextStyle(color: c.danger),
                  ),
                ],
                const SizedBox(height: 18),
                if (catalog == null)
                  Text(
                    cardCount == 0
                        ? 'Noch keine Aufgaben im Fach. Importiere Übungsblätter oder Altklausuren (Nachbereiten oder '
                              '„Fragen aus PDF importieren“) – oder gib oben einen eigenen Typ ein.'
                        : '$cardCount Aufgaben und Fragen im Fach – „Aufgabentypen erkennen“ ordnet sie.',
                    key: const ValueKey('task-types-empty'),
                    style: TextStyle(color: c.inkMuted, height: 1.4),
                  )
                else
                  for (final (i, t) in catalog.types.indexed)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        key: ValueKey('task-type-$i'),
                        enabled: !_busy,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        title: Text(
                          t.title,
                          style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                        ),
                        subtitle: Text(
                          [
                            if (t.description.isNotEmpty) t.description,
                            if (t.cardIds.isNotEmpty)
                              '${t.cardIds.length} ${t.cardIds.length == 1 ? 'Beispiel' : 'Beispiele'} im Fach',
                          ].join('\n'),
                          style: TextStyle(color: c.inkMuted, height: 1.35),
                        ),
                        trailing: const Icon(Icons.play_circle_outline),
                        onTap: () => _open(t),
                      ),
                    ),
              ],
            ),
    );
  }
}

/// Stufe und Lernweg für eine neue Aufgabe.
class _StartSheet extends StatefulWidget {
  const _StartSheet({required this.type});

  final VisualTaskType type;

  @override
  State<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<_StartSheet> {
  VisualTaskLevel _level = VisualTaskLevel.medium;
  VisualStyle _style = VisualStyle.explain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.type.title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink),
            ),
            if (widget.type.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(widget.type.description, style: TextStyle(color: c.inkMuted, height: 1.35)),
            ],
            const SizedBox(height: 16),
            Text(
              'Schwierigkeit',
              style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
            ),
            const SizedBox(height: 6),
            SegmentedButton<VisualTaskLevel>(
              key: const ValueKey('task-level'),
              segments: [
                for (final l in VisualTaskLevel.values)
                  ButtonSegment(
                    value: l,
                    label: Text(l.label, key: ValueKey('task-level-${l.name}')),
                  ),
              ],
              selected: {_level},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _level = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              'Leicht = ${VisualTaskLevel.easy.meaning}; Schwer = ${VisualTaskLevel.hard.meaning}.',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35),
            ),
            const SizedBox(height: 14),
            Text(
              'Lernweg',
              style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
            ),
            const SizedBox(height: 6),
            SegmentedButton<VisualStyle>(
              key: const ValueKey('task-style'),
              segments: const [
                ButtonSegment(value: VisualStyle.explain, label: Text('Vorrechnen')),
                ButtonSegment(value: VisualStyle.socratic, label: Text('Sokratisch')),
              ],
              selected: {_style},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _style = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              _style == VisualStyle.explain
                  ? 'Die KI rechnet dir jeden Schritt vor und zeigt ihn.'
                  : 'Die KI führt dich mit Fragen – du kommst selbst auf jeden Schritt.',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('task-start'),
                onPressed: () => Navigator.of(context).pop((level: _level, style: _style)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Aufgabe stellen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
