import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/visual_scene3d.dart';
import '../../models/visual_scene3d_blocks.dart';
import '../../services/ai_service.dart';
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
    this.extendAi,
    this.onSceneChanged,
    this.extendContext = '',
  });

  final VisualScene3D scene;
  final bool autoplay;
  final double height;
  final String title;

  /// KI für „Simulation erweitern“ – null = ohne Erweitern.
  final AiService? Function()? extendAi;

  /// Die erweiterte Szene speichern (z.B. im Schritt der Lektion); ohne gilt
  /// sie nur, solange die Ansicht offen ist.
  final void Function(VisualScene3D scene)? onSceneChanged;

  /// Worum es geht (Titel und Text des Schritts) – hilft der KI.
  final String extendContext;

  @override
  State<Scene3DLiveView> createState() => _Scene3DLiveViewState();
}

class _Scene3DLiveViewState extends State<Scene3DLiveView> {
  bool _on = false;
  Scene3DLiveState? _state;

  /// Erweiterte Szene, solange der Aufrufer sie nicht übernommen hat.
  VisualScene3D? _override;

  /// Vorige Szenen fürs Rückgängig.
  final List<VisualScene3D> _history = [];

  // Ablauf
  double _p = 0;
  bool _playing = false;
  Timer? _timer;

  // Erweitern
  final _wish = TextEditingController();
  bool _busy = false;
  String? _error;
  String _say = '';
  String _note = '';

  VisualScene3D get _scene => _override ?? widget.scene;
  Map<String, dynamic>? get _block => Scene3DLive.blockOf(_scene);

  @override
  void didUpdateWidget(covariant Scene3DLiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scene, widget.scene)) {
      // Der Aufrufer hat die (erweiterte) Szene übernommen – oder es ist ein
      // anderer Schritt.
      final adopted = _override != null && widget.onSceneChanged != null;
      _override = null;
      if (adopted) return;
      _on = false;
      _state = null;
      _history.clear();
      _say = '';
      _note = '';
      _stop();
      _p = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wish.dispose();
    super.dispose();
  }

  void _set(Scene3DLiveState state) => setState(() {
    _stop();
    _state = state;
  });

  List<({double at, Scene3DLiveState state, String caption})> _timeline() {
    final block = _block;
    if (block == null) return const [];
    return Scene3DLive.timelineOf(block, Scene3DLive.initial(block));
  }

  void _play() {
    final timeline = _timeline();
    if (timeline.isEmpty) return;
    _timer?.cancel();
    if (_p >= 1) _p = 0;
    final seconds = (_scene.seconds <= 0 ? 8.0 : _scene.seconds).clamp(4.0, 20.0);
    setState(() {
      _playing = true;
      _on = true;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {
        _p = (_p + 0.05 / seconds).clamp(0.0, 1.0);
        _state = Scene3DLive.stateAt(timeline, _p).state;
        if (_p >= 1) _stop();
      });
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _playing = false;
  }

  void _seek(double p) {
    final timeline = _timeline();
    setState(() {
      _stop();
      _p = p;
      _on = true;
      _state = Scene3DLive.stateAt(timeline, p).state;
    });
  }

  Future<void> _extend([String? preset]) async {
    final wish = (preset ?? _wish.text).trim();
    final ai = widget.extendAi?.call();
    if (wish.isEmpty || _busy) return;
    if (ai == null) {
      setState(() => _error = 'Zum Erweitern braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ai.extendScene3d(scene: _scene.toMap(), wish: wish, context: widget.extendContext);
      final raw = Map<String, dynamic>.from(result.scene);
      // Den Ablauf an den Körper-Baustein hängen – die App rechnet ihn.
      if (result.timeline != null && raw['objects'] is List) {
        var attached = false;
        raw['objects'] = [
          for (final o in raw['objects'] as List)
            if (!attached && o is Map && Scene3DBlocks.isBody(o) && (attached = true))
              {...Map<String, dynamic>.from(o), 'timeline': result.timeline}
            else
              o,
        ];
      }
      final extended = VisualScene3D.fromMap(raw);
      if (extended == null) throw AiServiceException('Die erweiterte Szene ließ sich nicht lesen.');
      if (!mounted) return;
      setState(() {
        _history.add(_scene);
        _override = extended;
        _say = result.say;
        _note = result.note;
        _wish.clear();
        _stop();
        _p = 0;
        _state = null;
        _on = false;
      });
      widget.onSceneChanged?.call(extended);
      if (Scene3DLive.blockOf(extended) != null && _timeline().isNotEmpty) _play();
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erweitern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _undo() {
    if (_history.isEmpty) return;
    final previous = _history.removeLast();
    setState(() {
      _override = previous;
      _say = '';
      _note = '';
      _stop();
      _p = 0;
      _state = null;
      _on = false;
    });
    widget.onSceneChanged?.call(previous);
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    final block = _block;
    // Derselbe Zustand der Ansicht (Drehung), auch wenn sich die Kräfte ändern.
    Widget canvas(VisualScene3D scene) => VisualScene3DView(
      key: const ValueKey('scene3d-live-canvas'),
      scene: scene,
      autoplay: widget.autoplay,
      height: widget.height,
      title: widget.title,
    );
    final c = context.colors;
    if (block == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [canvas(scene), if (widget.extendAi != null) ..._extendPanel(c, null)],
      );
    }
    final kind = Scene3DLive.kindOf(block)!;
    final state = _state ?? Scene3DLive.initial(block);
    final live = _on ? Scene3DLive.apply(scene, state) : null;
    final timeline = Scene3DLive.timelineOf(block, Scene3DLive.initial(block));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        canvas(live?.scene ?? scene),
        if (timeline.isNotEmpty) ...[const SizedBox(height: 8), _timelinePanel(c, timeline)],
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
                    onChanged: (v) => setState(() {
                      _stop();
                      _on = v;
                    }),
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
        if (widget.extendAi != null) ..._extendPanel(c, kind),
      ],
    );
  }

  /// Ablauf abspielen bzw. an eine Stelle springen – die Kräfte rechnet die
  /// App für jeden Moment neu.
  Widget _timelinePanel(AppColors c, List<({double at, Scene3DLiveState state, String caption})> timeline) {
    final caption = Scene3DLive.stateAt(timeline, _p).caption;
    return Container(
      key: const ValueKey('scene3d-timeline'),
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
      decoration: BoxDecoration(color: c.accentSoft.withAlpha(120), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('scene3d-timeline-play'),
                tooltip: _playing ? 'Anhalten' : 'Ablauf abspielen',
                onPressed: _playing ? () => setState(_stop) : _play,
                icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle, color: c.accent, size: 30),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('scene3d-timeline-slider'),
                  value: _p,
                  activeColor: c.accent,
                  onChanged: _seek,
                ),
              ),
            ],
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                caption,
                key: const ValueKey('scene3d-timeline-caption'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }

  /// „Simulation erweitern“: Wunsch eingeben, die KI baut die Szene aus.
  List<Widget> _extendPanel(AppColors c, String? kind) {
    final suggestions = switch (kind) {
      'car' => [
        'Lass das Auto mit dem Rad vorn links durch ein Schlagloch fahren und zeig weiter alle Kraftpfeile',
        'Fahr langsam einen Hang hinauf und wieder hinunter',
        'Beladung nach hinten verschieben',
      ],
      'block' => [
        'Stell die Ebene langsam steiler, bis der Klotz rutscht',
        'Zeig die Kräfte zerlegt in Hangabtrieb und Normalkraft',
      ],
      'beam' => ['Lass die Kraft von links nach rechts über den Balken wandern'],
      _ => [
        'Färbe alle Teile, die in der Zelle liegen, ein und setz sie zu ganzen Atomen zusammen',
        'Zeig es in Zeitlupe mit Beschriftungen',
        'Zoom auf das Wichtigste und erklär es Schritt für Schritt',
      ],
    };
    return [
      const SizedBox(height: 8),
      Container(
        key: const ValueKey('scene3d-extend'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: c.accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Simulation erweitern', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                if (_history.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('scene3d-extend-undo'),
                    onPressed: _busy ? null : _undo,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Rückgängig'),
                  ),
              ],
            ),
            if (_say.isNotEmpty || _note.isNotEmpty)
              Container(
                key: const ValueKey('scene3d-extend-say'),
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.goodSoft, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  [_say, if (_note.isNotEmpty) 'Hinweis: $_note'].where((t) => t.isNotEmpty).join('\n'),
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, s) in suggestions.indexed)
                  ActionChip(
                    key: ValueKey('scene3d-extend-suggest-$i'),
                    label: Text(s, maxLines: 2),
                    onPressed: _busy ? null : () => _extend(s),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('scene3d-extend-input'),
                    controller: _wish,
                    enabled: !_busy,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _extend(),
                    decoration: const InputDecoration(
                      hintText: 'z.B. „lass es durch ein Schlagloch fahren und zeig alle Kraftpfeile“',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey('scene3d-extend-go'),
                  tooltip: 'Erweitern',
                  onPressed: _busy ? null : () => _extend(),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  key: const ValueKey('scene3d-extend-error'),
                  style: TextStyle(color: c.danger),
                ),
              ),
            if (kind != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Bei Auto, Klotz und Balken rechnet die App die Kräfte des Ablaufs selbst nach.',
                  style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                ),
              ),
          ],
        ),
      ),
    ];
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
