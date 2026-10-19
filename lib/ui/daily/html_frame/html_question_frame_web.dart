import 'dart:js_interop';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../../services/html_question_bridge.dart';

/// Im Browser läuft die interaktive Seite in einem iframe statt einer WebView.
const bool htmlQuestionFrameSupported = true;

/// Interaktive HTML-Frage im Browser: abgeschottetes iframe
/// (`sandbox="allow-scripts"` ohne `allow-same-origin` – die Seite kommt an
/// nichts von der App heran, Netzwerk sperrt zusätzlich die CSP aus
/// wrapHtmlQuestionPage). Antworten kommen über die Brücke
/// (html_question_bridge.dart) per postMessage zurück.
class HtmlQuestionFrame extends StatefulWidget {
  const HtmlQuestionFrame({super.key, required this.page, required this.onMessage, this.onLoaded});

  /// Fertiges Dokument (wrapHtmlQuestionPage).
  final String page;
  final void Function(String message) onMessage;
  final VoidCallback? onLoaded;

  @override
  State<HtmlQuestionFrame> createState() => _HtmlQuestionFrameState();
}

class _HtmlQuestionFrameState extends State<HtmlQuestionFrame> {
  final String _token = List.generate(4, (_) => Random.secure().nextInt(0x7fffffff).toRadixString(36)).join();
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener = ((web.MessageEvent e) {
    final frame = _frame;
    if (frame == null || !mounted) return;
    if (!e.source.strictEquals(frame.contentWindow).toDart) return;
    final message = htmlQuestionBridgeMessage(e.data.dartify(), _token);
    if (message != null) widget.onMessage(message);
  }).toJS;

  @override
  void initState() {
    super.initState();
    web.window.addEventListener('message', _listener);
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        frame.sandbox.add('allow-scripts');
        frame.style
          ..border = '0'
          ..width = '100%'
          ..height = '100%'
          ..backgroundColor = '#ffffff';
        frame.addEventListener('load', ((web.Event _) => widget.onLoaded?.call()).toJS);
        frame.srcdoc = withHtmlQuestionBridge(widget.page, _token).toJS;
        _frame = frame;
      },
    );
  }
}
