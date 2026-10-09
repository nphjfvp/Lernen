import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/app_settings.dart';
import '../models/condense.dart';
import '../models/bom_task.dart';
import '../models/crystal_task.dart';
import '../models/sketch_task.dart';
import '../models/flashcard.dart' show QuestionType;
import '../models/formula_sheet.dart';
import '../models/gantt_task.dart';
import '../models/interactive_task.dart';
import '../models/lab_experiment.dart' show LabExperiment, LabFeedback;
import '../models/paper_review.dart';
import '../models/step_task.dart';
import '../models/step_task_review.dart';
import '../models/task_verification.dart';
import 'calc_engine.dart';
import 'calc_plan.dart';
import 'condense_service.dart';
import 'lab_photo_reading.dart';
import 'lab_report_draft.dart';
import 'math_markup.dart';
import 'question_parsing.dart';
import 'text_chunker.dart';

/// Wird geworfen, wenn die KI-Antwort kein (reparierbares) JSON enthält.
/// Trägt die Rohantwort mit, damit die UI sie bei Bedarf anzeigen kann
/// (hilfreich zum Debuggen eines schlecht formatierenden Modells).
/// Eine Schwierigkeitsstufe beim Erstellen von Fragen aus einer Seite (siehe
/// [AiService.generateQuestionsFromPage]): [level] ist der Name der Stufe
/// ("Leicht"/"Mittel"/"Schwer"), [type] null = die KI wählt das Format.
typedef PageQuestionTier = ({String level, QuestionType? type});

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
/// Urteil der KI über eine Lücke eines Lückentexts (siehe
/// [AiService.checkFillBlankAnswers]); [note] ist eine kurze Begründung.
typedef BlankVerdict = ({bool correct, String? note});

/// Urteil der zweiten KI über einen Import (siehe
/// [AiService.verifyImportedQuestions]): die selbst gezählten Fragen im
/// Dokument, Aufgaben, die in der Liste fehlen, und Einträge der Liste, die
/// im Dokument nicht stehen ([kind]: `not_in_document`, `duplicate`,
/// `altered`) – jeweils mit Begründung; [note] für Unsicherheiten.
typedef ImportVerification = ({
  int? documentCount,
  List<({int page, String task, String reason})> missing,
  List<({int n, String kind, String reason})> surplus,
  String note,
});

/// Antwort der KI zu einem Abschnitt beim fortlaufenden Import (siehe
/// [AiService.scanPdfWindow]): die neu gefundenen Fragen (Rohkarten mit
/// "page"), Überarbeitungen bereits übernommener Fragen (Nummer in der
/// mitgeschickten Liste → komplette neue Rohkarte) und die Seiten, die die
/// KI gelesen zu haben meldet (null = keine Angabe).
typedef ScanWindowReply = ({
  List<Map<String, dynamic>> questions,
  Map<int, Map<String, dynamic>> revisions,
  List<int>? pagesSeen,
});

/// Stufe des Originals, Ordnername und die zusätzlichen Fragen (Rohkarten
/// mit "level") zu einer übernommenen Frage (siehe
/// [AiService.expandQuestionStages]).
typedef StageExpansion = ({int? level, String? group, List<Map<String, dynamic>> variants});

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
  /// Gegen geschenkte Fragen – Teil aller Prompts, die selbst Fragen
  /// erstellen (Nutzer-Befund: Zuordnen mit nur einem Paar).
  static const _noGiveawayRule = '''
KEINE GESCHENKTEN FRAGEN – jede selbst erstellte Frage muss man auch falsch
beantworten können:
   - "drag_drop" nur mit mindestens 3 Paaren (verschiedene Ziele),
     "drag_category" nur mit mindestens 2 Kategorien und 4 Begriffen. Gibt
     der Stoff das nicht her (z.B. nur EINE Zuordnung), nimm einen anderen
     Typ (single_choice mit plausiblen falschen Optionen, fill_blank oder
     free_text).
   - "single_choice" mit mindestens 3, "multiple_choice" mit mindestens 4
     Optionen; die falschen Optionen sind plausibel und aus demselben
     Themengebiet (nicht offensichtlich absurd), bei "multiple_choice" ist
     mindestens eine Option falsch.
   - Die Lösung steht nicht schon im Fragetext und lässt sich nicht aus der
     Formulierung ablesen (z.B. kein Lückenwort, das im selben Satz steht).
''';

  /// Markierung von Rechenaufgaben (Schalter "Rechenaufgaben" beim Lernen, siehe
  /// CalcTaskDetector) – in allen Prompts, die Fragen erzeugen oder übernehmen.
  static const _calcFlagRule = '''
RECHENAUFGABEN MARKIEREN: Setze bei jeder Frage "calc": true, wenn man zum
Lösen echt rechnen muss (Taschenrechner, mehrere Rechenschritte, Formeln mit
Messwerten, Einheiten umrechnen) – sonst "calc": false. Kopfrechnen wie 2·3,
das Nennen einer Formel oder reines Wissen ist KEINE Rechenaufgabe.
''';

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
Typ passt: ist eine Tabelle mit kurzen Einträgen auszufüllen, gehört sie
zu "table"; hat sie eine Matrixstruktur, eine Zuordnungsaufgabe, oder
verlangt sie erkennbar mehrere separate Stichpunkte/Kernaussagen als
Antwort, gehört sie zu "html" (siehe unten), NICHT zu "free_text" – auch
wenn das mehr Aufwand bedeutet. Nutze NICHT für alles denselben Typ,
sondern möglichst den spezifischsten:
   - "table": Tabelle ausfüllen. "table" = Liste der Zeilen, jede eine Liste
     der Zellen; vorgegebene Zellen als Text, auszufüllende als
     {"answer": "Lösung; Variante"}.
     {"type": "table", "front": "Vervollständige die Tabelle", "table": [["Begriff", "Merkmal"], ["...", {"answer": "..."}]]}
   - "single_choice": genau eine richtige Antwort unter mehreren Optionen.
     {"type": "single_choice", "front": "Frage", "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]}
   - "multiple_choice": mehrere Antworten gleichzeitig richtig, gleiches Format.
   - "fill_blank": Lückentext. Markiere jede Lücke im "front"-Text mit genau
     drei Unterstrichen "___", "blanks" enthält die Lösungen in derselben
     Reihenfolge (passen mehrere Begriffe in eine Lücke, alle durch ";"
     getrennt in denselben Eintrag). {"type": "fill_blank", "front": "Text mit ___ Lücke", "blanks": ["Lösung; Variante"]}
   - "free_text": offene, aber eindeutig prüfbare Kurzantwort MIT EINER
     EINZELNEN, kompakten Musterlösung (Zahl, Formel, ein Satz). "correctText"
     enthält die Lösung (bei mehreren akzeptierten Formulierungen durch ";"
     getrennt). {"type": "free_text", "front": "Frage", "correctText": "Lösung; Alternative"}
   - "drag_drop": Begriffe einander zuordnen (Paare). "dragPairs" enthält
     {"source","target"}-Paare, jedes "target" genau EINMAL (1:1-Zuordnung) –
     gehören mehrere Begriffe zum selben Ziel, nimm "drag_category".
     {"type": "drag_drop", "front": "Ordne zu", "dragPairs": [{"source": "A", "target": "B"}]}
   - "drag_category": Begriffe in Kategorien einsortieren. "dragPairs" wie bei
     drag_drop, "target" ist hier der Kategoriename (mehrere "source" können
     denselben "target"-Wert haben).
   - "learn": NUR für Aufgaben, die sich in einer Quiz-App gar nicht prüfen
     lassen und in keinen der Typen oben passen: zeichnen, konstruieren,
     entwerfen (z.B. Diagramme, Netzpläne), programmieren, beweisen, lange
     Rechen-/Herleitungswege mit vielen Zwischenschritten. "front" = die
     Aufgabe WORTGETREU wie im Dokument (alle Teilaufgaben und Zahlenwerte,
     NICHT in einzelne Fragen aufteilen), "back" = deine ausführliche
     Erklärung bzw. der Lösungsweg Schritt für Schritt (steht eine
     Musterlösung im Dokument, erkläre sie verständlich). Der Lernende liest
     das und bewertet selbst, wie gut er es verstanden hat. Kein Typ für
     Aufgaben, die sich als Auswahl, Lücke, Tabelle oder Kurzantwort prüfen
     lassen. {"type": "learn", "front": "Aufgabe 1:1", "back": "Erklärung / Lösungsweg"}
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

$_noGiveawayRule
$_calcFlagRule
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
  /// [temperature] 0 für Bewertungen (gleiche Antwort → gleiches Urteil).
  Future<String> _complete(String systemPrompt, Object userContent, {double temperature = 0.3}) async {
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
              'temperature': temperature,
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
      final parsed = _parseJsonObject(raw);
      final points = parsed['key_points'];
      // Felder als Text/Textliste, egal was das Modell liefert – die
      // Oberfläche liest sie so (vorher: Absturz bei z.B. einer Zahl).
      return {
        'title': parsed['title']?.toString().trim() ?? '',
        'overview': parsed['overview']?.toString().trim() ?? '',
        'key_points': [
          if (points is List)
            for (final p in points)
              if (p != null && p.toString().trim().isNotEmpty) p.toString(),
        ],
      };
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

      final chunkTitle = parsed['title']?.toString().trim() ?? '';
      if (chunkTitle.isNotEmpty) title ??= chunkTitle;
      final overview = parsed['overview']?.toString().trim();
      if (overview != null && overview.isNotEmpty) overviewParts.add(overview);
      final rawPoints = parsed['key_points'];
      final points = rawPoints is List ? rawPoints.map((e) => e.toString()) : const <String>[];
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

  static const _formulaSheetSystemPrompt = r'''
Du bist ein Lernassistent für Studierende und erstellst eine FORMELSAMMLUNG zu
Vorlesungsfolien (möglicherweise nur ein Abschnitt eines längeren Foliensatzes)
– so, wie man sie beim Rechnen von Aufgaben und in der Klausur neben sich legt.
Sammle die Formeln, Sätze, Regeln und Verfahrensschritte, die man für dieses
Thema braucht, und ordne JEDEN Eintrag einer Stufe zu ("level"):
- "kern": was in diesen Folien neu eingeführt oder zentral behandelt wird
  (Definitionen, Sätze, Stammfunktionen, Integrationsregeln, Verfahren …). Führt
  die Folie eine Regel neu ein, ist sie "kern" – auch wenn sie in einem anderen
  Zusammenhang eine Hilfsregel wäre.
- "hilfsregel": Regeln aus früheren Themen, die man für die Aufgaben dieses
  Themas anwenden können muss, die die Folien aber NICHT neu einführen. Beispiel:
  Ableitungsregeln (Produkt-, Ketten-, Quotientenregel), weil man sie für
  partielle Integration und Substitution braucht.
- "rechenregel": elementare Rechenregeln, auf denen alles aufbaut: Bruchrechnung,
  Potenz- und Wurzelgesetze, Logarithmusgesetze, binomische Formeln,
  trigonometrische Grundidentitäten.
Denke an die Aufgaben, die zu diesem Thema gestellt werden könnten: Welche
Regeln braucht man, um sie zu lösen? Was dafür nötig ist, aber in den Folien
fehlt, ergänzt du mit "source": "ergaenzt" – aber NUR allgemein bekannte,
sicher gültige Standardregeln. Was auf den Folien steht: "source": "folien".
ERFINDE NICHTS: keine Spezialformeln, keine Zahlenwerte, die du nicht sicher
weißt; bist du bei einer Formel nicht sicher, lass sie weg. Gib jede Formel nur
einmal an.
Gruppiere die Einträge in Abschnitte nach Themen ("sections", z.B.
"Grundintegrale", "Integrationsregeln", "Ableitungsregeln", "Potenzgesetze").
"formula" ist reines LaTeX OHNE umgebende Dollarzeichen; verdopple in JSON jeden
Backslash (z.B. "\\frac{a}{b}"). "note" nennt in einem kurzen Satz Bedingungen
oder wann man die Regel anwendet (darf leer sein).
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences, ohne Text
davor oder danach:
{
  "title": "Kurzer Titel, z.B. Formelsammlung Integralrechnung",
  "sections": [
    {"title": "Integrationsregeln",
     "entries": [
       {"name": "Partielle Integration", "formula": "\\int u\\,v'\\,dx = u\\,v - \\int u'\\,v\\,dx",
        "note": "u, v stetig differenzierbar", "level": "kern", "source": "folien"}
     ]}
  ]
}
Wenn bereits erfasste Formeln aus vorherigen Abschnitten genannt werden,
wiederhole diese NICHT, sondern nimm nur Neues auf.
Antworte in der Sprache der Vorlage.
''';

  /// Formelsammlung aus Vorlesungsfolien (Vorbereiten-Modus). Die KI ordnet jeden
  /// Eintrag einer Stufe zu (Kernstoff, Hilfsregel, Rechenregel, siehe
  /// [FormulaLevel]); welche davon sichtbar sind, bestimmt erst die gewählte
  /// Genauigkeit ([FormulaDetail]) – die Sammlung enthält deshalb immer alles
  /// und lässt sich später ohne neue Anfrage grober oder feiner stellen.
  ///
  /// Lange Foliensätze werden wie bei [generateSummary] abschnittsweise
  /// verarbeitet; jeder weitere Abschnitt bekommt die schon erfassten Formeln,
  /// und die Ergebnisse werden zusammengeführt (gleiche Formeln nur einmal).
  Future<({String title, FormulaSheet sheet})> generateFormulaSheet(
    String slidesText, {
    ChunkGranularity granularity = ChunkGranularity.auto,
    bool rollingContext = true,
    FormulaDetail detail = FormulaDetail.mittel,
    void Function(int done, int total)? onProgress,
  }) async {
    final chunks = _chunksFor(slidesText, granularity);
    var sheet = FormulaSheet(detail: detail);
    String? title;
    final rawResponses = <String>[];

    for (var i = 0; i < chunks.length; i++) {
      final known = [for (final s in sheet.sections) for (final e in s.entries) e.name];
      final contextNote = chunks.length > 1 && rollingContext && known.isNotEmpty
          ? '\n\nBereits erfasste Formeln aus vorherigen Abschnitten (NICHT wiederholen):\n'
              '- ${known.take(_rollingContextLimit * 3).join('\n- ')}'
          : '';
      final header = chunks.length == 1
          ? 'Vorlesungsfolien:\n\n'
          : 'Dies ist Abschnitt ${i + 1} von ${chunks.length} eines längeren Foliensatzes.'
              '$contextNote\n\nAbschnitt-Text:\n\n';
      final raw = await _complete(_formulaSheetSystemPrompt, '$header${chunks[i]}', temperature: 0.2);
      rawResponses.add(raw);
      final parsed = _parseJsonObject(raw);
      final chunkTitle = parsed['title']?.toString().trim() ?? '';
      if (chunkTitle.isNotEmpty) title ??= chunkTitle;
      sheet = sheet.merged(FormulaSheet.fromMap({...parsed, 'detail': detail.name}));
      onProgress?.call(i + 1, chunks.length);
    }

    if (sheet.totalCount == 0) {
      throw AiServiceException(
        'Die KI hat in den Folien keine Formeln gefunden – enthalten sie keine Formeln, '
        'oder das Modell hat nicht im erwarteten Format geantwortet. Bitte erneut versuchen.',
        rawResponse: rawResponses.join('\n\n'),
      );
    }
    return (title: (title == null || title.isEmpty) ? 'Formelsammlung' : title, sheet: sheet);
  }

  // -- Kürzen -----------------------------------------------------------------

  static const _condenseAnalysisSystemPrompt = r'''
Du hilfst Studierenden, eine Vorlesung auf das Nötige zu kürzen. Du bekommst
Übungsaufgaben (möglicherweise nur einen Teil davon) und/oder einen Auftrag des
Studierenden. Stelle fest, WAS man wissen und können muss, um diese Aufgaben zu
lösen bzw. den Auftrag zu erfüllen: Verfahren, Definitionen, Sätze, Formeln,
Begriffe, Rechenregeln und Grundlagen aus früheren Themen, die die Aufgaben
stillschweigend voraussetzen (z.B. Ableitungsregeln für die partielle
Integration).
- Eine Anforderung ist ein kurzer Satz, z.B. "Partielle Integration: Formel und
  wann man sie anwendet".
- Eine Anforderung pro Sache, keine Dopplungen; nicht zu fein (keine
  Einzelschritte einer Rechnung) und nicht zu grob ("Mathematik").
- Erfinde keine Aufgaben. Gibt es keine Aufgaben, leite die Anforderungen aus
  dem Auftrag ab.
"tasks" nennt jede Aufgabe in einer Zeile (z.B. "Aufgabe 2: ∫ x·eˣ dx
berechnen"); bei sehr vielen Aufgaben fasse sie zusammen.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences, ohne Text
davor oder danach:
{"tasks": ["Aufgabe 1: …"], "needs": ["Partielle Integration: Formel und wann man sie anwendet"]}
Wenn bereits erfasste Anforderungen genannt werden, wiederhole sie NICHT.
Antworte in der Sprache der Aufgaben.
''';

  static const _condenseSelectSystemPrompt = r'''
Du hilfst Studierenden, eine Vorlesung zu KÜRZEN: Das gekürzte Skript soll nur
noch enthalten, was man braucht, um bestimmte Übungsaufgaben zu lösen – alle
Erklärungen dazu vollständig, den Rest nicht. Du bekommst einen Abschnitt der
Vorlesung in Blöcken ("[12.3] Text" ist Block 3 der Seite 12) sowie, was die
Aufgaben verlangen.
Du schreibst NICHTS um und erfindest nichts: Du wählst nur Blöcke aus, die
behalten werden.
Behalte ("kind": "erklaerung"), was zum Verstehen und Lösen nötig ist, und zwar
so vollständig, dass die Erklärung für sich lesbar bleibt: Definitionen und
Schreibweisen, Begründungen und Herleitungen, Sätze und Formeln samt
Voraussetzungen, Verfahren Schritt für Schritt, Hinweise auf typische Fehler.
Reiße keine Formel aus ihrem Zusammenhang – nimm den Block mit, der ihre
Bezeichnungen erklärt. Ein Beispiel, das man braucht, um das Verfahren zu
verstehen, ist "erklaerung".
Beispielaufgaben und Musterlösungen der Vorlesung, die in die Richtung der
Aufgaben gehen, die man zum Verstehen aber nicht braucht, bekommen
"kind": "beispiel" (der Studierende entscheidet später, ob sie mitkommen).
Lasse weg: Organisatorisches, Inhaltsverzeichnisse, Motivation, Geschichte und
Ausblicke, reine Wiederholungen und Zusammenfassungen, Stoff ohne Bezug zu den
Aufgaben, Literaturhinweise.
Fasse zusammenhängende Blöcke zu Abschnitten mit kurzer Überschrift ("title")
zusammen. "why" sagt in einem kurzen Satz, wofür der Abschnitt gebraucht wird
(z.B. "Aufgabe 2 braucht die Substitution"). "covers" nennt die Kennungen der
Anforderungen ("n1", "n2" …), die der Abschnitt erklärt. "blocks" ist eine Liste
von Kennungen oder Bereichen ("12.1-12.4", auch über Seiten hinweg:
"12.3-13.2") – NUR Kennungen aus DIESEM Abschnitt der Vorlesung. "skipped" nennt
in Stichworten, was du in diesem Abschnitt bewusst weggelassen hast.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences, ohne Text
davor oder danach:
{"sections": [{"title": "Partielle Integration", "kind": "erklaerung",
  "why": "Aufgabe 2 und 4", "blocks": ["12.1-12.4", "13.2"], "covers": ["n1"]}],
 "skipped": ["Organisatorisches", "Geschichte der Integralrechnung"]}
Ist in diesem Abschnitt nichts Relevantes, antworte mit {"sections": [], "skipped": [...]}.
Antworte in der Sprache der Vorlesung.
''';

  static String _strictnessText(CondenseStrictness strictness) => switch (strictness) {
        CondenseStrictness.knapp =>
          'Strenge: KNAPP – behalte nur, was die Aufgaben direkt brauchen; im Zweifel weglassen.',
        CondenseStrictness.ausgewogen =>
          'Strenge: AUSGEWOGEN – behalte das Nötige samt dem Zusammenhang, den man zum Verstehen braucht; Randthemen weglassen.',
        CondenseStrictness.grosszuegig =>
          'Strenge: GROSSZÜGIG – im Zweifel behalten, damit nichts fehlt, was beim Lösen helfen könnte.',
      };

  /// Was man können muss, um die Übungsaufgaben ([exercisesText], darf leer
  /// sein) bzw. den Auftrag ([task]) zu erfüllen – Grundlage der Auswahl in
  /// [condenseLecture]. Lange Aufgabentexte werden abschnittsweise ausgewertet
  /// und die Anforderungen zusammengeführt.
  Future<CondensePlan> analyzeCondenseTasks({
    required String task,
    String exercisesText = '',
    ChunkGranularity granularity = ChunkGranularity.auto,
    bool rollingContext = true,
  }) async {
    final chunks = exercisesText.trim().isEmpty ? [''] : _chunksFor(exercisesText, granularity);
    final needTexts = <String>[];
    final tasks = <String>[];
    final raws = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final known = CondenseService.mergeNeeds(needTexts);
      final b = StringBuffer();
      if (task.trim().isNotEmpty) b.writeln('Auftrag des Studierenden: ${task.trim()}\n');
      if (chunks[i].trim().isEmpty) {
        b.writeln('Es wurden keine Übungsaufgaben hochgeladen.');
      } else {
        if (chunks.length > 1) {
          b.writeln('Dies ist Abschnitt ${i + 1} von ${chunks.length} der Übungsaufgaben.');
          if (rollingContext && known.isNotEmpty) {
            b.writeln('Bereits erfasste Anforderungen (NICHT wiederholen):');
            for (final n in known.take(_rollingContextLimit * 2)) {
              b.writeln('- ${n.text}');
            }
          }
          b.writeln();
        }
        b.writeln('Übungsaufgaben:\n\n${chunks[i]}');
      }
      final raw = await _complete(_condenseAnalysisSystemPrompt, b.toString(), temperature: 0.1);
      raws.add(raw);
      final parsed = _parseJsonObject(raw);
      List<String> strings(Object? v) => [
            if (v is List)
              for (final e in v)
                if (e is Map ? '${e['text'] ?? e['title'] ?? ''}'.trim().isNotEmpty : '$e'.trim().isNotEmpty)
                  e is Map ? '${e['text'] ?? e['title']}'.trim() : '$e'.trim(),
          ];
      needTexts.addAll(strings(parsed['needs'] ?? parsed['anforderungen']));
      tasks.addAll(strings(parsed['tasks'] ?? parsed['aufgaben']));
    }
    final needs = CondenseService.mergeNeeds(needTexts);
    if (needs.isEmpty && exercisesText.trim().isNotEmpty) {
      throw AiServiceException(
        'Aus den Übungsaufgaben ließ sich nicht ableiten, was man dafür können muss – '
        'das Modell hat nicht im erwarteten Format geantwortet. Bitte erneut versuchen.',
        rawResponse: raws.join('\n\n'),
      );
    }
    return CondensePlan(tasks: tasks.take(40).toList(), needs: needs);
  }

  /// Geht die Vorlesung ([pages], siehe CondenseService) abschnittsweise durch
  /// und wählt die Blöcke aus, die man für die Aufgaben braucht. Die KI schreibt
  /// nichts um – das gekürzte Dokument besteht aus Originaltext. Jeder weitere
  /// Abschnitt bekommt (Rolling-Kontext) die schon abgedeckten und die noch
  /// offenen Anforderungen sowie die bisher behaltenen Überschriften, damit
  /// nichts doppelt behalten wird und die KI gezielt nach Fehlendem sucht.
  ///
  /// [plan] aus [analyzeCondenseTasks]; ohne Plan wird er hier erstellt.
  Future<CondenseSelection> condenseLecture({
    required List<CondensePage> pages,
    required String task,
    String exercisesText = '',
    CondensePlan? plan,
    CondenseStrictness strictness = CondenseStrictness.ausgewogen,
    ChunkGranularity granularity = ChunkGranularity.auto,
    bool rollingContext = true,
    void Function(String what, int done, int total)? onProgress,
  }) async {
    final totalLength = pages.fold<int>(0, (sum, p) => sum + p.length);
    final chunks = CondenseService.group(pages, TextChunker.chunkSizeFor(granularity, totalLength));
    if (chunks.isEmpty) {
      throw AiServiceException('In der Vorlesung wurde kein Text gefunden (gescannt ohne Text-Ebene?).');
    }

    onProgress?.call('Übungsaufgaben auswerten', 0, chunks.length);
    final analysis = plan ??
        await analyzeCondenseTasks(
          task: task,
          exercisesText: exercisesText,
          granularity: granularity,
          rollingContext: rollingContext,
        );

    final sections = <CondenseSection>[];
    final skipped = <String>[];
    final raws = <String>[];
    final covered = <String>{};
    final validNeeds = {for (final n in analysis.needs) n.id};

    for (var i = 0; i < chunks.length; i++) {
      final group = chunks[i];
      final range = group.length == 1
          ? '${group.first.label} ${group.first.number}'
          : '${group.first.label} ${group.first.number}–${group.last.number}';
      onProgress?.call('Vorlesung durchgehen: $range', i, chunks.length);

      final b = StringBuffer()..writeln(_strictnessText(strictness))..writeln();
      if (task.trim().isNotEmpty) b.writeln('Auftrag des Studierenden: ${task.trim()}\n');
      if (analysis.needs.isNotEmpty) {
        b.writeln('Was die Aufgaben verlangen:');
        for (final n in analysis.needs) {
          b.writeln('${n.id}: ${n.text}');
        }
        b.writeln();
      }
      if (chunks.length > 1) {
        b.writeln('Dies ist Abschnitt ${i + 1} von ${chunks.length} der Vorlesung ($range).');
        if (rollingContext && i > 0) {
          final done = [for (final n in analysis.needs) if (covered.contains(n.id)) n.id];
          final open = [for (final n in analysis.needs) if (!covered.contains(n.id)) n.id];
          if (done.isNotEmpty) b.writeln('Schon in früheren Abschnitten erklärt: ${done.join(', ')}.');
          if (open.isNotEmpty) b.writeln('Noch nicht gefunden: ${open.join(', ')} – suche gezielt danach.');
          final titles = [for (final s in sections) s.title];
          if (titles.isNotEmpty) {
            b.writeln('Bisher behaltene Abschnitte: ${titles.reversed.take(_rollingContextLimit).toList().reversed.join('; ')}.');
          }
        }
        b.writeln();
      }
      b.writeln('Vorlesung:\n\n${CondenseService.render(group)}');

      final ordered = CondenseService.idsOf(group);
      Map<String, dynamic> parsed;
      try {
        final raw = await _complete(_condenseSelectSystemPrompt, b.toString(), temperature: 0.1);
        raws.add(raw);
        parsed = _parseJsonObject(raw);
      } on AiServiceException {
        // Ein Abschnitt, der nicht lesbar war, wird einmal wiederholt.
        final raw = await _complete(_condenseSelectSystemPrompt, b.toString(), temperature: 0.1);
        raws.add(raw);
        parsed = _parseJsonObject(raw);
      }
      final rawSections = parsed['sections'] ?? parsed['abschnitte'];
      for (final entry in (rawSections is List ? rawSections : const [])) {
        final section = CondenseService.parseSection(entry, ordered);
        if (section == null) continue;
        final checked = CondenseSection(
          title: section.title,
          kind: section.kind,
          why: section.why,
          blockIds: section.blockIds,
          covers: [for (final c in section.covers) if (validNeeds.contains(c)) c],
        );
        sections.add(checked);
        covered.addAll(checked.covers);
      }
      final rawSkipped = parsed['skipped'] ?? parsed['weggelassen'];
      if (rawSkipped is List) {
        for (final e in rawSkipped) {
          final t = '$e'.trim();
          if (t.isNotEmpty && !skipped.contains(t)) skipped.add(t);
        }
      }
      onProgress?.call('Vorlesung durchgehen: $range', i + 1, chunks.length);
    }

    if (sections.isEmpty) {
      throw AiServiceException(
        'Die KI hat in der Vorlesung nichts gefunden, was zu den Aufgaben passt – oder nicht im erwarteten '
        'Format geantwortet. Prüfe die Aufgaben und den Auftrag, oder stelle die Strenge auf "Großzügig".',
        rawResponse: raws.join('\n\n'),
      );
    }
    return CondenseSelection(sections: sections, skipped: skipped.take(30).toList(), plan: analysis);
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
diesen Typ, den Rest möglichst mit den spezifischeren Typen unten. Auch
"free_text" ist kein Standardtyp: "flashcard" und "free_text" ZUSAMMEN
höchstens etwa ein Drittel der Karten; der Rest verteilt sich auf
Auswahl-, Lücken-, Zuordnungs- und (wo sinnvoll) interaktive Fragen.
Übungsaufgaben mit fester Aufgabenform (Ankreuzen, Lücken, Zuordnen,
Tabelle) behalten diese Form. Wähle pro Frage den zum Inhalt passenden Typ:
   - "table": eine Tabelle zum Ausfüllen (auch gut für "schwer": Merkmale
     mehrerer Begriffe gegenüberstellen). "table" = Liste der Zeilen, jede
     eine Liste der Zellen; vorgegebene Zellen als Text, auszufüllende als
     {"answer": "Lösung; Variante"}.
   - "single_choice": klares Faktenwissen mit genau einer richtigen Antwort.
   - "multiple_choice": wenn mehrere Aussagen gleichzeitig zutreffen können.
   - "fill_blank": Lückentext – markiere jede Lücke im "front"-Text mit genau
     drei Unterstrichen "___", "blanks" enthält die Lösungen in derselben
     Reihenfolge (passen mehrere Begriffe in eine Lücke, alle durch ";"
     getrennt in denselben Eintrag).
   - "free_text": offene, aber eindeutig prüfbare Kurzantwort; "correctText"
     enthält die Lösung (bei mehreren akzeptierten Formulierungen durch ";"
     getrennt).
   - "drag_drop": Begriffe einander zuordnen (Paare); "dragPairs" enthält
     {"source","target"}-Paare, jedes "target" genau EINMAL (1:1-Zuordnung) –
     gehören mehrere Begriffe zum selben Ziel, nimm "drag_category".
   - "drag_category": Begriffe in Kategorien einsortieren; "dragPairs" wie
     bei drag_drop, "target" ist hier der Kategoriename (mehrere "source"
     können denselben "target"-Wert haben).
   - "learn": NUR für Aufgaben, die sich in einer Quiz-App gar nicht prüfen
     lassen und in keinen der Typen oben passen: zeichnen, konstruieren,
     entwerfen (z.B. Diagramme, Netzpläne), programmieren, beweisen, lange
     Rechen-/Herleitungswege mit vielen Zwischenschritten. "front" = die
     Aufgabe WORTGETREU wie im Dokument (alle Teilaufgaben und Zahlenwerte,
     NICHT in einzelne Fragen aufteilen), "back" = deine ausführliche
     Erklärung bzw. der Lösungsweg Schritt für Schritt (steht eine
     Musterlösung im Dokument, erkläre sie verständlich). Der Lernende liest
     das und bewertet selbst, wie gut er es verstanden hat. Kein Typ für
     Aufgaben, die sich als Auswahl, Lücke, Tabelle oder Kurzantwort prüfen
     lassen. {"type": "learn", "front": "Aufgabe 1:1", "back": "Erklärung / Lösungsweg"}
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

$_noGiveawayRule
$_calcFlagRule
JEDER Eintrag in "flashcards" MUSS ALLE für seinen "type" nötigen Felder
enthalten (siehe Beispiele unten) – ein Eintrag mit nur "front" und sonst
nichts ist ungültig und wird verworfen.

SCHWIERIGKEITSSTUFEN: Frage jeden wichtigen Sachverhalt in bis zu drei
Stufen ab – die App fragt erst "leicht" ab, erst wenn das sitzt "mittel",
dann "schwer" (vorher kommen die schwereren nicht dran):
   - "leicht": Wiedererkennen (meist single_choice/multiple_choice),
   - "mittel": Ergänzen oder Zuordnen (meist fill_blank/drag_drop/
     drag_category),
   - "schwer": selbst formulieren bzw. anwenden, so wie in der Klausur
     (meist free_text, bei Übungsaufgaben mit fester Form auch deren Form).
Gib JEDER Karte "level": "leicht" | "mittel" | "schwer" und "group": einen
kurzen Schlüssel für den Sachverhalt (z.B. "Stücklisten-Arten"), der für
alle Stufen DESSELBEN Sachverhalts Zeichen für Zeichen gleich ist und sich
von anderen Sachverhalten unterscheidet. Dieselbe "group" nur für Fragen,
die dasselbe Wissen prüfen – sobald die schwerere Stufe dran ist, wird die
leichtere nicht mehr abgefragt; verschiedene Fakten desselben Kapitels
bekommen verschiedene Gruppen. Lass eine Stufe weg, wenn sie für
den Sachverhalt keinen Sinn ergibt (z.B. keine sinnvolle Auswahlfrage) –
dann rückt die nächste Stufe nach. Übungsaufgaben, die 1:1 übernommen
werden, sind "schwer".

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
    {"type": "single_choice", "front": "Frage", "level": "leicht", "group": "Sachverhalt A",
     "conceptTitle": "Konzeptname",
     "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]},
    {"type": "fill_blank", "front": "Text mit ___ Lücke", "blanks": ["Lösung"],
     "level": "mittel", "group": "Sachverhalt A", "conceptTitle": "Konzeptname"},
    {"type": "free_text", "front": "Frage", "correctText": "Lösung; Alternative",
     "level": "schwer", "group": "Sachverhalt A", "conceptTitle": "Konzeptname"},
    {"type": "multiple_choice", "front": "Frage", "level": "leicht", "group": "Sachverhalt B",
     "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]},
    {"type": "table", "front": "Vervollständige die Tabelle", "level": "schwer", "group": "Sachverhalt B",
     "table": [["Begriff", "Merkmal"], ["...", {"answer": "Lösung; Variante"}]]},
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

      for (final c in _mapsIn(parsed['concepts'])) {
        final title = (c['title'] ?? '').toString().trim();
        if (title.isNotEmpty && seenConceptTitles.add(title)) {
          concepts.add(c);
        }
      }
      flashcards.addAll(_mapsIn(parsed['flashcards']));
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

$_noGiveawayRule
$_calcFlagRule

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
  2b. Ist eine Tabelle mit kurzen Einträgen auszufüllen? -> "table":
     {"type": "table", "front": "...", "table": [["Kopf A", "Kopf B"],
     ["vorgegeben", {"answer": "Lösung; Variante"}]]} – vorgegebene Zellen
     als Text, auszufüllende als {"answer": ...}, Zeilen/Spalten wie im
     Original.
  3. Hat die Frage eine Matrixstruktur (mehrere Kriterien-Zeilen,
     pro Zeile eine von mehreren Spalten/Kategorien zuordnen), eine
     Zuordnungsaufgabe (Begriff <-> Begriff/Kategorie per Linie/Pfeil), oder
     verlangt sie erkennbar mehrere separate Stichpunkte/Kernaussagen als
     Antwort (bei denen ein einziger Textvergleich zu starr wäre)? -> "html"
     (siehe unten) – NICHT in eine vereinfachte free_text-Frage umwandeln,
     nur weil das weniger Aufwand bedeutet.
  3b. Ist es eine Aufgabe, die sich in einer Quiz-App gar nicht prüfen lässt
     (zeichnen, konstruieren, entwerfen, programmieren, beweisen, langer
     Rechenweg mit vielen Zwischenschritten)? -> "learn": "front" = die
     Aufgabe WORTGETREU mit allen Teilaufgaben und Zahlenwerten (NICHT
     aufteilen), "back" = deine ausführliche Erklärung/der Lösungsweg
     Schritt für Schritt. Dafür ist keine Musterlösung im Dokument nötig –
     du erklärst die Aufgabe selbst.
  4. Erst wenn NICHTS davon zutrifft und es sich um eine wirklich offene
     Frage mit einer einzelnen, kurzen erwarteten Antwort handelt (Zahl,
     Formel, ein Satz): "free_text".
   - "single_choice": Original ist Multiple-Choice mit genau einer richtigen
     Antwort. Antwortformat: {"type": "single_choice", "front": "...",
     "options": [{"text": "...", "isCorrect": true}, ...]}
   - "multiple_choice": mehrere Antworten gleichzeitig richtig, analog.
   - "fill_blank": Lückentext im Original. Markiere jede Lücke im
     "front"-Text mit genau drei Unterstrichen "___", "blanks" enthält die
     Lösungen in derselben Reihenfolge (mehrere akzeptierte Begriffe einer
     Lücke durch ";" getrennt in denselben Eintrag).
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
diese Frage (keine Karte ohne bekannte Antwort erzeugen) – außer bei "learn":
dort erklärst du die Aufgabe selbst.

Prüfe VOR der Wahl, ob du den gewählten Typ wirklich vollständig ausfüllen
kannst (single_choice/multiple_choice: mindestens 2 Optionen, genau die
richtige(n) markiert; html: der exakte postMessage-Aufruf ist enthalten;
free_text: "correctText" ist nicht leer) – bist du dir nicht sicher, wähle
lieber den nächstpassenden Typ, den du sicher vollständig befüllen kannst,
statt einen Typ zu behaupten, den du nur halb ausfüllst: eine unvollständige
Angabe wird sonst automatisch auf eine einfache Karteikarte zurückgestuft.

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{"flashcards": [
  {"type": "single_choice", "front": "Originalfrage", "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]}
]}
$_calcFlagRule
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
      flashcards.addAll(_mapsIn(parsed['flashcards']));
      onProgress?.call(i + 1, chunks.length);
    }
    return flashcards;
  }

  static const _scanPdfQuestionsSystemPrompt = '''
Du bekommst einige Seiten eines Dokuments (Folien, Übungsblatt, Altklausur,
Skript …). Deine Aufgabe: Finde die Fragen und Aufgaben, die auf diesen
Seiten TATSÄCHLICH stehen, und übernimm sie 1:1 als Quizfragen – in derselben
Aufgabenform wie im Original. Erfinde KEINE neuen Fragen.

WELCHE FRAGEN: {{SCOPE}}
{{ROLLING}}
Übernimm jede Frage möglichst im Originalwortlaut; kürze nur, was für eine
Quizfrage nötig ist. Eine Aufgabe mit Teilaufgaben (a, b, c …) wird zu
mehreren Fragen – jede so formuliert, dass sie ohne die anderen verständlich
ist (nötigen Kontext aus dem Aufgabentext übernehmen). Dieselbe Frage nur
einmal, auch wenn sie mehrfach vorkommt.

ABBILDUNGEN: {{FIGURES}}

LÖSUNG: Steht die Lösung im Dokument (Musterlösung, Lösungsteil,
angekreuzte/markierte Antwort, Auflösung auf einer der Seiten), übernimm sie
und setze "solutionFromDocument": true. {{MISSING}}

TYP – übernimm die Aufgabenform des Originals. "free_text" ist NICHT der
Auffangtyp für alles; prüfe der Reihe nach:
1. Antwortoptionen zum Ankreuzen vorgegeben (auch "richtig/falsch" zu EINER
   Aussage) -> "single_choice" (genau eine richtig) bzw. "multiple_choice":
   "options": [{"text": "...", "isCorrect": true}, …]
2. Lückentext -> "fill_blank": jede Lücke im "front" als "___", "blanks" = die
   Lösungen in derselben Reihenfolge (mehrere richtige Varianten einer Lücke
   mit ";" in einem Eintrag).
3. Zuordnen (Begriff <-> Begriff, Linien/Pfeile verbinden) -> "drag_drop":
   "dragPairs": [{"source": "...", "target": "..."}]. Einordnen in Kategorien
   (mehrere Begriffe je Kategorie) -> "drag_category" mit denselben
   "dragPairs" (target = Kategorie).
4. {{LABEL_RULE}}
5. Tabelle ausfüllen (Zellen mit kurzen Einträgen) -> "table": "table" =
   Liste der Zeilen, jede Zeile eine Liste der Zellen; vorgegebene Zellen
   (Kopfzeile, Zeilentitel, schon ausgefüllte Werte) als Text, auszufüllende
   als {"answer": "Lösung; Variante"} – genau wie im Original, gleiche Zeilen
   und Spalten. Beispiel: {"type": "table", "front": "Vervollständige die
   Tabelle", "table": [["Begriff", "Merkmal"], ["Stückliste", {"answer":
   "..."}]]}
6. Wahr/Falsch-Matrix mit mehreren Aussagen, Reihenfolge ordnen, mehrere
   Eingabefelder (z.B. Rechenweg mit Zwischenergebnissen) oder eine Aufgabe,
   deren Lösung aus mehreren getrennten Kernpunkten besteht -> "html" (siehe
   HTML) – NICHT zu free_text vereinfachen.
7. Kurze Antwort (Begriff, Zahl, Formel, ein Satz) -> "free_text":
   "correctText": "..." (mehrere akzeptierte Varianten mit ";").
8. Aufgabe, die sich in einer Quiz-App gar nicht prüfen lässt (zeichnen,
   konstruieren, entwerfen, z.B. Diagramm oder Netzplan erstellen,
   programmieren, beweisen, langer Rechenweg mit vielen Zwischenschritten)
   -> "learn": "front" = die Aufgabe WORTGETREU wie auf dem Blatt mit allen
   Teilaufgaben und Zahlenwerten (NICHT in Teilaufgaben aufteilen, 1:1),
   "back" = deine ausführliche Erklärung bzw. der Lösungsweg Schritt für
   Schritt (steht eine Musterlösung im Dokument, erkläre sie verständlich
   und setze "solutionFromDocument": true; sonst erklärst du selbst und
   setzt false). Gib "imageBox" um die KOMPLETTE Aufgabe an, wie sie auf der
   Seite steht (samt Abbildungen). {"type": "learn", "front": "...",
   "back": "...", "imageBox": [0.05, 0.2, 0.95, 0.6]}
9. Längere Erklär- oder Diskussionsaufgabe ohne kurze Antwort, die man
   nicht als Aufgabe "durcharbeiten" muss -> "flashcard": "back":
   Musterlösung, knapp und vollständig.
Prüfe VOR der Wahl, ob du den Typ wirklich vollständig ausfüllen kannst
(single_choice/multiple_choice: mindestens 2 Optionen, genau die richtige(n)
markiert; html: der exakte postMessage-Aufruf ist enthalten; free_text:
"correctText" ist nicht leer; table: mindestens eine Zelle mit "answer") – bist du dir nicht sicher, wähle lieber den
nächstpassenden Typ, den du sicher vollständig befüllen kannst, statt einen
Typ zu behaupten, den du nur halb ausfüllst: eine unvollständige Angabe wird
sonst automatisch auf eine einfache Karteikarte zurückgestuft.

HTML: "htmlContent" enthält NUR den <body>-Inhalt (kein
<html>/<head>/<style>-Rahmen) als eigenständige, interaktive Seite: reines
Inline-HTML/CSS/JS, kein externes Skript/Bild, keine Netzwerk-Anfrage. Die
Seite enthält ihre eigene Prüf-Logik (die Lösung kennst du) und ruft beim
Auswerten GENAU das auf:
window.FlutterAnswer.postMessage(JSON.stringify({correct: true}))
(bzw. correct: false) – ohne diesen Aufruf bekommt die App kein Ergebnis.
Offene Teile großzügig prüfen (Kernbegriffe, Groß-/Kleinschreibung egal).
Gib zusätzlich "front"/"back" als kurze Text-Fassung an.

Jede Frage bekommt "page" = ihre Seitenzahl im GESAMTEN Dokument (die
Zuordnung steht in der Nachricht).

Mathematische Formeln schreibst du in LaTeX: \$…\$ im Satz, \$\$…\$\$ für
abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash (z.B.
"\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences und ohne
Text davor oder danach:
{"pages": [{"page": 3, "tasks": 2}], "questions": [{"page": 3, "type": "single_choice", "front": "...", "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}], "solutionFromDocument": true}{{EXAMPLE}}]{{REVISIONS_FORMAT}}}
"pages" nennt JEDE gezeigte Seite mit der Zahl der Aufgaben, die du dort
gefunden hast (auch 0) – so lässt sich prüfen, dass du alle Seiten gelesen
hast. Stehen auf den Seiten keine passenden Fragen: "questions": [].
$_calcFlagRule
Antworte in der Sprache des Dokuments.
''';

  /// Zusatz für Abschnitte, die mit der letzten Seite des vorigen beginnen
  /// (fortlaufender Import, siehe [scanPdfWindow]).
  static const _scanRollingRules = '''

FORTLAUFENDER IMPORT: Das Dokument wird in überlappenden Abschnitten gelesen.
Die ERSTE gezeigte Seite (Dokument-Seite {{OVERLAP}}) ist die letzte des
vorigen Abschnitts und dort schon bearbeitet – sie ist nur dabei, damit du sie
zusammen mit den neuen Seiten liest. Alle weiteren Seiten sind NEU.
- Fragen auf den NEUEN Seiten übernimmst du wie oben unter "questions".
- Aus Seite {{OVERLAP}} wurden schon Fragen übernommen (Liste in der
  Nachricht). Übernimm sie NICHT noch einmal.
- Prüfe für jede dieser Fragen, ob auf den neuen Seiten etwas steht, das zu ihr
  gehört und beim Übernehmen gefehlt hat: die Aufgabe geht weiter (weitere
  Teilaufgaben, Fortsetzung von Aufgabentext oder Tabelle), die Lösung bzw.
  Musterlösung steht erst dort, eine zugehörige Abbildung, fehlende Angaben.
  Dann liefere sie VOLLSTÄNDIG überarbeitet unter "revisions":
  {"n": <Nummer aus der Liste>, "question": {komplette Frage im selben Format
  wie oben}}. Fehlte nichts, lass sie aus "revisions" heraus – die Frage bleibt
  dann unverändert. Ändere nichts ohne Grund.
- Beginnt auf Seite {{OVERLAP}} eine Aufgabe, die dort noch NICHT übernommen
  wurde (weil sie erst auf den neuen Seiten vollständig wird), übernimm sie
  jetzt als neue Frage mit "page": {{OVERLAP}}.
''';

  static const _scanFiguresFromImages =
      'Du siehst jede Seite als Bild. Am Rand steht eine Skala von 0 bis 1 '
      '(links/oben = 0, rechts/unten = 1) zum Ablesen von Positionen; dazu '
      'kommt – falls vorhanden – der Text der Seite für den genauen Wortlaut '
      'und Formeln. Gehört zu einer Frage eine Abbildung, Grafik, Tabelle, '
      'Schaltung, Diagramm, Code- oder Formelbild, das man zum Beantworten '
      'sehen muss, gib "imageBox": [links, oben, rechts, unten] an – ihren '
      'Bereich auf der Seite (Werte 0–1, lieber etwas zu groß als '
      'abgeschnitten). Die App schneidet genau diesen Bereich aus und zeigt '
      'ihn mit der Frage; beschreibe die Abbildung dann nicht zusätzlich. '
      'Keine imageBox für reinen Text, der schon in der Frage steht. Steht in '
      'der Abbildung die Lösung (z.B. ausgefüllte Beschriftungen in einer '
      'Musterlösung), gib "imageCovers": [[links, oben, rechts, unten], …] an '
      '(Seitenkoordinaten) – diese Stellen werden abgedeckt.';

  static const _scanFiguresFromPdf =
      'Bezieht sich eine Frage auf eine Abbildung, beschreibe das Nötige kurz '
      'in eckigen Klammern in der Frage selbst; lässt sie sich ohne die '
      'Abbildung gar nicht beantworten, lass sie weg.';

  static const _scanLabelFromImages =
      'Abbildung beschriften (Stellen in einer Abbildung benennen) -> '
      '"diagram_label": "imageBox" = die Abbildung, "targets": [{"box": [links, '
      'oben, rechts, unten], "label": "..."}] – box = die Stelle, an die die '
      'Beschriftung gehört, in Seitenkoordinaten wie imageBox; Stellen, deren '
      'Reihenfolge egal ist, bekommen dieselbe "group". Eine Stelle in der '
      'Abbildung markieren/ankreuzen -> "mark_image": "imageBox" und '
      '"targets": [{"box": [...]}] = die richtige(n) Stelle(n).';

  static const _scanLabelFromPdf =
      'Abbildung beschriften mit nummerierten Stellen -> "drag_drop" (Nummer '
      'der Stelle -> Begriff), die Abbildung kurz in eckigen Klammern '
      'beschreiben.';

  static const _scanScopeEvery =
      'JEDE Frage und Aufgabe, die auf den Seiten steht – auch Teilaufgaben, kurze '
      'Zwischen- und Verständnisfragen im Fließtext oder auf Folien ("Was passiert, '
      'wenn …?") und Rechenaufgaben. Weglassen nur, was gar keinen fachlichen Inhalt '
      'hat (z.B. "Noch Fragen?", Organisatorisches, Abgabehinweise).';

  static const _scanScopeContent =
      'NUR inhaltliche Fragen und Aufgaben, die fachliches Wissen oder Verständnis '
      'prüfen und eine klare Antwort haben. Weglassen: Organisatorisches, rhetorische '
      'Einstiegs- oder Überschriftenfragen, Meinungs- und Reflexionsfragen ohne '
      'fachliche Antwort, reine Verweise auf spätere Folien.';

  /// Sucht auf einigen Seiten eines Dokuments nach den dort vorhandenen
  /// Fragen/Aufgaben und liefert sie als Rohkarten – jede mit "page" (Seite
  /// im Gesamtdokument, [pageNumbers] = die Dokument-Seiten in Reihenfolge)
  /// und "solutionFromDocument". Mit [pageImages] (je Seite ein PNG,
  /// passend zu [pageNumbers], plus optional [pageTexts]) sieht die KI die
  /// Seiten als Bild und kann Abbildungen per "imageBox" angeben sowie
  /// Bildfragen erstellen; sonst bekommt sie die Seiten als PDF-Datei
  /// ([pdfBytes], z.B. per PdfService.extractPages ausgeschnitten).
  /// [contentOnly] lässt Organisatorisches/Rhetorisches weg;
  /// [fillMissingSolutions] beantwortet Fragen ohne Lösung im Dokument
  /// selbst, sonst fallen sie weg. Mit [focus] (Wortlaut einer Aufgabe)
  /// übernimmt die KI NUR diese eine Aufgabe – zum Nachholen einer beim
  /// ersten Durchlauf übersehenen. Gedacht für das Vision-Modell.
  Future<List<Map<String, dynamic>>> scanPdfPagesForQuestions(
    Uint8List? pdfBytes, {
    required List<int> pageNumbers,
    required bool contentOnly,
    required bool fillMissingSolutions,
    List<Uint8List>? pageImages,
    List<String>? pageTexts,
    String? referenceText,
    String? focus,
  }) async {
    final reply = await scanPdfWindow(
      pdfBytes,
      pageNumbers: pageNumbers,
      contentOnly: contentOnly,
      fillMissingSolutions: fillMissingSolutions,
      pageImages: pageImages,
      pageTexts: pageTexts,
      referenceText: referenceText,
      focus: focus,
    );
    return reply.questions;
  }

  /// Ein Abschnitt des fortlaufenden Imports: wie [scanPdfPagesForQuestions],
  /// aber mit Überlappung. [overlapPage] ist die erste der gezeigten
  /// [pageNumbers] und stammt aus dem vorigen Abschnitt; [previous] sind die
  /// daraus schon übernommenen Fragen (nummeriert ab 1). Die KI übernimmt nur
  /// die NEUEN Seiten und meldet unter "revisions", wenn eine der bisherigen
  /// Fragen durch die neuen Seiten vollständiger wird (Fortsetzung der
  /// Aufgabe, Musterlösung, Abbildung) – sonst bleiben sie unverändert.
  Future<ScanWindowReply> scanPdfWindow(
    Uint8List? pdfBytes, {
    required List<int> pageNumbers,
    required bool contentOnly,
    required bool fillMissingSolutions,
    int? overlapPage,
    List<({int n, String type, String front, String answer})> previous = const [],
    List<Uint8List>? pageImages,
    List<String>? pageTexts,
    String? referenceText,
    String? focus,
  }) async {
    final withImages = pageImages != null && pageImages.length == pageNumbers.length;
    if (!withImages && pdfBytes == null) {
      throw ArgumentError('Weder Seitenbilder noch PDF übergeben.');
    }
    final rolling = overlapPage != null && pageNumbers.length > 1;
    final systemPrompt = _scanPdfQuestionsSystemPrompt
        .replaceFirst('{{ROLLING}}', rolling ? _scanRollingRules.replaceAll('{{OVERLAP}}', '$overlapPage') : '')
        .replaceFirst('{{REVISIONS_FORMAT}}', rolling ? ', "revisions": [{"n": 1, "question": {…}}]' : '')
        .replaceFirst('{{SCOPE}}', contentOnly ? _scanScopeContent : _scanScopeEvery)
        .replaceFirst('{{FIGURES}}', withImages ? _scanFiguresFromImages : _scanFiguresFromPdf)
        .replaceFirst('{{LABEL_RULE}}', withImages ? _scanLabelFromImages : _scanLabelFromPdf)
        .replaceFirst(
          '{{EXAMPLE}}',
          withImages
              ? ', {"page": 4, "type": "free_text", "front": "Wie groß ist der Strom I in der abgebildeten '
                  'Schaltung?", "correctText": "2 A", "imageBox": [0.12, 0.30, 0.78, 0.62], '
                  '"solutionFromDocument": false}'
              : '',
        )
        .replaceFirst(
          '{{MISSING}}',
          fillMissingSolutions
              ? 'Steht keine Lösung im Dokument, beantworte die Frage selbst – fachlich korrekt, '
                  'knapp und passend zum Stoff des Dokuments – und setze "solutionFromDocument": false.'
              : 'Steht KEINE Lösung im Dokument, lass die Frage weg.',
        );
    final List<Map<String, dynamic>> content;
    if (withImages) {
      content = [
        {
          'type': 'text',
          'text': 'Du siehst ${pageNumbers.length} Seite${pageNumbers.length == 1 ? '' : 'n'} des Dokuments '
              '(${pageNumbers.map((p) => 'Dokument-Seite $p').join(', ')}). Suche darauf nach Fragen und Aufgaben.',
        },
        for (var i = 0; i < pageNumbers.length; i++) ...[
          {
            'type': 'text',
            'text': () {
              final text = i < (pageTexts?.length ?? 0) ? pageTexts![i].trim() : '';
              return text.isEmpty
                  ? 'Dokument-Seite ${pageNumbers[i]} (ohne Textebene – nur das Bild):'
                  : 'Dokument-Seite ${pageNumbers[i]} – Text der Seite:\n${_cap(text, _scanPageTextCap)}\n\nBild der Seite:';
            }(),
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,${base64Encode(pageImages[i])}'},
          },
        ],
      ];
    } else {
      final mapping = [
        for (var i = 0; i < pageNumbers.length; i++) 'Datei-Seite ${i + 1} = Dokument-Seite ${pageNumbers[i]}',
      ].join(', ');
      content = [
        {
          'type': 'text',
          'text': 'Die Datei enthält ${pageNumbers.length} Seite${pageNumbers.length == 1 ? '' : 'n'} '
              '($mapping). Suche darauf nach Fragen und Aufgaben.',
        },
        {
          'type': 'file',
          'file': {
            'filename': 'seiten.pdf',
            'file_data': 'data:application/pdf;base64,${base64Encode(pdfBytes!)}',
          },
        },
      ];
    }
    if (rolling) {
      final list = StringBuffer();
      for (final q in previous) {
        list.writeln('${q.n}. [${q.type}] ${_cap(q.front, 500)} — Lösung: ${_cap(q.answer, 300)}');
      }
      content.add({
        'type': 'text',
        'text': 'Seite $overlapPage ist die schon bearbeitete letzte Seite des vorigen Abschnitts. '
            '${previous.isEmpty ? 'Daraus wurde noch keine Frage übernommen.' : 'Daraus wurden schon diese Fragen übernommen:\n$list'}',
      });
    }
    if ((referenceText ?? '').trim().isNotEmpty) {
      content.add({
        'type': 'text',
        'text': 'Begleitdokumente (z.B. eine separate Musterlösung) – NUR zum Nachschlagen von Lösungen '
            'für die Fragen auf den Seiten oben; übernimm daraus KEINE eigenen Fragen. Eine dort gefundene '
            'Lösung zählt als "solutionFromDocument": true.\n\n${_cap(referenceText!.trim(), _scanReferenceCap)}',
      });
    }
    if ((focus ?? '').trim().isNotEmpty) {
      content.add({
        'type': 'text',
        'text': 'NUR EINE AUFGABE: Übernimm auf diesen Seiten AUSSCHLIESSLICH die folgende Aufgabe (alle anderen '
            'sind schon importiert – erzeuge für sie keine Fragen). Gehört dazu eine Abbildung oder Tabelle, '
            'übernimm sie mit.\n\n${_cap(focus!.trim(), 1500)}',
      });
    }
    final raw = await _complete(systemPrompt, content, temperature: 0.1);
    return parseScanWindow(
      _parseJsonObject(raw),
      shownPages: pageNumbers,
      overlapPage: rolling ? overlapPage : null,
    );
  }

  /// Liest die Antwort eines Abschnitts: die neuen Fragen (siehe
  /// [parseScannedQuestions]; eine fehlende oder unpassende Seitenangabe wird
  /// zur ersten NEUEN Seite), die "revisions" (Nummer → komplette Rohkarte,
  /// "page" fehlt → Überlappungsseite) und die gemeldeten "pages".
  static ScanWindowReply parseScanWindow(
    Map<String, dynamic> json, {
    required List<int> shownPages,
    int? overlapPage,
  }) {
    final newPages = [for (final p in shownPages) if (p != overlapPage) p];
    final questions = parseScannedQuestions(
      json,
      shownPages,
      fallbackPage: newPages.isEmpty ? null : newPages.first,
    );
    final revisions = <int, Map<String, dynamic>>{};
    if (overlapPage != null) {
      for (final entry in _mapsIn(json['revisions'])) {
        final n = entry['n'] is num ? (entry['n'] as num).toInt() : int.tryParse('${entry['n']}');
        final question = entry['question'];
        if (n == null || question is! Map) continue;
        final map = Map<String, dynamic>.from(question);
        final page = map['page'] is num ? (map['page'] as num).toInt() : int.tryParse('${map['page']}');
        map['page'] = page != null && shownPages.contains(page) ? page : overlapPage;
        revisions.putIfAbsent(n, () => map);
      }
    }
    final seen = json['pages'];
    return (
      questions: questions,
      revisions: revisions,
      pagesSeen: seen is List
          ? [
              for (final e in seen)
                if (e is Map && (e['page'] is num || int.tryParse('${e['page']}') != null))
                  e['page'] is num ? (e['page'] as num).toInt() : int.parse('${e['page']}'),
            ]
          : null,
    );
  }

  /// Seitentext je Seite beim Import mit Seitenbildern – genug für eine dicht
  /// beschriebene Klausurseite.
  static const _scanPageTextCap = 8000;

  /// Begleittext (andere Dateien, z.B. Musterlösung) je Anfrage – der
  /// Import wählt daraus die zum Abschnitt passenden Seiten (siehe
  /// ImportReference), die Obergrenze ist nur ein Sicherheitsnetz.
  static const _scanReferenceCap = 30000;

  /// Liest `{"questions": [...]}` (auch `{"flashcards": [...]}`) und sorgt
  /// dafür, dass jede Frage eine gültige Dokument-Seite aus [pageNumbers]
  /// trägt – eine fehlende oder unpassende Angabe wird zur ersten Seite.
  static List<Map<String, dynamic>> parseScannedQuestions(
    Map<String, dynamic> parsed,
    List<int> pageNumbers, {
    int? fallbackPage,
  }) {
    final list = parsed['questions'] ?? parsed['flashcards'];
    if (list is! List) return const [];
    final fallback = fallbackPage ?? (pageNumbers.isEmpty ? 1 : pageNumbers.first);
    return [
      for (final entry in list)
        if (entry is Map)
          () {
            final map = Map<String, dynamic>.from(entry);
            final page = map['page'] is num ? (map['page'] as num).toInt() : int.tryParse('${map['page']}');
            map['page'] = page != null && pageNumbers.contains(page) ? page : fallback;
            return map;
          }(),
    ];
  }

  static const _verifyImportSystemPrompt = """
Du bist ein unabhängiger Prüfer für einen Fragen-Import. Eine andere KI hat aus
den unten gezeigten Seiten eines Dokuments (Übungsblatt, Altklausur, Folien …)
Fragen und Aufgaben als Quizfragen übernommen. Du bekommst den Text der Seiten
und die Liste der übernommenen Fragen (nummeriert, mit Seite). Prüfe UNABHÄNGIG,
ob der Import vollständig und ehrlich ist – vertraue der Liste nicht.

Vorgehen:
1. Lies die Seiten und zähle selbst, wie viele Fragen und Aufgaben darauf
   stehen ({{SCOPE}}). Teilaufgaben (a, b, c …) zählen einzeln, ein reiner
   Aufgabenkopf ohne eigene Frage nicht. Eine Aufgabe zählt zu der Seite, auf
   der sie beginnt.
2. Gleiche mit der Liste ab:
   - "missing": eine Aufgabe steht im Dokument, aber keine Frage der Liste
     deckt sie ab.
   - "surplus": ein Eintrag der Liste passt zu KEINER Aufgabe im Dokument.
     "kind": "not_in_document" (erfunden oder aus anderem Zusammenhang),
     "duplicate" (dieselbe Aufgabe steht zweimal in der Liste) oder
     "altered" (die Aufgabe gibt es, aber die Frage ändert sie inhaltlich –
     andere Zahlen, andere Aufgabenstellung).
   Kürzungen und andere Formulierungen bei gleichem Inhalt sind in Ordnung
   und KEINE Abweichung.
3. Begründe JEDE Abweichung konkret: was steht im Dokument (kurz zitieren),
   was fehlt oder ist zu viel. Bist du unsicher (z.B. Text unleserlich oder
   unvollständig), melde es NICHT als Abweichung, sondern schreibe es in
   "note". Erfinde keine Abweichungen: stimmt alles, sind beide Listen leer.

Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences:
{"documentCount": 7,
 "missing": [{"page": 3, "task": "Aufgabe 2b: Berechnen Sie …", "reason": "Steht auf Seite 3, keine Frage der Liste behandelt sie."}],
 "surplus": [{"n": 4, "kind": "not_in_document", "reason": "Im Dokument gibt es keine Aufgabe zu …"}],
 "note": ""}
Antworte in der Sprache der Vorlage.
""";

  static const _verifyScopeEvery = 'wirklich jede Frage und Aufgabe, auch Teilaufgaben und kleine Zwischenfragen';
  static const _verifyScopeContent =
      'nur inhaltliche Fragen, die fachliches Wissen prüfen – Organisatorisches, rhetorische Fragen und '
      'Meinungsfragen zählen nicht';

  /// Text einer Seite in der Prüf-Anfrage.
  static const _verifyPageTextCap = 6000;

  /// Zweite Meinung zu einem Import ([ImportVerifyService]): liest den Text
  /// der Seiten [pageNumbers] SELBST, zählt die dort stehenden Fragen und
  /// gleicht sie mit den übernommenen [imported] ab (nummeriert, mit Seite).
  /// Weicht sie ab, begründet sie jede Abweichung – der Nutzer entscheidet.
  Future<ImportVerification> verifyImportedQuestions({
    required List<int> pageNumbers,
    required List<String> pageTexts,
    required List<({int n, int page, String front, String answer})> imported,
    required bool contentOnly,
  }) async {
    final system = _verifyImportSystemPrompt.replaceFirst(
        '{{SCOPE}}', contentOnly ? _verifyScopeContent : _verifyScopeEvery);
    final buffer = StringBuffer('Seiten des Dokuments:\n');
    for (var i = 0; i < pageNumbers.length; i++) {
      final text = i < pageTexts.length ? pageTexts[i].trim() : '';
      buffer
        ..writeln('=== Seite ${pageNumbers[i]} ===')
        ..writeln(text.isEmpty ? '(kein Text)' : _cap(text, _verifyPageTextCap))
        ..writeln();
    }
    buffer.writeln('Übernommene Fragen:');
    if (imported.isEmpty) buffer.writeln('(keine)');
    for (final q in imported) {
      buffer.writeln('${q.n}. (Seite ${q.page}) ${_cap(q.front, 400)} — Lösung: ${_cap(q.answer, 160)}');
    }
    final raw = await _complete(system, buffer.toString(), temperature: 0.1);
    return parseImportVerification(_parseJsonObject(raw), pageNumbers);
  }

  /// Liest die Antwort von [verifyImportedQuestions]. Eine fehlende oder
  /// unpassende Seitenangabe wird zur ersten Seite des Pakets, eine
  /// unbekannte Art zu "not_in_document"; Einträge ohne Aufgabentext bzw.
  /// Nummer fallen weg.
  static ImportVerification parseImportVerification(Map<String, dynamic> json, List<int> pageNumbers) {
    final fallbackPage = pageNumbers.isEmpty ? 1 : pageNumbers.first;
    String reasonOf(Map<String, dynamic> e) {
      final reason = (e['reason'] ?? e['begruendung'] ?? '').toString().trim();
      return reason.isEmpty ? 'Keine Begründung angegeben.' : reason;
    }

    final count = json['documentCount'] ?? json['count'];
    return (
      documentCount: count is num ? count.toInt() : int.tryParse('$count'),
      missing: [
        for (final e in _mapsIn(json['missing']))
          if ((e['task'] ?? '').toString().trim().isNotEmpty)
            (
              page: () {
                final page = e['page'] is num ? (e['page'] as num).toInt() : int.tryParse('${e['page']}');
                return page != null && pageNumbers.contains(page) ? page : fallbackPage;
              }(),
              task: e['task'].toString().trim(),
              reason: reasonOf(e),
            ),
      ],
      surplus: [
        for (final e in _mapsIn(json['surplus']))
          if (e['n'] is num || int.tryParse('${e['n']}') != null)
            (
              n: e['n'] is num ? (e['n'] as num).toInt() : int.parse('${e['n']}'),
              kind: const {'not_in_document', 'duplicate', 'altered'}.contains(e['kind']) ? e['kind'] as String : 'not_in_document',
              reason: reasonOf(e),
            ),
      ],
      note: (json['note'] ?? '').toString().trim(),
    );
  }

  static const _expandStagesSystemPrompt = """
Du erweiterst bereits übernommene Quizfragen um Schwierigkeitsstufen. Du
bekommst nummerierte ORIGINAL-Fragen (Typ, Frage, Lösung), die 1:1 aus einem
Dokument stammen und unverändert bleiben. Beim Lernen kommt zuerst die
leichte Stufe, erst wenn sie sitzt die mittlere, dann die schwere.

Je Original-Frage lieferst du:
1. "level": die Stufe des Originals nach seinem tatsächlichen Anspruch –
   "leicht" = wiedererkennen (Auswahl), "mittel" = ergänzen oder zuordnen
   (Lücke, Zuordnen), "schwer" = selbst formulieren, herleiten oder anwenden
   (Freitext, Rechen-/Übungsaufgabe, Tabelle).
2. "group": kurzer Ordnername (2–6 Wörter) für das geprüfte Wissen.
3. "variants": für JEDE gewünschte Stufe ({{LEVELS}}), die NICHT die Stufe des
   Originals ist, EINE zusätzliche Frage zu DEMSELBEN Wissen in dieser Stufe –
   wer die schwere sicher kann, kann auch die leichte. Nutze nur, was in
   Frage und Lösung des Originals steht oder unmittelbar daraus folgt; erfinde
   keine neuen Fakten. Lässt sich eine Stufe für diese Frage nicht sinnvoll
   umsetzen, lass diese Variante weg (eine leere Liste ist erlaubt).

Typ der Varianten:
{{TYPE_RULES}}

$_noGiveawayRule
$_calcFlagRule
Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences:
{"cards": [{"n": 1, "level": "mittel", "group": "Ohmsches Gesetz",
  "variants": [{"level": "leicht", "type": "single_choice", "front": "…", "options": [{"text": "…", "isCorrect": true}, {"text": "…", "isCorrect": false}, {"text": "…", "isCorrect": false}]},
               {"level": "schwer", "type": "free_text", "front": "…", "correctText": "…"}]}]}
Jede Nummer aus der Liste kommt genau einmal vor. Antworte in der Sprache der Vorlage.
""";

  /// Stufen (Namen wie in [QuestionParsing.parseStageLevel]) in der
  /// Reihenfolge leicht → schwer.
  static const stageLevelNames = ['leicht', 'mittel', 'schwer'];

  /// Ergänzt übernommene Original-Fragen um die Schwierigkeitsstufen
  /// [levels] (Namen aus [stageLevelNames]): je Frage die Stufe des Originals,
  /// ein Ordnername und die zusätzlichen Fragen derselben Sache. Den Typ der
  /// Varianten gibt [tierTypes] je Stufe vor, sonst die Eskalationskette
  /// (leicht = Auswahl, mittel = Lücke, schwer = Freitext).
  Future<Map<int, StageExpansion>> expandQuestionStages(
    List<({int n, String type, String front, String answer})> cards, {
    required List<String> levels,
    Map<String, QuestionType> tierTypes = const {},
  }) async {
    final wanted = [for (final l in stageLevelNames) if (levels.contains(l)) l];
    final rules = StringBuffer();
    for (final level in wanted) {
      final type = tierTypes[level] ?? QuestionParsing.escalationChain[stageLevelNames.indexOf(level)];
      rules.writeln('- "$level": ${_variantTypeRule(type)}');
    }
    final system = _expandStagesSystemPrompt
        .replaceFirst('{{LEVELS}}', wanted.join(', '))
        .replaceFirst('{{TYPE_RULES}}', rules.toString().trimRight());
    final buffer = StringBuffer('Gewünschte Stufen: ${wanted.join(', ')}\n\nOriginal-Fragen:\n');
    for (final c in cards) {
      buffer.writeln('${c.n}. [${c.type}] ${_cap(c.front, 500)} — Lösung: ${_cap(c.answer, 300)}');
    }
    final raw = await _complete(system, buffer.toString());
    return parseStageExpansions(_parseJsonObject(raw), wanted);
  }

  /// Liest die Antwort von [expandQuestionStages]: Nummer → Stufe/Ordner des
  /// Originals und seine Varianten. Varianten ohne gültige Stufe, mit einer
  /// nicht gewünschten Stufe oder in der Stufe des Originals fallen weg,
  /// ebenso doppelte Stufen (die erste zählt).
  static Map<int, StageExpansion> parseStageExpansions(Map<String, dynamic> json, List<String> wantedLevels) {
    final wanted = {for (final l in wantedLevels) QuestionParsing.parseStageLevel(l)}.whereType<int>().toSet();
    final result = <int, StageExpansion>{};
    for (final entry in _mapsIn(json['cards'])) {
      final n = entry['n'] is num ? (entry['n'] as num).toInt() : int.tryParse('${entry['n']}');
      if (n == null) continue;
      final level = QuestionParsing.parseStageLevel(entry['level']);
      final seen = <int>{?level};
      final variants = <Map<String, dynamic>>[];
      for (final v in _mapsIn(entry['variants'])) {
        final vLevel = QuestionParsing.parseStageLevel(v['level']);
        if (vLevel == null || !wanted.contains(vLevel) || !seen.add(vLevel)) continue;
        variants.add({...v, 'level': stageLevelNames[vLevel]});
      }
      result[n] = (level: level, group: QuestionParsing.parseStageGroup(entry['group']), variants: variants);
    }
    return result;
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
Seite als zusätzlicher Kontext) und möchte daraus gezielt Prüfungsfragen
erstellen. Stütze dich in erster Linie auf das Bild (Diagramme, Formeln,
Layout, was reiner Text nicht wiedergibt), der Text hilft bei der Einordnung.

FOKUS: Hat der Nutzer einen Bereich der Seite markiert (als zweites Bild
beigefügt) und/oder einen Fokus als Text vorgegeben, MUSS sich JEDE Frage
darauf beziehen – erfinde keinen anderen Inhalt; der Rest der Seite dient
nur als Kontext. Ohne Vorgabe wählst du selbst die wichtigsten, klar
abfragbaren Fakten der Seite.

ANZAHL: {{COUNT_RULE}} Mehrere Fragen prüfen
UNTERSCHIEDLICHE Fakten bzw. Aspekte (innerhalb des Fokus, falls
vorgegeben) – nie zweimal denselben Fakt.

STUFEN: Jede Frage gibt es in den folgenden Schwierigkeitsstufen, in genau
dieser Reihenfolge. Alle Stufen EINER Frage prüfen DENSELBEN Fakt – nur
Format und Schwierigkeit unterscheiden sich:
{{TIERS}}
Ist für eine Stufe kein Typ vorgegeben, wählst du das Format, das zu Inhalt
und Stufe am besten passt: leichte Stufen eher Wiedererkennen
(single_choice, multiple_choice), mittlere eher gestütztes Erinnern
(fill_blank), schwere eher freies Erinnern (free_text, flashcard).
Zuordnen ("drag_drop"/"drag_category") nur, wenn der Fakt selbst aus
mehreren zusammengehörigen Teilen besteht (z.B. mehrere Aufgaben und ihre
Abteilungen) – ein einzelner Fakt ergibt keine sinnvolle Zuordnung. Jede
Stufe ist mindestens so anspruchsvoll wie die vorherige; eine frei gewählte
Stufe hat möglichst einen anderen Typ als die übrigen Stufen derselben
Frage.

$_noGiveawayRule
$_calcFlagRule
Formatvorgaben der Fragetypen:
{{TYPE_RULES}}

Bekommst du zusätzlich bereits erstellte Fragen samt Überarbeitungs-
Anweisung, überarbeite GENAU diese Fragen gemäß der Anweisung (z.B. anderer
Fokus, einfacher formuliert, mehr Kontext) statt neue zu erfinden – Anzahl,
Stufen und vorgegebene Typen bleiben dabei gleich.

Entscheide zusätzlich pro Karte, ob das Bild an die Karte angehängt werden
soll ("needsImage": true/false) – angehängt wird der markierte Bereich,
falls vorhanden, sonst die ganze Seite. Setze "needsImage" NUR auf true,
wenn die Frage OHNE das Bild nicht sinnvoll verständlich oder beantwortbar
ist – z.B. weil sie sich auf ein Diagramm, eine Formel, eine Skizze, ein
Foto oder ein Layout bezieht, das sich nicht vollständig in Worten
wiedergeben lässt. Bei rein textbasierten Fakten setze "needsImage": false –
das ist der Regelfall. Dass die Seite ein Diagramm enthält, reicht allein
nicht – entscheidend ist, ob DIESE Frage es braucht; im Zweifel lieber
anhängen (der Nutzer kann ein unnötiges Bild wieder entfernen).

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{"questions": [{"flashcards": [{"type": "...", "front": "...", "needsImage": false, "...": "je nach Typ weitere Felder, siehe oben"}]}]}
"questions" hat {{COUNT_ENTRIES}} Einträge; "flashcards" enthält je Frage genau
eine Karte pro Stufe, in der Reihenfolge der Stufen. Antworte in der
Sprache der Vorlage.
''';

  static const int _pageQuestionGenerationTextCap = 20000;

  /// Obergrenze, wenn die KI die Anzahl der Fragen einer Seite selbst
  /// bestimmt ("Frage erstellen", Anzahl "KI").
  static const int maxAutoPageQuestions = 8;

  /// Fragetypen, aus denen die KI bei "KI entscheidet" wählt.
  static const pageQuestionTypes = [
    QuestionType.singleChoice,
    QuestionType.multipleChoice,
    QuestionType.fillBlank,
    QuestionType.dragDrop,
    QuestionType.dragCategory,
    QuestionType.freeText,
    QuestionType.flashcard,
  ];

  /// Fragetypen, die der Nutzer je Stufe fest wählen kann – zusätzlich
  /// "Interaktiv" (html: aufwendig und nur auf Android/iOS interaktiv) und
  /// die Bildfragen (brauchen ein passendes Bild, die KI schätzt Positionen)
  /// – deshalb nur auf ausdrücklichen Wunsch statt als KI-Wahl.
  static const selectablePageQuestionTypes = [
    ...pageQuestionTypes,
    QuestionType.learn,
    QuestionType.table,
    QuestionType.html,
    QuestionType.diagramLabel,
    QuestionType.markImage,
  ];

  /// Erstellt (oder überarbeitet) [questionCount] Fragen (0 = so viele, wie
  /// die Seite hergibt, siehe [maxAutoPageQuestions]) direkt aus einer
  /// betrachteten Seite (MaterialViewerScreen, "Frage erstellen"), jede in
  /// allen [tiers] – Varianten DESSELBEN Fakts von leicht nach schwer, die
  /// der Aufrufer zu einer Stufen-Kette zusammenführt. Liefert je Frage die
  /// Rohkarten in Stufen-Reihenfolge.
  ///
  /// Bewusst immer multimodal (Screenshot, [model] muss vision-fähig sein),
  /// da Folienseiten oft Diagramme/Formeln enthalten, die reiner Text nicht
  /// wiedergibt. Fokus, alles optional und kombinierbar: [focusImageBytes]
  /// (vom Nutzer markierter Ausschnitt der Seite), [focusText] (markierte
  /// Textstelle oder eigene Anweisung) und [answerText] (erwartete Antwort).
  /// Ohne Fokus wählt die KI selbst. Für eine Überarbeitung
  /// [previousQuestions] + [instruction] mitgeben.
  Future<List<List<Map<String, dynamic>>>> generateQuestionsFromPage({
    required Uint8List pageImageBytes,
    required String pageText,
    required List<PageQuestionTier> tiers,
    int questionCount = 1,
    Uint8List? focusImageBytes,
    String? focusText,
    String? answerText,
    String? examContext,
    List<List<Map<String, dynamic>>>? previousQuestions,
    String? instruction,
    bool coordinateGrid = false,
  }) async {
    // 0 = die KI entscheidet, wie viele Fragen die Seite hergibt.
    final auto = questionCount <= 0;
    final count = auto ? maxAutoPageQuestions : questionCount;
    final tierLines = [
      for (var i = 0; i < tiers.length; i++)
        '${i + 1}. Stufe "${tiers[i].level}": '
            '${tiers[i].type == null ? 'Typ frei wählbar' : 'Typ ${QuestionParsing.aiTypeName(tiers[i].type!)}'}',
    ].join('\n');
    // Bei frei wählbaren Stufen braucht die KI die Formatvorgaben aller
    // Typen, aus denen sie wählen darf, dazu die der vorgegebenen.
    final ruleTypes = {
      if (tiers.any((t) => t.type == null)) ...pageQuestionTypes,
      for (final t in tiers)
        if (t.type != null) t.type!,
    }.toList();
    final typeRules = ruleTypes.map((t) => '- ${_variantTypeRule(t)}').join('\n');
    final systemPrompt = _pageQuestionGenerationSystemPrompt
        .replaceFirst(
          '{{COUNT_RULE}}',
          auto
              ? 'Entscheide selbst, wie viele Fragen diese Seite (bzw. der Fokus) hergibt: eine je '
                  'eigenständigem, prüfungsrelevantem Fakt oder Aspekt, höchstens $maxAutoPageQuestions. Eine '
                  'inhaltsarme Seite (Titel, Gliederung, Überleitung) ergibt 1 Frage, eine dichte Seite mehrere – '
                  'keine Füllfragen.'
              : 'Erzeuge GENAU $count Frage(n).',
        )
        .replaceFirst('{{COUNT_ENTRIES}}', auto ? 'so viele (1 bis $maxAutoPageQuestions)' : 'genau $count')
        .replaceFirst('{{TIERS}}', tierLines)
        .replaceFirst('{{TYPE_RULES}}', typeRules);

    final buffer = StringBuffer()
      ..writeln('Text dieser Seite (Kontext, Grundlage ist primär das Bild):')
      ..writeln(_cap(pageText, _pageQuestionGenerationTextCap));
    final focus = focusText?.trim() ?? '';
    final answer = answerText?.trim() ?? '';
    if (focusImageBytes != null || focus.isNotEmpty || answer.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Vom Nutzer vorgegebener Fokus (VERBINDLICHE Grundlage):');
      if (focusImageBytes != null) {
        buffer.writeln('- Markierter Bereich der Seite: siehe zweites Bild.');
      }
      if (focus.isNotEmpty) buffer.writeln('- Worum es gehen soll: $focus');
      if (answer.isNotEmpty) buffer.writeln('- Erwartete Antwort/Fakt: $answer');
    }
    if (coordinateGrid) {
      buffer
        ..writeln()
        ..writeln(focusImageBytes != null
            ? 'Hinweis: Der markierte Ausschnitt (zweites Bild) trägt ein Koordinatenraster in Zehnteln '
                '(0.1 … 0.9 an den Rändern) – lies Positionen für Bildfragen daran ab. Das Raster gehört '
                'nicht zum Inhalt.'
            : 'Hinweis: Das Bild trägt ein Koordinatenraster in Zehnteln (0.1 … 0.9 an den Rändern) – lies '
                'Positionen für Bildfragen daran ab. Das Raster gehört nicht zum Inhalt.');
    }
    if (examContext != null && examContext.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Stil-Referenz, eine bereits hochgeladene Übungsklausur (orientiere '
            'dich bei Schwierigkeit/Formulierung daran, sofern thematisch passend):')
        ..writeln(_cap(examContext, _examContextCap));
    }
    if (previousQuestions != null && instruction != null && instruction.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Bereits erstellte Fragen (überarbeiten statt neu erfinden):')
        ..writeln(jsonEncode({
          'questions': [
            for (final q in previousQuestions) {'flashcards': q},
          ],
        }))
        ..writeln()
        ..writeln('Anweisung des Nutzers zur Überarbeitung: $instruction');
    }

    final content = [
      {'type': 'text', 'text': buffer.toString()},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,${base64Encode(pageImageBytes)}'},
      },
      if (focusImageBytes != null) ...[
        {'type': 'text', 'text': 'Vom Nutzer markierter Bereich (Ausschnitt der Seite oben):'},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,${base64Encode(focusImageBytes)}'},
        },
      ],
    ];
    final raw = await _complete(systemPrompt, content);
    return parsePageQuestionGroups(_parseJsonObject(raw));
  }

  /// Liest die Antwort von [generateQuestionsFromPage]: je Frage die Karten
  /// in Stufen-Reihenfolge. Akzeptiert auch das ältere flache Format
  /// (`{"flashcards": [...]}` = eine Frage); leere Fragen fallen weg.
  static List<List<Map<String, dynamic>>> parsePageQuestionGroups(Map<String, dynamic> parsed) {
    List<Map<String, dynamic>> cardsOf(Object? list) => [
          for (final e in (list is List ? list : const []))
            if (e is Map) Map<String, dynamic>.from(e),
        ];
    final questions = parsed['questions'];
    if (questions is List) {
      return [
        for (final q in questions)
          if (q is Map && cardsOf(q['flashcards']).isNotEmpty) cardsOf(q['flashcards']),
      ];
    }
    final flat = cardsOf(parsed['flashcards']);
    return flat.isEmpty ? const [] : [flat];
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
          ..writeln(jsonEncode(withoutImageData(generated))))
        .toString();
    final raw = await _complete(_crosscheckSystemPrompt, userPrompt);
    return _parseJsonObject(raw);
  }

  /// Karten ohne angehängte Bilddaten (Base64) – die gehören nicht in eine
  /// Text-Anfrage und würden sie nur aufblähen.
  static Map<String, dynamic> withoutImageData(Map<String, dynamic> generated) => {
        ...generated,
        if (generated['flashcards'] is List)
          'flashcards': [
            for (final f in generated['flashcards'] as List)
              if (f is Map) {...Map<String, dynamic>.from(f)}..remove('imageBase64') else f,
          ],
      };

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
              '"___"; passen mehrere Begriffe in eine Lücke, alle durch ";" '
              'getrennt in denselben Eintrag. Antwortformat: {"front": '
              '"Text mit ___ Lücke(n)", "blanks": ["Lösung 1", "..."]}',
        QuestionType.freeText =>
          'Zieltyp "free_text": derselbe Fakt als offene, aber eindeutig '
              'prüfbare Frage ohne Antwortoptionen (die schwerste Stufe – '
              'keine Auswahl mehr, nur Erinnerung). Antwortformat: '
              '{"front": "...", "correctText": "Lösung; ggf. Alternative"}',
        QuestionType.dragDrop =>
          'Zieltyp "drag_drop": als Zuordnungspaare – mindestens 3 Paare aus dem '
              'Stoff rund um diesen Fakt, sonst wäre die Zuordnung geschenkt; jedes Ziel genau einmal '
              '(1:1 – gehören mehrere Begriffe zum selben Ziel, ist es '
              'drag_category). Antwortformat: '
              '{"front": "...", "dragPairs": [{"source": "...", "target": "..."}]}',
        QuestionType.dragCategory =>
          'Zieltyp "drag_category": Begriffe in Kategorien einsortieren – mindestens '
              '2 Kategorien und 4 Begriffe. '
              'Antwortformat: {"front": "...", "dragPairs": '
              '[{"source": "...", "target": "Kategorie"}]}',
        QuestionType.flashcard =>
          'Zieltyp "flashcard": offene Frage/Antwort. Antwortformat: '
              '{"front": "...", "back": "..."}',
        // Rechenweg/Terminierung sind nie Ziel einer Beförderung – zur
        // Sicherheit wie eine Lernaufgabe.
        QuestionType.steps ||
        QuestionType.gantt ||
        QuestionType.crystal ||
        QuestionType.bom ||
        QuestionType.sketch =>
          _variantTypeRule(QuestionType.learn),
        QuestionType.learn =>
          'Zieltyp "learn" (Aufgabe zum Verstehen): "front" ist die Aufgabe '
              'WORTGETREU mit allen Teilaufgaben (bzw. der Fakt als zu '
              'lösende Aufgabe), "back" deine ausführliche Erklärung bzw. der '
              'Lösungsweg Schritt für Schritt. Der Lernende liest sie und '
              'bewertet selbst, wie gut er es verstanden hat. Antwortformat: '
              '{"front": "...", "back": "Erklärung / Lösungsweg"}',
        QuestionType.html =>
          'Zieltyp "html": derselbe Fakt als eigenständige interaktive Seite '
              '(z.B. Zuordnungs-Matrix, Klick-Aufgabe). '
              '"htmlContent" enthält NUR den Inhalt von <body> als EIN String mit '
              'Inline-HTML/CSS/JS – keine externen Skripte/Bilder, kein '
              'Netzwerkzugriff. Die Prüf-Logik steckt als Inline-JavaScript in der '
              'Seite und MUSS beim Auswerten genau '
              'window.FlutterAnswer.postMessage(JSON.stringify({correct: true})) '
              'bzw. {correct: false} aufrufen. Dazu "front" (kurze Frage) und '
              '"back" (Lösung als Text – Anzeige auf Geräten ohne interaktive '
              'Seite). Antwortformat: {"front": "...", "back": "...", '
              '"htmlContent": "..."}',
        QuestionType.diagramLabel =>
          'Zieltyp "diagram_label" (Bild beschriften): nur für ein Bild mit '
              'mehreren beschriftbaren Stellen (Diagramm, Skizze, Aufbau, '
              'Schaltbild, Prozess). Alle Koordinaten relativ zum Bild (markierter '
              'Ausschnitt, falls es einen gibt, sonst die ganze Seite), von 0 bis 1, '
              'Ursprung oben links – lies sie am eingezeichneten Koordinatenraster '
              'ab. "targets" enthält je Stelle die Beschriftung ("label"). Steht '
              'die Beschriftung schon als Text im Bild, gib "box" = [links, oben, '
              'rechts, unten] an: ein ENGER Kasten genau um diesen Text – er wird '
              'automatisch weiß abgedeckt, und genau dort beschriftet der Lernende. '
              'Ohne Text im Bild stattdessen "x" und "y" = Mittelpunkt der gemeinten '
              'Struktur. Stellen, deren Reihenfolge egal ist (z.B. mehrere '
              'Inputs/Eingänge, gleichrangige Elemente einer Aufzählung), bekommen '
              'denselben "group"-Namen (z.B. "Input") – dann zählt jede dieser '
              'Beschriftungen an jeder dieser Stellen. "covers" (optional): weitere '
              'Kästen [links, oben, rechts, unten] um Text, der die Lösung verraten '
              'würde (Legende, Überschrift, Erklärtext). 2 bis 8 Stellen, jede '
              'Beschriftung kurz, genau wie im Bild geschrieben. Antwortformat: '
              '{"front": "Beschrifte ...", "targets": [{"label": "...", "box": '
              '[0.10, 0.20, 0.24, 0.25], "group": "Input"}, {"label": "...", "x": '
              '0.6, "y": 0.5}], "covers": [[0.70, 0.05, 0.95, 0.12]]}',
        QuestionType.markImage =>
          'Zieltyp "mark_image" (Bild markieren): eine Frage, deren Antwort '
              'genau EINE Stelle im Bild ist ("Wo liegt/befindet sich …?"). '
              '"targets" enthält den richtigen Bereich als Kasten "box" = [links, '
              'oben, rechts, unten], relativ zum Bild von 0 bis 1, Ursprung oben '
              'links (markierter Ausschnitt, falls es einen gibt, sonst die ganze '
              'Seite) – lies ihn am eingezeichneten Koordinatenraster ab. Steht die '
              'Antwort als Beschriftung im Bild, gib unter "covers" einen Kasten um '
              'diesen Text an, damit er abgedeckt wird. "back" sagt kurz, was dort '
              'zu sehen ist. Antwortformat: {"front": "Wo ...?", "back": "...", '
              '"targets": [{"box": [0.40, 0.30, 0.60, 0.45]}], "covers": []}',
        QuestionType.table => 'Zieltyp "table" (Tabelle ausfüllen): "table" ist eine Liste von Zeilen, '
            'jede Zeile eine Liste von Zellen. Vorgegebene Zellen (Kopfzeile, Zeilentitel, schon '
            'ausgefüllte Werte) sind einfache Texte; Zellen, die der Lernende ausfüllen soll, sind '
            'Objekte {"answer": "Lösung; Alternative"}. Kurze, eindeutig prüfbare Zellinhalte. '
            'Antwortformat: {"front": "Vervollständige die Tabelle ...", "table": [["Begriff", '
            '"Merkmal"], ["...", {"answer": "..."}]]}',
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
Rechtschreib- und Tippfehler spielen keine Rolle, solange erkennbar ist, was
gemeint ist – geprüft wird Wissen, nicht Rechtschreibung.
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
    final raw = await _complete(_checkFreeTextSystemPrompt, userPrompt, temperature: 0);
    final parsed = _parseJsonObject(raw);
    return parsed['correct'] == true;
  }

  static const _checkFillBlankSystemPrompt = '''
Du bist ein fairer Tutor und bewertest die Eingaben eines Lernenden in einem
Lückentext. Ein exakter Textvergleich (mit kleiner Tippfehler-Toleranz) hat
mindestens eine Lücke abgelehnt – du entscheidest jetzt, ob der Lernende das
Richtige WUSSTE. Geprüft wird Wissen, nicht Rechtschreibung und nicht der
genaue Wortlaut der Musterlösung.
Du bekommst den Text (Lücken als "___"), je Lücke die Musterlösung (mehrere
akzeptierte Varianten durch ";" getrennt) und die Eingabe. Betrachte immer
den ganzen Satz mit allen Lücken zusammen.

Eine Lücke ist RICHTIG, wenn eines davon zutrifft:
1. Rechtschreib- oder Tippfehler: das gemeinte Wort ist erkennbar, auch bei
   mehreren vertauschten, fehlenden oder falschen Buchstaben (z.B. "debinrten"
   für "definierten", "Prodktion" für "Produktion").
2. Andere Reihenfolge: gleichrangige, austauschbare Lücken (Aufzählungen,
   "___ und ___", "sowohl ___ als auch ___") wurden vertauscht ausgefüllt –
   jede Lösung der Gruppe kommt aber vor (z.B. "Produktion" und "Entwicklung"
   statt "Entwicklung" und "Produktion"): dann sind ALLE Lücken der Gruppe
   richtig.
3. Gleiche Bedeutung: Synonym, gleichwertiger Fachbegriff, andere Wortform,
   Singular/Plural, Kurz- oder Langform oder ein Wort, das im Satz dasselbe
   aussagt (z.B. "Werkstätten" für "Werkstattfertigung").
4. Fachlich ebenso richtig: der Satz stimmt mit der Eingabe fachlich, auch
   wenn die Musterlösung ein anderes Wort nennt (z.B. "viele unterschiedliche
   Produkte" statt "viele unterschiedliche Varianten").

Eine Lücke ist FALSCH, wenn die Eingabe etwas anderes meint, den Satz
fachlich falsch macht, leer ist oder erkennbar geraten ist. Zahlen, Formeln
und Einheiten müssen im Wert stimmen (3,5 = 3.5 = 7/2, aber 35 ist nicht 3,5).
Im Zweifel, ob der Lernende das Richtige meint: zu seinen Gunsten.

Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences und ohne
Text davor oder danach – genau ein Eintrag je Lücke, in derselben
Reihenfolge; "note" ist eine sehr kurze Begründung (höchstens 6 Wörter):
{"results": [{"correct": true, "note": "Tippfehler"}, {"correct": false, "note": "anderer Begriff"}]}
''';

  /// Zweitmeinung für Lückentexte, analog zu [checkFreeTextAnswer]: der
  /// lokale Vergleich (AnswerChecker.fillBlankHits) kennt nur die
  /// hinterlegten Varianten, kleine Tippfehler und die feste Reihenfolge –
  /// ein anderer richtiger Begriff, ein Synonym, gröbere Rechtschreibfehler
  /// oder vertauschte gleichrangige Lücken fallen durch. Wird nur
  /// aufgerufen, wenn der lokale Vergleich eine Lücke abgelehnt hat. Liefert
  /// je Lücke das Urteil samt kurzer Begründung.
  Future<List<BlankVerdict>> checkFillBlankAnswers({
    required String text,
    required List<String> solutions,
    required List<String> answers,
  }) async {
    final buffer = StringBuffer()..writeln('Lückentext: $text');
    for (var i = 0; i < solutions.length; i++) {
      final answer = i < answers.length ? answers[i].trim() : '';
      buffer.writeln('Lücke ${i + 1}: Musterlösung "${solutions[i].trim()}" – Eingabe "$answer"');
    }
    final raw = await _complete(_checkFillBlankSystemPrompt, buffer.toString(), temperature: 0);
    return parseBlankVerdicts(_parseJsonObject(raw), solutions.length);
  }

  static const _checkDiagramLabelSystemPrompt = '''
Du prüfst, wie ein Lernender die Stellen in einer Abbildung beschriftet hat
(Lernfrage "Bild beschriften"). Je Stelle bekommst du, welche Beschriftung
dort erwartet wird, und was der Lernende eingetippt hat. Geprüft wird Wissen,
NICHT Rechtschreibung.

Eine Stelle ist RICHTIG, wenn die Eingabe erkennbar die erwartete
Beschriftung meint:
1. Rechtschreib- oder Tippfehler, auch mehrere ("Mitokondrium",
   "Zellmebran").
2. Synonym, gleichwertiger Fachbegriff, Abkürzung oder Langform,
   Singular/Plural, andere Wortform, deutsch/englisch ("ER" für
   "endoplasmatisches Retikulum", "Nucleus" für "Zellkern").
3. Austauschbare Stellen: stehen mehrere erlaubte Beschriftungen zur Auswahl
   ("eine von …"), genügt jede davon – aber jede nur EINMAL innerhalb der
   angegebenen Gruppe.

FALSCH ist eine Stelle, wenn die Eingabe etwas anderes meint, leer ist oder
erkennbar geraten ist. Im Zweifel, ob der Lernende das Richtige meint: zu
seinen Gunsten.

Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences und ohne
Text davor oder danach – genau ein Eintrag je Stelle, in derselben
Reihenfolge; "note" ist eine sehr kurze Begründung (höchstens 6 Wörter):
{"results": [{"correct": true, "note": "Tippfehler"}, {"correct": false, "note": "andere Struktur"}]}
''';

  /// Zweitmeinung für "Bild beschriften" mit eingetippten Beschriftungen –
  /// nur für die Stellen, die der lokale Vergleich (inkl. kleiner
  /// Tippfehler, AnswerChecker.diagramLabelZones) abgelehnt hat. Je Stelle:
  /// die erlaubten Beschriftungen (bei austauschbaren Stellen mehrere) und
  /// die Eingabe; [group] fasst austauschbare Stellen zusammen.
  Future<List<BlankVerdict>> checkDiagramLabelAnswers({
    required String question,
    required List<({int zone, List<String> allowed, String answer, String group})> items,
  }) async {
    final buffer = StringBuffer()..writeln('Frage: $question');
    for (final item in items) {
      final allowed = item.allowed.map((a) => '"${a.trim()}"').join(' oder ');
      final group = item.group.isEmpty ? '' : ' (Gruppe "${item.group}", austauschbar)';
      final expected = item.allowed.length > 1 ? 'eine von $allowed' : allowed;
      buffer.writeln('Stelle ${item.zone}$group: erwartet $expected – Eingabe "${item.answer.trim()}"');
    }
    final raw = await _complete(_checkDiagramLabelSystemPrompt, buffer.toString(), temperature: 0);
    return parseBlankVerdicts(_parseJsonObject(raw), items.length);
  }

  /// Liest `{"results": [{"correct": true, "note": "…"}, …]}` – oder das
  /// ältere `{"correct": [true, false, …]}` – für [count] Lücken. Fehlende
  /// oder unklare Einträge zählen als falsch; ein einzelnes `true`/`false`
  /// gilt für alle Lücken.
  static List<BlankVerdict> parseBlankVerdicts(Map<String, dynamic> parsed, int count) {
    bool isTrue(Object? v) => v == true || (v is String && v.trim().toLowerCase() == 'true');
    String? noteOf(Object? v) {
      final note = v?.toString().trim() ?? '';
      return note.isEmpty ? null : note;
    }

    final results = parsed['results'];
    if (results is List) {
      return [
        for (var i = 0; i < count; i++)
          if (i < results.length && results[i] is Map)
            (correct: isTrue((results[i] as Map)['correct']), note: noteOf((results[i] as Map)['note']))
          else if (i < results.length)
            (correct: isTrue(results[i]), note: null)
          else
            (correct: false, note: null),
      ];
    }
    final verdicts = parsed['correct'];
    if (verdicts is! List) return List.filled(count, (correct: isTrue(verdicts), note: null));
    return [
      for (var i = 0; i < count; i++) (correct: i < verdicts.length && isTrue(verdicts[i]), note: null),
    ];
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

  /// Denkanstoß VOR dem Antworten, ohne die Lösung zu verraten. Mit
  /// [previousHints] (Fehler-Leiter: die Frage ging trotz Tipp wieder
  /// schief) wird der neue Tipp deutlicher und konkreter als die bisherigen,
  /// verrät die Lösung aber weiterhin nicht.
  Future<String> generateHint({
    required String question,
    required String correctAnswer,
    List<String> previousHints = const [],
  }) async {
    final previous = previousHints.isEmpty
        ? ''
        : '\nBisherige Tipps (haben nicht gereicht – gib jetzt einen DEUTLICHEREN, konkreteren '
            'Hinweis, der einen Schritt weiter führt, ohne sie zu wiederholen und weiterhin ohne '
            'die Lösung zu nennen):\n${previousHints.map((h) => '- $h').join('\n')}';
    final raw = await _complete(
      _hintSystemPrompt,
      'Frage: $question\nLösung (NICHT verraten, nur als Hintergrund für den Tipp): $correctAnswer$previous',
    );
    return raw.trim();
  }

  static const _miniLessonSystemPrompt = '''
Du schreibst eine KURZE Lerneinheit (höchstens etwa 200 Wörter) genau zum
Thema einer Lernfrage – für jemanden, der die Frage nicht sicher
beantworten konnte. Vier kurze Absätze, jeder beginnt mit seinem Stichwort:
Worum es geht: ein, zwei Sätze Einordnung.
Kern: das Prinzip Schritt für Schritt, so dass man die Frage danach selbst
beantworten kann.
Beispiel: ein kurzes, konkretes Beispiel (nicht die Frage selbst).
Merke: ein Satz zum Behalten.
Stütze dich auf den mitgegebenen Auszug aus den Unterlagen bzw. die
Konzept-Erklärung – Begriffe und Schreibweisen wie dort; widersprich ihnen
nicht und erfinde nichts dazu. Kein JSON, keine Codefences, kein Markdown.
Formeln in LaTeX zwischen \$…\$. Antworte in der Sprache der Frage.
''';

  /// Kurze Lerneinheit zu einer Frage (siehe Flashcard.miniLesson): Worum
  /// es geht, Kern, Beispiel, Merksatz – auf Basis der Quellseite
  /// ([sourceText]) oder der Konzept-Erklärung, falls vorhanden.
  Future<String> generateMiniLesson({
    required String question,
    required String correctAnswer,
    String? sourceText,
    String? conceptExplanation,
    Uint8List? image,
  }) async {
    final buffer = StringBuffer()
      ..writeln('Frage: $question')
      ..writeln('Richtige Lösung: $correctAnswer');
    if ((conceptExplanation ?? '').trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Konzept-Erklärung aus dem Fach:')
        ..writeln(_cap(conceptExplanation!.trim(), _studyAidSourceCap));
    }
    if ((sourceText ?? '').trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Auszug aus den Unterlagen (Seite, auf der das Thema steht):')
        ..writeln(_cap(sourceText!.trim(), _studyAidSourceCap));
    }
    final raw = await _complete(_miniLessonSystemPrompt, _withOptionalImage(buffer.toString(), image));
    return raw.trim();
  }

  static const _socraticSystemPrompt = '''
Du bist ein sokratischer Tutor. Der Lernende tut sich mit einer Lernfrage
schwer (er hat sie wiederholt falsch beantwortet). Führe ihn im Dialog mit
Gegenfragen selbst zur Lösung, Schritt für Schritt.
Regeln:
1. Verrate die Lösung NIE direkt, auch nicht teilweise wörtlich. Bei
   Auswahlfragen keine Option als richtig oder falsch bezeichnen, bevor der
   Lernende sie selbst begründet hat.
2. Pro Nachricht GENAU EINE kurze Frage (insgesamt höchstens drei Sätze),
   die einen kleinen Schritt weiterführt. Knüpfe an seine letzte Antwort an;
   bei einem Fehler frag nach seinem Gedankengang oder gib ein Gegenbeispiel.
3. Steckt er fest ("weiß nicht"), gib einen kleinen Hinweis und stelle eine
   leichtere Teilfrage.
4. Beginne beim Denkfehler seiner falschen Antwort, falls sie bekannt ist.
5. Hat er die Lösung selbst gefunden UND begründet, bestätige das in ein,
   zwei Sätzen, fasse den Kerngedanken zusammen und schreibe als letzte
   Zeile genau: [[GELÖST]]
6. Stütze dich auf den Auszug aus den Unterlagen, falls mitgegeben.
Kein JSON, keine Codefences, kein Markdown. Formeln in LaTeX zwischen \$…\$.
Antworte in der Sprache der Frage und duze den Lernenden.
''';

  static final _solvedMarker = RegExp(r'\[\[\s*(GELÖST|GELOEST|SOLVED)\s*\]\]', caseSensitive: false);

  /// Ein Schritt im Sokrates-Dialog: die nächste Gegenfrage des Tutors (bei
  /// leerem [history] die erste). [solved] = der Lernende hat die Lösung
  /// selbst erarbeitet (Marker in der Antwort, der aus [reply] entfernt ist).
  Future<({String reply, bool solved})> socraticTurn({
    required String question,
    required String correctAnswer,
    String? wrongAnswer,
    String? sourceText,
    List<({bool isUser, String content})> history = const [],
    Uint8List? image,
  }) async {
    final buffer = StringBuffer()
      ..writeln('Lernfrage: $question')
      ..writeln('Richtige Lösung (NUR für dich, nicht verraten): $correctAnswer');
    if ((wrongAnswer ?? '').trim().isNotEmpty) buffer.writeln('Seine letzte falsche Antwort: $wrongAnswer');
    if ((sourceText ?? '').trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Auszug aus den Unterlagen:')
        ..writeln(_cap(sourceText!.trim(), _studyAidSourceCap));
    }
    buffer.writeln();
    if (history.isEmpty) {
      buffer.writeln('Beginne den Dialog mit deiner ersten Frage.');
    } else {
      buffer.writeln('Bisheriger Dialog:');
      for (final turn in history.length > _socraticHistoryLimit
          ? history.sublist(history.length - _socraticHistoryLimit)
          : history) {
        buffer.writeln('${turn.isUser ? 'Lernender' : 'Tutor'}: ${turn.content}');
      }
      buffer
        ..writeln()
        ..writeln('Antworte jetzt als Tutor auf die letzte Nachricht des Lernenden.');
    }
    final raw = await _complete(_socraticSystemPrompt, _withOptionalImage(buffer.toString(), image), temperature: 0.4);
    final solved = _solvedMarker.hasMatch(raw);
    return (reply: raw.replaceAll(_solvedMarker, '').trim(), solved: solved);
  }

  /// Genug Verlauf für den Zusammenhang, ohne dass lange Dialoge teuer werden.
  static const _socraticHistoryLimit = 16;

  /// Seitentext bzw. Konzept-Erklärung für Lernhilfen.
  static const _studyAidSourceCap = 6000;

  /// Text, bei vorhandenem Bild (z.B. Abbildung der Frage) als multimodale
  /// Nachricht.
  static Object _withOptionalImage(String text, Uint8List? image) => image == null
      ? text
      : [
          {'type': 'text', 'text': text},
          {'type': 'text', 'text': 'Bild zur Frage:'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,${base64Encode(image)}'},
          },
        ];

  static const _followUpSystemPrompt = '''
Du bist ein geduldiger Tutor im Gespräch mit einem Lernenden über EINE
Lernfrage, die er gerade beantwortet hat. Du bekommst die Frage, die richtige
Lösung, seine Antwort, ggf. eine schon gegebene Erklärung, ggf. einen Auszug
aus den Unterlagen und den bisherigen Dialog. Antworte auf seine letzte
Nachricht.
Je nach Nachricht:
1. Rückfrage oder "das habe ich nicht verstanden": beantworte sie direkt und
   knapp am konkreten Punkt, mit einem kleinen Beispiel, wenn es hilft.
2. Er erklärt etwas in EIGENEN WORTEN und will wissen, ob das stimmt: beginne
   mit dem Urteil ("Ja, das stimmt", "Fast", "Nicht ganz"), sag dann, was
   daran richtig ist, was fehlt oder falsch ist, und gib höchstens einen
   Hinweis zum Weiterdenken. Sei ehrlich, aber freundlich; lobe nichts, was
   nicht stimmt, und mach nichts schlechter, als es ist.
3. Er will "genauer auf einen Punkt eingehen": geh genau auf diesen Punkt
   tiefer ein (Herleitung, Hintergrund, Beispiel), nicht auf alles.
Regeln: Widersprich der gegebenen richtigen Lösung nicht. Stützt sich etwas
nicht auf die gegebenen Angaben und du bist unsicher, sag es. Höchstens 8 Sätze,
außer er bittet ausdrücklich um mehr. Normaler Fließtext (kein JSON, keine
Codefences, kein Markdown), Formeln in LaTeX zwischen \$…\$. Antworte in der
Sprache der Frage und duze den Lernenden.
''';

  /// Ein Schritt im Gespräch über eine Lernfrage nach dem Beantworten: Rückfragen,
  /// "stimmt das, was ich verstanden habe?" und "geh genauer auf … ein". [history]
  /// ist der bisherige Dialog (ohne [message]); [explanation] die schon
  /// gezeigte KI-Erklärung, [sourceText] ein Auszug aus den Unterlagen.
  Future<String> followUpAnswer({
    required String question,
    required String correctAnswer,
    String? userAnswer,
    bool? wasCorrect,
    String? explanation,
    String? sourceText,
    List<({bool isUser, String content})> history = const [],
    required String message,
  }) async {
    final buffer = StringBuffer()
      ..writeln('Lernfrage: $question')
      ..writeln('Richtige Lösung: $correctAnswer');
    if ((userAnswer ?? '').trim().isNotEmpty) buffer.writeln('Antwort des Lernenden: $userAnswer');
    if (wasCorrect != null) buffer.writeln(wasCorrect ? 'Die Antwort war richtig.' : 'Die Antwort war falsch.');
    if ((explanation ?? '').trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Bereits gegebene Erklärung:')
        ..writeln(_cap(explanation!.trim(), _studyAidSourceCap));
    }
    if ((sourceText ?? '').trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Auszug aus den Unterlagen:')
        ..writeln(_cap(sourceText!.trim(), _studyAidSourceCap));
    }
    if (history.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Bisheriger Dialog:');
      for (final turn in history.length > _socraticHistoryLimit
          ? history.sublist(history.length - _socraticHistoryLimit)
          : history) {
        buffer.writeln('${turn.isUser ? 'Lernender' : 'Tutor'}: ${turn.content}');
      }
    }
    buffer
      ..writeln()
      ..writeln('Letzte Nachricht des Lernenden:')
      ..writeln(_cap(message.trim(), 4000));
    final raw = await _complete(_followUpSystemPrompt, buffer.toString(), temperature: 0.3);
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

  static const _suggestUnitsSystemPrompt = '''
Du ordnest die hochgeladenen Materialien eines Studienfachs zu
Vorlesungseinheiten (je eine Sitzung bzw. ein zusammenhängendes Thema). Du
bekommst pro Material eine ID, den Dateinamen, die Art und einen kurzen
Inhaltsauszug. Bilde Einheiten in der Reihenfolge des Semesters (Nummern in
Dateinamen wie "VL03", "Kapitel 2", Datumsangaben und der inhaltliche
Aufbau helfen dabei). Übungsblätter und Musterlösungen gehören zur Einheit
mit dem passenden Stoff. Jede Material-ID höchstens einmal; lass Materialien
weg, die keiner Einheit sinnvoll zuzuordnen sind. Kurze, sprechende Titel
(z.B. "VL 3: Differentialgleichungen").
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{"units": [{"title": "...", "materialIds": ["..."]}]}
''';

  /// Schlägt Vorlesungseinheiten für bisher nicht zugeordnete Materialien
  /// vor (Titel + Material-IDs, in Semester-Reihenfolge). Unbekannte IDs
  /// und Doppelungen werden verworfen.
  Future<List<({String title, List<String> materialIds})>> suggestLectureUnits(
    List<({String id, String fileName, String kind, String excerpt})> materials,
  ) async {
    final buffer = StringBuffer();
    for (final m in materials) {
      buffer
        ..writeln('ID: ${m.id}')
        ..writeln('Datei: ${m.fileName} (${m.kind})')
        ..writeln('Auszug: ${_cap(m.excerpt, 700)}')
        ..writeln();
    }
    final raw = await _complete(_suggestUnitsSystemPrompt, buffer.toString());
    final parsed = _parseJsonObject(raw);
    final known = {for (final m in materials) m.id};
    final used = <String>{};
    final result = <({String title, List<String> materialIds})>[];
    for (final u in (parsed['units'] as List? ?? const [])) {
      if (u is! Map) continue;
      final title = (u['title'] ?? '').toString().trim();
      final ids = [
        for (final id in (u['materialIds'] as List? ?? const []))
          if (known.contains(id.toString()) && used.add(id.toString())) id.toString(),
      ];
      if (title.isEmpty || ids.isEmpty) continue;
      result.add((title: title, materialIds: ids));
    }
    return result;
  }

  static const _transcribeSystemPrompt = '''
Du schreibst den Text von gescannten bzw. bildbasierten Dokumentseiten ab
(Texterkennung). Gib den Inhalt jeder Seite vollständig und originalgetreu
wieder – Überschriften, Aufzählungen, Tabellen als einfache Zeilen, Formeln
in LaTeX zwischen \$…\$. Beschreibe Abbildungen nur in einem kurzen
Satz in eckigen Klammern (z.B. [Abbildung: Zellaufbau mit Beschriftung]).
Nichts zusammenfassen, nichts weglassen, nichts erfinden.
Beginne JEDE Seite mit einer eigenen Zeile <<<SEITE n>>> (n = 1, 2, … in der
Reihenfolge der Seiten in der Datei). Kein JSON, keine Codefences, keine
Einleitung.
''';

  /// Texterkennung: schickt eine (kleine) PDF an das Modell dieses Service
  /// – gedacht für das Vision-Modell – und liefert den Text je Seite.
  /// OpenRouter reicht PDFs an Modelle mit eigener PDF-Unterstützung direkt
  /// weiter, sonst über seinen OCR-Parser.
  Future<List<String>> transcribePdfPages(Uint8List pdfBytes, {required int pageCount}) async {
    final raw = await _complete(_transcribeSystemPrompt, [
      {
        'type': 'text',
        'text': 'Die Datei enthält $pageCount Seite${pageCount == 1 ? '' : 'n'}. Schreibe sie ab.',
      },
      {
        'type': 'file',
        'file': {
          'filename': 'seiten.pdf',
          'file_data': 'data:application/pdf;base64,${base64Encode(pdfBytes)}',
        },
      },
    ]);
    return splitTranscribedPages(raw, pageCount: pageCount);
  }

  /// Zerlegt die Antwort von [transcribePdfPages] an den `<<<SEITE n>>>`-
  /// Markern. Fehlen die Marker, gilt alles als Text der ersten Seite.
  static List<String> splitTranscribedPages(String raw, {required int pageCount}) {
    final pages = List<String>.filled(pageCount, '');
    final marker = RegExp(r'<<<\s*SEITE\s+(\d+)\s*>>>', caseSensitive: false);
    final matches = marker.allMatches(raw).toList();
    if (matches.isEmpty) {
      if (pageCount > 0) pages[0] = raw.trim();
      return pages;
    }
    for (var i = 0; i < matches.length; i++) {
      final number = int.tryParse(matches[i].group(1) ?? '') ?? 0;
      final end = i + 1 < matches.length ? matches[i + 1].start : raw.length;
      final text = raw.substring(matches[i].end, end).trim();
      if (number >= 1 && number <= pageCount) {
        pages[number - 1] = pages[number - 1].isEmpty ? text : '${pages[number - 1]}\n$text';
      }
    }
    return pages;
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

  static const _assignStagesSystemPrompt = '''
Du ordnest bereits vorhandene Lernfragen EINES Fachs in Ordner. Ein Ordner
enthält dieselbe Frage in verschiedenen Schwierigkeitsstufen – beim Lernen
kommt zuerst die leichte, erst wenn sie sitzt die mittlere, dann die
schwere. Sobald die schwerere Stufe dran ist, wird die leichtere NICHT mehr
abgefragt. Du bekommst eine nummerierte Liste (Nummer, Typ, Frage, Lösung).

Regeln:
- In einen Ordner gehören nur Fragen, die DASSELBE Wissen prüfen (dieselbe
  Aussage, dieselbe Definition, dieselbe Rechnung) – nur verschieden
  schwer. Wer die schwere Frage sicher kann, muss damit auch die leichte
  können. Nur dasselbe Oberthema reicht NICHT: zwei Fragen zu verschiedenen
  Fakten desselben Kapitels gehören in verschiedene Ordner.
- Eine Frage ohne solchen Partner bekommt einen eigenen Ordner.
- Stufe je Frage nach ihrem tatsächlichen Anspruch, nicht nur nach dem Typ:
  "leicht" = wiedererkennen (z.B. Auswahlfrage), "mittel" = ergänzen oder
  zuordnen (z.B. Lückentext, Zuordnen), "schwer" = selbst formulieren,
  herleiten oder anwenden (z.B. Freitext, Rechen-/Übungsaufgabe, Tabelle).
- Ordnername: kurz (2–6 Wörter), beschreibt das geprüfte Wissen, für alle
  Fragen desselben Ordners Zeichen für Zeichen gleich.
- Werden "Bereits vorhandene Ordner" genannt und prüft eine Frage genau
  deren Wissen, übernimm diesen Namen exakt statt einen neuen zu erfinden.
- Jede Nummer aus der Liste kommt genau einmal vor.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences:
{"cards": [{"n": 1, "level": "leicht", "group": "Kurzer Ordnername"}]}
''';

  /// Nummer (wie in der Anfrage) → Stufe (0–2) und Gruppe aus der Antwort
  /// von [assignStages]. Einträge ohne gültige Nummer fallen weg.
  static Map<int, ({int? level, String? group})> parseStageAssignments(Map<String, dynamic> json) => {
        for (final entry in _mapsIn(json['cards']))
          if (entry['n'] is num)
            (entry['n'] as num).toInt(): (
              level: QuestionParsing.parseStageLevel(entry['level']),
              group: QuestionParsing.parseStageGroup(entry['group']),
            ),
      };

  /// Ordnet bestehende Fragen per KI Ordnern (dasselbe Wissen, verschieden
  /// schwer) und Stufen (Leicht/Mittel/Schwer) zu. [cards] ist nummeriert
  /// (siehe [parseStageAssignments]); [knownGroups] sind die Ordnernamen aus
  /// früheren Portionen desselben Laufs – die KI übernimmt sie, damit
  /// Zusammengehöriges auch über Portionsgrenzen hinweg in EINEM Ordner
  /// landet.
  Future<Map<int, ({int? level, String? group})>> assignStages(
    List<({int n, String type, String front, String answer})> cards, {
    List<String> knownGroups = const [],
  }) async {
    final buffer = StringBuffer();
    if (knownGroups.isNotEmpty) {
      buffer.writeln('Bereits vorhandene Ordner:');
      for (final g in knownGroups) {
        buffer.writeln('- $g');
      }
      buffer.writeln();
      buffer.writeln('Fragen:');
    }
    for (final c in cards) {
      buffer.writeln('${c.n}. [${c.type}] ${_cap(c.front, 400)} — Lösung: ${_cap(c.answer, 200)}');
    }
    final raw = await _complete(_assignStagesSystemPrompt, buffer.toString());
    return parseStageAssignments(_parseJsonObject(raw));
  }

  static const _matchScriptSystemPrompt = '''
Du ordnest Lernfragen ihrer Erklärung im Skript (Vorlesungsfolien) zu. Du
bekommst nummerierte Fragen (Typ, Frage, Lösung) und je Frage einige
Kandidaten-Seiten aus dem Skript – mit Kennung, Datei, Seitenzahl und Text.
Die Fragen stammen meist aus Übungsblättern; die Erklärung oder Lösung steht
im Skript.

Wähle je Frage die Kandidaten-Seite, auf der die ERKLÄRUNG bzw. der Stoff
hinter der Lösung steht (Definition, Formel, Herleitung, Beispiel, Regel).
Regeln:
- Nur eine Kennung aus den Kandidaten DIESER Frage, nie eine erfundene.
- Eine Seite, die das Thema nur streift, nur Überschrift, Gliederung oder
  Inhaltsverzeichnis ist, zählt nicht.
- Im Zweifel null: lieber keine Fundstelle als eine falsche.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences:
{"matches": [{"n": 1, "page": "c2"}, {"n": 2, "page": null}]}
''';

  /// Ordnet Fragen der Skript-Seite zu, auf der ihre Erklärung steht. Jede
  /// Frage kommt mit ihren Kandidaten-Seiten (Kennung, Beschriftung, Text –
  /// meist die besten Treffer eines lokalen Textabgleichs). Liefert je
  /// Fragennummer die gewählte Kandidaten-Kennung oder `null` (keine passt);
  /// Kennungen, die es nicht gab, werden zu `null`.
  Future<Map<int, String?>> matchCardsToScript(
    List<
        ({
          int n,
          String type,
          String question,
          String answer,
          List<({String id, String label, String text})> candidates,
        })>
        items,
  ) async {
    final buffer = StringBuffer();
    for (final item in items) {
      buffer
        ..writeln('### Frage ${item.n} [${item.type}]')
        ..writeln('Frage: ${_cap(item.question, 500)}')
        ..writeln('Lösung: ${_cap(item.answer, 300)}')
        ..writeln('Kandidaten:');
      for (final c in item.candidates) {
        buffer.writeln('[${c.id}] ${c.label}: ${_cap(c.text.replaceAll(RegExp(r'\s+'), ' '), 800)}');
      }
      buffer.writeln();
    }
    final raw = await _complete(_matchScriptSystemPrompt, buffer.toString());
    final parsed = _parseJsonObject(raw);
    final valid = {for (final item in items) item.n: {for (final c in item.candidates) c.id}};
    return {
      for (final entry in _mapsIn(parsed['matches']))
        if (entry['n'] is num && valid.containsKey((entry['n'] as num).toInt()))
          (entry['n'] as num).toInt(): () {
            final id = entry['page']?.toString().trim();
            return id != null && valid[(entry['n'] as num).toInt()]!.contains(id) ? id : null;
          }(),
    };
  }

  /// Die Objekte einer JSON-Liste – ein einzelner kaputter Eintrag (Text
  /// statt Objekt) oder ein fehlendes Feld kostet sonst das Ergebnis des
  /// ganzen Abschnitts.
  static List<Map<String, dynamic>> _mapsIn(Object? value) => [
        if (value is List)
          for (final e in value)
            if (e is Map) Map<String, dynamic>.from(e),
      ];

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

  // -- Laborversuch ---------------------------------------------------------

  /// Text je Quelle (Anleitung, Theorie-Skript), den die KI beim Einlesen eines
  /// Versuchs sieht – längere Skripte werden gekürzt.
  static const labSourceCap = 45000;

  static const _labStructureSystemPrompt = '''
Du bist Assistent für Laborpraktika an einer Hochschule. Du bekommst die
Unterlagen zu EINEM Versuch (Versuchsanleitung/Durchführung und/oder ein
Theorie-Skript zum Versuch) und liest daraus die Struktur heraus, damit sich
die Studierenden vorbereiten, den Versuch durchführen und den Bericht
schreiben können. Du beantwortest nichts und erfindest nichts: nur, was in den
Unterlagen steht.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences, ohne Text
davor oder danach, in genau diesem Format:
{
  "title": "Name des Versuchs",
  "prepQuestions": [{"number": "1a", "question": "Wortlaut der Vorbereitungsaufgabe"}],
  "parts": [
    {
      "title": "Name des Versuchsteils bzw. der Aufgabe",
      "goals": ["Ziel oder Fragestellung dieses Teils"],
      "steps": ["Ein Arbeitsschritt, kurz und im Imperativ"],
      "tables": [
        {"title": "Name der Messwerttabelle",
         "columns": ["Spaltenüberschrift 1", "Spaltenüberschrift 2"],
         "rows": [["Vorgabe aus der Anleitung", ""], ["", ""]]}
      ],
      "evaluationQuestions": [{"number": "2.1", "question": "Frage oder Aufgabe zur Auswertung"}]
    }
  ],
  "hints": ["Organisatorisches: was mitzubringen ist, Sicherheit, Abgabe"]
}
Regeln:
1. "prepQuestions": ALLE Aufgaben/Fragen, die vor dem Versuch schriftlich zu
   bearbeiten oder vorzubereiten sind (Vorbereitungsaufgaben, Fragen zur
   Vorbereitung, "Machen Sie sich vertraut mit …", auch wenn sie im
   Theorie-Skript stehen). Wortlaut und Nummerierung ("1a", "3", "2.4.1")
   übernehmen; Unteraufgaben einzeln, wenn sie einzeln beantwortet werden.
   Nichts ergänzen, was nicht gefragt wird.
2. "parts": die Teile der Durchführung in der Reihenfolge der Anleitung.
   "steps" sind konkrete Handlungen am Aufbau (Einstellen, Anschließen,
   Messen, Speichern), je Eintrag EINE Handlung. Verweise, Erklärungen und
   Theorie gehören nicht in die Schritte.
3. "tables": jede Tabelle, in die Messwerte einzutragen sind. Kopfzeile in
   "columns", danach je Zeile alle Zellen; was in der Anleitung schon
   vorgegeben ist (z.B. Einstellwerte, Beschriftungen) steht als Text in der
   Zelle, was gemessen bzw. eingetragen werden soll, ist "" (leerer String).
   Jede Zeile hat genau so viele Zellen wie "columns".
4. "evaluationQuestions": Fragen und Aufgaben, die während oder nach dem
   Versuchsteil zu beantworten sind (Auswertung, Beobachtung, Vergleich,
   Skizze). Nummerierung wie in der Anleitung, sonst weglassen.
5. Fehlt etwas in den Unterlagen, lass die Liste leer statt zu raten. Gibt es
   keinen erkennbaren Namen, lass "title" leer.
6. Formeln in LaTeX (\$…\$) und in JSON jeden Backslash verdoppeln.
Antworte in der Sprache der Unterlagen.
''';

  /// Liest aus den Unterlagen eines Versuchs ([sources]: Bezeichnung und Text,
  /// z.B. „Versuchsanleitung“, „Theorie-Skript“) Vorbereitungsfragen, Versuchs-
  /// teile mit Schritten/Messwerttabellen/Auswertungsfragen und Hinweise
  /// heraus. Das Ergebnis ist die rohe Struktur für
  /// `LabExperiment.fromStructure`.
  Future<Map<String, dynamic>> structureLabExperiment({
    required List<({String label, String text})> sources,
  }) async {
    final buffer = StringBuffer();
    for (final source in sources) {
      if (source.text.trim().isEmpty) continue;
      buffer
        ..writeln('=== ${source.label} ===')
        ..writeln(_cap(source.text.trim(), labSourceCap))
        ..writeln();
    }
    if (buffer.isEmpty) {
      throw AiServiceException('Aus den gewählten Unterlagen konnte kein Text gelesen werden.');
    }
    final raw = await _complete(_labStructureSystemPrompt, buffer.toString(), temperature: 0.1);
    return _parseJsonObject(raw);
  }

  static const _labAnswerReviewSystemPrompt = '''
Du bist Betreuer im Laborpraktikum und liest die SELBST geschriebene Antwort
eines Studierenden auf eine Aufgabe zur Versuchsvorbereitung (oder Auswertung)
gegen. Er soll den Stoff selbst verstehen und die Antwort selbst schreiben.
Regeln:
1. Schreibe KEINE Musterlösung und keine Sätze, die er übernehmen könnte. Sag,
   was an seiner Antwort stimmt, was fehlt oder nicht stimmt (Fehler knapp
   benennen und begründen) und wo er nachschauen kann – mehr nicht.
2. Beurteile nur anhand der Aufgabe, der Antwort und der mitgegebenen
   Auszüge aus den Unterlagen bzw. Messwerten. Reichen die Auszüge nicht
   aus, sag das ehrlich, statt etwas zu erfinden.
3. "verdict": "gut" (inhaltlich richtig und vollständig genug), "teilweise"
   (richtiger Ansatz, aber Lücken oder Fehler) oder "unklar" (geht am Kern
   vorbei oder ist nicht nachvollziehbar).
4. "summary": ein bis zwei Sätze ehrliche Einschätzung, du-Form.
5. "missing": höchstens vier kurze Punkte – was fehlt oder nicht stimmt, als
   Aspekt benannt ("Du gehst nicht darauf ein, wie …"), ohne die Lösung
   auszuformulieren. Bei "gut" leer.
6. "hints": höchstens drei Hinweise, wo bzw. worüber er nachlesen oder
   nachdenken soll (Kapitel, Seite, Begriff). Bei "gut" leer.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Codefences, ohne Text davor
oder danach:
{"verdict": "gut|teilweise|unklar", "summary": "…", "missing": ["…"], "hints": ["…"]}
Formeln in LaTeX (\$…\$), in JSON jeden Backslash verdoppeln. Antworte in der
Sprache der Aufgabe.
''';

  /// Liest die Antwort [answer] auf die Aufgabe [question] gegen: Einschätzung,
  /// was fehlt, und Hinweise – bewusst ohne Musterlösung. [context] sind
  /// Auszüge aus dem Skript, [measurements] die Messwerte des Versuchsteils
  /// (bei Auswertungsfragen).
  Future<LabFeedback> reviewLabAnswer({
    required String experimentTitle,
    required String number,
    required String question,
    required String answer,
    String context = '',
    String measurements = '',
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    if (answer.trim().isEmpty) return parseLabFeedback(const {'verdict': 'leer'}, forText: answer, at: at);
    final buffer = StringBuffer()
      ..writeln('Versuch: $experimentTitle')
      ..writeln('Aufgabe ${number.isEmpty ? '' : '$number: '}$question');
    if (measurements.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Messwerte des Versuchsteils:')
        ..writeln(_cap(measurements.trim(), _labMeasurementCap));
    }
    if (context.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Auszüge aus den Unterlagen:')
        ..writeln(_cap(context.trim(), _labContextCap));
    }
    buffer
      ..writeln()
      ..writeln('Antwort des Studierenden:')
      ..writeln(_cap(answer.trim(), _labAnswerCap));
    final raw = await _complete(_labAnswerReviewSystemPrompt, buffer.toString(), temperature: 0);
    return parseLabFeedback(_parseJsonObject(raw), forText: answer, at: at);
  }

  static const _labReportReviewSystemPrompt = '''
Du bist Gegenleser für Laborberichte. Ein Studierender hat einen Abschnitt
seines Berichts SELBST geschrieben und möchte vor der Abgabe Rückmeldung.
Regeln:
1. Schreibe den Text NICHT um und liefere keine Formulierungen zum Übernehmen.
   Du sagst, was gut ist, was fehlt oder nicht stimmt und woran es liegt.
2. Prüfe: Stimmen genannte Werte mit den mitgegebenen Messwerten überein?
   Fehlen Einheiten oder Messabweichungen? Sind die Schlüsse aus den Messwerten
   nachvollziehbar? Sind die zum Abschnitt gehörenden Fragen beantwortet?
   Ist der Aufbau bzw. die Durchführung so beschrieben, dass andere den
   Versuch wiederholen könnten? Sachliche Fehler benennen.
3. Sprache und Stil nur kurz ansprechen, wenn sie das Verständnis stören
   (Umgangssprache, Ich-Form statt Passiv, wenn im Bericht üblich, sehr
   lange Sätze).
4. Beurteile nur, was im Text und in den mitgegebenen Daten steht. Erfinde
   keine Messwerte und nimm keine an.
5. "verdict": "gut" (kann so bleiben), "teilweise" (Lücken oder Fehler) oder
   "unklar" (Kern fehlt oder ist nicht nachvollziehbar).
6. "summary": ein bis zwei Sätze Gesamteindruck, du-Form.
7. "missing": höchstens fünf Punkte – was fehlt, nicht stimmt oder unklar ist,
   jeweils mit Bezug zur Stelle. Bei "gut" leer.
8. "hints": höchstens drei Hinweise, wie er es selbst verbessern kann (worauf
   er achten, wo er nachsehen soll).
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Codefences, ohne Text davor
oder danach:
{"verdict": "gut|teilweise|unklar", "summary": "…", "missing": ["…"], "hints": ["…"]}
Formeln in LaTeX (\$…\$), in JSON jeden Backslash verdoppeln. Antworte in der
Sprache des Berichts.
''';

  /// Liest den Berichtsabschnitt [text] gegen. [measurements] sind die Messwerte
  /// des zugehörigen Versuchsteils, [answers] die dort schon beantworteten
  /// Fragen (Aufgabe und Antwort), [context] Auszüge aus den Unterlagen.
  Future<LabFeedback> reviewReportSection({
    required String experimentTitle,
    required String sectionTitle,
    required String hint,
    required String text,
    String measurements = '',
    String answers = '',
    String context = '',
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    if (text.trim().isEmpty) return parseLabFeedback(const {'verdict': 'leer'}, forText: text, at: at);
    final buffer = StringBuffer()
      ..writeln('Versuch: $experimentTitle')
      ..writeln('Abschnitt: $sectionTitle');
    if (hint.trim().isNotEmpty) buffer.writeln('Was in den Abschnitt gehört: ${hint.trim()}');
    if (measurements.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Messwerte:')
        ..writeln(_cap(measurements.trim(), _labMeasurementCap));
    }
    if (answers.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Bereits beantwortete Auswertungsfragen:')
        ..writeln(_cap(answers.trim(), _labContextCap));
    }
    if (context.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Auszüge aus den Unterlagen:')
        ..writeln(_cap(context.trim(), _labContextCap));
    }
    buffer
      ..writeln()
      ..writeln('Text des Abschnitts:')
      ..writeln(_cap(text.trim(), _labReportCap));
    final raw = await _complete(_labReportReviewSystemPrompt, buffer.toString(), temperature: 0);
    return parseLabFeedback(_parseJsonObject(raw), forText: text, at: at);
  }

  static const _labContextCap = 9000;
  static const _labMeasurementCap = 4000;
  static const _labAnswerCap = 4000;
  static const _labReportCap = 12000;

  /// Liest die Einschätzung der KI zu einer Antwort bzw. einem Berichts-
  /// abschnitt ([forText] = der begutachtete Wortlaut). Unbekannte Urteile
  /// werden zu "unklar"; bei "gut" entfallen Anmerkungen und Hinweise.
  static LabFeedback parseLabFeedback(Map<String, dynamic> json, {required String forText, required DateTime at}) {
    List<String> strings(Object? v, int limit) => [
          if (v is List)
            for (final e in v)
              if (e.toString().trim().isNotEmpty) e.toString().trim(),
          if (v is String && v.trim().isNotEmpty) v.trim(),
        ].take(limit).toList();
    final verdict = switch ('${json['verdict']}'.trim().toLowerCase()) {
      'gut' || 'good' || 'ok' || 'richtig' || 'correct' => 'gut',
      'teilweise' || 'partial' || 'partly' || 'teilweise richtig' => 'teilweise',
      'leer' || 'empty' => 'leer',
      _ => 'unklar',
    };
    return LabFeedback(
      verdict: verdict,
      summary: '${json['summary'] ?? ''}'.trim(),
      missing: verdict == 'gut' ? const [] : strings(json['missing'], 5),
      hints: verdict == 'gut' ? const [] : strings(json['hints'], 3),
      forText: forText,
      at: at,
    );
  }

  // -- Rechnen ---------------------------------------------------------------

  static const _calcPlanSystemPrompt = r"""
Du bist Rechenassistent für Labor- und Übungsaufgaben (Ingenieurwesen,
Naturwissenschaften). Du bekommst eine Aufgabe, Werte (Text, Tabellen) und/oder
Bilder (Foto der Aufgabe, einer Tabelle, eines Messprotokolls, Bild eines
Messgeräts oder Oszilloskops, Schaltplan). Du stellst den RECHENPLAN auf – die
App rechnet selbst mit einem Formelauswerter. Du gibst deshalb NIE Ergebnisse
an, nur Gegebenes und Formeln.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences, ohne Text
davor oder danach, in genau diesem Format:
{
  "title": "Kurzer Titel der Rechnung",
  "given": [
    {"symbol": "R_1", "name": "Widerstand 1", "raw": "4,7 kΩ", "values": [4700],
     "unit": "Ω", "kind": "given", "uncertain": false}
  ],
  "steps": [
    {"symbol": "R", "name": "Gesamtwiderstand", "latex": "$R = R_1 + R_2$",
     "expression": "R_1 + R_2", "unit": "Ω", "explanation": "Reihenschaltung: Widerstände addieren sich."}
  ],
  "result": ["R"],
  "assumptions": [],
  "notes": [],
  "missing": []
}
Regeln:
1. Werte lesen: Übernimm aus Text UND Bildern alle Werte, die die Aufgabe
   braucht, Tabellen Zeile für Zeile. "raw" = so, wie es im Bild bzw. Text
   steht (mit Einheit), damit der Nutzer vergleichen kann. "values" = Zahlen
   in der GRUNDEINHEIT: Vorsätze umrechnen (4,7 kΩ → 4700 Ω, 250 mV → 0.25 V,
   12 µs → 1.2e-5 s). Dezimalpunkt in JSON-Zahlen. "unit" = Grundeinheit ohne
   Vorsatz ("Ω", "V", "s", "m/s"). Mehrere Messungen derselben Größe = EINE
   Größe mit mehreren "values" in der Reihenfolge der Tabelle (Zeile 1 zuerst),
   gleich viele Werte wie in den zugehörigen anderen Reihen. Winkel bleiben in
   der Einheit des Bildes/Textes ("°" oder "rad"); in Formeln rad(x) für
   Grad → Bogenmaß.
   Kannst du einen Wert nicht sicher lesen (unscharf, mehrdeutig, geschätzt,
   abgeschnitten), setze "uncertain": true und schreib in "raw", was du
   gelesen hast – rate nicht stillschweigend.
2. Konstanten (Elementarladung, Boltzmann, µ0, ε0, g …) nur, wenn die Aufgabe
   sie braucht, als "given" mit "kind": "constant", Standardwert und "name".
   Steht in den Unterlagen ein anderer Wert (z. B. g = 9,81 m/s²), nimm
   diesen.
3. Schritte in Rechenreihenfolge, jeder Schritt ist EINE Größe. "symbol": nur
   Buchstaben, Ziffern und Unterstrich, beginnt mit einem Buchstaben ("R_1",
   "U_aus", "f_g"), NICHT wie eine Funktion oder Konstante (nicht "pi", "e",
   "sin", "min", "n", "sum" …). Spätere Schritte dürfen frühere Größen und
   gegebene verwenden. "expression" ist der Ausdruck zum Rechnen, ausschließlich
   aus Zahlen (Punkt als Dezimalzeichen), Größen (given und frühere Schritte),
   + - * / ^, Klammern und diesen Funktionen: {{FUNCTIONS}}.
   Schreib jedes Mal * für Multiplikation (nicht "2x", nicht "2(x)"); keine
   Einheiten, keine Wörter, keine Zuweisung, keine Prozentzeichen (Prozent =
   Faktor 100 *). "latex" = dieselbe Formel als LaTeX zwischen Dollarzeichen für
   die Anzeige ("$R = \\frac{U}{I}$"). "unit" = Einheit des
   Ergebnisses. "explanation" = ein Satz: welches Gesetz bzw. warum.
   Prüfe, dass die Einheiten deiner Formeln zusammenpassen.
4. Reihen: Ist eine Größe eine Reihe, rechnet die Formel automatisch für jede
   Zeile. Kennzahlen der Reihe (Mittelwert, Standardabweichung, Steigung einer
   Ausgleichsgeraden …) als eigene Schritte danach.
5. Messunsicherheit nur, wenn Unsicherheiten/Toleranzen angegeben sind oder
   danach gefragt wird: Gaußsche Fehlerfortpflanzung als eigene Schritte
   (Größen wie "u_R").
6. "result": die Symbole der Schritte, die die gesuchten Endergebnisse sind.
   Rechne, was die Aufgabe verlangt; nützliche Zwischengrößen sind Schritte,
   aber keine Ergebnisse.
7. Fehlt ein Wert oder eine Angabe, erfinde nichts: nenne es in "missing" ("Die
   Länge l des Drahts ist nicht angegeben") und plane, was möglich ist.
   "assumptions": Annahmen, die du triffst (ideale Bauteile, Raumtemperatur …).
   "notes": höchstens vier kurze Hinweise zur Plausibilität (Größenordnung,
   auffällige Werte, Einheit prüfen).
8. Überarbeitung: Bekommst du einen bisherigen Plan und einen Wunsch des
   Nutzers, gib den KOMPLETTEN neuen Plan aus; übernimm Werte, die der Nutzer
   korrigiert hat, exakt, und ändere nur, was der Wunsch verlangt.
Antworte in der Sprache der Aufgabe (Standard: Deutsch).
""";

  /// Grenzen für die Texte, die die KI beim Rechnen sieht.
  static const _calcTaskCap = 4000;
  static const _calcValuesCap = 8000;
  static const _calcContextCap = 9000;

  /// Stellt den Rechenplan zu einer Aufgabe auf: liest Werte aus [values]
  /// (Text, Tabellen) und [images] (Fotos, Screenshots) und liefert gegebene
  /// Größen, Formeln und Annahmen – gerechnet wird in der App
  /// ([CalcPlan.evaluate]). [context] sind weitere Angaben (z.B. die
  /// Messwerte des Versuchs). Mit [previous] und [instruction] wird ein Plan
  /// nach Wunsch überarbeitet. Für Bilder ein Vision-Modell wählen.
  Future<CalcPlan> planCalculation({
    String task = '',
    String values = '',
    List<Uint8List> images = const [],
    String context = '',
    CalcPlan? previous,
    String instruction = '',
  }) async {
    if (task.trim().isEmpty && values.trim().isEmpty && images.isEmpty && previous == null) {
      throw AiServiceException('Gib eine Aufgabe, Werte oder ein Bild an.');
    }
    final buffer = StringBuffer();
    if (task.trim().isNotEmpty) {
      buffer
        ..writeln('Aufgabe / Wunsch:')
        ..writeln(_cap(task.trim(), _calcTaskCap))
        ..writeln();
    }
    if (values.trim().isNotEmpty) {
      buffer
        ..writeln('Werte (vom Nutzer eingegeben):')
        ..writeln(_cap(values.trim(), _calcValuesCap))
        ..writeln();
    }
    if (context.trim().isNotEmpty) {
      buffer
        ..writeln('Weitere Angaben zum Versuch:')
        ..writeln(_cap(context.trim(), _calcContextCap))
        ..writeln();
    }
    if (previous != null) {
      buffer
        ..writeln('Bisheriger Plan (JSON):')
        ..writeln(jsonEncode(previous.toJson()))
        ..writeln()
        ..writeln('Wunsch des Nutzers zur Überarbeitung:')
        ..writeln(instruction.trim().isEmpty ? 'Prüfe den Plan noch einmal und korrigiere Fehler.' : instruction.trim())
        ..writeln();
    }
    if (images.isNotEmpty) {
      buffer.writeln('Dem Text folgen ${images.length} Bild${images.length == 1 ? '' : 'er'}.');
    }
    final system = _calcPlanSystemPrompt.replaceFirst('{{FUNCTIONS}}', CalcEngine.functionNames);
    final Object content = images.isEmpty
        ? buffer.toString()
        : [
            {'type': 'text', 'text': buffer.toString()},
            for (final (i, image) in images.indexed) ...[
              {'type': 'text', 'text': 'Bild ${i + 1} von ${images.length}:'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:${_imageMime(image)};base64,${base64Encode(image)}'},
              },
            ],
          ];
    final raw = await _complete(system, content, temperature: 0);
    final plan = CalcPlan.fromJson(_parseJsonObject(raw));
    if (plan.isEmpty && plan.missing.isEmpty) {
      throw AiServiceException(
        'Die KI hat keinen brauchbaren Rechenplan geliefert – bitte die Aufgabe genauer beschreiben oder erneut versuchen.',
        rawResponse: raw,
      );
    }
    return plan;
  }

  /// Der MIME-Typ eines Bildes nach seinen ersten Bytes (Standard PNG).
  static String _imageMime(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b.length > 11 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
    return 'image/png';
  }


  // -- Fotos zu Laborversuchen --------------------------------------------------

  static const _labPhotoSystemPrompt = r"""
Du hilfst bei einem Laborpraktikum. Du bekommst ein FOTO (Messprotokoll,
handschriftliche Notizen, Anzeige eines Messgeräts, Oszilloskop, Tafel,
Versuchsaufbau, Tabelle) und eine Übersicht der Versuche des Fachs mit ihren
Versuchsteilen und Messwerttabellen. Deine Aufgaben:
1. Erkenne, was das Foto zeigt, und ordne es dem passenden Versuch und
   Versuchsteil zu: Titel, Nummern, Bezeichnungen, Größen und Einheiten, Spalten
   der Tabellen. Bist du nicht sicher, setze "experimentId" auf null; ein Raten
   ist schlimmer als keine Zuordnung. "confidence": "hoch", "mittel" oder "niedrig".
2. Lies die Werte genau ab und trage sie in die LEEREN Zellen der passenden
   Tabelle ein ("cells"). Nummeriert wird ab 1: "table" = Nummer der Tabelle im
   Versuchsteil, "row" = Zeile OHNE Kopfzeile, "col" = Spalte. "value" so, wie
   es in der Tabelle stehen soll (Zahl mit Einheit nur, wenn die Spalte die
   Einheit nicht schon nennt; Komma wie auf dem Foto). Zellen, die schon einen
   Wert haben, nur nennen, wenn das Foto etwas anderes zeigt.
3. Alles, was in keine Zelle passt (weitere Messwerte, Geräteeinstellungen,
   Skalen, Beobachtungen), kurz in "notes" mit Einheiten.
4. ERFINDE NICHTS. Nicht lesbare oder unsichere Stellen kommen NICHT in "cells",
   sondern als kurzer Eintrag in "unclear" ("Zeile 3, zweite Spalte: Ziffer
   unleserlich").
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences:
{
  "description": "Ein Satz: was das Foto zeigt",
  "experimentId": "Kennung des Versuchs oder null",
  "partId": "Kennung des Versuchsteils oder null",
  "confidence": "hoch|mittel|niedrig",
  "cells": [{"table": 1, "row": 2, "col": 3, "value": "4,7"}],
  "notes": "weitere Werte als kurzer Text oder leer",
  "unclear": []
}
Antworte in der Sprache der Tabellen (Standard: Deutsch).
""";

  /// Die Versuche mit Teilen und Tabellen als Text für [readLabPhoto] – Zeilen
  /// und Spalten ab 1, leere Zellen als "·" (zum Ausfüllen).
  static String describeExperimentsForPhoto(List<LabExperiment> experiments) {
    final b = StringBuffer();
    for (final e in experiments) {
      b.writeln('VERSUCH ${e.id}: ${e.title}');
      for (final p in e.parts) {
        b.writeln('  TEIL ${p.id}: ${p.title}');
        for (final g in p.goals.take(2)) {
          b.writeln('    Ziel: ${_cap(g, 160)}');
        }
        for (final (t, table) in p.tables.indexed) {
          b.writeln('    Tabelle ${t + 1}${table.title.trim().isEmpty ? '' : ' (${table.title.trim()})'}:');
          if (table.columns.isNotEmpty) {
            b.writeln('      Spalten: ${[for (final (i, c) in table.columns.indexed) '${i + 1}=$c'].join(' | ')}');
          }
          for (var r = 0; r < table.rows.length && r < 40; r++) {
            final cells = [
              for (var c = 0; c < table.rows[r].length; c++)
                table.editable[r][c] && table.rows[r][c].trim().isEmpty
                    ? '·'
                    : (table.rows[r][c].trim().isEmpty ? '–' : table.rows[r][c].trim()),
            ];
            b.writeln('      Zeile ${r + 1}: ${cells.join(' | ')}');
          }
        }
      }
      b.writeln();
    }
    return _cap(b.toString().trim(), _labPhotoOverviewCap);
  }

  static const _labPhotoOverviewCap = 14000;

  /// Liest ein Foto zu einem Laborversuch: ordnet es einem der [experiments]
  /// (und Versuchsteil) zu und liest Messwerte für deren leere Tabellenzellen
  /// ab. Antwort als [LabPhotoReading]; Kennungen sind schon gegen
  /// [experiments] geprüft. Für Bilder ein Vision-Modell wählen.
  Future<LabPhotoReading> readLabPhoto({required Uint8List image, required List<LabExperiment> experiments}) async {
    final text = StringBuffer()
      ..writeln('Versuche des Fachs:')
      ..writeln(experiments.isEmpty ? '(noch keine)' : describeExperimentsForPhoto(experiments))
      ..writeln()
      ..writeln('Das Foto folgt.');
    final content = [
      {'type': 'text', 'text': text.toString()},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:${_imageMime(image)};base64,${base64Encode(image)}'},
      },
    ];
    final raw = await _complete(_labPhotoSystemPrompt, content, temperature: 0);
    final reading = LabPhotoReading.fromJson(_parseJsonObject(raw), experiments);
    if (reading.isEmpty) {
      throw AiServiceException('Die KI konnte auf dem Foto nichts lesen – anderes Foto oder bessere Beleuchtung versuchen.',
          rawResponse: raw);
    }
    return reading;
  }

  // -- Berichtsentwurf --------------------------------------------------------

  static const _labDraftSystemPrompt = r"""
Du hilfst einem Studierenden, einen Laborbericht zu beginnen. Du schreibst einen
groben ENTWURF, der nur als Inspiration dient: Er soll trotzdem schon gut
lesbar sein und alles enthalten, was aus den Daten hervorgeht – aber der
Studierende schreibt seinen Bericht selbst und prüft jede Aussage.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences, ohne Text
davor oder danach, in genau diesem Format:
{
  "sections": [
    {"sectionId": "id eines vorhandenen Abschnitts oder null", "title": "Überschrift", "text": "Entwurf des Abschnitts"}
  ],
  "missing": ["Was noch fehlt"]
}
Regeln:
1. Grundlage sind NUR die mitgegebenen Daten: Versuchsbeschreibung, Messwerte,
   Notizen (auch dort gespeicherte Rechenwege), Antworten des Studierenden,
   Auszüge aus den Unterlagen. Erfinde keine Messwerte, Geräte, Einstellungen,
   Ergebnisse, Quellen oder Zitate. Wo eine Angabe fehlt, schreib an die Stelle
   "[ergänzen: was genau]" und nenne es zusätzlich in "missing".
2. Vorlage und Vorgaben: Folge der Gliederung der Vorlage (Überschriften,
   Reihenfolge) und ihren Formalia (Umfang, Zeitform, Passiv/Wir-Form,
   Beschriftung von Abbildungen und Tabellen, Zitierweise). Ohne Vorlage nutze
   die vorhandenen Abschnitte. Widerspricht die Vorlage der Abschnittsliste,
   geht die Vorlage vor.
3. Zuordnung: Gehört ein Entwurfsabschnitt zu einem vorhandenen Abschnitt, trag
   dessen "id" als "sectionId" ein (mehrere Einträge dürfen zum selben gehören).
   Kennt nur die Vorlage den Abschnitt (z.B. "Anhang", "Literatur"), setz
   "sectionId": null. Steht in der Anfrage, dass die Gliederung der Vorlage NICHT
   übernommen werden soll, ordne alles den vorhandenen Abschnitten zu.
4. Stil: sachlich und fachsprachlich, ganze Sätze (im Modus "Gerüst":
   Stichpunkte mit kurzen Erläuterungen), Durchführung in der Vergangenheit.
   Formeln in LaTeX zwischen Dollarzeichen ($…$), in JSON jeden Backslash
   verdoppeln. Zahlen exakt aus den Daten übernehmen, mit Einheit. Rechenwege aus
   den Notizen einbauen (Formel, eingesetzte Werte, Ergebnis) statt neu zu
   rechnen.
5. Messwerte als kurze Textzeile bzw. Tabelle mit "Tabelle 1: …" (Spalten mit
   | getrennt); wo eine Abbildung hingehört: "[Abbildung: was gezeigt werden
   soll, Achsen, Beschriftung]".
6. Diskussion und Fazit: vergleiche mit Erwartung/Theorie nur, wenn Daten oder
   Unterlagen dazu vorliegen, sonst schreib "[ergänzen: Vergleich mit …]". Nenne
   mögliche Fehlerquellen nur als Vorschläge ("Mögliche Ursachen: …"), die aus den
   Daten ableitbar sind.
7. Eigene Texte des Studierenden (falls mitgegeben): berücksichtige ihre Aussagen
   und widersprich ihnen nicht ohne Grund, schreib aber trotzdem einen eigenen
   Entwurf für den Abschnitt.
8. Länge je Abschnitt so kurz wie möglich, so lang wie nötig (meist 60–250
   Wörter). Kein Titelblatt und kein Inhaltsverzeichnis, außer die Vorlage
   verlangt Text dafür.
9. "missing": höchstens acht kurze Punkte – welche Angaben oder Anlagen
   (Schaltplan, Diagramme, Geräteliste, Messunsicherheiten, Quellen …) noch
   fehlen.
Antworte in der Sprache der Vorlage bzw. der Unterlagen (Standard: Deutsch).
""";

  static const _labDraftTemplateCap = 14000;
  static const _labDraftDataCap = 16000;
  static const _labDraftOwnCap = 12000;

  /// Schreibt einen groben Berichtsentwurf. [sections] sind die vorhandenen
  /// Berichtsabschnitte (id, Titel, Hinweis, Versuchsteil), [templates] Vorlage
  /// und Vorgaben als Text (Bezeichnung, Inhalt), [images] Vorlagen als Bild
  /// (Vision-Modell). [data] ist die Beschreibung des Versuchs mit Messwerten,
  /// Notizen und Antworten, [context] Auszüge aus den Unterlagen, [ownTexts] die
  /// bisherigen eigenen Berichtstexte. Mit [onlySectionId] entsteht nur der
  /// Entwurf dieses Abschnitts; mit [outline] ein Gerüst statt ausformulierter
  /// Sätze; [adoptStructure] übernimmt die Gliederung der Vorlage.
  Future<LabReportDraft> draftLabReport({
    required String experimentTitle,
    required List<({String id, String title, String hint, String? partTitle})> sections,
    List<({String label, String text})> templates = const [],
    List<Uint8List> images = const [],
    String specs = '',
    required String data,
    String context = '',
    String ownTexts = '',
    String? onlySectionId,
    bool outline = false,
    bool adoptStructure = true,
  }) async {
    if (sections.isEmpty && templates.isEmpty && images.isEmpty && specs.trim().isEmpty) {
      throw AiServiceException('Es gibt weder Berichtsabschnitte noch eine Vorlage, an der sich der Entwurf ausrichten kann.');
    }
    final buffer = StringBuffer()
      ..writeln('Versuch: $experimentTitle')
      ..writeln('Modus: ${outline ? 'Gerüst (Stichpunkte)' : 'ausformuliert'}');
    final hasTemplate = templates.any((t) => t.text.trim().isNotEmpty) || images.isNotEmpty || specs.trim().isNotEmpty;
    if (hasTemplate) {
      buffer.writeln(
        adoptStructure
            ? 'Gliederung: der Vorlage folgen (neue Abschnitte mit "sectionId": null sind erlaubt).'
            : 'Gliederung: die Gliederung der Vorlage NICHT übernehmen – alles den vorhandenen Abschnitten zuordnen.',
      );
    }
    if (onlySectionId != null) {
      buffer.writeln('Schreibe NUR den Entwurf für den Abschnitt mit der id $onlySectionId (ein einziger Eintrag in "sections").');
    }
    buffer.writeln();
    for (final t in templates) {
      if (t.text.trim().isEmpty) continue;
      buffer
        ..writeln('=== Vorlage / Vorgaben: ${t.label} ===')
        ..writeln(_cap(t.text.trim(), _labDraftTemplateCap))
        ..writeln();
    }
    if (specs.trim().isNotEmpty) {
      buffer
        ..writeln('=== Vorgaben des Studierenden ===')
        ..writeln(_cap(specs.trim(), _labContextCap))
        ..writeln();
    }
    buffer.writeln('Vorhandene Abschnitte des Berichts:');
    for (final s in sections) {
      buffer.writeln(
        '- id=${s.id} | ${s.title}${s.hint.trim().isEmpty ? '' : ' | ${s.hint.trim().replaceAll('\n', ' ')}'}'
        '${s.partTitle == null ? '' : ' | gehört zum Versuchsteil "${s.partTitle}"'}',
      );
    }
    buffer
      ..writeln()
      ..writeln('=== Daten des Versuchs ===')
      ..writeln(_cap(data.trim(), _labDraftDataCap))
      ..writeln();
    if (context.trim().isNotEmpty) {
      buffer
        ..writeln('=== Auszüge aus den Unterlagen ===')
        ..writeln(_cap(context.trim(), _labContextCap))
        ..writeln();
    }
    if (ownTexts.trim().isNotEmpty) {
      buffer
        ..writeln('=== Bisherige eigene Texte des Studierenden ===')
        ..writeln(_cap(ownTexts.trim(), _labDraftOwnCap))
        ..writeln();
    }
    if (images.isNotEmpty) {
      buffer.writeln('Dem Text folgen ${images.length} Bild${images.length == 1 ? '' : 'er'} der Vorlage bzw. Vorgaben.');
    }
    final Object content = images.isEmpty
        ? buffer.toString()
        : [
            {'type': 'text', 'text': buffer.toString()},
            for (final (i, image) in images.indexed) ...[
              {'type': 'text', 'text': 'Vorlage, Bild ${i + 1} von ${images.length}:'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:${_imageMime(image)};base64,${base64Encode(image)}'},
              },
            ],
          ];
    final raw = await _complete(_labDraftSystemPrompt, content, temperature: 0.4);
    final draft = LabReportDraft.fromJson(
      _parseJsonObject(raw),
      knownSectionIds: {for (final s in sections) s.id},
      sectionTitles: {for (final s in sections) s.id: s.title},
    );
    if (draft.isEmpty) {
      throw AiServiceException('Die KI hat keinen brauchbaren Entwurf geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return draft;
  }

  // -------------------------------------------------------------------------
  // Interaktive Aufgaben: Rechenweg und Terminierung
  // -------------------------------------------------------------------------

  static const _interactiveTaskCap = 8000;

  static Object _textWithImages(String text, List<Uint8List> images, String imageLabel) => images.isEmpty
      ? text
      : [
          {'type': 'text', 'text': text},
          for (final (i, image) in images.indexed) ...[
            {'type': 'text', 'text': '$imageLabel ${i + 1} von ${images.length}:'},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:${_imageMime(image)};base64,${base64Encode(image)}'},
            },
          ],
        ];

  /// Macht aus Übungsaufgaben (Text und/oder Bilder, optional mit
  /// vorhandener Lösung) interaktive Aufgaben – je Teilaufgabe ein Entwurf:
  /// Rechenweg, Terminierung, Kristallgitter, Stückliste oder Diagramm-Skizze.
  /// Die KI liefert nur Struktur und erwartete Antworten – nachgerechnet wird
  /// in der App (StepChecker, GanttScheduler, CrystalGeometry, BomCalculator,
  /// SketchChecker). Was nicht passt, kommt mit Begründung
  /// und fehlender Bedienart zurück (kind null). [kind] null = die KI
  /// entscheidet je Teilaufgabe.
  ///
  /// Für ganze Dokumente (siehe InteractiveTaskScanService): [instruction] ist
  /// der Wunsch des Nutzers, welche Aufgaben und wie (z.B. "alle Mathe-Aufgaben
  /// als Rechenweg") – nicht passende werden weggelassen; [pages] sind die
  /// Seitennummern der Bilder, [contextPage] eine schon gelesene Seite davor
  /// (nur Kontext). Mit [allowEmpty] ist "nichts gefunden" kein Fehler.
  Future<List<InteractiveTaskDraft>> buildInteractiveTasks({
    String text = '',
    List<Uint8List> images = const [],
    String solution = '',
    InteractiveKind? kind,
    String instruction = '',
    List<int> pages = const [],
    int? contextPage,
    bool allowEmpty = false,
  }) async {
    if (text.trim().isEmpty && images.isEmpty) {
      throw AiServiceException('Gib die Aufgabe als Text oder Bild an.');
    }
    final buffer = StringBuffer();
    if (text.trim().isNotEmpty) {
      buffer
        ..writeln('Aufgabe:')
        ..writeln(_cap(text.trim(), _interactiveTaskCap))
        ..writeln();
    }
    if (solution.trim().isNotEmpty) {
      buffer
        ..writeln('Vorhandene Lösung bzw. Lösungsweg (zum Abgleich, kann Fehler enthalten):')
        ..writeln(_cap(solution.trim(), _interactiveTaskCap))
        ..writeln();
    }
    buffer.writeln(switch (kind) {
      InteractiveKind.steps => 'Gewünscht: "kind": "steps" (Rechenweg) – nur wenn das gar nicht geht, "none" mit Begründung.',
      InteractiveKind.gantt => 'Gewünscht: "kind": "gantt" (Terminierung) – nur wenn das gar nicht geht, "none" mit Begründung.',
      InteractiveKind.crystal => 'Gewünscht: "kind": "crystal" (Kristallgitter) – nur wenn das gar nicht geht, "none" mit Begründung.',
      InteractiveKind.bom => 'Gewünscht: "kind": "bom" (Stückliste) – nur wenn das gar nicht geht, "none" mit Begründung.',
      InteractiveKind.sketch =>
        'Gewünscht: "kind": "sketch" (Diagramm skizzieren) – nur wenn das gar nicht geht, "none" mit Begründung.',
      null => 'Entscheide je Teilaufgabe selbst: "steps", "gantt", "crystal", "bom", "sketch", "question" oder "none".',
    });
    if (instruction.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Wunsch des Nutzers, welche Aufgaben und wie: ${instruction.trim()}')
        ..writeln('Übernimm NUR Aufgaben, die dazu passen, und lass alle anderen ganz weg (auch nicht als "none"). '
            'Nennt der Wunsch eine Art (z.B. "als Rechenweg"), verwende sie, wo es irgend geht.');
    }
    if (pages.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('${images.isEmpty ? 'Der Text enthält' : 'Die Bilder (und der Text) sind'} Seiten eines Dokuments: ${[
          if (contextPage != null) 'Seite $contextPage (nur Kontext)',
          for (final p in pages) 'Seite $p',
        ].join(', ')}.')
        ..writeln('Übernimm JEDE passende Aufgabe, die auf ${pages.length == 1 ? 'Seite ${pages.first}' : 'den Seiten ${pages.first}–${pages.last}'} '
            'beginnt (höchstens 8)${contextPage == null ? '' : ' – Aufgaben, die schon auf Seite $contextPage beginnen, wurden '
                'bereits übernommen und gehören nicht dazu'}. Gib bei jeder Aufgabe "page" an (Seite, auf der sie beginnt). '
            'Steht dort keine passende Aufgabe, antworte mit {"tasks": []}.');
    } else if (images.isNotEmpty) {
      buffer
        ..writeln('Dem Text folgen ${images.length} Bild${images.length == 1 ? '' : 'er'} der Aufgabe.')
        ..writeln('Stehen auf den Bildern mehrere Aufgaben und ist im Text eine bestimmte genannt (z.B. "Aufgabe 2b"), '
            'nimm nur diese; sonst alle Teilaufgaben.');
    }
    final raw = await _complete(
      _interactiveTaskSystemPrompt,
      _textWithImages(buffer.toString(), images, 'Bild'),
      temperature: 0,
    );
    final drafts = parseInteractiveTasks(_parseJsonObject(raw));
    if (allowEmpty) return drafts;
    if (drafts.isEmpty || drafts.every((d) => d.kind == null && d.reason.trim().isEmpty && !d.incomplete && !d.asQuestion)) {
      throw AiServiceException('Die KI hat keine interaktive Aufgabe geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    if (drafts.every((d) => d.incomplete)) {
      throw AiServiceException(
        'Die KI hat keine brauchbare Aufgabe geliefert – bitte erneut versuchen oder ein stärkeres Modell wählen.',
        rawResponse: raw,
      );
    }
    return drafts;
  }

  /// Liest die Antwort von [buildInteractiveTasks]: eine Liste unter "tasks"
  /// oder ein einzelnes Objekt.
  static List<InteractiveTaskDraft> parseInteractiveTasks(Map<String, dynamic> json) {
    final list = json['tasks'] ?? json['aufgaben'] ?? json['teilaufgaben'];
    if (list is List) {
      return [
        for (final t in list.take(10))
          if (t is Map) parseInteractiveTask(Map<String, dynamic>.from(t)),
      ];
    }
    return [parseInteractiveTask(json)];
  }

  /// Liest einen Eintrag tolerant (Daten unter "taskData" oder flach im
  /// Objekt, Art aus "kind" oder der Struktur). Nennt die KI eine Art, ohne
  /// brauchbare Daten zu liefern, wird der Entwurf als [InteractiveTaskDraft.incomplete]
  /// markiert.
  static InteractiveTaskDraft parseInteractiveTask(Map<String, dynamic> json) {
    final draft = _parseInteractiveTask(json);
    final page = json['page'] ?? json['seite'];
    final n = page is num ? page.toInt() : int.tryParse('${page ?? ''}'.trim());
    return n == null || n < 1 ? draft : draft.withPage(n);
  }

  static InteractiveTaskDraft _parseInteractiveTask(Map<String, dynamic> json) {
    final data = json['taskData'] is Map ? Map<String, dynamic>.from(json['taskData'] as Map) : json;
    final declared = '${json['kind'] ?? json['type'] ?? ''}'.toLowerCase().trim();
    final asQuestion = declared == 'question' || declared == 'frage' || declared == 'normal' || declared == 'quiz';
    if (asQuestion) {
      return InteractiveTaskDraft(
        kind: null,
        front: '${json['front'] ?? json['task'] ?? json['aufgabe'] ?? ''}'.trim(),
        back: '${json['back'] ?? json['solution'] ?? ''}'.trim(),
        reason: '${json['reason'] ?? json['begruendung'] ?? json['begründung'] ?? ''}'.trim(),
        asQuestion: true,
        questionType: '${json['questionType'] ?? json['fragetyp'] ?? ''}'.trim(),
      );
    }
    final none = declared == 'none' || declared == 'keine' || declared == 'nicht geeignet';
    final kind = none
        ? null
        : interactiveKindFrom(declared) ??
            (data['steps'] is List
                ? InteractiveKind.steps
                : data['items'] is List
                    ? InteractiveKind.gantt
                    : data['root'] is Map
                        ? InteractiveKind.bom
                        : data['features'] is List
                        ? InteractiveKind.sketch
                        : (data['parts'] is List ? InteractiveKind.crystal : null));
    final front = '${json['front'] ?? json['task'] ?? json['aufgabe'] ?? ''}'.trim();
    final back = '${json['back'] ?? json['solution'] ?? json['loesungsweg'] ?? json['lösungsweg'] ?? ''}'.trim();
    final reason = '${json['reason'] ?? json['begruendung'] ?? json['begründung'] ?? ''}'.trim();
    final needs = '${json['needs'] ?? json['bedienart'] ?? json['missing'] ?? ''}'.trim();
    final draft = InteractiveTaskDraft(
      kind: kind,
      front: front,
      back: back,
      steps: kind == InteractiveKind.steps ? StepTask.fromMap(data) : null,
      gantt: kind == InteractiveKind.gantt ? GanttTask.fromMap(data) : null,
      crystal: kind == InteractiveKind.crystal ? CrystalTask.fromMap(data) : null,
      bom: kind == InteractiveKind.bom ? BomTask.fromMap(data) : null,
      sketch: kind == InteractiveKind.sketch ? SketchTask.fromMap(data) : null,
      reason: reason,
      needs: needs,
    );
    if (kind != null && !draft.isUsable) {
      return InteractiveTaskDraft(
        kind: null,
        front: front,
        back: back,
        reason: 'Die KI hat diese Aufgabe nicht vollständig als ${kind.label} aufbereitet.',
        incomplete: true,
      );
    }
    if (kind == null && declared.isNotEmpty && !none) {
      // Unbekannte Art: wie "passt nicht" behandeln, aber mit Hinweis.
      return InteractiveTaskDraft(kind: null, front: front, back: back, reason: reason.isEmpty ? 'Unbekannte Art „$declared“.' : reason, needs: needs);
    }
    return draft;
  }

  /// Erklärt die Unstimmigkeiten, die die App in einem Rechenweg gefunden hat
  /// ([problems], siehe StepChecker.verify), rechnet selbst nach und schlägt
  /// bei Bedarf eine korrigierte Aufgabe vor ([StepTaskReview.corrected] –
  /// die App prüft sie danach wieder selbst). [question] = Nachfrage des
  /// Nutzers, [history] = bisheriges Gespräch.
  Future<StepTaskReview> reviewStepTask({
    required String taskText,
    required StepTask task,
    required List<String> problems,
    String? question,
    List<({String question, String answer})> history = const [],
  }) async {
    final buffer = StringBuffer()
      ..writeln('Aufgabe:')
      ..writeln(_cap(taskText.trim(), _interactiveTaskCap))
      ..writeln()
      ..writeln('Rechenweg als JSON (taskData):')
      ..writeln(jsonEncode(task.toMap()))
      ..writeln()
      ..writeln('Was die App beim Nachrechnen gefunden hat:');
    for (final p in problems) {
      buffer.writeln('- $p');
    }
    if (problems.isEmpty) buffer.writeln('- (nichts)');
    for (final h in history) {
      buffer
        ..writeln()
        ..writeln('Frage des Nutzers: ${h.question}')
        ..writeln('Deine Antwort: ${h.answer}');
    }
    buffer
      ..writeln()
      ..writeln(question == null || question.trim().isEmpty
          ? 'Erkläre die Meldungen und prüfe die Aufgabe.'
          : 'Neue Frage des Nutzers: ${question.trim()}');
    final raw = await _complete(_stepReviewSystemPrompt, buffer.toString(), temperature: 0);
    final review = StepTaskReview.fromJson(_parseJsonObject(raw));
    if (review.answer.isEmpty) {
      throw AiServiceException('Die KI hat keine Erklärung geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return review;
  }

  static const _stepReviewSystemPrompt = r'''
Du hilfst einem Studenten, der in einer Lern-App einen Rechenweg (Schritte mit erwarteten Antworten) aus einer Übungsaufgabe übernommen hat. Die App hat die hinterlegte Musterlösung selbst nachgerechnet und Unstimmigkeiten gemeldet. Erkläre sie verständlich und rechne selbst sorgfältig nach.

Hintergrund, den du erklären kannst:
- "answer" eines Felds ist die erwartete (richtige) Antwort, in Eingabe-Schreibweise.
- "mistakes" sind TYPISCHE FEHLER: absichtlich FALSCHE Antworten, die Lernende oft geben, mit einer eigenen Rückmeldung. Sie gehören nicht zum Lösungsweg. Meldet die App, ein typischer Fehler sei "in Wahrheit richtig", rechnet sie diese Eingabe als richtige Antwort – dann ist entweder der hinterlegte typische Fehler unsinnig (nur die Rückmeldung ist falsch, die Aufgabe stimmt) ODER die erwartete Antwort ist falsch.
- "tolerance" ist die erlaubte relative Abweichung bei gerundeten Zahlen.

Vorgehen:
1. Erkläre jede Meldung in 1–3 einfachen Sätzen: Was bedeutet sie? Ist die Aufgabe/Musterlösung falsch, nur eine Rückmeldung, oder harmlos? Was müsste man ändern?
2. Rechne die betroffenen Schritte selbst nach (kurz, mit Zahlen; LaTeX in $…$).
3. Beantworte eine Nachfrage des Nutzers direkt und konkret.
4. Wenn etwas korrigiert werden sollte: "corrected" = das vollständige korrigierte taskData-Objekt (gleiches Schema wie das gelieferte, alle Schritte, nur das Nötige ändern – z.B. falsche typische Fehler entfernen oder ersetzen, falsche erwartete Antworten korrigieren). Sonst "corrected": null.

Antworte NUR mit JSON:
{"answer": "Erklärung auf Deutsch, du-Form, mit Absätzen (
)", "verdict": "ok" | "rueckmeldung_falsch" | "loesung_falsch" | "unklar", "corrected": {...} | null}''';

  /// Prüft einen auf Papier gerechneten Rechenweg (Fotos) gegen die
  /// Musterlösung: die KI liest Zeile für Zeile, markiert Fehler und
  /// Folgefehler und nennt das Endergebnis – das prüft danach die App selbst
  /// (StepChecker.probe), damit eine falsch gelesene Zeile nicht täuscht.
  Future<PaperReview> reviewPaperSolution({
    required String task,
    required StepTask solution,
    String solutionText = '',
    required List<Uint8List> images,
  }) async {
    if (images.isEmpty) throw AiServiceException('Fotografiere zuerst deinen Rechenweg.');
    final steps = [
      for (final (i, s) in solution.steps.indexed) {'n': i + 1, 'title': s.title, 'result': s.resultText},
    ];
    final buffer = StringBuffer()
      ..writeln('Aufgabe:')
      ..writeln(_cap(task.trim(), _interactiveTaskCap))
      ..writeln()
      ..writeln('Musterlösung in Schritten:')
      ..writeln(jsonEncode(steps))
      ..writeln();
    if (solutionText.trim().isNotEmpty) {
      buffer
        ..writeln('Musterlösung als Text:')
        ..writeln(_cap(solutionText.trim(), _interactiveTaskCap))
        ..writeln();
    }
    buffer.writeln('Dem Text folgen ${images.length} Foto${images.length == 1 ? '' : 's'} des handschriftlichen Rechenwegs.');
    final raw = await _complete(_paperReviewSystemPrompt, _textWithImages(buffer.toString(), images, 'Foto'), temperature: 0);
    final review = PaperReview.fromJson(_parseJsonObject(raw));
    if (review.lines.isEmpty) {
      throw AiServiceException(
        'Auf dem Foto war kein Rechenweg zu erkennen – bitte näher, gerade und bei gutem Licht fotografieren.',
        rawResponse: raw,
      );
    }
    return review;
  }

  static const _interactiveTaskSystemPrompt = r"""
Du wandelst Übungsaufgaben in interaktive Aufgaben für eine Lern-App um. Die App prüft die Antworten der Lernenden SELBST: Formeln setzt sie an mehreren Stellen ein, Terminierungen, Kristallgitter und Stücklisten rechnet und zeichnet sie selbst, Skizzen prüft sie anhand von Merkmalen. Du lieferst nur Struktur, erwartete Antworten und Rückmeldungen.

Enthält das Material mehrere Aufgaben oder Teilaufgaben (a, b, c …), liefere JEDE als eigenen Eintrag in "tasks" (höchstens 8). Teilaufgaben derselben Art zum selben Bild (z.B. mehrere Richtungen im selben Würfel) dürfen EIN Eintrag sein.

Art ("kind") je Eintrag:
- "steps" (Rechenweg): Rechenaufgaben mit eindeutigem Ergebnis (Mathe, Physik, Technik, Werkstoffe, BWL-Rechnungen), zerlegbar in 3–7 Schritte.
- "gantt" (Terminierung): Vorwärts-/Rückwärtsterminierung, Durchlaufterminierung, Gantt-Diagramme mit Arbeitsgängen und Dauern.
- "crystal" (Kristallgitter): Richtungen [u v w] bzw. Ebenen (h k l) im kubischen Einheitswürfel einzeichnen oder ablesen, Richtungsfamilien ⟨u v w⟩, Atome in einer Ebene (kubisch primitiv, krz, kfz).
- "bom" (Stückliste): aus einem Erzeugnisbaum / einer Erzeugnis- bzw. Produktstruktur eine Mengenübersichts-, Struktur- oder Baukastenstückliste (auch "Baustellen-" oder "Baustückliste") aufstellen.
- "sketch" (Diagramm skizzieren): eine oder mehrere Kurven qualitativ in ein Diagramm zeichnen bzw. skizzieren (z.B. Längenänderung über der Temperatur, Spannungs-Dehnungs-Kurve, Potentialkurve, Abkühlkurven mehrerer Legierungen, Hall-Petch-Geraden für zwei Temperaturen, Härteverlauf für drei Auslagerungstemperaturen, Streckgrenze und Bruchdehnung über der Glühtemperatur) und ggf. Kennwerte darin markieren. Verlangt die Aufgabe zusätzlich eine Erklärung/Begründung ("Erläutern Sie …"), liefere die als EIGENEN Eintrag "question" mit "questionType": "free_text".
- "question": wenn es als NORMALE Quizfrage gut geht – die App hat dafür schon Fragetypen: Freitext/Erklären/Begründen/Kurzantwort ("free_text"), Auswahl ("single_choice"/"multiple_choice"), Zuordnen bzw. in Kategorien/Kriterien einordnen ("drag_category"), Tabelle ausfüllen mit festen Einträgen ("table"), Stellen in einer Abbildung markieren ("mark_image") oder beschriften ("diagram_label"), Lückentext ("fill_blank"). Dann "questionType" (einer dieser Werte) und "reason" mit einem kurzen Satz. "front" wortgetreu.
- "none": NUR wenn weder interaktiv noch als normale Frage sinnvoll übbar (z.B. einen Netzplan oder Schaltplan selbst zeichnen) – dann "reason" mit einem Satz UND "needs": in 2–5 Wörtern, welche Bedienart die App bräuchte (z.B. "Kurve in Diagramm zeichnen", "Netzplan zeichnen", "Schaltplan zeichnen").
- Fehlt für eine Rechnung nur ein Wert, den man üblicherweise nachschlägt (Werkstoffkennwert wie Streckgrenze, Naturkonstante), nimm einen üblichen Tabellenwert, schreib ihn als Annahme in "front" ("angenommen: R_{p0,2} = 355 MPa") und erstelle den Rechenweg trotzdem.

Bei "steps":
- "front": die Aufgabe WORTGETREU mit allen Angaben (Formeln in LaTeX mit $…$).
- taskData.steps: 3–7 Schritte in der Reihenfolge des Lösungswegs. Jeder Schritt hat
  - "title": kurz (z.B. "Substitution wählen"),
  - "prompt": die Frage an den Lernenden, OHNE die Lösung zu verraten,
  - ENTWEDER "options": 3–4 Antworten {"text", "correct": true/false, "feedback"} – jede falsche mit eigener Rückmeldung, warum sie hier nicht passt –
  - ODER "fields": 1–2 Eingabefelder.
  - "hints": genau 2 gestufte Tipps (erst ein Denkanstoß, dann deutlicher), ohne die Antwort zu nennen,
  - "result": das Ergebnis des Schritts zum Anzeigen (LaTeX in $…$),
  - "explanation": 1–2 Sätze, wie man darauf kommt.
- Feld: "label" (was vor dem Feld steht, z.B. "u' =", "C =", "y(x) ="), "kind": "formula" oder "number",
  "answer": erwartete Antwort in EINGABE-SCHREIBWEISE, KEIN LaTeX: + - * / ^, sqrt(), ln(), exp(), sin() …, pi, Dezimalpunkt – z.B. "-1/u", "x - sqrt(12 - 2*x)", "12", "pi*sqrt(3)/8",
  "variables": die Größen, die in der Antwort vorkommen (z.B. ["u"]),
  "constants": frei wählbare Konstanten wie die Integrationskonstante (z.B. ["C"]) – sonst weglassen,
  "tolerance": relative Toleranz NUR bei gerundeten Zahlenergebnissen (0.01 = 1 %),
  "mistakes": 1–3 typische Fehler {"answer": in Eingabe-Schreibweise, "feedback": kurze Rückmeldung, die zum Weiterdenken anregt, ohne die Lösung zu verraten},
  "domain": nur wenn die Antwort nicht überall definiert ist: Bereich je Größe, z.B. {"x": [-10, 5.9]}.
- Das letzte Feld des letzten Schritts ist das Endergebnis.
- taskData.probe NUR bei Differentialgleichungen bzw. Stammfunktionen, damit die App das Ergebnis unabhängig prüft:
  {"kind": "ode", "equation": rechte Seite f(x, y) von y' = f(x, y) in Eingabe-Schreibweise, "variable": "x", "function": "y", "order": 1, "conditions": [{"x": 4, "value": 2}]}
  bzw. {"kind": "antiderivative", "equation": Integrand in Eingabe-Schreibweise}.
- taskData.domainNote: wo die Lösung gilt (z.B. "für x < 6"), sonst leer.
- "back": der vollständige Lösungsweg als Text (LaTeX in $…$).
- RECHNE SORGFÄLTIG und prüfe jede erwartete Antwort selbst nach – die App setzt sie ein und meldet Widersprüche.

Bei "gantt":
- "front": die Aufgabe WORTGETREU.
- taskData.items: je Bauteil/Baugruppe {"id": kurz, "name", "operations": [{"name", "duration": Tage als Zahl}], "needs": [ids der Teile, die vorher fertig sein müssen], "uncertain": true, wenn Werte schlecht lesbar oder abgeschnitten waren}. Die Baugruppe "needs" ihre Bauteile.
- taskData.start: Starttermin (Zahl), taskData.due: Liefertermin (Zahl; weglassen, wenn keiner genannt ist),
  taskData.direction: "forward" oder "backward", taskData.counting: "inclusive" (Ende = Start + Dauer − 1, üblich bei Tages-Rastern) oder "points" (Ende = Start + Dauer), wie es die Aufgabe nahelegt.
- taskData.questions: was gefragt ist, je Teil {"item": id, "ask": "start" | "end" | "slack" | "buffer"} (slack = Liegezeit, buffer = Puffer).
- taskData.drawChart: true, wenn ein Gantt-Diagramm gezeichnet werden soll (Standard).
- Rechne die Termine NICHT selbst aus – das macht die App. "back" darf leer bleiben.

Bei "crystal":
- "front": die Aufgabe WORTGETREU.
- taskData.lattice: "sc" (kubisch primitiv), "bcc" (krz) oder "fcc" (kfz) – wie in der Aufgabe, sonst "sc".
- taskData.parts: je gefragter Richtung bzw. Ebene ein Teil {"kind", "indices": [3 ganze Zahlen], "uncertain": true, wenn ein Strich über einer Zahl schlecht lesbar war}.
  "kind": "direction" (Richtung einzeichnen), "readDirection" (gezeichneten Pfeil ablesen), "family" (alle Richtungen der Familie ⟨u v w⟩ einzeichnen – nur ⟨1 0 0⟩, ⟨1 1 0⟩, ⟨1 1 1⟩ u.ä. mit höchstens 12 Richtungen), "plane" (Ebene einzeichnen), "readPlane" (gezeichnete Ebene ablesen), "planeAtoms" (Atome in der Ebene markieren).
  Ein Strich über einer Zahl bedeutet minus: [1̄ 1̄ 1] → [-1, -1, 1].
  "direction"/"family" nur, wenn die gekürzten Indizes höchstens den Betrag 2 haben (sonst "readDirection"); "plane" nur bei Ebenen, die durch drei Punkte des ½-Rasters gehen (sonst "readPlane").
- "back": kurze Erklärung (Achsenabschnitte, Kehrwerte) – gezeichnet und geprüft wird in der App.

Bei "bom":
- "front": die Aufgabe WORTGETREU (ohne den Baum abzuschreiben).
- taskData.root: NUR den Erzeugnisbaum ablesen – das Erzeugnis (Stufe 0) mit {"nr": Sach-Nr. als Text, "name": Bezeichnung, "children": [...]}; jedes Kind {"nr", "name", "qty": Zahl an der Verbindungslinie (Menge je 1 Stück der Baugruppe direkt darüber), "unit": nur bei Mengeneinheiten wie "g", "kg", "l", "m" (sonst weglassen), "children": [...], "uncertain": true, wenn die Zahl schlecht lesbar war}.
  Kinder in der Reihenfolge von links nach rechts wie im Bild. Steht an einer Linie keine Menge, gilt laut Aufgabe meist 1. Kommt dieselbe Baugruppe mehrfach vor, reicht es, sie einmal mit ihren Kindern aufzuführen (sonst ohne "children").
- taskData.parts: je gefragter Liste ein Eintrag in der Reihenfolge der Aufgabe: {"list": "overview" (Mengenübersichtsstückliste) | "structure" (Strukturstückliste) | "modular" (Baukasten-/Baustellenstückliste)}.
  Bei "overview" zusätzlich "includeAssemblies": true, wenn Baugruppen mit aufgeführt werden ("mit Berücksichtigung der intern erstellten Baugruppen"), false bei nur Teilen/Rohstoffen.
  Bei "structure" "totals": true NUR, wenn ausdrücklich die Gesamtmenge je Erzeugnis verlangt ist (Standard: Menge je übergeordnete Baugruppe).
  Bei "modular" "lists": Sach-Nr. der vorgegebenen Formulare (z.B. ["10", "11", "23"]), wenn welche abgebildet sind – sonst weglassen.
- Rechne die Listen NICHT selbst aus – das macht die App. "back" darf leer bleiben.

Bei "sketch":
- "front": die Aufgabe WORTGETREU, aber ohne den Erklärungsteil (der kommt als eigener "question"-Eintrag).
- taskData.xAxis / taskData.yAxis: {"label": Größe mit Einheit (z.B. "T in °C"), "min", "max": sinnvoller Bereich laut Aufgabe, "showNumbers": false bei rein qualitativen Achsen ohne Zahlen}.
- taskData.reference: die Musterkurve als Punktliste [[x, y], …] in Achsen-Einheiten, 6–15 Punkte, die den typischen Verlauf zeigen; bei einem Sprung zwei Linienzüge [[[x, y], …], [[x, y], …]]. Qualitative Kurven deutlich ausgeprägt zeichnen (z.B. den elastischen Bereich überzeichnet).
- Gehören MEHRERE Kurven in dasselbe Diagramm (z.B. Abkühlkurven für 10 %, 20 %, 61,9 % und 100 % Sn; Geraden für T₁ und T₂; Härteverläufe für T₁, T₂, T₃; R_e und A über der Glühtemperatur): statt "reference" taskData.curves = [{"name": kurzer Name wie "T₁", "20 % Sn" oder "R_e", "reference": Punktliste wie oben}, …] und bei JEDEM Merkmal "curve": Name der Kurve. Liegen die Kurven nebeneinander in getrennten Diagrammen, ist das trotzdem EIN Diagramm mit mehreren Kurven (bei Abkühlkurven zeitlich versetzt nebeneinander).
- taskData.features: 2–6 Merkmale je Kurve (insgesamt höchstens 16), auf die es fachlich ankommt – die App prüft die Skizze NUR daran, grob und nicht pixelgenau. Je Merkmal {"kind", …, "text": ein Satz, was es bedeutet und warum (wird als Rückmeldung gezeigt)}:
  "rising"/"falling"/"linear" mit "x" und "x2" (Bereich), "jumpDown"/"jumpUp" mit "x" (Stelle des Sprungs, z.B. 911),
  "plateau" (Haltepunkt, waagerechtes Stück) mit "y" (Höhe, z.B. 183 bei der eutektischen Temperatur; optional "x"/"x2" als ungefährer Bereich), "kink" (Knick, deutlicher Steigungswechsel) mit "y" (z.B. Liquidustemperatur der Legierung) oder "x",
  Vergleiche zweier Kurven mit "curve" und "other" (Namen): "above"/"below" (liegt über/unter, optional Bereich "x"/"x2"), "parallel" (gleiche Steigung, verschoben), "steeper" (steiler als), "maxEarlier" (Maximum früher als), "maxHigher" (Maximum höher als), "max"/"min" mit "x" (ungefähre Stelle, sonst weglassen) und optional "y" (Minimum liegt unter y bzw. Maximum über y), "startsAt"/"endsAt" mit "x", "approaches" mit "y" (Wert, dem sich die Kurve am rechten Ende annähert), "steeperLeft" (links vom Minimum steiler als rechts, Asymmetrie), "mark" für Kennwerte, die markiert werden sollen: {"kind": "mark", "label": z.B. "R_m", "anchor": "max" | "min" | "end" | "start" | "beforeMax" | "curve" | "x" | "point", "x"/"y" falls nötig}.
  "tol": Toleranz als Anteil der Achse (Standard 0.08), bei ungenauen Stellen größer.
- Die Musterkurve muss alle Merkmale selbst erfüllen (die App prüft das nach): ein Haltepunkt braucht ein deutlich waagerechtes Stück (mind. 5 % der x-Achse), ein Knick einen deutlichen Steigungswechsel.
- "back": kurze Beschreibung des richtigen Verlaufs.

Antworte NUR mit einem JSON-Objekt:
{"tasks": [{"kind": "steps" | "gantt" | "crystal" | "bom" | "sketch" | "question" | "none", "page": Seite (nur bei Dokument-Seiten), "front": "...", "back": "...", "reason": "...", "needs": "...", "questionType": "...", "taskData": {...}}]}""";

  // -- Aufgaben von einer externen KI (JSON) -------------------------------

  /// Prompt zum Kopieren in eine externe KI (ChatGPT, Gemini, Claude.ai …):
  /// dasselbe Format wie [buildInteractiveTasks], aber für ein ganzes
  /// Dokument und mit fertigen Quizfragen ("card") für alles, was nicht
  /// interaktiv geht – die Antwort wird als JSON-Datei importiert
  /// ([parseImportedTasks]).
  static final String externalTaskPrompt = [
    'Ich lerne mit der App "Lernen" und möchte die Aufgaben aus dem Dokument, das ich dir gebe (Übungsblatt, '
        'Altklausur …), dort importieren. Lies das GANZE Dokument und befolge die folgenden Regeln der App genau.\n\n',
    _interactiveTaskSystemPrompt.replaceFirst(' (höchstens 8)', ''),
    _externalTaskRules,
  ].join();

  static const _externalTaskRules = r'''


ZUSÄTZLICH FÜR DEN IMPORT:
- Übernimm ALLE Aufgaben des Dokuments (keine Höchstzahl), in der Reihenfolge des Dokuments, und gib bei jeder "page" an (Seite, auf der sie beginnt).
- Bei "question" liefere die fertige Quizfrage zusätzlich unter "card", damit die App sie direkt übernehmen kann – mit allen Feldern ihres Typs:
  {"type": "single_choice" | "multiple_choice", "front": "Frage", "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]}
  {"type": "fill_blank", "front": "Text mit ___ Lücke", "blanks": ["Lösung; Variante"]}
  {"type": "free_text", "front": "Frage", "correctText": "Lösung; Alternative", "back": "Erklärung"}
  {"type": "table", "front": "Vervollständige die Tabelle", "table": [["Kopf 1", "Kopf 2"], ["vorgegeben", {"answer": "Lösung"}]]}
  {"type": "drag_drop" | "drag_category", "front": "Ordne zu", "dragPairs": [{"source": "Begriff", "target": "Ziel bzw. Kategorie"}]}
  {"type": "learn", "front": "Aufgabe wortgetreu", "back": "ausführlicher Lösungsweg"} (nur, wenn sich nichts davon prüfen lässt)
- Steht im Dokument eine Musterlösung, halte dich daran; sonst rechne bzw. löse SORGFÄLTIG selbst.
- Formeln in LaTeX mit $…$. Verdopple in JSON jeden Backslash (z.B. "$\\frac{a}{b}$"), sonst ist das JSON ungültig.
- Antworte AUSSCHLIESSLICH mit dem JSON-Objekt {"tasks": [...]} – ohne Text davor oder danach. Ich speichere es als Datei "aufgaben.json" und lade sie in der App hoch.''';

  /// Liest den JSON-Text einer externen KI (siehe [externalTaskPrompt]):
  /// {"tasks": [...]} mit interaktiven Aufgaben und Fragen, aber auch eine
  /// Liste fertiger Quizfragen ("flashcards"/"questions", z.B. aus dem
  /// Prompt im Nachbereiten). Fragen werden wie beim Import normalisiert
  /// (QuestionParsing.normalizeGeneratedFlashcard); unbrauchbare zählen in
  /// `dropped`. Wirft [AiServiceException], wenn das kein JSON ist.
  static ({List<InteractiveTaskDraft> drafts, int dropped}) parseImportedTasks(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(MathMarkup.escapeLatexInJson(_extractJsonBlock(raw)));
    } catch (e) {
      throw AiServiceException('Das ist kein gültiges JSON: $e', rawResponse: raw);
    }
    final tasks = <Object?>[];
    final cards = <Object?>[];
    if (decoded is List) {
      tasks.addAll(decoded);
    } else if (decoded is Map) {
      for (final key in const ['tasks', 'aufgaben', 'teilaufgaben']) {
        if (decoded[key] is List) tasks.addAll(decoded[key] as List);
      }
      for (final key in const ['flashcards', 'questions', 'cards', 'fragen']) {
        if (decoded[key] is List) cards.addAll(decoded[key] as List);
      }
      if (tasks.isEmpty && cards.isEmpty) tasks.add(decoded);
    }
    final drafts = <InteractiveTaskDraft>[];
    var dropped = 0;
    InteractiveTaskDraft? question(Map<String, dynamic> card, {Object? page, String reason = ''}) {
      final normalized = QuestionParsing.normalizeGeneratedFlashcard(card);
      if (normalized == null) return null;
      final draft = InteractiveTaskDraft(
        kind: null,
        front: '${normalized['front'] ?? ''}'.trim(),
        back: '${normalized['back'] ?? ''}'.trim(),
        reason: reason,
        asQuestion: true,
        questionType: '${normalized['type'] ?? ''}',
        questionData: normalized,
      );
      final n = page is num ? page.toInt() : int.tryParse('${page ?? ''}'.trim());
      return n == null || n < 1 ? draft : draft.withPage(n);
    }

    for (final t in tasks) {
      if (t is! Map) {
        dropped++;
        continue;
      }
      final map = Map<String, dynamic>.from(t);
      // Ohne "kind"/"taskData", aber mit Fragetyp: eine fertige Quizfrage.
      if (!map.containsKey('kind') && !map.containsKey('taskData') && map.containsKey('type')) {
        cards.add(map);
        continue;
      }
      var draft = parseInteractiveTask(map);
      final card = map['card'] ?? map['question'] ?? map['frage'];
      if (draft.asQuestion && card is Map) {
        final front = '${card['front'] ?? card['question'] ?? ''}'.trim();
        final full = question(
          {...Map<String, dynamic>.from(card), if (front.isEmpty) 'front': draft.front},
          page: map['page'] ?? map['seite'],
          reason: draft.reason,
        );
        if (full != null) draft = full;
      }
      if (draft.front.trim().isEmpty && draft.kind == null && draft.reason.trim().isEmpty) {
        dropped++;
        continue;
      }
      drafts.add(draft);
    }
    for (final c in cards) {
      final draft = c is Map ? question(Map<String, dynamic>.from(c), page: c['page'] ?? c['sourcePage']) : null;
      if (draft == null) {
        dropped++;
      } else {
        drafts.add(draft);
      }
    }
    return (drafts: drafts, dropped: dropped);
  }

  /// Zweite Meinung zu einer übernommenen Aufgabe bzw. Frage: stimmen
  /// erwartete Antworten, Daten und Lösung mit der Aufgabenstellung? [kind]
  /// = Art ("steps", … bzw. der Fragetyp), [data] = taskData bzw. die
  /// Frage, [appFindings] = was die App beim Nachrechnen selbst gefunden hat.
  Future<TaskVerification> verifyTask({
    required String kind,
    required String front,
    String back = '',
    required Map<String, dynamic> data,
    List<String> appFindings = const [],
  }) async {
    final buffer = StringBuffer()
      ..writeln('Art: $kind')
      ..writeln()
      ..writeln('Aufgabe:')
      ..writeln(_cap(front.trim(), _interactiveTaskCap))
      ..writeln();
    if (back.trim().isNotEmpty) {
      buffer
        ..writeln('Hinterlegter Lösungsweg/Erklärung:')
        ..writeln(_cap(back.trim(), _interactiveTaskCap))
        ..writeln();
    }
    buffer
      ..writeln('Daten als JSON:')
      ..writeln(jsonEncode(data))
      ..writeln()
      ..writeln('Was die App beim Nachrechnen selbst gefunden hat:');
    for (final f in appFindings) {
      buffer.writeln('- $f');
    }
    if (appFindings.isEmpty) buffer.writeln('- (nichts)');
    final raw = await _complete(_verifyTaskSystemPrompt, buffer.toString(), temperature: 0);
    final verification = TaskVerification.fromJson(_parseJsonObject(raw));
    if (verification.verdict == TaskVerdict.unclear && verification.comment.isEmpty) {
      throw AiServiceException('Die KI hat kein Urteil geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return verification;
  }

  static const _verifyTaskSystemPrompt = r'''
Du prüfst für eine Lern-App eine Aufgabe, die eine andere KI aus einem Übungsblatt übernommen hat. Prüfe GENAU und rechne selbst nach – Lernende verlassen sich darauf.

Je nach Art:
- "steps" (Rechenweg): Stimmt jede erwartete Antwort ("answer") und das Endergebnis? Sind die "mistakes" (typische Fehler) wirklich falsch? Passen die Auswahl-Antworten ("correct")? Antworten stehen in Eingabe-Schreibweise (x^2, sqrt(), pi …).
- "gantt" (Terminierung): Passen Teile, Arbeitsgänge, Dauern, Reihenfolge ("needs"), Start-/Liefertermin, Richtung und Zählweise zur Aufgabe? Termine rechnet die App selbst.
- "crystal" (Kristallgitter): Passen Gitter und Indizes (Vorzeichen!) zur Aufgabe?
- "bom" (Stückliste): Passt der Erzeugnisbaum (Sach-Nr., Mengen, Struktur) und welche Listen gefragt sind? Die Listen rechnet die App selbst.
- "sketch" (Diagramm): Ist die Musterkurve fachlich richtig, stimmen die Merkmale?
- Quizfrage (Typ wie "single_choice", "free_text", "fill_blank", "table" …): Ist die als richtig hinterlegte Antwort fachlich richtig und vollständig, sind falsche Optionen wirklich falsch, passt die Frage zur Aufgabe?

Urteil:
- "ok": alles stimmt.
- "fehler": mindestens eine Angabe ist falsch. Dann "comment": kurz und konkret, was falsch ist und was richtig wäre (1–4 Sätze, LaTeX in $…$), und "corrected": das VOLLSTÄNDIGE korrigierte Datenobjekt im gleichen Schema wie geliefert (nur das Nötige ändern).
- "unklar": lässt sich ohne das Blatt nicht entscheiden (z.B. Werte, die nur im Bild stehen) – "comment" sagt, was man prüfen sollte.

Antworte NUR mit JSON:
{"verdict": "ok" | "fehler" | "unklar", "comment": "...", "corrected": {...} | null}''';

  static const _paperReviewSystemPrompt = r"""
Du bist Korrektor für handschriftliche Rechenwege. Du bekommst eine Aufgabe, die Musterlösung in Schritten und Fotos eines Rechenwegs.

1. Lies den Rechenweg Zeile für Zeile WORTGETREU ab – auch Fehler genau so, wie sie dastehen; nichts verbessern. Formeln in LaTeX mit $…$.
2. Bewerte jede Zeile mit "status":
   - "ok": richtig (ein anderer, aber richtiger Weg ist auch ok – vergleiche inhaltlich, nicht wörtlich),
   - "fehler": hier passiert ein eigener Fehler,
   - "folgefehler": aus einer früheren falschen Zeile richtig weitergerechnet,
   - "unklar": nicht lesbar.
3. Bei "fehler": in "comment" kurz und konkret, was falsch ist (ein bis zwei Sätze), in "fix" die richtige Zeile. Bei "folgefehler": in "comment", dass richtig weitergerechnet wurde, in "fix", was mit der richtigen Rechnung dastünde.
4. "finalAnswer": das Endergebnis der Person als Formel in Eingabe-Schreibweise ohne linke Seite (z.B. "x - sqrt(2*x - 4)"); leer, wenn keins dasteht.
5. "firstErrorStep": Nummer des Musterlösungs-Schritts, in dem der erste Fehler passiert; null, wenn alles stimmt.
6. "summary": ein Satz (z.B. "1 Fehler in Zeile 3 – die Methode stimmt").
7. "grade": "gut" (alles richtig), "schwer" (Methode richtig, kleine Rechenfehler) oder "nochmal" (falsche Methode oder mehrere Fehler).

Antworte NUR mit JSON:
{"lines": [{"n": 1, "text": "...", "status": "ok", "comment": "", "fix": ""}], "finalAnswer": "...", "firstErrorStep": null, "summary": "...", "grade": "gut"}""";
}
