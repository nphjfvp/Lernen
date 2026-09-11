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
  });

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
      };

  factory AiModelInfo.fromMap(Map<String, dynamic> map) => AiModelInfo(
        id: map['id'] as String,
        name: map['name'] as String,
        contextLength: map['contextLength'] as int?,
        promptPricePerMillion: (map['promptPricePerMillion'] as num?)?.toDouble(),
        completionPricePerMillion: (map['completionPricePerMillion'] as num?)?.toDouble(),
        supportsVision: map['supportsVision'] as bool,
        isFree: map['isFree'] as bool,
      );
}
