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

  /// Lädt ALLE Karteikarten bestehender Fächer (für den modulübergreifenden
  /// Daily-Quiz-Scheduler, Statistik, Fehlertagebuch, Sprint). Verwaiste
  /// Karten ohne Fach – z.B. früher beim Beantworten wieder angelegte,
  /// eigentlich gelöschte Karten – bleiben außen vor: sie ließen sich
  /// nirgends anzeigen oder löschen.
  Future<List<Flashcard>> loadAll() async {
    final db = await DatabaseService.instance.database;
    final moduleIds = (await DatabaseService.modules.findKeys(db)).toSet();
    final records = await DatabaseService.flashcards.find(db);
    return records
        .map((r) => Flashcard.fromMap(r.value))
        .where((c) => moduleIds.contains(c.moduleId))
        .toList();
  }

  /// Aktueller gespeicherter Stand einer Karte, oder null, wenn gelöscht.
  Future<Flashcard?> loadById(String id) async {
    final db = await DatabaseService.instance.database;
    final record = await DatabaseService.flashcards.record(id).get(db);
    return record == null ? null : Flashcard.fromMap(record);
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

  /// Schreibt eine BESTEHENDE Karte zurück. Wurde sie inzwischen gelöscht –
  /// in der Kartenliste oder mit ihrem Fach, während sie noch in einer
  /// laufenden Lernrunde stand –, passiert nichts: sonst entstünde sie beim
  /// Beantworten als "Zombie" neu, womöglich ohne Fach. Liefert, ob
  /// geschrieben wurde.
  Future<bool> update(Flashcard card) async {
    final db = await DatabaseService.instance.database;
    final written = await db.transaction((txn) async {
      final ref = DatabaseService.flashcards.record(card.id);
      if (await ref.get(txn) == null) return false;
      await ref.put(txn, card.toMap());
      return true;
    });
    if (written && _byModule.containsKey(card.moduleId)) {
      await loadForModule(card.moduleId);
    }
    return written;
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
