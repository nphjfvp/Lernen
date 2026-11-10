import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_scene3d.dart';
import 'package:lernen/services/scene3d_html.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/tasks/crystal_cube.dart';
import 'package:lernen/ui/visual/visual_diagram_view.dart' show diagramColor;
import 'package:lernen/ui/visual/visual_scene3d_view.dart';

import '../fixtures/achse_scene.dart';

void main() {
  test('Zylinder: from/to/r, Kegelstumpf, übliche Schreibweisen der KI', () {
    final c = Scene3DObject.fromMap({
      'type': 'cylinder',
      'from': [0, 0, 0],
      'to': [10, 0, 0],
      'r': 3,
      'r2': 2,
      'fill': 'gray',
      'text': 'd = 6',
    })!;
    expect(c.shape, Scene3DShape.cylinder);
    expect(c.number('r', 0), 3);
    expect(c.number('r2', 0), 2);
    expect(Scene3DObject.fromMap(c.toMap())!.toMap(), c.toMap());

    // Durchmesser statt Radius, deutsches Wort.
    final welle = Scene3DObject.fromMap({
      'type': 'Welle',
      'from': [0, 0, 0],
      'to': [1, 0, 0],
      'd': 60,
    })!;
    expect(welle.shape, Scene3DShape.cylinder);
    expect(welle.number('r', 0), 30);
    // Kegel läuft spitz zu; Lage über at + axis + height.
    final kegel = Scene3DObject.fromMap({
      'type': 'cone',
      'at': [1, 1, 0],
      'axis': [0, 0, 2],
      'height': 5,
      'radius': 2,
    })!;
    expect(kegel.number('r2', 0), 0);
    expect(kegel.vector('from', 0), [1, 1, 0]);
    expect(kegel.vector('to', 0), [1, 1, 5]);
    // Ohne Lage unbrauchbar; das Raster-"d" eines repeat ist kein Durchmesser.
    expect(Scene3DObject.fromMap({'type': 'cylinder', 'r': 1}), isNull);
    final kugel = Scene3DObject.fromMap({
      'type': 'sphere',
      'at': [0, 0, 0],
      'd': [1, 1, 1],
    })!;
    expect(kugel.numbers.containsKey('r'), isFalse);
  });

  test('Achse mit Absatz: Szene wird gelesen, gezeichnet und für three.js übergeben', () {
    final raw = achseScene();
    final scene = VisualScene3D.fromMap(raw)!;
    expect(scene.objects, hasLength((raw['objects'] as List).length));
    expect(scene.objects.where((o) => o.shape == Scene3DShape.cylinder), hasLength(8));

    // Zeichnen ohne Fehler – auch mit durchscheinenden und animierten Zylindern.
    for (final progress in [0.0, 0.7, 1.0]) {
      final recorder = ui.PictureRecorder();
      Scene3DPainter(
        scene: scene,
        progress: progress,
        theta: -60,
        phi: 20,
        colors: AppColors.light,
      ).paint(Canvas(recorder), const Size(600, 400));
      recorder.endRecording();
    }

    const c = AppColors.light;
    final html = Scene3DHtml.build(
      scene: scene,
      title: 'Achse',
      palette: Scene3DPalette(
        bg: c.bg,
        surface: c.surface,
        ink: c.ink,
        muted: c.inkMuted,
        accent: c.accent,
        warn: c.warn,
      ),
      libs: const ThreeJsSources(three: '', orbitControls: '', css2d: ''),
      resolveColor: (name) => diagramColor(name, c),
    );
    expect(html, contains('"shape":"cylinder"'));
    expect(html, contains("o.shape === 'cylinder'"));
  });

  test('Vergrößerung der Projektion: Standard 1, größer rückt näher', () {
    const size = Size(400, 400);
    final base = CubeProjection(theta: 30, phi: 20, size: size);
    final zoomed = CubeProjection(theta: 30, phi: 20, size: size, zoom: 2);
    final a = base.project([1, 1, 1]) - base.project([0, 0, 0]);
    final b = zoomed.project([1, 1, 1]) - zoomed.project([0, 0, 0]);
    expect(b.distance, closeTo(a.distance * 2, 1e-6));
    expect(base.project([.5, .5, .5]), zoomed.project([.5, .5, .5]), reason: 'um die Mitte');
  });
}
