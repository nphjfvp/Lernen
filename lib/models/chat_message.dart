enum ChatRole { user, assistant }

ChatRole chatRoleFromString(String value) =>
    ChatRole.values.firstWhere((e) => e.name == value);

/// Eine Nachricht im Frage-Chat eines Fachs (siehe ModuleChatScreen). Wird
/// persistiert, damit der Gesprächsverlauf einen App-Neustart übersteht.
class ChatMessage {
  final String id;
  final String moduleId;
  final ChatRole role;
  final String content;
  final DateTime createdAt;

  /// Nur für Assistant-Nachrichten gesetzt: die Dateinamen der Materialien,
  /// die als Kontext für diese Antwort herangezogen wurden – `null`, wenn
  /// der Material-Kontext-Schalter ausgeschaltet war (nicht anwendbar),
  /// eine LEERE Liste, wenn er an war, aber kein Material als relevant
  /// ausgewählt wurde. Macht sichtbar, ob/welches Material genutzt wurde,
  /// statt einer stillen Blackbox-Entscheidung (siehe ModuleChatScreen).
  final List<String>? sourceFileNames;

  const ChatMessage({
    required this.id,
    required this.moduleId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.sourceFileNames,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'sourceFileNames': sourceFileNames,
      };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        role: chatRoleFromString(map['role'] as String),
        content: map['content'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        sourceFileNames: (map['sourceFileNames'] as List?)?.map((e) => e.toString()).toList(),
      );
}
