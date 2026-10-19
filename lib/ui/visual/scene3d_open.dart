import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../models/visual_scene3d.dart';
import '../../services/scene3d_html.dart';
import '../../theme/app_colors.dart';
import 'scene3d_page/html_page_io.dart' if (dart.library.js_interop) 'scene3d_page/html_page_web.dart';
import 'visual_diagram_view.dart' show diagramColor;

/// „In 3D ansehen“: die Szene als echte 3D-Seite (three.js, siehe
/// [Scene3DHtml]) – Android/iOS und Browser in der App, Windows im
/// Standardbrowser (dort gibt es keine WebView).
class Scene3DOpener {
  Scene3DOpener._();

  static ThreeJsSources? _libs;

  static Future<ThreeJsSources> _loadLibs() async => _libs ??= ThreeJsSources(
    three: await rootBundle.loadString('assets/three/three.min.js'),
    orbitControls: await rootBundle.loadString('assets/three/OrbitControls.js'),
    css2d: await rootBundle.loadString('assets/three/CSS2DRenderer.js'),
  );

  /// Mit WebView bzw. iframe in der App; sonst im Browser.
  static bool get showsInApp =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> open(BuildContext context, VisualScene3D scene, {required String title}) async {
    final c = context.colors;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final html = Scene3DHtml.build(
      scene: scene,
      title: title,
      palette: Scene3DPalette(
        bg: c.bg,
        surface: c.surface,
        ink: c.ink,
        muted: c.inkMuted,
        accent: c.accent,
        warn: c.warn,
      ),
      libs: await _loadLibs(),
      resolveColor: (name) => diagramColor(name, c),
    );
    if (showsInApp) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => _Scene3DPage(title: title, html: html),
        ),
      );
      return;
    }
    if (!await openHtmlExternally(html, title)) {
      messenger?.showSnackBar(const SnackBar(content: Text('Die 3D-Ansicht ließ sich nicht im Browser öffnen.')));
    }
  }
}

class _Scene3DPage extends StatelessWidget {
  const _Scene3DPage({required this.title, required this.html});

  final String title;
  final String html;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(plainMath(title), overflow: TextOverflow.ellipsis)),
    body: SafeArea(child: htmlPageView(html)),
  );
}
