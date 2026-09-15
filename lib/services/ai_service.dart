import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/app_settings.dart';
import '../models/flashcard.dart' show QuestionType;
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

  /// Zeichenobergrenze für Aufrufe, die bewusst NICHT gechunkt werden
  /// (Crosscheck-Quellmaterial dient nur als Kontext, keine vollständige
  /// Neuverarbeitung).
  static const int _crosscheckSourceCap = 40000;

  /// Wie viele bereits erfasste Stichpunkte/Konzepttitel maximal als
  /// Rolling-Context in den nächsten Chunk-Prompt übernommen werden – hält
  /// den Prompt bei sehr vielen Chunks trotzdem beschränkt.
  static const int _rollingContextLimit = 40;

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

    final response = await _client.post(
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
    );

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
einen schnellen Überblick. Antworte AUSSCHLIESSLICH mit validem JSON in genau
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
Nachbereitung vor. Du bekommst Vorlesungsfolien UND Übungsaufgaben zum
gleichen Thema (möglicherweise nur einen Abschnitt eines längeren
Materials, in dem Folien- und Übungsinhalte gemischt vorkommen können).
Analysiere den Abschnitt und erstelle:
1. Lernkonzepte, die erklären, WARUM die Übungsaufgaben so gelöst werden wie
   sie gelöst werden (der Fokus liegt auf tiefem Verständnis der Übungen,
   nicht auf reiner Theorie-Wiedergabe der Folien).
2. Karteikarten/Fragen zur Wiederholung dieser Konzepte.

WICHTIG zur Typwahl: verwende NICHT für alle Karten denselben Typ. "flashcard"
(freies front/back) ist die LETZTE Wahl, nur wenn WIRKLICH keiner der
anderen Typen passt – erzeuge höchstens für etwa ein Fünftel der Karten
diesen Typ, den Rest möglichst mit den spezifischeren Typen unten. Wähle pro
Frage den zum Inhalt passenden Typ:
   - "single_choice": klares Faktenwissen mit genau einer richtigen Antwort.
     Setze zusätzlich "escalate": true – das System steigert den
     Schwierigkeitsgrad solcher Fragen automatisch, sobald sie zuverlässig
     richtig beantwortet werden.
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

JEDER Eintrag in "flashcards" MUSS ALLE für seinen "type" nötigen Felder
enthalten (siehe Beispiele unten) – ein Eintrag mit nur "front" und sonst
nichts ist ungültig und wird verworfen.

Trägt eine Karteikarte inhaltlich zu einem der oben erstellten Konzepte bei,
ergänze zusätzlich "conceptTitle" mit EXAKT demselben Titel wie im
"concepts"-Array (Zeichen für Zeichen identisch, damit die Zuordnung
technisch funktioniert). Nicht jede Karte muss einem Konzept zugeordnet
werden – reines Einzelfaktenwissen ohne Konzeptbezug lässt das Feld einfach
weg.

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
    {"type": "flashcard", "front": "Frage", "back": "Antwort (Pflichtfeld, nie leer)"}
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
    void Function(int done, int total)? onProgress,
  }) async {
    final combinedText = (StringBuffer()
          ..writeln('=== VORLESUNGSFOLIEN ===')
          ..writeln(slidesText)
          ..writeln()
          ..writeln('=== ÜBUNGSAUFGABEN ===')
          ..writeln(exercisesText))
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
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format (siehe
oben), ohne Markdown-Codefences, ohne zusätzlichen Text davor/danach.
Antworte in der Sprache der Vorlage.
''';
    final userPrompt = 'Ursprüngliche Frage: $questionText\nBekannte Lösung: $currentAnswer';
    final raw = await _complete(systemPrompt, userPrompt);
    return _parseJsonObject(raw);
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

Sei dabei STRENG: wähle NUR Materialien, die für die Antwort tatsächlich
gebraucht werden – nicht "um jeden Preis" irgendetwas, nur weil es
thematisch entfernt passen könnte. Ist die Frage allgemein, hat sie keinen
erkennbaren Bezug zu einem der Themen im Index, oder lässt sie sich auch
ohne ein bestimmtes Material beantworten, liefere eine LEERE Liste – das
ist ein völlig normales, gutes Ergebnis, kein Fehler und keine Notlösung.
Es ist besser, zu wenig auszuwählen als zu viel.

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
    final candidate = _extractJsonBlock(raw);
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
