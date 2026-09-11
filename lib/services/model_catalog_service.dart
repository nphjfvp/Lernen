import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_model_info.dart';

class ModelCatalogException implements Exception {
  ModelCatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Ruft OpenRouters öffentlichen Modell-Katalog ab (kein API-Key nötig für
/// diesen Endpunkt). Das ist die "recherchiert selbst"-Antwort auf "welche
/// Modelle gibt es gerade": statt eine Liste in der App fest zu hinterlegen,
/// die mit jedem neuen Modell veraltet, fragt die App bei Bedarf OpenRouter
/// direkt – Vision-Fähigkeit, Preis und Gratis-Status kommen live von dort.
class ModelCatalogService {
  ModelCatalogService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint = 'https://openrouter.ai/api/v1/models';

  Future<List<AiModelInfo>> fetchModels() async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse(_endpoint));
    } catch (e) {
      throw ModelCatalogException('Modell-Katalog konnte nicht abgerufen werden: $e');
    }
    if (response.statusCode != 200) {
      throw ModelCatalogException('Modell-Katalog: OpenRouter antwortete mit ${response.statusCode}.');
    }

    late final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      throw ModelCatalogException('Modell-Katalog: Antwort war kein gültiges JSON ($e).');
    }

    final data = decoded is Map<String, dynamic> ? decoded['data'] as List? : null;
    if (data == null) {
      throw ModelCatalogException('Modell-Katalog: unerwartetes Antwortformat.');
    }

    final models = <AiModelInfo>[];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        final model = AiModelInfo.fromOpenRouterJson(entry);
        if (model.id.isNotEmpty) models.add(model);
      } catch (_) {
        // Ein einzelnes kaputtes Eintrags-Format soll nicht den ganzen Katalog kippen.
      }
    }
    return models;
  }
}

/// Kuratierte Startauswahl, bis der erste Live-Abruf gelungen ist (oder wenn
/// das Gerät gerade offline ist). Bewusst kurz – nur damit die App vor dem
/// ersten Katalog-Refresh nicht mit einer leeren Modellliste dasteht.
const List<AiModelInfo> kFallbackModels = [
  AiModelInfo(
    id: 'deepseek/deepseek-chat',
    name: 'DeepSeek Chat (Fallback)',
    contextLength: 64000,
    promptPricePerMillion: 0.28,
    completionPricePerMillion: 0.42,
    supportsVision: false,
    isFree: false,
  ),
  AiModelInfo(
    id: 'google/gemini-2.5-flash',
    name: 'Gemini 2.5 Flash (Fallback)',
    contextLength: 1048576,
    promptPricePerMillion: 0.30,
    completionPricePerMillion: 2.50,
    supportsVision: true,
    isFree: false,
  ),
  AiModelInfo(
    id: 'anthropic/claude-3.5-haiku',
    name: 'Claude 3.5 Haiku (Fallback)',
    contextLength: 200000,
    promptPricePerMillion: 0.80,
    completionPricePerMillion: 4.00,
    supportsVision: true,
    isFree: false,
  ),
];
