/// Ein Modell aus OpenRouters öffentlichem Modell-Katalog
/// (https://openrouter.ai/api/v1/models). Wird zur Laufzeit vom Gerät des
/// Nutzers abgerufen statt in der App fest hinterlegt zu sein – so bleibt
/// die Auswahl automatisch aktuell, ohne dass ein App-Update nötig ist.
class AiModelInfo {
  const AiModelInfo({
    required this.id,
    required this.name,
    required this.contextLength,
    required this.promptPricePerMillion,
    required this.completionPricePerMillion,
    required this.supportsVision,
    required this.isFree,
    this.maxOutputTokens,
  });

  /// Wie viele Tokens das Modell höchstens ausgeben kann (OpenRouter:
  /// `top_provider.max_completion_tokens`); null, wenn nicht gemeldet.
  final int? maxOutputTokens;

  /// Obergrenze, die die App je Anfrage als `max_tokens` mitschickt.
  static const requestCap = 32000;

  /// `max_tokens` für Anfragen an dieses Modell: sein Ausgabe-Limit, höchstens
  /// [requestCap] und höchstens das halbe Kontextfenster (der Prompt braucht
  /// auch Platz). Ohne Angabe gilt sonst die Voreinstellung des Anbieters –
  /// bei manchen nur 4096 Tokens, dann brechen lange Antworten (viele
  /// Aufgaben, Lektionen mit Szenen) mittendrin ab.
  int? get requestMaxTokens {
    final max = maxOutputTokens;
    if (max == null || max < 1024) return null;
    var limit = max > requestCap ? requestCap : max;
    final context = contextLength;
    if (context != null && limit > context ~/ 2) limit = context ~/ 2;
    return limit < 1024 ? null : limit;
  }

  final String id;
  final String name;
  final int? contextLength;

  /// USD pro 1 Million Input-/Output-Tokens. Null, wenn OpenRouter keinen
  /// Preis meldet (z.B. bei manchen experimentellen/kostenlosen Modellen).
  final double? promptPricePerMillion;
  final double? completionPricePerMillion;

  final bool supportsVision;
  final bool isFree;

  factory AiModelInfo.fromOpenRouterJson(Map<String, dynamic> json) {
    final pricing = json['pricing'] as Map<String, dynamic>? ?? const {};
    final promptPrice = _perMillion(pricing['prompt']);
    final completionPrice = _perMillion(pricing['completion']);
    final architecture = json['architecture'] as Map<String, dynamic>? ?? const {};
    final inputModalities = (architecture['input_modalities'] as List?)?.map((e) => e.toString()) ?? const [];
    final modalityString = (architecture['modality'] as String?) ?? '';
    final supportsVision = inputModalities.contains('image') || modalityString.contains('image');
    final id = json['id'] as String? ?? '';

    return AiModelInfo(
      id: id,
      name: (json['name'] as String?)?.trim().isNotEmpty == true ? json['name'] as String : id,
      contextLength: (json['context_length'] as num?)?.toInt(),
      promptPricePerMillion: promptPrice,
      completionPricePerMillion: completionPrice,
      supportsVision: supportsVision,
      isFree: id.endsWith(':free') || (promptPrice == 0 && completionPrice == 0),
      maxOutputTokens: switch (json['top_provider']) {
        final Map top => (top['max_completion_tokens'] as num?)?.toInt(),
        _ => null,
      },
    );
  }

  static double? _perMillion(dynamic rawPricePerToken) {
    if (rawPricePerToken == null) return null;
    final value = double.tryParse(rawPricePerToken.toString());
    if (value == null) return null;
    return value * 1000000;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'contextLength': contextLength,
        'promptPricePerMillion': promptPricePerMillion,
        'completionPricePerMillion': completionPricePerMillion,
        'supportsVision': supportsVision,
        'isFree': isFree,
        if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
      };

  factory AiModelInfo.fromMap(Map<String, dynamic> map) => AiModelInfo(
        id: map['id'] as String,
        name: map['name'] as String,
        contextLength: map['contextLength'] as int?,
        promptPricePerMillion: (map['promptPricePerMillion'] as num?)?.toDouble(),
        completionPricePerMillion: (map['completionPricePerMillion'] as num?)?.toDouble(),
        supportsVision: map['supportsVision'] as bool,
        isFree: map['isFree'] as bool,
        maxOutputTokens: (map['maxOutputTokens'] as num?)?.toInt(),
      );
}
