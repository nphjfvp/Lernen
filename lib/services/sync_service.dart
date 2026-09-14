import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sembast/sembast.dart' hide FieldValue;

import '../models/app_settings.dart';
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

/// Merged den BYOK-Teil (API-Key + Modellwahl) aus einem Sync-Dokument in
/// [current] ein. Pure Logik (kein DB-/Firestore-Zugriff), damit die Regel
/// "ein leerer/fehlender Cloud-Wert löscht nie einen lokal vorhandenen
/// Wert" isoliert testbar ist – ein `pull` von einem Gerät, das noch nie
/// einen API-Key gesetzt hat, soll den lokalen Key nicht versehentlich
/// wegräumen.
AppSettings mergeAiSettings(AppSettings current, Map<String, dynamic>? synced) {
  if (synced == null) return current;
  return current.copyWith(
    openRouterApiKey: synced['openRouterApiKey'] as String?,
    questionModelId: synced['questionModelId'] as String?,
    visionModelId: synced['visionModelId'] as String?,
    crosscheckModelId: synced['crosscheckModelId'] as String?,
  );
}

/// Cloud-Sync über Firestore, auf zwei Wegen erreichbar:
///  - Konto-gebunden (empfohlen): Daten liegen unter `users/{uid}`, per
///    Firestore-Regel exakt auf `request.auth.uid == uid` beschränkt. Kein
///    Code nötig – auf jedem Gerät mit demselben Firebase-Konto anmelden,
///    dann synchronisieren.
///  - Sync-Code (Fallback ohne Konto, wie beim Vorgänger): Daten liegen
///    unter `sync_codes/{code}`, der Code wirkt wie ein Passwort.
///
/// Beide Wege übertragen dieselben Inhalte: Fächer, Materialien,
/// Zusammenfassungen, Konzepte, Karteikarten UND den BYOK-Teil der
/// Einstellungen (API-Key + Modellwahl). Das ist beim Konto-Weg
/// unproblematisch (nur der authentifizierte Besitzer hat Zugriff); beim
/// Code-Weg ist es dasselbe Vertrauensmodell wie der Rest der Daten auch
/// schon hat. Geräte-lokale Dinge wie die Lernerinnerungs-Uhrzeit werden
/// bewusst NICHT übertragen.
///
/// Setzt voraus, dass Firebase in main.dart erfolgreich initialisiert wurde.
/// Ist Firebase nicht konfiguriert, bleibt die App voll offline nutzbar –
/// [isAvailable] meldet das der UI, die den Sync-Bereich dann ausblendet.
class SyncService {
  bool get isAvailable => Firebase.apps.isNotEmpty;

  static const _settingsKey = 'app_settings';

  DocumentReference<Map<String, dynamic>> _codeDoc(String code) =>
      FirebaseFirestore.instance.collection('sync_codes').doc(code);

  DocumentReference<Map<String, dynamic>> _accountDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  Future<void> pushToCode(String syncCode) => _push(_codeDoc(syncCode));
  Future<void> pushToAccount(String uid) => _push(_accountDoc(uid));

  Future<void> pullFromCode(String syncCode) => _pull(_codeDoc(syncCode));
  Future<void> pullFromAccount(String uid) => _pull(_accountDoc(uid));

  Future<void> _push(DocumentReference<Map<String, dynamic>> doc) async {
    if (!isAvailable) {
      throw SyncException('Cloud-Sync ist nicht konfiguriert (kein Firebase-Projekt verbunden).');
    }
    final db = await DatabaseService.instance.database;

    final modules = (await DatabaseService.modules.find(db)).map((r) => r.value).toList();
    final materials = (await DatabaseService.materials.find(db)).map((r) => r.value).toList();
    final summaries = (await DatabaseService.summaries.find(db)).map((r) => r.value).toList();
    final concepts = (await DatabaseService.concepts.find(db)).map((r) => r.value).toList();
    final flashcards = (await DatabaseService.flashcards.find(db)).map((r) => r.value).toList();

    await doc.set({
      'updatedAt': FieldValue.serverTimestamp(),
      'modules': modules,
      'materials': materials,
      'summaries': summaries,
      'concepts': concepts,
      'flashcards': flashcards,
      'aiSettings': await _readAiSettings(db),
    });
  }

  /// Lädt die Cloud-Daten herunter und ERSETZT die lokalen Fächer/
  /// Materialien/Konzepte/Karteikarten vollständig. Die UI muss vorher eine
  /// Bestätigung einholen (siehe SettingsScreen). Der BYOK-Teil der
  /// Einstellungen wird nur übernommen, wenn er in der Cloud gesetzt ist –
  /// ein leerer/fehlender Cloud-API-Key löscht nie einen lokal
  /// vorhandenen Key (siehe [_writeAiSettings]).
  Future<void> _pull(DocumentReference<Map<String, dynamic>> doc) async {
    if (!isAvailable) {
      throw SyncException('Cloud-Sync ist nicht konfiguriert (kein Firebase-Projekt verbunden).');
    }
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      throw SyncException('Für dieses Ziel liegen noch keine Cloud-Daten vor.');
    }
    final data = snapshot.data()!;
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

      await _writeAiSettings(txn, data['aiSettings'] as Map<String, dynamic>?);
    });
  }

  Future<Map<String, dynamic>> _readAiSettings(DatabaseClient db) async {
    final record = await DatabaseService.settings.record(_settingsKey).get(db);
    final settings = record == null ? const AppSettings() : AppSettings.fromMap(record);
    return {
      'openRouterApiKey': settings.openRouterApiKey,
      'questionModelId': settings.questionModelId,
      'visionModelId': settings.visionModelId,
      'crosscheckModelId': settings.crosscheckModelId,
    };
  }

  Future<void> _writeAiSettings(DatabaseClient db, Map<String, dynamic>? synced) async {
    if (synced == null) return;
    final record = await DatabaseService.settings.record(_settingsKey).get(db);
    final current = record == null ? const AppSettings() : AppSettings.fromMap(record);
    final updated = mergeAiSettings(current, synced);
    await DatabaseService.settings.record(_settingsKey).put(db, updated.toMap());
  }
}
