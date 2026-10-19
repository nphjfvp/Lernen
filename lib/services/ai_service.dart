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
import '../models/drawing_task.dart';
import '../models/phase_task.dart';
import '../models/step_task.dart';
import '../models/step_task_review.dart';
import '../models/task_verification.dart';
import 'calc_engine.dart';
import 'calc_plan.dart';
import 'condense_service.dart';
import 'lab_photo_reading.dart';
import 'lab_report_draft.dart';
import 'json_repair.dart';
import 'openrouter_errors.dart';
import 'question_parsing.dart';
import 'screen_awake.dart';
import 'text_chunker.dart';

part 'ai_prompts/material.dart';
part 'ai_prompts/import.dart';
part 'ai_prompts/check.dart';
part 'ai_prompts/tasks.dart';
part 'ai_prompts/visual.dart';

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

/// Ein Thema aus einer PDF für „Visuell lernen“ (siehe
/// [AiService.findVisualTopics]): Seiten, Idee zur Darstellung und ob sich
/// eine Animation lohnt ([visual] false → [reason]).
typedef VisualTopicIdea = ({
  String title,
  String summary,
  List<int> pages,
  String how,
  bool visual,
  String reason,
});

class AiService {
  /// [background]: Darf [backgroundTransport] übernehmen? Standard: nur ohne
  /// eigenen [client] (Tests geben einen vor).
  AiService({required this.apiKey, required this.model, http.Client? client, bool? background})
      : _client = client ?? http.Client(),
        _useBackground = background ?? client == null;

  final String apiKey;
  final String model;
  final http.Client _client;

  final bool _useBackground;

  /// Übertragung, die weiterläuft, wenn die App im Hintergrund ist (unter
  /// Android über WorkManager, gesetzt in main.dart). Scheitert sie selbst
  /// (keine HTTP-Antwort), geht die Anfrage auf dem normalen Weg raus.
  /// [label]: worum es geht (für die Absturz-Notiz).
  static Future<http.Response> Function(Uri url, Map<String, String> headers, String body, String label)?
  backgroundTransport;

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  /// Großzügig, da einzelne Generierungsaufrufe (große Chunks, Vision-
  /// Modelle) legitimerweise mehrere Minuten dauern können. Danach wird
  /// gefragt ([onSlowResponse]) statt sofort abgebrochen. Nur Tests ändern
  /// den Wert.
  static Duration requestTimeout = const Duration(minutes: 3);

  /// Pausen vor dem 2., 3. … Versuch bei vorübergehenden Fehlern (siehe
  /// [OpenRouterErrors.transientCodes]); ein `Retry-After` des Servers geht
  /// vor. Nur Tests ändern den Wert.
  static List<Duration> retryDelays = const [Duration(seconds: 3), Duration(seconds: 8)];

  /// Fragt nach [requestTimeout] ohne Antwort, ob weiter gewartet werden soll
  /// (true) – die Anfrage läuft dabei weiter, nichts wird neu gestartet.
  /// [waited] ist die bisherige Wartezeit, [done] wird fertig, sobald die
  /// Antwort doch noch kommt (ein offener Dialog schließt sich dann selbst).
  /// Ohne Hook (Tests, kein Bildschirm) bricht die Anfrage wie bisher ab.
  static Future<bool> Function(Duration waited, Future<void> done)? onSlowResponse;

  /// Zeichenobergrenze für Aufrufe, die bewusst NICHT gechunkt werden
  /// (Crosscheck-Quellmaterial dient nur als Kontext, keine vollständige
  /// Neuverarbeitung).
  static const int _crosscheckSourceCap = 40000;

  /// Wie viele bereits erfasste Stichpunkte/Konzepttitel maximal als
  /// Rolling-Context in den nächsten Chunk-Prompt übernommen werden – hält
  /// den Prompt bei sehr vielen Chunks trotzdem beschränkt.
  static const int _rollingContextLimit = 40;

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

    final url = Uri.parse(_endpoint);
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://github.com/nphjfvp/lernen',
      'X-Title': 'Lernen',
    };
    final body = jsonEncode({
      'model': model,
      'temperature': temperature,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userContent},
      ],
    });
    Future<http.Response> sendOnce() async {
      final background = _useBackground ? backgroundTransport : null;
      if (background != null) {
        try {
          return await background(url, headers, body, _labelOf(systemPrompt));
        } on AiServiceException {
          rethrow;
        } catch (_) {
          // Hintergrund-Übertragung nicht verfügbar – normaler Weg.
        }
      }
      return _client.post(url, headers: headers, body: body);
    }

    // Vorübergehende Fehler (Überlastung, Anbieter kurz weg, Verbindung
    // abgerissen) nach kurzer Pause erneut versuchen – bei kostenlosen
    // Modellen kommt 429 ständig vor.
    var attempts = 0;
    Future<http.Response> send() async {
      while (true) {
        attempts++;
        final more = attempts <= retryDelays.length;
        try {
          final response = await sendOnce();
          if (!more || !OpenRouterErrors.isTransient(response.statusCode, response.body)) return response;
          await Future<void>.delayed(OpenRouterErrors.retryAfter(response.headers) ?? retryDelays[attempts - 1]);
        } on http.ClientException {
          if (!more) rethrow;
          await Future<void>.delayed(retryDelays[attempts - 1]);
        }
      }
    }

    final http.Response response;
    final release = ScreenAwake.hold();
    try {
      response = await _awaitPatiently(send());
    } on http.ClientException catch (e) {
      throw AiServiceException('Keine Verbindung zu OpenRouter: ${e.message}');
    } finally {
      release();
    }

    final errorCode = OpenRouterErrors.codeOf(response.statusCode, response.body);
    if (errorCode != null) {
      throw AiServiceException(
        OpenRouterErrors.message(errorCode, response.body, attempts: attempts),
        rawResponse: response.body,
      );
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

  /// Wartet auf [request] – ohne Obergrenze bliebe bei einer hängenden
  /// Verbindung (z.B. Netzwechsel unterwegs) der Lade-Spinner für immer
  /// stehen. Große Aufgaben brauchen aber auch mal länger: Nach jeweils
  /// [requestTimeout] entscheidet der Nutzer über [onSlowResponse], ob er
  /// weiter wartet; die Anfrage läuft solange weiter.
  static Future<T> _awaitPatiently<T>(Future<T> request) async {
    var waited = Duration.zero;
    while (true) {
      try {
        return await request.timeout(requestTimeout);
      } on TimeoutException {
        waited += requestTimeout;
        final ask = onSlowResponse;
        final minutes = _minutesText(waited);
        if (ask == null) {
          throw AiServiceException('Keine Antwort von OpenRouter nach $minutes – bitte erneut versuchen.');
        }
        final done = request.then<void>((_) {}, onError: (Object _) {});
        if (!await ask(waited, done)) {
          throw AiServiceException(
            'Abgebrochen – OpenRouter hat nach $minutes nicht geantwortet. Bei großen Aufgaben hilft '
            'oft, weniger Seiten auf einmal zu schicken oder ein schnelleres Modell zu wählen.',
          );
        }
      }
    }
  }

  /// Kurzbeschreibung einer Anfrage: die erste Zeile ihres System-Prompts.
  static String _labelOf(String systemPrompt) {
    final line = systemPrompt.trim().split('\n').first.trim();
    return line.length > 90 ? '${line.substring(0, 90)}…' : line;
  }

  static String _minutesText(Duration d) => d.inSeconds < 60
      ? '${d.inSeconds} Sekunden'
      : (d.inMinutes == 1 ? '1 Minute' : '${d.inMinutes} Minuten');

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
      final parsed = await _json(raw);
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
      final parsed = await _json(raw);

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
      final parsed = await _json(raw);
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
      final parsed = await _json(raw);
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
        parsed = await _json(raw);
      } on AiServiceException {
        // Ein Abschnitt, der nicht lesbar war, wird einmal wiederholt.
        final raw = await _complete(_condenseSelectSystemPrompt, b.toString(), temperature: 0.1);
        raws.add(raw);
        parsed = await _json(raw);
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
      return await _json(raw);
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
      final parsed = await _json(raw);

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
    final parsed = await _json(raw);
    return (parsed['flashcards'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

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
      final parsed = await _json(raw);
      flashcards.addAll(_mapsIn(parsed['flashcards']));
      onProgress?.call(i + 1, chunks.length);
    }
    return flashcards;
  }

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
      '(Seitenkoordinaten) – diese Stellen werden abgedeckt. Sind die '
      'Antwortoptionen einer Auswahlfrage selbst Bilder (z.B. Gefügebilder a–d '
      'zum Zuordnen), gib bei JEDER Option "imageBox": [links, oben, rechts, '
      'unten] um ihr Bild an und als "text" nur die Beschriftung (z.B. "Bild a") '
      '– die App schneidet jedes Bild aus und zeigt es als Antwort.';

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
      await _json(raw),
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
    return parseImportVerification(await _json(raw), pageNumbers);
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
    return parseStageExpansions(await _json(raw), wanted);
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
    return await _json(raw);
  }

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
    return parsePageQuestionGroups(await _json(raw));
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
    return await _json(raw);
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
        QuestionType.sketch ||
        QuestionType.phase ||
        QuestionType.drawing =>
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
    return await _json(raw);
  }

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
    final parsed = await _json(raw);
    return parsed['correct'] == true;
  }

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
    return parseBlankVerdicts(await _json(raw), solutions.length);
  }

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
    return parseBlankVerdicts(await _json(raw), items.length);
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
    final parsed = await _json(raw);
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
    final parsed = await _json(raw);
    final ids = (parsed['relevant_ids'] as List?)?.map((e) => e.toString()).toList();
    return ids ?? const [];
  }

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
    final parsed = await _json(raw);
    return (parsed['highlights'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

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
    return parseStageAssignments(await _json(raw));
  }

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
    final parsed = await _json(raw);
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

  /// Liest die Antwort als JSON-Objekt – erst mit lokaler Reparatur
  /// ([JsonRepair]: Codefences, LaTeX, Zeilenumbrüche, Kommas, abgeschnitten),
  /// sonst schickt sie die Antwort samt Fehler einmal an die KI zurück, die
  /// sie als gültiges JSON neu ausgibt ([repairJson]). Der Nutzer muss nichts
  /// neu eingeben.
  Future<Map<String, dynamic>> _json(String raw) async {
    Object? decoded;
    try {
      decoded = JsonRepair.decode(raw);
    } on FormatException catch (e) {
      try {
        decoded = await repairJson(raw, error: e.message);
      } on AiServiceException catch (r) {
        throw AiServiceException(
          'Antwort der KI konnte nicht als JSON gelesen werden (auch nicht nach Reparatur): ${r.message}',
          rawResponse: raw,
        );
      }
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    // Nur eine Liste statt des Objekts (z.B. gleich die Karten): unter den
    // üblichen Schlüsseln weitergeben.
    if (decoded is List) return {'items': decoded, 'flashcards': decoded, 'tasks': decoded};
    throw AiServiceException('Antwort der KI ist kein JSON-Objekt.', rawResponse: raw);
  }

  /// Lässt kaputtes JSON von der KI reparieren: sie bekommt den Text und die
  /// Fehlermeldung und gibt denselben Inhalt als gültiges JSON zurück. Auch
  /// für eingefügtes JSON einer externen KI. Wirft [AiServiceException].
  Future<Object?> repairJson(String raw, {String error = ''}) async {
    final reply = await _complete(
      _jsonRepairSystemPrompt,
      'Fehler beim Einlesen: ${error.isEmpty ? 'kein gültiges JSON' : error}\n\n'
      'Text:\n${_cap(raw, 120000)}',
      temperature: 0,
    );
    try {
      return JsonRepair.decode(reply);
    } on FormatException catch (e) {
      throw AiServiceException('Auch die reparierte Antwort ist kein gültiges JSON: ${e.message}', rawResponse: reply);
    }
  }

  // -- Laborversuch ---------------------------------------------------------

  /// Text je Quelle (Anleitung, Theorie-Skript), den die KI beim Einlesen eines
  /// Versuchs sieht – längere Skripte werden gekürzt.
  static const labSourceCap = 45000;

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
    return await _json(raw);
  }

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
    return parseLabFeedback(await _json(raw), forText: answer, at: at);
  }

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
    return parseLabFeedback(await _json(raw), forText: text, at: at);
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
    final plan = CalcPlan.fromJson(await _json(raw));
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
    final reading = LabPhotoReading.fromJson(await _json(raw), experiments);
    if (reading.isEmpty) {
      throw AiServiceException('Die KI konnte auf dem Foto nichts lesen – anderes Foto oder bessere Beleuchtung versuchen.',
          rawResponse: raw);
    }
    return reading;
  }

  // -- Berichtsentwurf --------------------------------------------------------

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
      await _json(raw),
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
      InteractiveKind.phase =>
        'Gewünscht: "kind": "phase" (Zustandsdiagramm) – nur wenn das gar nicht geht, "none" mit Begründung.',
      InteractiveKind.drawing =>
        'Gewünscht: "kind": "drawing" (Freihand-Skizze) – nur wenn das gar nicht geht, "none" mit Begründung.',
      null =>
        'Entscheide je Teilaufgabe selbst: "steps", "gantt", "crystal", "bom", "sketch", "phase", "drawing", "question" oder "none".',
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
    final drafts = parseInteractiveTasks(await _json(raw));
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
                    : data['system'] is Map
                        ? InteractiveKind.phase
                        : data['criteria'] is List
                        ? InteractiveKind.drawing
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
      phase: kind == InteractiveKind.phase ? PhaseTask.fromMap(data) : null,
      drawing: kind == InteractiveKind.drawing ? DrawingTask.fromMap(data) : null,
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
    final review = StepTaskReview.fromJson(await _json(raw));
    if (review.answer.isEmpty) {
      throw AiServiceException('Die KI hat keine Erklärung geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return review;
  }

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
    final review = PaperReview.fromJson(await _json(raw));
    if (review.lines.isEmpty) {
      throw AiServiceException(
        'Auf dem Foto war kein Rechenweg zu erkennen – bitte näher, gerade und bei gutem Licht fotografieren.',
        rawResponse: raw,
      );
    }
    return review;
  }

  // -- Visuell lernen ------------------------------------------------------------

  /// Erzeugt Lektionen für „Visuell lernen“: aus einem Thema / eigenen Beispiel
  /// des Nutzers ([topic]) und/oder Material ([material], [images] = Seiten).
  /// [detail]: "kurz", "normal", "ausführlich". [maxLessons]: bei einer ganzen
  /// PDF mehrere Lektionen (je Thema eine), sonst 1. [socratic]: der Nutzer
  /// will sich die Schritte selbst erarbeiten (Leitfragen besonders
  /// sorgfältig). Liefert die rohen Lektions-Objekte (siehe
  /// VisualLesson.fromMap).
  Future<List<Map<String, dynamic>>> generateVisualLessons({
    String topic = '',
    String material = '',
    List<Uint8List> images = const [],
    String detail = 'normal',
    int maxLessons = 1,
    bool socratic = false,
    String courseContext = '',
  }) async {
    if (topic.trim().isEmpty && material.trim().isEmpty && images.isEmpty) {
      throw AiServiceException('Gib ein Thema oder Beispiel ein oder wähle eine PDF.');
    }
    final buffer = StringBuffer()
      ..writeln('Detailgrad: $detail – ${switch (detail) {
        'kurz' => '3–4 Schritte, knappe Texte (1–2 Sätze).',
        'ausführlich' => '6–10 Schritte, ausführliche Texte (3–6 Sätze), jede Umformung einzeln.',
        _ => '4–7 Schritte, Texte mit 2–4 Sätzen.',
      }}')
      ..writeln('Höchstens $maxLessons Lektion${maxLessons == 1 ? '' : 'en'}'
          '${maxLessons > 1 ? ' – je abgeschlossenem Thema des Materials eine, Wichtiges zuerst' : ''}.')
      ..writeln(socratic
          ? 'Lernweg: SOKRATISCH – der Nutzer erarbeitet sich jeden Schritt selbst. Die "guide"-Fragen sind '
              'besonders wichtig: so gestellt, dass man mit Nachdenken und Blick auf die Simulation selbst darauf kommt.'
          : 'Lernweg: erklären (die "guide"-Fragen trotzdem mitliefern).')
      ..writeln();
    if (courseContext.trim().isNotEmpty) {
      buffer
        ..writeln('LERNPFAD (diese Lektion ist ein Thema davon – "recap" liefern):')
        ..writeln(_cap(courseContext.trim(), 6000))
        ..writeln();
    }
    if (topic.trim().isNotEmpty) {
      buffer
        ..writeln('Wunsch des Nutzers (Thema, eigenes Beispiel oder Aufgabe – genau daran halten):')
        ..writeln(_cap(topic.trim(), _interactiveTaskCap))
        ..writeln();
    } else {
      buffer.writeln('Kein eigenes Beispiel: Such dir selbst ein anschauliches, sinnvolles Beispiel zum Material.');
    }
    if (material.trim().isNotEmpty) {
      buffer
        ..writeln('Material (Text):')
        ..writeln(_cap(material.trim(), 24000))
        ..writeln();
    }
    if (images.isNotEmpty) buffer.writeln('Dem Text folgen ${images.length} Seite${images.length == 1 ? '' : 'n'} als Bild.');
    final raw = await _complete(
      _visualLessonSystemPrompt,
      _textWithImages(buffer.toString(), images, 'Seite'),
      temperature: 0.2,
    );
    final json = await _json(raw);
    final list = json['lessons'] ?? json['lektionen'];
    final lessons = <Map<String, dynamic>>[
      if (list is List)
        for (final l in list)
          if (l is Map) Map<String, dynamic>.from(l),
      if (list is! List && (json['steps'] is List)) json,
    ];
    if (lessons.isEmpty) {
      throw AiServiceException('Die KI hat keine Lektion geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return lessons.take(maxLessons).toList();
  }

  /// Analysiert Material für „Visuell lernen“ (wie die Themenliste bei
  /// interaktiven Aufgaben): abgeschlossene Themen mit Seiten, einer Idee, wie
  /// die App es zeigen kann, und ob sich das lohnt. [imagePages]: welche
  /// Seite jedes Bild ist. [topic]: Wunsch des Nutzers als Schwerpunkt.
  Future<List<VisualTopicIdea>> findVisualTopics({
    String topic = '',
    String material = '',
    List<Uint8List> images = const [],
    List<int> imagePages = const [],
    int maxTopics = 8,
  }) async {
    if (material.trim().isEmpty && images.isEmpty) {
      throw AiServiceException('Die PDF enthält keinen lesbaren Inhalt.');
    }
    final buffer = StringBuffer()..writeln('Höchstens $maxTopics Themen, Wichtiges zuerst.');
    if (topic.trim().isNotEmpty) {
      buffer.writeln('Wunsch des Nutzers (Schwerpunkt): ${_cap(topic.trim(), 2000)}');
    }
    if (material.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Material (Text):')
        ..writeln(_cap(material.trim(), 40000));
    }
    if (images.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Dem Text folgen ${images.length} Seiten als Bild'
            '${imagePages.length == images.length ? ' (der Reihe nach Seite ${imagePages.join(', ')})' : ''}.');
    }
    final raw = await _complete(
      _visualTopicsSystemPrompt,
      _textWithImages(buffer.toString(), images, 'Bild'),
      temperature: 0.1,
    );
    final json = await _json(raw);
    final list = json['topics'] ?? json['themen'];
    final topics = <VisualTopicIdea>[
      if (list is List)
        for (final t in list)
          if (t is Map && '${t['title'] ?? ''}'.trim().isNotEmpty)
            (
              title: '${t['title']}'.trim(),
              summary: '${t['summary'] ?? ''}'.trim(),
              pages: [
                if (t['pages'] is List)
                  for (final p in t['pages'] as List) ?int.tryParse('$p'),
              ],
              how: '${t['how'] ?? t['idea'] ?? ''}'.trim(),
              visual: t['visual'] != false && '${t['visual']}'.toLowerCase() != 'false',
              reason: '${t['reason'] ?? ''}'.trim(),
            ),
    ];
    if (topics.isEmpty) {
      throw AiServiceException('Die KI hat keine Themen gefunden – bitte erneut versuchen.', rawResponse: raw);
    }
    return topics.take(maxTopics).toList();
  }

  static const _visualTopicsSystemPrompt =
      r'''
Du analysierst Lernmaterial (z.B. Vorlesungsfolien, Skript, Übungsblatt) für den Modus "Visuell lernen" einer Lern-App. Teile es in abgeschlossene THEMEN und beurteile je Thema, ob und wie die App es anschaulich animieren kann.
''' +
      _visualToolsSpec +
      r'''

Antworte NUR mit JSON:
{"topics": [{
  "title": "kurzer Titel des Themas (Begriffe aus dem Material)",
  "summary": "worum es geht, 1 Satz",
  "pages": [Seitenzahlen, laut "--- Seite N ---" bzw. Bildangabe],
  "how": "konkrete Idee, wie die App es zeigt (welches Werkzeug, was sich bewegt) – 1–2 Sätze",
  "visual": true | false,
  "reason": "nur bei false: warum sich eine Animation hier nicht lohnt"
}]}

- "visual": true, wenn eine Animation das Verständnis wirklich verbessert (Vorgänge, Mechanismen, Zusammenhänge, Rechenwege, Diagramme). false bei reinen Aufzählungen, Definitionen ohne Vorgang, Organisatorischem, Geschichte, Literaturangaben – dann kurz begründen.
- Fasse zusammengehörige Seiten zu EINEM Thema zusammen; Titelseiten/Gliederungen nicht als Thema.
- Gibt der Nutzer einen Schwerpunkt vor, nimm nur Themen dazu.
- Deutsch, Formeln in $…$ (Backslashes verdoppeln).''';

  /// Lernpfad planen: aus den Themen (mehrerer Vorlesungen) eine sinnvolle
  /// Reihenfolge mit Übergängen und Voraussetzungen. [topics]: je Thema
  /// `{n, title, summary, how, source, visual}`. Liefert
  /// `{"title", "intro", "units": [{"n", "title", "bridge", "needs": [n…]}]}` –
  /// die Reihenfolge der Liste ist die Lernreihenfolge; reine Organisation
  /// darf wegfallen, zu kleine Themen dürfen zusammengelegt werden ("merge").
  Future<Map<String, dynamic>> planVisualCourse({
    required List<Map<String, dynamic>> topics,
    String wish = '',
  }) async {
    if (topics.isEmpty) throw AiServiceException('Keine Themen zum Planen.');
    final buffer = StringBuffer();
    if (wish.trim().isNotEmpty) buffer.writeln('Wunsch des Nutzers: ${_cap(wish.trim(), 2000)}\n');
    buffer
      ..writeln('Themen (in der Reihenfolge der Unterlagen):')
      ..writeln(_cap(jsonEncode(topics), 60000));
    final raw = await _complete(_visualCoursePlanSystemPrompt, buffer.toString(), temperature: 0.1);
    final json = await _json(raw);
    if (json['units'] is! List || (json['units'] as List).isEmpty) {
      throw AiServiceException('Die KI hat keinen Lernpfad geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return json;
  }

  /// Visueller Chat: beantwortet [question] im Gespräch ([history]: frühere
  /// Nachrichten, user = Nutzer) – [mode] "visual", "text" oder "both".
  /// Antwort: `{"title", "text", "variable", "domain", "functions", "show",
  /// "transform"}` (Darstellung im Lektionsformat, alles optional).
  Future<Map<String, dynamic>> visualChat({
    required String question,
    List<({bool user, String text})> history = const [],
    String mode = 'both',
    String subject = '',
  }) async {
    if (question.trim().isEmpty) throw AiServiceException('Stell eine Frage.');
    final buffer = StringBuffer();
    if (subject.trim().isNotEmpty) buffer.writeln('Fach: ${subject.trim()}');
    if (history.isNotEmpty) {
      buffer.writeln('Bisheriges Gespräch:');
      for (final m in history.length > 12 ? history.sublist(history.length - 12) : history) {
        buffer.writeln('${m.user ? 'Nutzer' : 'Du'}: ${_cap(m.text, 1500)}');
      }
      buffer.writeln();
    }
    buffer
      ..writeln('Frage: ${_cap(question.trim(), 4000)}')
      ..writeln('Gewünschte Antwort: ${switch (mode) {
        'visual' => 'VISUELL – vor allem eine Darstellung ("show"/"transform"), Text nur 1–3 Sätze dazu',
        'text' => 'SCHRIFTLICH – ausführlicher Text, keine Darstellung',
        _ => 'BEIDES – klarer Text und eine passende Darstellung',
      }}');
    final raw = await _complete(_visualChatSystemPrompt, buffer.toString(), temperature: 0.3);
    final json = await _json(raw);
    if ('${json['text'] ?? ''}'.trim().isEmpty && json['show'] is! Map && json['transform'] is! List) {
      throw AiServiceException('Die KI hat nicht geantwortet – bitte erneut versuchen.', rawResponse: raw);
    }
    return json;
  }

  static const _visualChatSystemPrompt =
      r'''
Du bist ein Tutor in einer Lern-App und erklärst im Chat – für jedes Fach (Mathe, Physik, Werkstoffkunde, Technik, Chemie, BWL …). Die App kann deine Antwort ANIMIERT zeigen. Wähle die Darstellung frei nach der Frage (2D-Szene meist am klarsten, 3D nur bei räumlichem Aufbau, Graph bei Zusammenhängen y = f(x), Fahrzeug nur bei Bewegung, Umformung bei Rechnungen).
''' +
      _visualToolsSpec +
      r'''

Antworte NUR mit JSON:
{"title": "kurzer Titel des Themas (nur bei der ersten Antwort eines Gesprächs)",
 "text": "Antwort, du-Form, Formeln in $…$ (Backslashes verdoppeln)",
 "variable": "t", "domain": [0, 10],
 "functions": [{"key": "s", "label": "…", "expr": "Eingabe-Schreibweise, nur die Variable", "unit": "…"}],
 "show": {"scene": {…}, "scene3d": {…}, "car": key, "carFrom": "position"|"velocity", "vehicle": "…", "plot": [keys], "tangent": key, "area": key},
 "transform": [{"latex": "Gleichung ohne $", "note": "was passiert und warum"}]}

- Beantworte genau die Frage, knüpfe an das bisherige Gespräch an (Rückfragen beziehen sich darauf).
- Halte dich an die gewünschte Art (visuell/schriftlich/beides). Felder, die du nicht brauchst, weglassen.
- Rechne sorgfältig; die App rechnet Funktionen selbst nach.''';

  /// „Darstellung ändern“: baut eine Lektion nach dem Wunsch des Nutzers um
  /// (z.B. „Formeln richtig darstellen“, „Rakete statt Auto“, „anderes
  /// Beispiel“). [stepIndex]: nur dieser Schritt (Index in "steps"; -1 =
  /// Ergebnis, -2 = Kurzfassung) – Antwort `{"step": {…}, "functions": […]}`;
  /// null = ganze Lektion – Antwort `{"lesson": {…}}` im Lektionsformat.
  Future<Map<String, dynamic>> reviseVisualLesson({
    required Map<String, dynamic> lesson,
    required String request,
    int? stepIndex,
  }) async {
    if (request.trim().isEmpty) throw AiServiceException('Schreib, was an der Darstellung anders sein soll.');
    final which = switch (stepIndex) {
      null => 'die GANZE Lektion',
      -1 => 'NUR das Ergebnis ("result")',
      -2 => 'NUR die Kurzfassung ("short")',
      final i => 'NUR Schritt ${i + 1} (steps[$i])',
    };
    final buffer = StringBuffer()
      ..writeln('Lektion (JSON):')
      ..writeln(_cap(jsonEncode(lesson), 60000))
      ..writeln()
      ..writeln('Zu ändern: $which')
      ..writeln('Wunsch des Nutzers: ${_cap(request.trim(), 3000)}')
      ..writeln()
      ..writeln(stepIndex == null
          ? 'Antworte mit {"lesson": {… die komplette überarbeitete Lektion im selben Format …}}.'
          : 'Antworte mit {"step": {… der überarbeitete Schritt: title, text, formula, show, guide …}, '
              '"functions": [… nur neue oder geänderte Funktionen, sonst weglassen …]}.');
    final raw = await _complete(_visualReviseSystemPrompt, buffer.toString(), temperature: 0.2);
    final json = await _json(raw);
    if (stepIndex == null ? json['lesson'] is! Map && json['steps'] is! List : json['step'] is! Map) {
      throw AiServiceException('Die KI hat keine überarbeitete Darstellung geliefert – bitte erneut versuchen.',
          rawResponse: raw);
    }
    return json;
  }

  static const _visualReviseSystemPrompt =
      r'''
Du überarbeitest in einer Lern-App eine Lektion aus "Visuell lernen" nach dem Wunsch des Nutzers. Das Format ist dasselbe wie beim Erstellen (title, intro, variable, domain, functions, steps mit title/text/formula/show/guide, result, short, recap, exercise).
''' +
      _visualToolsSpec +
      r'''

Regeln:
- Ändere, was der Nutzer will – das darf auch groß sein (anderes Beispiel, andere Darstellung, Rakete statt Auto, mehr Schritte). Alles andere bleibt WÖRTLICH erhalten.
- Wird ein anderes Beispiel gewünscht, passe Texte, Formeln, Funktionen, Szenen und – bei der ganzen Lektion – auch die Übung konsistent an. Rechne alles neu nach.
- Formeln in Texten und Szenen-Texten in $…$ – die App setzt sie als echte Formeln. Backslashes in JSON verdoppeln.
- Bei Szenen: sauber zeichnen, nichts überlappt ungewollt, Texte passen in ihre Kästen (lieber kürzer oder kleiner).
- Bezüge ("car", "plot", "tangent", "area") nur auf Funktionen, die es gibt oder die du in "functions" mitlieferst.
- Antworte NUR mit JSON.''';

  /// Rückfrage zu einem Schritt einer Lektion bzw. Erklärung eines Fehlers in
  /// der Übung. [mode]: "visual", "text" oder "both". Antwort:
  /// `{"text", "transform": [...], "functions": [...], "show": {...}}`.
  Future<Map<String, dynamic>> explainVisual({
    required Map<String, dynamic> lesson,
    String stepTitle = '',
    String stepText = '',
    String question = '',
    String mode = 'both',
    String wrongAnswer = '',
    String expectedAnswer = '',
    String fieldLabel = '',
  }) async {
    final buffer = StringBuffer()
      ..writeln('Lektion (JSON):')
      ..writeln(_cap(jsonEncode({
        for (final k in const ['title', 'intro', 'variable', 'domain', 'functions']) k: lesson[k],
        'steps': [
          for (final s in (lesson['steps'] as List? ?? const []))
            if (s is Map) {'title': s['title'], 'formula': s['formula']},
        ],
      }), 8000))
      ..writeln();
    if (stepTitle.isNotEmpty) {
      buffer
        ..writeln('Gefragter Schritt: $stepTitle')
        ..writeln(_cap(stepText, 3000))
        ..writeln();
    }
    if (wrongAnswer.isNotEmpty) {
      buffer
        ..writeln('In der Übung hat der Nutzer bei "$fieldLabel" FALSCH geantwortet: $wrongAnswer')
        ..writeln('Richtig wäre: $expectedAnswer')
        ..writeln('Erkläre genau, WARUM das falsch ist und was die falsche Antwort im echten Leben bedeuten würde '
            '(z.B. was das Auto dann täte). Zeig, wo der Fehler beim Umstellen/Rechnen passiert.')
        ..writeln();
    }
    buffer
      ..writeln('Frage des Nutzers: ${question.trim().isEmpty ? '(keine – erkläre den Schritt bzw. Fehler)' : question.trim()}')
      ..writeln('Gewünschte Erklärung: ${switch (mode) {
        'visual' => 'VISUELL – vor allem "transform" und/oder "show", Text nur 1–2 Sätze',
        'text' => 'SCHRIFTLICH – ausführlicher Text, "transform" und "show" weglassen',
        _ => 'BEIDES – Text und Visualisierung',
      }}');
    final raw = await _complete(_visualExplainSystemPrompt, buffer.toString(), temperature: 0.2);
    final json = await _json(raw);
    final text = '${json['text'] ?? ''}'.trim();
    if (text.isEmpty && json['transform'] is! List && json['show'] is! Map) {
      throw AiServiceException('Die KI hat keine Erklärung geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return json;
  }

  /// Sokratisch lernen: ein Zug im Dialog zu einem Schritt der Lektion. Die
  /// KI bewertet [answer] (leer = Eröffnungsfrage), führt mit Gegenfragen hin
  /// und verrät die Lösung nicht (auflösen kann die App selbst). [hint]: der Nutzer
  /// will einen konkreteren Tipp. [history]: bisheriger Dialog (user = Nutzer).
  /// Antwort: `{"reply", "reached": bool, "transform", "functions", "show"}`.
  Future<Map<String, dynamic>> visualSocraticTurn({
    required Map<String, dynamic> lesson,
    required int stepIndex,
    required Map<String, dynamic> step,
    List<({bool user, String text})> history = const [],
    String answer = '',
    bool hint = false,
  }) async {
    final steps = lesson['steps'] as List? ?? const [];
    final buffer = StringBuffer()
      ..writeln('Lektion (JSON):')
      ..writeln(_cap(jsonEncode({
        for (final k in const ['title', 'intro', 'variable', 'domain', 'functions']) k: lesson[k],
        'bisherige Schritte (schon erarbeitet)': [
          for (final s in steps.take(stepIndex))
            if (s is Map) {'title': s['title'], 'formula': s['formula']},
        ],
      }), 8000))
      ..writeln()
      ..writeln('AKTUELLER SCHRITT (Lösung – NICHT verraten):')
      ..writeln(_cap(jsonEncode({
        for (final k in const ['title', 'text', 'formula', 'guide']) k: step[k],
      }), 4000))
      ..writeln();
    if (history.isNotEmpty) {
      buffer.writeln('Bisheriger Dialog:');
      for (final turn in history.length > 16 ? history.sublist(history.length - 16) : history) {
        buffer.writeln('${turn.user ? 'Lernender' : 'Tutor'}: ${_cap(turn.text, 1500)}');
      }
      buffer.writeln();
    }
    if (hint) {
      buffer.writeln('Der Lernende bittet um einen TIPP: gib einen konkreteren Hinweis als bisher (gern mit Blick auf die '
          'Simulation), aber noch nicht die Lösung, und ende mit einer Frage.');
    } else if (answer.trim().isEmpty) {
      buffer.writeln('Eröffne den Schritt mit einer Leitfrage (gern auf Basis von "guide").');
    } else {
      buffer.writeln('Antwort des Lernenden: ${_cap(answer.trim(), 3000)}');
    }
    final raw = await _complete(_visualSocraticSystemPrompt, buffer.toString(), temperature: 0.3);
    final json = await _json(raw);
    if ('${json['reply'] ?? json['text'] ?? ''}'.trim().isEmpty) {
      throw AiServiceException('Die KI hat nicht geantwortet – bitte erneut versuchen.', rawResponse: raw);
    }
    return {
      ...json,
      'reply': '${json['reply'] ?? json['text']}'.trim(),
      'reached': json['reached'] == true || '${json['reached']}'.toLowerCase() == 'true',
    };
  }

  static const _visualSocraticSystemPrompt =
      r'''
Du bist ein sokratischer Tutor in einer Lern-App (Modus "Visuell lernen"). Der Lernende soll sich den AKTUELLEN SCHRITT einer Lektion SELBST erarbeiten.
''' +
      _visualToolsSpec +
      r'''

So gehst du vor:
- Verrate die Lösung, Formel oder das Ergebnis des Schritts NICHT (auflösen kann der Lernende selbst per Knopf). Führe mit EINER kurzen, konkreten Frage pro Zug hin.
- Prüfe die Antwort des Lernenden ehrlich. Ist sie richtig oder im Kern getroffen (eigene Worte genügen, Schreibweise egal), setze "reached": true, bestätige kurz, was er gut erkannt hat, und fasse den Schritt in 1–2 Sätzen zusammen.
- Ist sie teilweise richtig: würdige den richtigen Teil und frag gezielt nach dem fehlenden.
- Ist sie falsch: sag nicht nur "falsch", sondern zeig einen Widerspruch auf (z.B. "Wenn das stimmt, was müsste das Auto dann bei t = 0 tun? Schau es dir an.") und stell eine kleinere Frage.
- Nutze die Animation als Denkhilfe: Du darfst "show" setzen (gern eine eigene "scene"), damit der Lernende etwas beobachtet (z.B. Atome, die beim Erwärmen stärker schwingen, oder die Tangente an s, ohne v zu zeigen), und "functions" für Hilfsfunktionen (z.B. die Vermutung des Lernenden, um sie neben dem Original zu zeigen). Zeig dabei NICHT das Ergebnis des Schritts, solange "reached" false ist.
- Kurz bleiben: 1–4 Sätze, du-Form, ermutigend, Formeln in $…$.

Antworte NUR mit JSON:
{"reply": "deine Antwort/Frage (Backslashes verdoppeln)",
 "reached": true | false,
 "transform": [{"latex": "Gleichung ohne $", "note": "…"}],
 "functions": [{"key": "neu", "label": "…", "expr": "Eingabe-Schreibweise, nur die Variable der Lektion"}],
 "show": {"scene": {…}, "scene3d": {…}, "car": key, "carFrom": "position"|"velocity", "plot": [keys], "tangent": key, "area": key}}
Felder, die du nicht brauchst, weglassen.''';

  static const _visualLessonSystemPrompt =
      r'''
Du erstellst Lektionen für den Modus "Visuell lernen" einer Lern-App – für JEDES Fach (Mathe, Physik, Werkstoffkunde, Chemie, Elektrotechnik, Mechanik, Biologie, BWL …). Die App ZEIGT und ANIMIERT selbst; du lieferst Struktur, Texte, Funktionsterme und Szenen.

Ziel: Der Lernende versteht, WARUM jeder Schritt gemacht wird, WELCHE Formel/Regel gilt und WAS dabei anschaulich passiert. Wähle die Darstellung FREI nach dem Thema – kein festes Schema:
- Werkstoffkunde z.B.: Atome im Gitter (repeat), die beim Erwärmen stärker schwingen und Abstand gewinnen (Wärmeausdehnung); eine Versetzung, die durch das Gitter wandert (plastische Verformung); Körner, die wachsen (Rekristallisation); Kohlenstoffatome, die ins Gitter diffundieren; eine Abkühlkurve, die gezeichnet wird, während sich Kristalle bilden; Spannungs-Dehnungs-Kurve mit Probe, die sich längt und einschnürt. Räumlich (scene3d) z.B.: kfz-Elementarzelle, deren Atome wachsen, bis sie sich auf der Flächendiagonale berühren – mit Packungsdichte 74 % als mitlaufender Größe; Oktaederlücke im kfz-Gitter; Gleitebene (111) mit Gleitrichtung.
- Physik/Mechanik z.B.: Kräfte als Pfeile an einem Balken, Hebel, schiefe Ebene; Welle, Pendel, Feldlinien; Bewegung mit dem Auto.
- Mathe z.B.: Graph mit Tangente/Fläche, Umformungen, geometrische Konstruktionen als Szene.
- Wirtschaft/Sonstiges z.B.: Angebot/Nachfrage als Graph, Abläufe als animierte Kästen und Pfeile.
Das Auto NUR, wenn es wirklich um Bewegung geht. Gibt der Nutzer ein Thema/Beispiel vor, halte dich genau daran; liegt Material vor, nimm dessen Inhalt, Bezeichnungen und Beispiele – erfinde kein fachfremdes Beispiel.
''' +
      _visualToolsSpec +
      r'''

Antworte NUR mit JSON:
{"lessons": [{
  "title": "kurzer Titel",
  "intro": "Ausgangslage/Beispiel in 1–3 Sätzen (LaTeX in $…$)",
  "variable": "t",                 ← Variable der Funktionen (Zeit t, Dehnung x, Temperatur T …); nur nötig mit "functions"
  "domain": [0, 10],
  "functions": [{"key": "s", "label": "Weg s(t)", "expr": "0.5*t^2 + 2*t", "unit": "m"}],   ← nur, wenn Graphen/Auto vorkommen, sonst []
  "steps": [{"title": "…", "text": "Warum wir das machen, was es bedeutet, was man in der Animation sieht", "formula": "LaTeX ohne $ (optional)", "show": {…}, "guide": "Leitfrage, mit der man den Schritt selbst findet"}],
  "result": {"title": "Ergebnis", "text": "…", "formula": "…", "show": {…}},
  "short": {"title": "Kurzfassung", "text": "3–6 Kernpunkte, je Zeile mit • beginnend (LaTeX in $…$)", "formula": "die wichtigste Formel (optional)", "show": {… EINE Darstellung, die das Wichtigste auf einen Blick zeigt}},
  "recap": "nur im Lernpfad – siehe unten",
  "exercise": {"front": "Neue, ähnliche Aufgabe WORTGETREU mit allen Zahlen (LaTeX in $…$)", "simulate": "position" | "velocity" | "graph", "steps": [ … wie unten … ]}
}]}

Regeln für "functions":
- "expr" in EINGABE-SCHREIBWEISE, KEIN LaTeX: + - * / ^, sqrt(), exp(), ln(), sin(), cos(), pi; Dezimalpunkt; NUR die Variable – keine weiteren Buchstaben/Konstanten, setz Zahlen ein.
- "domain": Bereich, auf dem alle Funktionen definiert sind und gut aussehen. Rechne sorgfältig (auch Ableitungen/Stammfunktionen als eigene Funktion).

Regeln für "show": Zeige in JEDEM Schritt etwas, das genau diesen Schritt sichtbar macht (meist eine "scene", wo es passt Graph/Auto/Umformung). Eine Szene darf die vorige weiterführen (gleicher Aufbau, neue Bewegung). Bezüge nur auf vorhandene "functions"-keys.

Regeln für "short" (IMMER): Die Kurzfassung zum schnellen Wiedereinsteigen, wenn man das Thema schon einmal gelernt hat – das Wesentliche in wenigen Zeilen plus eine aussagekräftige Darstellung, keine neuen Inhalte.

Regeln für "recap" (NUR wenn ein Lernpfad angegeben ist, sonst weglassen): 2–4 Sätze Rückblick und Übergang – was aus den genannten früheren Themen gebraucht wird, kurz wiederholt, und warum dieses Thema jetzt darauf aufbaut ("Bei … haben wir gesehen, dass … – genau das brauchen wir jetzt, um …"). Knüpfe auch in den Schritten an die früheren Themen an, wo es passt.

Regeln für "guide" (sokratisches Lernen – JEDER Schritt bekommt eine):
- Eine offene Leitfrage, mit der der Lernende den Schritt SELBST herausfinden kann, OHNE dass sie die Lösung verrät. Knüpft an Vorwissen oder an das an, was die Animation gerade zeigt.
- Der Titel des Schritts darf das Ergebnis ebenfalls nicht verraten.

Regeln für "exercise" (eine Übung wie ein Rechenweg – die App prüft Zahlen und Formeln selbst):
- "steps": 2–5 Schritte; jeder {"title", "prompt" (Frage ohne Lösung), "fields": [{"label": z.B. "v(t) =", "kind": "formula" | "number", "answer": in Eingabe-Schreibweise, "variables": ["t"], "tolerance": nur bei gerundeten Zahlen, "mistakes": [{"answer": typischer Fehler, "feedback": kurze Rückmeldung, die zum Nachdenken anregt}]}], "hints": [2 gestufte Tipps], "result": Ergebnis des Schritts (LaTeX in $…$), "explanation": 1–2 Sätze}.
- Auch bei eher qualitativen Themen eine prüfbare Frage mit Zahl oder Formel finden (Anzahl Atome je Elementarzelle, Längenänderung, Anteil, Kraft, Abschätzung …). Nur wenn wirklich nichts Prüfbares passt, "exercise" weglassen.
- Ist das Endergebnis eine Funktion der Variablen, setz "simulate": "position" (Weg), "velocity" (Geschwindigkeit) oder "graph" – dann simuliert die App eine falsche Antwort neben der richtigen.
- Rechne jede erwartete Antwort selbst nach.

Allgemein: Deutsch, du-Form, Fachbegriffe erklären. Formeln in Texten in $…$, in JSON jeden Backslash verdoppeln.''';

  static const _visualExplainSystemPrompt =
      r'''
Du beantwortest in einer Lern-App eine Rückfrage zu einer visuellen Lektion (siehe JSON) – zu einem Schritt oder zu einem Fehler in der Übung. Wähle die Visualisierung frei nach dem Thema.
''' +
      _visualToolsSpec +
      r'''

Antworte NUR mit JSON:
{"text": "Erklärung, du-Form, Formeln in $…$ (Backslashes verdoppeln)",
 "transform": [{"latex": "Gleichung ohne $", "note": "was passiert und warum"}],
 "functions": [{"key": "neu", "label": "…", "expr": "Eingabe-Schreibweise, nur die Variable der Lektion", "unit": "…"}],
 "show": {"scene": {…}, "scene3d": {…}, "car": key, "carFrom": "position"|"velocity", "plot": [keys], "tangent": key, "area": key}}

- "transform": langsam, jeder Zwischenstand einzeln (z.B. bei y' = dy/dx: was dy und dx bedeuten, Differenzenquotient → Grenzwert → Schreibweise).
- "functions" nur, wenn du für die Erklärung neue Funktionen brauchst (z.B. die falsche Antwort des Nutzers als Funktion, um sie neben der richtigen zu zeigen); "show" darf auf die Funktionen der Lektion und die neuen verweisen.
- Bei einem Fehler: sag genau, welcher Rechenschritt falsch ist, wie es richtig geht und was die falsche Antwort im echten Leben bedeuten würde.
- Halte dich an den gewünschten Modus (visuell/schriftlich/beides). Felder, die du nicht brauchst, weglassen.''';

  /// Bewertet eine Freihand-Skizze (gezeichnet oder als Foto) an den
  /// Kriterien der Aufgabe. Je Fläche ein Bild; die App wertet das Urteil
  /// selbst aus ([DrawingReview.passes]). Für Bilder ein Vision-Modell wählen.
  Future<DrawingReview> reviewDrawing({
    required String task,
    required DrawingTask drawing,
    required List<({String panel, Uint8List image})> images,
  }) async {
    if (images.isEmpty) throw AiServiceException('Zeichne zuerst etwas – oder lade ein Foto deiner Skizze hoch.');
    final multi = drawing.panels.length > 1;
    final text = StringBuffer()
      ..writeln('Aufgabe:')
      ..writeln(_cap(task.trim(), _interactiveTaskCap))
      ..writeln();
    if (drawing.solution.trim().isNotEmpty) {
      text
        ..writeln('So sieht die Musterskizze aus: ${drawing.solution.trim()}')
        ..writeln();
    }
    text.writeln('Kriterien:');
    for (final (i, c) in drawing.criteria.indexed) {
      text.writeln('${i + 1}. ${multi && c.panel.isNotEmpty ? '[${c.panel}] ' : ''}${c.text}'
          '${c.required ? '' : ' (optional)'}');
    }
    final missing = [
      for (final p in drawing.surfaces)
        if (multi && !images.any((i) => i.panel == p)) p,
    ];
    if (missing.isNotEmpty) {
      text.writeln('\nNicht gezeichnet (Kriterien dazu sind nicht erfüllt): ${missing.join(', ')}.');
    }
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': text.toString()},
      for (final (i, img) in images.indexed) ...[
        {
          'type': 'text',
          'text': 'Bild ${i + 1}${multi ? ' – Fläche „${img.panel}“' : ''}:',
        },
        {
          'type': 'image_url',
          'image_url': {'url': 'data:${_imageMime(img.image)};base64,${base64Encode(img.image)}'},
        },
      ],
    ];
    final raw = await _complete(_drawingReviewSystemPrompt, content, temperature: 0);
    final review = DrawingReview.fromJson(await _json(raw), drawing.criteria.length);
    if (review.marks.every((m) => m == DrawingMark.unclear) && review.feedback.isEmpty) {
      throw AiServiceException('Die KI hat die Zeichnung nicht bewertet – bitte erneut versuchen.', rawResponse: raw);
    }
    return review;
  }

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

  /// Liest den JSON-Text einer externen KI (siehe [externalTaskPrompt]):
  /// {"tasks": [...]} mit interaktiven Aufgaben und Fragen, aber auch eine
  /// Liste fertiger Quizfragen ("flashcards"/"questions", z.B. aus dem
  /// Prompt im Nachbereiten). Fragen werden wie beim Import normalisiert
  /// (QuestionParsing.normalizeGeneratedFlashcard); unbrauchbare zählen in
  /// `dropped`. Wirft [AiServiceException], wenn das kein JSON ist.
  static ({List<InteractiveTaskDraft> drafts, int dropped}) parseImportedTasks(String raw) {
    final Object? decoded;
    try {
      decoded = JsonRepair.decode(raw);
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
    final verification = TaskVerification.fromJson(await _json(raw));
    if (verification.verdict == TaskVerdict.unclear && verification.comment.isEmpty) {
      throw AiServiceException('Die KI hat kein Urteil geliefert – bitte erneut versuchen.', rawResponse: raw);
    }
    return verification;
  }

}
