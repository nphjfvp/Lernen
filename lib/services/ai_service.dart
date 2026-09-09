import 'dart:convert';

import 'package:http/http.dart' as http;

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
class AiService {
  AiService({required this.apiKey, required this.model, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  /// Zeichenobergrenze pro Anfrage. Sehr lange Foliensätze werden hart
  /// gekürzt statt (wie in der Vorgänger-App) in mehrere KI-Aufrufe zu
  /// zerlegt – bewusste Vereinfachung für den schlankeren Funktionsumfang.
  static const int maxInputChars = 60000;

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

  String _truncate(String text) {
    if (text.length <= maxInputChars) return text;
    return '${text.substring(0, maxInputChars)}\n\n[... gekürzt, Text war länger ...]';
  }

  /// Vorbereiten-Modus: strukturierte Zusammenfassung + Kernkonzepte aus
  /// Vorlesungsfolien für den schnellen Überblick vor der Sitzung.
  Future<Map<String, dynamic>> generateSummary(String slidesText) async {
    const systemPrompt = '''
Du bist ein Lernassistent für Studierende. Du bekommst den Text von
Vorlesungsfolien und erstellst daraus eine strukturierte Zusammenfassung für
einen schnellen Überblick. Antworte AUSSCHLIESSLICH mit validem JSON in genau
diesem Format, ohne Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{
  "title": "Kurzer Titel der Sitzung/des Themas",
  "overview": "Strukturierte Zusammenfassung, 3-6 Absätze, klar gegliedert",
  "key_points": ["Kernkonzept 1", "Kernkonzept 2", "..."]
}
Antworte in der Sprache der Vorlage.
''';
    final userPrompt = 'Vorlesungsfolien:\n\n${_truncate(slidesText)}';
    final raw = await _complete(systemPrompt, userPrompt);
    return _parseJsonObject(raw);
  }

  /// Nachbereiten-Modus: analysiert Folien UND Übungsaufgaben gemeinsam und
  /// erzeugt gezielte Lernkonzepte + Karteikarten. Fokus liegt laut Vorgabe
  /// auf der tiefen Durchdringung der Übungen, nicht nur auf Theorie.
  Future<Map<String, dynamic>> generateConceptsAndFlashcards({
    required String slidesText,
    required String exercisesText,
  }) async {
    const systemPrompt = '''
Du bist ein Lernassistent für Studierende und bereitest Stoff für die
Nachbereitung vor. Du bekommst Vorlesungsfolien UND Übungsaufgaben zum
gleichen Thema. Analysiere BEIDE gemeinsam und erstelle:
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
Erstelle 3-8 Konzepte und 8-20 Karteikarten, je nach Umfang des Materials.
Antworte in der Sprache der Vorlage.
''';
    final buffer = StringBuffer()
      ..writeln('Vorlesungsfolien:')
      ..writeln(_truncate(slidesText))
      ..writeln()
      ..writeln('Übungsaufgaben:')
      ..writeln(_truncate(exercisesText));
    final raw = await _complete(systemPrompt, buffer.toString());
    return _parseJsonObject(raw);
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
