import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_settings.dart';
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

  Future<String> _complete(String systemPrompt, String userPrompt) async {
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
          {'role': 'user', 'content': userPrompt},
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
2. Karteikarten (Frage/Antwort) zur Wiederholung dieser Konzepte.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{
  "concepts": [
    {"title": "Konzeptname", "explanation": "Ausführliche Erklärung mit Bezug zu den Übungsaufgaben"}
  ],
  "flashcards": [
    {"front": "Frage", "back": "Antwort"}
  ]
}
Erstelle so viele Konzepte/Karteikarten wie der Abschnitt hergibt (auch
wenige, wenn der Abschnitt kurz ist). Wenn bereits erstellte Konzepte aus
vorherigen Abschnitten genannt werden, erstelle diese NICHT erneut.
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
Lernkonzepte und Karteikarten. Prüfe die Konzepte und Karteikarten auf
fachliche Fehler, Ungenauigkeiten oder Widersprüche zum Ausgangsmaterial.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{
  "ok": true,
  "issues": [
    {"title": "Betroffenes Konzept/Karteikarte", "problem": "Was ist falsch/ungenau", "suggestion": "Korrekturvorschlag"}
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
