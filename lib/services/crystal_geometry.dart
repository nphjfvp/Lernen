import '../models/crystal_task.dart';

/// Rückmeldung zu einer Antwort.
class CrystalVerdict {
  const CrystalVerdict(this.ok, this.text);
  final bool ok;
  final String text;
}

/// Ebene n · r = dNum / dDen (r in Würfeleinheiten), n ganzzahlig und
/// gekürzt, dNum ≥ 0 (bei 0: erste Komponente von n positiv).
class CrystalPlane {
  const CrystalPlane(this.n, this.dNum, this.dDen);

  final List<int> n;
  final int dNum;
  final int dDen;

  double get d => dNum / dDen;

  /// Ob ein Punkt in halben Einheiten (0, 1, 2 = 0, ½, 1) in der Ebene liegt.
  bool contains(List<int> half) => CrystalGeometry.dot(n, half) * dDen == 2 * dNum;

  /// Abstand des Ursprungs [origin] (Würfelecke, halbe Einheiten) entlang n,
  /// als Bruch num / den: n · r' = num / den für r' = r − origin.
  (int, int) _shifted(List<int> origin) => (2 * dNum - dDen * CrystalGeometry.dot(n, origin), 2 * dDen);

  /// Miller-Indizes von [origin] aus (Kehrwerte der Achsenabschnitte, Brüche
  /// beseitigt); null, wenn die Ebene durch diesen Ursprung geht.
  List<int>? millerFrom(List<int> origin) {
    final (num, den) = _shifted(origin);
    if (num == 0) return null;
    final a = [for (final k in n) k * den];
    final g = CrystalGeometry.gcd(num, CrystalGeometry.gcd3(a));
    final sign = num < 0 ? -1 : 1;
    return [for (final x in a) x ~/ (sign * g)];
  }

  /// Achsenabschnitte von [origin] aus: "1", "½", "∞", "−1" …
  List<String> interceptsFrom(List<int> origin) {
    final (num, den) = _shifted(origin);
    return [for (final k in n) k == 0 ? '∞' : CrystalGeometry.fracText(num, den * k)];
  }

  /// "x + y + z = 1", "x − y = 0", "2x = 1".
  String get equation {
    final terms = <String>[];
    for (final (i, k) in n.indexed) {
      if (k == 0) continue;
      final name = const ['x', 'y', 'z'][i];
      final mag = k.abs() == 1 ? name : '${k.abs()}$name';
      terms.add(terms.isEmpty ? (k < 0 ? '−$mag' : mag) : (k < 0 ? '− $mag' : '+ $mag'));
    }
    return '${terms.join(' ')} = ${CrystalGeometry.fracText(dNum, dDen)}';
  }
}

/// Ergebnis beim Festlegen einer Ebene durch Punkte.
class PlaneFromPoints {
  const PlaneFromPoints({this.plane, this.collinear = false});
  final CrystalPlane? plane;
  final bool collinear;
}

/// Rechnet Kristallaufgaben aus und prüft Antworten – ohne KI. Punkte im
/// Würfel sind in halben Einheiten angegeben ((0, 1, 2) = (0, ½, 1)).
class CrystalGeometry {
  CrystalGeometry._();

  static int gcd(int a, int b) {
    a = a.abs();
    b = b.abs();
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    return a;
  }

  static int gcd3(List<int> v) => gcd(gcd(v[0], v[1]), v[2]);
  static int dot(List<int> a, List<int> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  static bool same(List<int>? a, List<int>? b) => a != null && b != null && a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
  static List<int> sub(List<int> a, List<int> b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  static List<int> neg(List<int> a) => [-a[0], -a[1], -a[2]];
  static List<int> cross(List<int> a, List<int> b) =>
      [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

  /// Auf kleinste ganze Zahlen gekürzt (Nullvektor bleibt).
  static List<int> reduce(List<int> v) {
    final g = gcd3(v);
    return g == 0 ? [0, 0, 0] : [for (final x in v) x ~/ g];
  }

  /// "1", "½", "−½", "2/3".
  static String fracText(int p, int q) {
    if (q < 0) {
      p = -p;
      q = -q;
    }
    final g = gcd(p, q);
    if (g > 1) {
      p ~/= g;
      q ~/= g;
    }
    final sign = p < 0 ? '−' : '';
    final a = p.abs();
    if (q == 1) return '$sign$a';
    if (a == 1 && q == 2) return '$sign½';
    return '$sign$a/$q';
  }

  /// Koordinate in halben Einheiten als Text: 0, ½, 1.
  static String coord(int half) => half.isEven ? '${half ~/ 2}' : (half == 1 ? '½' : '$half/2');

  static String pointText(List<int> half) => '(${half.map(coord).join(', ')})';

  /// Vektor in halben Einheiten als Text in ganzen Einheiten: (1, −1, ½).
  static String vectorText(List<int> half) => '(${half.map((h) => fracText(h, 2)).join(', ')})';

  static const corners = [
    [0, 0, 0], [0, 0, 2], [0, 2, 0], [0, 2, 2], [2, 0, 0], [2, 0, 2], [2, 2, 0], [2, 2, 2],
  ];

  /// Atomlagen der Zelle (halbe Einheiten).
  static List<List<int>> sites(CrystalLattice lattice) => [
        ...corners,
        if (lattice == CrystalLattice.bcc) [1, 1, 1],
        if (lattice == CrystalLattice.fcc) ...[
          [1, 1, 0], [1, 1, 2], [1, 0, 1], [1, 2, 1], [0, 1, 1], [2, 1, 1],
        ],
      ];

  /// Antippbare Punkte: Atomlagen, mit [half] alle 27 Gitterpunkte.
  static List<List<int>> gridPoints(CrystalLattice lattice, {required bool half}) {
    if (!half) return sites(lattice);
    return [
      for (var x = 0; x <= 2; x++)
        for (var y = 0; y <= 2; y++)
          for (var z = 0; z <= 2; z++) [x, y, z],
    ];
  }

  static bool isCorner(List<int> p) => p.every((k) => k != 1);

  // ---------------------------------------------------------------------------
  // Richtungen
  // ---------------------------------------------------------------------------

  /// Richtung eines Pfeils (halbe Einheiten) als gekürzte Indizes.
  static List<int> directionOf(List<int> start, List<int> end) => reduce(sub(end, start));

  /// Ob sich die Richtung zwischen Gitterpunkten (Raster ½) zeichnen lässt.
  static bool drawableDirection(List<int> uvw) => reduce(uvw).every((k) => k.abs() <= 2);

  /// Wo die App die Richtung zeichnet (Würfeleinheiten): Start in der Ecke,
  /// von der aus der Pfeil in die Zelle passt (negativ = Start auf der 1-Seite).
  static (List<double>, List<double>) segment(List<int> uvw) {
    final m = uvw.map((k) => k.abs()).reduce((a, b) => a > b ? a : b);
    final start = [for (final k in uvw) k < 0 ? 1.0 : 0.0];
    return (start, [for (final (i, k) in uvw.indexed) start[i] + k / (m == 0 ? 1 : m)]);
  }

  /// Dieselbe Lage in halben Einheiten, wenn sie auf Gitterpunkten liegt.
  static (List<int>, List<int>)? gridSegment(List<int> uvw) {
    final (a, b) = segment(uvw);
    final ha = [for (final x in a) (x * 2).round()];
    final hb = [for (final x in b) x * 2];
    if (hb.any((x) => (x - x.round()).abs() > 1e-9)) return null;
    return (ha, [for (final x in hb) x.round()]);
  }

  /// Alle Richtungen der Familie ⟨u v w⟩ (kubisch: Vertauschen und Vorzeichen).
  static List<List<int>> familyMembers(List<int> uvw) {
    final a = [for (final k in reduce(uvw)) k.abs()];
    const perms = [
      [0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0],
    ];
    final seen = <String>{};
    final out = <List<int>>[];
    for (final p in perms) {
      for (var signs = 0; signs < 8; signs++) {
        final v = [for (var i = 0; i < 3; i++) a[p[i]] * ((signs >> i) & 1 == 1 ? -1 : 1)];
        if (seen.add(v.join(','))) out.add(v);
      }
    }
    out.sort((x, y) {
      for (var i = 2; i >= 0; i--) {
        final c = y[i].abs().compareTo(x[i].abs());
        if (c != 0) return c;
      }
      return y.join().compareTo(x.join());
    });
    return out;
  }

  static CrystalVerdict judgeDirection(List<int> target, List<int> start, List<int> end) {
    final t = reduce(target);
    final v = directionOf(start, end);
    final lab = millerText(v);
    if (same(v, t)) {
      final shifted = !same(start, const [0, 0, 0]);
      final note = target.any((k) => k < 0)
          ? ' Für die negativen Indizes hast du den Ursprung nach ${pointText(start)} verschoben.'
          : (shifted ? ' Üblich ist der Start im Ursprung – zählt aber auch so.' : '');
      return CrystalVerdict(true, 'Richtig – $lab.$note');
    }
    if (same(v, neg(t))) {
      return CrystalVerdict(false, 'Fast – dein Pfeil zeigt genau andersherum ($lab). Tausche Start und Ziel.');
    }
    final absSame = [for (var i = 0; i < 3; i++) v[i].abs() == t[i].abs()].every((b) => b);
    if (absSame) {
      final axes = [for (var i = 0; i < 3; i++) if (v[i] != t[i]) const ['x', 'y', 'z'][i]];
      return CrystalVerdict(false, 'Dein Pfeil ist $lab – bei ${axes.join(' und ')} stimmt das Vorzeichen nicht.');
    }
    return CrystalVerdict(false, 'Dein Pfeil ist $lab, gesucht ist ${millerText(t)}. Ziel − Start muss in jeder Achse passen.');
  }

  static CrystalVerdict judgeReadDirection(List<int> target, List<int>? answer) {
    if (answer == null) return const CrystalVerdict(false, 'Gib drei ganze Zahlen ein – negative mit Minus, z. B. −2.');
    final t = target;
    if (same(answer, t)) return CrystalVerdict(true, 'Richtig – ${millerText(t)}.');
    final r = reduce(answer);
    if (same(r, reduce(t)) && !same(answer, t)) {
      return CrystalVerdict(true, 'Richtung stimmt – gekürzt schreibt man ${millerText(reduce(t))}.');
    }
    if (same(r, neg(reduce(t)))) {
      return const CrystalVerdict(false, 'Genau andersherum – du hast Start − Ziel gerechnet. Richtung = Ziel − Start.');
    }
    return CrystalVerdict(false, '${millerText(answer)} stimmt noch nicht. Bilde Ziel − Start und mach die Zahlen ganzzahlig.');
  }

  // ---------------------------------------------------------------------------
  // Ebenen
  // ---------------------------------------------------------------------------

  static CrystalPlane _normalized(List<int> n, int dNum, int dDen) {
    final g = gcd3(n);
    var nn = [for (final k in n) k ~/ g];
    var dn = dNum;
    var dd = dDen * g;
    final first = nn.firstWhere((k) => k != 0);
    if (dn < 0 || (dn == 0 && first < 0)) {
      nn = neg(nn);
      dn = -dn;
    }
    final h = gcd(dn, dd);
    if (h > 1) {
      dn ~/= h;
      dd ~/= h;
    }
    return CrystalPlane(nn, dn, dd);
  }

  /// Ebene durch drei Punkte (halbe Einheiten).
  static PlaneFromPoints planeFromPoints(List<List<int>> pts) {
    final n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]));
    if (n.every((k) => k == 0)) return const PlaneFromPoints(collinear: true);
    // n · q = d' mit q in halben Einheiten  ⇔  n · r = d' / 2.
    return PlaneFromPoints(plane: _normalized(n, dot(n, pts[0]), 2));
  }

  /// Ebene aus Achsenabschnitten vom Ursprung aus ("1", "½", "∞"); null, wenn alle ∞.
  static CrystalPlane? planeFromIntercepts(List<String> intercepts) {
    final n = [for (final a in intercepts) a == '∞' ? 0 : (a == '½' ? 2 : 1)];
    if (n.every((k) => k == 0)) return null;
    return _normalized(n, 1, 1);
  }

  /// Ursprung, von dem aus man die Ebene (h k l) üblicherweise zeichnet:
  /// bei negativen Indizes auf die 1-Seite der Achse verschoben.
  static List<int> standardOrigin(List<int> hkl) => [for (final k in hkl) k < 0 ? 2 : 0];

  /// Die Ebene (h k l) so, wie man sie in die Zelle zeichnet.
  static CrystalPlane standardPlane(List<int> hkl) {
    final o = standardOrigin(hkl);
    // Σ h_i (x_i − o_i) = 1  ⇔  h · r = 1 + h · o (o in Würfeleinheiten).
    return _normalized(hkl, 2 + dot(hkl, o), 2);
  }

  /// Schnitt der Ebene mit dem Würfel (Ecken des Vielecks, Würfeleinheiten,
  /// unsortiert); bei 2 Punkten nur eine Kante, bei weniger nichts.
  static List<List<double>> section(CrystalPlane plane) {
    final pts = <List<double>>[];
    final seen = <String>{};
    void add(List<double> p) {
      if (seen.add(p.map((x) => (x * 1000).round()).join('|'))) pts.add(p);
    }

    double f(List<int> half) => (dot(plane.n, half) / 2) - plane.d;
    for (final a in corners) {
      for (var ax = 0; ax < 3; ax++) {
        if (a[ax] != 0) continue;
        final b = [...a]..[ax] = 2;
        final fa = f(a), fb = f(b);
        if (fa.abs() < 1e-9) add([for (final x in a) x / 2]);
        if (fb.abs() < 1e-9) add([for (final x in b) x / 2]);
        if (fa * fb < -1e-12) {
          final t = fa / (fa - fb);
          add([for (var i = 0; i < 3; i++) (a[i] + (b[i] - a[i]) * t) / 2]);
        }
      }
    }
    return pts;
  }

  /// Gitterpunkte (halbe Einheiten) auf der Ebene.
  static List<List<int>> gridPointsOn(CrystalPlane plane) => [
        for (final p in gridPoints(CrystalLattice.sc, half: true))
          if (plane.contains(p)) p,
      ];

  /// Ob sich die Ebene durch drei Gitterpunkte (Raster ½) festlegen lässt.
  static bool drawablePlane(List<int> hkl) => _threePointsOn(standardPlane(hkl)) != null;

  static List<List<int>>? _threePointsOn(CrystalPlane plane) {
    final pts = gridPointsOn(plane)..sort((a, b) => (isCorner(b) ? 1 : 0) - (isCorner(a) ? 1 : 0));
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        for (var k = j + 1; k < pts.length; k++) {
          if (!cross(sub(pts[j], pts[i]), sub(pts[k], pts[i])).every((c) => c == 0)) return [pts[i], pts[j], pts[k]];
        }
      }
    }
    return null;
  }

  static CrystalVerdict judgePlane(List<int> target, CrystalPlane? plane, {bool collinear = false}) {
    final t = target;
    final tl = millerText(t, open: '(', close: ')');
    if (collinear) {
      return const CrystalVerdict(false, 'Die drei Punkte liegen auf einer Geraden – damit ist keine Ebene festgelegt. Wähle einen anderen dritten Punkt.');
    }
    if (plane == null) return const CrystalVerdict(false, 'Lege zuerst die Ebene fest: drei Punkte antippen oder die Achsenabschnitte wählen.');
    for (final o in corners) {
      final h = plane.millerFrom(o);
      if (h == null) continue;
      if (same(h, t) || same(h, neg(t))) {
        final shifted = !same(o, const [0, 0, 0]);
        return CrystalVerdict(
          true,
          'Richtig – $tl: Achsenabschnitte ${plane.interceptsFrom(o).join(', ')}'
          '${shifted ? ' vom Ursprung ${pointText(o)} aus' : ''}.',
        );
      }
    }
    final from0 = plane.millerFrom(const [0, 0, 0]);
    final parallel = same(reduce(plane.n), reduce(t)) || same(reduce(plane.n), neg(reduce(t)));
    if (parallel) {
      if (from0 == null) {
        return CrystalVerdict(false, 'Richtige Lage, aber die Ebene geht durch den Ursprung – dort lassen sich die Achsenabschnitte nicht ablesen. Nimm die parallele Ebene, die die Achsen schneidet.');
      }
      return CrystalVerdict(
        false,
        'Parallel zu $tl, aber an anderer Stelle: die Achsenabschnitte ${plane.interceptsFrom(const [0, 0, 0]).join(', ')} '
        'ergeben ${millerText(from0, open: '(', close: ')')}.',
      );
    }
    if (from0 == null) {
      return CrystalVerdict(false, 'Deine Ebene (${plane.equation}) geht durch den Ursprung. Gesucht ist $tl.');
    }
    return CrystalVerdict(
      false,
      'Deine Ebene ist ${millerText(from0, open: '(', close: ')')} (Achsenabschnitte '
      '${plane.interceptsFrom(const [0, 0, 0]).join(', ')}), gesucht ist $tl.',
    );
  }

  static CrystalVerdict judgeReadPlane(List<int> target, List<int>? answer) {
    if (answer == null) return const CrystalVerdict(false, 'Gib drei ganze Zahlen ein – negative mit Minus, z. B. −1.');
    final tl = millerText(target, open: '(', close: ')');
    if (same(answer, target) || same(answer, neg(target))) return CrystalVerdict(true, 'Richtig – $tl.');
    final o = standardOrigin(target);
    final icpt = standardPlane(target).interceptsFrom(o);
    if (same(reduce(answer), reduce(target)) || same(reduce(answer), neg(reduce(target)))) {
      return CrystalVerdict(false, 'Die Lage passt, aber die Indizes nicht genau: Achsenabschnitte ${icpt.join(', ')} – davon die Kehrwerte.');
    }
    return CrystalVerdict(false, '${millerText(answer, open: '(', close: ')')} stimmt noch nicht. Lies ab, wo die Ebene die Achsen schneidet, und bilde die Kehrwerte.');
  }

  /// Atome der Zelle in der Ebene (h k l).
  static List<List<int>> atomsIn(List<int> hkl, CrystalLattice lattice) {
    final plane = standardPlane(hkl);
    return [for (final p in sites(lattice)) if (plane.contains(p)) p];
  }

  static String atomsSummary(List<List<int>> atoms) {
    final c = atoms.where(isCorner).length;
    final center = atoms.where((p) => p.every((k) => k == 1)).length;
    final face = atoms.length - c - center;
    return [
      if (c > 0) '$c ${c == 1 ? 'Ecke' : 'Ecken'}',
      if (face > 0) '$face ${face == 1 ? 'Flächenmitte' : 'Flächenmitten'}',
      if (center > 0) 'die Würfelmitte',
    ].join(', ');
  }

  static CrystalVerdict judgeAtoms(List<int> hkl, CrystalLattice lattice, List<List<int>> marked) {
    final want = atomsIn(hkl, lattice);
    final plane = standardPlane(hkl);
    final right = marked.where((m) => want.any((w) => same(w, m))).length;
    final wrong = marked.where((m) => !want.any((w) => same(w, m))).toList();
    if (right == want.length && wrong.isEmpty) {
      return CrystalVerdict(true, 'Richtig – ${want.length} Atome: ${atomsSummary(want)}.');
    }
    if (wrong.isNotEmpty) {
      return CrystalVerdict(
        false,
        '${pointText(wrong.first)} liegt nicht in der Ebene ${plane.equation}. $right von ${want.length} richtig.',
      );
    }
    final missing = want.length - right;
    return CrystalVerdict(false, '$right von ${want.length} richtig – es ${missing == 1 ? 'fehlt' : 'fehlen'} noch $missing.');
  }

  // ---------------------------------------------------------------------------
  // Tipps, Lösungen, Prüfung der Aufgabe
  // ---------------------------------------------------------------------------

  static List<String> hints(CrystalPart part, CrystalLattice lattice) {
    final v = part.indices;
    switch (part.kind) {
      case CrystalPartKind.direction:
        final seg = gridSegment(reduce(v));
        final neg = v.any((k) => k < 0);
        return [
          neg
              ? 'Ein Strich über der Zahl heißt minus. Vom Ursprung aus passt das nicht in die Zelle – verschiebe den Start in eine andere Ecke.'
              : 'Richtung = Ziel − Start. Am einfachsten startest du im Ursprung (0, 0, 0).',
          if (seg != null) 'Starte bei ${pointText(seg.$1)} und gehe nach ${pointText(seg.$2)}.',
        ];
      case CrystalPartKind.readDirection:
        final seg = gridSegment(v);
        return [
          'Lies Start und Ziel des Pfeils ab und bilde Ziel − Start.',
          if (seg != null) 'Ziel − Start = ${vectorText(sub(seg.$2, seg.$1))} – auf ganze Zahlen bringen und kürzen.',
        ];
      case CrystalPartKind.family:
        return [
          'Zur Familie ${part.notation} gehören alle Richtungen, die durch Vertauschen der Zahlen und andere Vorzeichen entstehen.',
          'Insgesamt sind es ${familyMembers(v).length} Richtungen.',
        ];
      case CrystalPartKind.plane:
        final o = standardOrigin(v);
        final pl = standardPlane(v);
        final three = _threePointsOn(pl);
        return [
          'Achsenabschnitte = Kehrwerte der Indizes: ${pl.interceptsFrom(o).join(', ')}'
              '${same(o, const [0, 0, 0]) ? '' : ' – vom Ursprung ${pointText(o)} aus'} (∞ = parallel zur Achse).',
          if (three != null) 'Tippe ${three.map(pointText).join(', ')} an.',
        ];
      case CrystalPartKind.readPlane:
        final o = standardOrigin(v);
        return [
          'Lies ab, wo die Ebene die Achsen schneidet${same(o, const [0, 0, 0]) ? '' : ' (Ursprung in ${pointText(o)})'}, und bilde die Kehrwerte.',
          'Achsenabschnitte: ${standardPlane(v).interceptsFrom(o).join(', ')}.',
        ];
      case CrystalPartKind.planeAtoms:
        final atoms = atomsIn(v, lattice);
        return [
          'Ein Atom liegt in der Ebene, wenn es die Gleichung ${standardPlane(v).equation} erfüllt.',
          'Es sind ${atoms.length} Atome: ${atomsSummary(atoms)}.',
        ];
    }
  }

  /// Was an einer Aufgabe nicht geht (leer = alles in Ordnung).
  static List<String> problems(CrystalTask task) {
    final out = <String>[];
    if (task.parts.isEmpty) out.add('Die Aufgabe hat keine Teilaufgabe.');
    for (final (i, p) in task.parts.indexed) {
      final label = 'Teil ${String.fromCharCode(97 + i)}';
      if (p.indices.length != 3 || p.indices.every((k) => k == 0)) {
        out.add('$label: drei Indizes, nicht alle 0.');
        continue;
      }
      if (p.indices.any((k) => k.abs() > 6)) out.add('$label: Indizes über 6 lassen sich nicht sinnvoll zeichnen.');
      if ((p.kind == CrystalPartKind.direction || p.kind == CrystalPartKind.family) && !drawableDirection(p.indices)) {
        out.add('$label: ${p.notation} liegt nicht auf dem ½-Raster und lässt sich nicht zwischen Gitterpunkten zeichnen.');
      }
      if (p.kind == CrystalPartKind.family && familyMembers(p.indices).length > 12) {
        out.add('$label: die Familie ${p.notation} hat zu viele Richtungen zum Einzeichnen.');
      }
      if (p.kind == CrystalPartKind.plane && !drawablePlane(p.indices)) {
        out.add('$label: ${p.notation} geht nicht durch drei Gitterpunkte (Raster ½) – besser „Ebene ablesen“.');
      }
      if (p.kind == CrystalPartKind.planeAtoms && atomsIn(p.indices, task.latticeOf(p)).isEmpty) {
        out.add('$label: in ${p.notation} liegt kein Atom des ${task.latticeOf(p).short}-Gitters.');
      }
    }
    return out;
  }

  static bool playable(CrystalTask task) => task.isUsable && problems(task).isEmpty;

  /// Lösungsweg als Text (Rückseite, wenn keine eigene Erklärung da ist).
  static String solutionText(CrystalTask task) => [
        for (final (i, p) in task.parts.indexed)
          '${String.fromCharCode(97 + i)}) ${p.kind.label} ${p.notation}: ${switch (p.kind) {
            CrystalPartKind.plane => hints(p, task.latticeOf(p)).first,
            CrystalPartKind.family =>
              '${familyMembers(p.indices).length} Richtungen: ${familyMembers(p.indices).map(millerText).join(', ')}.',
            _ => hints(p, task.latticeOf(p)).last,
          }}',
      ].join('\n');
}
