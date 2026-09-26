import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' hide Filter;
import 'package:firebase_core/firebase_core.dart';
import 'package:sembast/sembast.dart' hide FieldValue;
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/concept.dart';
import '../models/flashcard.dart';
import '../models/lecture_unit.dart';
import '../models/material_item.dart';
import '../models/module.dart';
import '../models/pdf_storage_config.dart';
import '../models/summary.dart';
import '../repositories/mock_exam_repository.dart';
import '../services/database_service.dart';
import 'sync_codec.dart';

class SyncException implements Exception {
  final String message;
  SyncException(this.message);
  @override
  String toString() => message;
}

/// Upload abgebrochen, weil der Cloud-Stand nicht überschrieben werden soll
/// (siehe `abortIf` in [SyncService.push]).
class SyncConflictException extends SyncException {
  SyncConflictException(super.message);
}

/// Merged den BYOK-Teil (API-Key + Modellwahl) aus einem Sync-Dokument in
/// [current] ein. Pure Logik (kein DB-/Firestore-Zugriff), damit die Regel
/// "ein leerer/fehlender Cloud-Wert löscht nie einen lokal vorhandenen
/// Wert" isoliert testbar ist – ein `pull` von einem Gerät, das noch nie
/// einen API-Key gesetzt hat, soll den lokalen Key nicht versehentlich
/// wegräumen.
AppSettings mergeAiSettings(AppSettings current, Map<String, dynamic>? synced) {
  if (synced == null) return current;
  final storage = synced['pdfStorage'] is Map
      ? PdfStorageConfig.fromMap(Map<String, dynamic>.from(synced['pdfStorage'] as Map))
      : null;
  return current.copyWith(
    openRouterApiKey: synced['openRouterApiKey'] as String?,
    questionModelId: synced['questionModelId'] as String?,
    visionModelId: synced['visionModelId'] as String?,
    crosscheckModelId: synced['crosscheckModelId'] as String?,
    // Wie beim API-Key: ein leerer Cloud-Stand löscht nie lokale Zugangsdaten.
    pdfStorage: (storage?.isConfigured ?? false) ? storage : null,
  );
}

/// Entfernt beim Download über einen Sync-Code den API-Key aus den
/// übernommenen KI-Einstellungen (siehe SyncService.pull) – rein, testbar.
Map<String, dynamic> syncedAiSettingsForPull(Map<String, dynamic> synced, {required bool acceptApiKey}) {
  if (acceptApiKey) return synced;
  return {...synced, 'openRouterApiKey': null, 'pdfStorage': null};
}

/// Bricht ab, wenn der Cloud-Stand von einer NEUEREN App-Version stammt: ihn
/// als "alten Stand" zu lesen hieße, nichts zu finden, lokal aber alles zu
/// löschen.
void checkCloudFormat(Map<String, dynamic> root) {
  final format = (root['format'] as num?)?.toInt();
  if (format != null && format > SyncService.syncFormat) {
    throw SyncException('Der Cloud-Stand stammt von einer neueren App-Version – bitte diese App erst aktualisieren.');
  }
}

/// Ohne Fächerliste ist ein Download kein brauchbarer Stand – dann lieber
/// abbrechen, als die lokalen Daten durch nichts zu ersetzen.
void checkUsablePayload(Map<String, dynamic> data) {
  if (data['modules'] is! List) {
    throw SyncException('Der Cloud-Stand ist unvollständig – lokale Daten bleiben unverändert.');
  }
}

/// Wohin synchronisiert wird: an ein Firebase-Konto gebunden oder über
/// einen frei gewählten Sync-Code.
class SyncTarget {
  const SyncTarget.account(this.id) : isAccount = true;
  const SyncTarget.code(this.id) : isAccount = false;

  /// Firebase-UID bzw. Sync-Code.
  final String id;
  final bool isAccount;

  @override
  bool operator ==(Object other) => other is SyncTarget && other.id == id && other.isAccount == isAccount;

  @override
  int get hashCode => Object.hash(id, isAccount);
}

/// Kopfdaten des Cloud-Stands – wer ihn wann zuletzt hochgeladen hat.
/// Grundlage für den Schutz beim Auto-Sync (siehe AutoSyncService): hat
/// seit dem letzten eigenen Sync ein ANDERES Gerät hochgeladen, darf ein
/// automatischer Upload dessen Fortschritt nicht still überschreiben.
class CloudSyncMeta {
  const CloudSyncMeta({this.pushId, this.deviceId, this.updatedAt});

  final String? pushId;
  final String? deviceId;
  final DateTime? updatedAt;
}

/// Cloud-Sync über Firestore, auf zwei Wegen erreichbar:
///  - Konto-gebunden (empfohlen): Daten liegen unter `users/{uid}`, per
///    Firestore-Regel exakt auf `request.auth.uid == uid` beschränkt. Kein
///    Code nötig – auf jedem Gerät mit demselben Firebase-Konto anmelden,
///    dann synchronisieren.
///  - Sync-Code (Fallback ohne Konto, wie beim Vorgänger): Daten liegen
///    unter `sync_codes/{code}`, der Code wirkt wie ein Passwort.
///
/// Beide Wege übertragen Fächer, Einheiten, Materialien (ohne die PDF-Datei
/// selbst, siehe SyncCodec), Zusammenfassungen, Konzepte und Karteikarten.
/// Beim BYOK-Teil der Einstellungen (API-Key + Modellwahl) unterscheiden sie
/// sich bewusst: der Konto-Weg überträgt auch den API-Key (nur der
/// authentifizierte Besitzer hat Zugriff); der Code-Weg überträgt NUR die
/// Modellwahl, NIE den Key selbst – ein frei getippter Sync-Code hat keine
/// Mindestkomplexität/Ratenbegrenzung und darf deshalb kein potenziell
/// kostenpflichtiges API-Zugangsmittel offenlegen können. Geräte-lokale
/// Dinge wie die Lernerinnerungs-Uhrzeit werden bewusst NICHT übertragen.
///
/// Speicherformat (Version [syncFormat]): der Datenbestand wird komprimiert
/// (siehe SyncCodec). Passt er in ein Dokument, liegt er direkt im
/// Hauptdokument (`data`); sonst in Teilen unter `…/sync_parts/0..n-1` (braucht die aktuellen Firestore-Regeln, siehe firestore.rules).
/// Jeder Upload trägt eine eigene `pushId`, damit ein Download nie Teile
/// zweier verschiedener Uploads zusammensetzt. Ältere Cloud-Stände (alles
/// als Klartext in EINEM Dokument) werden weiterhin gelesen.
///
/// Setzt voraus, dass Firebase in main.dart erfolgreich initialisiert wurde.
/// Ist Firebase nicht konfiguriert, bleibt die App voll offline nutzbar –
/// [isAvailable] meldet das der UI, die den Sync-Bereich dann ausblendet.
class SyncService {
  bool get isAvailable => Firebase.apps.isNotEmpty;

  static const _settingsKey = 'app_settings';
  static const _partsCollection = 'sync_parts';
  static const syncFormat = 2;

  DocumentReference<Map<String, dynamic>> _doc(SyncTarget target) => FirebaseFirestore.instance
      .collection(target.isAccount ? 'users' : 'sync_codes')
      .doc(target.id);

  /// [SyncTarget.isAccount] entscheidet, ob der API-Key mitreist (siehe
  /// Klassenkommentar). Liefert die `pushId` des neuen Cloud-Stands.
  /// [abortIf] prüft die Kopfdaten des bisherigen Cloud-Stands (ohne extra
  /// Lesezugriff) und bricht bei true mit [SyncConflictException] ab, bevor
  /// etwas geschrieben wird – für den Auto-Sync.
  Future<String> push(
    SyncTarget target, {
    required String deviceId,
    bool Function(CloudSyncMeta? cloud)? abortIf,
  }) =>
      _push(_doc(target), includeApiKey: target.isAccount, deviceId: deviceId, abortIf: abortIf);

  /// Ersetzt die lokalen Daten durch den Cloud-Stand. Liefert dessen
  /// `pushId` (null bei einem Cloud-Stand im alten Format).
  /// Über einen Sync-Code wird ein dort hinterlegter API-Key NIE übernommen:
  /// wer den Code kennt oder errät, könnte sonst seinen eigenen Key
  /// unterschieben und die KI-Anfragen (mit deinem Lernmaterial) über sein
  /// Konto umleiten.
  Future<String?> pull(SyncTarget target) => _pull(_doc(target), acceptApiKey: target.isAccount);

  static CloudSyncMeta? _metaOf(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    final updatedAt = data['updatedAt'];
    return CloudSyncMeta(
      pushId: data['pushId'] as String?,
      deviceId: data['deviceId'] as String?,
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
    );
  }

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

  void _ensureAvailable() {
    if (!isAvailable) {
      throw SyncException('Cloud-Sync ist nicht konfiguriert (kein Firebase-Projekt verbunden).');
    }
  }

  Future<String> _push(
    DocumentReference<Map<String, dynamic>> doc, {
    required bool includeApiKey,
    required String deviceId,
    bool Function(CloudSyncMeta? cloud)? abortIf,
  }) async {
    _ensureAvailable();
    final previous = await doc.get();
    if (abortIf != null && abortIf(_metaOf(previous))) {
      throw SyncConflictException('Der Cloud-Stand stammt von einem anderen Gerät.');
    }
    final db = await DatabaseService.instance.database;

    final payload = {
      'modules': (await DatabaseService.modules.find(db)).map((r) => r.value).toList(),
      'materials': (await DatabaseService.materials.find(db))
          .map((r) => SyncCodec.stripDeviceLocalMaterialFields(r.value))
          .toList(),
      'summaries': (await DatabaseService.summaries.find(db)).map((r) => r.value).toList(),
      'concepts': (await DatabaseService.concepts.find(db)).map((r) => r.value).toList(),
      'flashcards': (await DatabaseService.flashcards.find(db)).map((r) => r.value).toList(),
      'lectureUnits': (await DatabaseService.lectureUnits.find(db)).map((r) => r.value).toList(),
    };
    final parts = SyncCodec.encode(payload);
    final pushId = const Uuid().v4();
    final previousPartCount = (previous.data()?['partCount'] as num?)?.toInt() ?? 0;

    final meta = <String, dynamic>{
      'format': syncFormat,
      'updatedAt': FieldValue.serverTimestamp(),
      'pushId': pushId,
      'deviceId': deviceId,
      'counts': {for (final e in payload.entries) e.key: e.value.length},
      'aiSettings': await _readAiSettings(db, includeApiKey: includeApiKey),
    };

    if (parts.length == 1) {
      await doc.set({...meta, 'partCount': 0, 'data': Blob(parts.single)});
    } else {
      try {
        for (var i = 0; i < parts.length; i++) {
          await doc.collection(_partsCollection).doc('$i').set({'pushId': pushId, 'data': Blob(parts[i])});
        }
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          throw SyncException(
            'Deine Daten sind zu groß für ein einzelnes Cloud-Dokument und werden '
            'jetzt in Teilen hochgeladen – dafür müssen die Firestore-Regeln einmal '
            'aktualisiert werden: Inhalt von firestore.rules in der Firebase-Konsole '
            '(Firestore → Regeln) einfügen und veröffentlichen.',
          );
        }
        rethrow;
      }
      // Erst NACH allen Teilen: ein gleichzeitiger Download sieht so entweder
      // den alten oder den vollständigen neuen Stand (siehe pushId-Prüfung).
      await doc.set({...meta, 'partCount': parts.length});
    }

    // Überzählige Teile eines früheren, größeren Stands entfernen.
    final firstStale = parts.length == 1 ? 0 : parts.length;
    for (var i = firstStale; i < previousPartCount; i++) {
      try {
        await doc.collection(_partsCollection).doc('$i').delete();
      } catch (_) {
        // Aufräumen ist optional – ein übrig gebliebener Teil wird nie
        // gelesen (partCount/pushId passen nicht).
      }
    }
    return pushId;
  }

  Future<Map<String, dynamic>> _readPayload(
    DocumentReference<Map<String, dynamic>> doc,
    Map<String, dynamic> root,
  ) async {
    checkCloudFormat(root);
    if (root['format'] != syncFormat) return root; // alter Stand: alles im Hauptdokument
    final partCount = (root['partCount'] as num?)?.toInt() ?? 0;
    if (partCount == 0) {
      final blob = root['data'];
      if (blob is! Blob) throw SyncException('Der Cloud-Stand ist unvollständig.');
      return SyncCodec.decode([blob.bytes]);
    }
    final snapshots =
        await Future.wait([for (var i = 0; i < partCount; i++) doc.collection(_partsCollection).doc('$i').get()]);
    final parts = <Uint8List>[];
    for (final snap in snapshots) {
      final data = snap.data();
      final blob = data?['data'];
      if (data == null || data['pushId'] != root['pushId'] || blob is! Blob) {
        throw SyncException(
            'Der Cloud-Stand wird gerade von einem anderen Gerät aktualisiert – bitte gleich nochmal versuchen.');
      }
      parts.add(blob.bytes);
    }
    return SyncCodec.decode(parts);
  }

  /// Lädt die Cloud-Daten herunter und ERSETZT die lokalen Fächer/
  /// Materialien/Konzepte/Karteikarten vollständig. Die UI muss vorher eine
  /// Bestätigung einholen (siehe SettingsScreen). Der BYOK-Teil der
  /// Einstellungen wird nur übernommen, wenn er in der Cloud gesetzt ist –
  /// ein leerer/fehlender Cloud-API-Key löscht nie einen lokal
  /// vorhandenen Key (siehe [_writeAiSettings]). Lokal vorhandene PDFs
  /// bleiben erhalten (siehe SyncCodec.withLocalMaterialFields).
  Future<String?> _pull(DocumentReference<Map<String, dynamic>> doc, {required bool acceptApiKey}) async {
    _ensureAvailable();
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      throw SyncException('Für dieses Ziel liegen noch keine Cloud-Daten vor.');
    }
    final root = snapshot.data()!;
    final data = await _readPayload(doc, root);
    checkUsablePayload(data);
    final db = await DatabaseService.instance.database;

    await db.transaction((txn) async {
      final localMaterials = {
        for (final r in await DatabaseService.materials.find(txn)) r.key: r.value,
      };
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
        final remote = Map<String, dynamic>.from(m as Map);
        final item = MaterialItem.fromMap(
            SyncCodec.withLocalMaterialFields(remote, localMaterials[remote['id']?.toString()]));
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

      // Lokale, nicht gesyncte Daten zu Fächern, die es nach dem Download
      // nicht mehr gibt, würden sonst verwaist liegen bleiben.
      final moduleIds = {
        for (final m in (data['modules'] as List? ?? [])) (m as Map)['id']?.toString() ?? '',
      };
      await DatabaseService.chatMessages.delete(
        txn,
        finder: Finder(filter: Filter.not(Filter.inList('moduleId', moduleIds.toList()))),
      );
      await MockExamRepository.retainModulesIn(txn, moduleIds);

      final aiSettings = root['aiSettings'] ?? data['aiSettings'];
      await _writeAiSettings(
        txn,
        aiSettings == null ? null : syncedAiSettingsForPull(Map<String, dynamic>.from(aiSettings as Map), acceptApiKey: acceptApiKey),
      );
    });
    return root['pushId'] as String?;
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
      // Zugangsdaten zum eigenen PDF-Speicher sind geheim wie der API-Key.
      'pdfStorage': includeApiKey ? settings.pdfStorage.toMap() : null,
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
