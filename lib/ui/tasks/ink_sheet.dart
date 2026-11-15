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
  InkStroke(this.points, this.cell, {this.widths});

  final List<Offset> points;
  final InkCell cell;

  /// Strichstärke je Punkt (Stiftdruck bzw. Tempo) – null = gleichmäßig.
  final List<double>? widths;

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

  /// Breite des Blatts in Blatt-Koordinaten: wird beim ersten Anzeigen
  /// festgelegt, danach wird das Blatt nur noch skaliert (größeres Fenster,
  /// Vollbild) – so bleiben die Striche an ihrer Stelle.
  double lastWidth = 600;
  bool _widthFixed = false;

  /// Zählt jede Änderung (fürs Neuzeichnen nur bei Bedarf).
  int revision = 0;

  /// Blattbreite festlegen (solange noch nichts geschrieben ist, folgt sie der
  /// Anzeige).
  double fixWidth(double shown) {
    if (!_widthFixed || strokes.isEmpty) {
      lastWidth = shown;
      _widthFixed = strokes.isNotEmpty;
    }
    return lastWidth;
  }

  @override
  void notifyListeners() {
    revision++;
    super.notifyListeners();
  }

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

  void add(List<Offset> points, double width, {List<double>? widths}) {
    if (points.isEmpty) return;
    final rough = InkStroke(points, (row: 0, side: false)).bounds;
    final stroke = InkStroke(
      List.unmodifiable(points),
      cellAt(rough.center, width),
      widths: widths == null || widths.length != points.length ? null : List.unmodifiable(widths),
    );
    _widthFixed = true;
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
/// Eine Zeile wird gelesen, sobald man in einer anderen ansetzt (oder nach
/// einer längeren Pause bzw. mit „Zeile lesen“, siehe StepTaskView).
/// [marks] zeigt Prüfergebnisse je Zelle, [busy] die gerade gelesenen Zellen.
///
/// Geschrieben wird in Blatt-Koordinaten ([InkSheetController.lastWidth]);
/// ist die Anzeige breiter (großes Fenster, Vollbild), wird das Blatt
/// vergrößert dargestellt – höchstens um [maxScale].
class InkSheet extends StatefulWidget {
  const InkSheet({
    super.key,
    required this.controller,
    required this.onCellsChanged,
    this.onStrokeStart,
    this.marks = const {},
    this.busy = const {},
    this.onCheckSheet,
    this.onExpand,
    this.onReadNow,
    this.maxScale = 1,
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

  /// „Großes Blatt“ (Vollbild) – null = ausgeblendet.
  final VoidCallback? onExpand;

  /// „Zeile lesen“: Geschriebenes sofort lesen – null = nichts wartet.
  final VoidCallback? onReadNow;

  /// So weit darf das Blatt vergrößert werden (1 = nie).
  final double maxScale;

  @override
  State<InkSheet> createState() => _InkSheetState();
}

/// Der Strich, der gerade entsteht – eigene Zeichenebene, damit beim Schreiben
/// nicht das ganze Blatt neu gezeichnet wird.
class _LiveStroke extends ChangeNotifier {
  final points = <Offset>[];
  final widths = <double>[];
  Duration? _lastTime;

  bool get isEmpty => points.isEmpty;

  void start(Offset p, double width, Duration time) {
    points
      ..clear()
      ..add(p);
    widths
      ..clear()
      ..add(width);
    _lastTime = time;
    notifyListeners();
  }

  /// Neuer Punkt – leicht geglättet gegen Zittern.
  void add(Offset raw, double width, Duration time, {double smoothing = 0.55}) {
    if (points.isEmpty) return start(raw, width, time);
    final last = points.last;
    final p = Offset.lerp(last, raw, smoothing)!;
    if ((p - last).distance < 0.6) return;
    points.add(p);
    // Auch die Stärke ändert sich sanft.
    widths.add(widths.last + (width - widths.last) * 0.35);
    _lastTime = time;
    notifyListeners();
  }

  Duration? get lastTime => _lastTime;

  void clear() {
    points.clear();
    widths.clear();
    _lastTime = null;
    notifyListeners();
  }
}

class _InkSheetState extends State<InkSheet> {
  final _live = _LiveStroke();
  int? _pointer;
  PointerDeviceKind? _kind;
  bool _erasing = false;
  final Set<InkCell> _erased = {};

  /// Blattbreite (Koordinaten) und Vergrößerung der Anzeige.
  double _width = 0;
  double _scale = 1;

  InkSheetController get _ctrl => widget.controller;

  static const _penDevices = {PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus};
  static const _allDevices = {
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.unknown,
  };

  /// Grundstärke der Tinte (Blatt-Koordinaten).
  static const baseWidth = 2.6;

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
    _live.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Offset _toSheet(Offset local) => local / _scale;

  /// Stärke aus dem Stiftdruck, sonst aus dem Tempo (schnell = dünner).
  double _widthFor(PointerEvent e, Offset at) {
    if (e.kind == PointerDeviceKind.stylus && e.pressureMax > e.pressureMin) {
      final p = ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin)).clamp(0.0, 1.0);
      return baseWidth * (0.55 + 0.9 * p);
    }
    final last = _live.points.isEmpty ? null : _live.points.last;
    final then = _live.lastTime;
    if (last == null || then == null) return baseWidth;
    final ms = (e.timeStamp - then).inMicroseconds / 1000;
    if (ms <= 0) return _live.widths.last;
    final speed = (at - last).distance / ms; // Blatt-Pixel je ms
    return baseWidth * (1.2 - speed * 0.25).clamp(0.7, 1.2);
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null || !_drawDevices.contains(e.kind)) return;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) return;
    if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus) {
      _ctrl.setPenOnly(true, chosen: false);
    }
    _pointer = e.pointer;
    _kind = e.kind;
    final at = _toSheet(e.localPosition);
    _erasing = _ctrl.eraser || e.kind == PointerDeviceKind.invertedStylus || (e.buttons & kSecondaryStylusButton) != 0;
    if (_erasing) {
      _erased.addAll(_ctrl.eraseAt(at, radius: 12));
      return;
    }
    widget.onStrokeStart?.call(InkSheetController.cellAt(at, _width));
    _live.start(at, _widthFor(e, at), e.timeStamp);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final at = _toSheet(e.localPosition);
    if (_erasing) {
      _erased.addAll(_ctrl.eraseAt(at, radius: 12));
      return;
    }
    if (_live.isEmpty) return;
    _live.add(at, _widthFor(e, at), e.timeStamp, smoothing: _kind == PointerDeviceKind.stylus ? 0.7 : 0.55);
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
    if (_live.isEmpty) return;
    final points = List.of(_live.points);
    final widths = List.of(_live.widths);
    _live.clear();
    if (e is PointerCancelEvent && points.length < 3) return;
    // Der letzte Punkt genau dort, wo der Stift abhob.
    final end = _toSheet(e.localPosition);
    if (e is! PointerCancelEvent && (end - points.last).distance > 0.6) {
      points.add(end);
      widths.add(widths.last);
    }
    _ctrl.add(points, _width, widths: widths);
    widget.onCellsChanged({_ctrl.strokes.last.cell});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFA9C1FF) : const Color(0xFF1B2F7A);
    final red = dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828);
    final paper = dark ? c.surface : const Color(0xFFFFFEF9);
    final rows = math.max(12, _ctrl.rowsUsed + 6);
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
                if (widget.onExpand != null)
                  IconButton(
                    key: const ValueKey('ink-expand'),
                    tooltip: 'Großes Blatt (Vollbild)',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onExpand,
                    icon: const Icon(Icons.open_in_full, size: 20),
                  ),
                FilterChip(
                  key: const ValueKey('ink-pen-only'),
                  label: const Text('Nur Stift zeichnet'),
                  tooltip: 'Mit Stift: der Finger scrollt, die aufgelegte Hand malt nicht',
                  selected: _ctrl.penOnly,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => _ctrl.setPenOnly(v),
                ),
                if (widget.onReadNow != null)
                  TextButton.icon(
                    key: const ValueKey('ink-read-now'),
                    // Immer da (nur ausgegraut) – sonst springt das Blatt beim ersten Strich.
                    onPressed: _ctrl.strokes.isEmpty ? null : widget.onReadNow,
                    icon: const Icon(Icons.text_fields, size: 18),
                    label: const Text('Zeile lesen'),
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
              // Blatt-Koordinaten bleiben fest; die Anzeige wird höchstens
              // um maxScale vergrößert und dann mittig gesetzt.
              // Das vergrößerte Blatt (Vollbild) nutzt die Breite des normalen.
              _width = widget.maxScale > 1 ? _ctrl.lastWidth : _ctrl.fixWidth(box.maxWidth);
              _scale = (box.maxWidth / _width).clamp(0.4, math.max(1.0, widget.maxScale));
              final shown = Size(_width * _scale, rows * InkSheetController.rowHeight * _scale);
              final rule = dark ? Colors.white.withAlpha(30) : const Color(0xFF90A4C8).withAlpha(90);
              return Align(
                alignment: Alignment.topCenter,
                child: Listener(
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
                    child: SizedBox.fromSize(
                      size: shown,
                      child: Stack(
                        children: [
                          // Blatt und fertige Striche: nur neu, wenn sich etwas ändert.
                          RepaintBoundary(
                            child: CustomPaint(
                              size: shown,
                              painter: _SheetPainter(
                                revision: _ctrl.revision,
                                strokes: _ctrl.strokes,
                                rows: rows,
                                scale: _scale,
                                width: _width,
                                ink: ink,
                                rule: rule,
                                margin: red.withAlpha(110),
                                muted: c.inkMuted,
                                red: red,
                                marks: widget.marks,
                                busy: widget.busy,
                              ),
                            ),
                          ),
                          // Der Strich, der gerade entsteht.
                          CustomPaint(
                            size: shown,
                            painter: _LivePainter(_live, scale: _scale, ink: ink),
                          ),
                        ],
                      ),
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

/// Tinte: geglättet (Catmull-Rom) und mit wechselnder Stärke.
void paintInk(Canvas canvas, List<Offset> points, List<double>? widths, Color color, {double width = 2.6}) {
  final paint = Paint()
    ..color = color
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  double w(int i) => widths == null || i >= widths.length ? width : widths[i];
  if (points.length == 1) {
    canvas.drawCircle(points.first, w(0) / 2, Paint()..color = color);
    return;
  }
  if (widths == null) {
    canvas.drawPath(smoothInkPath(points), paint..strokeWidth = width);
    return;
  }
  // Abschnittsweise mit der jeweiligen Stärke – runde Enden fügen sie nahtlos.
  for (var i = 0; i < points.length - 1; i++) {
    final p0 = points[i == 0 ? 0 : i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[i + 2 < points.length ? i + 2 : i + 1];
    final steps = math.max(1, math.min(6, ((p2 - p1).distance / 2).ceil()));
    var prev = p1;
    for (var k = 1; k <= steps; k++) {
      final t = k / steps;
      final q = _catmullRom(p0, p1, p2, p3, t);
      paint.strokeWidth = w(i) + (w(i + 1) - w(i)) * t;
      canvas.drawLine(prev, q, paint);
      prev = q;
    }
  }
}

/// Geglätteter Pfad durch [points] (Catmull-Rom).
Path smoothInkPath(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i < points.length - 1; i++) {
    final p0 = points[i == 0 ? 0 : i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[i + 2 < points.length ? i + 2 : i + 1];
    // Catmull-Rom als kubische Bézierkurve.
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

Offset _catmullRom(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final t2 = t * t, t3 = t2 * t;
  double f(double a, double b, double c, double d) =>
      0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
  return Offset(f(p0.dx, p1.dx, p2.dx, p3.dx), f(p0.dy, p1.dy, p2.dy, p3.dy));
}

class _LivePainter extends CustomPainter {
  _LivePainter(this.live, {required this.scale, required this.ink}) : super(repaint: live);

  final _LiveStroke live;
  final double scale;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (live.isEmpty) return;
    canvas.scale(scale);
    paintInk(canvas, live.points, live.widths, ink);
  }

  @override
  bool shouldRepaint(_LivePainter old) => old.live != live || old.scale != scale || old.ink != ink;
}

class _SheetPainter extends CustomPainter {
  _SheetPainter({
    required this.revision,
    required this.strokes,
    required this.rows,
    required this.scale,
    required this.width,
    required this.ink,
    required this.rule,
    required this.margin,
    required this.muted,
    required this.red,
    required this.marks,
    required this.busy,
  });

  final int revision;
  final List<InkStroke> strokes;
  final int rows;
  final double scale, width;
  final Color ink, rule, margin, muted, red;
  final Map<InkCell, PaperLineStatus> marks;
  final Set<InkCell> busy;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    const h = InkSheetController.rowHeight;
    final rulePaint = Paint()
      ..color = rule
      ..strokeWidth = 1 / scale;
    for (var r = 1; r <= rows; r++) {
      canvas.drawLine(Offset(0, r * h - 0.5), Offset(width, r * h - 0.5), rulePaint);
    }
    final mx = width * InkSheetController.marginStart;
    canvas.drawLine(
      Offset(mx, 0),
      Offset(mx, rows * h),
      Paint()
        ..color = margin
        ..strokeWidth = 1.2 / scale,
    );
    _text(canvas, 'Nebenrechnung', Offset(mx + 6, 2), 11, muted);
    for (var r = 0; r < rows; r++) {
      _text(canvas, '${r + 1}', Offset(4, r * h + 4), 10, muted.withAlpha(140));
    }
    for (final s in strokes) {
      paintInk(canvas, s.points, s.widths, ink);
    }
    for (final MapEntry(key: cell, value: status) in marks.entries) {
      final symbol = switch (status) {
        PaperLineStatus.ok => '✓',
        PaperLineStatus.error => '✗',
        PaperLineStatus.follow => '↳',
        PaperLineStatus.unclear => '?',
      };
      final x = cell.side ? width - 22 : mx - 24;
      _text(canvas, symbol, Offset(x, cell.row * h + h * 0.18), 30, red);
    }
    for (final cell in busy) {
      final x = cell.side ? width - 18 : mx - 18;
      _text(canvas, '…', Offset(x, cell.row * h + h - 26), 18, muted);
    }
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
  bool shouldRepaint(_SheetPainter old) =>
      old.revision != revision ||
      old.rows != rows ||
      old.scale != scale ||
      old.width != width ||
      old.ink != ink ||
      !identical(old.marks, marks) ||
      !identical(old.busy, busy);
}

/// Das Stift-Blatt im Vollbild: dasselbe Blatt, vergrößert. [sheet] baut es
/// (mit den aktuellen Markierungen), [refresh] meldet, wenn sich dort etwas
/// ändert.
Future<void> showInkSheetFullscreen(
  BuildContext context, {
  required Widget Function(BuildContext context) sheet,
  required Listenable refresh,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (context) => Scaffold(
      appBar: AppBar(
        title: const Text('Rechenweg'),
        actions: [
          TextButton(
            key: const ValueKey('ink-fullscreen-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fertig'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: refresh,
        builder: (context, _) => SingleChildScrollView(
          key: const ValueKey('ink-fullscreen'),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
          child: sheet(context),
        ),
      ),
    ),
  ),
);

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
    if (s.points.length == 1) {
      canvas.drawCircle(s.points.first, pen.strokeWidth / 2, Paint()..color = pen.color);
    } else {
      canvas.drawPath(smoothInkPath(s.points), pen);
    }
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
    if (s.points.length == 1) {
      canvas.drawCircle(s.points.first, pen.strokeWidth / 2, Paint()..color = pen.color);
    } else {
      canvas.drawPath(smoothInkPath(s.points), pen);
    }
  }
  final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}
