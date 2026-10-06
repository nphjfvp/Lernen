import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/flashcard.dart';
import '../../models/gantt_task.dart';
import '../../models/interactive_task.dart';
import '../../models/material_item.dart';
import '../../models/step_task.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/gantt_scheduler.dart';
import '../../services/image_crop.dart';
import '../../services/step_checker.dart';
import '../../theme/app_colors.dart';
import '../widgets/discard_guard.dart';
import '../widgets/raw_response_dialog.dart';
import '../widgets/safe_set_state.dart';
import 'gantt_task_editor.dart';
import 'gantt_task_view.dart';
import 'step_task_editor.dart';
import 'step_task_view.dart';

enum _KindChoice { auto, steps, gantt }

/// Aufgabe übernehmen: aus einer Übungsaufgabe (Text und/oder Fotos, optional
/// mit vorhandener Lösung) wird eine interaktive Aufgabe – Rechenweg Schritt
/// für Schritt ([QuestionType.steps]) oder Terminierung im Gantt-Diagramm
/// ([QuestionType.gantt]). Die KI schlägt Struktur und erwartete Antworten
/// vor (AiService.buildInteractiveTask), die App rechnet nach
/// (StepChecker.verify bzw. GanttScheduler). Vor dem Speichern lässt sich
/// alles bearbeiten und ausprobieren.
class TaskImportScreen extends StatefulWidget {
  const TaskImportScreen({
    super.key,
    required this.moduleId,
    this.moduleName = '',
    this.initialText = '',
    this.initialSolution = '',
    this.initialImages = const [],
    this.initialKind,
    this.sourceMaterialId,
    this.sourcePage,
    this.unitId,
    this.replaceCard,
  });

  final String moduleId;
  final String moduleName;
  final String initialText;
  final String initialSolution;
  final List<Uint8List> initialImages;

  /// Vorgewählte Art; null = die KI entscheidet.
  final InteractiveKind? initialKind;

  /// Herkunft (Übungsblatt und Seite) – "Im Aufgabenblatt ansehen" führt dorthin.
  final String? sourceMaterialId;
  final int? sourcePage;
  final String? unitId;

  /// Aufgabe aus dem Aufgaben-Ordner, die hiermit interaktiv wird. Sie bleibt
  /// erhalten, außer man wählt beim Speichern "aus dem Ordner entfernen".
  final Flashcard? replaceCard;

  static const maxImages = 4;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  /// Nur für Tests: statt des Datei-Dialogs.
  @visibleForTesting
  static Future<List<({String name, Uint8List bytes})>> Function()? pickImagesHook;

  @override
  State<TaskImportScreen> createState() => _TaskImportScreenState();
}

class _TaskImportScreenState extends State<TaskImportScreen> with SafeSetState<TaskImportScreen> {
  late final _text = TextEditingController(text: widget.initialText);
  late final _solution = TextEditingController(text: widget.initialSolution);
  final _front = TextEditingController();
  final _back = TextEditingController();
  late final List<({String name, Uint8List bytes})> _images = [
    for (final (i, bytes) in widget.initialImages.indexed) (name: 'Seite ${widget.sourcePage ?? i + 1}', bytes: bytes),
  ];
  late _KindChoice _choice = switch (widget.initialKind) {
    InteractiveKind.steps => _KindChoice.steps,
    InteractiveKind.gantt => _KindChoice.gantt,
    null => _KindChoice.auto,
  };

  bool _busy = false;
  bool _saving = false;
  String? _error;
  String? _raw;

  /// Begründung der KI, wenn die Aufgabe nicht passt.
  String? _unsuitable;
  InteractiveKind? _kind;
  StepTask? _steps;
  GanttTask? _gantt;

  /// Neu aufgebaute Editoren nach jedem KI-Ergebnis.
  int _revision = 0;
  bool _attachImage = false;
  bool _removeReplaced = false;

  bool get _hasDraft => _kind != null && (_steps != null || _gantt != null);

  @override
  void initState() {
    super.initState();
    // Bei einem Seitenbild gehört die Abbildung meist zur Aufgabe.
    _attachImage = widget.initialImages.length == 1 && widget.sourcePage != null;
  }

  @override
  void dispose() {
    _text.dispose();
    _solution.dispose();
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  AiService? _ai({required bool vision}) {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return null;
    final model = vision ? settings.visionModelId : settings.questionModelId;
    return TaskImportScreen.aiFactory?.call(settings.openRouterApiKey!, model) ??
        AiService(apiKey: settings.openRouterApiKey!, model: model);
  }

  InteractiveKind? get _wanted => switch (_choice) {
        _KindChoice.auto => null,
        _KindChoice.steps => InteractiveKind.steps,
        _KindChoice.gantt => InteractiveKind.gantt,
      };

  Future<void> _pickImages() async {
    final room = TaskImportScreen.maxImages - _images.length;
    if (room <= 0) return;
    final List<({String name, Uint8List bytes})> picked;
    final hook = TaskImportScreen.pickImagesHook;
    if (hook != null) {
      picked = await hook();
    } else {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      picked = [for (final f in files.take(room)) (name: f.name, bytes: await f.readAsBytes())];
    }
    final prepared = [for (final p in picked.take(room)) (name: p.name, bytes: await prepareImageForAi(p.bytes))];
    if (!mounted) return;
    setState(() => _images.addAll(prepared));
  }

  Future<void> _build({InteractiveKind? force}) async {
    if (_text.text.trim().isEmpty && _images.isEmpty) {
      setState(() => _error = 'Gib die Aufgabe als Text ein oder füge ein Foto hinzu.');
      return;
    }
    final ai = _ai(vision: _images.isNotEmpty);
    if (ai == null) {
      setState(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    if (force != null) {
      _choice = force == InteractiveKind.steps ? _KindChoice.steps : _KindChoice.gantt;
    }
    setState(() {
      _busy = true;
      _error = null;
      _raw = null;
      _unsuitable = null;
    });
    try {
      final draft = await ai.buildInteractiveTask(
        text: _text.text,
        images: [for (final i in _images) i.bytes],
        solution: _solution.text,
        kind: force ?? _wanted,
      );
      setState(() {
        if (draft.kind == null) {
          _unsuitable = draft.reason;
          return;
        }
        _kind = draft.kind;
        _steps = draft.steps;
        _gantt = draft.gantt;
        _front.text = draft.front.trim().isNotEmpty ? draft.front.trim() : _text.text.trim();
        _back.text = draft.back.trim();
        _revision++;
      });
    } on AiServiceException catch (e) {
      setState(() {
        _error = e.message;
        _raw = e.rawResponse;
      });
    } catch (e) {
      setState(() => _error = 'Erstellen fehlgeschlagen: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// Karte aus dem aktuellen Stand – zum Ausprobieren und Speichern.
  Flashcard _card({DateTime? now}) {
    final at = now ?? DateTime.now();
    final kind = _kind!;
    final gantt = _gantt;
    final material = widget.sourceMaterialId == null
        ? null
        : context.read<MaterialRepository?>()?.forModule(widget.moduleId).where((m) => m.id == widget.sourceMaterialId).firstOrNull;
    return Flashcard(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      front: _front.text.trim(),
      back: kind == InteractiveKind.gantt && gantt != null ? GanttScheduler.solutionText(gantt) : _back.text.trim(),
      createdAt: at,
      due: at,
      type: kind.type,
      taskData: kind == InteractiveKind.gantt ? gantt?.confirmed().toMap() : _steps?.toMap(),
      imageBase64: _attachImage && _images.isNotEmpty && kind == InteractiveKind.steps ? base64Encode(_images.first.bytes) : null,
      unitId: widget.unitId ?? widget.replaceCard?.unitId,
      sourceMaterialId: widget.sourceMaterialId ?? widget.replaceCard?.sourceMaterialId,
      sourcePage: widget.sourcePage ?? widget.replaceCard?.sourcePage,
      // Selbst übernommene Aufgaben sollen bald drankommen, unabhängig vom
      // Einheiten-Gate (siehe Flashcard.priorityIntroduction).
      priorityIntroduction: true,
      weight: defaultFlashcardWeightFor(material?.kind ?? MaterialKind.exercise),
    );
  }

  /// Was vor dem Speichern noch fehlt (null = alles da).
  String? _missing() {
    if (_front.text.trim().isEmpty) return 'Die Aufgabe (Text) darf nicht leer sein.';
    switch (_kind) {
      case InteractiveKind.steps:
        final steps = _steps;
        if (steps == null || !steps.isUsable) {
          return 'Jeder Schritt braucht ein Eingabefeld oder eine richtige Auswahl-Antwort.';
        }
        if (steps.finalField == null && steps.steps.every((s) => s.isChoice)) {
          return 'Es fehlt ein Feld für das Endergebnis.';
        }
      case InteractiveKind.gantt:
        final gantt = _gantt;
        if (gantt == null || !gantt.isValid) {
          return 'Die Teile passen nicht zusammen (fehlende Arbeitsgänge oder ein Kreis in der Reihenfolge).';
        }
        if (!gantt.drawChart && gantt.questions.isEmpty) {
          return 'Wähle, was gefragt ist, oder lass das Diagramm zeichnen.';
        }
      case null:
        return 'Erst eine Aufgabe erstellen.';
    }
    return null;
  }

  /// Hinweise, bei denen man bewusst trotzdem speichern kann.
  List<String> _warnings() => switch (_kind) {
        InteractiveKind.steps => StepChecker.verify(_steps!).problems,
        InteractiveKind.gantt => [
            if (_gantt!.hasUncertain) 'Manche Werte waren schlecht lesbar und sind noch nicht bestätigt.',
            ...GanttScheduler.plan(_gantt!).problems,
          ],
        null => const [],
      };

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _try() async {
    final missing = _missing();
    if (missing != null) return _snack(missing);
    final card = _card();
    final outcome = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _TryTaskScreen(card: card)),
    );
    if (outcome != null && mounted) _snack(outcome);
  }

  Future<void> _save() async {
    final missing = _missing();
    if (missing != null) {
      setState(() => _error = missing);
      return;
    }
    final warnings = _warnings();
    if (warnings.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Trotzdem speichern?'),
          content: Text('Die App hat noch etwas gefunden:\n\n${warnings.map((w) => '• $w').join('\n')}'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Prüfen')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Speichern')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final repo = context.read<FlashcardRepository>();
    final card = _card();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await repo.saveAll([card]);
      final replaced = widget.replaceCard;
      if (_removeReplaced && replaced != null) await repo.delete(replaced.id, replaced.moduleId);
      if (!mounted) return;
      _snack('${card.type.label}-Aufgabe gespeichert – sie kommt bald im Lernplan dran.');
      Navigator.of(context).pop(card);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Speichern fehlgeschlagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    return DiscardGuard(
      active: _hasDraft && !_saving,
      message: 'Die erstellte Aufgabe ist noch nicht gespeichert.',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aufgabe übernehmen', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if (widget.moduleName.isNotEmpty) Text(widget.moduleName, style: TextStyle(fontSize: 12, color: c.inkMuted)),
            ],
          ),
          actions: [
            if (_hasDraft)
              TextButton(
                key: const ValueKey('task-import-save-top'),
                onPressed: _saving ? null : _save,
                child: const Text('Speichern'),
              ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                children: [
                  _inputCard(c, hasKey),
                  if (_error != null) ...[const SizedBox(height: 12), _errorCard(c)],
                  if (_unsuitable != null) ...[const SizedBox(height: 12), _unsuitableCard(c)],
                  if (_hasDraft) ..._draftViews(c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(AppColors c, {required Widget child, Color? tint, Key? key}) => Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tint ?? c.surface,
          border: tint == null ? Border.all(color: c.border) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );

  Widget _inputCard(AppColors c, bool hasKey) {
    return _panel(
      c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Aus einer Übungsaufgabe wird eine interaktive Aufgabe: ein Rechenweg Schritt für Schritt (z. B. '
            'Differentialgleichungen, Integrale, Werkstoff- oder BWL-Rechnungen) oder eine Terminierung im '
            'Gantt-Diagramm. Die KI liest die Aufgabe, die App rechnet alles nach.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_KindChoice>(
            key: const ValueKey('task-import-kind'),
            segments: const [
              ButtonSegment(value: _KindChoice.auto, label: Text('Automatisch')),
              ButtonSegment(value: _KindChoice.steps, label: Text('Rechenweg')),
              ButtonSegment(value: _KindChoice.gantt, label: Text('Terminierung')),
            ],
            selected: {_choice},
            showSelectedIcon: false,
            onSelectionChanged: _busy ? null : (s) => setState(() => _choice = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('task-import-text'),
            controller: _text,
            minLines: 3,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Aufgabe',
              hintText: 'Aufgabentext einfügen – bei einem Foto reicht, welche Aufgabe (z. B. „Aufgabe 2b“)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('task-import-add-image'),
                onPressed: _busy || _images.length >= TaskImportScreen.maxImages ? null : _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(_images.isEmpty ? 'Foto der Aufgabe' : 'Weiteres Foto'),
              ),
              for (final (i, image) in _images.indexed)
                InputChip(
                  key: ValueKey('task-import-image-$i'),
                  avatar: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      image.bytes,
                      width: 22,
                      height: 22,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.image_outlined, size: 18),
                    ),
                  ),
                  label: Text(image.name, overflow: TextOverflow.ellipsis),
                  onDeleted: _busy ? null : () => setState(() => _images.removeAt(i)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('task-import-solution'),
            controller: _solution,
            minLines: 1,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Lösung (optional)',
              hintText: 'Vorhandene Musterlösung – hilft der KI, die Schritte richtig aufzuteilen',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('task-import-build'),
            onPressed: hasKey && !_busy ? () => _build() : null,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_hasDraft ? Icons.refresh : Icons.auto_awesome_outlined, size: 18),
            label: Text(_busy ? 'KI liest die Aufgabe …' : (_hasDraft ? 'Neu erstellen' : 'Aufgabe erstellen')),
          ),
          if (!hasKey)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Dafür braucht die App deinen OpenRouter-Key (Einstellungen).',
                  style: TextStyle(fontSize: 12.5, color: c.warn)),
            ),
        ],
      ),
    );
  }

  Widget _errorCard(AppColors c) => _panel(
        c,
        tint: c.dangerSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, key: const ValueKey('task-import-error'), style: TextStyle(color: c.danger, height: 1.35)),
            if (_raw != null)
              TextButton(onPressed: () => showRawResponseDialog(context, _raw!), child: const Text('Rohantwort anzeigen')),
          ],
        ),
      );

  Widget _unsuitableCard(AppColors c) => _panel(
        c,
        key: const ValueKey('task-import-unsuitable'),
        tint: c.warnSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Passt nicht als interaktive Aufgabe',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.warn)),
            const SizedBox(height: 4),
            Text(_unsuitable!, style: TextStyle(fontSize: 13, height: 1.4, color: c.ink)),
            const SizedBox(height: 4),
            Text(
              widget.replaceCard != null
                  ? 'Die Aufgabe bleibt im Aufgaben-Ordner. Du kannst es trotzdem versuchen:'
                  : 'Du kannst es trotzdem versuchen:',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const ValueKey('task-import-force-steps'),
                  onPressed: _busy ? null : () => _build(force: InteractiveKind.steps),
                  child: const Text('Als Rechenweg'),
                ),
                OutlinedButton(
                  key: const ValueKey('task-import-force-gantt'),
                  onPressed: _busy ? null : () => _build(force: InteractiveKind.gantt),
                  child: const Text('Als Terminierung'),
                ),
              ],
            ),
          ],
        ),
      );

  List<Widget> _draftViews(AppColors c) {
    final kind = _kind!;
    return [
      const SizedBox(height: 20),
      Row(
        children: [
          Icon(kind == InteractiveKind.steps ? Icons.functions : Icons.view_timeline_outlined, color: c.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Vorschau · ${kind.label}',
                key: const ValueKey('task-import-draft'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        kind == InteractiveKind.steps
            ? 'Prüf die Schritte und erwarteten Antworten. Die App setzt jede Antwort selbst ein und meldet Widersprüche.'
            : 'Vergleiche Teile, Dauern und Termine mit dem Blatt – die Musterlösung rechnet die App bei jeder Änderung neu.',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('task-import-front'),
        controller: _front,
        minLines: 2,
        maxLines: 12,
        decoration: const InputDecoration(labelText: 'Aufgabe (wie im Dokument)', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 14),
      if (kind == InteractiveKind.steps && _steps != null)
        StepTaskEditor(
          key: ValueKey('task-import-steps-$_revision'),
          task: _steps!,
          onChanged: (t) => setState(() => _steps = t),
        ),
      if (kind == InteractiveKind.gantt && _gantt != null)
        GanttTaskEditor(
          key: ValueKey('task-import-gantt-$_revision'),
          task: _gantt!,
          onChanged: (t) => setState(() => _gantt = t),
        ),
      if (kind == InteractiveKind.steps) ...[
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('task-import-back'),
          controller: _back,
          minLines: 2,
          maxLines: 14,
          decoration: const InputDecoration(
            labelText: 'Lösungsweg als Text (für „Lösung ansehen“)',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        if (_images.isNotEmpty)
          SwitchListTile(
            key: const ValueKey('task-import-attach-image'),
            contentPadding: EdgeInsets.zero,
            value: _attachImage,
            onChanged: (v) => setState(() => _attachImage = v),
            title: const Text('Foto bei der Aufgabe anzeigen'),
            subtitle: const Text('Sinnvoll, wenn eine Skizze oder Tabelle zur Aufgabe gehört.'),
          ),
      ],
      if (widget.replaceCard != null)
        CheckboxListTile(
          key: const ValueKey('task-import-remove-replaced'),
          contentPadding: EdgeInsets.zero,
          value: _removeReplaced,
          onChanged: (v) => setState(() => _removeReplaced = v ?? false),
          title: const Text('Aus dem Aufgaben-Ordner entfernen'),
          subtitle: const Text('Sonst bleibt die Aufgabe zusätzlich dort mit ihrer Erklärung.'),
        ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('task-import-try'),
            onPressed: _saving ? null : _try,
            icon: const Icon(Icons.play_arrow_outlined, size: 18),
            label: const Text('Ausprobieren'),
          ),
          FilledButton.icon(
            key: const ValueKey('task-import-save'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, size: 18),
            label: const Text('Speichern'),
          ),
        ],
      ),
    ];
  }
}

/// Die Aufgabe so lösen, wie sie später im Quiz erscheint – ohne dass etwas
/// gespeichert oder bewertet wird. Gibt eine kurze Rückmeldung zurück.
class _TryTaskScreen extends StatelessWidget {
  const _TryTaskScreen({required this.card});

  final Flashcard card;

  static String _outcome({Grade? selfGrade, bool? isCorrect}) {
    if (isCorrect == false || selfGrade == Grade.again) return 'Ausprobiert: wäre als „Nochmal“ gewertet worden.';
    if (selfGrade == Grade.hard) return 'Ausprobiert: wäre als „Schwer“ gewertet worden.';
    return 'Ausprobiert: wäre als gewusst gewertet worden.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    void done({Grade? selfGrade, bool? isCorrect}) =>
        Navigator.of(context).pop(_outcome(selfGrade: selfGrade, isCorrect: isCorrect));
    final steps = card.type == QuestionType.steps ? StepTask.fromMap(card.taskData) : null;
    final gantt = card.type == QuestionType.gantt ? GanttTask.fromMap(card.taskData) : null;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Ausprobieren')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: steps != null
                  ? StepTaskView(card: card, task: steps, isNew: true, onComplete: done)
                  : gantt != null
                      ? GanttTaskView(card: card, task: gantt, isNew: true, onComplete: done)
                      : const Center(child: Text('Die Aufgabe ist noch nicht vollständig.')),
            ),
          ),
        ),
      ),
    );
  }
}
