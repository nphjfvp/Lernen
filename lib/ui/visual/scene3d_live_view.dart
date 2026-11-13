import 'package:flutter/material.dart';

import '../../models/visual_scene3d.dart';
import '../../models/visual_scene3d_blocks.dart';
import '../../services/scene3d_live.dart';
import '../../theme/app_colors.dart';
import 'visual_scene3d_view.dart';

/// Räumliche Szene – mit „Ausprobieren“, wenn sie einen Körper-Baustein
/// enthält, an dem die App selbst rechnen kann (siehe [Scene3DLive]): Rad
/// anheben, Schwerpunkt verschieben, Unterlage neigen, Kraft verschieben. Die
/// Pfeile und Werte ändern sich sofort. Ohne solchen Baustein (oder solange
/// man es nicht einschaltet) ist es genau die gewohnte Ansicht.
class Scene3DLiveView extends StatefulWidget {
  const Scene3DLiveView({
    super.key,
    required this.scene,
    this.autoplay = true,
    this.height = 340,
    this.title = '3D-Szene',
  });

  final VisualScene3D scene;
  final bool autoplay;
  final double height;
  final String title;

  @override
  State<Scene3DLiveView> createState() => _Scene3DLiveViewState();
}

class _Scene3DLiveViewState extends State<Scene3DLiveView> {
  bool _on = false;
  Scene3DLiveState? _state;

  Map<String, dynamic>? get _block => Scene3DLive.blockOf(widget.scene);

  @override
  void didUpdateWidget(covariant Scene3DLiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scene, widget.scene)) {
      _on = false;
      _state = null;
    }
  }

  void _set(Scene3DLiveState state) => setState(() => _state = state);

  @override
  Widget build(BuildContext context) {
    final block = _block;
    // Derselbe Zustand der Ansicht (Drehung), auch wenn sich die Kräfte ändern.
    Widget canvas(VisualScene3D scene) => VisualScene3DView(
      key: const ValueKey('scene3d-live-canvas'),
      scene: scene,
      autoplay: widget.autoplay,
      height: widget.height,
      title: widget.title,
    );
    if (block == null) return canvas(widget.scene);
    final c = context.colors;
    final kind = Scene3DLive.kindOf(block)!;
    final state = _state ?? Scene3DLive.initial(block);
    final live = _on ? Scene3DLive.apply(widget.scene, state) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        canvas(live?.scene ?? widget.scene),
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('scene3d-live'),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.touch_app_outlined, size: 18, color: c.accent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Ausprobieren', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
                  if (_on)
                    TextButton(
                      key: const ValueKey('scene3d-live-reset'),
                      onPressed: () => _set(Scene3DLive.initial(block)),
                      child: const Text('Zurücksetzen'),
                    ),
                  Switch(
                    key: const ValueKey('scene3d-live-toggle'),
                    value: _on,
                    activeThumbColor: c.accent,
                    onChanged: (v) => setState(() => _on = v),
                  ),
                ],
              ),
              if (!_on)
                Text(switch (kind) {
                  'car' => 'Heb ein Rad an, verschieb den Schwerpunkt oder stell das Auto an den Hang – die App rechnet die Radlasten neu.',
                  'block' =>
                    'Neig die Ebene und ändere die Reibung – die App rechnet, ob der Klotz haftet oder rutscht.',
                  _ => 'Verschieb die Kraft – die App rechnet die Lagerkräfte neu.',
                }, style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35))
              else ...[
                ..._controls(c, kind, block, state),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (live?.warn ?? false) ? c.warnSoft : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    live?.status ?? 'Das lässt sich hier nicht rechnen.',
                    key: const ValueKey('scene3d-live-status'),
                    style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Von der App gerechnet (Statik, starrer Körper) – nicht von der KI.',
                  style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _slider(
    AppColors c, {
    required String keyName,
    required String label,
    required String value,
    required double current,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          Text(
            value,
            key: ValueKey('$keyName-value'),
            style: TextStyle(fontSize: 12.5, color: c.inkMuted),
          ),
        ],
      ),
      Slider(
        key: ValueKey(keyName),
        value: current.clamp(min, max),
        min: min,
        max: max,
        activeColor: c.accent,
        onChanged: onChanged,
      ),
    ],
  );

  List<Widget> _controls(AppColors c, String kind, Map<String, dynamic> block, Scene3DLiveState state) {
    switch (kind) {
      case 'car':
        return [
          const SizedBox(height: 4),
          const Text('Rad anheben', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final e in Scene3DLive.wheelNames.entries)
                FilterChip(
                  key: ValueKey('scene3d-live-wheel-${e.key}'),
                  label: Text(e.value),
                  selected: state.lifted.contains(e.key),
                  onSelected: (v) =>
                      _set(state.copyWith(lifted: v ? {...state.lifted, e.key} : ({...state.lifted}..remove(e.key)))),
                ),
            ],
          ),
          _slider(
            c,
            keyName: 'scene3d-live-cg',
            label: 'Schwerpunkt',
            value: state.cg < 0.45
                ? 'weiter hinten'
                : state.cg > 0.55
                ? 'weiter vorn'
                : 'mittig',
            current: state.cg,
            min: 0.05,
            max: 0.95,
            onChanged: (v) => _set(state.copyWith(cg: v)),
          ),
          _slider(
            c,
            keyName: 'scene3d-live-slope',
            label: 'Neigung der Fahrbahn',
            value: '${Scene3DBlocks.fmt(state.slope.roundToDouble())}°',
            current: state.slope,
            min: -30,
            max: 30,
            onChanged: (v) => _set(state.copyWith(slope: v.roundToDouble())),
          ),
        ];
      case 'block':
        return [
          _slider(
            c,
            keyName: 'scene3d-live-slope',
            label: 'Neigung der Ebene',
            value: '${Scene3DBlocks.fmt(state.slope.roundToDouble())}°',
            current: state.slope,
            min: 0,
            max: 60,
            onChanged: (v) => _set(state.copyWith(slope: v.roundToDouble())),
          ),
          _slider(
            c,
            keyName: 'scene3d-live-mu',
            label: 'Haftreibungszahl μ',
            value: Scene3DBlocks.fmt((state.mu * 20).round() / 20),
            current: state.mu,
            min: 0,
            max: 1.5,
            onChanged: (v) => _set(state.copyWith(mu: (v * 20).round() / 20)),
          ),
        ];
      default:
        final length = Scene3DBlocks.beamGeometry(block)!.l;
        return [
          _slider(
            c,
            keyName: 'scene3d-live-force',
            label: 'Lage der Kraft',
            value: '${Scene3DBlocks.fmt(state.forceAt)} vom linken Ende',
            current: state.forceAt,
            min: 0,
            max: length,
            onChanged: (v) => _set(state.copyWith(forceAt: (v / length * 100).round() / 100 * length)),
          ),
        ];
    }
  }
}
