/// Verbrauch EINER KI-Anfrage, wie OpenRouter ihn in der Antwort meldet
/// (`usage`): Tokens rein/raus und die Kosten in US-Dollar.
class AiUsage {
  const AiUsage({
    required this.at,
    required this.model,
    required this.label,
    required this.promptTokens,
    required this.completionTokens,
    this.cost,
    this.estimated = false,
  });

  final DateTime at;
  final String model;

  /// Worum es ging: die erste Zeile des System-Prompts.
  final String label;
  final int promptTokens;
  final int completionTokens;

  /// Kosten in US-Dollar; null = unbekannt (kein Preis gemeldet).
  final double? cost;

  /// true = nicht von OpenRouter gemeldet, sondern aus Tokens und Listenpreis
  /// gerechnet.
  final bool estimated;

  /// Liest den `usage`-Block einer OpenRouter-Antwort; null, wenn keiner da ist.
  static AiUsage? fromResponse(Object? usage, {required String model, required String label, DateTime? at}) {
    if (usage is! Map) return null;
    int tokens(String key) => switch (usage[key]) {
      final num n => n.toInt(),
      _ => 0,
    };
    final cost = switch (usage['cost']) {
      final num n when n >= 0 => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };
    final prompt = tokens('prompt_tokens');
    final completion = tokens('completion_tokens');
    if (prompt == 0 && completion == 0 && cost == null) return null;
    return AiUsage(
      at: at ?? DateTime.now(),
      model: model,
      label: label,
      promptTokens: prompt,
      completionTokens: completion,
      cost: cost,
    );
  }

  AiUsage withEstimate(double? promptPerMillion, double? completionPerMillion) {
    if (cost != null || promptPerMillion == null || completionPerMillion == null) return this;
    return AiUsage(
      at: at,
      model: model,
      label: label,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      cost: (promptTokens * promptPerMillion + completionTokens * completionPerMillion) / 1000000,
      estimated: true,
    );
  }

  Map<String, dynamic> toMap() => {
    'at': at.millisecondsSinceEpoch,
    'model': model,
    'label': label,
    'in': promptTokens,
    'out': completionTokens,
    if (cost != null) 'cost': cost,
    if (estimated) 'estimated': true,
  };

  static AiUsage? fromMap(Map<String, dynamic>? map) {
    if (map == null || map['at'] is! int) return null;
    return AiUsage(
      at: DateTime.fromMillisecondsSinceEpoch(map['at'] as int),
      model: map['model'] as String? ?? '',
      label: map['label'] as String? ?? '',
      promptTokens: (map['in'] as num?)?.toInt() ?? 0,
      completionTokens: (map['out'] as num?)?.toInt() ?? 0,
      cost: (map['cost'] as num?)?.toDouble(),
      estimated: map['estimated'] == true,
    );
  }
}

/// Summe je Tag und Modell – bleibt erhalten, auch wenn die einzelnen
/// Anfragen (nur die letzten) schon wieder gelöscht sind.
class AiUsageTotal {
  const AiUsageTotal({
    required this.day,
    required this.model,
    this.calls = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cost = 0,
    this.unknownCalls = 0,
    this.estimatedCalls = 0,
  });

  /// Tag in Ortszeit, `JJJJ-MM-TT`.
  final String day;
  final String model;
  final int calls;
  final int promptTokens;
  final int completionTokens;
  final double cost;

  /// Anfragen ohne bekannten Preis (in [cost] nicht enthalten).
  final int unknownCalls;
  final int estimatedCalls;

  String get id => '$day|$model';

  static String dayOf(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  AiUsageTotal plus(AiUsage usage) => AiUsageTotal(
    day: day,
    model: model,
    calls: calls + 1,
    promptTokens: promptTokens + usage.promptTokens,
    completionTokens: completionTokens + usage.completionTokens,
    cost: cost + (usage.cost ?? 0),
    unknownCalls: unknownCalls + (usage.cost == null ? 1 : 0),
    estimatedCalls: estimatedCalls + (usage.estimated ? 1 : 0),
  );

  AiUsageTotal merge(AiUsageTotal other) => AiUsageTotal(
    day: day,
    model: model,
    calls: calls + other.calls,
    promptTokens: promptTokens + other.promptTokens,
    completionTokens: completionTokens + other.completionTokens,
    cost: cost + other.cost,
    unknownCalls: unknownCalls + other.unknownCalls,
    estimatedCalls: estimatedCalls + other.estimatedCalls,
  );

  Map<String, dynamic> toMap() => {
    'day': day,
    'model': model,
    'calls': calls,
    'in': promptTokens,
    'out': completionTokens,
    'cost': cost,
    if (unknownCalls > 0) 'unknown': unknownCalls,
    if (estimatedCalls > 0) 'estimated': estimatedCalls,
  };

  static AiUsageTotal? fromMap(Map<String, dynamic>? map) {
    if (map == null || map['day'] is! String) return null;
    return AiUsageTotal(
      day: map['day'] as String,
      model: map['model'] as String? ?? '',
      calls: (map['calls'] as num?)?.toInt() ?? 0,
      promptTokens: (map['in'] as num?)?.toInt() ?? 0,
      completionTokens: (map['out'] as num?)?.toInt() ?? 0,
      cost: (map['cost'] as num?)?.toDouble() ?? 0,
      unknownCalls: (map['unknown'] as num?)?.toInt() ?? 0,
      estimatedCalls: (map['estimated'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Betrag in US-Dollar, deutsch geschrieben: kleine Beträge genauer
/// („0,0034 \$“), größere auf Cent („1,25 \$“).
String formatUsd(double value) {
  final digits = value == 0
      ? 2
      : value < 0.01
      ? 4
      : value < 1
      ? 3
      : 2;
  return '${value.toStringAsFixed(digits).replaceAll('.', ',')} \$';
}
