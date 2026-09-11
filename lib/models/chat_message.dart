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

  const ChatMessage({
    required this.id,
    required this.moduleId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        role: chatRoleFromString(map['role'] as String),
        content: map['content'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
