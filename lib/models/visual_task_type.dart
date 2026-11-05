/// Aufgabentypen eines Fachs für „Aufgaben visuell lösen“: die KI ordnet die
/// vorhandenen Aufgaben und Fragen in typische Klausur-Aufgabentypen (z.B.
/// „Weg-Zeit-Funktion aus der Beschleunigung integrieren“). Aus einem Typ
/// stellt sie dann neue Aufgaben in Leicht/Mittel/Schwer.
library;

String _str(Object? raw) => '${raw ?? ''}'.trim();

class VisualTaskType {
  const VisualTaskType({required this.id, required this.title, this.description = '', this.cardIds = const []});

  final String id;
  final String title;

  /// Worum es geht und welche Schritte typisch sind.
  final String description;

  /// Karten des Fachs, die zu diesem Typ gehören (Beispiele für neue Aufgaben).
  final List<String> cardIds;

  Map<String, dynamic> toMap() => {'id': id, 'title': title, 'description': description, 'cardIds': cardIds};

  static VisualTaskType? fromMap(Object? raw, {Set<String>? knownIds, String? fallbackId}) {
    if (raw is! Map) return null;
    final title = _str(raw['title'] ?? raw['name'] ?? raw['typ']);
    if (title.isEmpty) return null;
    final ids = raw['cardIds'] ?? raw['cards'] ?? raw['examples'];
    return VisualTaskType(
      id: _str(raw['id']).isNotEmpty ? _str(raw['id']) : (fallbackId ?? title),
      title: title,
      description: _str(raw['description'] ?? raw['beschreibung']),
      cardIds: [
        if (ids is List)
          for (final i in ids)
            if (_str(i).isNotEmpty && (knownIds == null || knownIds.contains(_str(i)))) _str(i),
      ],
    );
  }
}

/// Die erkannten Typen eines Fachs (lokal gespeichert, jederzeit neu erkennbar).
class VisualTaskCatalog {
  const VisualTaskCatalog({required this.moduleId, required this.types, this.cardCount = 0, required this.updatedAt});

  final String moduleId;
  final List<VisualTaskType> types;

  /// Wie viele Karten das Fach beim Erkennen hatte – sind es deutlich mehr,
  /// lohnt sich ein neues Erkennen.
  final int cardCount;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
    'moduleId': moduleId,
    'types': [for (final t in types) t.toMap()],
    'cardCount': cardCount,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static VisualTaskCatalog? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final moduleId = _str(raw['moduleId']);
    if (moduleId.isEmpty) return null;
    return VisualTaskCatalog(
      moduleId: moduleId,
      types: [
        if (raw['types'] is List)
          for (final t in raw['types'] as List) ?VisualTaskType.fromMap(t),
      ],
      cardCount: (raw['cardCount'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(_str(raw['updatedAt'])) ?? DateTime.now(),
    );
  }
}

/// Schwierigkeit einer gestellten Aufgabe.
enum VisualTaskLevel {
  easy('Leicht', 'eine Grundaufgabe mit wenigen Schritten und glatten Zahlen'),
  medium('Mittel', 'eine typische Übungsaufgabe wie in den Beispielen'),
  hard('Schwer', 'eine Klausuraufgabe mit mehreren Teilschritten, Fallstricken oder Kombination mit anderem Stoff');

  const VisualTaskLevel(this.label, this.meaning);

  final String label;

  /// Was die KI unter dieser Stufe verstehen soll.
  final String meaning;
}
