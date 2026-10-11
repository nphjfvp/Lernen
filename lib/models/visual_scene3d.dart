/// Räumliche Szene für „Visuell lernen“ – nur dort, wo der räumliche Aufbau
/// wesentlich ist (Elementarzellen, Packungsdichte, Lücken im Gitter,
/// Gleitebenen, Moleküle, Kräfte im Raum). Die KI liefert Kugeln, Linien,
/// Pfeile, Quader, ebene Flächen und Text mit 3D-Koordinaten und
/// Schlüsselbildern; die App projiziert, sortiert nach Tiefe und lässt drehen.
/// Für fast alles andere bleibt die 2D-Szene ([VisualDiagram]) die erste Wahl.
library;

double? _num(Object? raw) => raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}'.trim().replaceAll(',', '.'));

String _str(Object? raw) => '${raw ?? ''}'.trim();

List<double>? _vec(Object? raw) {
  if (raw is List && raw.length >= 3) {
    final v = [for (final x in raw.take(3)) _num(x)];
    if (v.every((x) => x != null)) return [for (final x in v) x!];
  }
  if (raw is Map) {
    final v = [_num(raw['x']), _num(raw['y']), _num(raw['z'])];
    if (v.every((x) => x != null)) return [for (final x in v) x!];
  }
  return null;
}

List<List<double>>? _vecs(Object? raw) {
  if (raw is! List) return null;
  final out = [for (final p in raw) ?_vec(p)];
  return out.length >= 3 ? out : null;
}

/// Zahl-Eigenschaften, die sich animieren lassen.
const scene3dNumberProps = ['r', 'opacity', 'width', 'draw', 'size'];

/// Vektor-Eigenschaften (x, y, z), die sich animieren lassen.
const scene3dVectorProps = ['at', 'from', 'to', 'dims'];

/// Ein Schlüsselbild zum Zeitpunkt [at] (0…1).
class Scene3DKey {
  const Scene3DKey({
    required this.at,
    this.numbers = const {},
    this.vectors = const {},
    this.points,
    this.fill,
    this.stroke,
    this.text,
  });

  final double at;
  final Map<String, double> numbers;
  final Map<String, List<double>> vectors;
  final List<List<double>>? points;
  final String? fill;
  final String? stroke;
  final String? text;

  Map<String, dynamic> toMap() => {
    't': at,
    ...numbers,
    ...vectors,
    'points': ?points,
    'fill': ?fill,
    'stroke': ?stroke,
    'text': ?text,
  };

  static Scene3DKey? fromMap(Object? raw) {
    if (raw is! Map) return null;
    // „at“ ist bei Formen die Position – die Zeit heißt hier „t“.
    final t = _num(raw['t'] ?? raw['time'] ?? (raw['at'] is num ? raw['at'] : null));
    if (t == null) return null;
    final fill = _str(raw['fill'] ?? raw['color']);
    final stroke = _str(raw['stroke']);
    return Scene3DKey(
      at: t.clamp(0, 1).toDouble(),
      numbers: {for (final k in scene3dNumberProps) k: ?_num(raw[k])},
      vectors: {for (final k in scene3dVectorProps) k: ?_vec(raw[k])},
      points: _vecs(raw['points']),
      fill: fill.isEmpty ? null : fill,
      stroke: stroke.isEmpty ? null : stroke,
      text: raw['text'] == null ? null : _str(raw['text']),
    );
  }
}

enum Scene3DShape { sphere, line, arrow, box, polygon, text }

Scene3DShape? _shape(String raw) => switch (raw.toLowerCase()) {
  'sphere' || 'kugel' || 'atom' || 'ball' => Scene3DShape.sphere,
  'line' || 'linie' || 'edge' || 'kante' => Scene3DShape.line,
  'arrow' || 'pfeil' || 'vector' => Scene3DShape.arrow,
  'box' || 'cube' || 'quader' || 'würfel' || 'wuerfel' => Scene3DShape.box,
  'polygon' || 'plane' || 'ebene' || 'face' || 'fläche' || 'flaeche' => Scene3DShape.polygon,
  'text' || 'label' => Scene3DShape.text,
  _ => null,
};

/// Ein Objekt der Szene; mit Raster ([n] Kopien je Richtung im Abstand [d])
/// z.B. alle Atome eines Gitters.
class Scene3DObject {
  const Scene3DObject({
    required this.shape,
    this.numbers = const {},
    this.vectors = const {},
    this.points = const [],
    this.fill = '',
    this.stroke = '',
    this.text = '',
    this.dashed = false,
    this.keys = const [],
    this.n = const [1, 1, 1],
    this.d = const [0, 0, 0],
  });

  final Scene3DShape shape;
  final Map<String, double> numbers;
  final Map<String, List<double>> vectors;
  final List<List<double>> points;
  final String fill;
  final String stroke;
  final String text;
  final bool dashed;
  final List<Scene3DKey> keys;
  final List<int> n;
  final List<double> d;

  int get copies => n[0] * n[1] * n[2];

  static T? _track<T>(List<(double, T)> track, double p, T Function(T a, T b, double f) lerp) {
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

  static List<double> _lerpVec(List<double> a, List<double> b, double f) => [
    for (var i = 0; i < 3; i++) a[i] + (b[i] - a[i]) * f,
  ];

  double? number(String prop, double p) => _track(
    [
      if (numbers[prop] case final v?) (0.0, v),
      for (final k in keys)
        if (k.numbers[prop] case final v?) (k.at, v),
    ],
    p,
    (a, b, f) => a + (b - a) * f,
  );

  List<double>? vector(String prop, double p) => _track(
    [
      if (vectors[prop] case final v?) (0.0, v),
      for (final k in keys)
        if (k.vectors[prop] case final v?) (k.at, v),
    ],
    p,
    _lerpVec,
  );

  List<List<double>> pointsAt(double p) =>
      _track(
        [
          if (points.isNotEmpty) (0.0, points),
          for (final k in keys)
            if (k.points != null) (k.at, k.points!),
        ],
        p,
        (a, b, f) =>
            a.length != b.length ? (f < 0.5 ? a : b) : [for (var i = 0; i < a.length; i++) _lerpVec(a[i], b[i], f)],
      ) ??
      const [];

  /// Farbverlauf (von, nach, Anteil).
  (String, String, double)? colorAt(String which, double p) {
    final base = which == 'fill' ? fill : stroke;
    final track = <(double, String)>[
      if (base.isNotEmpty) (0.0, base),
      for (final k in keys)
        if ((which == 'fill' ? k.fill : k.stroke) case final c?) (k.at, c),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (track.isEmpty) return null;
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

  String textAt(double p) {
    var out = text;
    for (final k in [...keys]..sort((a, b) => a.at.compareTo(b.at))) {
      if (k.at <= p && k.text != null) out = k.text!;
    }
    return out;
  }

  Map<String, dynamic> toMap() => {
    'type': shape.name,
    ...numbers,
    ...vectors,
    if (points.isNotEmpty) 'points': points,
    if (fill.isNotEmpty) 'fill': fill,
    if (stroke.isNotEmpty) 'stroke': stroke,
    if (text.isNotEmpty) 'text': text,
    if (dashed) 'dashed': true,
    if (copies > 1) 'repeat': {'n': n, 'd': d},
    if (keys.isNotEmpty) 'keys': [for (final k in keys) k.toMap()],
  };

  static Scene3DObject? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final shape = _shape(_str(raw['type'] ?? raw['shape']));
    if (shape == null) return null;
    final vectors = {for (final k in scene3dVectorProps) k: ?_vec(raw[k])};
    // Gängige Schreibweisen: "pos"/"center" für "at", "size" als Vektor bei Quadern.
    final pos = vectors['at'] ?? _vec(raw['pos'] ?? raw['position'] ?? raw['center']);
    if (pos != null) vectors['at'] = pos;
    final dims = shape == Scene3DShape.box ? _vec(raw['size']) : null;
    if (dims != null) vectors['dims'] ??= dims;
    final numbers = {
      for (final k in scene3dNumberProps)
        if (!(k == 'size' && raw[k] is List)) k: ?_num(raw[k]),
    };
    final points = _vecs(raw['points']) ?? const [];
    final text = _str(raw['text'] ?? raw['label']);
    final ok = switch (shape) {
      Scene3DShape.sphere || Scene3DShape.box => vectors.containsKey('at'),
      Scene3DShape.line || Scene3DShape.arrow => vectors.containsKey('from') && vectors.containsKey('to'),
      Scene3DShape.polygon => points.length >= 3,
      Scene3DShape.text => vectors.containsKey('at') && text.isNotEmpty,
    };
    if (!ok) return null;
    final repeat = raw['repeat'] is Map ? raw['repeat'] as Map : const {};
    final rn = repeat['n'], rd = repeat['d'];
    int count(Object? v) => (_num(v) ?? 1).round().clamp(1, 8);
    final rawKeys = raw['keys'] ?? raw['keyframes'];
    return Scene3DObject(
      shape: shape,
      numbers: numbers,
      vectors: vectors,
      points: points,
      fill: _str(raw['fill'] ?? (shape == Scene3DShape.sphere || shape == Scene3DShape.text ? raw['color'] : null)),
      stroke: _str(raw['stroke'] ?? (shape == Scene3DShape.line || shape == Scene3DShape.arrow ? raw['color'] : null)),
      text: text,
      dashed: raw['dashed'] == true,
      keys: [
        if (rawKeys is List)
          for (final k in rawKeys) ?Scene3DKey.fromMap(k),
      ],
      n: rn is List && rn.length >= 3 ? [for (final v in rn.take(3)) count(v)] : const [1, 1, 1],
      d: _vec(rd) ?? const [0, 0, 0],
    );
  }
}

/// Die ganze räumliche Szene.
class VisualScene3D {
  const VisualScene3D({
    this.box = const [1, 1, 1],
    this.frame = true,
    this.axes = true,
    this.spin = false,
    this.objects = const [],
    this.captions = const [],
    this.paramName = '',
    this.paramUnit = '',
    this.paramFrom = 0,
    this.paramTo = 1,
    this.seconds = 6,
  });

  /// Raum 0…box (x, y, z; z nach oben).
  final List<double> box;

  /// Kanten des Raums zeichnen (z.B. die Elementarzelle).
  final bool frame;
  final bool axes;

  /// Beim Abspielen langsam einmal herumdrehen.
  final bool spin;
  final List<Scene3DObject> objects;
  final List<({double at, String text})> captions;
  final String paramName;
  final String paramUnit;
  final double paramFrom;
  final double paramTo;
  final double seconds;

  /// Höchstens so viele Objekte (Raster mitgezählt) – flüssig auch am Handy.
  static const maxObjects = 400;

  bool get hasParam => paramName.isNotEmpty;

  double paramAt(double p) => paramFrom + (paramTo - paramFrom) * p;

  String captionAt(double p) {
    var out = '';
    for (final c in [...captions]..sort((a, b) => a.at.compareTo(b.at))) {
      if (c.at <= p) out = c.text;
    }
    return out;
  }

  Map<String, dynamic> toMap() => {
    'box': box,
    if (!frame) 'frame': false,
    if (!axes) 'axes': false,
    if (spin) 'spin': true,
    'objects': [for (final o in objects) o.toMap()],
    if (captions.isNotEmpty)
      'captions': [
        for (final c in captions) {'at': c.at, 'text': c.text},
      ],
    if (hasParam) 'param': {'name': paramName, 'unit': paramUnit, 'from': paramFrom, 'to': paramTo},
    'seconds': seconds,
  };

  static VisualScene3D? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final rawObjects = raw['objects'] ?? raw['elements'];
    final objects = <Scene3DObject>[];
    var count = 0;
    if (rawObjects is List) {
      for (final o in rawObjects) {
        final obj = Scene3DObject.fromMap(o);
        if (obj == null || count + obj.copies > maxObjects) continue;
        count += obj.copies;
        objects.add(obj);
      }
    }
    if (objects.isEmpty) return null;
    final box = _vec(raw['box'] ?? raw['size']) ?? const [1.0, 1.0, 1.0];
    final rawCaptions = raw['captions'];
    final param = raw['param'] is Map ? raw['param'] as Map : const {};
    return VisualScene3D(
      box: [for (final v in box) v <= 0 ? 1.0 : v],
      frame: raw['frame'] != false,
      axes: raw['axes'] != false,
      spin: raw['spin'] == true,
      objects: objects,
      captions: [
        if (rawCaptions is List)
          for (final c in rawCaptions)
            if (c is Map && _str(c['text']).isNotEmpty)
              (at: (_num(c['at']) ?? 0).clamp(0, 1).toDouble(), text: _str(c['text'])),
      ],
      paramName: _str(param['name']),
      paramUnit: _str(param['unit']),
      paramFrom: _num(param['from']) ?? 0,
      paramTo: _num(param['to']) ?? 1,
      seconds: (_num(raw['seconds'] ?? raw['duration']) ?? 6).clamp(2, 30).toDouble(),
    );
  }
}
