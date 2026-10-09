/// Zustandsdiagramme ([QuestionType.phase]): ein Zweistoffsystem mit
/// Eutektikum (z.B. Pb-Sn) oder Eutektoid (Stahlecke des Fe-Fe₃C-Diagramms).
/// Die KI liest nur die Eckdaten ab (Schmelzpunkte, eutektischer Punkt,
/// Löslichkeitsgrenzen, bei Bedarf Zwischenpunkte gekrümmter Linien) – alles
/// Weitere rechnet die App selbst (PhaseCalculator): Phasen an einem Punkt,
/// Hebelgesetz, Gefügeanteile, Abkühlkurven, Zusammensetzung zu einer
/// Liquidustemperatur, Gebiete.
library;

double? _num(Object? raw) => raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}'.trim().replaceAll(',', '.'));

/// Ein Punkt im Diagramm: Zusammensetzung [c] (Anteil von B) und Temperatur [t].
class PhasePoint {
  const PhasePoint(this.c, this.t);
  final double c;
  final double t;

  List<double> toList() => [c, t];

  static PhasePoint? fromRaw(Object? raw) {
    if (raw is List && raw.length >= 2) {
      final c = _num(raw[0]), t = _num(raw[1]);
      return c == null || t == null ? null : PhasePoint(c, t);
    }
    if (raw is Map) {
      final c = _num(raw['c'] ?? raw['x']), t = _num(raw['t'] ?? raw['T'] ?? raw['y']);
      return c == null || t == null ? null : PhasePoint(c, t);
    }
    return null;
  }
}

/// Die Linien des Diagramms.
enum PhaseLine {
  liquidusLeft('Liquidus links'),
  liquidusRight('Liquidus rechts'),
  solidusLeft('Solidus links'),
  solidusRight('Solidus rechts'),
  solvusLeft('Löslichkeitslinie links'),
  solvusRight('Löslichkeitslinie rechts');

  const PhaseLine(this.label);
  final String label;
}

/// Die Zustandsgebiete.
enum PhaseRegion { liquid, liquidAlpha, alpha, liquidBeta, beta, alphaBeta }

PhaseRegion? phaseRegionFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase().replaceAll(RegExp(r'[\s_+\-]'), '');
  for (final r in PhaseRegion.values) {
    if (r.name.toLowerCase() == v) return r;
  }
  return switch (v) {
    'l' || 'schmelze' || 'liquid' || 'flüssig' || 'austenit' || 'gamma' || 'γ' => PhaseRegion.liquid,
    'alpha' || 'α' || 'αmk' || 'ferrit' || 'alphamischkristall' => PhaseRegion.alpha,
    'beta' || 'β' || 'βmk' || 'zementit' => PhaseRegion.beta,
    'alphaliquid' || 'lalpha' || 'αl' || 'lα' || 'schmelzeα' || 'αschmelze' => PhaseRegion.liquidAlpha,
    'betaliquid' || 'lbeta' || 'βl' || 'lβ' || 'schmelzeβ' || 'βschmelze' => PhaseRegion.liquidBeta,
    'alphabeta' || 'αβ' || 'βα' => PhaseRegion.alphaBeta,
    _ => null,
  };
}

/// Das Zweistoffsystem.
class PhaseSystem {
  const PhaseSystem({
    this.a = 'A',
    this.b = 'B',
    this.unit = 'Masse-%',
    this.cMax = 100,
    this.tMin = 0,
    this.tMax = 400,
    this.liquid = 'Schmelze',
    this.alpha = 'α',
    this.beta = 'β',
    this.eutecticName = 'Eutektikum',
    this.eutectoid = false,
    this.structureNames = false,
    required this.meltA,
    required this.eutecticC,
    required this.eutecticT,
    required this.rightC,
    required this.rightT,
    required this.alphaMax,
    required this.alphaLow,
    required this.betaMax,
    required this.betaLow,
    this.lines = const {},
  });

  /// Die beiden Komponenten (A links bei 0 %, B rechts).
  final String a;
  final String b;

  /// Einheit der Zusammensetzung (Masse-%, Gew.-%, At.-%).
  final String unit;

  /// Rechtes Ende der Zusammensetzungsachse (100, bei der Stahlecke z.B. 2,1).
  final double cMax;
  final double tMin;
  final double tMax;

  /// Namen: Schmelze (bei der Stahlecke: Austenit γ), Mischkristalle bzw.
  /// Phasen links und rechts, das eutektische (eutektoide) Gefüge.
  final String liquid;
  final String alpha;
  final String beta;
  final String eutecticName;

  /// Eutektoid (Umwandlung im festen Zustand, z.B. γ → α + Fe₃C): Wörter
  /// "Umwandlung" statt "Erstarrung".
  final bool eutectoid;

  /// Unter der eutektischen Linie nach Gefüge beschriften („Eutektikum +
  /// α“ links, „Eutektikum + β“ rechts, getrennt an der eutektischen
  /// Zusammensetzung) statt nach Phasen („α + β“) – wie in vielen Skripten.
  final bool structureNames;

  /// Schmelz- (bzw. Umwandlungs-)Temperatur von A.
  final double meltA;
  final double eutecticC;
  final double eutecticT;

  /// Rechtes Ende der rechten Liquiduslinie (reines B: [cMax], Schmelzpunkt
  /// von B; Stahlecke: Punkt E).
  final double rightC;
  final double rightT;

  /// Größte Löslichkeit von B in α (bei der eutektischen Temperatur) und
  /// Löslichkeit bei [tMin].
  final double alphaMax;
  final double alphaLow;

  /// Zusammensetzung von β bei der eutektischen Temperatur und bei [tMin]
  /// (Zementit: beide 6,67).
  final double betaMax;
  final double betaLow;

  /// Gekrümmte Linien als Zwischenpunkte (sonst Geraden zwischen den Eckdaten).
  final Map<PhaseLine, List<PhasePoint>> lines;

  bool get isValid =>
      cMax > 0 &&
      tMax > tMin &&
      eutecticC > 0 &&
      eutecticC < cMax + 1e-9 &&
      meltA > eutecticT &&
      rightT > eutecticT &&
      rightC > eutecticC &&
      alphaMax >= 0 &&
      alphaMax < eutecticC &&
      betaMax > eutecticC &&
      alphaLow <= alphaMax + 1e-9 &&
      betaLow >= betaMax - 1e-9;

  /// Linienzug einer Linie (Zwischenpunkte oder Gerade aus den Eckdaten).
  List<PhasePoint> line(PhaseLine l) {
    final custom = lines[l];
    if (custom != null && custom.length >= 2) return custom;
    return switch (l) {
      PhaseLine.liquidusLeft => [PhasePoint(0, meltA), PhasePoint(eutecticC, eutecticT)],
      PhaseLine.liquidusRight => [PhasePoint(eutecticC, eutecticT), PhasePoint(rightC, rightT)],
      PhaseLine.solidusLeft => [PhasePoint(0, meltA), PhasePoint(alphaMax, eutecticT)],
      PhaseLine.solidusRight => [PhasePoint(betaMax, eutecticT), PhasePoint(rightC, rightT)],
      PhaseLine.solvusLeft => [PhasePoint(alphaMax, eutecticT), PhasePoint(alphaLow, tMin)],
      PhaseLine.solvusRight => [PhasePoint(betaMax, eutecticT), PhasePoint(betaLow, tMin)],
    };
  }

  /// Name eines Gebiets (wie im Diagramm beschriftet).
  String regionName(PhaseRegion r) => switch (r) {
    PhaseRegion.liquid => liquid,
    PhaseRegion.liquidAlpha => '$liquid + $alpha',
    PhaseRegion.alpha => alpha,
    PhaseRegion.liquidBeta => '$liquid + $beta',
    PhaseRegion.beta => beta,
    PhaseRegion.alphaBeta => '$alpha + $beta',
  };

  /// Die Phasen eines Gebiets.
  List<String> phasesOf(PhaseRegion r) => switch (r) {
    PhaseRegion.liquid => [liquid],
    PhaseRegion.liquidAlpha => [liquid, alpha],
    PhaseRegion.alpha => [alpha],
    PhaseRegion.liquidBeta => [liquid, beta],
    PhaseRegion.beta => [beta],
    PhaseRegion.alphaBeta => [alpha, beta],
  };

  List<String> get allPhases => [liquid, alpha, beta];

  Map<String, dynamic> toMap() => {
    'a': a,
    'b': b,
    'unit': unit,
    'cMax': cMax,
    'tMin': tMin,
    'tMax': tMax,
    'liquid': liquid,
    'alpha': alpha,
    'beta': beta,
    'eutecticName': eutecticName,
    if (eutectoid) 'eutectoid': true,
    if (structureNames) 'structureNames': true,
    'meltA': meltA,
    'eutecticC': eutecticC,
    'eutecticT': eutecticT,
    'rightC': rightC,
    'rightT': rightT,
    'alphaMax': alphaMax,
    'alphaLow': alphaLow,
    'betaMax': betaMax,
    'betaLow': betaLow,
    if (lines.isNotEmpty)
      'lines': {
        for (final e in lines.entries) e.key.name: [for (final p in e.value) p.toList()],
      },
  };

  PhaseSystem copyWith({
    String? a,
    String? b,
    String? unit,
    double? cMax,
    double? tMin,
    double? tMax,
    String? liquid,
    String? alpha,
    String? beta,
    String? eutecticName,
    bool? eutectoid,
    bool? structureNames,
    double? meltA,
    double? eutecticC,
    double? eutecticT,
    double? rightC,
    double? rightT,
    double? alphaMax,
    double? alphaLow,
    double? betaMax,
    double? betaLow,
    Map<PhaseLine, List<PhasePoint>>? lines,
  }) => PhaseSystem(
    a: a ?? this.a,
    b: b ?? this.b,
    unit: unit ?? this.unit,
    cMax: cMax ?? this.cMax,
    tMin: tMin ?? this.tMin,
    tMax: tMax ?? this.tMax,
    liquid: liquid ?? this.liquid,
    alpha: alpha ?? this.alpha,
    beta: beta ?? this.beta,
    eutecticName: eutecticName ?? this.eutecticName,
    eutectoid: eutectoid ?? this.eutectoid,
    structureNames: structureNames ?? this.structureNames,
    meltA: meltA ?? this.meltA,
    eutecticC: eutecticC ?? this.eutecticC,
    eutecticT: eutecticT ?? this.eutecticT,
    rightC: rightC ?? this.rightC,
    rightT: rightT ?? this.rightT,
    alphaMax: alphaMax ?? this.alphaMax,
    alphaLow: alphaLow ?? this.alphaLow,
    betaMax: betaMax ?? this.betaMax,
    betaLow: betaLow ?? this.betaLow,
    lines: lines ?? this.lines,
  );

  static PhaseSystem? fromMap(Object? raw) {
    if (raw is! Map) return null;
    double? n(List<String> keys) {
      for (final k in keys) {
        final v = _num(raw[k]);
        if (v != null) return v;
      }
      return null;
    }

    final cMax = n(['cMax', 'cmax', 'maxC']) ?? 100;
    final meltA = n(['meltA', 'tA', 'schmelzA']);
    final cE = n(['eutecticC', 'cE', 'eutektischC']);
    final tE = n(['eutecticT', 'tE', 'eutektischT']);
    final alphaMax = n(['alphaMax', 'alphaSolubility', 'loeslichkeitAlpha']);
    final betaMax = n(['betaMax', 'betaSolubility', 'loeslichkeitBeta']);
    if (meltA == null || cE == null || tE == null || alphaMax == null || betaMax == null) return null;
    final rightC = n(['rightC', 'cRight']) ?? cMax;
    final rightT = n(['rightT', 'meltB', 'tB', 'schmelzB']);
    if (rightT == null) return null;
    final rawLines = raw['lines'] ?? raw['linien'];
    final lines = <PhaseLine, List<PhasePoint>>{};
    if (rawLines is Map) {
      for (final l in PhaseLine.values) {
        final pts = rawLines[l.name];
        if (pts is! List) continue;
        final points = [for (final p in pts) ?PhasePoint.fromRaw(p)];
        if (points.length >= 2) lines[l] = points;
      }
    }
    String s(List<String> keys, String fallback) {
      for (final k in keys) {
        final v = '${raw[k] ?? ''}'.trim();
        if (v.isNotEmpty) return v;
      }
      return fallback;
    }

    final eutectoid = raw['eutectoid'] == true || '${raw['eutectoid']}'.toLowerCase() == 'true';
    return PhaseSystem(
      a: s(['a', 'componentA', 'komponenteA'], 'A'),
      b: s(['b', 'componentB', 'komponenteB'], 'B'),
      unit: s(['unit', 'einheit'], 'Masse-%'),
      cMax: cMax,
      tMin: n(['tMin', 'tmin']) ?? 0,
      tMax: n(['tMax', 'tmax']) ?? (([meltA, rightT].reduce((x, y) => x > y ? x : y)) * 1.1).roundToDouble(),
      liquid: s(['liquid', 'schmelze'], eutectoid ? 'γ' : 'Schmelze'),
      alpha: s(['alpha'], 'α'),
      beta: s(['beta'], 'β'),
      eutecticName: s(['eutecticName', 'eutektikum'], eutectoid ? 'Perlit' : 'Eutektikum'),
      eutectoid: eutectoid,
      structureNames: raw['structureNames'] == true || '${raw['structureNames']}'.toLowerCase() == 'true',
      meltA: meltA,
      eutecticC: cE,
      eutecticT: tE,
      rightC: rightC,
      rightT: rightT,
      alphaMax: alphaMax,
      alphaLow: n(['alphaLow', 'alphaMin', 'alphaRoom']) ?? alphaMax,
      betaMax: betaMax,
      betaLow: n(['betaLow', 'betaMin', 'betaRoom']) ?? betaMax,
      lines: lines,
    );
  }
}

/// Art einer Teilaufgabe.
enum PhasePartKind {
  phases('Phasen'),
  lever('Hebelgesetz'),
  structure('Gefügeanteile'),
  cooling('Abkühlkurven'),
  composition('Zusammensetzung'),
  solubility('Löslichkeit'),
  eutecticLine('Eutektische Linie'),
  regions('Gebiete benennen'),
  pickRegion('Gebiet zeigen'),
  question('Frage');

  const PhasePartKind(this.label);
  final String label;
}

PhasePartKind? phasePartKindFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
  for (final k in PhasePartKind.values) {
    if (k.name.toLowerCase() == v) return k;
  }
  return switch (v) {
    'phasen' || 'phase' || 'welchephasen' => PhasePartKind.phases,
    'hebel' || 'hebelgesetz' || 'phasenanteile' || 'leverrule' || 'anteile' => PhasePartKind.lever,
    'gefuege' || 'gefüge' || 'gefügeanteile' || 'gefuegeanteile' || 'microstructure' => PhasePartKind.structure,
    'abkuehlkurve' || 'abkühlkurve' || 'abkühlkurven' || 'abkuehlkurven' || 'coolingcurve' => PhasePartKind.cooling,
    'zusammensetzung' || 'legierung' || 'liquidus' => PhasePartKind.composition,
    'loeslichkeit' || 'löslichkeit' => PhasePartKind.solubility,
    'eutektischelinie' || 'eutectic' || 'eutectoidline' => PhasePartKind.eutecticLine,
    'gebiete' || 'benennen' || 'labels' || 'beschriften' => PhasePartKind.regions,
    'gebiet' || 'region' || 'bereich' || 'markieren' => PhasePartKind.pickRegion,
    'frage' ||
    'text' ||
    'freetext' ||
    'erklaeren' ||
    'erklären' ||
    'choice' ||
    'singlechoice' => PhasePartKind.question,
    _ => null,
  };
}

/// Eine Teilaufgabe.
class PhasePart {
  const PhasePart({
    required this.kind,
    this.c,
    this.t,
    this.compositions = const [],
    this.labels = const [],
    this.side = 'b',
    this.region,
    this.curveGiven = false,
    this.prompt = '',
    this.answer = '',
    this.options = const [],
    this.correct,
  });

  final PhasePartKind kind;

  /// Zusammensetzung (Anteil B) bzw. Temperatur des gefragten Punkts.
  final double? c;
  final double? t;

  /// Abkühlkurven: die Zusammensetzungen.
  final List<double> compositions;

  /// Abkühlkurven: Namen wie auf dem Blatt (z.B. "Eutektische Legierung"),
  /// je Zusammensetzung; leer = die App benennt sie selbst.
  final List<String> labels;

  /// Löslichkeit: 'b' = von B in α (links), 'a' = von A in β (rechts).
  final String side;

  /// Gebiet zeigen: das gesuchte Gebiet.
  final PhaseRegion? region;

  /// Zusammensetzung: statt der Temperatur ist eine gemessene Abkühlkurve
  /// gegeben (Knick bei [t], Haltepunkt bei der eutektischen Temperatur) –
  /// die App zeigt die Kurve, man liest selbst ab.
  final bool curveGiven;

  /// Eigener Aufgabentext (sonst schreibt ihn die App).
  final String prompt;

  /// Frage ([PhasePartKind.question]): Musterantwort bzw. Auswahl.
  final String answer;
  final List<String> options;
  final int? correct;

  bool get isChoice => options.length >= 2 && correct != null && correct! >= 0 && correct! < options.length;

  bool get isValid => switch (kind) {
    PhasePartKind.phases || PhasePartKind.lever => c != null && t != null,
    PhasePartKind.structure => c != null,
    PhasePartKind.cooling => compositions.isNotEmpty,
    PhasePartKind.composition => t != null,
    PhasePartKind.pickRegion => region != null,
    PhasePartKind.question => prompt.trim().isNotEmpty && (isChoice || answer.trim().isNotEmpty),
    _ => true,
  };

  PhasePart copyWith({
    PhasePartKind? kind,
    double? c,
    double? t,
    bool clearC = false,
    bool clearT = false,
    List<double>? compositions,
    List<String>? labels,
    String? side,
    PhaseRegion? region,
    bool? curveGiven,
    String? prompt,
    String? answer,
    List<String>? options,
    int? correct,
    bool clearCorrect = false,
  }) => PhasePart(
    kind: kind ?? this.kind,
    c: clearC ? null : (c ?? this.c),
    t: clearT ? null : (t ?? this.t),
    compositions: compositions ?? this.compositions,
    labels: labels ?? this.labels,
    side: side ?? this.side,
    region: region ?? this.region,
    curveGiven: curveGiven ?? this.curveGiven,
    prompt: prompt ?? this.prompt,
    answer: answer ?? this.answer,
    options: options ?? this.options,
    correct: clearCorrect ? null : (correct ?? this.correct),
  );

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    if (c != null) 'c': c,
    if (t != null) 't': t,
    if (compositions.isNotEmpty) 'compositions': compositions,
    if (labels.any((l) => l.trim().isNotEmpty)) 'labels': labels,
    if (kind == PhasePartKind.solubility) 'side': side,
    if (region != null) 'region': region!.name,
    if (curveGiven) 'curveGiven': true,
    if (prompt.trim().isNotEmpty) 'prompt': prompt.trim(),
    if (answer.trim().isNotEmpty) 'answer': answer.trim(),
    if (options.isNotEmpty) 'options': options,
    if (correct != null) 'correct': correct,
  };

  static PhasePart? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = phasePartKindFrom(raw['kind'] ?? raw['type'] ?? raw['art']);
    if (kind == null) return null;
    final comps = raw['compositions'] ?? raw['zusammensetzungen'] ?? raw['alloys'];
    final labels = raw['labels'] ?? raw['names'] ?? raw['namen'];
    final side = '${raw['side'] ?? raw['seite'] ?? 'b'}'.toLowerCase().trim();
    final given = raw['curveGiven'] ?? raw['kurveGegeben'];
    final rawOptions = raw['options'] ?? raw['optionen'] ?? raw['choices'];
    // Optionen als Texte oder als {"text", "correct"}.
    final options = <String>[];
    int? correct = (raw['correct'] is num) ? (raw['correct'] as num).toInt() : int.tryParse('${raw['correct'] ?? ''}');
    if (rawOptions is List) {
      for (final o in rawOptions) {
        if (o is Map) {
          final text = '${o['text'] ?? ''}'.trim();
          if (text.isEmpty) continue;
          final flag = o['correct'] ?? o['isCorrect'];
          if (flag == true || '$flag'.toLowerCase() == 'true') correct = options.length;
          options.add(text);
        } else if ('${o ?? ''}'.trim().isNotEmpty) {
          options.add('$o'.trim());
        }
      }
    }
    return PhasePart(
      kind: kind,
      c: _num(raw['c'] ?? raw['composition'] ?? raw['zusammensetzung']),
      t: _num(raw['t'] ?? raw['T'] ?? raw['temperature'] ?? raw['temperatur']),
      compositions: [
        if (comps is List)
          for (final v in comps) ?_num(v),
      ],
      labels: [
        if (labels is List)
          for (final l in labels) '${l ?? ''}'.trim(),
      ],
      side: side == 'a' || side == 'left' || side == 'links' ? 'a' : 'b',
      region: phaseRegionFrom(raw['region'] ?? raw['gebiet']),
      curveGiven: given == true || '$given'.toLowerCase() == 'true',
      prompt: '${raw['prompt'] ?? raw['frage'] ?? ''}'.trim(),
      answer: '${raw['answer'] ?? raw['antwort'] ?? raw['solution'] ?? ''}'.trim(),
      options: options,
      correct: correct,
    );
  }
}

/// Die ganze Aufgabe.
class PhaseTask {
  const PhaseTask({required this.system, required this.parts, this.uncertain = false});

  final PhaseSystem system;
  final List<PhasePart> parts;

  /// Werte waren schlecht ablesbar – vor dem Speichern prüfen.
  final bool uncertain;

  bool get isUsable => system.isValid && parts.isNotEmpty && parts.every((p) => p.isValid);

  PhaseTask confirmed() => copyWith(uncertain: false);

  PhaseTask copyWith({PhaseSystem? system, List<PhasePart>? parts, bool? uncertain}) =>
      PhaseTask(system: system ?? this.system, parts: parts ?? this.parts, uncertain: uncertain ?? this.uncertain);

  String describe() => 'Zustandsdiagramm ${system.a}-${system.b}: ${[for (final p in parts) p.kind.label].join(', ')}';

  Map<String, dynamic> toMap() => {
    'kind': 'phase',
    'system': system.toMap(),
    'parts': [for (final p in parts) p.toMap()],
    if (uncertain) 'uncertain': true,
  };

  static PhaseTask? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final system = PhaseSystem.fromMap(raw['system'] ?? raw['diagram'] ?? raw['diagramm'] ?? raw);
    final parts = raw['parts'] ?? raw['teilaufgaben'] ?? raw['questions'];
    if (system == null || parts is! List) return null;
    final u = raw['uncertain'] ?? raw['unsicher'];
    return PhaseTask(
      system: system,
      parts: [for (final p in parts) ?PhasePart.fromMap(p)],
      uncertain: u == true || '$u'.toLowerCase() == 'true',
    );
  }
}
