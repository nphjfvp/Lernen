import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_scene3d.dart';
import 'package:lernen/services/scene3d_html.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/visual_diagram_view.dart' show diagramColor;

import 'visual_scene3d_test.dart' show fccScene;

ThreeJsSources _libs() => ThreeJsSources(
  three: File('assets/three/three.min.js').readAsStringSync(),
  orbitControls: File('assets/three/OrbitControls.js').readAsStringSync(),
  css2d: File('assets/three/CSS2DRenderer.js').readAsStringSync(),
);

String _build(VisualScene3D scene, {String title = 'kfz-Gitter'}) => Scene3DHtml.build(
  scene: scene,
  title: title,
  palette: const Scene3DPalette(
    bg: Color(0xFFFAFAF7),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF2A2E3D),
    muted: Color(0xFF6B7280),
    accent: Color(0xFF6B74C4),
    warn: Color(0xFF876433),
  ),
  libs: _libs(),
  resolveColor: (name) => diagramColor(name, AppColors.light),
);

Map<String, dynamic> _sceneJson(String html) {
  final m = RegExp(r'const S = (\{.*?\});\n', dotAll: true).firstMatch(html)!;
  return jsonDecode(m.group(1)!) as Map<String, dynamic>;
}

void main() {
  test('Eigenständige Seite: Bibliotheken eingebettet, Farben aufgelöst, Szene vollständig', () {
    final html = _build(VisualScene3D.fromMap(fccScene())!);
    expect(html, contains('THREE.OrbitControls = OrbitControls'));
    expect(html, contains('THREE.CSS2DRenderer = CSS2DRenderer'));
    expect(html, isNot(contains('/*__')), reason: 'alle Platzhalter ersetzt');
    expect(html, isNot(contains('__BG__')));
    expect(html, contains('<title>kfz-Gitter – 3D</title>'));
    final s = _sceneJson(html);
    expect(s['param']['name'], 'Packungsdichte');
    expect(s['palette']['accent'], '#6b74c4');
    final objects = (s['objects'] as List).cast<Map>();
    expect(objects.first['n'], [2, 2, 2]);
    expect(objects.first['fill'], '#6b74c4', reason: '„accent“ als Hex');
    expect(objects[1]['fill'], '#876433', reason: '„orange“ = warn');
    expect(objects.first['keys'].first['t'], 1);
    expect(objects.firstWhere((o) => o['shape'] == 'line')['dashed'], isTrue);
    // Optional zum Ansehen im Browser: LERNEN_3D_OUT=/pfad/datei.html flutter test …
    final out = Platform.environment['LERNEN_3D_OUT'];
    if (out != null) File(out).writeAsStringSync(html);
  });

  test('Titel und Texte können die Seite nicht aufbrechen', () {
    final scene = VisualScene3D.fromMap({
      'objects': [
        {
          'type': 'text',
          'at': [0.5, 0.5, 0.5],
          'text': '</script><script>alert(1)</script>',
        },
      ],
    })!;
    final html = _build(scene, title: '<b>"Titel"</b>');
    expect(html, contains('<title>&lt;b&gt;&quot;Titel&quot;&lt;/b&gt; – 3D</title>'));
    expect('</script>'.allMatches(html).length, 4, reason: 'nur die vier eigenen Skript-Enden');
    expect(_sceneJson(html)['objects'].first['text'], '</script><script>alert(1)</script>');
  });

  test('Formeln werden lesbarer Text (die 3D-Ansicht setzt kein LaTeX)', () {
    expect(plainMath(r'Berühren sich: $r = a\sqrt{2}/4$'), 'Berühren sich: r = a√2/4');
    expect(plainMath(r'$\frac{a}{2}$ und $x^2 + y_0$'), 'a/2 und x² + y₀');
    expect(plainMath(r'$\Delta T = 20\,\text{K}$'), 'ΔT = 20 K');
    expect(plainMath(r'$\sqrt{\frac{3}{4}} \cdot a$'), '√(3/4) · a');
    expect(plainMath(r'$e^{-kt}$'), 'e^-kt', reason: 'ohne passende Hochzeichen bleibt ^');
    expect(plainMath(r'Packungsdichte $\approx 74\,\%$'), 'Packungsdichte ≈ 74 %');
    expect(plainMath('ohne Formel'), 'ohne Formel');
  });
}
