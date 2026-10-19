import 'dart:convert';
import 'dart:ui' show Color;

import '../models/visual_scene3d.dart';

/// Die Bibliotheken für die echte 3D-Ansicht (three.js, als klassische
/// Skripte – laufen auch als lokale Datei ohne Server), aus assets/three/.
class ThreeJsSources {
  const ThreeJsSources({required this.three, required this.orbitControls, required this.css2d});

  final String three;
  final String orbitControls;
  final String css2d;
}

/// Farben der App für die 3D-Ansicht (aus AppColors), damit sie wie die
/// eingebaute Darstellung aussieht.
class Scene3DPalette {
  const Scene3DPalette({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.warn,
  });

  final Color bg;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color warn;
}

/// Baut aus einer [VisualScene3D] eine eigenständige HTML-Seite mit echtem 3D
/// (three.js): Licht und Schatten, mit Finger/Maus drehen, zoomen und
/// verschieben, dazu Abspielen, Zeitregler, Beschriftung und mitlaufende
/// Größe wie in der App. Alles steckt in der Seite – kein Netz nötig.
///
/// Farben werden hier aufgelöst ([resolveColor], z.B. die Namen der KI wie
/// „rot“), das Skript bekommt nur noch Hex-Werte.
class Scene3DHtml {
  Scene3DHtml._();

  static String build({
    required VisualScene3D scene,
    required String title,
    required Scene3DPalette palette,
    required ThreeJsSources libs,
    required Color? Function(String name) resolveColor,
  }) {
    String? hex(String name) {
      if (name.trim().isEmpty) return null;
      final c = resolveColor(name);
      return c == null ? null : _hex(c);
    }

    final data = {
      'title': plainMath(title),
      'box': scene.box,
      'frame': scene.frame,
      'axes': scene.axes,
      'spin': scene.spin,
      'seconds': scene.seconds,
      'captions': [
        for (final c in scene.captions) {'at': c.at, 'text': plainMath(c.text)},
      ],
      'param': scene.hasParam
          ? {
              'name': plainMath(scene.paramName),
              'unit': plainMath(scene.paramUnit),
              'from': scene.paramFrom,
              'to': scene.paramTo,
            }
          : null,
      'palette': {
        'bg': _hex(palette.bg),
        'surface': _hex(palette.surface),
        'ink': _hex(palette.ink),
        'muted': _hex(palette.muted),
        'accent': _hex(palette.accent),
        'warn': _hex(palette.warn),
      },
      'objects': [
        for (final o in scene.objects)
          {
            'shape': o.shape.name,
            'numbers': o.numbers,
            'vectors': o.vectors,
            'points': o.points,
            'fill': hex(o.fill),
            'stroke': hex(o.stroke),
            'text': plainMath(o.text),
            'dashed': o.dashed,
            'n': o.n,
            'd': o.d,
            'keys': [
              for (final k in o.keys)
                {
                  't': k.at,
                  'numbers': k.numbers,
                  'vectors': k.vectors,
                  'points': k.points,
                  'fill': k.fill == null ? null : hex(k.fill!),
                  'stroke': k.stroke == null ? null : hex(k.stroke!),
                  'text': k.text == null ? null : plainMath(k.text!),
                },
            ],
          },
      ],
    };
    // Erst die Farben, dann der Titel (er könnte Platzhalter enthalten), zuletzt
    // Bibliotheken und Szene – deren Inhalt wird nicht mehr durchsucht.
    return _template
        .replaceAll('__BG__', _hex(palette.bg))
        .replaceAll('__INK__', _hex(palette.ink))
        .replaceAll('__MUTED__', _hex(palette.muted))
        .replaceAll('__SURFACE__', _hex(palette.surface))
        .replaceAll('__ACCENT__', _hex(palette.accent))
        .replaceFirst('__TITLE__', _escapeHtml(title))
        .replaceFirst('/*__THREE__*/', libs.three)
        .replaceFirst('/*__ORBIT__*/', libs.orbitControls)
        .replaceFirst('/*__CSS2D__*/', libs.css2d)
        .replaceFirst('/*__SCENE__*/null', _jsonForScript(data));
  }

  static String _hex(Color c) {
    final v = c.toARGB32() & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  /// JSON, das man gefahrlos in ein `<script>` schreiben kann (kein
  /// `</script>`, kein `<!--`).
  static String _jsonForScript(Object data) =>
      jsonEncode(data).replaceAll('<', '\\u003c').replaceAll('\u2028', '\\u2028').replaceAll('\u2029', '\\u2029');

  static String _escapeHtml(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

/// Formeln (`$…$`) als lesbarer Text für die 3D-Ansicht, die kein LaTeX
/// setzt: häufige Befehle als Zeichen (√, ·, ², α …), der Rest ohne Backslash.
String plainMath(String text) {
  if (!text.contains('\$')) return text;
  return text.replaceAllMapped(RegExp(r'\$\$?(.+?)\$\$?', dotAll: true), (m) => _latexToText(m.group(1)!));
}

const _latexSymbols = {
  'cdot': '·',
  'times': '×',
  'pm': '±',
  'leq': '≤',
  'le': '≤',
  'geq': '≥',
  'ge': '≥',
  'neq': '≠',
  'ne': '≠',
  'approx': '≈',
  'infty': '∞',
  'to': '→',
  'rightarrow': '→',
  'Rightarrow': '⇒',
  'degree': '°',
  'circ': '°',
  'alpha': 'α',
  'beta': 'β',
  'gamma': 'γ',
  'delta': 'δ',
  'Delta': 'Δ',
  'epsilon': 'ε',
  'varepsilon': 'ε',
  'eta': 'η',
  'theta': 'θ',
  'lambda': 'λ',
  'mu': 'μ',
  'nu': 'ν',
  'pi': 'π',
  'rho': 'ρ',
  'sigma': 'σ',
  'Sigma': 'Σ',
  'tau': 'τ',
  'phi': 'φ',
  'varphi': 'φ',
  'omega': 'ω',
  'Omega': 'Ω',
  'sum': 'Σ',
  'int': '∫',
  'partial': '∂',
  'nabla': '∇',
  'sqrt': '√',
};
const _latexOperators = {
  'cdot',
  'times',
  'pm',
  'leq',
  'le',
  'geq',
  'ge',
  'neq',
  'ne',
  'approx',
  'to',
  'rightarrow',
  'Rightarrow',
};
const _sup = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
  '-': '⁻',
  '+': '⁺',
  'n': 'ⁿ',
};
const _sub = {
  '0': '₀',
  '1': '₁',
  '2': '₂',
  '3': '₃',
  '4': '₄',
  '5': '₅',
  '6': '₆',
  '7': '₇',
  '8': '₈',
  '9': '₉',
  '-': '₋',
  '+': '₊',
};

String _latexToText(String latex) {
  // Maskierte Sonderzeichen (\%, \&, \#) zuerst.
  var s = latex.replaceAllMapped(RegExp(r'\\([%&#])'), (m) => m[1]!);
  String group(String body) => body.length == 1 ? body : '($body)';
  // \frac{a}{b} und \sqrt{x} (auch verschachtelt: mehrfach anwenden).
  for (var i = 0; i < 4; i++) {
    s = s
        .replaceAllMapped(RegExp(r'\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}'), (m) => '${group(m[1]!)}/${group(m[2]!)}')
        .replaceAllMapped(RegExp(r'\\sqrt\{([^{}]*)\}'), (m) => '√${group(m[1]!)}')
        .replaceAllMapped(RegExp(r'\\(?:text|mathrm|mathbf|mathit|operatorname)\{([^{}]*)\}'), (m) => m[1]!);
  }
  String script(String body, Map<String, String> table, String mark) =>
      body.split('').every(table.containsKey) ? body.split('').map((c) => table[c]!).join() : '$mark$body';
  s = s
      .replaceAllMapped(RegExp(r'\^\{([^{}]*)\}'), (m) => script(m[1]!, _sup, '^'))
      .replaceAllMapped(RegExp(r'\^(\w)'), (m) => script(m[1]!, _sup, '^'))
      .replaceAllMapped(RegExp(r'_\{([^{}]*)\}'), (m) => script(m[1]!, _sub, '_'))
      .replaceAllMapped(RegExp(r'_(\w)'), (m) => script(m[1]!, _sub, '_'))
      .replaceAll(RegExp(r'\\(left|right|big|Big)'), '')
      .replaceAll(RegExp(r'\\[,;: !]'), ' ')
      // Das Leerzeichen hinter einem Befehl gehört in LaTeX zum Befehl (\Delta T = ΔT);
      // Rechenzeichen bekommen Abstand.
      .replaceAllMapped(RegExp(r'\\([A-Za-z]+) ?'), (m) {
        final sym = _latexSymbols[m[1]!];
        if (sym == null) return m[1]!;
        return _latexOperators.contains(m[1]) ? ' $sym ' : sym;
      })
      .replaceAll(RegExp(r'[{}]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  return s.trim();
}

// Ersetzungen: __TITLE__ usw. (siehe build). Die Bibliotheken kommen als
// eigene <script>-Blöcke vor dem Szenen-Skript.
const _template = r'''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>__TITLE__ – 3D</title>
<style>
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; background: __BG__; color: __INK__;
    font: 15px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; overflow: hidden; }
  #view { position: absolute; inset: 0 0 112px 0; }
  #view canvas { display: block; }
  .labels { position: absolute; inset: 0; }
  .lbl { font-weight: 600; white-space: nowrap; text-shadow: 0 0 3px __SURFACE__, 0 0 3px __SURFACE__; pointer-events: none; }
  #bar { position: absolute; left: 0; right: 0; bottom: 0; height: 112px; padding: 10px 14px;
    background: __SURFACE__; border-top: 1px solid rgba(0,0,0,.08); }
  #title { font-weight: 600; margin-bottom: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  #caption { color: __MUTED__; min-height: 20px; font-size: 14px; }
  .row { display: flex; align-items: center; gap: 10px; margin-top: 6px; }
  button { font: inherit; border: 1px solid rgba(0,0,0,.15); background: __BG__; color: __INK__;
    border-radius: 999px; padding: 6px 14px; cursor: pointer; }
  input[type=range] { flex: 1; accent-color: __ACCENT__; }
  #param { min-width: 90px; text-align: right; font-weight: 600; font-size: 14px; }
  #hint { position: absolute; top: 10px; left: 12px; color: __MUTED__; font-size: 12px; pointer-events: none; }
  #error { position: absolute; inset: 0; display: none; align-items: center; justify-content: center; padding: 24px;
    text-align: center; color: __MUTED__; }
</style>
</head>
<body>
<div id="view"><div id="hint">Ziehen: drehen · zwei Finger / Mausrad: zoomen · rechts / Strg: verschieben</div></div>
<div id="error">Diese Ansicht braucht WebGL – der Browser bzw. das Gerät unterstützt es gerade nicht.</div>
<div id="bar">
  <div id="title"></div>
  <div id="caption"></div>
  <div class="row">
    <button id="play">Pause</button>
    <button id="reset">Ansicht</button>
    <input id="time" type="range" min="0" max="1000" value="0">
    <div id="param"></div>
  </div>
</div>
<script>/*__THREE__*/</script>
<script>/*__ORBIT__*/</script>
<script>/*__CSS2D__*/</script>
<script>
(function () {
  const S = /*__SCENE__*/null;
  const P = S.palette;
  const box = S.box;
  const m = Math.max(box[0], box[1], box[2]);
  document.getElementById('title').textContent = S.title;

  const view = document.getElementById('view');
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ antialias: true });
  } catch (e) {
    document.getElementById('error').style.display = 'flex';
    return;
  }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  view.appendChild(renderer.domElement);
  const labels = new THREE.CSS2DRenderer();
  labels.domElement.className = 'labels';
  view.appendChild(labels.domElement);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(P.bg);
  const camera = new THREE.PerspectiveCamera(38, 1, m * 0.01, m * 100);
  camera.up.set(0, 0, 1); // z nach oben wie in der App
  const center = new THREE.Vector3(box[0] / 2, box[1] / 2, box[2] / 2);
  const home = new THREE.Vector3(center.x + m * 1.7, center.y - m * 2.3, center.z + m * 1.3);
  camera.position.copy(home);
  const controls = new THREE.OrbitControls(camera, labels.domElement);
  controls.target.copy(center);
  controls.enableDamping = true;
  controls.update();

  scene.add(new THREE.HemisphereLight(0xffffff, 0x8a96a8, 0.7));
  const sun = new THREE.DirectionalLight(0xffffff, 0.8);
  sun.position.set(center.x + m * 1.2, center.y - m * 0.8, center.z + m * 3);
  sun.target.position.copy(center);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  Object.assign(sun.shadow.camera, { left: -m * 2, right: m * 2, top: m * 2, bottom: -m * 2, near: m * 0.1, far: m * 8 });
  scene.add(sun, sun.target);
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(m * 8, m * 8), new THREE.ShadowMaterial({ opacity: 0.16 }));
  ground.position.set(center.x, center.y, -m * 0.02);
  ground.receiveShadow = true;
  scene.add(ground);

  // ---- Zeitverlauf wie in der App (Scene3DObject.number/vector/…) ----
  function track(list, p, lerp) {
    if (!list.length) return null;
    list.sort((a, b) => a[0] - b[0]);
    if (p <= list[0][0]) return list[0][1];
    for (let i = 0; i < list.length - 1; i++) {
      const a = list[i], b = list[i + 1];
      if (p <= b[0]) {
        const span = b[0] - a[0];
        return span <= 0 ? b[1] : lerp(a[1], b[1], (p - a[0]) / span);
      }
    }
    return list[list.length - 1][1];
  }
  const lerpV = (a, b, f) => [0, 1, 2].map(i => a[i] + (b[i] - a[i]) * f);
  function num(o, prop, p) {
    const l = [];
    if (typeof o.numbers[prop] === 'number') l.push([0, o.numbers[prop]]);
    for (const k of o.keys) if (typeof k.numbers[prop] === 'number') l.push([k.t, k.numbers[prop]]);
    return track(l, p, (a, b, f) => a + (b - a) * f);
  }
  function vec(o, prop, p) {
    const l = [];
    if (o.vectors[prop]) l.push([0, o.vectors[prop]]);
    for (const k of o.keys) if (k.vectors[prop]) l.push([k.t, k.vectors[prop]]);
    return track(l, p, lerpV);
  }
  function pointsAt(o, p) {
    const l = [];
    if (o.points.length) l.push([0, o.points]);
    for (const k of o.keys) if (k.points) l.push([k.t, k.points]);
    return track(l, p, (a, b, f) => a.length !== b.length ? (f < 0.5 ? a : b) : a.map((v, i) => lerpV(v, b[i], f))) || [];
  }
  function colorAt(o, which, p) {
    const l = [];
    if (o[which]) l.push([0, o[which]]);
    for (const k of o.keys) if (k[which]) l.push([k.t, k[which]]);
    if (!l.length) return null;
    return track(l, p, (a, b, f) => new THREE.Color(a).lerp(new THREE.Color(b), f).getStyle());
  }
  function textAt(o, p) {
    let out = o.text;
    for (const k of [...o.keys].sort((a, b) => a.t - b.t)) if (k.t <= p && k.text != null) out = k.text;
    return out;
  }
  // Formeln ($…$) zeigt die 3D-Ansicht als Text – ohne die Dollarzeichen.
  const plain = s => (s || '').replace(/\$\$?/g, '');

  function label(text, color, size) {
    const div = document.createElement('div');
    div.className = 'lbl';
    div.style.color = color;
    div.style.fontSize = (size || 14) + 'px';
    div.textContent = plain(text);
    return new THREE.CSS2DObject(div);
  }
  function setLabel(obj, text, color) {
    obj.element.textContent = plain(text);
    obj.element.style.color = color;
    obj.visible = !!text;
  }

  // Rahmen (Kanten des Raums) und Achsen
  if (S.frame) {
    const edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(new THREE.BoxGeometry(box[0], box[1], box[2])),
      new THREE.LineBasicMaterial({ color: P.muted, transparent: true, opacity: 0.6 }));
    edges.position.copy(center);
    scene.add(edges);
  }
  if (S.axes) {
    ['x', 'y', 'z'].forEach((name, i) => {
      const dir = new THREE.Vector3(i === 0 ? 1 : 0, i === 1 ? 1 : 0, i === 2 ? 1 : 0);
      const len = box[i] + m * 0.25;
      scene.add(new THREE.ArrowHelper(dir, new THREE.Vector3(0, 0, 0), len, new THREE.Color(P.muted), m * 0.05, m * 0.03));
      const l = label(name, P.muted, 14);
      l.element.style.fontStyle = 'italic';
      l.position.copy(dir.clone().multiplyScalar(len + m * 0.05));
      scene.add(l);
    });
  }

  // ---- Objekte (mit Raster-Kopien) ----
  const up = new THREE.Vector3(0, 1, 0);
  function material(color, opacity, extra) {
    return new THREE.MeshStandardMaterial(Object.assign({
      color, roughness: 0.45, metalness: 0.08, transparent: opacity < 1, opacity,
    }, extra || {}));
  }
  function placeRod(mesh, a, b) {
    const va = new THREE.Vector3(...a), vb = new THREE.Vector3(...b);
    const d = vb.clone().sub(va);
    const len = Math.max(d.length(), 1e-6);
    mesh.position.copy(va.clone().add(vb).multiplyScalar(0.5));
    mesh.scale.set(1, len, 1);
    mesh.quaternion.setFromUnitVectors(up, d.normalize());
  }
  const items = [];
  for (const o of S.objects) {
    for (let i = 0; i < o.n[0]; i++) for (let j = 0; j < o.n[1]; j++) for (let k = 0; k < o.n[2]; k++) {
      const shift = [i * o.d[0], j * o.d[1], k * o.d[2]];
      const mv = v => [v[0] + shift[0], v[1] + shift[1], v[2] + shift[2]];
      const group = new THREE.Group();
      scene.add(group);
      const it = { o, mv, group };
      if (o.shape === 'sphere') {
        it.mesh = new THREE.Mesh(new THREE.SphereGeometry(1, 40, 28), material(P.accent, 1));
        it.mesh.castShadow = true;
        group.add(it.mesh);
        it.label = label('', P.ink, 13);
        group.add(it.label);
      } else if (o.shape === 'line' || o.shape === 'arrow') {
        if (o.dashed) {
          it.line = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3()]),
            new THREE.LineDashedMaterial({ color: P.ink, dashSize: m * 0.03, gapSize: m * 0.025, transparent: true }));
          group.add(it.line);
        } else {
          it.rod = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 1, 16), material(P.ink, 1));
          it.rod.castShadow = true;
          group.add(it.rod);
        }
        if (o.shape === 'arrow') {
          it.head = new THREE.Mesh(new THREE.ConeGeometry(1, 1, 20), material(P.ink, 1));
          it.head.castShadow = true;
          group.add(it.head);
        }
        it.label = label('', P.ink, 13);
        group.add(it.label);
      } else if (o.shape === 'box') {
        it.mesh = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), material(P.warn, 0.28, { depthWrite: false }));
        it.edges = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(1, 1, 1)),
          new THREE.LineBasicMaterial({ color: P.warn, transparent: true }));
        it.mesh.castShadow = true;
        group.add(it.mesh, it.edges);
        it.label = label('', P.warn, 13);
        group.add(it.label);
      } else if (o.shape === 'polygon') {
        it.mesh = new THREE.Mesh(new THREE.BufferGeometry(),
          material(P.accent, 0.35, { side: THREE.DoubleSide, depthWrite: false }));
        it.outline = new THREE.LineLoop(new THREE.BufferGeometry(), new THREE.LineBasicMaterial({ color: P.accent, transparent: true }));
        group.add(it.mesh, it.outline);
        it.label = label('', P.ink, 13);
        group.add(it.label);
      } else if (o.shape === 'text') {
        it.label = label('', P.ink, num(o, 'size', 0) || 14);
        group.add(it.label);
      }
      items.push(it);
    }
  }

  function update(p) {
    for (const it of items) {
      const o = it.o;
      const opacity = Math.max(0, Math.min(1, num(o, 'opacity', p) ?? 1));
      it.group.visible = opacity > 0.001;
      if (!it.group.visible) continue;
      const fill = colorAt(o, 'fill', p), stroke = colorAt(o, 'stroke', p);
      const text = textAt(o, p);
      if (o.shape === 'sphere') {
        const pos = it.mv(vec(o, 'at', p));
        const r = num(o, 'r', p) ?? m * 0.08;
        it.mesh.position.set(...pos);
        it.mesh.scale.setScalar(Math.max(r, 1e-4));
        it.mesh.material.color.set(fill || P.accent);
        it.mesh.material.opacity = opacity;
        it.mesh.material.transparent = opacity < 1;
        it.label.position.set(...pos);
        setLabel(it.label, text, P.ink);
      } else if (o.shape === 'line' || o.shape === 'arrow') {
        const a = it.mv(vec(o, 'from', p)), e0 = it.mv(vec(o, 'to', p));
        const f = Math.max(0, Math.min(1, num(o, 'draw', p) ?? 1));
        let e = [0, 1, 2].map(q => a[q] + (e0[q] - a[q]) * f);
        const color = stroke || fill || P.ink;
        const w = (num(o, 'width', p) ?? 2) * m * 0.0035;
        const dir = new THREE.Vector3(e[0] - a[0], e[1] - a[1], e[2] - a[2]);
        const len = dir.length();
        if (it.head) {
          const hl = Math.min(len * 0.35, Math.max(w * 7, m * 0.05));
          const nd = len > 1e-6 ? dir.clone().normalize() : up.clone();
          const base = [e[0] - nd.x * hl, e[1] - nd.y * hl, e[2] - nd.z * hl];
          it.head.visible = len > 1e-6;
          it.head.position.set(e[0] - nd.x * hl / 2, e[1] - nd.y * hl / 2, e[2] - nd.z * hl / 2);
          it.head.scale.set(Math.max(w * 2.6, m * 0.018), hl, Math.max(w * 2.6, m * 0.018));
          it.head.quaternion.setFromUnitVectors(up, nd);
          it.head.material.color.set(color);
          it.head.material.opacity = opacity;
          it.head.material.transparent = opacity < 1;
          e = base;
        }
        if (it.rod) {
          placeRod(it.rod, a, e);
          it.rod.scale.x = it.rod.scale.z = Math.max(w, m * 0.002);
          it.rod.visible = len > 1e-6;
          it.rod.material.color.set(color);
          it.rod.material.opacity = opacity;
          it.rod.material.transparent = opacity < 1;
        } else {
          it.line.geometry.setFromPoints([new THREE.Vector3(...a), new THREE.Vector3(...e)]);
          it.line.computeLineDistances();
          it.line.material.color.set(color);
          it.line.material.opacity = opacity;
        }
        it.label.position.set((a[0] + e0[0]) / 2, (a[1] + e0[1]) / 2, (a[2] + e0[2]) / 2 + m * 0.04);
        setLabel(it.label, text, color);
      } else if (o.shape === 'box') {
        const o0 = it.mv(vec(o, 'at', p));
        const s = num(o, 'size', p) ?? 1;
        const dims = vec(o, 'dims', p) || [s, s, s];
        const c = [o0[0] + dims[0] / 2, o0[1] + dims[1] / 2, o0[2] + dims[2] / 2];
        for (const mesh of [it.mesh, it.edges]) {
          mesh.position.set(...c);
          mesh.scale.set(Math.max(dims[0], 1e-4), Math.max(dims[1], 1e-4), Math.max(dims[2], 1e-4));
        }
        const f = fill || P.warn;
        it.mesh.material.color.set(f);
        it.mesh.material.opacity = 0.28 * opacity;
        it.edges.material.color.set(stroke || f);
        it.edges.material.opacity = opacity;
        it.label.position.set(o0[0] + dims[0], o0[1] + dims[1], o0[2] + dims[2] + m * 0.04);
        setLabel(it.label, text, f);
      } else if (o.shape === 'polygon') {
        const pts = pointsAt(o, p).map(it.mv);
        if (pts.length >= 3) {
          const pos = [];
          for (let q = 1; q < pts.length - 1; q++) pos.push(...pts[0], ...pts[q], ...pts[q + 1]);
          it.mesh.geometry.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
          it.mesh.geometry.computeVertexNormals();
          it.outline.geometry.setFromPoints(pts.map(v => new THREE.Vector3(...v)));
          const f = fill || P.accent;
          it.mesh.material.color.set(f);
          it.mesh.material.opacity = 0.35 * opacity;
          it.outline.material.color.set(stroke || f);
          it.outline.material.opacity = opacity;
          const c = [0, 1, 2].map(q => pts.reduce((s, v) => s + v[q], 0) / pts.length);
          it.label.position.set(...c);
        }
        setLabel(it.label, text, P.ink);
      } else if (o.shape === 'text') {
        it.label.position.set(...it.mv(vec(o, 'at', p)));
        it.label.element.style.fontSize = (num(o, 'size', p) || 14) + 'px';
        setLabel(it.label, text, fill || P.ink);
      }
    }
    let caption = '';
    for (const c of [...S.captions].sort((a, b) => a.at - b.at)) if (c.at <= p) caption = c.text;
    document.getElementById('caption').textContent = plain(caption);
    const par = document.getElementById('param');
    if (S.param) {
      const v = S.param.from + (S.param.to - S.param.from) * p;
      const a = Math.abs(v);
      let t = v.toFixed(a >= 100 ? 0 : a >= 10 ? 1 : 2);
      if (t.includes('.')) t = t.replace(/0+$/, '').replace(/\.$/, '');
      par.textContent = S.param.name + ' = ' + t.replace('.', ',') + (S.param.unit ? ' ' + S.param.unit : '');
    } else {
      par.textContent = Math.round(p * 100) + ' %';
    }
  }

  // ---- Abspielen ----
  const slider = document.getElementById('time');
  const playBtn = document.getElementById('play');
  let p = 0, playing = true, last = performance.now();
  playBtn.onclick = () => {
    if (!playing && p >= 1) p = 0;
    playing = !playing;
    playBtn.textContent = playing ? 'Pause' : 'Abspielen';
  };
  slider.oninput = () => {
    playing = false;
    playBtn.textContent = 'Abspielen';
    p = slider.value / 1000;
  };
  document.getElementById('reset').onclick = () => {
    camera.position.copy(home);
    controls.target.copy(center);
    controls.update();
  };

  function resize() {
    const w = view.clientWidth, h = view.clientHeight;
    renderer.setSize(w, h);
    labels.setSize(w, h);
    camera.aspect = w / Math.max(h, 1);
    camera.updateProjectionMatrix();
  }
  window.addEventListener('resize', resize);
  resize();

  function frame(now) {
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    if (playing) {
      p = Math.min(1, p + dt / S.seconds);
      if (p >= 1) {
        playing = false;
        playBtn.textContent = 'Abspielen';
      }
      slider.value = Math.round(p * 1000);
    }
    controls.autoRotate = S.spin && playing;
    // Halbe Umdrehung je Durchlauf wie in der App (Tempo 1 = eine Umdrehung in 60 s).
    controls.autoRotateSpeed = 30 / S.seconds;
    controls.update();
    update(p);
    renderer.render(scene, camera);
    labels.render(scene, camera);
    requestAnimationFrame(frame);
  }
  window.lernen3dReady = true;
  requestAnimationFrame(frame);
})();
</script>
</body>
</html>
''';
