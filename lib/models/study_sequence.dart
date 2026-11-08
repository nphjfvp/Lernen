/// „Der Reihe nach“: Aufgaben einer Einheit oder einer PDF in ihrer
/// Reihenfolge durcharbeiten – mit gespeichertem Stand (siehe StudySequence).
library;

String _str(Object? raw) => '${raw ?? ''}'.trim();

/// Was der Reihe nach durchgearbeitet wird.
enum StudySequenceKind { unit, material }

class StudySequenceSource {
  const StudySequenceSource({required this.kind, required this.id, required this.title});

  final StudySequenceKind kind;

  /// Einheit- bzw. Material-ID.
  final String id;
  final String title;

  /// Schlüssel des gespeicherten Stands (je Fach eindeutig).
  String get key => '${kind.name}:$id';
}

/// Stand einer Aufgabe in der Reihenfolge.
enum StudySequenceStatus {
  /// Richtig gelöst – kommt in der nächsten Runde nicht mehr.
  solved,

  /// „Kann ich schon“ bzw. beim Neustart davor liegend – zählt als erledigt.
  skipped,

  /// Nicht geschafft – kommt in der nächsten Runde wieder.
  failed,
}

class StudySequenceProgress {
  const StudySequenceProgress({
    required this.moduleId,
    required this.key,
    this.status = const {},
    this.nextId,
    required this.updatedAt,
  });

  final String moduleId;
  final String key;

  /// Karten-ID → Stand; fehlt eine Karte, ist sie noch offen.
  final Map<String, StudySequenceStatus> status;

  /// Mit dieser Karte geht die laufende Runde weiter (null = Runde beendet,
  /// die nächste beginnt bei der ersten offenen Aufgabe).
  final String? nextId;
  final DateTime updatedAt;

  String get id => '$moduleId|$key';

  bool isDone(String cardId) {
    final s = status[cardId];
    return s == StudySequenceStatus.solved || s == StudySequenceStatus.skipped;
  }

  StudySequenceProgress copyWith({
    Map<String, StudySequenceStatus>? status,
    String? nextId,
    bool clearNext = false,
    DateTime? updatedAt,
  }) => StudySequenceProgress(
    moduleId: moduleId,
    key: key,
    status: status ?? this.status,
    nextId: clearNext ? null : (nextId ?? this.nextId),
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'moduleId': moduleId,
    'key': key,
    'status': {for (final e in status.entries) e.key: e.value.name},
    if (nextId != null) 'nextId': nextId,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static StudySequenceProgress? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final moduleId = _str(raw['moduleId']);
    final key = _str(raw['key']);
    if (moduleId.isEmpty || key.isEmpty) return null;
    final rawStatus = raw['status'];
    return StudySequenceProgress(
      moduleId: moduleId,
      key: key,
      status: {
        if (rawStatus is Map)
          for (final e in rawStatus.entries)
            '${e.key}': ?StudySequenceStatus.values.where((s) => s.name == '${e.value}').firstOrNull,
      },
      nextId: _str(raw['nextId']).isEmpty ? null : _str(raw['nextId']),
      updatedAt: DateTime.tryParse(_str(raw['updatedAt'])) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
