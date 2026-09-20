/// Name des JavaScript-Kanals, über den eine interaktive HTML-Frage (siehe
/// [QuestionType.html]) ihr Ergebnis an die App zurückmeldet. Die von der KI
/// generierte Seite ruft beim Auswerten
/// `window.FlutterAnswer.postMessage(JSON.stringify({correct: true}))` auf –
/// dieselbe Zeichenkette dient [QuestionParsing] als grobe Vertragsprüfung
/// (ohne den Aufruf im generierten Code wäre die Karte technisch nutzlos, da
/// die App nie ein Ergebnis bekäme).
const htmlAnswerChannelName = 'FlutterAnswer';

/// Rahmt den von der KI gelieferten HTML/CSS/JS-Fragment-Inhalt (nur der
/// `<body>`-Inhalt, siehe AiService-Prompts) in ein vollständiges, per
/// Content-Security-Policy abgeriegeltes Dokument: kein Netzwerkzugriff
/// (`default-src 'none'`), keine externen Bilder/Schriften/Skripte – nur
/// Inline-Styles/-Skripte und Daten-URIs. Wichtig, weil hier KI-generiertes
/// (potenziell von einem schwachen oder manipulierten Modell stammendes)
/// JavaScript in einer echten WebView ausgeführt wird: die Sandbox verhindert
/// Exfiltration/Tracking, selbst wenn der generierte Code das versuchen
/// würde. Reine String-Funktion (kein Flutter-Import), daher auch ohne
/// WebView-Widget testbar.
String wrapHtmlQuestionPage(String bodyFragment) => '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src data:;">
<style>
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    margin: 0;
    padding: 16px;
    color: #1a1a1a;
    background: #ffffff;
    font-size: 15px;
    line-height: 1.5;
  }
  table { border-collapse: collapse; width: 100%; }
  td, th { border: 1px solid #d0d0d0; padding: 6px 8px; text-align: left; }
  button {
    font: inherit;
    padding: 8px 14px;
    border-radius: 10px;
    border: 1px solid #c9c9c9;
    background: #f4f4f4;
    cursor: pointer;
  }
  button:active { opacity: 0.7; }
</style>
</head>
<body>
$bodyFragment
</body>
</html>
''';
