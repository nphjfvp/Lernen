import 'html_question_contract.dart';

/// Im Browser gibt es keine WebView mit JavaScript-Kanal: die Seite läuft dort
/// in einem abgeschotteten iframe (`sandbox="allow-scripts"`, eigener
/// Ursprung). Dieses Skript stellt ihr denselben `window.FlutterAnswer`-
/// Aufruf bereit und leitet ihn per `postMessage` an die App weiter; [token]
/// unterscheidet die Nachrichten dieser Seite von allen anderen.
String htmlQuestionBridgeScript(String token) =>
    '<script>window.$htmlAnswerChannelName={postMessage:function(m){try{parent.postMessage('
    '{lernenHtmlAnswer:${_jsString(token)},message:String(m)},"*")}catch(e){}}};</script>';

/// [page] (fertiges Dokument aus [wrapHtmlQuestionPage]) mit der Brücke
/// als erstem Skript im `<head>` – vor jedem Code der KI.
String withHtmlQuestionBridge(String page, String token) {
  final script = htmlQuestionBridgeScript(token);
  final head = RegExp('<head[^>]*>', caseSensitive: false).firstMatch(page);
  if (head == null) return '$script$page';
  return page.replaceRange(head.end, head.end, '\n$script');
}

/// Liest die Antwort einer Brücken-Nachricht: der Text aus
/// `FlutterAnswer.postMessage(...)`, oder null, wenn sie nicht von der Seite
/// mit [token] stammt.
String? htmlQuestionBridgeMessage(Object? data, String token) {
  if (data is! Map) return null;
  if (data['lernenHtmlAnswer'] != token) return null;
  final message = data['message'];
  return message is String ? message : null;
}

String _jsString(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('<', r'\u003c')}"';
