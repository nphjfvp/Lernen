/// Freie Szene für „Visuell lernen“: Die KI zeichnet mit einfachen Formen
/// (Kreise, Rechtecke, Linien, Pfeile, Flächen, Kurvenzüge, Text) in einem
/// eigenen Koordinatensystem und bewegt sie über Schlüsselbilder – so lässt
/// sich fast alles zeigen: schwingende Atome im Gitter, eine wandernde
/// Versetzung, Kräfte an einem Balken, eine Welle, eine Abkühlkurve, die
/// gezeichnet wird. Die App rechnet nur zwischen den Schlüsselbildern hin und
/// her (linear) und zeichnet.
library;

double? _num(Object? raw) {
  final v = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}'.trim().replaceAll(',', '.'));
  // „NaN“/„Infinity“ der KI zählen als fehlend – sie zerschießen sonst die Zeichnung.
  return v != null && v.isFinite ? v : null;
}

String _str(Object? raw) => '${raw ?? ''}'.trim();

/// Zahl-Eigenschaften, die sich animieren lassen.
const diagramNumberProps = [
  'x',
  'y',
  'r',
  'w',
  'h',
  'x1',
  'y1',
  'x2',
  'y2',
  'opacity',
  'rotate',
  'scale',
  'size',
  'width',
  'draw',
];

List<List<double>>? _points(Object? raw) {
  if (raw is! List) return null;
  final out = <List<double>>[];
  for (final p in raw) {
    if (p is List && p.length >= 2) {
      final x = _num(p[0]), y = _num(p[1]);
      if (x != null && y != null) out.add([x, y]);
    } else if (p is Map) {
      final x = _num(p['x']), y = _num(p['y']);
      if (x != null && y != null) out.add([x, y]);
    }
  }
  return out.length >= 2 ? out : null;
}

Map<String, double> _numbers(Map raw) => {for (final k in diagramNumberProps) k: ?_num(raw[k])};

/// Ein Schlüsselbild: Werte, die zum Zeitpunkt [at] (0 = Anfang, 1 = Ende)
/// gelten sollen.
class DiagramKey {
  const DiagramKey({required this.at, this.numbers = const {}, this.fill, this.stroke, this.text, this.points});

  final double at;
  final Map<String, double> numbers;
  final String? fill;
  final String? stroke;
  final String? text;
  final List<List<double>>? points;

  Map<String, dynamic> toMap() => {
    'at': at,
    ...numbers,
    'fill': ?fill,
    'stroke': ?stroke,
    'text': ?text,
    if (points != null) 'points': points,
  };

  static DiagramKey? fromMap(Object? raw) {
    if (raw is! Map) return null;
    raw = DiagramElement.normalize(raw);
    final at = _num(raw['at'] ?? raw['t'] ?? raw['time']);
    if (at == null) return null;
    final fill = _str(raw['fill'] ?? raw['color']);
    final stroke = _str(raw['stroke']);
    return DiagramKey(
      at: at.clamp(0, 1).toDouble(),
      numbers: _numbers(raw),
      fill: fill.isEmpty ? null : fill,
      stroke: stroke.isEmpty ? null : stroke,
      text: raw['text'] == null ? null : _str(raw['text']),
      points: _points(raw['points']),
    );
  }
}

/// Arten von Formen.
enum DiagramShape { circle, rect, line, arrow, polygon, path, text }

DiagramShape? _shape(String raw) => switch (raw.toLowerCase()) {
  'circle' || 'kreis' || 'dot' || 'atom' || 'ellipse' || 'point' || 'punkt' => DiagramShape.circle,
  'rect' || 'rectangle' || 'box' || 'rechteck' || 'square' || 'quadrat' => DiagramShape.rect,
  'line' || 'linie' || 'segment' => DiagramShape.line,
  'triangle' || 'dreieck' => DiagramShape.polygon,
  'arrow' || 'pfeil' || 'vector' => DiagramShape.arrow,
  'polygon' || 'area' || 'flaeche' || 'fläche' => DiagramShape.polygon,
  'path' || 'polyline' || 'curve' || 'kurve' => DiagramShape.path,
  'text' || 'label' => DiagramShape.text,
  _ => null,
};

/// Eine Form der Szene; mit [repeat] als Raster aus [nx] × [ny] Kopien im
/// Abstand [dx]/[dy] (z.B. Atome eines Gitters).
class DiagramElement {
  const DiagramElement({
    required this.shape,
    this.numbers = const {},
    this.points = const [],
    this.fill = '',
    this.stroke = '',
    this.text = '',
    this.dashed = false,
    this.keys = const [],
    this.nx = 1,
    this.ny = 1,
    this.dx = 0,
    this.dy = 0,
  });

  final DiagramShape shape;
  final Map<String, double> numbers;
  final List<List<double>> points;
  final String fill;
  final String stroke;

  /// Text (bei [DiagramShape.text]) bzw. Beschriftung der Form.
  final String text;
  final bool dashed;
  final List<DiagramKey> keys;
  final int nx;
  final int ny;
  final double dx;
  final double dy;

  int get copies => nx * ny;

  /// Wert der Eigenschaft [prop] zum Zeitpunkt [p] (linear zwischen den
  /// Schlüsselbildern; Grundwert gilt bei 0).
  double? number(String prop, double p) {
    final track = <(double, double)>[
      if (numbers[prop] case final v?) (0.0, v),
      for (final k in keys)
        if (k.numbers[prop] case final v?) (k.at, v),
    ];
    return _interpolate(track, p, (a, b, f) => a + (b - a) * f);
  }

  List<List<double>> pointsAt(double p) {
    final track = <(double, List<List<double>>)>[
      if (points.isNotEmpty) (0.0, points),
      for (final k in keys)
        if (k.points != null) (k.at, k.points!),
    ];
    return _interpolate(
          track,
          p,
          (a, b, f) => a.length != b.length
              ? (f < 0.5 ? a : b)
              : [
                  for (var i = 0; i < a.length; i++)
                    [a[i][0] + (b[i][0] - a[i][0]) * f, a[i][1] + (b[i][1] - a[i][1]) * f],
                ],
        ) ??
        const [];
  }

  /// Farbverlauf: (von, nach, Anteil) – die Oberfläche mischt die Farben.
  (String, String, double)? colorAt(String which, double p) {
    final base = which == 'fill' ? fill : stroke;
    final track = <(double, String)>[
      if (base.isNotEmpty) (0.0, base),
      for (final k in keys)
        if ((which == 'fill' ? k.fill : k.stroke) case final c?) (k.at, c),
    ];
    if (track.isEmpty) return null;
    track.sort((a, b) => a.$1.compareTo(b.$1));
    if (p <= track.first.$1) return (track.first.$2, track.first.$2, 0);
    for (var i = 0; i < track.length - 1; i++) {
      final (a, b) = (track[i], track[i + 1]);
      if (p <= b.$1) {
        final span = b.$1 - a.$1;
        return (a.$2, b.$2, span <= 0 ? 1 : (p - a.$1) / span);
      }
    }
    return (track.last.$2, track.last.$2, 0);
  }

  /// Text zum Zeitpunkt [p]: der des letzten erreichten Schlüsselbilds.
  String textAt(double p) {
    var out = text;
    final sorted = [...keys]..sort((a, b) => a.at.compareTo(b.at));
    for (final k in sorted) {
      if (k.at <= p && k.text != null) out = k.text!;
    }
    return out;
  }

  static T? _interpolate<T>(List<(double, T)> track, double p, T Function(T a, T b, double f) lerp) {
    if (track.isEmpty) return null;
    track.sort((a, b) => a.$1.compareTo(b.$1));
    if (p <= track.first.$1) return track.first.$2;
    for (var i = 0; i < track.length - 1; i++) {
      final (a, b) = (track[i], track[i + 1]);
      if (p <= b.$1) {
        final span = b.$1 - a.$1;
        return span <= 0 ? b.$2 : lerp(a.$2, b.$2, (p - a.$1) / span);
      }
    }
    return track.last.$2;
  }

  Map<String, dynamic> toMap() => {
    'type': shape.name,
    ...numbers,
    if (points.isNotEmpty) 'points': points,
    if (fill.isNotEmpty) 'fill': fill,
    if (stroke.isNotEmpty) 'stroke': stroke,
    if (text.isNotEmpty) 'text': text,
    if (dashed) 'dashed': true,
    if (copies > 1) 'repeat': {'nx': nx, 'ny': ny, 'dx': dx, 'dy': dy},
    if (keys.isNotEmpty) 'keys': [for (final k in keys) k.toMap()],
  };

  /// Übliche Abweichungen der KI vereinheitlichen: Position als [x, y]
  /// ("pos", "position", "center", "at"), Größe als [b, h] ("size") oder
  /// "width"/"height", Radius als "radius", Linien mit "from"/"to",
  /// Zahlen als Text.
  static Map<String, dynamic> normalize(Map raw) {
    final m = Map<String, dynamic>.from(raw);
    List<double>? pair(Object? v) {
      if (v is List && v.length >= 2) {
        final a = _num(v[0]), b = _num(v[1]);
        if (a != null && b != null) return [a, b];
      }
      if (v is Map) {
        final a = _num(v['x']), b = _num(v['y']);
        if (a != null && b != null) return [a, b];
      }
      return null;
    }

    final at = pair(m['pos'] ?? m['position'] ?? m['center'] ?? m['at']);
    if (at != null) {
      m['x'] ??= at[0];
      m['y'] ??= at[1];
    }
    final isRect = _shape(_str(m['type'] ?? m['shape'] ?? m['form'])) == DiagramShape.rect;
    final size = pair(m['size']);
    if (size != null && isRect) {
      m['w'] ??= size[0];
      m['h'] ??= size[1];
      m.remove('size');
    }
    // Bei Rechtecken meinen "width"/"height" die Größe, sonst ist "width" die
    // Strichstärke.
    if (isRect && m['w'] == null && _num(m['width']) != null) m['w'] = m.remove('width');
    if (isRect && m['h'] == null && _num(m['height']) != null) m['h'] = m.remove('height');
    m['r'] ??= m['radius'];
    final from = pair(m['from'] ?? m['start']), to = pair(m['to'] ?? m['end']);
    if (from != null && to != null) {
      m['x1'] ??= from[0];
      m['y1'] ??= from[1];
      m['x2'] ??= to[0];
      m['y2'] ??= to[1];
    }
    m.removeWhere((_, v) => v == null);
    return m;
  }

  static DiagramElement? fromMap(Object? raw) {
    if (raw is! Map) return null;
    raw = normalize(raw);
    final shape = _shape(_str(raw['type'] ?? raw['shape'] ?? raw['form']));
    if (shape == null) return null;
    final numbers = _numbers(raw);
    final points = _points(raw['points'] ?? raw['punkte']) ?? const [];
    final text = _str(raw['text'] ?? raw['label']);
    final ok = switch (shape) {
      DiagramShape.circle => numbers.containsKey('x') && numbers.containsKey('y'),
      DiagramShape.rect => numbers.containsKey('x') && numbers.containsKey('y'),
      DiagramShape.line || DiagramShape.arrow => ['x1', 'y1', 'x2', 'y2'].every(numbers.containsKey),
      DiagramShape.polygon || DiagramShape.path => points.length >= 2,
      DiagramShape.text => text.isNotEmpty && numbers.containsKey('x') && numbers.containsKey('y'),
    };
    if (!ok) return null;
    final repeat = raw['repeat'] is Map ? raw['repeat'] as Map : const {};
    int count(Object? v) => (_num(v) ?? 1).round().clamp(1, 30);
    final rawKeys = raw['keys'] ?? raw['keyframes'] ?? raw['animate'];
    return DiagramElement(
      shape: shape,
      numbers: numbers,
      points: points,
      fill: _str(raw['fill'] ?? (shape == DiagramShape.text ? raw['color'] : null)),
      stroke: _str(raw['stroke'] ?? (shape == DiagramShape.text ? null : raw['color'])),
      text: text,
      dashed: raw['dashed'] == true,
      keys: [
        if (rawKeys is List)
          for (final k in rawKeys) ?DiagramKey.fromMap(k),
      ],
      nx: count(repeat['nx']),
      ny: count(repeat['ny']),
      dx: _num(repeat['dx']) ?? 0,
      dy: _num(repeat['dy']) ?? 0,
    );
  }
}

/// Text unter der Szene ab dem Zeitpunkt [at].
class DiagramCaption {
  const DiagramCaption({required this.at, required this.text});

  final double at;
  final String text;

  Map<String, dynamic> toMap() => {'at': at, 'text': text};
}

/// Die ganze Szene.
class VisualDiagram {
  const VisualDiagram({
    this.width = 100,
    this.height = 60,
    this.elements = const [],
    this.captions = const [],
    this.paramName = '',
    this.paramUnit = '',
    this.paramFrom = 0,
    this.paramTo = 1,
    this.seconds = 6,
  });

  /// Koordinatensystem: x nach rechts 0…[width], y nach UNTEN 0…[height].
  final double width;
  final double height;
  final List<DiagramElement> elements;
  final List<DiagramCaption> captions;

  /// Optionale Größe, die mit der Zeit läuft (z.B. Temperatur 20 → 900 °C).
  final String paramName;
  final String paramUnit;
  final double paramFrom;
  final double paramTo;

  /// Dauer eines Durchlaufs.
  final double seconds;

  /// Höchstens so viele gezeichnete Formen (Raster mitgezählt).
  static const maxShapes = 600;

  bool get hasParam => paramName.isNotEmpty;

  double paramAt(double p) => paramFrom + (paramTo - paramFrom) * p;

  String captionAt(double p) {
    var out = '';
    final sorted = [...captions]..sort((a, b) => a.at.compareTo(b.at));
    for (final c in sorted) {
      if (c.at <= p) out = c.text;
    }
    return out;
  }

  Map<String, dynamic> toMap() => {
    'width': width,
    'height': height,
    'elements': [for (final e in elements) e.toMap()],
    if (captions.isNotEmpty) 'captions': [for (final c in captions) c.toMap()],
    if (hasParam) 'param': {'name': paramName, 'unit': paramUnit, 'from': paramFrom, 'to': paramTo},
    'seconds': seconds,
  };

  static VisualDiagram? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final rawElements = raw['elements'] ?? raw['shapes'] ?? raw['elemente'] ?? raw['objects'];
    final elements = <DiagramElement>[];
    var shapes = 0;
    // Gruppen ({"type": "group", "x", "y", "children": [...]}) aufgelöst –
    // die Kinder um die Gruppenposition verschoben.
    List<Object?> flatten(List list, double ox, double oy) => [
      for (final e in list)
        if (e is Map && '${e['type']}'.toLowerCase() == 'group' && (e['children'] ?? e['elements']) is List)
          ...flatten((e['children'] ?? e['elements']) as List, ox + (_num(e['x']) ?? 0), oy + (_num(e['y']) ?? 0))
        else if (e is Map && (ox != 0 || oy != 0))
          {
            ...e,
            for (final k in const ['x', 'x1', 'x2'])
              if (_num(e[k]) != null) k: _num(e[k])! + ox,
            for (final k in const ['y', 'y1', 'y2'])
              if (_num(e[k]) != null) k: _num(e[k])! + oy,
            if (_points(e['points']) case final pts?)
              'points': [
                for (final p in pts) [p[0] + ox, p[1] + oy],
              ],
          }
        else
          e,
    ];
    if (rawElements is List) {
      for (final e in flatten(rawElements, 0, 0)) {
        final el = DiagramElement.fromMap(e);
        if (el == null || shapes + el.copies > maxShapes) continue;
        shapes += el.copies;
        elements.add(el);
      }
    }
    if (elements.isEmpty) return null;
    final rawCaptions = raw['captions'] ?? raw['texts'];
    final param = raw['param'] is Map ? raw['param'] as Map : const {};
    var w = _num(raw['width']) ?? 100, h = _num(raw['height']) ?? 60;
    if (w <= 0) w = 100;
    if (h <= 0) h = 60;
    return VisualDiagram(
      width: w,
      height: h,
      elements: elements,
      captions: [
        if (rawCaptions is List)
          for (final c in rawCaptions)
            if (c is Map && _str(c['text']).isNotEmpty)
              DiagramCaption(at: (_num(c['at']) ?? 0).clamp(0, 1).toDouble(), text: _str(c['text'])),
      ],
      paramName: _str(param['name']),
      paramUnit: _str(param['unit']),
      paramFrom: _num(param['from']) ?? 0,
      paramTo: _num(param['to']) ?? 1,
      seconds: (_num(raw['seconds'] ?? raw['duration']) ?? 6).clamp(2, 30).toDouble(),
    );
  }
}
