import 'dart:math' as math;

import '../services/math_input.dart';

/// Bausteine für räumliche Szenen: Die KI liefert nur Parameter (einen
/// Funktionsterm, Durchmesser und Längen), die App rechnet und baut daraus
/// die Formen – maßstäblich und ohne Rechenfehler. Ergänzt die freie Szene
/// (Kugel, Quader, Zylinder, Pfeil …), ersetzt sie nicht.
///
/// - `surface`: Fläche z = f(x, y) mit Punkten, Tangentialebene, Gradient und
///   einer Kurve auf der Fläche (Nebenbedingung).
/// - `shaft`: Welle/Achse aus Abschnitten (Durchmesser, Länge) mit Lagern,
///   Kräften und markierten Querschnitten.
/// - `body`: Körper für die Mechanik – Auto, Klotz, Kugel/Walze (auch auf
///   schiefer Ebene) oder Balken auf Lagern – mit Kräften an benannten
///   Angriffspunkten, Streckenlasten, Momenten und Maßlinien (Freischnitt).
///
/// [expand] macht aus einem Baustein die einfachen Formen des Szenen-Formats.
class Scene3DBlocks {
  const Scene3DBlocks._();

  /// So fein wird eine Fläche höchstens gerastert (je Richtung).
  static const maxGrid = 24;

  static double? _num(Object? raw) {
    final v = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}'.trim().replaceAll(',', '.'));
    return v != null && v.isFinite ? v : null;
  }

  static String _str(Object? raw) => raw == null ? '' : '$raw'.trim();

  static (double, double)? _range(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    final lo = _num(raw[0]), hi = _num(raw[1]);
    return lo == null || hi == null || hi <= lo ? null : (lo, hi);
  }

  static String _type(Map raw) => _str(raw['type'] ?? raw['shape']).toLowerCase();

  static bool _isSurface(Map raw) =>
      const {'surface', 'function', 'funktion', 'graph', 'flaeche3d', 'funktionsfläche'}.contains(_type(raw)) &&
      _str(raw['expr'] ?? raw['f'] ?? raw['z']).isNotEmpty;

  static bool _isShaft(Map raw) =>
      const {'shaft', 'welle', 'achse', 'stufenwelle'}.contains(_type(raw)) && raw['segments'] is List;

  static const _bodyTypes = {'body', 'freebody', 'freikörper', 'freikoerper', 'freischnitt', 'körper', 'koerper'};
  static const _bodyKinds = {
    'car': 'car',
    'auto': 'car',
    'fahrzeug': 'car',
    'vehicle': 'car',
    'wagen': 'car',
    'pkw': 'car',
    'block': 'block',
    'klotz': 'block',
    'box': 'block',
    'quader': 'block',
    'kiste': 'block',
    'ball': 'ball',
    'kugel': 'ball',
    'sphere': 'ball',
    'roller': 'roller',
    'walze': 'roller',
    'rad': 'roller',
    'wheel': 'roller',
    'zylinder': 'roller',
    'cylinder': 'roller',
    'beam': 'beam',
    'balken': 'beam',
    'träger': 'beam',
    'traeger': 'beam',
  };

  static String? _bodyKind(Map raw) {
    if (!_bodyTypes.contains(_type(raw))) return null;
    return _bodyKinds[_str(raw['body'] ?? raw['kind'] ?? raw['shape'] ?? raw['form']).toLowerCase()];
  }

  static bool _isBody(Map raw) => _bodyKind(raw) != null;

  /// Ist [raw] ein Körper-Baustein (Auto, Klotz, Balken …)?
  static bool isBody(Object? raw) => raw is Map && _isBody(raw);

  /// Ist [raw] ein Baustein (und keine einfache Form)?
  static bool isBlock(Object? raw) => raw is Map && (_isSurface(raw) || _isShaft(raw) || _isBody(raw));

  /// Bringt der Baustein seine eigenen Maße mit (Welle, Körper)? Dann richtet
  /// sich der Raum der Szene nach ihm.
  static bool sizesItself(Object? raw) => raw is Map && (_isShaft(raw) || _isBody(raw));

  /// Die einfachen Formen, aus denen der Baustein [raw] besteht – im
  /// Koordinatensystem der Szene mit dem Raum [box]. Leer, wenn sich der
  /// Baustein nicht lesen lässt.
  static List<Map<String, dynamic>> expand(Map raw, List<double> box) {
    try {
      if (_isSurface(raw)) return _surface(raw, box);
      if (_isShaft(raw)) return _shaft(raw);
      if (_isBody(raw)) return _body(raw);
    } catch (_) {
      // Unlesbarer Baustein: weglassen statt die ganze Szene zu verlieren.
    }
    return const [];
  }

  /// Zahl kurz und deutsch für Beschriftungen.
  static String fmt(double v) {
    if (v == 0) return '0';
    final a = v.abs();
    final digits = a >= 100
        ? 0
        : a >= 10
        ? 1
        : a >= 1
        ? 2
        : 3;
    var s = v.toStringAsFixed(digits);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return (s == '-0' ? '0' : s).replaceAll('.', ',').replaceAll('-', '−');
  }

  static String _hex(List<int> rgb) =>
      '#${[for (final c in rgb) c.clamp(0, 255).toRadixString(16).padLeft(2, '0')].join()}';

  /// Farbe nach Höhe: unten blau, oben orange.
  static String heightColor(double t) {
    const lo = [59, 111, 216], mid = [120, 196, 170], hi = [242, 163, 58];
    final u = t.isFinite ? t.clamp(0.0, 1.0) : 0.5;
    final (a, b, w) = u < 0.5 ? (lo, mid, u * 2) : (mid, hi, (u - 0.5) * 2);
    return _hex([for (var i = 0; i < 3; i++) (a[i] + (b[i] - a[i]) * w).round()]);
  }

  // -------------------------------------------------------------------------
  // Fläche z = f(x, y)
  // -------------------------------------------------------------------------

  static List<Map<String, dynamic>> _surface(Map raw, List<double> box) {
    final f = MathExpression.tryParse(_str(raw['expr'] ?? raw['f'] ?? raw['z']), names: const {'x', 'y'});
    if (f == null || !f.freeSymbols.every(const {'x', 'y'}.contains)) return const [];
    final (x0, x1) = _range(raw['x'] ?? raw['xRange']) ?? (-2.0, 2.0);
    final (y0, y1) = _range(raw['y'] ?? raw['yRange']) ?? (-2.0, 2.0);
    final n = (_num(raw['n'] ?? raw['grid']) ?? 16).round().clamp(4, maxGrid);
    double at(double x, double y) {
      final v = f.evaluate({'x': x, 'y': y});
      return v.isFinite ? v : double.nan;
    }

    final grid = [
      for (var i = 0; i <= n; i++) [for (var j = 0; j <= n; j++) at(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * j / n)],
    ];
    final finite = [
      for (final row in grid)
        for (final v in row)
          if (!v.isNaN) v,
    ]..sort();
    if (finite.isEmpty) return const [];
    // Höhenbereich: angegeben, sonst aus den Werten. Nur echte Ausreißer
    // (Pole wie bei 1/y) kappen – sonst bestimmten sie den Maßstab allein.
    var (z0, z1) = _range(raw['zRange'] ?? (raw['z'] is List ? raw['z'] : null)) ?? (finite.first, finite.last);
    if (raw['zRange'] == null && raw['z'] is! List && finite.length >= 20) {
      final p10 = finite[(finite.length * 0.10).floor()], p90 = finite[(finite.length * 0.90).ceil() - 1];
      if (p90 > p10 && (finite.last - finite.first) > 8 * (p90 - p10)) {
        final pad = (p90 - p10) * 0.75;
        (z0, z1) = (math.max(finite.first, p10 - pad), math.min(finite.last, p90 + pad));
      }
    }
    if (z1 - z0 < 1e-9) (z0, z1) = (z0 - 0.5, z0 + 0.5);

    final bx = box[0], by = box[1], bz = box[2];
    double px(double x) => (x - x0) / (x1 - x0) * bx;
    double py(double y) => (y - y0) / (y1 - y0) * by;
    double pz(double z) => (z.clamp(z0, z1) - z0) / (z1 - z0) * bz;
    List<double> p(double x, double y, double z) => [px(x), py(y), pz(z)];
    final opacity = _num(raw['opacity']) ?? 1.0;
    final fill = _str(raw['fill']);

    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final corners = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)];
        final values = [for (final (a, b) in corners) grid[a][b]];
        if (values.any((v) => v.isNaN)) continue;
        // Ganz außerhalb des Höhenbereichs (Pol): weglassen.
        if (values.every((v) => v > z1) || values.every((v) => v < z0)) continue;
        final mean = values.reduce((a, b) => a + b) / 4;
        out.add({
          'type': 'polygon',
          'points': [
            for (final (k, (a, b)) in corners.indexed) p(x0 + (x1 - x0) * a / n, y0 + (y1 - y0) * b / n, values[k]),
          ],
          'fill': fill.isNotEmpty ? fill : heightColor((mean - z0) / (z1 - z0)),
          'opacity': opacity,
          'solid': true,
        });
      }
    }
    if (out.isEmpty) return const [];

    // Achsen mit den echten Werten beschriften.
    final vx = _str(raw['xLabel']).isEmpty ? 'x' : _str(raw['xLabel']);
    final vy = _str(raw['yLabel']).isEmpty ? 'y' : _str(raw['yLabel']);
    final vz = _str(raw['zLabel']).isEmpty ? 'z' : _str(raw['zLabel']);
    // Schriftgröße in Bildschirm-Pixeln (wie bei "text" im Szenen-Format).
    Map<String, dynamic> label(List<double> at, String text) => {'type': 'text', 'at': at, 'text': text, 'size': 12};
    out
      ..add(label([bx / 2, -by * 0.14, 0], '$vx: ${fmt(x0)} … ${fmt(x1)}'))
      ..add(label([bx * 1.16, by / 2, 0], '$vy: ${fmt(y0)} … ${fmt(y1)}'))
      ..add(label([0, by, bz * 1.1], '$vz: ${fmt(z0)} … ${fmt(z1)}'));
    final title = _str(raw['text'] ?? raw['label']);
    if (title.isNotEmpty) out.add(label([bx / 2, by / 2, bz * 1.22], title));

    final hx = (x1 - x0) * 1e-4, hy = (y1 - y0) * 1e-4;
    double fx(double x, double y) => (at(x + hx, y) - at(x - hx, y)) / (2 * hx);
    double fy(double x, double y) => (at(x, y + hy) - at(x, y - hy)) / (2 * hy);
    final r = math.max(bx, by) * 0.028;
    (double, double)? xy(Object? v) {
      final list = v is Map ? (v['at'] ?? v['point'] ?? v['p']) : v;
      if (list is! List || list.length < 2) return null;
      final a = _num(list[0]), b = _num(list[1]);
      return a == null || b == null ? null : (a, b);
    }

    // Punkt auf der Fläche; seine Beschriftung steht darüber (im Punkt selbst
    // wäre sie nicht lesbar).
    List<Map<String, dynamic>> dot(double x, double y, String fill, String text) {
      final at3 = p(x, y, at(x, y));
      return [
        {'type': 'sphere', 'at': at3, 'r': r, 'fill': fill},
        if (text.isNotEmpty)
          {
            'type': 'text',
            'at': [at3[0], at3[1], at3[2] + bz * 0.09],
            'text': text,
            'size': 12,
          },
      ];
    }

    // Punkte auf der Fläche (die Höhe rechnet die App).
    final points = raw['points'] ?? raw['punkte'];
    if (points is List) {
      for (final q in points.take(12)) {
        final at2 = xy(q);
        if (at2 == null || at(at2.$1, at2.$2).isNaN) continue;
        out.addAll(
          dot(
            at2.$1,
            at2.$2,
            q is Map && _str(q['fill']).isNotEmpty ? _str(q['fill']) : 'red',
            q is Map ? _str(q['text'] ?? q['label']) : '',
          ),
        );
      }
    }

    // Tangentialebene in (x0, y0): z = f + f_x·(x − x0) + f_y·(y − y0).
    final tangent = xy(raw['tangent'] ?? raw['tangentialebene']);
    if (tangent != null) {
      final (tx, ty) = tangent;
      final f0 = at(tx, ty), gx = fx(tx, ty), gy = fy(tx, ty);
      if (!f0.isNaN && gx.isFinite && gy.isFinite) {
        // So groß, wie sie ohne weit aus dem Raum zu ragen sein kann.
        var half = 0.32;
        final span = z1 - z0;
        while (half > 0.08 && (gx.abs() * (x1 - x0) + gy.abs() * (y1 - y0)) * half > span * 0.75) {
          half *= 0.8;
        }
        final ax = (x1 - x0) * half, ay = (y1 - y0) * half;
        out
          ..add({
            'type': 'polygon',
            'points': [
              for (final (sx, sy) in const [(-1, -1), (1, -1), (1, 1), (-1, 1)])
                [px(tx + sx * ax), py(ty + sy * ay), (f0 + gx * sx * ax + gy * sy * ay - z0) / (z1 - z0) * bz],
            ],
            'fill': 'orange',
            'opacity': 0.5,
            'text': 'Tangentialebene',
          })
          ..addAll(dot(tx, ty, 'red', 'P(${fmt(tx)} | ${fmt(ty)} | ${fmt(f0)})'));
      }
    }

    // Gradient in (x0, y0): Pfeil in der Grundebene in Richtung des steilsten Anstiegs.
    final gradient = xy(raw['gradient']);
    if (gradient != null) {
      final (gx0, gy0) = gradient;
      final gx = fx(gx0, gy0), gy = fy(gx0, gy0), f0 = at(gx0, gy0);
      final norm = math.sqrt(gx * gx + gy * gy);
      if (!f0.isNaN && norm.isFinite && norm > 1e-12) {
        // Länge: ein Viertel der kürzeren Seite (in Rechen-Koordinaten).
        final s = 0.25 * math.min(x1 - x0, y1 - y0) / norm;
        out
          ..add({
            'type': 'line',
            'from': [px(gx0), py(gy0), 0],
            'to': p(gx0, gy0, f0),
            'stroke': 'gray',
            'dashed': true,
          })
          ..add({
            'type': 'arrow',
            'from': [px(gx0), py(gy0), 0],
            'to': [px(gx0 + gx * s), py(gy0 + gy * s), 0],
            'stroke': 'green',
            'text': 'grad f = (${fmt(gx)} | ${fmt(gy)})',
          })
          ..addAll(dot(gx0, gy0, 'green', ''));
      }
    }

    // Kurve auf der Fläche (z.B. eine Nebenbedingung): y = g(x) oder x(t), y(t).
    final curve = raw['curve'] ?? raw['kurve'] ?? raw['constraint'] ?? raw['nebenbedingung'];
    if (curve is Map) {
      final ey = MathExpression.tryParse(_str(curve['y']), names: const {'x', 't'});
      final ex = _str(curve['x']).isEmpty ? null : MathExpression.tryParse(_str(curve['x']), names: const {'t'});
      final (t0, t1) = _range(curve['t']) ?? (ex == null ? (x0, x1) : (0.0, 2 * math.pi));
      if (ey != null) {
        const steps = 64;
        final stroke = _str(curve['stroke'] ?? curve['fill']).isEmpty ? 'red' : _str(curve['stroke'] ?? curve['fill']);
        List<double>? last;
        var labelled = false;
        for (var k = 0; k <= steps; k++) {
          final t = t0 + (t1 - t0) * k / steps;
          final cx = ex == null ? t : ex.evaluate({'t': t});
          final cy = ey.evaluate({'x': cx, 't': t});
          final cz = cx.isFinite && cy.isFinite ? at(cx, cy) : double.nan;
          final inside = !cz.isNaN && cx >= x0 && cx <= x1 && cy >= y0 && cy <= y1;
          final here = inside ? p(cx, cy, cz) : null;
          if (last != null && here != null) {
            final text = !labelled && k >= steps ~/ 2 ? _str(curve['text'] ?? curve['label']) : '';
            if (text.isNotEmpty) labelled = true;
            out.add({
              'type': 'line',
              'from': last,
              'to': here,
              'stroke': stroke,
              'width': 2.5,
              if (text.isNotEmpty) 'text': text,
            });
          }
          last = here;
        }
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Welle / Achse
  // -------------------------------------------------------------------------

  static List<Map<String, dynamic>> _shaft(Map raw) {
    final segments = <({double d, double l, String text, String fill})>[];
    for (final s in raw['segments'] as List) {
      if (s is! Map) continue;
      final d = _num(s['d'] ?? s['diameter'] ?? s['durchmesser']) ?? (_num(s['r'] ?? s['radius']) ?? 0) * 2;
      final l = _num(s['l'] ?? s['length'] ?? s['laenge'] ?? s['länge']);
      if (d <= 0 || l == null || l <= 0) continue;
      segments.add((d: d, l: l, text: _str(s['text'] ?? s['label']), fill: _str(s['fill'])));
      if (segments.length >= 24) break;
    }
    if (segments.isEmpty) return const [];
    final total = segments.fold<double>(0, (sum, s) => sum + s.l);
    final dMax = segments.map((s) => s.d).reduce(math.max);

    // Achsrichtung: "x" (Standard), "y", "z" oder ein Vektor.
    var axis = switch (raw['axis']) {
      'y' || 'Y' => [0.0, 1.0, 0.0],
      'z' || 'Z' => [0.0, 0.0, 1.0],
      final List v when v.length >= 3 && v.every((e) => _num(e) != null) => [for (final e in v.take(3)) _num(e)!],
      _ => [1.0, 0.0, 0.0],
    };
    final norm = math.sqrt(axis.fold<double>(0, (s, v) => s + v * v));
    axis = norm < 1e-12 ? [1.0, 0.0, 0.0] : [for (final v in axis) v / norm];
    // „Oben“ quer zur Achse: z, bei senkrechter Achse x.
    final up = axis[2].abs() > 0.9 ? [1.0, 0.0, 0.0] : [0.0, 0.0, 1.0];
    final rawFrom = raw['from'] ?? raw['at'];
    final origin = rawFrom is List && rawFrom.length >= 3 && rawFrom.every((e) => _num(e) != null)
        ? [for (final e in rawFrom.take(3)) _num(e)!]
        // Ohne Angabe: Achse mittig über dem Boden.
        : [0.0, dMax * 0.9, dMax * 0.9];
    List<double> along(double s, [double lift = 0]) => [
      for (var q = 0; q < 3; q++) origin[q] + axis[q] * s + up[q] * lift,
    ];
    double radiusAt(double s) {
      var start = 0.0;
      for (final seg in segments) {
        if (s <= start + seg.l + 1e-9) return seg.d / 2;
        start += seg.l;
      }
      return segments.last.d / 2;
    }

    final baseFill = _str(raw['fill']).isEmpty ? 'gray' : _str(raw['fill']);
    final opacity = _num(raw['opacity']);
    // Abstand der Beschriftungen von der Oberfläche (Szenen-Einheiten); die
    // Schriftgröße selbst ist in Bildschirm-Pixeln.
    final gap = dMax * 0.28;
    const size = 12;
    final out = <Map<String, dynamic>>[];
    var start = 0.0;
    for (final (i, seg) in segments.indexed) {
      out.add({
        'type': 'cylinder',
        'from': along(start),
        'to': along(start + seg.l),
        'r': seg.d / 2,
        // Nachbarn leicht absetzen, damit man die Absätze sieht.
        'fill': seg.fill.isNotEmpty ? seg.fill : (baseFill == 'gray' ? (i.isEven ? '#9aa3ad' : '#b9c0c8') : baseFill),
        'opacity': ?opacity,
      });
      out.add({
        'type': 'text',
        'at': along(start + seg.l / 2, seg.d / 2 + gap),
        'text': seg.text.isNotEmpty ? seg.text : 'Ø${fmt(seg.d)}',
        'size': size,
      });
      start += seg.l;
    }

    double? pos(Object? m) => m is Map ? _num(m['at'] ?? m['x'] ?? m['pos']) : _num(m);

    // Markierte Querschnitte (z.B. der gefährdete): farbige Scheibe.
    final marks = raw['marks'] ?? raw['kritisch'];
    if (marks is List) {
      for (final m in marks.take(8)) {
        final s = pos(m);
        if (s == null) continue;
        final fill = m is Map && _str(m['fill']).isNotEmpty ? _str(m['fill']) : 'red';
        final r = radiusAt(s) * 1.12, w = math.max(total * 0.006, dMax * 0.03);
        out.add({'type': 'cylinder', 'from': along(s - w), 'to': along(s + w), 'r': r, 'fill': fill});
        final text = m is Map ? _str(m['text'] ?? m['label']) : '';
        if (text.isNotEmpty) {
          out.add({'type': 'text', 'at': along(s, -r - gap * 1.2), 'text': text, 'size': size, 'fill': fill});
        }
      }
    }

    // Lager: Keil von unten an die Welle.
    final supports = raw['supports'] ?? raw['lager'];
    if (supports is List) {
      for (final m in supports.take(6)) {
        final s = pos(m);
        if (s == null) continue;
        final r = radiusAt(s), h = dMax * 0.7;
        out.add({
          'type': 'cylinder',
          'from': along(s, -r - h),
          'to': along(s, -r),
          'r': h * 0.45,
          'r2': 0,
          'fill': 'accent',
        });
        final text = m is Map ? _str(m['text'] ?? m['label']) : '';
        if (text.isNotEmpty) {
          out.add({'type': 'text', 'at': along(s, -r - h - gap), 'text': text, 'size': size});
        }
      }
    }

    // Kräfte: Pfeil quer auf die Welle (Standard von oben, "dir": "up" von unten).
    final forces = raw['forces'] ?? raw['kraefte'] ?? raw['kräfte'];
    if (forces is List) {
      final len = math.max(dMax * 1.3, total * 0.1);
      for (final m in forces.take(8)) {
        final s = pos(m);
        if (s == null) continue;
        final r = radiusAt(s);
        final upward = m is Map && const {'up', 'oben', 'hoch', '+z'}.contains(_str(m['dir']).toLowerCase());
        final stroke = m is Map && _str(m['stroke'] ?? m['fill']).isNotEmpty ? _str(m['stroke'] ?? m['fill']) : 'red';
        out.add({
          'type': 'arrow',
          'from': along(s, upward ? -r - len : r + len),
          'to': along(s, upward ? -r : r),
          'stroke': stroke,
          'width': 3,
          if (m is Map && _str(m['text'] ?? m['label']).isNotEmpty) 'text': _str(m['text'] ?? m['label']),
        });
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Körper mit Kräften (Freischnitt)
  // -------------------------------------------------------------------------

  static List<double>? _vec3(Object? raw) => raw is List && raw.length >= 3 && raw.take(3).every((e) => _num(e) != null)
      ? [for (final e in raw.take(3)) _num(e)!]
      : null;

  /// Länge (x), Breite (y), Höhe (z) eines Körpers – in den Maßen der Aufgabe.
  static (double, double, double) _bodyDims(Map raw, String kind) {
    final round = kind == 'ball' || kind == 'roller';
    final rawSize = raw['size'] ?? raw['dims'] ?? raw['maße'] ?? raw['masse'];
    final given = rawSize is List ? [for (final v in rawSize.take(3)) _num(v)] : const <double?>[];
    double dim(int q, List<String> names, double fallback) {
      final v = (q < given.length ? given[q] : null) ?? names.map((n) => _num(raw[n])).whereType<double>().firstOrNull;
      return v != null && v > 0 ? v : fallback;
    }

    var l = dim(
      0,
      const ['l', 'length', 'laenge', 'länge'],
      switch (kind) {
        'car' => 4.0,
        'beam' => 4.0,
        _ => 1.0,
      },
    );
    var w = dim(
      1,
      const ['w', 'width', 'breite'],
      switch (kind) {
        'car' => l * 0.42,
        'beam' => l * 0.08,
        _ => l * 0.6,
      },
    );
    var h = dim(
      2,
      const ['h', 'height', 'hoehe', 'höhe'],
      switch (kind) {
        'car' => l * 0.34,
        'beam' => l * 0.08,
        _ => l * 0.6,
      },
    );
    if (round) {
      // Kugel/Walze: Durchmesser = Länge = Höhe.
      final d = _num(raw['d'] ?? raw['diameter'] ?? raw['durchmesser']) ?? (_num(raw['r'] ?? raw['radius']) ?? 0) * 2;
      if (d > 0) l = d;
      h = l;
      if (kind == 'ball') w = l;
    }
    // Unsinnige Verhältnisse (Tippfehler) entschärfen.
    w = w.clamp(l * 0.02, l * 5);
    h = h.clamp(l * 0.02, l * 5);
    return (l, w, h);
  }

  /// Art des Körper-Bausteins [raw]: 'car', 'block', 'ball', 'roller', 'beam' – sonst null.
  static String? bodyKindOf(Object? raw) => raw is Map ? _bodyKind(raw) : null;

  /// Maße und Aufstandspunkte des Autos [raw] in Körper-Koordinaten (x nach
  /// vorn, y quer): Radstand, Achsen ([xr] hinten, [xf] vorn), Spur ([yl]
  /// links, [yr] rechts), Radradius und Schwerpunkt. null, wenn [raw] kein Auto ist.
  static ({
    double l,
    double w,
    double h,
    double wheelbase,
    double xr,
    double xf,
    double yl,
    double yr,
    double r,
    double cgx,
    double cgz,
  })?
  carGeometry(Object? raw) {
    if (raw is! Map || _bodyKind(raw) != 'car') return null;
    final (l, w, h) = _bodyDims(raw, 'car');
    final wheelbase = (_num(raw['wheelbase'] ?? raw['radstand']) ?? l * 0.6).clamp(l * 0.2, l * 0.95);
    final r = ((_num(raw['wheel'] ?? raw['raddurchmesser']) ?? l * 0.15) / 2).clamp(l * 0.03, h * 0.45);
    final rawCg = raw['cg'] ?? raw['schwerpunkt'];
    final cgx = rawCg is List && rawCg.isNotEmpty ? _num(rawCg[0]) : (rawCg is Map ? _num(rawCg['x']) : null);
    final cgz = rawCg is List && rawCg.length > 1 ? _num(rawCg.last) : (rawCg is Map ? _num(rawCg['z']) : null);
    return (
      l: l,
      w: w,
      h: h,
      wheelbase: wheelbase,
      xr: (l - wheelbase) / 2,
      xf: (l + wheelbase) / 2,
      yl: w * 0.07,
      yr: w * 0.93,
      r: r,
      cgx: (cgx ?? l * 0.5).clamp(0.0, l),
      cgz: (cgz ?? h * 0.42).clamp(0.0, h),
    );
  }

  /// Länge, Auflager (ohne Einspannungen) und Einzelkräfte des Balkens [raw].
  /// Je Kraft: Lage [at], relative Größe [size] ("value", sonst "len", sonst
  /// 1) und [down] – der Anteil nach unten (+1 = von oben, −1 = von unten).
  /// null, wenn [raw] kein Balken ist oder eine Kraft keine Lage als Zahl hat.
  static ({double l, List<({double at, String text})> supports, List<({double at, double size, double down})> forces})?
  beamGeometry(Object? raw) {
    if (raw is! Map || _bodyKind(raw) != 'beam') return null;
    final (l, _, _) = _bodyDims(raw, 'beam');
    final supports = <({double at, String text})>[];
    final rawSupports = raw['supports'] ?? raw['lager'];
    if (rawSupports is List) {
      for (final m in rawSupports) {
        final x = m is Map ? _num(m['at'] ?? m['x'] ?? m['pos']) : _num(m);
        if (x == null) continue;
        final type = m is Map ? _str(m['kind'] ?? m['type'] ?? m['art']).toLowerCase() : '';
        if (const {'clamp', 'einspannung', 'wall', 'wand', 'fest eingespannt'}.contains(type)) return null;
        supports.add((at: x.clamp(0.0, l), text: m is Map ? _str(m['text'] ?? m['label']) : ''));
      }
    }
    supports.sort((a, b) => a.at.compareTo(b.at));
    final forces = <({double at, double size, double down})>[];
    final rawForces = raw['forces'] ?? raw['kraefte'] ?? raw['kräfte'];
    if (rawForces is List) {
      for (final m in rawForces) {
        if (m is! Map) continue;
        final x = _num(m['at'] ?? m['point'] ?? m['angriff']);
        if (x == null) return null;
        final angle = _num(m['angle'] ?? m['winkel']);
        final dir = _str(m['dir'] ?? m['direction'] ?? m['richtung']).toLowerCase();
        final down = angle != null
            ? -math.sin(angle * math.pi / 180)
            : const {'up', 'oben', 'hoch', '+z'}.contains(dir)
            ? -1.0
            : 1.0;
        forces.add((
          at: x.clamp(0.0, l),
          size: (_num(m['value'] ?? m['wert']) ?? _num(m['len'] ?? m['length'] ?? m['scale']) ?? 1).abs(),
          down: down,
        ));
      }
    }
    return (l: l, supports: supports, forces: forces);
  }

  static List<Map<String, dynamic>> _body(Map raw) {
    final kind = _bodyKind(raw)!;
    final beam = kind == 'beam';
    final round = kind == 'ball' || kind == 'roller';

    final (l, w, h) = _bodyDims(raw, kind);

    // Neigung der Unterlage in Grad (schiefe Ebene); der Balken liegt waagrecht.
    final slope = beam
        ? 0.0
        : (_num(raw['slope'] ?? raw['incline'] ?? raw['neigung'] ?? raw['alpha']) ?? 0).clamp(-60.0, 60.0) *
              math.pi /
              180;
    final cs = math.cos(slope), sn = math.sin(slope);
    // Körper-Koordinaten (x entlang der Unterlage, y quer, z senkrecht dazu) → Welt.
    List<double> world(List<double> p) => [p[0] * cs - p[2] * sn, p[1], p[0] * sn + p[2] * cs];

    final freed = raw['cut'] == true || raw['freigeschnitten'] == true || raw['free'] == true;
    final scale = math.max(l, h);
    final gap = scale * 0.06;
    const size = 12;
    final fill = _str(raw['fill']).isEmpty ? (beam ? 'gray' : 'accent') : _str(raw['fill']);
    final out = <Map<String, dynamic>>[];

    // Prisma: Umriss in der x–z-Ebene, von y0 bis y1.
    void prism(List<List<double>> outline, double y0, double y1, String color, {bool solid = false, double? opacity}) {
      Map<String, dynamic> face(List<List<double>> pts) => {
        'type': 'polygon',
        'points': [for (final q in pts) world(q)],
        'fill': color,
        if (solid) 'solid': true,
        'opacity': ?opacity,
      };
      out.add(
        face([
          for (final q in outline) [q[0], y0, q[1]],
        ]),
      );
      out.add(
        face([
          for (final q in outline) [q[0], y1, q[1]],
        ]),
      );
      for (var k = 0; k < outline.length; k++) {
        final a = outline[k], b = outline[(k + 1) % outline.length];
        out.add(
          face([
            [a[0], y0, a[1]],
            [b[0], y0, b[1]],
            [b[0], y1, b[1]],
            [a[0], y1, a[1]],
          ]),
        );
      }
    }

    void label(List<double> at, String text, {String? color}) {
      if (text.isEmpty) return;
      out.add({'type': 'text', 'at': world(at), 'text': text, 'size': size, 'fill': ?color});
    }

    // Unterkante des Körpers über der Unterlage und sein Schwerpunkt.
    var base = 0.0;
    late List<double> cg;
    final anchors = <String, List<double>>{};
    final mid = w / 2;

    if (kind == 'car') {
      final car = carGeometry(raw)!;
      final r = car.r, xr = car.xr, xf = car.xf;
      final z0 = r * 0.75, zb = z0 + (h - z0) * 0.5;
      // Karosserie und Kabine (vorn = +x).
      prism(
        [
          [0, z0],
          [l, z0],
          [l, zb],
          [0, zb],
        ],
        w * 0.06,
        w * 0.94,
        fill,
      );
      prism(
        [
          [l * 0.12, zb],
          [l * 0.78, zb],
          [l * 0.64, h],
          [l * 0.26, h],
        ],
        w * 0.1,
        w * 0.9,
        fill,
      );
      // Angehobene Räder ("lifted": ["fl", "rr"] …) stehen sichtbar über der Fahrbahn.
      final rawLifted = raw['lifted'] ?? raw['angehoben'];
      final lifted = {
        if (rawLifted is List)
          for (final v in rawLifted) _str(v).toLowerCase(),
      };
      for (final (x, axle) in [(xr, 'r'), (xf, 'f')]) {
        for (final (y0, y1, side) in [(0.0, w * 0.14, 'l'), (w * 0.86, w, 'r')]) {
          final up = lifted.contains('$axle$side');
          final z = up ? r * 1.7 : r;
          out.add({
            'type': 'cylinder',
            'from': world([x, y0, z]),
            'to': world([x, y1, z]),
            'r': r,
            'fill': up ? 'orange' : '#2b2f36',
          });
        }
      }
      cg = [car.cgx, mid, car.cgz];
      anchors.addAll({
        'front': [xf, mid, 0],
        'rear': [xr, mid, 0],
        'front_axle': [xf, mid, r],
        'rear_axle': [xr, mid, r],
        'top': [l / 2, mid, h],
        'nose': [l, mid, (z0 + zb) / 2],
        'tail': [0, mid, (z0 + zb) / 2],
        'bottom': [l / 2, mid, 0],
      });
    } else if (kind == 'block') {
      prism(
        [
          [0, 0],
          [l, 0],
          [l, h],
          [0, h],
        ],
        0,
        w,
        fill,
      );
      cg = [l / 2, mid, h / 2];
      anchors.addAll({
        'bottom': [l / 2, mid, 0],
        'top': [l / 2, mid, h],
        'front': [l, mid, h / 2],
        'rear': [0, mid, h / 2],
        'front_bottom': [l, mid, 0],
        'rear_bottom': [0, mid, 0],
      });
    } else if (round) {
      final r = l / 2;
      if (kind == 'ball') {
        out.add({
          'type': 'sphere',
          'at': world([r, mid, r]),
          'r': r,
          'fill': fill,
          'opacity': 0.55,
        });
      } else {
        out.add({
          'type': 'cylinder',
          'from': world([r, 0, r]),
          'to': world([r, w, r]),
          'r': r,
          'fill': fill,
          'opacity': 0.55,
        });
      }
      cg = [r, mid, r];
      anchors.addAll({
        'bottom': [r, mid, 0],
        'top': [r, mid, l],
        'front': [l, mid, r],
        'rear': [0, mid, r],
      });
    } else {
      // Balken auf Lagern.
      base = l * 0.12;
      prism(
        [
          [0, base],
          [l, base],
          [l, base + h],
          [0, base + h],
        ],
        0,
        w,
        fill,
        solid: true,
      );
      cg = [l / 2, mid, base + h / 2];
      anchors.addAll({
        'left': [0, mid, base + h / 2],
        'right': [l, mid, base + h / 2],
        'top': [l / 2, mid, base + h],
        'bottom': [l / 2, mid, base],
      });
      final supports = raw['supports'] ?? raw['lager'];
      if (supports is List) {
        for (final m in supports.take(6)) {
          final x = (m is Map ? _num(m['at'] ?? m['x'] ?? m['pos']) : _num(m))?.clamp(0.0, l);
          if (x == null) continue;
          final type = m is Map ? _str(m['kind'] ?? m['type'] ?? m['art']).toLowerCase() : '';
          final text = m is Map ? _str(m['text'] ?? m['label']) : '';
          if (const {'clamp', 'einspannung', 'wall', 'wand', 'fest eingespannt'}.contains(type)) {
            // Einspannung: Wand am Balkenende.
            final (x0, x1) = x < l / 2 ? (x - l * 0.06, x) : (x, x + l * 0.06);
            prism(
              [
                [x0, 0],
                [x1, 0],
                [x1, base * 2 + h],
                [x0, base * 2 + h],
              ],
              -w * 0.6,
              w * 1.6,
              '#8a929c',
              solid: true,
            );
            label([(x0 + x1) / 2, mid, -gap], text);
            continue;
          }
          final loose = const {'roller', 'loslager', 'los', 'loose', 'gleitlager'}.contains(type);
          final foot = loose ? base * 0.28 : 0.0;
          out.add({
            'type': 'cylinder',
            'from': world([x, mid, foot]),
            'to': world([x, mid, base]),
            'r': base * 0.5,
            'r2': 0,
            'fill': 'accent',
          });
          if (loose) {
            // Loslager: rollt auf zwei Walzen.
            for (final dx in [-base * 0.25, base * 0.25]) {
              out.add({
                'type': 'cylinder',
                'from': world([x + dx, mid - base * 0.5, foot / 2]),
                'to': world([x + dx, mid + base * 0.5, foot / 2]),
                'r': foot / 2,
                'fill': '#2b2f36',
              });
            }
          }
          label([x, mid, -gap], text);
        }
      }
    }
    anchors['cg'] = cg;
    final centre = [l / 2, mid, base + h / 2];

    // Unterlage: Platte unter dem Körper; freigeschnitten nur gestrichelt
    // angedeutet. Bei Neigung ein Keil mit dem Winkel.
    if (!beam && raw['ground'] != false) {
      final xa = -l * 0.3, xb = l * 1.3, ya = -w * 0.25, yb = w * 1.25;
      if (freed) {
        final corners = [
          [xa, ya, 0.0],
          [xb, ya, 0.0],
          [xb, yb, 0.0],
          [xa, yb, 0.0],
        ];
        for (var k = 0; k < 4; k++) {
          out.add({
            'type': 'line',
            'from': world(corners[k]),
            'to': world(corners[(k + 1) % 4]),
            'stroke': 'gray',
            'dashed': true,
          });
        }
      } else {
        final t = scale * 0.03;
        prism(
          [
            [xa, -t],
            [xb, -t],
            [xb, 0],
            [xa, 0],
          ],
          ya,
          yb,
          '#8a929c',
          solid: true,
        );
      }
      if (slope.abs() > 0.01) {
        final lo = world([slope > 0 ? xa : xb, ya, 0]), hi = world([slope > 0 ? xb : xa, ya, 0]);
        if (!freed) {
          // Keil unter der schiefen Ebene bis zur Waagrechten.
          final t = scale * 0.03;
          final corners = [
            [lo[0], lo[2] - t],
            [hi[0], lo[2] - t],
            [hi[0], hi[2] - t],
          ];
          List<double> at(int k, double y) => [corners[k][0], y, corners[k][1]];
          for (final y in [ya, yb]) {
            out.add({
              'type': 'polygon',
              'points': [for (var k = 0; k < 3; k++) at(k, y)],
              'fill': '#8a929c',
            });
          }
          // Boden und Rückwand.
          for (final (i, j) in [(0, 1), (1, 2)]) {
            out.add({
              'type': 'polygon',
              'points': [at(i, ya), at(j, ya), at(j, yb), at(i, yb)],
              'fill': '#8a929c',
            });
          }
        }
        out.add({
          'type': 'line',
          'from': [lo[0], ya, lo[2]],
          'to': [hi[0], ya, lo[2]],
          'stroke': 'gray',
          'dashed': true,
        });
        final angle = _str(raw['slopeText'] ?? raw['angleText']);
        out.add({
          'type': 'text',
          'at': [lo[0] + (hi[0] - lo[0]) * 0.22, ya, lo[2] + (hi[2] - lo[2]) * 0.08 + gap * 0.4],
          'text': angle.isNotEmpty ? angle : 'α = ${fmt(slope.abs() * 180 / math.pi)}°',
          'size': size,
        });
      }
    }

    // Angriffspunkt: Name, Abstand entlang der Länge (Balken: auf der
    // Oberseite, sonst auf der Unterlage) oder Anteile [Länge, Breite, Höhe].
    List<double>? anchor(Object? at, {bool bottom = false}) {
      if (at is List) {
        final v = _vec3(at);
        return v == null ? null : [v[0].clamp(0.0, 1.0) * l, v[1].clamp(0.0, 1.0) * w, base + v[2].clamp(0.0, 1.0) * h];
      }
      final x = _num(at);
      if (x != null) return [x.clamp(0.0, l), mid, beam && !bottom ? base + h : base];
      final name = _str(at).toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
      return anchors[switch (name) {
        '' || 's' || 'schwerpunkt' || 'center' || 'centre' || 'mitte' || 'com' => 'cg',
        'vorn' || 'vorne' || 'vorderachse' || 'vorderrad' || 'front_wheel' => 'front',
        'hinten' || 'hinterachse' || 'hinterrad' || 'rear_wheel' || 'back' => 'rear',
        'oben' => 'top',
        'unten' || 'kontakt' || 'contact' || 'aufstandspunkt' => 'bottom',
        'links' => beam ? 'left' : 'rear',
        'rechts' => beam ? 'right' : 'front',
        _ => name,
      }];
    }

    // Richtung in Welt-Koordinaten (Einheitsvektor).
    List<double>? direction(Map m) {
      List<double>? unit(List<double> v) {
        final n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        return n < 1e-12 ? null : [for (final c in v) c / n];
      }

      final angle = _num(m['angle'] ?? m['winkel']);
      if (angle != null) {
        // Winkel gegen die Waagrechte (+x), 90° = nach oben.
        final a = angle * math.pi / 180;
        return [math.cos(a), 0, math.sin(a)];
      }
      final rawDir = m['dir'] ?? m['direction'] ?? m['richtung'];
      final v = _vec3(rawDir);
      if (v != null) return unit(v);
      return switch (_str(rawDir).toLowerCase()) {
        'up' || 'oben' || 'hoch' || '+z' => [0.0, 0.0, 1.0],
        'normal' || 'senkrecht' || 'n' => unit(world([0, 0, 1])),
        'into' || 'andrücken' => unit(world([0, 0, -1])),
        'forward' ||
        'along' ||
        'uphill' ||
        'vorwärts' ||
        'hangaufwärts' ||
        'right' ||
        'rechts' ||
        '+x' => unit(world([1, 0, 0])),
        'back' ||
        'backward' ||
        'downhill' ||
        'rückwärts' ||
        'hangabwärts' ||
        'left' ||
        'links' ||
        '-x' => unit(world([-1, 0, 0])),
        'side' || 'seitlich' || '+y' => [0.0, 1.0, 0.0],
        '-y' => [0.0, -1.0, 0.0],
        _ => [0.0, 0.0, -1.0],
      };
    }

    // Länge eines Kraftpfeils (bei "len": 1).
    final unitLen = beam ? l * 0.2 : scale * 0.32;
    var usesCg = false;

    final forces = raw['forces'] ?? raw['kraefte'] ?? raw['kräfte'];
    if (forces is List) {
      for (final m in forces.take(12)) {
        if (m is! Map) continue;
        final at = m['at'] ?? m['point'] ?? m['angriff'];
        final local = anchor(at, bottom: const {'bottom', 'unten'}.contains(_str(m['side']).toLowerCase()));
        final dir = direction(m);
        if (local == null || dir == null) continue;
        final a = world(local), c = world(centre);
        final atCg = identical(local, cg);
        if (atCg) usesCg = true;
        final len = unitLen * (_num(m['len'] ?? m['length'] ?? m['scale']) ?? 1).clamp(0.2, 3.0);
        // Der Pfeil steht außerhalb des Körpers: zeigt die Kraft vom
        // Angriffspunkt in den Körper hinein, endet er dort; sonst beginnt er dort.
        final inward = !atCg && dir[0] * (a[0] - c[0]) + dir[1] * (a[1] - c[1]) + dir[2] * (a[2] - c[2]) < -1e-9;
        final tipAt = m['tip'] == true || (m['tip'] != false && inward);
        final from = tipAt ? [for (var q = 0; q < 3; q++) a[q] - dir[q] * len] : a;
        final to = tipAt ? a : [for (var q = 0; q < 3; q++) a[q] + dir[q] * len];
        final given = _str(m['stroke'] ?? m['color'] ?? m['fill']);
        out.add({
          'type': 'arrow',
          'from': from,
          'to': to,
          'stroke': given.isNotEmpty
              ? given
              : dir[2] < -0.9
              ? 'red'
              : dir[2] > 0.5
              ? 'green'
              : 'orange',
          'width': 3,
          if (_str(m['text'] ?? m['label']).isNotEmpty) 'text': _str(m['text'] ?? m['label']),
        });
      }
    }

    // Streckenlasten (Balken): Pfeilreihe von oben mit Verbindungslinie.
    final loads = raw['loads'] ?? raw['streckenlast'] ?? raw['streckenlasten'];
    if (beam && loads is List) {
      for (final m in loads.take(4)) {
        if (m is! Map) continue;
        final x0 = (_num(m['from'] ?? m['von']) ?? 0).clamp(0.0, l),
            x1 = (_num(m['to'] ?? m['bis']) ?? l).clamp(0.0, l);
        if (x1 - x0 < l * 0.02) continue;
        final n = ((x1 - x0) / l * 10).round().clamp(3, 9);
        final top = base + h, len = unitLen * 0.55;
        final stroke = _str(m['stroke'] ?? m['color']).isEmpty ? 'purple' : _str(m['stroke'] ?? m['color']);
        for (var k = 0; k <= n; k++) {
          final x = x0 + (x1 - x0) * k / n;
          out.add({
            'type': 'arrow',
            'from': world([x, mid, top + len]),
            'to': world([x, mid, top]),
            'stroke': stroke,
            'width': 2,
          });
        }
        out.add({
          'type': 'line',
          'from': world([x0, mid, top + len]),
          'to': world([x1, mid, top + len]),
          'stroke': stroke,
          'width': 2,
        });
        label([(x0 + x1) / 2, mid, top + len + gap], _str(m['text'] ?? m['label']), color: stroke);
      }
    }

    // Momente: Kreisbogen mit Pfeilspitze um den Punkt (in der x–z-Ebene).
    final moments = raw['moments'] ?? raw['momente'];
    if (moments is List) {
      for (final m in moments.take(4)) {
        if (m is! Map) continue;
        final local = anchor(m['at'] ?? m['point']);
        if (local == null) continue;
        final p0 = beam ? [local[0], mid, base + h / 2] : local;
        final r = beam ? math.max(h * 1.3, l * 0.07) : scale * 0.16;
        final cw = const {
          'cw',
          'rechts',
          'uhrzeigersinn',
          'clockwise',
        }.contains(_str(m['dir'] ?? m['sense']).toLowerCase());
        final stroke = _str(m['stroke'] ?? m['color']).isEmpty ? 'orange' : _str(m['stroke'] ?? m['color']);
        const steps = 8;
        List<double> on(int k) {
          // Dreiviertelkreis, Start oben.
          final a = math.pi / 2 + (cw ? -1 : 1) * 1.5 * math.pi * k / steps;
          return world([p0[0] + r * math.cos(a), p0[1], p0[2] + r * math.sin(a)]);
        }

        for (var k = 0; k < steps; k++) {
          out.add({
            'type': k == steps - 1 ? 'arrow' : 'line',
            'from': on(k),
            'to': on(k + 1),
            'stroke': stroke,
            'width': 2.5,
          });
        }
        label([p0[0], p0[1], p0[2] + r + gap], _str(m['text'] ?? m['label']), color: stroke);
      }
    }

    // Schwerpunkt zeigen, wenn dort eine Kraft angreift.
    if (!beam && (usesCg || raw['showCg'] == true)) {
      out.add({'type': 'sphere', 'at': world(cg), 'r': scale * 0.022, 'fill': 'ink'});
      label([cg[0] - scale * 0.06, cg[1], cg[2] + scale * 0.05], 'S');
    }

    // Maßlinien unter dem Körper: zwischen zwei Angriffspunkten entlang der Länge.
    final measures = raw['measures'] ?? raw['bemaßung'] ?? raw['bemassung'] ?? raw['masslinien'];
    if (measures is List) {
      var row = 1;
      for (final m in measures.take(4)) {
        if (m is! Map) continue;
        final a = anchor(m['from'] ?? m['von']), b = anchor(m['to'] ?? m['bis']);
        if (a == null || b == null || (a[0] - b[0]).abs() < l * 0.01) continue;
        final z = -scale * 0.09 * row - (beam ? gap : 0);
        row++;
        out.add({
          'type': 'line',
          'from': world([a[0], mid, z]),
          'to': world([b[0], mid, z]),
          'stroke': 'ink',
          'width': 1,
        });
        for (final x in [a[0], b[0]]) {
          out.add({
            'type': 'line',
            'from': world([x, mid, z - gap * 0.3]),
            'to': world([x, mid, z + gap * 0.3]),
            'stroke': 'ink',
            'width': 1,
          });
        }
        label([(a[0] + b[0]) / 2, mid, z - gap * 0.7], _str(m['text'] ?? m['label']));
      }
    }

    // Alles in den positiven Raum schieben (mit Rand); "at" versetzt zusätzlich.
    Iterable<List<double>> pointsOf(Map<String, dynamic> o) sync* {
      for (final k in const ['at', 'from', 'to']) {
        if (o[k] is List<double>) yield o[k] as List<double>;
      }
      if (o['points'] is List) yield* (o['points'] as List).cast<List<double>>();
    }

    final lo = [double.infinity, double.infinity, double.infinity];
    for (final o in out) {
      final r = o['type'] == 'sphere' || o['type'] == 'cylinder' ? (o['r'] as num).toDouble() : 0.0;
      for (final p in pointsOf(o)) {
        for (var q = 0; q < 3; q++) {
          lo[q] = math.min(lo[q], p[q] - r);
        }
      }
    }
    final offset = _vec3(raw['at'] ?? raw['origin']) ?? const [0.0, 0.0, 0.0];
    final margin = scale * 0.08;
    for (final o in out) {
      for (final p in pointsOf(o)) {
        for (var q = 0; q < 3; q++) {
          p[q] = p[q] - lo[q] + margin + offset[q];
        }
      }
    }
    return out;
  }
}
