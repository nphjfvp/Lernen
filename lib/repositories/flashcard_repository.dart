import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/flashcard.dart';
import '../services/database_service.dart';

class FlashcardRepository extends ChangeNotifier {
  final Map<String, List<Flashcard>> _byModule = {};

  List<Flashcard> forModule(String moduleId) =>
      List.unmodifiable(_byModule[moduleId] ?? const []);

  Future<void> loadForModule(String moduleId) async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.flashcards.find(
      db,
      finder: Finder(filter: Filter.equals('moduleId', moduleId)),
    );
    _byModule[moduleId] =
        records.map((r) => Flashcard.fromMap(r.value)).toList();
    notifyListeners();
  }

  /// Lädt ALLE Karteikarten (für den modulübergreifenden Daily-Quiz-Scheduler).
  Future<List<Flashcard>> loadAll() async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.flashcards.find(db);
    return records.map((r) => Flashcard.fromMap(r.value)).toList();
  }

  Future<void> saveAll(List<Flashcard> cards) async {
    if (cards.isEmpty) return;
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) async {
      for (final c in cards) {
        await DatabaseService.flashcards.record(c.id).put(txn, c.toMap());
      }
    });
    await loadForModule(cards.first.moduleId);
  }

  Future<void> update(Flashcard card) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.flashcards.record(card.id).put(db, card.toMap());
    if (_byModule.containsKey(card.moduleId)) {
      await loadForModule(card.moduleId);
    }
  }

  Future<void> delete(String id, String moduleId) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.flashcards.record(id).delete(db);
    await loadForModule(moduleId);
  }

  /// Löscht mehrere Karten in EINER Transaktion (statt [delete] wiederholt
  /// aufzurufen, was pro Karte einen eigenen Modul-Reload auslösen würde) –
  /// Grundlage für die Mehrfachauswahl in FlashcardListScreen.
  Future<void> deleteMany(List<String> ids, String moduleId) async {
    if (ids.isEmpty) return;
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await DatabaseService.flashcards.record(id).delete(txn);
      }
    });
    await loadForModule(moduleId);
  }
}
