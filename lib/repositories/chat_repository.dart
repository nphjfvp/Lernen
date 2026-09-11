import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/chat_message.dart';
import '../services/database_service.dart';

/// Persistierter Gesprächsverlauf des Frage-Chats, pro Fach getrennt.
class ChatRepository extends ChangeNotifier {
  final Map<String, List<ChatMessage>> _byModule = {};

  List<ChatMessage> forModule(String moduleId) =>
      List.unmodifiable(_byModule[moduleId] ?? const []);

  Future<void> loadForModule(String moduleId) async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.chatMessages.find(
      db,
      finder: Finder(
        filter: Filter.equals('moduleId', moduleId),
        sortOrders: [SortOrder('createdAt')],
      ),
    );
    _byModule[moduleId] = records.map((r) => ChatMessage.fromMap(r.value)).toList();
    notifyListeners();
  }

  Future<void> save(ChatMessage message) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.chatMessages.record(message.id).put(db, message.toMap());
    await loadForModule(message.moduleId);
  }

  Future<void> clearModule(String moduleId) async {
    final db = await DatabaseService.instance.database;
    for (final message in _byModule[moduleId] ?? const <ChatMessage>[]) {
      await DatabaseService.chatMessages.record(message.id).delete(db);
    }
    await loadForModule(moduleId);
  }
}
