import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sembast/sembast.dart' hide FieldValue;

import '../models/app_settings.dart';
import '../models/concept.dart';
import '../models/flashcard.dart';
import '../models/lecture_unit.dart';
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
/// Beide Wege übertragen Fächer, Einheiten, Materialien, Zusammenfassungen,
/// Konzepte und Karteikarten. Beim BYOK-Teil der Einstellungen (API-Key + Modellwahl)
/// unterscheiden sie sich bewusst: der Konto-Weg überträgt auch den API-Key
/// (nur der authentifizierte Besitzer hat Zugriff); der Code-Weg überträgt
/// NUR die Modellwahl, NIE den Key selbst – ein frei getippter Sync-Code hat
/// keine Mindestkomplexität/Ratenbegrenzung und darf deshalb kein
/// potenziell kostenpflichtiges API-Zugangsmittel offenlegen können (siehe
/// [_push]/[pushToCode]). Geräte-lokale Dinge wie die Lernerinnerungs-Uhrzeit
/// werden bewusst NICHT übertragen.
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

  /// [includeApiKey] ist bei Konto-Sync true (der Weg ist per Firestore-Regel
  /// exakt auf den authentifizierten Besitzer beschränkt), beim Sync-Code
  /// bewusst false: der Code selbst hat keine Mindestkomplexität und keine
  /// Ratenbegrenzung außer Firebases Default – ein erratener/schwacher Code
  /// darf kein potenziell kostenpflichtiges API-Zugangsmittel offenlegen.
  /// Modellwahl (nicht geheim) wird trotzdem weiter übertragen.
  Future<void> pushToCode(String syncCode) => _push(_codeDoc(syncCode), includeApiKey: false);
  Future<void> pushToAccount(String uid) => _push(_accountDoc(uid), includeApiKey: true);

  Future<void> pullFromCode(String syncCode) => _pull(_codeDoc(syncCode));
  Future<void> pullFromAccount(String uid) => _pull(_accountDoc(uid));

  /// Anzahl lokal vorhandener Datensätze je Kategorie – Grundlage für die
  /// Bestätigung vor einem Pull (siehe SettingsScreen._confirmOverwrite):
  /// [_pull] ersetzt diese Daten vollständig statt sie zu mergen (kein
  /// Abgleich nach Änderungszeitpunkt), daher soll der Nutzer VOR dem
  /// Bestätigen sehen, was konkret wegfällt, statt nur pauschal gewarnt zu
  /// werden.
  Future<({int modules, int materials, int concepts, int flashcards})> localCounts() async {
    final db = await DatabaseService.instance.database;
    return (
      modules: await DatabaseService.modules.count(db),
      materials: await DatabaseService.materials.count(db),
      concepts: await DatabaseService.concepts.count(db),
      flashcards: await DatabaseService.flashcards.count(db),
    );
  }

  Future<void> _push(DocumentReference<Map<String, dynamic>> doc, {required bool includeApiKey}) async {
    if (!isAvailable) {
      throw SyncException('Cloud-Sync ist nicht konfiguriert (kein Firebase-Projekt verbunden).');
    }
    final db = await DatabaseService.instance.database;

    final modules = (await DatabaseService.modules.find(db)).map((r) => r.value).toList();
    final materials = (await DatabaseService.materials.find(db)).map((r) => r.value).toList();
    final summaries = (await DatabaseService.summaries.find(db)).map((r) => r.value).toList();
    final concepts = (await DatabaseService.concepts.find(db)).map((r) => r.value).toList();
    final flashcards = (await DatabaseService.flashcards.find(db)).map((r) => r.value).toList();
    final lectureUnits = (await DatabaseService.lectureUnits.find(db)).map((r) => r.value).toList();

    await doc.set({
      'updatedAt': FieldValue.serverTimestamp(),
      'modules': modules,
      'materials': materials,
      'summaries': summaries,
      'concepts': concepts,
      'flashcards': flashcards,
      'lectureUnits': lectureUnits,
      'aiSettings': await _readAiSettings(db, includeApiKey: includeApiKey),
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
      // Ältere Cloud-Stände (vor Einheiten-Sync) enthalten den Schlüssel
      // nicht – dann die lokalen Einheiten behalten statt sie ersatzlos zu
      // löschen.
      if (data.containsKey('lectureUnits')) await DatabaseService.lectureUnits.delete(txn);

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
      // Ohne Einheiten würden Materialien/Karten auf dem Zielgerät auf nicht
      // existierende unitIds zeigen: Materialien unsichtbar im Modul-Detail,
      // Karten noch nicht behandelter Einheiten sofort im Daily Quiz.
      for (final u in (data['lectureUnits'] as List? ?? [])) {
        final unit = LectureUnit.fromMap(Map<String, dynamic>.from(u as Map));
        await DatabaseService.lectureUnits.record(unit.id).put(txn, unit.toMap());
      }

      await _writeAiSettings(txn, data['aiSettings'] as Map<String, dynamic>?);
    });
  }

  Future<Map<String, dynamic>> _readAiSettings(DatabaseClient db, {required bool includeApiKey}) async {
    final record = await DatabaseService.settings.record(_settingsKey).get(db);
    final settings = record == null ? const AppSettings() : AppSettings.fromMap(record);
    return {
      // Explizit null (nicht einfach weggelassen) statt des echten Keys, wenn
      // includeApiKey=false: überschreibt dabei auch einen eventuell VOR
      // diesem Fix in dieses Dokument gelangten Key beim nächsten Push.
      'openRouterApiKey': includeApiKey ? settings.openRouterApiKey : null,
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
