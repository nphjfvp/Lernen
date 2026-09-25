import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/app_settings.dart';
import '../models/flashcard.dart' show QuestionType;
import 'math_markup.dart';
import 'text_chunker.dart';

/// Wird geworfen, wenn die KI-Antwort kein (reparierbares) JSON enthält.
/// Trägt die Rohantwort mit, damit die UI sie bei Bedarf anzeigen kann
/// (hilfreich zum Debuggen eines schlecht formatierenden Modells).
class AiServiceException implements Exception {
  final String message;
  final String? rawResponse;
  AiServiceException(this.message, {this.rawResponse});

  @override
  String toString() => message;
}

/// BYOK-Anbindung an OpenRouter (https://openrouter.ai). Der Nutzer bringt
/// seinen eigenen API-Key mit (Einstellungen); es gibt keinen App-eigenen
/// Server, der Kosten verursachen könnte.
///
/// [model] bestimmt, welches OpenRouter-Modell für diese Instanz genutzt
/// wird – für die drei Rollen (Fragenerstellen/Vision/Crosscheck) werden
/// separate [AiService]-Instanzen mit dem jeweils passenden Modell aus den
/// Einstellungen erzeugt.
class AiService {
  AiService({required this.apiKey, required this.model, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  /// Großzügig, da einzelne Generierungsaufrufe (große Chunks, Vision-
  /// Modelle) legitimerweise mehrere Minuten dauern können.
  static const _requestTimeout = Duration(minutes: 3);

  /// Zeichenobergrenze für Aufrufe, die bewusst NICHT gechunkt werden
  /// (Crosscheck-Quellmaterial dient nur als Kontext, keine vollständige
  /// Neuverarbeitung).
  static const int _crosscheckSourceCap = 40000;

  /// Wie viele bereits erfasste Stichpunkte/Konzepttitel maximal als
  /// Rolling-Context in den nächsten Chunk-Prompt übernommen werden – hält
  /// den Prompt bei sehr vielen Chunks trotzdem beschränkt.
  static const int _rollingContextLimit = 40;

  /// Eigenständiger Prompt zum Kopieren in ein EXTERNES KI-Chat-Fenster
  /// (ChatGPT, Gemini, Claude.ai, ...), wenn ein stärkeres Modell gebraucht
  /// wird als die in dieser App per BYOK hinterlegten – z.B. bei besonders
  /// unüblichen Vorlagen (Zuordnungs-Matrizen, Diskussionsfragen ohne
  /// exakte Musterlösung), an denen ein schwächeres Modell scheitert. Anders
  /// als [_importQuestionsSystemPrompt]/[_conceptsSystemPrompt] wird dieser
  /// Text NIE direkt an OpenRouter geschickt (kein API-Call, keine Kosten) –
  /// er wird nur in der UI angezeigt/in die Zwischenablage kopiert (siehe
  /// ReviewScreen-Modus "JSON einfügen"). Das externe Modell liefert damit
  /// GENAU das JSON-Format, das `QuestionParsing.normalizeGeneratedFlashcard`
  /// auch von den beiden anderen Erzeugungswegen erwartet, daher hier bewusst
  /// dieselbe Feld-/Typ-Beschreibung dupliziert statt geteilt: der Text muss
  /// für sich allein stehen, ohne Bezug auf Dart-Code, das ihn ein Mensch
  /// woanders einfügt.
  static const externalJsonPromptTemplate = '''
Du hilfst mir, Lernmaterial für die App "Lernen" aufzubereiten. Ich füge dir
unten den Text eines Dokuments an (Klausur, Übungsblatt, Folien o.ä.).

AUFGABE: Erstelle daraus Karteikarten/Fragen zur Wiederholung – entweder
ORIGINALGETREU übernommen (wenn das Dokument bereits fertige Fragen samt
Lösung enthält, z.B. eine alte Klausur) oder SELBST ERSTELLT (wenn es reine
Theorie/Folien ohne vorformulierte Fragen sind). Wenn unklar, entscheide
sinnvoll je nach Abschnitt.

Wähle pro Frage den technisch passenden Typ AUSSCHLIESSLICH aus der
tatsächlichen Struktur der Original-Frage im Dokument – nicht nach dem, was
am bequemsten zu erzeugen wäre. "free_text" ist NICHT der Standard-
Auffangtyp für alles, was nicht auf Anhieb offensichtlich in einen anderen
Typ passt: hat die Frage eine Tabellen-/Matrixstruktur, eine
Zuordnungsaufgabe, oder verlangt sie erkennbar mehrere separate
Stichpunkte/Kernaussagen als Antwort, gehört sie zu "html" (siehe unten),
NICHT zu "free_text" – auch wenn "html" mehr Aufwand bedeutet. Nutze
NICHT für alles denselben Typ, sondern möglichst den spezifischsten:
   - "single_choice": genau eine richtige Antwort unter mehreren Optionen.
     {"type": "single_choice", "front": "Frage", "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]}
   - "multiple_choice": mehrere Antworten gleichzeitig richtig, gleiches Format.
   - "fill_blank": Lückentext. Markiere jede Lücke im "front"-Text mit genau
     drei Unterstrichen "___", "blanks" enthält die Lösungen in derselben
     Reihenfolge. {"type": "fill_blank", "front": "Text mit ___ Lücke", "blanks": ["Lösung"]}
   - "free_text": offene, aber eindeutig prüfbare Kurzantwort MIT EINER
     EINZELNEN, kompakten Musterlösung (Zahl, Formel, ein Satz). "correctText"
     enthält die Lösung (bei mehreren akzeptierten Formulierungen durch ";"
     getrennt). {"type": "free_text", "front": "Frage", "correctText": "Lösung; Alternative"}
   - "drag_drop": Begriffe einander zuordnen (Paare). "dragPairs" enthält
     {"source","target"}-Paare. {"type": "drag_drop", "front": "Ordne zu", "dragPairs": [{"source": "A", "target": "B"}]}
   - "drag_category": Begriffe in Kategorien einsortieren. "dragPairs" wie bei
     drag_drop, "target" ist hier der Kategoriename (mehrere "source" können
     denselben "target"-Wert haben).
   - "flashcard": einfaches front/back, nur wenn kein anderer Typ passt.
     "back" ist PFLICHT und darf nie leer sein.
   - "html": bei Zuordnungs-/Matrix-/Tabellenstruktur mit mehreren
     Kriterien-Zeilen (pro Zeile eine von mehreren Spalten auswählen), einer
     Drag&Drop-Zeichnung, ODER einer offenen Erläuterungs-/Diskussionsfrage
     mit MEHREREN erkennbaren Kernpunkten als Musterlösung, bei der ein
     reiner Text-Exakt-Vergleich zu streng wäre. Für diesen Typ baust du
     selbst eine eigenständige, interaktive HTML-Seite:
       * "htmlContent" enthält NUR den Inhalt, der in <body> gehört (also KEIN
         <html>/<head>/<style>-Rahmen, keine <!DOCTYPE>-Zeile) – reines
         Inline-HTML/CSS/JS in einem einzigen String.
       * Kein externes Skript, Bild, keine Netzwerk-Anfrage/kein fetch/XHR –
         wird ohnehin blockiert (die App zeigt die Seite in einer
         abgeriegelten Sandbox ohne Netzwerkzugriff an).
       * Du kennst die richtige Lösung bereits jetzt beim Erstellen – baue die
         Prüf-Logik direkt als Inline-JavaScript in die Seite ein (z.B. bei
         Klick auf einen "Prüfen"-Button).
       * Beim Auswerten MUSS die Seite GENAU diesen Aufruf machen, sonst
         bekommt die App nie ein Ergebnis und die Karte ist unbrauchbar:
         window.FlutterAnswer.postMessage(JSON.stringify({correct: true}))
         (bzw. {correct: false} bei falscher Antwort).
       * Gib zusätzlich "front" (kurze Frage-Überschrift) und "back" (kurze
         Text-Zusammenfassung der Lösung) an – dient als Fallback-Anzeige auf
         Geräten, die keine interaktive Seite anzeigen können (z.B. Windows-
         Desktop statt Android/iOS).

JEDER Eintrag in "flashcards" MUSS ALLE für seinen "type" nötigen Felder
enthalten (siehe Beispiele oben) – ein Eintrag mit nur "front" und sonst
nichts ist ungültig und wird von der App verworfen. Enthält das Dokument zu
einer Frage KEINE erkennbare Musterlösung, überspringe diese Frage.

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
WICHTIG – Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format,
ohne Markdown-Codefences (kein ```), ohne jeden Text davor oder danach, sonst
kann ich deine Antwort nicht in die App einfügen:
{"flashcards": [
  {"type": "single_choice", "front": "...", "options": [{"text": "...", "isCorrect": true}]}
]}
Antworte in der Sprache der Vorlage.

Hier ist der Dokumenttext:

[FÜGE HIER DEN TEXT/DIE FRAGEN DEINES DOKUMENTS EIN]
''';

  /// [userContent] ist entweder ein einfacher String (Text-Anfrage, der
  /// Normalfall) oder eine OpenRouter/OpenAI-kompatible Content-Parts-Liste
  /// (`[{"type": "text", ...}, {"type": "image_url", ...}]`) für multimodale
  /// Anfragen an ein Vision-Modell (siehe [answerPageQuestion]) – beides ist
  /// als `content`-Wert einer Chat-Nachricht gültig, daher hier bewusst
  /// `Object` statt `String`.
  Future<String> _complete(String systemPrompt, Object userContent) async {
    if (apiKey.trim().isEmpty) {
      throw AiServiceException(
          'Kein OpenRouter-API-Key hinterlegt. Bitte in den Einstellungen eintragen.');
    }

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://github.com/nphjfvp/lernen',
              'X-Title': 'Lernen',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0.3,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userContent},
              ],
            }),
          )
          // Ohne Obergrenze bliebe bei einer hängenden Verbindung (z.B.
          // Netzwechsel unterwegs) der Lade-Spinner für immer stehen.
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw AiServiceException(
          'Keine Antwort von OpenRouter nach ${_requestTimeout.inMinutes} Minuten – bitte erneut versuchen.');
    } on http.ClientException catch (e) {
      throw AiServiceException('Keine Verbindung zu OpenRouter: ${e.message}');
    }

    if (response.statusCode != 200) {
      throw AiServiceException(
          'OpenRouter-Anfrage fehlgeschlagen (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw AiServiceException('Leere Antwort vom Modell erhalten.',
          rawResponse: response.body);
    }
    final content = choices.first['message']?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw AiServiceException('Leere Antwort vom Modell erhalten.',
          rawResponse: response.body);
    }
    return content;
  }

  static String _cap(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}\n\n[... gekürzt, Text war länger ...]';
  }

  /// Zerlegt [text] gemäß [granularity] in Abschnitte (oder gibt ihn
  /// unverändert als einzigen Abschnitt zurück, wenn Chunking nicht nötig
  /// bzw. deaktiviert ist).
  static List<String> _chunksFor(String text, ChunkGranularity granularity) {
    final chunkSize = TextChunker.chunkSizeFor(granularity, text.length);
    if (chunkSize == null) return [text];
    final chunks = TextChunker.split(text, chunkSize);
    return chunks.isEmpty ? [text] : chunks;
  }

  static const _summarySystemPrompt = '''
Du bist ein Lernassistent für Studierende. Du bekommst den Text von
Vorlesungsfolien (möglicherweise nur einen Abschnitt eines längeren
Foliensatzes) und erstellst daraus eine strukturierte Zusammenfassung für
einen schnellen Überblick.
Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau
diesem Format, ohne Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{
  "title": "Kurzer Titel der Sitzung/des Themas",
  "overview": "Strukturierte Zusammenfassung, 3-6 Absätze, klar gegliedert",
  "key_points": ["Kernkonzept 1", "Kernkonzept 2", "..."]
}
Wenn bereits erfasste Kernkonzepte aus vorherigen Abschnitten genannt werden,
wiederhole diese NICHT, sondern konzentriere dich auf neuen Inhalt.
Antworte in der Sprache der Vorlage.
''';

  /// Vorbereiten-Modus: strukturierte Zusammenfassung + Kernkonzepte aus
  /// Vorlesungsfolien für den schnellen Überblick vor der Sitzung.
  ///
  /// Sehr lange Foliensätze werden – wie im Vorgänger per
  /// "Rolling-Context-Chunking" – in mehrere Anfragen zerlegt: jeder
  /// weitere Abschnitt bekommt die bereits erfassten Kernkonzepte als
  /// Kontext, damit das Modell nicht dieselben Punkte wiederholt.
  Future<Map<String, dynamic>> generateSummary(
    String slidesText, {
    ChunkGranularity granularity = ChunkGranularity.auto,
    bool rollingContext = true,
    void Function(int done, int total)? onProgress,
  }) async {
    final chunks = _chunksFor(slidesText, granularity);

    if (chunks.length == 1) {
      final raw = await _complete(
          _summarySystemPrompt, 'Vorlesungsfolien:\n\n${chunks.first}');
      onProgress?.call(1, 1);
      return _parseJsonObject(raw);
    }

    String? title;
    final overviewParts = <String>[];
    final keyPoints = <String>[];

    for (var i = 0; i < chunks.length; i++) {
      final contextNote = rollingContext && keyPoints.isNotEmpty
          ? '\n\nBereits erfasste Kernkonzepte aus vorherigen Abschnitten '
              '(NICHT wiederholen, nur bei völlig neuen Aspekten ergänzen):\n'
              '- ${keyPoints.take(_rollingContextLimit).join('\n- ')}'
          : '';
      final userPrompt =
          'Dies ist Abschnitt ${i + 1} von ${chunks.length} eines längeren '
          'Foliensatzes.$contextNote\n\nAbschnitt-Text:\n\n${chunks[i]}';
      final raw = await _complete(_summarySystemPrompt, userPrompt);
      final parsed = _parseJsonObject(raw);

      title ??= (parsed['title'] as String?)?.trim();
      final overview = (parsed['overview'] as String?)?.trim();
      if (overview != null && overview.isNotEmpty) overviewParts.add(overview);
      final points =
          (parsed['key_points'] as List?)?.map((e) => e.toString()) ??
              const <String>[];
      for (final p in points) {
        if (p.trim().isNotEmpty && !keyPoints.contains(p)) keyPoints.add(p);
      }
      onProgress?.call(i + 1, chunks.length);
    }

    return {
      'title': (title == null || title.isEmpty) ? 'Zusammenfassung' : title,
      'overview': overviewParts.join('\n\n'),
      'key_points': keyPoints,
    };
  }

  static const _conceptsSystemPrompt = '''
Du bist ein Lernassistent für Studierende und bereitest Stoff für die
Nachbereitung vor. Du bekommst Vorlesungsfolien, meist zusammen mit
Übungsaufgaben zum gleichen Thema (möglicherweise nur einen Abschnitt eines
längeren Materials, in dem Folien- und Übungsinhalte gemischt vorkommen
können) – wurden keine Übungsaufgaben hochgeladen, arbeite allein anhand
der Folien. Analysiere den Abschnitt und erstelle:
1. Lernkonzepte: liegen Übungsaufgaben vor, erkläre WARUM sie so gelöst
   werden wie sie gelöst werden (Fokus auf tiefem Verständnis der Übungen,
   nicht auf reiner Theorie-Wiedergabe); ohne Übungsaufgaben die zentralen
   Konzepte der Folien selbst.
2. Karteikarten/Fragen zur Wiederholung dieser Konzepte.

WICHTIG zur inhaltlichen Korrektheit: stütze JEDE Erklärung, Frage und
Antwort AUSSCHLIESSLICH auf das gegebene Material. Erfinde keine Fakten,
Zahlen, Formeln oder Definitionen, die dort nicht vorkommen oder sich nicht
direkt daraus ableiten lassen – auch nicht aus vermeintlichem
Allgemeinwissen zum Thema, das vom konkreten Material abweichen könnte.
Bist du dir bei einem Detail nicht sicher, ob es im Material so steht, lass
die Frage lieber weg statt zu raten.

WICHTIG zur Typwahl: verwende NICHT für alle Karten denselben Typ. "flashcard"
(freies front/back) ist die LETZTE Wahl, nur wenn WIRKLICH keiner der
anderen Typen passt – erzeuge höchstens für etwa ein Fünftel der Karten
diesen Typ, den Rest möglichst mit den spezifischeren Typen unten. Wähle pro
Frage den zum Inhalt passenden Typ:
   - "single_choice": klares Faktenwissen mit genau einer richtigen Antwort.
     Setze zusätzlich "escalate": true – das System steigert den
     Schwierigkeitsgrad solcher Fragen automatisch in mehreren Stufen
     (Single-Choice -> Lückentext -> Freitext), sobald sie zuverlässig
     richtig beantwortet werden, und stuft bei wiederholten Fehlversuchen
     wieder zurück. WICHTIG: erzeuge zu JEDEM Konzept, sofern das Thema
     dafür überhaupt geeignetes Faktenwissen hergibt, MINDESTENS eine
     "single_choice"-Frage mit "escalate": true (nicht nur gelegentlich bei
     zufällig passenden Fragen) – dieses Stufensystem soll für den Lernenden
     tatsächlich regelmäßig zum Einsatz kommen, nicht nur in Ausnahmefällen.
   - "multiple_choice": wenn mehrere Aussagen gleichzeitig zutreffen können.
   - "fill_blank": Lückentext – markiere jede Lücke im "front"-Text mit genau
     drei Unterstrichen "___", "blanks" enthält die Lösungen in derselben
     Reihenfolge.
   - "free_text": offene, aber eindeutig prüfbare Kurzantwort; "correctText"
     enthält die Lösung (bei mehreren akzeptierten Formulierungen durch ";"
     getrennt).
   - "drag_drop": Begriffe einander zuordnen (Paare); "dragPairs" enthält
     {"source","target"}-Paare.
   - "drag_category": Begriffe in Kategorien einsortieren; "dragPairs" wie
     bei drag_drop, "target" ist hier der Kategoriename (mehrere "source"
     können denselben "target"-Wert haben).
   - "flashcard": nur als letzte Wahl (siehe oben) – "front"/"back" wie
     bisher. Das Feld "back" ist dabei PFLICHT und darf NIE leer sein – eine
     Karteikarte ohne Antwort ist nutzlos.
   - "html": AUSNAHME, noch seltener als "flashcard" – nur wenn WIRKLICH
     keiner der obigen Typen die Struktur der Vorlage abbilden kann.
     Typische Beispiele: eine Zuordnungs-Matrix/Tabelle mit mehreren
     Kriterien-Zeilen, bei der man pro Zeile eine von mehreren Spalten
     wählt; oder eine offene Erläuterungs-/Diskussionsfrage, bei der ein
     reiner Text-Exakt-Vergleich zu streng wäre (dann prüft dein eigenes
     JavaScript großzügiger, z.B. ob mehrere der erwarteten Kernpunkte
     sinngemäß vorkommen, statt eine einzige exakte Formulierung zu
     verlangen). "htmlContent" enthält NUR den `<body>`-Inhalt (kein
     `<html>`/`<head>`/`<style>`-Rahmen, die App bettet das selbst sicher
     ein) als eigenständige, interaktive Seite: reines Inline-HTML/CSS/JS,
     kein externes Skript/Bild/keine Netzwerk-Anfrage (wird ohnehin
     blockiert). Die Seite MUSS ihre eigene Prüf-Logik enthalten (du kennst
     die Lösung bereits jetzt) und beim Auswerten GENAU diesen Aufruf
     machen: `window.FlutterAnswer.postMessage(JSON.stringify({correct:
     true}))` (bzw. `correct: false` bei falscher Antwort) – ohne diesen
     Aufruf bekommt die App nie ein Ergebnis und die Karte ist unbrauchbar.
     Gib zusätzlich "front" (kurze Frage-Überschrift) und "back" (kurze
     Text-Zusammenfassung der Lösung) an – dient als Fallback-Anzeige auf
     Geräten ohne WebView-Unterstützung (z.B. Windows-Desktop).

JEDER Eintrag in "flashcards" MUSS ALLE für seinen "type" nötigen Felder
enthalten (siehe Beispiele unten) – ein Eintrag mit nur "front" und sonst
nichts ist ungültig und wird verworfen.

Trägt eine Karteikarte inhaltlich zu einem der oben erstellten Konzepte bei,
ergänze zusätzlich "conceptTitle" mit EXAKT demselben Titel wie im
"concepts"-Array (Zeichen für Zeichen identisch, damit die Zuordnung
technisch funktioniert). Nicht jede Karte muss einem Konzept zugeordnet
werden – reines Einzelfaktenwissen ohne Konzeptbezug lässt das Feld einfach
weg.

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{
  "concepts": [
    {"title": "Konzeptname", "explanation": "Ausführliche Erklärung mit Bezug zu den Übungsaufgaben"}
  ],
  "flashcards": [
    {"type": "single_choice", "front": "Frage", "escalate": true, "conceptTitle": "Konzeptname",
     "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]},
    {"type": "multiple_choice", "front": "Frage",
     "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]},
    {"type": "fill_blank", "front": "Text mit ___ Lücke", "blanks": ["Lösung"]},
    {"type": "free_text", "front": "Frage", "correctText": "Lösung; Alternative"},
    {"type": "drag_drop", "front": "Ordne zu", "dragPairs": [{"source": "A", "target": "B"}]},
    {"type": "drag_category", "front": "Sortiere ein", "dragPairs": [{"source": "A", "target": "Kategorie 1"}]},
    {"type": "flashcard", "front": "Frage", "back": "Antwort (Pflichtfeld, nie leer)"},
    {"type": "html", "front": "Kurzfassung der Frage", "back": "Kurzfassung der Lösung",
     "htmlContent": "<div>...Inline-HTML/CSS/JS mit eigener Prüf-Logik, siehe oben...</div>"}
  ]
}
Erstelle so viele Konzepte/Karteikarten wie der Abschnitt hergibt (auch
wenige, wenn der Abschnitt kurz ist), mit einer sinnvollen Mischung aus
mindestens 3 verschiedenen Typen, wenn der Abschnitt lang genug für mehrere
Karten ist. Wenn bereits erstellte Konzepte aus vorherigen Abschnitten
genannt werden, erstelle diese NICHT erneut.
Antworte in der Sprache der Vorlage.
''';

  /// Nachbereiten-Modus: analysiert Folien UND Übungsaufgaben gemeinsam und
  /// erzeugt gezielte Lernkonzepte + Karteikarten. Fokus liegt laut Vorgabe
  /// auf der tiefen Durchdringung der Übungen, nicht nur auf Theorie.
  ///
  /// Beide Texte werden zu einem Materialstrom zusammengeführt und bei
  /// Bedarf gemeinsam gechunkt (statt getrennt), damit ein Abschnitt Folien
  /// und die zugehörigen Übungen weiterhin gemeinsam betrachtet.
  Future<Map<String, dynamic>> generateConceptsAndFlashcards({
    required String slidesText,
    required String exercisesText,
    ChunkGranularity granularity = ChunkGranularity.auto,
    bool rollingContext = true,
    String? examContext,
    void Function(int done, int total)? onProgress,
  }) async {
    final combinedText = (StringBuffer()
          ..writeln('=== VORLESUNGSFOLIEN ===')
          ..writeln(slidesText)
          ..writeln()
          ..writeln('=== ÜBUNGSAUFGABEN ===')
          ..writeln(exercisesText.isEmpty ? '(keine hochgeladen)' : exercisesText)
          ..writeln(examContext != null && examContext.trim().isNotEmpty
              ? '\n=== STIL-REFERENZ: ÜBUNGSKLAUSUR (orientiere Frageart/-schwierigkeit '
                  'daran, sofern thematisch passend, erfinde aber keine themenfremden Fragen) ===\n'
                  '${_cap(examContext, _examContextCap)}'
              : ''))
        .toString();

    final chunks = _chunksFor(combinedText, granularity);

    if (chunks.length == 1) {
      final raw = await _complete(_conceptsSystemPrompt, chunks.first);
      onProgress?.call(1, 1);
      return _parseJsonObject(raw);
    }

    final concepts = <Map<String, dynamic>>[];
    final flashcards = <Map<String, dynamic>>[];
    final seenConceptTitles = <String>{};

    for (var i = 0; i < chunks.length; i++) {
      final contextNote = rollingContext && seenConceptTitles.isNotEmpty
          ? '\n\nBereits erstellte Konzepte aus vorherigen Abschnitten '
              '(NICHT erneut erstellen, nur bei völlig neuen Aspekten '
              'ergänzen):\n- ${seenConceptTitles.take(_rollingContextLimit).join('\n- ')}'
          : '';
      final userPrompt =
          'Dies ist Abschnitt ${i + 1} von ${chunks.length} eines längeren '
          'Materials.$contextNote\n\nAbschnitt-Text:\n\n${chunks[i]}';
      final raw = await _complete(_conceptsSystemPrompt, userPrompt);
      final parsed = _parseJsonObject(raw);

      for (final entry in (parsed['concepts'] as List? ?? const [])) {
        final c = Map<String, dynamic>.from(entry as Map);
        final title = (c['title'] ?? '').toString().trim();
        if (title.isNotEmpty && seenConceptTitles.add(title)) {
          concepts.add(c);
        }
      }
      for (final entry in (parsed['flashcards'] as List? ?? const [])) {
        flashcards.add(Map<String, dynamic>.from(entry as Map));
      }
      onProgress?.call(i + 1, chunks.length);
    }

    return {'concepts': concepts, 'flashcards': flashcards};
  }

  static const _checkpointQuizSystemPrompt = '''
Du bist ein Lernassistent für Studierende im "Lernmodus": der Nutzer liest
gerade einen Foliensatz Seite für Seite und bekommt nach ein paar Seiten
einen SEHR KURZEN Zwischen-Check zum Abschnitt, den er/sie gerade gelesen
hat – kein vollständiges Nachbereiten, nur ein schneller Verständnis-Check.

Erstelle 2-3 kurze Fragen NUR zu dem gegebenen Abschnitt (nicht zu Stoff,
der dort nicht vorkommt). Wähle pro Frage einen passenden Typ (nicht immer
denselben): "single_choice" (options mit isCorrect), "fill_blank" (Lücken
im "front" als "___" markiert, "blanks" mit den Lösungen), "free_text"
("correctText" mit der Lösung) oder "flashcard" (offenes front/back, back
ist Pflicht) – wie im Hauptformat des Nachbereiten-Modus.

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{"flashcards": [
  {"type": "single_choice", "front": "Frage", "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]},
  {"type": "fill_blank", "front": "Text mit ___ Lücke", "blanks": ["Lösung"]},
  {"type": "free_text", "front": "Frage", "correctText": "Lösung"},
  {"type": "flashcard", "front": "Frage", "back": "Antwort (Pflichtfeld, nie leer)"}
]}
Antworte in der Sprache der Vorlage.
''';

  static const int _checkpointQuizInputCap = 20000;
  static const int _examContextCap = 15000;

  /// Kurzer Zwischen-Check im "Lernmodus" (siehe MaterialViewerScreen): 2-3
  /// Fragen NUR zu [pageRangeText] (dem Text der zuletzt gelesenen Seiten),
  /// optional orientiert an einer hochgeladenen Übungsklausur
  /// ([examContext], siehe MaterialKind.practiceExam) für realistischere
  /// Frageart/-schwierigkeit. Liefert rohe Flashcard-JSON-Maps im selben
  /// Format wie [generateConceptsAndFlashcards] (siehe QuestionParsing für
  /// die Umwandlung in echte [Flashcard]-Objekte).
  Future<List<Map<String, dynamic>>> generateCheckpointQuiz(
    String pageRangeText, {
    String? examContext,
  }) async {
    final buffer = StringBuffer()
      ..writeln('Gerade gelesener Abschnitt:')
      ..writeln(_cap(pageRangeText, _checkpointQuizInputCap));
    if (examContext != null && examContext.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Stil-Referenz, eine bereits hochgeladene Übungsklausur '
            '(orientiere dich bei Frageart/-schwierigkeit daran, sofern '
            'thematisch passend, erfinde aber KEINE Fragen zu Themen, die '
            'nicht im obigen Abschnitt vorkommen):')
        ..writeln(_cap(examContext, _examContextCap));
    }
    final raw = await _complete(_checkpointQuizSystemPrompt, buffer.toString());
    final parsed = _parseJsonObject(raw);
    return (parsed['flashcards'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static const _importQuestionsSystemPrompt = '''
Du bekommst den Text eines Übungsdokuments (z.B. eine alte Klausur, ein
Übungsblatt mit Musterlösung o.ä.), das BEREITS FERTIGE Fragen samt Lösung
enthält. Deine Aufgabe ist NICHT, neue Fragen zu erfinden, sondern die
tatsächlich im Dokument vorhandenen Fragen/Aufgaben so originalgetreu wie
möglich als Karteikarten zu übernehmen (Wortlaut der Frage beibehalten,
nur so weit umformulieren wie für das Karteikarten-Format nötig, z.B. eine
mehrteilige Aufgabe in mehrere einzelne Karten aufteilen).

WICHTIG zur Typwahl: bestimme den Typ AUSSCHLIESSLICH aus der tatsächlichen
Struktur der Original-Frage im Dokument – wie ist sie dort GESTELLT (nicht:
welcher Typ am bequemsten zu erzeugen wäre). "free_text" ist NICHT der
Standard-Auffangtyp für alles, was nicht auf Anhieb offensichtlich in einen
anderen Typ passt – bevor du "free_text" wählst, prüfe der Reihe nach:
  1. Sind im Original mehrere Antwortoptionen zum Ankreuzen vorgegeben?
     -> "single_choice"/"multiple_choice".
  2. Ist es ein Lückentext? -> "fill_blank".
  3. Hat die Frage eine Tabellen-/Matrixstruktur (mehrere Kriterien-Zeilen,
     pro Zeile eine von mehreren Spalten/Kategorien zuordnen), eine
     Zuordnungsaufgabe (Begriff <-> Begriff/Kategorie per Linie/Pfeil), oder
     verlangt sie erkennbar mehrere separate Stichpunkte/Kernaussagen als
     Antwort (bei denen ein einziger Textvergleich zu starr wäre)? -> "html"
     (siehe unten) – NICHT in eine vereinfachte free_text-Frage umwandeln,
     nur weil das weniger Aufwand bedeutet.
  4. Erst wenn NICHTS davon zutrifft und es sich um eine wirklich offene
     Frage mit einer einzelnen, kurzen erwarteten Antwort handelt (Zahl,
     Formel, ein Satz): "free_text".
   - "single_choice": Original ist Multiple-Choice mit genau einer richtigen
     Antwort. Antwortformat: {"type": "single_choice", "front": "...",
     "options": [{"text": "...", "isCorrect": true}, ...]}
   - "multiple_choice": mehrere Antworten gleichzeitig richtig, analog.
   - "fill_blank": Lückentext im Original. Markiere jede Lücke im
     "front"-Text mit genau drei Unterstrichen "___", "blanks" enthält die
     Lösungen in derselben Reihenfolge.
   - "free_text": offene Rechen-/Kurzantwortaufgabe mit einer einzelnen,
     kompakten Musterlösung. "correctText" enthält die Lösung.
   - "flashcard": passt keiner der obigen Typen, offenes front/back. "back"
     ist Pflicht und darf nie leer sein.
   - "html": bei Zuordnungs-/Matrix-/Tabellenstruktur ODER einer offenen
     Erläuterungs-/Diskussionsfrage mit MEHREREN im Dokument erkennbaren
     Kernpunkten/Stichpunkten als Musterlösung, bei der ein reiner
     Text-Exakt-Vergleich zu streng wäre (dann prüft dein eigenes JavaScript
     großzügiger, z.B. ob mehrere der erwarteten Kernpunkte sinngemäß
     vorkommen). "htmlContent" enthält NUR den `<body>`-Inhalt (kein
     `<html>`/`<head>`/`<style>`-Rahmen) als eigenständige, interaktive
     Seite: reines Inline-HTML/CSS/JS, kein externes Skript/Bild/keine
     Netzwerk-Anfrage (wird ohnehin blockiert). Die Seite MUSS ihre eigene
     Prüf-Logik enthalten (du kennst die Musterlösung bereits jetzt) und
     beim Auswerten GENAU diesen Aufruf machen:
     `window.FlutterAnswer.postMessage(JSON.stringify({correct: true}))`
     (bzw. `correct: false`) – ohne diesen Aufruf bekommt die App nie ein
     Ergebnis. Gib zusätzlich "front"/"back" als kurze Text-Zusammenfassung
     an (Fallback-Anzeige ohne WebView-Unterstützung).

Enthält das Dokument KEINE erkennbare Musterlösung zu einer Frage, überspringe
diese Frage (keine Karte ohne bekannte Antwort erzeugen).

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{"flashcards": [
  {"type": "single_choice", "front": "Originalfrage", "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]}
]}
Übernimm ALLE im Dokument vorhandenen Fragen mit erkennbarer Lösung, auch
wenn es viele sind. Antworte in der Sprache der Vorlage.
''';

  /// Statt neue Fragen zu ERFINDEN (siehe [generateConceptsAndFlashcards]):
  /// übernimmt die bereits im Dokument vorhandenen Fragen samt Musterlösung
  /// möglichst originalgetreu ("importieren" statt "generieren", siehe
  /// ReviewScreen-Import-Modus – Pendant zum entsprechenden Feature der
  /// Vorgänger-App).
  Future<List<Map<String, dynamic>>> importQuestionsFromExercises(
    String exercisesText, {
    ChunkGranularity granularity = ChunkGranularity.auto,
    void Function(int done, int total)? onProgress,
  }) async {
    final chunks = _chunksFor(exercisesText, granularity);
    final flashcards = <Map<String, dynamic>>[];
    for (var i = 0; i < chunks.length; i++) {
      final userPrompt = chunks.length == 1
          ? chunks.first
          : 'Dies ist Abschnitt ${i + 1} von ${chunks.length} eines längeren '
              'Übungsdokuments.\n\nAbschnitt-Text:\n\n${chunks[i]}';
      final raw = await _complete(_importQuestionsSystemPrompt, userPrompt);
      final parsed = _parseJsonObject(raw);
      for (final entry in (parsed['flashcards'] as List? ?? const [])) {
        flashcards.add(Map<String, dynamic>.from(entry as Map));
      }
      onProgress?.call(i + 1, chunks.length);
    }
    return flashcards;
  }

  static const _pageConceptSystemPrompt = '''
Du bist ein Lernassistent für Studierende im Lernmodus: der Nutzer betrachtet
gerade EINE konkrete Seite eines Foliensatzes und möchte daraus ein
eigenständiges Lernkonzept erstellen (Titel + ausführliche Erklärung).

Grundlage ist in erster Linie der Text dieser EINEN Seite. Text der
vorherigen/nachfolgenden Seite wird dir NUR als zusätzlicher Kontext
mitgegeben (falls verfügbar) – nutze ihn AUSSCHLIESSLICH, wenn das Konzept
auf dieser Seite ohne ihn unvollständig oder unverständlich wäre (z.B. eine
Definition beginnt auf der vorherigen Seite, eine Formel wird erst auf der
nächsten hergeleitet). Ist der Seiteninhalt für sich verständlich, ignoriere
den Nachbar-Kontext komplett – erweitere das Konzept NICHT unnötig auf
Nachbarthemen.

Bekommst du zusätzlich ein BEREITS erstelltes Konzept samt Überarbeitungs-
Anweisung, überarbeite GENAU dieses Konzept gemäß der Anweisung (z.B.
umformulieren, kürzen, mehr Fokus auf einen Aspekt) statt ein neues zu
erfinden.

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{"title": "Kurzer, prägnanter Konzepttitel", "explanation": "Ausführliche, klar strukturierte Erklärung"}
Antworte in der Sprache der Vorlage.
''';

  static const int _pageConceptCap = 20000;
  static const int _pageConceptNeighborCap = 8000;

  /// Erstellt (oder überarbeitet) ein Lernkonzept aus GENAU einer Seite
  /// (siehe MaterialViewerScreen-Button "Konzept speichern" im Lernmodus).
  /// [previousPageText]/[nextPageText] sind rein optionaler Zusatzkontext –
  /// die KI entscheidet selbst (siehe Systemprompt), ob sie ihn tatsächlich
  /// braucht, statt ihn immer einzuarbeiten. Für eine Überarbeitung
  /// bestehender Ergebnisse [currentTitle]/[currentExplanation] +
  /// [instruction] mitgeben (z.B. "kürzer", "mehr Fokus auf die Formel").
  Future<Map<String, dynamic>> generatePageConcept({
    required String pageText,
    String? previousPageText,
    String? nextPageText,
    String? currentTitle,
    String? currentExplanation,
    String? instruction,
  }) async {
    final buffer = StringBuffer()
      ..writeln('Text der aktuellen Seite:')
      ..writeln(_cap(pageText, _pageConceptCap));
    if (previousPageText != null && previousPageText.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Text der VORHERIGEN Seite (nur bei Bedarf nutzen):')
        ..writeln(_cap(previousPageText, _pageConceptNeighborCap));
    }
    if (nextPageText != null && nextPageText.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Text der NACHFOLGENDEN Seite (nur bei Bedarf nutzen):')
        ..writeln(_cap(nextPageText, _pageConceptNeighborCap));
    }
    if (currentExplanation != null && instruction != null && instruction.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Bereits erstelltes Konzept (überarbeiten statt neu erfinden):')
        ..writeln('Titel: ${currentTitle ?? ''}')
        ..writeln('Erklärung: $currentExplanation')
        ..writeln()
        ..writeln('Anweisung des Nutzers zur Überarbeitung: $instruction');
    }
    final raw = await _complete(_pageConceptSystemPrompt, buffer.toString());
    return _parseJsonObject(raw);
  }

  static const _pageQuestionGenerationSystemPrompt = '''
Du bist ein Lernassistent für Studierende im Lernmodus: der Nutzer betrachtet
gerade EINE konkrete Seite eines Foliensatzes (als Bild beigefügt, Text der
Seite als zusätzlicher Kontext) und möchte daraus gezielt eine Prüfungsfrage
erstellen. Stütze dich in erster Linie auf das Bild (Diagramme, Formeln,
Layout, was reiner Text nicht wiedergibt), der Text hilft bei der Einordnung.

Wurde dir ein konkretes Frage/Antwort-Paar mitgegeben (der Nutzer hat es auf
der Seite selbst markiert), MUSS sich JEDE erzeugte Karte auf GENAU diesen
Fakt beziehen – erfinde keinen anderen Inhalt. Andernfalls wähle selbst den
wichtigsten, klar abfragbaren Fakt auf der Seite.

Du bekommst eine Liste gewünschter Fragetypen. Erzeuge für JEDEN dieser Typen
in der gegebenen Reihenfolge GENAU EINE Karte zu DEMSELBEN Fakt – nur das
Format/die Schwierigkeit unterscheidet sich zwischen den Karten, nicht der
geprüfte Inhalt. Die Typ-spezifischen Formatvorgaben:
{{TYPE_RULES}}

Bekommst du zusätzlich bereits erstellte Karten samt Überarbeitungs-
Anweisung, überarbeite GENAU diese Karten gemäß der Anweisung (z.B. anderer
Fokus, einfacher formuliert, mehr Kontext) statt neue zu erfinden – behalte
dabei weiterhin Typ und Reihenfolge der gewünschten Fragetypen bei.

Entscheide zusätzlich pro Karte, ob der Seiten-Screenshot als Bild an die
Karte angehängt werden soll ("needsImage": true/false). Setze "needsImage"
NUR auf true, wenn die Frage OHNE das Bild nicht sinnvoll verständlich oder
beantwortbar ist – z.B. weil sie sich auf ein Diagramm, eine Formel, eine
Skizze, ein Foto oder ein Layout bezieht, das sich nicht vollständig in
Worten wiedergeben lässt. Bei rein textbasierten Fakten (die man auch ohne
das Bild klar verstehen und beantworten kann) setze "needsImage": false –
das ist der Regelfall, hänge also nicht bei jeder Karte ein Bild an.

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{"flashcards": [{"type": "...", "front": "...", "needsImage": false, "...": "je nach Typ weitere Felder, siehe oben"}]}
Die Reihenfolge im "flashcards"-Array entspricht der Reihenfolge der
gewünschten Typen. Antworte in der Sprache der Vorlage.
''';

  static const int _pageQuestionGenerationTextCap = 20000;

  /// Erstellt (oder überarbeitet) 1-3 Karteikarten-Varianten (unterschiedliche
  /// Typen/Schwierigkeitsgrade DESSELBEN Fakts, siehe [_variantTypeRule])
  /// direkt aus einer betrachteten Seite (siehe MaterialViewerScreen-Button
  /// "Frage erstellen" im Lernmodus). Bewusst immer multimodal (Screenshot +
  /// [model] muss vision-fähig sein) statt optional – einfacher UND
  /// robuster als ein Text/Vision-Umschalter, da Folienseiten oft Diagramme/
  /// Formeln enthalten, die reiner Text nicht wiedergibt. Optional
  /// [questionHighlight]/[answerHighlight]: vom Nutzer selbst markierter/
  /// eingegebener Frage/Antwort-Fakt (siehe MaterialHighlight) als
  /// VERBINDLICHE Grundlage statt freier KI-Wahl. Für eine Überarbeitung
  /// bestehender Ergebnisse [previousFlashcards] + [instruction] mitgeben
  /// (z.B. "einfacher formulieren", "anderer Fokus").
  Future<List<Map<String, dynamic>>> generateQuestionsFromPage({
    required Uint8List pageImageBytes,
    required String pageText,
    required List<QuestionType> types,
    String? questionHighlight,
    String? answerHighlight,
    String? examContext,
    List<Map<String, dynamic>>? previousFlashcards,
    String? instruction,
  }) async {
    final typeRules = types.map((t) => '- ${_variantTypeRule(t)}').join('\n');
    final systemPrompt = _pageQuestionGenerationSystemPrompt.replaceFirst('{{TYPE_RULES}}', typeRules);

    final buffer = StringBuffer()
      ..writeln('Text dieser Seite (Kontext, Grundlage ist primär das Bild):')
      ..writeln(_cap(pageText, _pageQuestionGenerationTextCap));
    if (questionHighlight != null && questionHighlight.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Vom Nutzer markierter/eingegebener Frage/Antwort-Fakt (VERBINDLICHE Grundlage):')
        ..writeln('Frage-Stelle: $questionHighlight')
        ..writeln('Antwort-Stelle: ${(answerHighlight ?? '').trim().isEmpty ? '(keine angegeben)' : answerHighlight}');
    }
    if (examContext != null && examContext.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Stil-Referenz, eine bereits hochgeladene Übungsklausur (orientiere '
            'dich bei Schwierigkeit/Formulierung daran, sofern thematisch passend):')
        ..writeln(_cap(examContext, _examContextCap));
    }
    if (previousFlashcards != null && instruction != null && instruction.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Bereits erstellte Karten (überarbeiten statt neu erfinden):')
        ..writeln(jsonEncode(previousFlashcards))
        ..writeln()
        ..writeln('Anweisung des Nutzers zur Überarbeitung: $instruction');
    }

    final content = [
      {'type': 'text', 'text': buffer.toString()},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,${base64Encode(pageImageBytes)}'},
      },
    ];
    final raw = await _complete(systemPrompt, content);
    final parsed = _parseJsonObject(raw);
    return (parsed['flashcards'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static const _crosscheckSystemPrompt = '''
Du bist ein fachlicher Prüfer für Lernmaterial. Du bekommst
Vorlesungsfolien, Übungsaufgaben und bereits von einer anderen KI erstellte
Lernkonzepte und Karteikarten (als JSON mit den Arrays "concepts" und
"flashcards" – Indizes darin beginnen bei 0, in der gegebenen Reihenfolge).
Prüfe die Konzepte und Karteikarten auf fachliche Fehler, Ungenauigkeiten
oder Widersprüche zum Ausgangsmaterial.

Findest du ein Problem, liefere nicht nur eine Beschreibung, sondern auch
eine KONKRET KORRIGIERTE Fassung des betroffenen Eintrags in "fix" – exakt
dieselbe Feldstruktur wie das Original (bei Konzepten "title"+"explanation";
bei Karteikarten "type" plus alle für diesen Typ nötigen Felder, siehe die
Typen im Original: front/back, front/options, front/correctText,
front/blanks, front/dragPairs). Ändere dabei NUR, was fachlich falsch ist –
lass alles andere unverändert.

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{
  "ok": true,
  "issues": [
    {
      "targetType": "concept",
      "targetIndex": 0,
      "problem": "Was ist falsch/ungenau",
      "fix": {"title": "korrigierter Titel", "explanation": "korrigierte Erklärung"}
    },
    {
      "targetType": "flashcard",
      "targetIndex": 2,
      "problem": "Was ist falsch/ungenau",
      "fix": {"type": "single_choice", "front": "...", "options": [{"text": "...", "isCorrect": true}]}
    }
  ]
}
"ok" ist true, wenn keine Probleme gefunden wurden (dann "issues": []).
Antworte in der Sprache der Vorlage.
''';

  /// Crosscheck-Pass: ein bewusst ZWEITES Modell prüft bereits generierte
  /// Konzepte/Karteikarten auf fachliche Fehler, bevor sie gespeichert
  /// werden. Nutzt das Quellmaterial nur gekürzt als Kontext – hier geht es
  /// um eine Plausibilitätsprüfung, keine vollständige Neuverarbeitung.
  Future<Map<String, dynamic>> crosscheckConceptsAndFlashcards({
    required String slidesText,
    required String exercisesText,
    required Map<String, dynamic> generated,
  }) async {
    final userPrompt = (StringBuffer()
          ..writeln('Vorlesungsfolien:')
          ..writeln(_cap(slidesText, _crosscheckSourceCap))
          ..writeln()
          ..writeln('Übungsaufgaben:')
          ..writeln(_cap(exercisesText, _crosscheckSourceCap))
          ..writeln()
          ..writeln('Generierte Konzepte und Karteikarten (zu prüfen):')
          ..writeln(jsonEncode(generated)))
        .toString();
    final raw = await _complete(_crosscheckSystemPrompt, userPrompt);
    return _parseJsonObject(raw);
  }

  static String _variantTypeRule(QuestionType targetType) => switch (targetType) {
        QuestionType.singleChoice =>
          'Zieltyp "single_choice": 3-4 Antwortoptionen, GENAU eine davon '
              'richtig (die bekannte Lösung). Antwortformat: '
              '{"front": "...", "options": [{"text": "...", "isCorrect": true}, ...]}',
        QuestionType.multipleChoice =>
          'Zieltyp "multiple_choice": 4-6 Antwortoptionen, mehrere davon '
              'richtig. Antwortformat: {"front": "...", "options": '
              '[{"text": "...", "isCorrect": true}, ...]}',
        QuestionType.fillBlank =>
          'Zieltyp "fill_blank": derselbe Fakt als Lückentext. Markiere '
              'jede Lücke im "front"-Text mit genau drei Unterstrichen '
              '"___". Antwortformat: {"front": "Text mit ___ Lücke(n)", '
              '"blanks": ["Lösung 1", "..."]}',
        QuestionType.freeText =>
          'Zieltyp "free_text": derselbe Fakt als offene, aber eindeutig '
              'prüfbare Frage ohne Antwortoptionen (die schwerste Stufe – '
              'keine Auswahl mehr, nur Erinnerung). Antwortformat: '
              '{"front": "...", "correctText": "Lösung; ggf. Alternative"}',
        QuestionType.dragDrop =>
          'Zieltyp "drag_drop": als Zuordnungspaare. Antwortformat: '
              '{"front": "...", "dragPairs": [{"source": "...", "target": "..."}]}',
        QuestionType.dragCategory =>
          'Zieltyp "drag_category": Begriffe in Kategorien einsortieren. '
              'Antwortformat: {"front": "...", "dragPairs": '
              '[{"source": "...", "target": "Kategorie"}]}',
        QuestionType.flashcard =>
          'Zieltyp "flashcard": offene Frage/Antwort. Antwortformat: '
              '{"front": "...", "back": "..."}',
        QuestionType.html =>
          'Zieltyp "html": kein Bestandteil dieser einfachen Schwierigkeits-'
              'Eskalation (siehe eigener Abschnitt zum html-Typ) – wird hier '
              'nicht als Zielstufe verwendet.',
      };

  /// Erster Schritt der Schwierigkeits-Eskalation (siehe
  /// [Flashcard.variantChain]): wandelt eine Frage mit BEKANNTER Lösung in
  /// einen anspruchsvolleren Fragetyp um, OHNE den geprüften Fakt zu
  /// verändern – nur das Format wird schwerer. Wird lazy aufgerufen, sobald
  /// eine Frage zuverlässig richtig beantwortet wurde (nicht im Voraus für
  /// alle Stufen), damit keine KI-Kosten für Stufen anfallen, die
  /// möglicherweise nie erreicht werden.
  Future<Map<String, dynamic>> generateHarderVariant({
    required String questionText,
    required String currentAnswer,
    required QuestionType targetType,
  }) async {
    final systemPrompt = '''
Du wandelst eine Lernfrage mit BEKANNTER Lösung in einen anspruchsvolleren
Fragetyp um. Der geprüfte Fakt/die Lösung darf sich NICHT ändern – nur das
Format der Frage.
${_variantTypeRule(targetType)}
Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format (siehe
oben), ohne Markdown-Codefences, ohne zusätzlichen Text davor/danach.
Antworte in der Sprache der Vorlage.
''';
    final userPrompt = 'Ursprüngliche Frage: $questionText\nBekannte Lösung: $currentAnswer';
    final raw = await _complete(systemPrompt, userPrompt);
    return _parseJsonObject(raw);
  }

  static const _checkFreeTextSystemPrompt = '''
Du bewertest, ob die Antwort eines Lernenden auf eine Freitext-Frage
INHALTLICH mit der hinterlegten Musterlösung übereinstimmt. Die Formulierung
darf komplett anders sein als die Musterlösung – andere Wortwahl, andere
Satzstruktur, mehr oder weniger ausführlich: das alles ist in Ordnung,
solange der fachliche Kern stimmt. Ein Wort-für-Wort-Vergleich ist NICHT
das Ziel (den gibt es bereits vorgeschaltet, du bist die Zweitmeinung für
Fälle, in denen dieser Vergleich fehlgeschlagen ist, obwohl die Antwort
inhaltlich richtig sein könnte).
Enthält die Musterlösung mehrere durch ";" getrennte akzeptierte
Formulierungen, reicht Übereinstimmung mit EINER davon.
Sei fair, aber nicht beliebig großzügig: fehlt der für die Musterlösung
zentrale fachliche Punkt komplett, ist die Antwort erkennbar nur geraten
oder widerspricht sie der Musterlösung inhaltlich, ist sie falsch.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text:
{"correct": true}
''';

  /// Zweitmeinung für Freitext-Antworten: der lokale Vergleich
  /// (AnswerChecker.checkFreeText) ist ein reiner Text-/Tippfehler-Abgleich
  /// und damit für echte, frei formulierte Antworten fast unmöglich zu
  /// erfüllen – schon eine inhaltlich richtige, aber anders formulierte
  /// Antwort fällt durch. Wird deshalb NUR aufgerufen, wenn der lokale
  /// Vergleich die Antwort bereits als falsch eingestuft hat (siehe
  /// QuestionAnswerView._checkFreeTextAnswer): kein API-Call für den
  /// Normalfall einer nahen Übereinstimmung, nur als Rettungsanker für
  /// abweichende Formulierungen.
  Future<bool> checkFreeTextAnswer({
    required String question,
    required String correctAnswer,
    required String userAnswer,
  }) async {
    final userPrompt =
        'Frage: $question\nMusterlösung: $correctAnswer\nAntwort des Lernenden: $userAnswer';
    final raw = await _complete(_checkFreeTextSystemPrompt, userPrompt);
    final parsed = _parseJsonObject(raw);
    return parsed['correct'] == true;
  }

  static const _explainSystemPrompt = '''
Du bist ein geduldiger Tutor für Studierende. Du bekommst eine Lernfrage,
die richtige Lösung und (falls vorhanden) die Antwort des Lernenden.
Erkläre in 3 bis 6 kurzen Sätzen, WARUM die Lösung richtig ist – das
zugrunde liegende Prinzip, nicht nur die Lösung wiederholen. Wenn der
Lernende falsch lag: benenne freundlich den konkreten Denkfehler bzw. was
seine Antwort von der Lösung unterscheidet. Schließe mit einer kurzen
Merkhilfe (Eselsbrücke, Beispiel oder Faustregel), wenn sich eine anbietet.
Stütze dich auf die gegebene Lösung und widersprich ihr nicht.
Antworte in normalem Fließtext (kein JSON, keine Codefences), in der
Sprache der Frage. Formeln in LaTeX zwischen \$…\$.
''';

  static const _explainSimplerSystemPrompt = '''
Du bist ein geduldiger Tutor. Der Lernende hat die vorherige Erklärung zu
einer Lernfrage nicht verstanden. Erkläre dieselbe Sache noch einmal VIEL
einfacher: Alltagssprache, keine Fachbegriffe ohne Erklärung, ein
anschauliches Beispiel oder eine Analogie, höchstens 5 kurze Sätze.
Antworte in normalem Fließtext (kein JSON, keine Codefences), in der
Sprache der Frage. Formeln in LaTeX zwischen \$…\$.
''';

  /// Erklärt nach dem Beantworten, warum die Lösung stimmt (und bei einer
  /// falschen Antwort, wo der Denkfehler lag). Mit [previousExplanation]
  /// entsteht stattdessen eine deutlich einfachere Neufassung ("Einfacher
  /// erklären").
  Future<String> explainAnswer({
    required String question,
    required String correctAnswer,
    String? userAnswer,
    bool? wasCorrect,
    String? previousExplanation,
  }) async {
    final buffer = StringBuffer()
      ..writeln('Frage: $question')
      ..writeln('Richtige Lösung: $correctAnswer');
    if (userAnswer != null && userAnswer.trim().isNotEmpty) {
      buffer.writeln('Antwort des Lernenden: $userAnswer');
    }
    if (wasCorrect != null) {
      buffer.writeln(wasCorrect ? 'Die Antwort war richtig.' : 'Die Antwort war falsch.');
    }
    if (previousExplanation != null) {
      buffer
        ..writeln()
        ..writeln('Bisherige Erklärung (zu schwer verständlich):')
        ..writeln(previousExplanation);
    }
    final raw = await _complete(
      previousExplanation == null ? _explainSystemPrompt : _explainSimplerSystemPrompt,
      buffer.toString(),
    );
    return raw.trim();
  }

  static const _hintSystemPrompt = '''
Du gibst einem Lernenden einen TIPP zu einer Lernfrage, ohne die Lösung zu
verraten. Ein Satz, höchstens zwei: ein Denkanstoß (worauf achten, welches
Prinzip, welche Eselsbrücke), aber NIE die Lösung selbst, kein Teil davon
wörtlich und bei Auswahlfragen keine Option ausschließen oder nennen.
Antworte in normalem Fließtext (kein JSON, keine Codefences), in der
Sprache der Frage.
''';

  /// Denkanstoß VOR dem Antworten, ohne die Lösung zu verraten.
  Future<String> generateHint({required String question, required String correctAnswer}) async {
    final raw = await _complete(
      _hintSystemPrompt,
      'Frage: $question\nLösung (NICHT verraten, nur als Hintergrund für den Tipp): $correctAnswer',
    );
    return raw.trim();
  }

  static const _weaknessSystemPrompt = '''
Du bist ein Lerncoach. Du bekommst die Lernfragen, mit denen sich ein
Studierender gerade am schwersten tut (jeweils mit richtiger Lösung und wie
oft sie falsch war). Finde die GEMEINSAMEN Muster: welche Themen, Begriffe
oder Denkfehler stecken dahinter (z.B. zwei Begriffe werden verwechselt,
eine Formel sitzt nicht, Details einer Definition fehlen)? Antworte kurz und
konkret:
1. Die 2–4 wichtigsten Muster als Stichpunkte, jeweils mit einem Satz,
   was genau schiefläuft.
2. Pro Muster eine konkrete Empfehlung, was man wiederholen oder wie man es
   sich merken kann.
Erfinde keine Themen, die in den Fragen nicht vorkommen. Normaler Text mit
Aufzählungszeichen, kein JSON, keine Codefences, in der Sprache der Fragen.
''';

  /// Fehlertagebuch: erkennt Muster in den aktuell schwächsten Karten
  /// (siehe WeaknessService) und schlägt vor, was gezielt zu wiederholen ist.
  Future<String> analyzeWeaknesses(List<({String question, String answer, String reasons})> items) async {
    final buffer = StringBuffer();
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      buffer
        ..writeln('${i + 1}. Frage: ${item.question}')
        ..writeln('   Lösung: ${item.answer}')
        ..writeln('   Probleme: ${item.reasons}');
    }
    final raw = await _complete(_weaknessSystemPrompt, buffer.toString());
    return raw.trim();
  }

  static const _chatSystemPrompt = '''
Du bist ein Lernassistent für Studierende. Wird dir Material bereitgestellt
(hochgeladenes Vorlesungs-/Übungsmaterial eines Fachs, chronologisch
geordnet und jeweils markiert, ob es im Unterricht bereits "Behandelt"
wurde oder "Noch nicht behandelt" ist), stütze deine Antwort darauf und
ordne sie bei Bezug auf früheren/späteren Stoff entsprechend chronologisch
ein (auch noch nicht behandeltes Material, wenn danach gefragt wird – weise
dann kurz darauf hin, dass es im Unterricht noch nicht dran war). Wird KEIN
Material bereitgestellt oder passt keines zur Frage, beantworte sie anhand
deines allgemeinen Wissens – sag in dem Fall kurz, dass sich die Antwort
nicht auf die hochgeladenen Materialien stützt.
Beantworte NUR die gestellte Frage – erkläre oder ergänze nichts, wonach
nicht gefragt wurde. Antworte klar und prägnant in normalem Fließtext
Mathematische Formeln schreibst du in LaTeX zwischen \$…\$ (im Satz) bzw.
\$\$…\$\$ (abgesetzt).
(kein JSON, keine Codefences), in der Sprache der Frage.
''';

  /// Frage-Chat zu den hochgeladenen Materialien eines Fachs (oder, wenn
  /// [materialsContext] weggelassen wird, eine ganz normale Frage ohne
  /// Materialbezug – der Nutzer kann das explizit wählen). Reagiert
  /// ausschließlich auf [question] – wird nie von selbst aufgerufen, siehe
  /// ModuleChatScreen. [materialsContext] kommt aus [ChatContextBuilder] und
  /// enthält bereits alle Materialien chronologisch mit Behandelt-Status,
  /// [history] die letzten Chat-Turns für Rückbezüge ("und was meintest du
  /// vorhin mit...").
  Future<String> answerQuestion({
    required String question,
    String? materialsContext,
    List<({bool isUser, String content})> history = const [],
  }) async {
    final buffer = StringBuffer();
    if (materialsContext != null) {
      buffer
        ..writeln('Verfügbares Material:')
        ..writeln(materialsContext);
    }
    if (history.isNotEmpty) {
      buffer.writeln('Bisheriger Gesprächsverlauf:');
      for (final turn in history) {
        buffer.writeln('${turn.isUser ? 'Ich' : 'Assistent'}: ${turn.content}');
      }
      buffer.writeln();
    }
    buffer.writeln('Meine Frage: $question');
    return _complete(_chatSystemPrompt, buffer.toString());
  }

  static const _pageQuestionSystemPrompt = '''
Du bist ein Lernassistent für Studierende. Du bekommst ein Bild EINER
konkreten Seite eines PDF-Foliensatzes/einer Übungsaufgabe (die Seite, auf
der sich der Nutzer gerade befindet) sowie den vollständigen Text des
GESAMTEN Dokuments als zusätzlichen Kontext – z.B. um Begriffe, Formeln
oder Abkürzungen einzuordnen, die auf einer früheren oder späteren Seite
erklärt werden. Stütze deine Antwort in erster Linie auf das, was auf dem
Bild zu sehen ist (Layout, Diagramme, Formeln, hervorgehobene Stellen –
Dinge, die reiner Text nicht wiedergibt), beziehe den Text-Kontext ein,
wo er die Seite erklärt oder ergänzt. Beantworte AUSSCHLIESSLICH die
gestellte Frage zu dieser Seite – erkläre oder ergänze nichts, wonach
nicht gefragt wurde. Antworte klar und prägnant in normalem Fließtext
Mathematische Formeln schreibst du in LaTeX zwischen \$…\$ (im Satz) bzw.
\$\$…\$\$ (abgesetzt).
(kein JSON, keine Codefences), in der Sprache der Frage.
''';

  /// Zeichenobergrenze für den Volltext-Kontext: hier geht es um Einordnung
  /// der aktuellen Seite, nicht um vollständige Neuverarbeitung des ganzen
  /// Dokuments (wie beim Vorbereiten/Nachbereiten-Modus).
  static const int _pageQuestionDocumentCap = 40000;

  /// Frage-Chat zu EINER KONKRETEN, gerade betrachteten PDF-Seite (siehe
  /// MaterialViewerScreen): [pageImageBytes] ist ein Screenshot genau
  /// dieser Seite (PNG), damit das – zwingend bildfähige, siehe
  /// [AppSettings.visionModelId] – Modell sieht, was der Nutzer gerade vor
  /// sich hat (Diagramme, Formeln, Markierungen), [documentText] der
  /// Volltext des GESAMTEN Materials als zusätzlicher Kontext. Anders als
  /// [answerQuestion] (materialübergreifend, reiner Text) ist dies bewusst
  /// auf EIN Material und EINE Seite fokussiert.
  Future<String> answerPageQuestion({
    required String question,
    required Uint8List pageImageBytes,
    required int pageNumber,
    required int totalPages,
    required String documentText,
    List<({bool isUser, String content})> history = const [],
  }) async {
    final buffer = StringBuffer()
      ..writeln('Aktuelle Seite: $pageNumber von $totalPages')
      ..writeln()
      ..writeln('Volltext des gesamten Dokuments (Kontext):')
      ..writeln(_cap(documentText, _pageQuestionDocumentCap));
    if (history.isNotEmpty) {
      buffer.writeln('\nBisheriger Gesprächsverlauf:');
      for (final turn in history) {
        buffer.writeln('${turn.isUser ? 'Ich' : 'Assistent'}: ${turn.content}');
      }
    }
    buffer.writeln('\nMeine Frage zu Seite $pageNumber: $question');

    final content = [
      {'type': 'text', 'text': buffer.toString()},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,${base64Encode(pageImageBytes)}'},
      },
    ];
    return _complete(_pageQuestionSystemPrompt, content);
  }

  static const _indexSystemPrompt = '''
Du erstellst einen SEHR KURZEN Index-Eintrag für ein Stück Lernmaterial
(Foliensatz oder Übungsaufgabe). Dieser Eintrag hilft später einer anderen
KI-Anfrage zu entscheiden, ob genau dieses Material für eine gestellte
Frage relevant ist, ohne den vollen Text lesen zu müssen. Antworte in 2-4
Sätzen als Fließtext (kein JSON, keine Codefences, keine Einleitung wie
"Hier ist..."): welche Themen/Stichworte werden behandelt, grobe
inhaltliche Kurzfassung. Antworte in der Sprache der Vorlage.
''';

  /// Zeichenobergrenze für den Index-Aufruf: hier geht es nur um den groben
  /// Gist eines Materials, nicht um Vollständigkeit – ein Anriss reicht.
  static const int _indexInputCap = 30000;

  /// Erstellt den Kurz-Index für ein einzelnes Material (siehe
  /// [MaterialItem.topicIndex]). Wird einmalig pro Material aufgerufen und
  /// das Ergebnis dauerhaft gespeichert, nicht bei jeder Frage neu.
  Future<String> summarizeForIndex(String extractedText) async {
    final raw = await _complete(_indexSystemPrompt, _cap(extractedText, _indexInputCap));
    return raw.trim();
  }

  static const _selectRelevantSystemPrompt = '''
Du bekommst einen Index ALLER verfügbaren Lernmaterialien eines Fachs: pro
Material eine ID, ob es im Unterricht bereits behandelt wurde, und eine
kurze Themen-/Inhaltsangabe. Wähle anhand der gestellten Frage (und des
Gesprächsverlaufs, falls vorhanden) aus, welche Materialien man sich im
Detail ansehen müsste, um die Frage gut zu beantworten. Bezieht sich die
Frage auf den Zusammenhang mit früherem oder späterem Stoff, wähle auch
diese Materialien aus (auch noch nicht behandelte, wenn explizit danach
gefragt wird).

Sei dabei GROSSZÜGIG statt zurückhaltend: erkennst du auch nur einen
plausiblen thematischen Bezug zwischen der Frage und einem Material im
Index, wähle es lieber MIT aus – der Nutzer lernt für genau dieses Fach,
ein zusätzliches, am Ende doch nicht gebrauchtes Material kostet nur ein
wenig Kontext, ein fälschlich übergangenes Material liefert dagegen eine
Antwort ohne echten Bezug zu seinem eigenen Material, was sich für ihn wie
ein Fehler anfühlt. Nur wenn die Frage erkennbar NICHTS mit dem Fach zu tun
hat (z.B. reiner Small Talk) oder keines der Materialien im Index
irgendeinen erkennbaren Bezug zeigt, liefere eine leere Liste.

Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text:
{"relevant_ids": ["id1", "id2"]}
''';

  /// Erster Schritt des zweistufigen Frage-Chats: statt bei jeder Frage
  /// alle Materialien im Volltext mitzuschicken, sieht die KI hier zuerst
  /// nur den kompakten Index ([indexContext], siehe
  /// [ChatContextBuilder.buildIndexContext]) und wählt die tatsächlich
  /// relevanten IDs aus. Erst danach wird von genau diesen Materialien der
  /// volle Text nachgeladen (siehe [ChatContextBuilder.build] +
  /// [answerQuestion]).
  Future<List<String>> selectRelevantMaterials({
    required String question,
    required String indexContext,
    List<({bool isUser, String content})> history = const [],
  }) async {
    final buffer = StringBuffer()
      ..writeln('Material-Index:')
      ..writeln(indexContext);
    if (history.isNotEmpty) {
      buffer.writeln('Bisheriger Gesprächsverlauf:');
      for (final turn in history) {
        buffer.writeln('${turn.isUser ? 'Ich' : 'Assistent'}: ${turn.content}');
      }
      buffer.writeln();
    }
    buffer.writeln('Frage: $question');
    final raw = await _complete(_selectRelevantSystemPrompt, buffer.toString());
    final parsed = _parseJsonObject(raw);
    final ids = (parsed['relevant_ids'] as List?)?.map((e) => e.toString()).toList();
    return ids ?? const [];
  }

  static const _highlightSuggestionSystemPrompt = '''
Du bekommst den Text einer Vorlesungsfolie. Finde die wichtigsten
Textstellen und ordne jede EINER von drei Kategorien zu:
- "red": eignet sich gut als Prüfungsfrage (klares, abfragbares Faktenwissen).
- "green": die dazugehörige Antwort bzw. der Kernfakt, der so eine Frage
  beantworten würde.
- "yellow": sonst einfach wichtig/relevant, ohne klare Frage/Antwort-Rolle.

Zitiere jede markierte Stelle EXAKT wie sie im Original vorkommt – keine
Paraphrase, keine Kürzung mit "...", keine Korrektur von Tipp-/OCR-Fehlern –
die Stelle muss im Original per Textsuche wiedergefunden werden können.
Wähle höchstens 12 Stellen, konzentriere dich auf das fachlich Wichtigste.

Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{"highlights": [
  {"text": "exaktes Zitat aus dem Original", "color": "red", "reason": "kurze Begründung"}
]}
Antworte in der Sprache der Vorlage.
''';

  static const int _highlightInputCap = 40000;

  /// Lässt die KI die wichtigsten Textstellen einer Folie vorschlagen und
  /// nach rot (Frage-relevant) / grün (Antwort) / gelb (sonst relevant)
  /// kategorisieren (siehe [MaterialViewerScreen]). Die zurückgegebenen
  /// "text"-Zitate werden anschließend per Text-Matching im PDF wiedergefunden
  /// und dort als Annotation platziert (siehe HighlightMatcher) – bleibt ein
  /// Zitat unauffindbar, zählt es trotzdem als markierter Kontext für die
  /// spätere KI-Weiterverarbeitung, erscheint aber nicht sichtbar im Dokument.
  Future<List<Map<String, dynamic>>> suggestHighlights(String extractedText) async {
    final raw = await _complete(
        _highlightSuggestionSystemPrompt, _cap(extractedText, _highlightInputCap));
    final parsed = _parseJsonObject(raw);
    return (parsed['highlights'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Map<String, dynamic> _parseJsonObject(String raw) {
    // Einfache Backslashes in LaTeX-Formeln ("$\frac…$") wären in JSON
    // Steuerzeichen oder ungültig – vor dem Dekodieren reparieren.
    final candidate = MathMarkup.escapeLatexInJson(_extractJsonBlock(raw));
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('Antwort ist kein JSON-Objekt');
    } catch (e) {
      throw AiServiceException(
          'Antwort der KI konnte nicht als JSON gelesen werden: $e',
          rawResponse: raw);
    }
  }

  static String _extractJsonBlock(String text) {
    var t = text.trim();
    final fenceMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
    if (fenceMatch != null) {
      t = fenceMatch.group(1)!.trim();
    }
    final start = t.indexOf(RegExp(r'[\{\[]'));
    if (start == -1) return t;
    final firstChar = t[start];
    final lastChar = firstChar == '{' ? '}' : ']';
    final end = t.lastIndexOf(lastChar);
    if (end == -1 || end < start) return t;
    return t.substring(start, end + 1);
  }
}
