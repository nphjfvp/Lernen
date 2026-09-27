import 'dart:math' as math;
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

/// Ergebnis des Bild-Editors: das (ggf. bearbeitete) Bild, die Ziele und die
/// Bearbeitungen selbst – wer sie aufhebt (zusammen mit dem Ausgangsbild),
/// kann sie später wieder einzeln verschieben oder entfernen.
class ImageEditResult {
  const ImageEditResult({
    required this.bytes,
    required this.targets,
    required this.imageChanged,
    this.edits = const [],
  });

  final Uint8List bytes;
  final List<ImageTarget> targets;

  /// false, wenn nichts abgedeckt oder beschriftet ist.
  final bool imageChanged;

  /// Abdeckungen und Texte, bezogen auf das Ausgangsbild.
  final List<ImageEdit> edits;
}

/// Öffnet den Bild-Editor bildschirmfüllend. `null` bei Abbruch. [edits]
/// sind schon vorhandene, noch bearbeitbare Abdeckungen/Texte auf [bytes]
/// (z.B. von der KI vorgeschlagene Abdeckungen).
Future<ImageEditResult?> showImageEditor(
  BuildContext context,
  Uint8List bytes, {
  ImageTargetMode? targetMode,
  List<ImageTarget> targets = const [],
  List<ImageEdit> edits = const [],
  String title = 'Bild bearbeiten',
}) {
  return Navigator.of(context).push<ImageEditResult>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ImageEditorScreen(
      bytes: bytes,
      targetMode: targetMode,
      initialTargets: targets,
      initialEdits: edits,
      title: title,
    ),
  ));
}

enum _Tool { cover, text, target }

enum _Kind { cover, text, target }

typedef _Selection = ({_Kind kind, int index});

enum _DragMode { create, move, resize }

/// Bild bearbeiten: Stellen abdecken (weiß oder schwarz – z.B. Beschriftungen,
/// die sonst die Antwort verraten), Text daraufschreiben und – für Bildfragen –
/// die Stellen mit ihrer Beschriftung bzw. die richtigen Bereiche setzen.
/// Alles bleibt bis zum Übernehmen einzeln bearbeitbar: ziehen verschiebt,
/// die Ecke eines ausgewählten Rahmens ändert die Größe, Antippen öffnet
/// Text/Beschriftung zum Ändern (inkl. Schriftgröße bzw. Gruppe). Abdeckungen
/// und Text werden beim Übernehmen fest ins Bild eingerechnet, die Ziele
/// nicht (die zeigt erst das Quiz).
class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({
    super.key,
    required this.bytes,
    this.targetMode,
    this.initialTargets = const [],
    this.initialEdits = const [],
    this.title = 'Bild bearbeiten',
  });

  final Uint8List bytes;
  final ImageTargetMode? targetMode;
  final List<ImageTarget> initialTargets;
  final List<ImageEdit> initialEdits;
  final String title;

  /// Kleinere Rechtecke gelten als versehentliches Antippen.
  static const minSide = 0.015;

  /// Schriftgröße (relativ zur Bildhöhe): Standard und Grenzen.
  static const defaultTextSize = 0.05;
  static const minTextSize = 0.02;
  static const maxTextSize = 0.15;

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  late final List<CoverEdit> _covers = [...widget.initialEdits.whereType<CoverEdit>()];
  late final List<TextEdit> _texts = [...widget.initialEdits.whereType<TextEdit>()];
  late final List<ImageTarget> _targets = [...widget.initialTargets];

  /// Stände vor jeder Änderung für "Rückgängig".
  final List<({List<CoverEdit> covers, List<TextEdit> texts, List<ImageTarget> targets})> _undoStack = [];

  late _Tool _tool = widget.targetMode == null ? _Tool.cover : _Tool.target;
  bool _dark = false;
  double _textSize = ImageEditorScreen.defaultTextSize;
  _Selection? _selected;
  bool _saving = false;

  /// Laufendes Ziehen: was passiert, wo es begann und der Ausgangszustand
  /// des gezogenen Objekts.
  _DragMode? _dragMode;
  Offset? _dragStart;
  Rect? _dragRect;
  Rect? _dragOriginRect;
  Offset? _dragOriginPoint;

  /// Zuletzt angezeigte Bildgröße in Pixeln – für Trefferflächen, die in
  /// Pixeln gedacht sind (Beschriftungs-Chips, Anfasser).
  Size _box = const Size(1, 1);

  bool get _labels => widget.targetMode == ImageTargetMode.labels;
  bool get _regions => widget.targetMode == ImageTargetMode.regions;

  bool get _createsRect => _tool == _Tool.cover || (_tool == _Tool.target && _regions);

  String get _hint => switch (_tool) {
        _Tool.cover => 'Rahmen über die Stelle ziehen, die abgedeckt werden soll. Antippen wählt eine Abdeckung aus – '
            'dann verschieben, an der Ecke die Größe ändern oder löschen.',
        _Tool.text => 'Auf die Stelle tippen, an die der Text soll. Text ziehen zum Verschieben, antippen zum '
            'Ändern (auch die Schriftgröße).',
        _Tool.target => _labels
            ? 'Auf jede Stelle tippen, die beschriftet werden soll. Stellen ziehen zum Verschieben, antippen zum '
                'Ändern – mit gleicher Gruppe werden Stellen austauschbar.'
            : 'Rahmen um die richtige Stelle ziehen. Antippen wählt einen Bereich aus – dann verschieben, an der '
                'Ecke die Größe ändern oder löschen.',
      };

  // -- Zustand ---------------------------------------------------------------

  void _pushUndo() {
    _undoStack.add((covers: List.of(_covers), texts: List.of(_texts), targets: List.of(_targets)));
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final last = _undoStack.removeLast();
    setState(() {
      _covers
        ..clear()
        ..addAll(last.covers);
      _texts
        ..clear()
        ..addAll(last.texts);
      _targets
        ..clear()
        ..addAll(last.targets);
      _selected = null;
    });
  }

  Rect _rectOf(_Selection sel) => switch (sel.kind) {
        _Kind.cover => _covers[sel.index].rect,
        _Kind.target => Rect.fromCenter(
            center: Offset(_targets[sel.index].x, _targets[sel.index].y),
            width: _targets[sel.index].w,
            height: _targets[sel.index].h,
          ),
        _Kind.text => Rect.fromCenter(center: _texts[sel.index].position, width: 0, height: 0),
      };

  bool _isRectSelection(_Selection? sel) =>
      sel != null && (sel.kind == _Kind.cover || (sel.kind == _Kind.target && _regions));

  void _setRect(_Selection sel, Rect rect) {
    final r = _clampRect(rect);
    switch (sel.kind) {
      case _Kind.cover:
        _covers[sel.index] = CoverEdit(r, dark: _covers[sel.index].dark);
      case _Kind.target:
        _targets[sel.index] =
            _targets[sel.index].copyWith(x: r.center.dx, y: r.center.dy, w: r.width, h: r.height);
      case _Kind.text:
        break;
    }
  }

  void _setPoint(_Selection sel, Offset p) {
    final c = Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0));
    switch (sel.kind) {
      case _Kind.text:
        final t = _texts[sel.index];
        _texts[sel.index] = TextEdit(c, t.text, size: t.size);
      case _Kind.target:
        _targets[sel.index] = _targets[sel.index].copyWith(x: c.dx, y: c.dy);
      case _Kind.cover:
        break;
    }
  }

  /// Hält einen Rahmen im Bild (verschiebt ihn nötigenfalls zurück).
  static Rect _clampRect(Rect r) {
    final w = math.min(r.width, 1.0);
    final h = math.min(r.height, 1.0);
    final left = r.left.clamp(0.0, 1.0 - w);
    final top = r.top.clamp(0.0, 1.0 - h);
    return Rect.fromLTWH(left, top, w, h);
  }

  // -- Treffer ---------------------------------------------------------------

  Offset _toPx(Offset rel) => Offset(rel.dx * _box.width, rel.dy * _box.height);

  /// Ungefähre Fläche eines Texts in Pixeln (für Antippen/Ziehen).
  Rect _textRectPx(TextEdit t) {
    final fontPx = t.size * _box.height;
    final width = math.max(24.0, t.text.length * fontPx * 0.6 + fontPx * 0.6);
    final height = math.max(24.0, fontPx * 1.4);
    return Rect.fromCenter(center: _toPx(t.position), width: width, height: height);
  }

  /// Fläche eines Beschriftungs-Chips ("1 · Zellkern") in Pixeln.
  Rect _labelRectPx(int index) {
    final t = _targets[index];
    final text = _chipText(index);
    return Rect.fromCenter(center: _toPx(Offset(t.x, t.y)), width: math.max(40.0, text.length * 7.5 + 20), height: 30);
  }

  String _chipText(int index) {
    final t = _targets[index];
    return t.group.isEmpty ? '${index + 1} · ${t.label}' : '${index + 1} · ${t.label} [${t.group}]';
  }

  bool _nearHandle(_Selection sel, Offset p) {
    final corner = _toPx(_rectOf(sel).bottomRight);
    return (corner - _toPx(p)).distance < 22;
  }

  /// Oberstes Objekt an [p] (Ziele über Texten über Abdeckungen).
  _Selection? _hitTest(Offset p) {
    final px = _toPx(p);
    if (widget.targetMode != null) {
      for (var i = _targets.length - 1; i >= 0; i--) {
        final hit = _regions ? _targets[i].contains(p.dx, p.dy, tolerance: 0) : _labelRectPx(i).contains(px);
        if (hit) return (kind: _Kind.target, index: i);
      }
    }
    for (var i = _texts.length - 1; i >= 0; i--) {
      if (_textRectPx(_texts[i]).contains(px)) return (kind: _Kind.text, index: i);
    }
    for (var i = _covers.length - 1; i >= 0; i--) {
      if (_covers[i].rect.contains(p)) return (kind: _Kind.cover, index: i);
    }
    return null;
  }

  // -- Gesten ----------------------------------------------------------------

  void _onPanStart(Offset p) {
    final selected = _selected;
    if (_isRectSelection(selected) && _nearHandle(selected!, p)) {
      _pushUndo();
      _dragMode = _DragMode.resize;
      _dragOriginRect = _rectOf(selected);
      return;
    }
    final hit = _hitTest(p);
    if (hit != null) {
      _pushUndo();
      setState(() => _selected = hit);
      _dragMode = _DragMode.move;
      _dragStart = p;
      if (hit.kind == _Kind.text) {
        _dragOriginPoint = _texts[hit.index].position;
      } else if (hit.kind == _Kind.target && _labels) {
        _dragOriginPoint = Offset(_targets[hit.index].x, _targets[hit.index].y);
      } else {
        _dragOriginRect = _rectOf(hit);
      }
      return;
    }
    if (!_createsRect) return;
    setState(() {
      _selected = null;
      _dragMode = _DragMode.create;
      _dragStart = p;
      _dragRect = Rect.fromPoints(p, p);
    });
  }

  void _onPanUpdate(Offset p) {
    final selected = _selected;
    switch (_dragMode) {
      case _DragMode.create:
        final start = _dragStart;
        if (start != null) setState(() => _dragRect = Rect.fromPoints(start, p));
      case _DragMode.move:
        final start = _dragStart;
        if (start == null || selected == null) return;
        final delta = p - start;
        setState(() {
          final point = _dragOriginPoint;
          final rect = _dragOriginRect;
          if (point != null) {
            _setPoint(selected, point + delta);
          } else if (rect != null) {
            _setRect(selected, rect.shift(delta));
          }
        });
      case _DragMode.resize:
        final origin = _dragOriginRect;
        if (origin == null || selected == null) return;
        const minSide = 0.02;
        setState(() => _setRect(
              selected,
              Rect.fromLTRB(
                origin.left,
                origin.top,
                math.max(origin.left + minSide, p.dx),
                math.max(origin.top + minSide, p.dy),
              ),
            ));
      case null:
        return;
    }
  }

  void _onPanEnd() {
    final mode = _dragMode;
    final rect = _dragRect;
    _dragMode = null;
    _dragStart = null;
    _dragOriginPoint = null;
    _dragOriginRect = null;
    if (mode != _DragMode.create) return;
    setState(() => _dragRect = null);
    if (rect == null || rect.width < ImageEditorScreen.minSide || rect.height < ImageEditorScreen.minSide) return;
    _pushUndo();
    setState(() {
      if (_tool == _Tool.cover) {
        _covers.add(CoverEdit(_clampRect(rect), dark: _dark));
        _selected = (kind: _Kind.cover, index: _covers.length - 1);
      } else {
        final r = _clampRect(rect);
        _targets.add(ImageTarget(x: r.center.dx, y: r.center.dy, w: r.width, h: r.height));
        _selected = (kind: _Kind.target, index: _targets.length - 1);
      }
    });
  }

  Future<void> _onTap(Offset p) async {
    final hit = _hitTest(p);
    if (hit != null) {
      switch (hit.kind) {
        case _Kind.text:
          await _editText(hit.index);
        case _Kind.target when _labels:
          await _editLabel(hit.index);
        case _Kind.target:
        case _Kind.cover:
          setState(() => _selected = _selected == hit ? null : hit);
      }
      return;
    }
    if (_selected != null) {
      setState(() => _selected = null);
      return;
    }
    switch (_tool) {
      case _Tool.text:
        await _editText(null, at: p);
      case _Tool.target when _labels:
        await _editLabel(null, at: p);
      case _Tool.target:
      case _Tool.cover:
        return;
    }
  }

  // -- Dialoge ---------------------------------------------------------------

  /// Text anlegen ([index] null, an [at]) oder ändern: Inhalt, Schriftgröße,
  /// Entfernen.
  Future<void> _editText(int? index, {Offset? at}) async {
    final existing = index == null ? null : _texts[index];
    final controller = TextEditingController(text: existing?.text ?? '');
    var size = existing?.size ?? _textSize;
    final result = await showDialog<Object>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(existing == null ? 'Text' : 'Text ändern'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('editor-text-field'),
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Text auf dem Bild'),
              ),
              const SizedBox(height: 16),
              Text('Schriftgröße', style: Theme.of(ctx).textTheme.bodySmall),
              Slider(
                key: const ValueKey('editor-text-size'),
                value: size,
                min: ImageEditorScreen.minTextSize,
                max: ImageEditorScreen.maxTextSize,
                onChanged: (v) => setDialog(() => size = v),
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Entfernen')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop((text: controller.text.trim(), size: size)),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    _pushUndo();
    setState(() {
      if (result == false) {
        _texts.removeAt(index!);
        _selected = null;
        return;
      }
      final value = result as ({String text, double size});
      _textSize = value.size;
      if (value.text.isEmpty) {
        _undoStack.removeLast();
        return;
      }
      if (existing == null) {
        _texts.add(TextEdit(at!, value.text, size: value.size));
      } else {
        _texts[index!] = TextEdit(existing.position, value.text, size: value.size);
      }
    });
  }

  /// Stelle anlegen ([index] null, an [at]) oder ändern: Beschriftung,
  /// Gruppe (austauschbare Stellen), Entfernen.
  Future<void> _editLabel(int? index, {Offset? at}) async {
    final existing = index == null ? null : _targets[index];
    final label = TextEditingController(text: existing?.label ?? '');
    final group = TextEditingController(text: existing?.group ?? '');
    final groups = {for (final t in _targets) if (t.group.isNotEmpty) t.group}.toList();
    final number = index == null ? _targets.length + 1 : index + 1;
    final result = await showDialog<Object>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Stelle $number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('editor-label-field'),
                controller: label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Beschriftung'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('editor-group-field'),
                controller: group,
                decoration: const InputDecoration(
                  labelText: 'Gruppe (optional)',
                  helperText: 'Stellen derselben Gruppe sind austauschbar –\nz.B. „Input“ für mehrere Eingänge.',
                  helperMaxLines: 3,
                ),
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final g in groups)
                      ActionChip(label: Text(g), onPressed: () => setDialog(() => group.text = g)),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Entfernen')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop((label: label.text.trim(), group: group.text.trim())),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (result == false) {
      _pushUndo();
      setState(() {
        _targets.removeAt(index!);
        _selected = null;
      });
      return;
    }
    final value = result as ({String label, String group});
    if (value.label.isEmpty) return;
    _pushUndo();
    setState(() {
      if (existing == null) {
        _targets.add(ImageTarget(x: at!.dx, y: at.dy, label: value.label, group: value.group));
      } else {
        _targets[index!] = existing.copyWith(label: value.label, group: value.group);
      }
    });
  }

  void _deleteSelected() {
    final sel = _selected;
    if (sel == null) return;
    _pushUndo();
    setState(() {
      switch (sel.kind) {
        case _Kind.cover:
          _covers.removeAt(sel.index);
        case _Kind.text:
          _texts.removeAt(sel.index);
        case _Kind.target:
          _targets.removeAt(sel.index);
      }
      _selected = null;
    });
  }

  void _toggleSelectedColor() {
    final sel = _selected;
    if (sel == null || sel.kind != _Kind.cover) return;
    _pushUndo();
    setState(() {
      final cover = _covers[sel.index];
      _covers[sel.index] = CoverEdit(cover.rect, dark: !cover.dark);
    });
  }

  // -- Übernehmen ------------------------------------------------------------

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
    // Texte über den Abdeckungen – so lässt sich eine Beschriftung auf eine
    // frisch abgedeckte Stelle schreiben.
    final edits = <ImageEdit>[..._covers, ..._texts];
    final bytes = await applyImageEdits(widget.bytes, edits);
    if (!mounted) return;
    setState(() => _saving = false);
    if (bytes == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Das Bild konnte nicht bearbeitet werden.')));
      return;
    }
    Navigator.of(context).pop(ImageEditResult(
      bytes: bytes,
      targets: List.of(_targets),
      imageChanged: edits.isNotEmpty,
      edits: edits,
    ));
  }

  // -- Darstellung -----------------------------------------------------------

  List<Widget> _overlay(BuildContext context, Size box) {
    _box = box;
    final c = context.colors;
    Rect scaled(Rect r) =>
        Rect.fromLTRB(r.left * box.width, r.top * box.height, r.right * box.width, r.bottom * box.height);
    final selected = _selected;
    Widget handle(Rect r) => Positioned(
          left: r.right * box.width - 11,
          top: r.bottom * box.height - 11,
          child: IgnorePointer(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.open_in_full, size: 12, color: Colors.white),
            ),
          ),
        );
    final drag = _dragRect;
    return [
      for (final (i, cover) in _covers.indexed)
        Positioned.fromRect(
          rect: scaled(cover.rect),
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: cover.color,
                border: selected == (kind: _Kind.cover, index: i) ? Border.all(color: c.accent, width: 2) : null,
              ),
            ),
          ),
        ),
      for (final (i, text) in _texts.indexed)
        positionedAt(
          box: box,
          x: text.position.dx,
          y: text.position.dy,
          child: IgnorePointer(
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: text.size * box.height * 0.3, vertical: text.size * box.height * 0.15),
              decoration: BoxDecoration(
                color: TextEdit.backgroundColor,
                borderRadius: BorderRadius.circular(text.size * box.height * 0.25),
                border: selected == (kind: _Kind.text, index: i) ? Border.all(color: c.accent, width: 2) : null,
              ),
              child: Text(
                text.text,
                style: TextStyle(
                  color: TextEdit.textColor,
                  fontSize: text.size * box.height,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      if (_regions)
        for (final (i, t) in _targets.indexed)
          Positioned.fromRect(
            rect: scaled(Rect.fromCenter(center: Offset(t.x, t.y), width: t.w, height: t.h)),
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: c.good.withAlpha(50),
                  border: Border.all(
                    color: selected == (kind: _Kind.target, index: i) ? c.accent : c.good,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
      if (_labels)
        for (final (i, t) in _targets.indexed)
          positionedAt(
            box: box,
            x: t.x,
            y: t.y,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(14)),
                child: Text(_chipText(i),
                    style: TextStyle(color: c.accentInk, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      if (_isRectSelection(selected)) handle(_rectOf(selected!)),
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

  /// Aktionen für eine ausgewählte Abdeckung bzw. einen Bereich.
  Widget? _selectionBar() {
    final sel = _selected;
    if (sel == null || sel.kind == _Kind.text || (sel.kind == _Kind.target && _labels)) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          if (sel.kind == _Kind.cover)
            OutlinedButton.icon(
              onPressed: _toggleSelectedColor,
              icon: const Icon(Icons.invert_colors, size: 18),
              label: Text(_covers[sel.index].dark ? 'Weiß' : 'Schwarz'),
            ),
          OutlinedButton.icon(
            key: const ValueKey('editor-delete-selected'),
            onPressed: _deleteSelected,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Entfernen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = widget.targetMode;
    final selectionBar = _selectionBar();
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Rückgängig',
            onPressed: _undoStack.isEmpty ? null : _undo,
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
                onSelectionChanged: (s) => setState(() {
                  _tool = s.first;
                  _selected = null;
                }),
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
            // Fester Platz, damit das Bild beim Auswählen nicht springt.
            SizedBox(height: 44, child: Center(child: selectionBar)),
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
