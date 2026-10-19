import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Im Browser: die Seite in einem abgeschotteten iframe (nur Skripte, kein
/// Zugriff auf die App).
Widget htmlPageView(String html) => HtmlElementView.fromTagName(
  tagName: 'iframe',
  onElementCreated: (element) {
    final frame = element as web.HTMLIFrameElement;
    frame.sandbox.add('allow-scripts');
    frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%';
    frame.srcdoc = html.toJS;
  },
);

/// Im Browser gibt es kein „außerhalb öffnen“ – angezeigt wird in der App.
Future<bool> openHtmlExternally(String html, String name) async => false;
