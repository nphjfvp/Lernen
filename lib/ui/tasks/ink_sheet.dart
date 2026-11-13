import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/paper_review.dart';
import '../../theme/app_colors.dart';
import 'hand_math.dart';

/// Eine Stelle auf dem Stift-Blatt: Zeile [row], [side] = Nebenrechnungs-Rand.
typedef InkCell = ({int row, bool side});

/// Ein Strich (Punkte in logischen Pixeln des Blatts) – die Zelle wird beim
/// Absetzen aus der Mitte des Strichs bestimmt und bleibt dann fest.
class InkStroke {
  InkStroke(this.points, this.cell);

  final List<Offset> points;
  final InkCell cell;

  Rect get bounds {
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final p in points) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }
}

/// Inhalt des Stift-Blatts: Striche je Zeile und Rand, Rückgängig, Radieren.
/// Jede Änderung einer Zelle erhöht deren Version – so erkennt die
/// Handschrift-Erkennung veraltete Ergebnisse.
class InkSheetController extends ChangeNotifier {
  static const rowHeight = 72.0;

  /// Ab diesem Anteil der Breite beginnt der Rand für Nebenrechnungen.
  static const marginStart = 0.64;

  final List<InkStroke> strokes = [];
  final List<List<InkStroke>> _undo = [];
  final Map<InkCell, int> _versions = {};

  /// Nur der Stift zeichnet (Finger scrollt) – schaltet sich beim ersten
  /// Stift-Strich von selbst ein.
  bool penOnly = false;

  /// Breite des Blatts beim letzten Zeichnen (fürs Bild des ganzen Blatts).
  double lastWidth = 600;
  bool _penOnlyChosen = false;
  bool eraser = false;

  int version(InkCell cell) => _versions[cell] ?? 0;

  List<InkStroke> strokesIn(InkCell cell) => [
    for (final s in strokes)
      if (s.cell == cell) s,
  ];

  Set<InkCell> get cells => {for (final s in strokes) s.cell};

  int get rowsUsed => strokes.isEmpty ? 0 : strokes.map((s) => s.cell.row).reduce(math.max) + 1;

  bool get canUndo => _undo.isNotEmpty;

  void _bump(Iterable<InkCell> cells) {
    for (final c in cells) {
      _versions[c] = version(c) + 1;
    }
  }

  void _snapshot() {
    _undo.add(List.of(strokes));
    if (_undo.length > 60) _undo.removeAt(0);
  }

  static InkCell cellAt(Offset center, double width) =>
      (row: math.max(0, (center.dy / rowHeight).floor()), side: center.dx > width * marginStart);

  void add(List<Offset> points, double width) {
    if (points.isEmpty) return;
    final rough = InkStroke(points, (row: 0, side: false)).bounds;
    final stroke = InkStroke(List.unmodifiable(points), cellAt(rough.center, width));
    _snapshot();
    strokes.add(stroke);
    _bump([stroke.cell]);
    notifyListeners();
  }

  /// Entfernt Striche, die [p] (mit [radius]) berühren – liefert die
  /// betroffenen Zellen.
  Set<InkCell> eraseAt(Offset p, {double radius = 12}) {
    final hit = [
      for (final s in strokes)
        if (s.points.any((q) => (q - p).distance <= radius)) s,
    ];
    if (hit.isEmpty) return const {};
    _snapshot();
    strokes.removeWhere(hit.contains);
    final cells = {for (final s in hit) s.cell};
    _bump(cells);
    notifyListeners();
    return cells;
  }

  /// Rückgängig – liefert die geänderten Zellen.
  Set<InkCell> undo() {
    if (_undo.isEmpty) return const {};
    final before = {...strokes};
    final restored = _undo.removeLast();
    final after = {...restored};
    strokes
      ..clear()
      ..addAll(restored);
    final cells = {for (final s in before.difference(after)) s.cell, for (final s in after.difference(before)) s.cell};
    _bump(cells);
    notifyListeners();
    return cells;
  }

  /// Alle Striche einer Zelle löschen (Zeile entfernt).
  void clearCell(InkCell cell) {
    if (!strokes.any((s) => s.cell == cell)) return;
    _snapshot();
    strokes.removeWhere((s) => s.cell == cell);
    _bump([cell]);
    notifyListeners();
  }

  Set<InkCell> clear() {
    if (strokes.isEmpty) return const {};
    final cells = this.cells;
    _snapshot();
    strokes.clear();
    _bump(cells);
    notifyListeners();
    return cells;
  }

  void setPenOnly(bool value, {bool chosen = true}) {
    if (!chosen && _penOnlyChosen) return;
    if (chosen) _penOnlyChosen = true;
    if (penOnly == value) return;
    penOnly = value;
    notifyListeners();
  }

  void setEraser(bool value) {
    if (eraser == value) return;
    eraser = value;
    notifyListeners();
  }
}

/// Das Stift-Blatt: linierte Zeilen, rechts ein Rand für Nebenrechnungen.
/// Jede Zeile (und jeder Rand) wird nach einer kurzen Schreibpause einzeln
/// erkannt (siehe StepTaskView). [marks] zeigt Prüfergebnisse je Zelle,
/// [busy] die gerade gelesenen Zellen.
class InkSheet extends StatefulWidget {
  const InkSheet({
    super.key,
    required this.controller,
    required this.onCellsChanged,
    this.onStrokeStart,
    this.marks = const {},
    this.busy = const {},
    this.onCheckSheet,
  });

  final InkSheetController controller;

  /// Striche in diesen Zellen haben sich geändert (nach dem Absetzen,
  /// Radieren, Rückgängig).
  final void Function(Set<InkCell> cells) onCellsChanged;

  /// Der Stift setzt in [cell] an – z.B. um die vorige Zeile gleich zu lesen.
  final void Function(InkCell cell)? onStrokeStart;
  final Map<InkCell, PaperLineStatus> marks;
  final Set<InkCell> busy;

  /// „Ganzes Blatt prüfen“ (null = ausgeblendet).
  final VoidCallback? onCheckSheet;

  @override
  State<InkSheet> createState() => _InkSheetState();
}

class _InkSheetState extends State<InkSheet> {
  List<Offset>? _current;
  int? _pointer;
  bool _erasing = false;
  final Set<InkCell> _erased = {};
  double _width = 0;

  InkSheetController get _ctrl => widget.controller;

  static const _penDevices = {PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus};
  static const _allDevices = {
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.unknown,
  };

  Set<PointerDeviceKind> get _drawDevices => _ctrl.penOnly ? _penDevices : _allDevices;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_changed);
  }

  @override
  void didUpdateWidget(InkSheet old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null || !_drawDevices.contains(e.kind)) return;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) return;
    if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus) {
      _ctrl.setPenOnly(true, chosen: false);
    }
    _pointer = e.pointer;
    _erasing = _ctrl.eraser || e.kind == PointerDeviceKind.invertedStylus || (e.buttons & kSecondaryStylusButton) != 0;
    if (_erasing) {
      _erased.addAll(_ctrl.eraseAt(e.localPosition));
      return;
    }
    widget.onStrokeStart?.call(InkSheetController.cellAt(e.localPosition, _width));
    setState(() => _current = [e.localPosition]);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (_erasing) {
      _erased.addAll(_ctrl.eraseAt(e.localPosition));
      return;
    }
    final cur = _current;
    if (cur == null) return;
    if ((cur.last - e.localPosition).distance < 0.8) return;
    setState(() => cur.add(e.localPosition));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_erasing) {
      _erasing = false;
      if (_erased.isNotEmpty) widget.onCellsChanged({..._erased});
      _erased.clear();
      return;
    }
    final cur = _current;
    _current = null;
    if (cur == null) return;
    if (e is PointerCancelEvent && cur.length < 3) {
      setState(() {});
      return;
    }
    _ctrl.add(cur, _width);
    widget.onCellsChanged({_ctrl.strokes.last.cell});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFF9DB8FF) : const Color(0xFF1F3A93);
    final red = dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828);
    final paper = dark ? c.surface : const Color(0xFFFFFEF9);
    final rows = math.max(6, _ctrl.rowsUsed + 3);
    return Container(
      key: const ValueKey('ink-sheet'),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
        boxShadow: dark
            ? null
            : [BoxShadow(color: Colors.black.withAlpha(14), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
              children: [
                Text(
                  'Rechenweg',
                  style: TextStyle(fontFamily: handwritingFont, fontSize: 20, color: ink),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('ink-pen'),
                  tooltip: 'Stift',
                  isSelected: !_ctrl.eraser,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _ctrl.setEraser(false),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  selectedIcon: Icon(Icons.edit, size: 20, color: c.accent),
                ),
                IconButton(
                  key: const ValueKey('ink-eraser'),
                  tooltip: 'Radierer (oder die Radierer-Seite des Stifts)',
                  isSelected: _ctrl.eraser,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _ctrl.setEraser(true),
                  icon: const Icon(Icons.auto_fix_normal_outlined, size: 20),
                  selectedIcon: Icon(Icons.auto_fix_normal, size: 20, color: c.accent),
                ),
                IconButton(
                  key: const ValueKey('ink-undo'),
                  tooltip: 'Rückgängig',
                  visualDensity: VisualDensity.compact,
                  onPressed: _ctrl.canUndo
                      ? () {
                          final cells = _ctrl.undo();
                          if (cells.isNotEmpty) widget.onCellsChanged(cells);
                        }
                      : null,
                  icon: const Icon(Icons.undo, size: 20),
                ),
                IconButton(
                  key: const ValueKey('ink-clear'),
                  tooltip: 'Blatt leeren',
                  visualDensity: VisualDensity.compact,
                  onPressed: _ctrl.strokes.isEmpty
                      ? null
                      : () {
                          final cells = _ctrl.clear();
                          if (cells.isNotEmpty) widget.onCellsChanged(cells);
                        },
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                ),
                FilterChip(
                  key: const ValueKey('ink-pen-only'),
                  label: const Text('Nur Stift zeichnet'),
                  tooltip: 'Mit Stift: der Finger scrollt, die aufgelegte Hand malt nicht',
                  selected: _ctrl.penOnly,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => _ctrl.setPenOnly(v),
                ),
                if (widget.onCheckSheet != null)
                  TextButton.icon(
                    key: const ValueKey('ink-check-sheet'),
                    onPressed: _ctrl.strokes.isEmpty ? null : widget.onCheckSheet,
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Ganzes Blatt prüfen'),
                  ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, box) {
              _width = box.maxWidth;
              _ctrl.lastWidth = box.maxWidth;
              return Listener(
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                child: RawGestureDetector(
                  key: ValueKey(_ctrl.penOnly),
                  // Zeichnen hat Vorrang vor dem Scrollen der Seite.
                  gestures: {
                    EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                      () => EagerGestureRecognizer(supportedDevices: _drawDevices),
                      (_) {},
                    ),
                  },
                  child: CustomPaint(
                    size: Size(box.maxWidth, rows * InkSheetController.rowHeight),
                    painter: _InkPainter(
                      strokes: _ctrl.strokes,
                      current: _current,
                      rows: rows,
                      ink: ink,
                      rule: dark ? Colors.white.withAlpha(30) : const Color(0xFF90A4C8).withAlpha(90),
                      margin: red.withAlpha(110),
                      muted: c.inkMuted,
                      red: red,
                      marks: widget.marks,
                      busy: widget.busy,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.strokes,
    required this.current,
    required this.rows,
    required this.ink,
    required this.rule,
    required this.margin,
    required this.muted,
    required this.red,
    required this.marks,
    required this.busy,
  });

  final List<InkStroke> strokes;
  final List<Offset>? current;
  final int rows;
  final Color ink, rule, margin, muted, red;
  final Map<InkCell, PaperLineStatus> marks;
  final Set<InkCell> busy;

  @override
  void paint(Canvas canvas, Size size) {
    const h = InkSheetController.rowHeight;
    final rulePaint = Paint()
      ..color = rule
      ..strokeWidth = 1;
    for (var r = 1; r <= rows; r++) {
      canvas.drawLine(Offset(0, r * h - 0.5), Offset(size.width, r * h - 0.5), rulePaint);
    }
    final mx = size.width * InkSheetController.marginStart;
    canvas.drawLine(
      Offset(mx, 0),
      Offset(mx, size.height),
      Paint()
        ..color = margin
        ..strokeWidth = 1.2,
    );
    _text(canvas, 'Nebenrechnung', Offset(mx + 6, 2), 11, muted);
    for (var r = 0; r < rows; r++) {
      _text(canvas, '${r + 1}', Offset(4, r * h + 4), 10, muted.withAlpha(140));
    }
    final pen = Paint()
      ..color = ink
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      _stroke(canvas, s.points, pen);
    }
    if (current != null) _stroke(canvas, current!, pen);
    for (final MapEntry(key: cell, value: status) in marks.entries) {
      final symbol = switch (status) {
        PaperLineStatus.ok => '✓',
        PaperLineStatus.error => '✗',
        PaperLineStatus.follow => '↳',
        PaperLineStatus.unclear => '?',
      };
      final x = cell.side ? size.width - 22 : mx - 24;
      _text(canvas, symbol, Offset(x, cell.row * h + h * 0.18), 30, red);
    }
    for (final cell in busy) {
      final x = cell.side ? size.width - 18 : mx - 18;
      _text(canvas, '…', Offset(x, cell.row * h + h - 26), 18, muted);
    }
  }

  static void _stroke(Canvas canvas, List<Offset> points, Paint pen) {
    if (points.length == 1) {
      canvas.drawCircle(points.first, pen.strokeWidth / 2, Paint()..color = pen.color);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final p = points[i - 1], q = points[i];
      // Geglättet: Mittelpunkte als Kurvenpunkte.
      path.quadraticBezierTo(p.dx, p.dy, (p.dx + q.dx) / 2, (p.dy + q.dy) / 2);
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, pen);
  }

  static void _text(Canvas canvas, String text, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_InkPainter old) => true;
}

/// Striche als PNG (schwarz auf weiß, zugeschnitten) für die Bild-KI –
/// eine Zeile wird etwa [targetHeight] Pixel hoch.
Future<Uint8List?> renderInkPng(List<InkStroke> strokes, {double targetHeight = 150}) async {
  if (strokes.isEmpty) return null;
  var bounds = strokes.first.bounds;
  for (final s in strokes.skip(1)) {
    bounds = bounds.expandToInclude(s.bounds);
  }
  bounds = bounds.inflate(14);
  final scale = (targetHeight / math.max(bounds.height, InkSheetController.rowHeight * 0.8)).clamp(0.5, 3.0);
  final size = Size(bounds.width * scale, bounds.height * scale);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  canvas.scale(scale);
  canvas.translate(-bounds.left, -bounds.top);
  final pen = Paint()
    ..color = Colors.black
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final s in strokes) {
    _InkPainter._stroke(canvas, s.points, pen);
  }
  final image = await recorder.endRecording().toImage(
    math.max(1, size.width.round()),
    math.max(1, size.height.round()),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// Das ganze Blatt als PNG (mit Rand-Linie) – für „Ganzes Blatt prüfen“.
Future<Uint8List?> renderInkSheetPng(InkSheetController ctrl, double width) async {
  if (ctrl.strokes.isEmpty) return null;
  final rows = ctrl.rowsUsed;
  const scale = 1.5;
  final size = Size(width * scale, (rows * InkSheetController.rowHeight + 10) * scale);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  canvas.scale(scale);
  canvas.drawLine(
    Offset(width * InkSheetController.marginStart, 0),
    Offset(width * InkSheetController.marginStart, rows * InkSheetController.rowHeight),
    Paint()
      ..color = const Color(0xFFBBBBBB)
      ..strokeWidth = 1,
  );
  final pen = Paint()
    ..color = Colors.black
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final s in ctrl.strokes) {
    _InkPainter._stroke(canvas, s.points, pen);
  }
  final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}
