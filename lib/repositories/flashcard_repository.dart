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

  /// Alle gespeicherten Karten eines Fachs, ohne den Anzeige-Stand
  /// ([forModule]) anzufassen.
  Future<List<Flashcard>> loadModuleCards(String moduleId) async {
    final db = await DatabaseService.instance.database;
    final records = await DatabaseService.flashcards.find(
      db,
      finder: Finder(filter: Filter.equals('moduleId', moduleId)),
    );
    return records.map((r) => Flashcard.fromMap(r.value)).toList();
  }

  /// Wie [update] für mehrere Karten in EINER Transaktion – inzwischen
  /// gelöschte bleiben weg.
  Future<void> updateAll(List<Flashcard> cards) async {
    if (cards.isEmpty) return;
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) async {
      for (final card in cards) {
        final ref = DatabaseService.flashcards.record(card.id);
        if (await ref.get(txn) != null) await ref.put(txn, card.toMap());
      }
    });
    for (final moduleId in {for (final c in cards) c.moduleId}) {
      if (_byModule.containsKey(moduleId)) await loadForModule(moduleId);
    }
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

  /// Lernhilfen am GESPEICHERTEN Stand nachtragen (gefundene Quellseite,
  /// erzeugte Lerneinheit) – so überschreibt das weder eine gleichzeitig
  /// gespeicherte Bewertung noch umgekehrt. Gelöschte Karten bleiben weg.
  Future<Flashcard?> updateStudyAids(String id, {String? sourceMaterialId, int? sourcePage, String? miniLesson}) async {
    final db = await DatabaseService.instance.database;
    final updated = await db.transaction((txn) async {
      final ref = DatabaseService.flashcards.record(id);
      final stored = await ref.get(txn);
      if (stored == null) return null;
      final card = Flashcard.fromMap(stored).copyWithStudyAids(
        sourceMaterialId: sourceMaterialId,
        sourcePage: sourcePage,
        miniLesson: miniLesson,
      );
      await ref.put(txn, card.toMap());
      return card;
    });
    if (updated != null && _byModule.containsKey(updated.moduleId)) {
      await loadForModule(updated.moduleId);
    }
    return updated;
  }

  /// Fundstellen der Erklärung im Skript am GESPEICHERTEN Stand ablegen
  /// (siehe Flashcard.scriptMaterialId): [locations] ordnet Karten-IDs
  /// (Material-ID oder null für "nichts gefunden", Seite) zu. Alles andere an
  /// der Karte – auch ein gleichzeitig verbuchter Lernstand – bleibt; gelöschte
  /// Karten bleiben weg. Gibt zurück, wie viele Karten geändert wurden.
  Future<int> updateScriptLocations(Map<String, ({String? materialId, int page})> locations) async {
    if (locations.isEmpty) return 0;
    final db = await DatabaseService.instance.database;
    final moduleIds = <String>{};
    final changed = await db.transaction((txn) async {
      var n = 0;
      for (final e in locations.entries) {
        final ref = DatabaseService.flashcards.record(e.key);
        final stored = await ref.get(txn);
        if (stored == null) continue;
        final card = Flashcard.fromMap(stored).copyWithScript(materialId: e.value.materialId, page: e.value.page);
        await ref.put(txn, card.toMap());
        moduleIds.add(card.moduleId);
        n++;
      }
      return n;
    });
    for (final id in moduleIds) {
      if (_byModule.containsKey(id)) await loadForModule(id);
    }
    return changed;
  }

  /// KI-Hilfestellungen am GESPEICHERTEN Stand ablegen (siehe
  /// Flashcard.aiHints) – nur, solange die Karte noch dieselbe Frage
  /// ([type]/[front]) zeigt; nach einem Stufenwechsel passen sie nicht mehr.
  Future<void> updateHints(String id, List<String> hints, {required QuestionType type, required String front}) async {
    final db = await DatabaseService.instance.database;
    final updated = await db.transaction((txn) async {
      final ref = DatabaseService.flashcards.record(id);
      final stored = await ref.get(txn);
      if (stored == null) return null;
      final card = Flashcard.fromMap(stored);
      if (card.type != type || card.front != front) return null;
      final withHints = card.copyWithHints(hints);
      await ref.put(txn, withHints.toMap());
      return withHints;
    });
    if (updated != null && _byModule.containsKey(updated.moduleId)) {
      await loadForModule(updated.moduleId);
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
