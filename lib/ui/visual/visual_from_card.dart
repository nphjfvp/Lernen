import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/flashcard.dart';
import '../../models/visual_lesson.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/visual_lesson_repository.dart';
import '../../services/ai_service.dart';
import '../../services/visual_math.dart';
import '../../theme/app_colors.dart';
import '../study/study_aids.dart';
import 'visual_lesson_screen.dart';

/// „Visuell erklären“ zu einer Frage: Die KI baut aus Frage, Lösung und der
/// Stelle im Skript eine Lektion wie in „Visuell lernen“ (Animation,
/// Schritte, Übung). Sie wird im Fach gespeichert und gehört zur Frage – gibt
/// es schon eine, lässt sie sich direkt öffnen.
Future<void> openVisualForCard(BuildContext context, Flashcard card) async {
  final lesson = await showDialog<VisualLesson>(
    context: context,
    barrierDismissible: false,
    builder: (_) => VisualFromCardDialog(card: card),
  );
  if (lesson == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VisualLessonScreen(lesson: lesson)));
}

/// Auswahl (Erklären/Sokratisch) und Fortschritt; gibt die Lektion zurück.
class VisualFromCardDialog extends StatefulWidget {
  const VisualFromCardDialog({super.key, required this.card});

  final Flashcard card;

  /// Test-Hook statt OpenRouter.
  static AiService? Function(String apiKey, String model)? aiFactory;

  @override
  State<VisualFromCardDialog> createState() => _VisualFromCardDialogState();
}

class _VisualFromCardDialogState extends State<VisualFromCardDialog> {
  VisualStyle _style = VisualStyle.explain;
  VisualLesson? _existing;
  bool _checked = false;
  bool _busy = false;
  String _progress = '';
  String? _error;

  Flashcard get _card => widget.card;

  @override
  void initState() {
    super.initState();
    final repo = context.read<VisualLessonRepository>();
    repo.forCard(_card.id).then((l) {
      if (mounted) {
        setState(() {
          _existing = l;
          _checked = true;
        });
      }
    });
  }

  Uint8List? get _image {
    final encoded = _card.imageBase64;
    if (encoded == null) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  AiService? _ai({required bool vision}) {
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings == null || !settings.hasApiKey) return null;
    final model = vision ? settings.visionModelId : settings.questionModelId;
    return VisualFromCardDialog.aiFactory?.call(settings.openRouterApiKey!, model) ??
        AiService(apiKey: settings.openRouterApiKey!, model: model);
  }

  Future<void> _create() async {
    final image = _image;
    final ai = _ai(vision: image != null);
    if (ai == null) {
      setState(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final repo = context.read<VisualLessonRepository>();
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Stelle im Skript wird gesucht …';
    });
    try {
      final source = await findCardSource(context, _card);
      if (!mounted) return;
      setState(() => _progress = 'Die KI baut die visuelle Erklärung …');
      final explanation = _card.back.trim();
      final answer = answerTextOf(_card).trim();
      final raws = await ai.generateVisualLessons(
        topic: [
          'Erkläre diese Lernfrage visuell, so dass man sie wirklich versteht – das Thema dahinter, warum die '
              'Lösung stimmt und wie man selbst darauf kommt. Die Übung am Ende ist eine ähnliche, neue Aufgabe.',
          'Frage: ${_card.promptText}',
          if (answer.isNotEmpty) 'Richtige Lösung: $answer',
          if (explanation.isNotEmpty && explanation != answer) 'Erklärung/Lösungsweg: $explanation',
        ].join('\n'),
        material: source == null || source.pageText.trim().isEmpty
            ? ''
            : '--- ${source.material.fileName}, Seite ${source.page} ---\n${source.pageText.trim()}',
        images: [?image],
        socratic: _style == VisualStyle.socratic,
      );
      final front = _card.front.trim().replaceAll(RegExp(r'\s+'), ' ');
      final lesson = [
        for (final raw in raws)
          ?VisualLesson.fromMap(
            raw,
            id: const Uuid().v4(),
            moduleId: _card.moduleId,
            createdAt: DateTime.now(),
            source: 'Frage: ${front.length > 60 ? '${front.substring(0, 60)}…' : front}',
            style: _style,
            cardId: _card.id,
          ),
      ].map(VisualMath.sanitize).where((l) => l.isUsable).firstOrNull;
      if (lesson == null) {
        throw AiServiceException('Die KI-Antwort ließ sich nicht als Lektion lesen – bitte erneut versuchen.');
      }
      await repo.save(lesson);
      if (mounted) Navigator.of(context).pop(lesson);
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final existing = _existing;
    return AlertDialog(
      key: const ValueKey('card-visual-dialog'),
      title: const Text('Visuell erklären'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              existing != null
                  ? 'Zu dieser Frage gibt es schon eine visuelle Erklärung („${existing.title}“). Du kannst sie öffnen '
                        'oder eine neue erstellen lassen.'
                  : 'Die KI baut aus der Frage, ihrer Lösung und der Stelle im Skript eine animierte Erklärung mit '
                        'Übung. Sie wird im Fach unter „Visuell lernen“ gespeichert.',
              style: TextStyle(color: c.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 12),
            SegmentedButton<VisualStyle>(
              key: const ValueKey('card-visual-style'),
              segments: const [
                ButtonSegment(value: VisualStyle.explain, label: Text('Erklären')),
                ButtonSegment(value: VisualStyle.socratic, label: Text('Sokratisch')),
              ],
              selected: {_style},
              showSelectedIcon: false,
              onSelectionChanged: _busy ? null : (s) => setState(() => _style = s.first),
            ),
            if (_busy) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_progress, key: const ValueKey('card-visual-progress'))),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('card-visual-error'),
                style: TextStyle(color: c.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('card-visual-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        if (existing != null)
          TextButton(
            key: const ValueKey('card-visual-open'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(existing),
            child: const Text('Öffnen'),
          ),
        FilledButton(
          key: const ValueKey('card-visual-create'),
          onPressed: _busy || !_checked ? null : _create,
          child: Text(existing != null ? 'Neu erstellen' : 'Erstellen'),
        ),
      ],
    );
  }
}
