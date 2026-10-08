/// Diagramm-Skizzen ([QuestionType.sketch]): in vorgegebene Achsen eine
/// Kurve skizzieren (z.B. Längenänderung über der Temperatur mit Sprung bei
/// 911 °C, Spannungs-Dehnungs-Kurve mit R_p0,2/R_m/A, Potentialkurve). Die KI
/// liefert Achsen, eine Musterkurve und die Merkmale, auf die es ankommt –
/// geprüft wird grob in der App (SketchChecker), nicht pixelgenau.
library;

/// Ein Punkt in Achsen-Einheiten.
class SketchPoint {
  const SketchPoint(this.x, this.y);
  final double x;
  final double y;

  List<double> toList() => [x, y];

  static SketchPoint? fromRaw(Object? raw) {
    if (raw is List && raw.length >= 2 && raw[0] is num && raw[1] is num) {
      return SketchPoint((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
    }
    if (raw is Map && raw['x'] is num && raw['y'] is num) {
      return SketchPoint((raw['x'] as num).toDouble(), (raw['y'] as num).toDouble());
    }
    return null;
  }
}

double? _num(Object? raw) => raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}'.trim().replaceAll(',', '.'));

/// Eine Achse.
class SketchAxis {
  const SketchAxis({this.label = '', this.min = 0, this.max = 1, this.showNumbers = true});

  /// Beschriftung mit Einheit, z.B. "T in °C".
  final String label;
  final double min;
  final double max;

  /// Zahlen an der Achse (bei rein qualitativen Skizzen aus).
  final bool showNumbers;

  bool get isValid => max > min;
  double norm(double value) => (value - min) / (max - min);
  double denorm(double t) => min + t * (max - min);

  SketchAxis copyWith({String? label, double? min, double? max, bool? showNumbers}) => SketchAxis(
    label: label ?? this.label,
    min: min ?? this.min,
    max: max ?? this.max,
    showNumbers: showNumbers ?? this.showNumbers,
  );

  Map<String, dynamic> toMap() => {'label': label, 'min': min, 'max': max, if (!showNumbers) 'showNumbers': false};

  static SketchAxis fromMap(Object? raw) {
    if (raw is! Map) return const SketchAxis();
    final numbers = raw['showNumbers'] ?? raw['numbers'];
    return SketchAxis(
      label: '${raw['label'] ?? raw['name'] ?? ''}'.trim(),
      min: _num(raw['min']) ?? 0,
      max: _num(raw['max']) ?? 1,
      showNumbers: numbers == null || numbers == true || '$numbers'.toLowerCase() == 'true',
    );
  }
}

/// Worauf es bei der Skizze ankommt.
enum SketchFeatureKind {
  rising('steigt'),
  falling('fällt'),
  linear('verläuft gerade'),
  jumpDown('Sprung nach unten'),
  jumpUp('Sprung nach oben'),
  max('Maximum'),
  min('Minimum'),
  startsAt('beginnt bei'),
  endsAt('endet bei'),
  approaches('nähert sich an'),
  steeperLeft('links steiler als rechts'),
  mark('Markierung');

  const SketchFeatureKind(this.label);
  final String label;

  /// Bereich von–bis statt einer Stelle.
  bool get isRange => this == rising || this == falling || this == linear;
}

SketchFeatureKind? sketchFeatureKindFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  if (v.isEmpty) return null;
  for (final k in SketchFeatureKind.values) {
    if (k.name.toLowerCase() == v) return k;
  }
  return switch (v) {
    'increasing' || 'steigt' || 'steigend' || 'rise' => SketchFeatureKind.rising,
    'decreasing' || 'fällt' || 'fallend' || 'fall' => SketchFeatureKind.falling,
    'straight' || 'gerade' || 'linearer' => SketchFeatureKind.linear,
    'jump' || 'drop' || 'sprung' || 'sprungrunter' || 'sprungnachunten' => SketchFeatureKind.jumpDown,
    'sprunghoch' || 'sprungnachoben' || 'step' => SketchFeatureKind.jumpUp,
    'maximum' || 'peak' => SketchFeatureKind.max,
    'minimum' || 'tal' => SketchFeatureKind.min,
    'start' || 'beginnt' => SketchFeatureKind.startsAt,
    'end' || 'endet' || 'bruch' => SketchFeatureKind.endsAt,
    'asymptote' || 'approach' || 'annähern' => SketchFeatureKind.approaches,
    'asymmetric' || 'asymmetrie' || 'asymmetry' => SketchFeatureKind.steeperLeft,
    'label' || 'point' || 'punkt' || 'kennwert' || 'markieren' => SketchFeatureKind.mark,
    _ => null,
  };
}

/// Wo eine Markierung sitzen soll.
enum SketchAnchor {
  max('am Maximum der Kurve'),
  min('am Minimum der Kurve'),
  end('am Ende der Kurve'),
  start('am Anfang der Kurve'),
  beforeMax('auf der Kurve vor dem Maximum'),
  curve('auf der Kurve an der Stelle'),
  x('an der Stelle'),
  point('am Punkt');

  const SketchAnchor(this.label);
  final String label;
}

SketchAnchor sketchAnchorFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  for (final a in SketchAnchor.values) {
    if (a.name.toLowerCase() == v) return a;
  }
  if (v.contains('vormax') || v.contains('before')) return SketchAnchor.beforeMax;
  if (v.contains('max')) return SketchAnchor.max;
  if (v.contains('min')) return SketchAnchor.min;
  if (v.contains('ende') || v.contains('end') || v.contains('bruch')) return SketchAnchor.end;
  if (v.contains('anfang') || v.contains('start')) return SketchAnchor.start;
  if (v.contains('kurve') || v.contains('curve') || v.contains('on')) return SketchAnchor.curve;
  return SketchAnchor.point;
}

/// Ein Merkmal. Stellen ([x], [x2], [y]) in Achsen-Einheiten, [tol] als
/// Anteil der Achsenlänge (0.08 = 8 %).
class SketchFeature {
  const SketchFeature({
    required this.kind,
    this.x,
    this.x2,
    this.y,
    this.tol = 0.08,
    this.label = '',
    this.anchor = SketchAnchor.point,
    this.text = '',
  });

  final SketchFeatureKind kind;

  /// Stelle bzw. Bereichsanfang.
  final double? x;

  /// Bereichsende (steigt/fällt/gerade).
  final double? x2;

  /// Wert (annähern) bzw. Obergrenze (Minimum liegt unter [y]) bzw. Punkt einer Markierung.
  final double? y;
  final double tol;

  /// Name der Markierung (z.B. "R_m").
  final String label;
  final SketchAnchor anchor;

  /// Was gemeint ist, in einem Satz – Rückmeldung und Tipp
  /// ("Sprung nach unten bei 911 °C: krz → kfz, dichter gepackt").
  final String text;

  bool get isValid => switch (kind) {
    SketchFeatureKind.rising ||
    SketchFeatureKind.falling ||
    SketchFeatureKind.linear => x != null && x2 != null && x2! > x!,
    SketchFeatureKind.approaches => y != null,
    SketchFeatureKind.mark =>
      label.trim().isNotEmpty &&
          switch (anchor) {
            SketchAnchor.point => x != null && y != null,
            SketchAnchor.x || SketchAnchor.curve => x != null,
            _ => true,
          },
    SketchFeatureKind.max || SketchFeatureKind.min => true,
    _ => x != null,
  };

  SketchFeature copyWith({
    SketchFeatureKind? kind,
    double? x,
    double? x2,
    double? y,
    bool clearX = false,
    bool clearX2 = false,
    bool clearY = false,
    double? tol,
    String? label,
    SketchAnchor? anchor,
    String? text,
  }) => SketchFeature(
    kind: kind ?? this.kind,
    x: clearX ? null : (x ?? this.x),
    x2: clearX2 ? null : (x2 ?? this.x2),
    y: clearY ? null : (y ?? this.y),
    tol: tol ?? this.tol,
    label: label ?? this.label,
    anchor: anchor ?? this.anchor,
    text: text ?? this.text,
  );

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    if (x != null) 'x': x,
    if (x2 != null) 'x2': x2,
    if (y != null) 'y': y,
    if (tol != 0.08) 'tol': tol,
    if (kind == SketchFeatureKind.mark) 'label': label,
    if (kind == SketchFeatureKind.mark) 'anchor': anchor.name,
    if (text.trim().isNotEmpty) 'text': text.trim(),
  };

  static SketchFeature? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = sketchFeatureKindFrom(raw['kind'] ?? raw['type'] ?? raw['art']);
    if (kind == null) return null;
    final range = raw['range'] ?? raw['bereich'];
    final tol = _num(raw['tol'] ?? raw['tolerance']);
    return SketchFeature(
      kind: kind,
      x: _num(raw['x'] ?? raw['from'] ?? raw['at'] ?? (range is List && range.isNotEmpty ? range[0] : null)),
      x2: _num(raw['x2'] ?? raw['to'] ?? (range is List && range.length > 1 ? range[1] : null)),
      y: _num(raw['y'] ?? raw['value'] ?? raw['below']),
      tol: tol == null || tol <= 0 ? 0.08 : (tol > 0.5 ? 0.5 : tol),
      label: '${raw['label'] ?? raw['name'] ?? ''}'.trim(),
      anchor: sketchAnchorFrom(raw['anchor'] ?? raw['where'] ?? raw['ort']),
      text: '${raw['text'] ?? raw['feedback'] ?? raw['description'] ?? ''}'.trim(),
    );
  }
}

/// Die ganze Aufgabe.
class SketchTask {
  const SketchTask({
    required this.xAxis,
    required this.yAxis,
    required this.reference,
    required this.features,
    this.uncertain = false,
  });

  final SketchAxis xAxis;
  final SketchAxis yAxis;

  /// Musterkurve als Linienzüge (mehrere bei einem Sprung).
  final List<List<SketchPoint>> reference;
  final List<SketchFeature> features;

  /// Achsen oder Merkmale waren unklar – vor dem Speichern prüfen.
  final bool uncertain;

  List<SketchFeature> get marks => [
    for (final f in features)
      if (f.kind == SketchFeatureKind.mark) f,
  ];

  bool get isUsable =>
      xAxis.isValid &&
      yAxis.isValid &&
      reference.any((s) => s.length >= 2) &&
      features.isNotEmpty &&
      features.every((f) => f.isValid);

  SketchTask confirmed() => copyWith(uncertain: false);

  SketchTask copyWith({
    SketchAxis? xAxis,
    SketchAxis? yAxis,
    List<List<SketchPoint>>? reference,
    List<SketchFeature>? features,
    bool? uncertain,
  }) => SketchTask(
    xAxis: xAxis ?? this.xAxis,
    yAxis: yAxis ?? this.yAxis,
    reference: reference ?? this.reference,
    features: features ?? this.features,
    uncertain: uncertain ?? this.uncertain,
  );

  /// Kurzfassung (Kartenliste, Antwort-Vorschau).
  String describe() =>
      '${yAxis.label.isEmpty ? 'y' : yAxis.label} über ${xAxis.label.isEmpty ? 'x' : xAxis.label}: '
      '${[for (final f in features) f.kind == SketchFeatureKind.mark ? f.label : f.kind.label].join(', ')}';

  Map<String, dynamic> toMap() => {
    'kind': 'sketch',
    'xAxis': xAxis.toMap(),
    'yAxis': yAxis.toMap(),
    'reference': [
      for (final s in reference) [for (final p in s) p.toList()],
    ],
    'features': [for (final f in features) f.toMap()],
    if (uncertain) 'uncertain': true,
  };

  static SketchTask? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final features = raw['features'] ?? raw['merkmale'] ?? raw['checks'];
    if (features is! List) return null;
    final ref = raw['reference'] ?? raw['curve'] ?? raw['kurve'] ?? raw['musterkurve'];
    final strokes = <List<SketchPoint>>[];
    if (ref is List && ref.isNotEmpty) {
      // Ein Linienzug [[x, y], …] oder mehrere [[[x, y], …], …].
      final nested = ref.first is List && (ref.first as List).isNotEmpty && (ref.first as List).first is! num;
      for (final s in nested ? ref : [ref]) {
        if (s is! List) continue;
        final points = [for (final p in s) ?SketchPoint.fromRaw(p)];
        if (points.isNotEmpty) strokes.add(points);
      }
    }
    final u = raw['uncertain'] ?? raw['unsicher'];
    return SketchTask(
      xAxis: SketchAxis.fromMap(raw['xAxis'] ?? raw['x']),
      yAxis: SketchAxis.fromMap(raw['yAxis'] ?? raw['y']),
      reference: strokes,
      features: [for (final f in features) ?SketchFeature.fromMap(f)],
      uncertain: u == true || '$u'.toLowerCase() == 'true',
    );
  }

  /// Musterkurve als Text für den Editor: "x; y" je Zeile, Leerzeile = neuer Linienzug.
  static String referenceText(List<List<SketchPoint>> strokes) => [
    for (final s in strokes) [for (final p in s) '${_fmt(p.x)}; ${_fmt(p.y)}'].join('\n'),
  ].join('\n\n');

  static String _fmt(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
    return v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  }

  static ({List<List<SketchPoint>> strokes, String? error}) parseReference(String text) {
    final strokes = <List<SketchPoint>>[];
    var current = <SketchPoint>[];
    for (final (i, line) in text.split('\n').indexed) {
      final l = line.trim();
      if (l.isEmpty) {
        if (current.isNotEmpty) strokes.add(current);
        current = [];
        continue;
      }
      final parts = l.split(RegExp(r'\s*[;|\t]\s*|\s+'));
      final x = parts.isNotEmpty ? _num(parts[0]) : null;
      final y = parts.length > 1 ? _num(parts[1]) : null;
      if (x == null || y == null) return (strokes: const [], error: 'Zeile ${i + 1}: „x; y“ erwartet.');
      current.add(SketchPoint(x, y));
    }
    if (current.isNotEmpty) strokes.add(current);
    if (!strokes.any((s) => s.length >= 2)) {
      return (strokes: strokes, error: 'Die Musterkurve braucht mindestens 2 Punkte.');
    }
    return (strokes: strokes, error: null);
  }
}
