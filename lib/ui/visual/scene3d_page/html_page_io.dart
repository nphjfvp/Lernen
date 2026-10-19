import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Android/iOS: in einer WebView (WebGL läuft dort).
Widget htmlPageView(String html) => _WebViewPage(html: html);

class _WebViewPage extends StatefulWidget {
  const _WebViewPage({required this.html});
  final String html;

  @override
  State<_WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<_WebViewPage> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    // Nur die eigene Seite – Links o.ä. öffnen nichts.
    ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (r) => NavigationDecision.prevent))
    ..loadHtmlString(widget.html);

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

/// Windows/macOS/Linux (keine WebView): als Datei im Standardbrowser öffnen.
Future<bool> openHtmlExternally(String html, String name) async {
  try {
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}lernen-3d');
    await dir.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9äöüÄÖÜß_-]+'), '-');
    final file = File('${dir.path}${Platform.pathSeparator}${safe.isEmpty ? 'szene' : safe}.html');
    await file.writeAsString(html);
    return await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
