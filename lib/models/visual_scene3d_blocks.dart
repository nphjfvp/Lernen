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

  /// Ist [raw] ein Baustein (und keine einfache Form)?
  static bool isBlock(Object? raw) => raw is Map && (_isSurface(raw) || _isShaft(raw));

  /// Die einfachen Formen, aus denen der Baustein [raw] besteht – im
  /// Koordinatensystem der Szene mit dem Raum [box]. Leer, wenn sich der
  /// Baustein nicht lesen lässt.
  static List<Map<String, dynamic>> expand(Map raw, List<double> box) {
    try {
      if (_isSurface(raw)) return _surface(raw, box);
      if (_isShaft(raw)) return _shaft(raw);
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
}
