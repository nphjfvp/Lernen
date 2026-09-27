import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../services/image_edit.dart';
import '../../theme/app_colors.dart';
import 'relative_image.dart';

/// Welche Ziele der Bild-Editor zusätzlich setzen lässt (für Bildfragen).
enum ImageTargetMode {
  /// Stellen mit Beschriftung ([QuestionType.diagramLabel]).
  labels,

  /// Bereiche, in die getippt werden muss ([QuestionType.markImage]).
  regions,
}

/// Ergebnis des Bild-Editors: das (ggf. bearbeitete) Bild und die Ziele.
class ImageEditResult {
  const ImageEditResult({required this.bytes, required this.targets, required this.imageChanged});

  final Uint8List bytes;
  final List<ImageTarget> targets;

  /// false, wenn nichts abgedeckt oder beschriftet wurde.
  final bool imageChanged;
}

/// Öffnet den Bild-Editor bildschirmfüllend. `null` bei Abbruch.
Future<ImageEditResult?> showImageEditor(
  BuildContext context,
  Uint8List bytes, {
  ImageTargetMode? targetMode,
  List<ImageTarget> targets = const [],
  String title = 'Bild bearbeiten',
}) {
  return Navigator.of(context).push<ImageEditResult>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ImageEditorScreen(bytes: bytes, targetMode: targetMode, initialTargets: targets, title: title),
  ));
}

enum _Tool { cover, text, target }

/// Bild bearbeiten: Stellen abdecken (weiß oder schwarz – z.B. Beschriftungen,
/// die sonst die Antwort verraten), Text daraufschreiben und – für Bildfragen –
/// die Stellen mit ihrer Beschriftung bzw. die richtigen Bereiche setzen.
/// Abdeckungen und Text werden beim Übernehmen fest ins Bild eingerechnet,
/// die Ziele nicht (die zeigt erst das Quiz).
class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({
    super.key,
    required this.bytes,
    this.targetMode,
    this.initialTargets = const [],
    this.title = 'Bild bearbeiten',
  });

  final Uint8List bytes;
  final ImageTargetMode? targetMode;
  final List<ImageTarget> initialTargets;
  final String title;

  /// Kleinere Rechtecke gelten als versehentliches Antippen.
  static const minSide = 0.015;

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  final List<ImageEdit> _edits = [];
  late final List<ImageTarget> _targets = [...widget.initialTargets];

  /// Reihenfolge der Änderungen für "Rückgängig" (ImageEdit oder ImageTarget).
  final List<Object> _history = [];

  late _Tool _tool = widget.targetMode == null ? _Tool.cover : _Tool.target;
  bool _dark = false;
  Offset? _dragStart;
  Rect? _dragRect;
  bool _saving = false;

  bool get _drawsRect => _tool == _Tool.cover || (_tool == _Tool.target && widget.targetMode == ImageTargetMode.regions);

  String get _hint => switch (_tool) {
        _Tool.cover => 'Rahmen über die Stelle ziehen, die abgedeckt werden soll.',
        _Tool.text => 'Auf die Stelle tippen, an die der Text soll.',
        _Tool.target => widget.targetMode == ImageTargetMode.labels
            ? 'Auf jede Stelle tippen, die beschriftet werden soll, und die Beschriftung eingeben. '
                'Eine gesetzte Stelle antippen zum Ändern.'
            : 'Rahmen um die richtige Stelle ziehen. Einen Bereich antippen zum Entfernen.',
      };

  void _onPanStart(Offset p) {
    if (!_drawsRect) return;
    setState(() {
      _dragStart = p;
      _dragRect = Rect.fromPoints(p, p);
    });
  }

  void _onPanUpdate(Offset p) {
    final start = _dragStart;
    if (start == null) return;
    setState(() => _dragRect = Rect.fromPoints(start, p));
  }

  void _onPanEnd() {
    final rect = _dragRect;
    setState(() {
      _dragStart = null;
      _dragRect = null;
    });
    if (rect == null || rect.width < ImageEditorScreen.minSide || rect.height < ImageEditorScreen.minSide) return;
    setState(() {
      if (_tool == _Tool.cover) {
        final edit = CoverEdit(rect, dark: _dark);
        _edits.add(edit);
        _history.add(edit);
      } else {
        final target = ImageTarget(x: rect.center.dx, y: rect.center.dy, w: rect.width, h: rect.height);
        _targets.add(target);
        _history.add(target);
      }
    });
  }

  Future<void> _onTap(Offset p) async {
    switch (_tool) {
      case _Tool.cover:
        return;
      case _Tool.text:
        final text = await _askText(title: 'Text', label: 'Text auf dem Bild');
        if (text == null) return;
        final edit = TextEdit(p, text);
        setState(() {
          _edits.add(edit);
          _history.add(edit);
        });
      case _Tool.target:
        final index = _targetAt(p);
        if (widget.targetMode == ImageTargetMode.regions) {
          if (index != null) setState(() => _history.remove(_targets.removeAt(index)));
          return;
        }
        if (index != null) {
          await _editLabel(index);
          return;
        }
        final label = await _askText(title: 'Stelle ${_targets.length + 1}', label: 'Beschriftung');
        if (label == null) return;
        final target = ImageTarget(x: p.dx, y: p.dy, label: label);
        setState(() {
          _targets.add(target);
          _history.add(target);
        });
    }
  }

  /// Index des Ziels an [p] (Beschriften: in der Nähe der Stelle,
  /// Markieren: im Bereich), sonst null.
  int? _targetAt(Offset p) {
    for (var i = _targets.length - 1; i >= 0; i--) {
      final t = _targets[i];
      final hit = widget.targetMode == ImageTargetMode.regions
          ? t.contains(p.dx, p.dy, tolerance: 0)
          : (Offset(t.x, t.y) - p).distance < 0.05;
      if (hit) return i;
    }
    return null;
  }

  Future<void> _editLabel(int index) async {
    final target = _targets[index];
    final controller = TextEditingController(text: target.label);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stelle ${index + 1}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Beschriftung'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop('\u0000delete'), child: const Text('Entfernen')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result == '\u0000delete') {
        _history.remove(_targets.removeAt(index));
      } else if (result.isNotEmpty) {
        final updated = target.copyWith(label: result);
        _targets[index] = updated;
        final h = _history.indexOf(target);
        if (h >= 0) _history[h] = updated;
      }
    });
  }

  Future<String?> _askText({required String title, required String label}) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    return (text == null || text.isEmpty) ? null : text;
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      final last = _history.removeLast();
      if (last is ImageEdit) {
        _edits.remove(last);
      } else {
        _targets.remove(last);
      }
    });
  }

  String? get _missingTargets => switch (widget.targetMode) {
        ImageTargetMode.labels when !_targets.any((t) => t.label.isNotEmpty) =>
          'Setz mindestens eine Stelle mit Beschriftung.',
        ImageTargetMode.regions when _targets.isEmpty => 'Zieh einen Rahmen um die richtige Stelle.',
        _ => null,
      };

  Future<void> _apply() async {
    final missing = _missingTargets;
    if (missing != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(missing)));
      return;
    }
    setState(() => _saving = true);
    final bytes = await applyImageEdits(widget.bytes, List.of(_edits));
    if (!mounted) return;
    setState(() => _saving = false);
    if (bytes == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Das Bild konnte nicht bearbeitet werden.')));
      return;
    }
    Navigator.of(context).pop(ImageEditResult(bytes: bytes, targets: List.of(_targets), imageChanged: _edits.isNotEmpty));
  }

  List<Widget> _overlay(BuildContext context, Size box) {
    final c = context.colors;
    Rect scaled(Rect r) => Rect.fromLTRB(r.left * box.width, r.top * box.height, r.right * box.width, r.bottom * box.height);
    final drag = _dragRect;
    return [
      for (final edit in _edits)
        switch (edit) {
          CoverEdit() => Positioned.fromRect(
              rect: scaled(edit.rect),
              child: IgnorePointer(child: ColoredBox(color: edit.color)),
            ),
          TextEdit() => positionedAt(
              box: box,
              x: edit.position.dx,
              y: edit.position.dy,
              child: IgnorePointer(
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: edit.size * box.height * 0.3, vertical: edit.size * box.height * 0.15),
                  decoration: BoxDecoration(
                    color: TextEdit.backgroundColor,
                    borderRadius: BorderRadius.circular(edit.size * box.height * 0.25),
                  ),
                  child: Text(
                    edit.text,
                    style: TextStyle(
                      color: TextEdit.textColor,
                      fontSize: edit.size * box.height,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        },
      if (widget.targetMode == ImageTargetMode.regions)
        for (final t in _targets)
          Positioned.fromRect(
            rect: scaled(Rect.fromCenter(center: Offset(t.x, t.y), width: t.w, height: t.h)),
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: c.good.withAlpha(50),
                  border: Border.all(color: c.good, width: 3),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
      if (widget.targetMode == ImageTargetMode.labels)
        for (final (i, t) in _targets.indexed)
          positionedAt(
            box: box,
            x: t.x,
            y: t.y,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(14)),
                child: Text('${i + 1} · ${t.label}',
                    style: TextStyle(color: c.accentInk, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      if (drag != null)
        Positioned.fromRect(
          rect: scaled(drag),
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: _tool == _Tool.cover ? (_dark ? Colors.black : Colors.white).withAlpha(200) : c.good.withAlpha(50),
                border: Border.all(color: c.accent, width: 2),
              ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = widget.targetMode;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Rückgängig',
            onPressed: _history.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: SegmentedButton<_Tool>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: _Tool.cover, icon: Icon(Icons.crop_square), label: Text('Abdecken')),
                  const ButtonSegment(value: _Tool.text, icon: Icon(Icons.text_fields), label: Text('Text')),
                  if (mode != null)
                    ButtonSegment(
                      value: _Tool.target,
                      icon: Icon(mode == ImageTargetMode.labels ? Icons.label_outline : Icons.ads_click),
                      label: Text(mode == ImageTargetMode.labels ? 'Stellen' : 'Bereich'),
                    ),
                ],
                selected: {_tool},
                onSelectionChanged: (s) => setState(() => _tool = s.first),
              ),
            ),
            if (_tool == _Tool.cover)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(label: const Text('Weiß'), selected: !_dark, onSelected: (_) => setState(() => _dark = false)),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text('Schwarz'), selected: _dark, onSelected: (_) => setState(() => _dark = true)),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(_hint, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: RelativeImage(
                    key: const ValueKey('image-editor-canvas'),
                    bytes: widget.bytes,
                    maxHeight: double.infinity,
                    onTapRelative: _onTap,
                    onPanStartRelative: _onPanStart,
                    onPanUpdateRelative: _onPanUpdate,
                    onPanEndRelative: _onPanEnd,
                    overlayBuilder: _overlay,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _apply,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Übernehmen'),
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
