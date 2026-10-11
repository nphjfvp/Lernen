/// Eine markierte Frage (z.B. im Daily Quiz): ein Fehler ist aufgefallen
/// oder die Frage soll aus einem anderen Grund gemerkt werden. Eine
/// Markierung je Karte ([id] = Karten-ID); [front] hält den Fragetext fest,
/// damit die Liste ihn auch zeigt, wenn die Karte inzwischen fehlt.
library;

enum CardFlagKind { error, saved }

class CardFlag {
  const CardFlag({
    required this.cardId,
    required this.moduleId,
    required this.kind,
    this.note = '',
    this.front = '',
    required this.createdAt,
  });

  final String cardId;
  final String moduleId;
  final CardFlagKind kind;

  /// Was nicht stimmt bzw. warum gemerkt.
  final String note;
  final String front;
  final DateTime createdAt;

  String get id => cardId;

  String get kindLabel => kind == CardFlagKind.error ? 'Fehler gemeldet' : 'Gemerkt';

  CardFlag copyWith({CardFlagKind? kind, String? note, String? front}) => CardFlag(
    cardId: cardId,
    moduleId: moduleId,
    kind: kind ?? this.kind,
    note: note ?? this.note,
    front: front ?? this.front,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'id': cardId,
    'moduleId': moduleId,
    'kind': kind.name,
    if (note.isNotEmpty) 'note': note,
    if (front.isNotEmpty) 'front': front,
    'createdAt': createdAt.toIso8601String(),
  };

  static CardFlag? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? raw['cardId'] ?? ''}'.trim();
    final moduleId = '${raw['moduleId'] ?? ''}'.trim();
    if (id.isEmpty || moduleId.isEmpty) return null;
    return CardFlag(
      cardId: id,
      moduleId: moduleId,
      kind: '${raw['kind']}' == CardFlagKind.error.name ? CardFlagKind.error : CardFlagKind.saved,
      note: '${raw['note'] ?? ''}'.trim(),
      front: '${raw['front'] ?? ''}'.trim(),
      createdAt: DateTime.tryParse('${raw['createdAt']}') ?? DateTime.now(),
    );
  }
}
