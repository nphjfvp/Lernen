import 'package:flutter/material.dart';

import '../../models/visual_lesson.dart';
import '../../services/visual_math.dart';
import 'visual_diagram_view.dart';
import 'visual_scene.dart';
import 'visual_scene3d_view.dart';

/// Alles, was eine [VisualShow] zeigt, untereinander: Umformung, 2D-Szene,
/// 3D-Szene und Fahrzeug/Graph (mit [math] gerechnet).
class VisualShowView extends StatelessWidget {
  const VisualShowView({super.key, required this.math, required this.show});

  final VisualMath math;
  final VisualShow show;

  static bool hasContent(VisualShow show) =>
      show.transform.isNotEmpty || show.scene != null || show.scene3d != null || VisualSceneView.hasScene(show);

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[
      if (show.transform.isNotEmpty) EquationTransformView(states: show.transform, autoplay: true),
      if (show.scene != null) VisualDiagramView(diagram: show.scene!),
      if (show.scene3d != null) VisualScene3DView(scene: show.scene3d!),
      if (VisualSceneView.hasScene(show)) VisualSceneView(math: math, show: show),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, p) in parts.indexed) ...[if (i > 0) const SizedBox(height: 10), p],
      ],
    );
  }
}
