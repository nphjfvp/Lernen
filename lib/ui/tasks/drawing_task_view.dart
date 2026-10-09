import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/drawing_task.dart';
import '../../models/flashcard.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/image_crop.dart';
import '../../theme/app_colors.dart';
import '../study/study_aids.dart';
import '../widgets/math_text.dart';
import '../widgets/safe_set_state.dart';
import '../widgets/zoomable_image.dart';
import 'drawing_canvas.dart';

/// Freihand zeichnen ([QuestionType.drawing]): je Fläche zeichnen oder ein
/// Foto der Papier-Skizze hochladen; „Von der KI prüfen lassen“ schickt die
/// Bilder mit den Kriterien an das Bild-Modell, „Selbst prüfen“ zeigt die
/// Kriterien zum Abhaken. Die Kriterien bleiben bis zur Prüfung verborgen.
///
/// Bewertung beim "Weiter": im ersten Versuch bestanden = gewusst, nach einem
/// Fehlversuch Schwer; Lösung angesehen, selbst nicht bestanden oder
/// aufgelöst = Nochmal. Probeklausur: keine Rückmeldung, "Antwort abgeben"
/// lässt die KI bewerten (ohne KI selbst abhaken).
class DrawingTaskView extends StatefulWidget {
  const DrawingTaskView({
    super.key,
    required this.card,
    required this.task,
    required this.isNew,
    required this.onComplete,
    this.examMode = false,
    this.onSkip,
    this.canGiveUp = false,
  });

  final Flashcard card;
  final DrawingTask task;
  final bool isNew;
  final bool examMode;
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;
  final VoidCallback? onSkip;
  final bool canGiveUp;

  /// Test-Hooks: KI (statt OpenRouter mit dem Bild-Modell), Foto-Auswahl und
  /// Umwandlung der Striche in ein Bild.
  static AiService? Function(String apiKey, String model)? aiFactory;
  static Future<Uint8List?> Function()? pickPhotoHook;
  static Future<Uint8List?> Function(List<DrawingStroke> strokes)? renderHook;

  @override
  State<DrawingTaskView> createState() => _DrawingTaskViewState();
}

class _DrawingTaskViewState extends State<DrawingTaskView> with SafeSetState<DrawingTaskView> {
  late final List<String> _surfaces = widget.task.surfaces;
  late final Map<String, List<DrawingStroke>> _strokes = {for (final s in _surfaces) s: []};
  final Map<String, Uint8List> _photos = {};
  late String _current = _surfaces.first;

  DrawingReview? _review;
  bool _selfCheck = false;
  final Set<int> _ticks = {};
  bool _busy = false;
  String? _error;
  bool _solved = false;
  bool _revealed = false;
  bool _gaveUp = false;
  bool _submitted = false;
  int _wrong = 0;

  DrawingTask get _task => widget.task;
  bool get _finished => _solved || _revealed || _gaveUp;

  bool _hasContent(String s) => _photos[s] != null || (_strokes[s]?.isNotEmpty ?? false);

  AiService? _ai() {
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings == null || !settings.hasApiKey) return null;
    return DrawingTaskView.aiFactory?.call(settings.openRouterApiKey!, settings.visionModelId) ??
        AiService(apiKey: settings.openRouterApiKey!, model: settings.visionModelId);
  }

  void _submit({Grade? selfGrade, bool? isCorrect}) {
    if (_submitted) return;
    _submitted = true;
    widget.onComplete(selfGrade: selfGrade, isCorrect: isCorrect);
  }

  void _finish() {
    if (_gaveUp || _revealed) return _submit(isCorrect: false);
    if (_wrong == 0) return _submit(isCorrect: true);
    _submit(isCorrect: true, selfGrade: Grade.hard);
  }

  void _changed() {
    _review = null;
    _error = null;
  }

  Future<void> _pickPhoto() async {
    Uint8List? bytes;
    final hook = DrawingTaskView.pickPhotoHook;
    if (hook != null) {
      bytes = await hook();
    } else {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      bytes = await files.first.readAsBytes();
    }
    if (bytes == null) return;
    final prepared = await prepareImageForAi(bytes);
    setState(() {
      _photos[_current] = prepared;
      _changed();
    });
  }

  Future<Uint8List?> _render(List<DrawingStroke> strokes) =>
      DrawingTaskView.renderHook?.call(strokes) ?? renderDrawingPng(strokes);

  /// Lässt die Bild-KI die Zeichnung bewerten.
  Future<void> _checkWithAi() async {
    final ai = _ai();
    if (ai == null) {
      setState(
        () => _error =
            'Für die KI-Prüfung braucht die App deinen OpenRouter-Key (Einstellungen) – '
            'oder prüf selbst anhand der Kriterien.',
      );
      return;
    }
    final empty = [
      for (final s in _surfaces)
        if (!_hasContent(s)) s,
    ];
    if (empty.length == _surfaces.length) {
      setState(() => _error = 'Zeichne zuerst etwas – oder lade ein Foto deiner Skizze hoch.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final images = <({String panel, Uint8List image})>[];
      for (final s in _surfaces) {
        if (!_hasContent(s)) continue;
        final image = _photos[s] ?? await _render(_strokes[s]!);
        if (image != null) images.add((panel: s, image: image));
      }
      final review = await ai.reviewDrawing(task: widget.card.front, drawing: _task, images: images);
      if (!mounted) return;
      final passed = review.passes(_task);
      if (widget.examMode) {
        _submit(isCorrect: passed);
        return;
      }
      setState(() {
        _review = review;
        _selfCheck = false;
        if (passed) {
          _solved = true;
        } else {
          _wrong++;
        }
      });
    } on AiServiceException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Die Prüfung hat nicht geklappt: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Selbst abhaken: Kriterien (vorbelegt mit dem KI-Urteil) und Musterlösung.
  void _startSelfCheck() => setState(() {
    _selfCheck = true;
    _ticks
      ..clear()
      ..addAll([
        for (var i = 0; i < _task.criteria.length; i++)
          if (_review != null && i < _review!.marks.length && _review!.marks[i] == DrawingMark.met) i,
      ]);
  });

  void _rateSelf() {
    final passed = [
      for (final (i, c) in _task.criteria.indexed)
        if (c.required) _ticks.contains(i),
    ].every((b) => b);
    if (widget.examMode) return _submit(isCorrect: passed);
    setState(() {
      _selfCheck = false;
      if (passed) {
        _solved = true;
      } else {
        // Die Kriterien waren schon zu sehen – ein neuer Versuch zählt nicht mehr.
        _revealed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = widget.card;
    final strokes = _strokes[_current]!;
    final photo = _photos[_current];
    final locked = _finished || _busy;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (widget.isNew)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(20)),
              child: Text(
                'NEU',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.warn),
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      QuestionType.drawing.label,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accentOnSoft),
                    ),
                  ),
                  const Spacer(),
                  if (!widget.examMode) SourceLinkButton(card: card),
                ],
              ),
              const SizedBox(height: 10),
              if (card.imageBase64 != null) _image(card.imageBase64!),
              MathText(card.front, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.45)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_surfaces.length > 1) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, s) in _surfaces.indexed)
                ChoiceChip(
                  key: ValueKey('drawing-panel-$i'),
                  selected: s == _current,
                  showCheckmark: false,
                  avatar: _hasContent(s) ? Icon(Icons.edit, size: 15, color: c.accent) : null,
                  label: Text(s),
                  onSelected: (_) => setState(() => _current = s),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        DrawingCanvas(
          key: const ValueKey('drawing-canvas'),
          strokes: strokes,
          photo: photo,
          onStrokeStart: locked
              ? null
              : (p) => setState(() {
                  strokes.add([p]);
                  _changed();
                }),
          onStrokeUpdate: locked ? null : (p) => setState(() => strokes.isEmpty ? null : strokes.last.add(p)),
          onStrokeEnd: () {},
        ),
        if (!locked)
          Wrap(
            spacing: 4,
            children: [
              if (photo == null) ...[
                TextButton.icon(
                  key: const ValueKey('drawing-undo'),
                  onPressed: strokes.isEmpty ? null : () => setState(() => strokes.removeLast()),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Rückgängig'),
                ),
                TextButton.icon(
                  key: const ValueKey('drawing-clear'),
                  onPressed: strokes.isEmpty ? null : () => setState(strokes.clear),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Leeren'),
                ),
                TextButton.icon(
                  key: const ValueKey('drawing-photo'),
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Foto statt Zeichnung'),
                ),
              ] else
                TextButton.icon(
                  key: const ValueKey('drawing-photo-remove'),
                  onPressed: () => setState(() {
                    _photos.remove(_current);
                    _changed();
                  }),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Foto entfernen, selbst zeichnen'),
                ),
            ],
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('drawing-error'),
            child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 13)),
          ),
        ],
        if (_review != null && !widget.examMode) ...[const SizedBox(height: 10), _reviewBox(c, _review!)],
        if (_selfCheck) ...[const SizedBox(height: 10), _selfCheckBox(c)],
        if ((_revealed || _gaveUp) && !_selfCheck) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('drawing-solution'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(14)),
            child: MathText(
              '${_gaveUp ? 'Aufgelöst – zählt als nicht gewusst.' : 'Lösung angesehen – zählt als „Nochmal“.'}\n'
              '${_task.solutionText()}',
              style: const TextStyle(fontSize: 13.5, height: 1.45),
            ),
          ),
        ],
        const SizedBox(height: 12),
        ..._buttons(c),
      ],
    );
  }

  Widget _image(String base64) {
    try {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ZoomableImage(bytes: base64Decode(base64)),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  String _criterionLabel(DrawingCriterion cr) =>
      '${cr.panel.isEmpty || _surfaces.length < 2 ? '' : '${cr.panel}: '}${cr.text}${cr.required ? '' : ' (optional)'}';

  Widget _reviewBox(AppColors c, DrawingReview review) {
    final passed = review.passes(_task);
    return Container(
      key: const ValueKey('drawing-review'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: passed ? c.goodSoft : c.dangerSoft, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            passed ? 'Die KI erkennt alle wichtigen Merkmale.' : 'Noch nicht alles zu erkennen:',
            style: TextStyle(fontWeight: FontWeight.w700, color: passed ? c.good : c.danger),
          ),
          const SizedBox(height: 6),
          for (final (i, cr) in _task.criteria.indexed)
            Padding(
              key: ValueKey('drawing-result-$i'),
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (review.marks[i]) {
                      DrawingMark.met => Icons.check_circle,
                      DrawingMark.missing => Icons.cancel,
                      DrawingMark.unclear => Icons.help_outline,
                    },
                    size: 18,
                    color: switch (review.marks[i]) {
                      DrawingMark.met => c.good,
                      DrawingMark.missing => c.danger,
                      DrawingMark.unclear => c.warn,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      review.comments[i].isEmpty
                          ? _criterionLabel(cr)
                          : '${_criterionLabel(cr)} – ${review.comments[i]}',
                      style: const TextStyle(fontSize: 13.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          if (review.feedback.isNotEmpty) ...[
            const SizedBox(height: 4),
            MathText(review.feedback, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink)),
          ],
          if (!passed && !_finished)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Ergänze die Zeichnung und lass sie noch einmal prüfen – oder prüf selbst, wenn die KI etwas übersehen hat.',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted),
              ),
            ),
        ],
      ),
    );
  }

  // Material statt Container: die CheckboxListTiles malen auf dem nächsten Material.
  Widget _selfCheckBox(AppColors c) => Material(
    key: const ValueKey('drawing-self-box'),
    color: c.surfaceAlt,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Was zeigt deine Zeichnung? Hak ehrlich ab.', style: TextStyle(fontWeight: FontWeight.w700)),
          if (_task.solution.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            MathText(_task.solution.trim(), style: TextStyle(fontSize: 13.5, height: 1.4, color: c.inkMuted)),
          ],
          const SizedBox(height: 6),
          for (final (i, cr) in _task.criteria.indexed)
            CheckboxListTile(
              key: ValueKey('drawing-tick-$i'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _ticks.contains(i),
              title: Text(_criterionLabel(cr)),
              onChanged: (v) => setState(() => v == true ? _ticks.add(i) : _ticks.remove(i)),
            ),
          const SizedBox(height: 6),
          FilledButton(
            key: const ValueKey('drawing-self-done'),
            onPressed: _rateSelf,
            child: Text(widget.examMode ? 'Antwort abgeben' : 'Bewerten'),
          ),
        ],
      ),
    ),
  );

  List<Widget> _buttons(AppColors c) {
    if (widget.examMode) {
      if (_selfCheck) return const [];
      return [
        FilledButton(
          key: const ValueKey('drawing-submit'),
          onPressed: _busy ? null : () => _ai() == null ? _startSelfCheck() : _checkWithAi(),
          child: Text(_busy ? 'Wird geprüft …' : 'Antwort abgeben'),
        ),
      ];
    }
    if (_finished) {
      final clean = _solved && _wrong == 0;
      return [
        if (!_selfCheck) ...[
          Container(
            key: const ValueKey('drawing-finished'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _solved ? (clean ? c.goodSoft : c.accentSoft) : c.warnSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _gaveUp
                  ? 'Aufgelöst – zählt als nicht gewusst'
                  : !_solved
                  ? 'Nicht alles getroffen – zählt als „Nochmal“'
                  : (clean ? 'Geschafft – ohne Hilfe' : 'Geschafft – im zweiten Anlauf, zählt als „Schwer“'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(key: const ValueKey('drawing-next'), onPressed: _finish, child: const Text('Weiter')),
        ],
      ];
    }
    if (_selfCheck) return const [];
    return [
      Row(
        children: [
          OutlinedButton.icon(
            key: const ValueKey('drawing-self'),
            onPressed: _busy ? null : _startSelfCheck,
            icon: const Icon(Icons.checklist, size: 18),
            label: const Text('Selbst prüfen'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('drawing-check'),
              onPressed: _busy ? null : _checkWithAi,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_busy ? 'KI prüft …' : 'Von der KI prüfen lassen'),
            ),
          ),
        ],
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton(
            key: const ValueKey('drawing-reveal'),
            onPressed: _busy ? null : () => setState(() => _revealed = true),
            child: const Text('Lösung zeigen'),
          ),
          if (widget.onSkip != null)
            TextButton(
              key: const ValueKey('question-skip'),
              onPressed: () {
                if (_submitted) return;
                _submitted = true;
                widget.onSkip!();
              },
              child: const Text('Überspringen'),
            ),
          if (widget.canGiveUp)
            TextButton(
              key: const ValueKey('question-give-up'),
              onPressed: () => setState(() => _gaveUp = true),
              child: const Text('Auflösen'),
            ),
        ],
      ),
    ];
  }
}
