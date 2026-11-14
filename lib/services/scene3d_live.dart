import 'dart:math' as math;

import '../models/visual_scene3d.dart';
import '../models/visual_scene3d_blocks.dart';

/// Was der Nutzer beim „Ausprobieren“ an einem Körper-Baustein verstellt hat.
class Scene3DLiveState {
  const Scene3DLiveState({this.lifted = const {}, this.cg = 0.5, this.slope = 0, this.mu = 0.5, this.forceAt = 0});

  /// Auto: angehobene Räder ('fl', 'fr', 'rl', 'rr').
  final Set<String> lifted;

  /// Auto: Lage des Schwerpunkts zwischen Hinterachse (0) und Vorderachse (1).
  final double cg;

  /// Neigung der Unterlage in Grad.
  final double slope;

  /// Klotz: Haftreibungszahl.
  final double mu;

  /// Balken: Lage der (ersten) Kraft, Abstand vom linken Ende.
  final double forceAt;

  Scene3DLiveState copyWith({Set<String>? lifted, double? cg, double? slope, double? mu, double? forceAt}) =>
      Scene3DLiveState(
        lifted: lifted ?? this.lifted,
        cg: cg ?? this.cg,
        slope: slope ?? this.slope,
        mu: mu ?? this.mu,
        forceAt: forceAt ?? this.forceAt,
      );
}

/// Ergebnis von [Scene3DLive.apply]: die Szene mit neu gerechneten Kräften
/// und ein Satz dazu, was gerade passiert.
class Scene3DLiveResult {
  const Scene3DLiveResult({required this.scene, required this.status, this.warn = false});

  final VisualScene3D scene;
  final String status;

  /// Der Körper kippt, rutscht oder hebt ab.
  final bool warn;
}

/// „Ausprobieren“: Aus einem Körper-Baustein (siehe [Scene3DBlocks]) wird ein
/// Modell, an dem man etwas verstellen kann – ein Rad anheben, den
/// Schwerpunkt oder eine Kraft verschieben, die Unterlage neigen. Die App
/// rechnet die Kräfte dann selbst neu (Statik), ohne KI:
///
/// - Auto: Radlasten aus Schwerpunkt, Neigung und den Rädern, die aufliegen.
/// - Klotz auf schiefer Ebene: Normalkraft, nötige Reibung, haftet oder rutscht.
/// - Balken auf zwei Lagern: Lagerkräfte, wenn die Kraft wandert.
class Scene3DLive {
  const Scene3DLive._();

  static const wheelNames = {'fl': 'vorn links', 'fr': 'vorn rechts', 'rl': 'hinten links', 'rr': 'hinten rechts'};
  static const _wheelShort = {'fl': 'VL', 'fr': 'VR', 'rl': 'HL', 'rr': 'HR'};

  /// Der Baustein der Szene, mit dem sich etwas ausprobieren lässt (der erste).
  static Map<String, dynamic>? blockOf(VisualScene3D scene) {
    for (final b in scene.blocks) {
      if (kindOf(b) != null) return b;
    }
    return null;
  }

  /// 'car', 'block' oder 'beam' – null, wenn die App für diesen Baustein
  /// nichts rechnen kann.
  static String? kindOf(Map<String, dynamic> block) {
    switch (Scene3DBlocks.bodyKindOf(block)) {
      case 'car':
        return 'car';
      case 'block':
        return 'block';
      case 'beam':
        final beam = Scene3DBlocks.beamGeometry(block);
        // Statisch bestimmt und ohne Größen, die die App nicht kennt.
        final simple = block['loads'] == null && block['moments'] == null && block['streckenlast'] == null;
        return beam != null && beam.supports.length == 2 && beam.forces.isNotEmpty && simple ? 'beam' : null;
      default:
        return null;
    }
  }

  /// Ausgangslage: so, wie der Baustein gezeichnet ist.
  static Scene3DLiveState initial(Map<String, dynamic> block) {
    final slope = (_num(block['slope'] ?? block['incline'] ?? block['neigung'] ?? block['alpha']) ?? 0).clamp(
      -60.0,
      60.0,
    );
    switch (kindOf(block)) {
      case 'car':
        final car = Scene3DBlocks.carGeometry(block)!;
        return Scene3DLiveState(cg: ((car.cgx - car.xr) / car.wheelbase).clamp(0.0, 1.0), slope: slope);
      case 'block':
        return Scene3DLiveState(
          slope: slope,
          mu: (_num(block['mu'] ?? block['µ'] ?? block['reibung']) ?? 0.5).clamp(0.0, 1.5),
        );
      case 'beam':
        return Scene3DLiveState(forceAt: Scene3DBlocks.beamGeometry(block)!.forces.first.at);
      default:
        return const Scene3DLiveState();
    }
  }

  static double? _num(Object? raw) {
    final v = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}'.trim().replaceAll(',', '.'));
    return v != null && v.isFinite ? v : null;
  }

  /// Zahl mit Einheit aus einer Beschriftung wie „F_G = 12 kN“.
  static ({double value, String unit, String symbol})? quantityIn(String text) {
    final m = RegExp(r'^(.*?)=\s*(-?\d+(?:[.,]\d+)?)\s*([a-zA-Zµ/²·]*)').firstMatch(text.trim());
    if (m == null) return null;
    final value = double.tryParse(m.group(2)!.replaceAll(',', '.'));
    if (value == null) return null;
    return (value: value, unit: m.group(3)!.trim(), symbol: m.group(1)!.trim());
  }

  static String _pct(double share) => '${(share * 100).round()} %';

  static String _amount(double share, ({double value, String unit, String symbol})? total, String symbol) =>
      total == null
      ? '${Scene3DBlocks.fmt(share)} · $symbol'
      : '${Scene3DBlocks.fmt(share * total.value)}${total.unit.isEmpty ? '' : ' ${total.unit}'}';

  /// Radlasten als Anteile der Last, die senkrecht auf der Fahrbahn steht.
  /// [wheels]: Aufstandspunkte (x, y) der Räder, die aufliegen; [at]: Punkt,
  /// in dem die Last die Fahrbahn trifft. Vier Räder teilen sich die Last wie
  /// auf gleichen Federn (ebene Verteilung); würde ein Rad dabei ziehen statt
  /// drücken, hebt es ab und die übrigen tragen. null = der Körper kippt.
  static Map<String, double>? wheelLoads(Map<String, (double, double)> wheels, (double, double) at) {
    final active = {...wheels};
    while (true) {
      if (active.length < 2) return null;
      if (active.length == 2) {
        // Zwei Räder tragen nur, wenn die Last genau auf ihrer Verbindungslinie liegt.
        final (a, b) = (active.values.first, active.values.last);
        final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
        final len2 = dx * dx + dy * dy;
        if (len2 < 1e-18) return null;
        final t = ((at.$1 - a.$1) * dx + (at.$2 - a.$2) * dy) / len2;
        final off = ((at.$1 - a.$1) * dy - (at.$2 - a.$2) * dx).abs() / math.sqrt(len2);
        if (off > 1e-6 * math.sqrt(len2) || t < -1e-9 || t > 1 + 1e-9) return null;
        return {for (final k in wheels.keys) k: 0.0, active.keys.first: 1 - t, active.keys.last: t};
      }
      // N_i = a + b·x_i + c·y_i mit ΣN = 1, ΣN·x = X, ΣN·y = Y.
      var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0;
      for (final (x, y) in active.values) {
        sx += x;
        sy += y;
        sxx += x * x;
        sxy += x * y;
        syy += y * y;
      }
      final n = active.length.toDouble();
      final solution = _solve3(
        [
          [n, sx, sy],
          [sx, sxx, sxy],
          [sy, sxy, syy],
        ],
        [1, at.$1, at.$2],
      );
      if (solution == null) return null;
      final loads = {
        for (final e in active.entries) e.key: solution[0] + solution[1] * e.value.$1 + solution[2] * e.value.$2,
      };
      final worst = loads.entries.reduce((a, b) => a.value < b.value ? a : b);
      if (worst.value >= -1e-9) {
        return {for (final k in wheels.keys) k: math.max(0.0, loads[k] ?? 0.0)};
      }
      // Drei Räder sind eindeutig – zieht eines, kippt der Körper.
      if (active.length == 3) return null;
      active.remove(worst.key);
    }
  }

  /// Löst ein 3×3-Gleichungssystem (Cramer); null, wenn es nicht eindeutig ist.
  static List<double>? _solve3(List<List<double>> m, List<double> r) {
    double det(List<List<double>> a) =>
        a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
        a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
        a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]);
    final d = det(m);
    final scale = m.expand((row) => row).fold<double>(0, (s, v) => math.max(s, v.abs()));
    if (d.abs() < 1e-12 * math.max(1.0, scale * scale * scale)) return null;
    List<List<double>> swap(int col) => [
      for (var i = 0; i < 3; i++) [for (var j = 0; j < 3; j++) j == col ? r[i] : m[i][j]],
    ];
    return [for (var c = 0; c < 3; c++) det(swap(c)) / d];
  }

  /// Die Szene mit dem Baustein im Zustand [state] – Kräfte neu gerechnet.
  static Scene3DLiveResult? apply(VisualScene3D scene, Scene3DLiveState state) {
    final block = blockOf(scene);
    if (block == null) return null;
    final (changed, status, warn) = switch (kindOf(block)) {
      'car' => _car(block, state),
      'block' => _block(block, state),
      _ => _beam(block, state),
    };
    final map = scene.toMap();
    map['objects'] = [for (final o in map['objects'] as List) identical(o, block) ? changed : o];
    // Der Raum richtet sich neu nach dem Körper.
    map.remove('box');
    final rebuilt = VisualScene3D.fromMap(map);
    return rebuilt == null ? null : Scene3DLiveResult(scene: rebuilt, status: status, warn: warn);
  }

  static List<Map<String, dynamic>> _forcesOf(Map<String, dynamic> block) => [
    if ((block['forces'] ?? block['kraefte'] ?? block['kräfte']) case final List list)
      for (final f in list)
        if (f is Map) Map<String, dynamic>.from(f),
  ];

  /// Beschriftung des Gewichts (die Kraft im Schwerpunkt nach unten), sonst „F_G“.
  static String _weightText(Map<String, dynamic> block) {
    for (final f in _forcesOf(block)) {
      final at = '${f['at'] ?? ''}'.toLowerCase();
      final dir = '${f['dir'] ?? 'down'}'.toLowerCase();
      if ((at.isEmpty || at == 'cg' || at == 's' || at == 'schwerpunkt') && (dir == 'down' || dir == 'unten')) {
        final text = '${f['text'] ?? f['label'] ?? ''}'.trim();
        if (text.isNotEmpty) return text;
      }
    }
    return 'F_G';
  }

  static (Map<String, dynamic>, String, bool) _car(Map<String, dynamic> block, Scene3DLiveState state) {
    final car = Scene3DBlocks.carGeometry(block)!;
    final slope = state.slope * math.pi / 180;
    final cgx = car.xr + state.cg.clamp(0.0, 1.0) * car.wheelbase;
    // Die Wirkungslinie des Gewichts trifft die Fahrbahn hangabwärts versetzt.
    final at = (cgx - car.cgz * math.tan(slope), car.w / 2);
    final contacts = {'fl': (car.xf, car.yl), 'fr': (car.xf, car.yr), 'rl': (car.xr, car.yl), 'rr': (car.xr, car.yr)};
    final resting = {
      for (final e in contacts.entries)
        if (!state.lifted.contains(e.key)) e.key: e.value,
    };
    final loads = wheelLoads(resting, at);
    final weight = _weightText(block);
    final total = quantityIn(weight);
    final symbol = total?.symbol.isNotEmpty == true ? total!.symbol : weight;
    final normal = math.cos(slope);

    final forces = <Map<String, dynamic>>[
      {'at': 'cg', 'dir': 'down', 'text': weight},
      if (loads != null)
        for (final e in loads.entries)
          if (e.value > 1e-6)
            {
              'at': [contacts[e.key]!.$1 / car.l, contacts[e.key]!.$2 / car.w, 0],
              'dir': 'normal',
              'len': 0.25 + 1.6 * e.value * normal,
              'text':
                  '${_wheelShort[e.key]} ${total == null ? _pct(e.value * normal) : _amount(e.value * normal, total, symbol)}',
            },
    ];
    final String status;
    var warn = false;
    if (loads == null) {
      warn = true;
      status = state.lifted.length >= 3
          ? 'Auf einem Rad allein steht das Auto nicht – es kippt.'
          : 'Das Auto kippt: Der Schwerpunkt liegt nicht mehr über der Fläche zwischen den Rädern, die aufliegen.';
    } else {
      final own = [
        for (final e in loads.entries)
          if (e.value <= 1e-6 && !state.lifted.contains(e.key)) wheelNames[e.key]!,
      ];
      double at(String k) => loads[k] ?? 0;
      final front = (at('fl') + at('fr')) * normal, rear = (at('rl') + at('rr')) * normal;
      final top = loads.values.reduce(math.max);
      final most = [
        for (final e in loads.entries)
          if (e.value >= top - 1e-6) wheelNames[e.key]!,
      ];
      status = [
        'Vorderachse ${_pct(front)}, Hinterachse ${_pct(rear)} von $symbol.',
        if (state.lifted.isNotEmpty)
          most.length == 1
              ? 'Am meisten trägt jetzt das Rad ${most.single} (${_pct(top * normal)}).'
              : 'Am meisten tragen jetzt die Räder ${most.join(' und ')} (je ${_pct(top * normal)}).',
        if (own.isNotEmpty)
          own.length == 1
              ? 'Das Rad ${own.single} trägt nichts mehr – das Auto liegt nur noch auf den anderen.'
              : 'Die Räder ${own.join(' und ')} tragen nichts mehr.',
        if (slope.abs() > 0.01) 'Die Reibung der Räder hält ${_pct(math.sin(slope).abs())} von $symbol hangabwärts.',
      ].join(' ');
      // Ein entlastetes Rad ist noch kein Kippen – nur ein Hinweis im Text.
      warn = false;
    }
    return (
      {
        ...block,
        'slope': state.slope,
        'cg': [cgx, car.cgz],
        'lifted': state.lifted.toList(),
        'forces': forces,
      },
      status,
      warn,
    );
  }

  static (Map<String, dynamic>, String, bool) _block(Map<String, dynamic> block, Scene3DLiveState state) {
    final slope = state.slope.abs() * math.pi / 180;
    final weight = _weightText(block);
    final total = quantityIn(weight);
    final symbol = total?.symbol.isNotEmpty == true ? total!.symbol : weight;
    final normal = math.cos(slope), pull = math.sin(slope);
    final grip = state.mu * normal;
    final holds = pull <= grip + 1e-12;
    final friction = holds ? pull : grip;
    final uphill = state.slope >= 0 ? 'uphill' : 'downhill';
    final forces = <Map<String, dynamic>>[
      {'at': 'cg', 'dir': 'down', 'text': weight},
      {'at': 'bottom', 'dir': 'normal', 'len': 0.25 + normal, 'text': 'F_N = ${_amount(normal, total, symbol)}'},
      if (friction > 0.005)
        {'at': 'bottom', 'dir': uphill, 'len': 0.25 + friction, 'text': 'F_R = ${_amount(friction, total, symbol)}'},
    ];
    final String status;
    if (pull < 0.005) {
      status = 'Eben: Die Unterlage trägt das ganze Gewicht, Reibung wird nicht gebraucht.';
    } else if (holds) {
      status =
          'Haftet: Der Hangabtrieb ${_amount(pull, total, symbol)} wird von der Reibung gehalten – möglich wären bis '
          '${_amount(grip, total, symbol)} (μ = ${Scene3DBlocks.fmt(state.mu)}).';
    } else {
      status =
          'Rutscht: Der Hangabtrieb ${_amount(pull, total, symbol)} ist größer als die größte Haftreibung '
          '${_amount(grip, total, symbol)} (μ = ${Scene3DBlocks.fmt(state.mu)}). Beschleunigung etwa '
          '${Scene3DBlocks.fmt(9.81 * (pull - grip))} m/s².';
    }
    return ({...block, 'slope': state.slope, 'forces': forces}, status, !holds);
  }

  static (Map<String, dynamic>, String, bool) _beam(Map<String, dynamic> block, Scene3DLiveState state) {
    final beam = Scene3DBlocks.beamGeometry(block)!;
    final a = beam.supports[0], b = beam.supports[1];
    final span = b.at - a.at;
    final given = _forcesOf(block);
    // Die erste Kraft wandert; alle zählen mit ihrem senkrechten Anteil.
    final first = quantityIn('${given.first['text'] ?? given.first['label'] ?? ''}');
    final unit = first == null ? null : (value: 1.0, unit: first.unit, symbol: first.symbol);
    final symbol = first?.symbol.isNotEmpty == true
        ? first!.symbol
        : ('${given.first['text'] ?? given.first['label'] ?? ''}'.trim().isEmpty
              ? 'F'
              : '${given.first['text'] ?? given.first['label']}'.trim());
    var sum = 0.0, moment = 0.0;
    final moved = <Map<String, dynamic>>[];
    for (final (i, f) in beam.forces.indexed) {
      final at = i == 0 ? state.forceAt.clamp(0.0, beam.l) : f.at;
      final size = first == null
          ? f.size
          : (quantityIn('${given[i]['text'] ?? given[i]['label'] ?? ''}')?.value ?? f.size);
      sum += size * f.down;
      moment += size * f.down * (at - a.at);
      moved.add({...given[i], 'at': at});
    }
    final rb = span.abs() < 1e-12 ? 0.0 : moment / span, ra = sum - rb;
    final biggest = math.max(1e-12, [ra.abs(), rb.abs(), sum.abs()].reduce(math.max));
    String label(String name, double r) =>
        '$name = ${first == null ? '${Scene3DBlocks.fmt(r)} · $symbol' : _amount(r, unit, symbol)}';
    Map<String, dynamic> reaction(({double at, String text}) s, String fallback, double r) => {
      'at': s.at,
      'side': 'bottom',
      'dir': r >= 0 ? 'up' : 'down',
      'len': 0.25 + 1.1 * r.abs() / biggest,
      'stroke': 'green',
      'text': label(s.text.isEmpty ? fallback : s.text, r),
    };

    final lifts = ra < -1e-9 || rb < -1e-9;
    final share = sum.abs() < 1e-12 ? 0.5 : ra / sum;
    final status = lifts
        ? 'Die Kraft steht außerhalb der Lager: Lager ${(ra < 0 ? a.text : b.text).isEmpty ? (ra < 0 ? 'A' : 'B') : (ra < 0 ? a.text : b.text)} '
              'müsste den Balken nach unten halten – ein einfaches Auflager hebt hier ab.'
        : 'Lager ${a.text.isEmpty ? 'A' : a.text} trägt ${_pct(share)}, Lager ${b.text.isEmpty ? 'B' : b.text} '
              '${_pct(1 - share)} der Last. Je näher die Kraft an einem Lager, desto mehr trägt es.';
    return (
      {
        ...block,
        'forces': [...moved, reaction(a, 'A', ra), reaction(b, 'B', rb)],
      },
      status,
      lifts,
    );
  }

  // ---------------------------------------------------------------------------
  // Ablauf („Simulation erweitern“): Zustände über die Zeit, die App rechnet
  // für jeden Moment die Kräfte neu.
  // ---------------------------------------------------------------------------

  /// Der Ablauf eines Bausteins (`timeline`), fehlende Werte vom Schritt davor
  /// bzw. aus [base]. Sortiert nach `at` (0…1).
  static List<({double at, Scene3DLiveState state, String caption})> timelineOf(
    Map<String, dynamic> block,
    Scene3DLiveState base,
  ) {
    final raw = block['timeline'] ?? block['ablauf'];
    if (raw is! List) return const [];
    final entries = [
      for (final e in raw)
        if (e is Map && _num(e['at'] ?? e['t']) != null) e,
    ]..sort((a, b) => _num(a['at'] ?? a['t'])!.compareTo(_num(b['at'] ?? b['t'])!));
    final out = <({double at, Scene3DLiveState state, String caption})>[];
    var state = base;
    for (final e in entries) {
      final lifted = e['lifted'] ?? e['angehoben'] ?? e['offGround'];
      state = Scene3DLiveState(
        lifted: lifted is List
            ? {
                for (final w in lifted)
                  if (wheelNames.containsKey('$w'.toLowerCase())) '$w'.toLowerCase(),
              }
            : state.lifted,
        cg: (_num(e['cg']) ?? state.cg).clamp(0.0, 1.0),
        slope: (_num(e['slope'] ?? e['neigung']) ?? state.slope).clamp(-60.0, 60.0),
        mu: (_num(e['mu']) ?? state.mu).clamp(0.0, 1.5),
        forceAt: _num(e['forceAt'] ?? e['force_at']) ?? state.forceAt,
      );
      out.add((
        at: _num(e['at'] ?? e['t'])!.clamp(0.0, 1.0),
        state: state,
        caption: '${e['caption'] ?? e['text'] ?? ''}'.trim(),
      ));
    }
    return out;
  }

  /// Zustand zur Zeit [p] (0…1): Zahlen gleiten zwischen den Schritten,
  /// angehobene Räder und Text wechseln am Schritt.
  static ({Scene3DLiveState state, String caption}) stateAt(
    List<({double at, Scene3DLiveState state, String caption})> timeline,
    double p,
  ) {
    if (timeline.isEmpty) return (state: const Scene3DLiveState(), caption: '');
    if (p <= timeline.first.at) return (state: timeline.first.state, caption: timeline.first.caption);
    for (var i = 0; i + 1 < timeline.length; i++) {
      final a = timeline[i], b = timeline[i + 1];
      if (p >= a.at && p < b.at) {
        final f = b.at == a.at ? 0.0 : (p - a.at) / (b.at - a.at);
        double lerp(double x, double y) => x + (y - x) * f;
        return (
          state: Scene3DLiveState(
            lifted: a.state.lifted,
            cg: lerp(a.state.cg, b.state.cg),
            slope: lerp(a.state.slope, b.state.slope),
            mu: lerp(a.state.mu, b.state.mu),
            forceAt: lerp(a.state.forceAt, b.state.forceAt),
          ),
          caption: a.caption,
        );
      }
    }
    return (state: timeline.last.state, caption: timeline.last.caption);
  }
}
