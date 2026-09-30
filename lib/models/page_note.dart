/// Eine Notiz zu einer Seite eines Materials – z.B. eine gespeicherte Antwort
/// der KI aus dem Frage-Panel des PDF-Viewers. Gehört zur PDF-Seite [page]
/// (1-basiert) und reist mit dem Material (Sync, Fach-Export).
class PageNote {
  const PageNote({
    required this.id,
    required this.page,
    required this.text,
    this.question = '',
    required this.createdAt,
  });

  final String id;
  final int page;

  /// Die Frage, auf die [text] die Antwort war (leer bei einer freien Notiz).
  final String question;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'page': page,
        'question': question,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PageNote.fromMap(Map<String, dynamic> map) => PageNote(
        id: (map['id'] ?? '').toString(),
        page: (map['page'] as num?)?.toInt() ?? 1,
        question: (map['question'] ?? '').toString(),
        text: (map['text'] ?? '').toString(),
        createdAt: DateTime.tryParse('${map['createdAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}
