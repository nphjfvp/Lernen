/// Was ein Modell-Test prüft (Einstellungen → „Test“ neben der Modellauswahl).
enum ModelTestKind {
  questions('Fragen erstellen', 'Aus einer Seite entstehen Lernkonzepte und Karteikarten – wie beim Nachbereiten.'),
  lesson('Visuelle Lektion', 'Aus einer Seite entsteht eine Lektion mit Zeichnungen – wie bei „Visuell lernen“.'),
  explain('Erklärung', 'Das Modell erklärt die Lösung einer Frage – wie „Erklären“ nach dem Antworten.'),
  vision('Seite abschreiben', 'Das Modell liest eine Seite als Bild – wie bei gescannten Folien.'),
  crosscheck('Fragen gegenprüfen', 'Das Modell sucht Fehler in erstellten Fragen – wie die Zweitmeinung beim Import.'),
  scene3d('3D-Modell', 'Aus deiner Beschreibung entsteht ein 3D-Modell – wie „Als 3D-Modell“ in einer Lektion.');

  const ModelTestKind(this.label, this.hint);

  final String label;
  final String hint;

  /// Braucht eine Seite oder einen Text als Eingabe.
  bool get needsDocument => switch (this) {
    questions || lesson || vision || crosscheck => true,
    explain || scene3d => false,
  };

  /// Die Tests einer Modell-Rolle der Einstellungen.
  static List<ModelTestKind> forRole(String role) => switch (role) {
    'question' => const [questions, lesson],
    'help' => const [explain],
    'vision' => const [vision],
    'crosscheck' => const [crosscheck],
    'scene3d' => const [scene3d],
    _ => const [questions],
  };

  static ModelTestKind? byName(Object? name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

/// Ergebnis EINES Tests mit EINEM Modell. Nur zum Vergleichen: bleibt 30
/// Minuten, mit [pinned] dauerhaft – und nur auf diesem Gerät.
class ModelTestResult {
  const ModelTestResult({
    required this.id,
    required this.kind,
    required this.modelId,
    required this.createdAt,
    required this.inputLabel,
    this.inputKey = '',
    this.pinned = false,
    this.duration = Duration.zero,
    this.cost,
    this.costEstimated = false,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.calls = 0,
    this.output = const {},
    this.error,
  });

  /// So lange bleibt ein Ergebnis ohne „Behalten“.
  static const keepFor = Duration(minutes: 30);

  final String id;
  final ModelTestKind kind;
  final String modelId;
  final DateTime createdAt;

  /// Woraus getestet wurde („Seite 3 von folien.pdf“, die Beschreibung …).
  final String inputLabel;

  /// Gleiche Eingabe = gleicher Schlüssel (Ergebnisse gehören zusammen).
  final String inputKey;
  final bool pinned;
  final Duration duration;

  /// Kosten in US-Dollar; null = unbekannt.
  final double? cost;
  final bool costEstimated;
  final int promptTokens;
  final int completionTokens;

  /// Zahl der KI-Anfragen (eine Lektion in zwei Stufen braucht mehrere).
  final int calls;

  /// Die Antwort, je nach [kind] (siehe ModelTestRunner).
  final Map<String, dynamic> output;

  /// Fehlermeldung, wenn der Test scheiterte.
  final String? error;

  bool get failed => error != null;

  bool isExpired(DateTime now) => !pinned && now.difference(createdAt) >= keepFor;

  /// Restzeit bis zum Löschen; null bei [pinned].
  Duration? remaining(DateTime now) {
    if (pinned) return null;
    final left = keepFor - now.difference(createdAt);
    return left.isNegative ? Duration.zero : left;
  }

  ModelTestResult copyWith({bool? pinned}) => ModelTestResult(
    id: id,
    kind: kind,
    modelId: modelId,
    createdAt: createdAt,
    inputLabel: inputLabel,
    inputKey: inputKey,
    pinned: pinned ?? this.pinned,
    duration: duration,
    cost: cost,
    costEstimated: costEstimated,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    calls: calls,
    output: output,
    error: error,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind.name,
    'model': modelId,
    'at': createdAt.millisecondsSinceEpoch,
    'input': inputLabel,
    if (inputKey.isNotEmpty) 'inputKey': inputKey,
    if (pinned) 'pinned': true,
    'ms': duration.inMilliseconds,
    if (cost != null) 'cost': cost,
    if (costEstimated) 'estimated': true,
    'in': promptTokens,
    'out': completionTokens,
    'calls': calls,
    'output': output,
    if (error != null) 'error': error,
  };

  static ModelTestResult? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final kind = ModelTestKind.byName(map['kind']);
    final id = map['id'];
    final at = map['at'];
    if (kind == null || id is! String || at is! int) return null;
    int number(String key) => switch (map[key]) {
      final num n => n.toInt(),
      _ => 0,
    };
    return ModelTestResult(
      id: id,
      kind: kind,
      modelId: '${map['model'] ?? ''}',
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
      inputLabel: '${map['input'] ?? ''}',
      inputKey: '${map['inputKey'] ?? ''}',
      pinned: map['pinned'] == true,
      duration: Duration(milliseconds: number('ms')),
      cost: switch (map['cost']) {
        final num n => n.toDouble(),
        _ => null,
      },
      costEstimated: map['estimated'] == true,
      promptTokens: number('in'),
      completionTokens: number('out'),
      calls: number('calls'),
      output: map['output'] is Map ? Map<String, dynamic>.from(map['output'] as Map) : const {},
      error: map['error'] is String ? map['error'] as String : null,
    );
  }
}
