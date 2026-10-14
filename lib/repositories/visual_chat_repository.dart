import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/visual_chat.dart';
import '../services/database_service.dart';

/// Gespräche des visuellen Chats – liest immer frisch aus der Datenbank.
class VisualChatRepository extends ChangeNotifier {
  /// [openDatabase]: nur für Tests.
  VisualChatRepository({Future<DatabaseClient> Function()? openDatabase})
    : _open = openDatabase ?? (() => DatabaseService.instance.database);

  final Future<DatabaseClient> Function() _open;

  /// Die Gespräche eines Fachs, zuletzt benutzte zuerst.
  Future<List<VisualChat>> forModule(String moduleId) async {
    final db = await _open();
    final records = await DatabaseService.visualChats.find(
      db,
      finder: Finder(filter: Filter.equals('moduleId', moduleId)),
    );
    final chats = [for (final r in records) ?VisualChat.fromMap(r.value)];
    chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return chats;
  }

  Future<void> save(VisualChat chat) async {
    final db = await _open();
    await DatabaseService.visualChats.record(chat.id).put(db, chat.toMap());
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final db = await _open();
    await DatabaseService.visualChats.record(id).delete(db);
    notifyListeners();
  }
}
