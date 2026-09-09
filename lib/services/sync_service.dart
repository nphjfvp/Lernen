import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sembast/sembast.dart' hide FieldValue;

import '../models/concept.dart';
import '../models/flashcard.dart';
import '../models/material_item.dart';
import '../models/module.dart';
import '../models/summary.dart';
import '../services/database_service.dart';

class SyncException implements Exception {
  final String message;
  SyncException(this.message);
  @override
  String toString() => message;
}

/// Sync-Code-basierter Cloud-Sync (kein Account nötig) über Firestore –
/// analog zur Vorgänger-App. Der Code funktioniert wie ein Passwort: wer
/// ihn kennt, kann die Daten unter diesem Code lesen/überschreiben.
///
/// Setzt voraus, dass Firebase in main.dart erfolgreich initialisiert wurde
/// (eigenes Firebase-Projekt via `flutterfire configure`, siehe README).
/// Ist Firebase nicht konfiguriert, bleibt die App voll offline nutzbar –
/// [isAvailable] meldet das der UI, die den Sync-Bereich dann ausblendet.
class SyncService {
  bool get isAvailable => Firebase.apps.isNotEmpty;

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('sync_codes');

  Future<void> push(String syncCode) async {
    if (!isAvailable) {
      throw SyncException('Cloud-Sync ist nicht konfiguriert (kein Firebase-Projekt verbunden).');
    }
    final db = await DatabaseService.instance.database;

    final modules = (await DatabaseService.modules.find(db)).map((r) => r.value).toList();
    final materials = (await DatabaseService.materials.find(db)).map((r) => r.value).toList();
    final summaries = (await DatabaseService.summaries.find(db)).map((r) => r.value).toList();
    final concepts = (await DatabaseService.concepts.find(db)).map((r) => r.value).toList();
    final flashcards = (await DatabaseService.flashcards.find(db)).map((r) => r.value).toList();

    await _collection.doc(syncCode).set({
      'updatedAt': FieldValue.serverTimestamp(),
      'modules': modules,
      'materials': materials,
      'summaries': summaries,
      'concepts': concepts,
      'flashcards': flashcards,
    });
  }

  /// Lädt die Cloud-Daten herunter und ERSETZT die lokalen Daten vollständig.
  /// Die UI muss vorher eine Bestätigung einholen (siehe SettingsScreen).
  Future<void> pull(String syncCode) async {
    if (!isAvailable) {
      throw SyncException('Cloud-Sync ist nicht konfiguriert (kein Firebase-Projekt verbunden).');
    }
    final doc = await _collection.doc(syncCode).get();
    if (!doc.exists) {
      throw SyncException('Für diesen Sync-Code liegen noch keine Cloud-Daten vor.');
    }
    final data = doc.data()!;
    final db = await DatabaseService.instance.database;

    await db.transaction((txn) async {
      await DatabaseService.modules.delete(txn);
      await DatabaseService.materials.delete(txn);
      await DatabaseService.summaries.delete(txn);
      await DatabaseService.concepts.delete(txn);
      await DatabaseService.flashcards.delete(txn);

      for (final m in (data['modules'] as List? ?? [])) {
        final module = Module.fromMap(Map<String, dynamic>.from(m as Map));
        await DatabaseService.modules.record(module.id).put(txn, module.toMap());
      }
      for (final m in (data['materials'] as List? ?? [])) {
        final item = MaterialItem.fromMap(Map<String, dynamic>.from(m as Map));
        await DatabaseService.materials.record(item.id).put(txn, item.toMap());
      }
      for (final m in (data['summaries'] as List? ?? [])) {
        final summary = Summary.fromMap(Map<String, dynamic>.from(m as Map));
        await DatabaseService.summaries.record(summary.id).put(txn, summary.toMap());
      }
      for (final m in (data['concepts'] as List? ?? [])) {
        final concept = Concept.fromMap(Map<String, dynamic>.from(m as Map));
        await DatabaseService.concepts.record(concept.id).put(txn, concept.toMap());
      }
      for (final m in (data['flashcards'] as List? ?? [])) {
        final card = Flashcard.fromMap(Map<String, dynamic>.from(m as Map));
        await DatabaseService.flashcards.record(card.id).put(txn, card.toMap());
      }
    });
  }
}
