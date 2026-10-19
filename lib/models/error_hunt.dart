/// Eine Aussage der Fehlerjagd (Wahr/Falsch-Spiel, siehe ErrorHuntScreen):
/// zu genau einer Karte, richtig oder mit einem typischen Denkfehler.
class ErrorHuntStatement {
  const ErrorHuntStatement({required this.text, required this.isTrue, required this.explanation, this.cardId});

  final String text;
  final bool isTrue;

  /// Ein Satz: warum es stimmt bzw. was richtig wäre.
  final String explanation;

  /// Karte, zu der die Aussage gehört (null, wenn die KI eine unbekannte
  /// ID genannt hat).
  final String? cardId;

  /// Liest die KI-Antwort tolerant: `true`/`wahr`/`isTrue`/`correct` als
  /// Wahrheitswert (auch als Text), `card`/`cardId`/`id` als Karte – nur
  /// IDs aus [knownIds] zählen. Aussagen ohne Text oder Wahrheitswert fallen weg.
  static List<ErrorHuntStatement> listFrom(Object? raw, {required Set<String> knownIds}) {
    final list = raw is Map ? (raw['statements'] ?? raw['aussagen'] ?? raw['items']) : raw;
    if (list is! List) return const [];
    final result = <ErrorHuntStatement>[];
    for (final e in list) {
      if (e is! Map) continue;
      final text = (e['text'] ?? e['statement'] ?? e['aussage'] ?? '').toString().trim();
      final truth = _bool(e['true'] ?? e['isTrue'] ?? e['wahr'] ?? e['correct']);
      if (text.isEmpty || truth == null) continue;
      final card = (e['card'] ?? e['cardId'] ?? e['id'])?.toString().trim();
      result.add(
        ErrorHuntStatement(
          text: text,
          isTrue: truth,
          explanation: (e['explanation'] ?? e['erklaerung'] ?? e['erklärung'] ?? '').toString().trim(),
          cardId: card != null && knownIds.contains(card) ? card : null,
        ),
      );
    }
    return result;
  }

  static bool? _bool(Object? v) {
    if (v is bool) return v;
    final s = v?.toString().trim().toLowerCase();
    if (s == 'true' || s == 'wahr' || s == 'ja' || s == 'richtig') return true;
    if (s == 'false' || s == 'falsch' || s == 'nein') return false;
    return null;
  }
}
