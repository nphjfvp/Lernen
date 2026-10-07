import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' hide Filter;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:sembast/sembast.dart' hide FieldValue;
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/concept.dart';
import '../models/daily_session_state.dart';
import '../models/flashcard.dart';
import '../models/lab_experiment.dart';
import '../models/lecture_unit.dart';
import '../models/mastery_snapshot.dart';
import '../models/material_item.dart';
import '../models/module.dart';
import '../models/pdf_storage_config.dart';
import '../models/summary.dart';
import '../models/unsupported_task.dart';
import '../repositories/daily_session_repository.dart';
import '../repositories/mock_exam_repository.dart';
import '../repositories/study_log_repository.dart';
import '../services/database_service.dart';
import 'mock_exam_service.dart';
import 'sync_backup_service.dart';
import 'sync_base_store.dart';
import 'sync_cloud_history.dart';
import 'sync_codec.dart';
import 'sync_diagnostics.dart';
import 'sync_merge.dart';
import 'sync_merge_apply.dart';

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

/// Die Einstellungen, die mit dem Lernstand in die Cloud reisen: KI-Key und
/// Modellwahl, Zugangsdaten zum eigenen PDF-Speicher sowie Vorlieben, die
/// auf jedem Gerät gleich sein sollen. Geheimes ([includeSecrets] = false,
/// Sync-Code-Weg) wird als `null` geschrieben, nicht weggelassen – das
/// überschreibt auch einen früher dort gelandeten Wert. Rein geräte-lokales
/// (Erinnerung, Auto-Sync-Schalter, Gerätekennung) bleibt bewusst draußen.
/// Rein, damit testbar; dient auch als "hat sich etwas geändert?"-Vergleich
/// für den Auto-Sync.
Map<String, dynamic> syncedSettingsOf(AppSettings settings, {required bool includeSecrets}) => {
      'openRouterApiKey': includeSecrets ? settings.openRouterApiKey : null,
      'questionModelId': settings.questionModelId,
      'visionModelId': settings.visionModelId,
      'crosscheckModelId': settings.crosscheckModelId,
      // Zugangsdaten zum eigenen PDF-Speicher sind geheim wie der API-Key.
      'pdfStorage': includeSecrets ? settings.pdfStorage.toMap() : null,
      'chunkGranularity': settings.chunkGranularity.name,
      'rollingContextEnabled': settings.rollingContextEnabled,
      'checkpointQuizPageInterval': settings.checkpointQuizPageInterval,
      'bestSprintScore': settings.bestSprintScore,
      'themeSkin': settings.themeSkin,
      'themeModePreference': settings.themeModePreference,
      'pageQuestionTierTypes': settings.pageQuestionTierTypes,
      'favoriteModelIds': settings.favoriteModelIds,
      // Leer heißt "wie das Fragen-Modell" – als '' statt null, damit ein
      // älterer Stand (Feld fehlt) von einer bewussten Wahl unterscheidbar bleibt.
      'helpModelId': settings.helpModelId ?? '',
    };

/// Merged die gesyncten Einstellungen (siehe [syncedSettingsOf]) in
/// [current] ein. Pure Logik (kein DB-/Firestore-Zugriff), damit die Regel
/// "ein leerer/fehlender Cloud-Wert löscht nie einen lokal vorhandenen
/// Wert" isoliert testbar ist – ein `pull` von einem Gerät, das noch nie
/// einen API-Key gesetzt hat, soll den lokalen Key nicht versehentlich
/// wegräumen. Fehlende Felder (ältere Cloud-Stände) lassen den lokalen Wert
/// stehen; der Sprint-Rekord gilt geräteübergreifend (der höhere zählt).
AppSettings mergeAiSettings(AppSettings current, Map<String, dynamic>? synced) {
  if (synced == null) return current;
  final storage = synced['pdfStorage'] is Map
      ? PdfStorageConfig.fromMap(Map<String, dynamic>.from(synced['pdfStorage'] as Map))
      : null;
  final apiKey = (synced['openRouterApiKey'] as String?)?.trim();
  final granularity = synced['chunkGranularity'];
  final interval = (synced['checkpointQuizPageInterval'] as num?)?.toInt();
  final bestSprint = (synced['bestSprintScore'] as num?)?.toInt() ?? 0;
  return current.copyWith(
    openRouterApiKey: apiKey == null || apiKey.isEmpty ? null : apiKey,
    questionModelId: synced['questionModelId'] as String?,
    visionModelId: synced['visionModelId'] as String?,
    crosscheckModelId: synced['crosscheckModelId'] as String?,
    // Wie beim API-Key: ein leerer Cloud-Stand löscht nie lokale Zugangsdaten.
    pdfStorage: (storage?.isConfigured ?? false) ? storage : null,
    chunkGranularity: ChunkGranularity.values.where((g) => g.name == granularity).firstOrNull,
    rollingContextEnabled: synced['rollingContextEnabled'] as bool?,
    checkpointQuizPageInterval: interval != null && interval > 0 ? interval : null,
    bestSprintScore: bestSprint > current.bestSprintScore ? bestSprint : null,
    themeSkin: (synced['themeSkin'] as String?)?.trim().isNotEmpty == true ? synced['themeSkin'] as String : null,
    themeModePreference: (synced['themeModePreference'] as String?)?.trim().isNotEmpty == true
        ? synced['themeModePreference'] as String
        : null,
    // Fehlt das Feld (älterer Cloud-Stand), bleibt der lokale Wert; eine
    // vorhandene, auch leere Angabe ist eine bewusste Einstellung.
    pageQuestionTierTypes: AppSettings.parseTierTypes(synced['pageQuestionTierTypes']),
    favoriteModelIds: AppSettings.parseModelIds(synced['favoriteModelIds']),
    // Fehlt das Feld (älterer Stand), bleibt der lokale Wert; '' = wie das Fragen-Modell.
    helpModelId: (synced['helpModelId'] as String?)?.trim().isNotEmpty == true ? synced['helpModelId'] as String : null,
    clearHelpModel: synced['helpModelId'] is String && (synced['helpModelId'] as String).trim().isEmpty,
  );
}

/// Entfernt beim Download über einen Sync-Code den API-Key aus den
/// übernommenen KI-Einstellungen (siehe SyncService.pull) – rein, testbar.
Map<String, dynamic> syncedAiSettingsForPull(Map<String, dynamic> synced, {required bool acceptApiKey}) {
  if (acceptApiKey) return synced;
  return {...synced, 'openRouterApiKey': null, 'pdfStorage': null};
}

/// Übernimmt Verlauf und Statistik aus einem heruntergeladenen Stand.
/// Frage-Chats und Probeklausuren werden wie Karten ERSETZT (auch
/// Löschungen sollen ankommen). Lerntage, Ampel-Trend und der heutige
/// Daily-Quiz-Stand werden ZUSAMMENGEFÜHRT: ein Lerntag bleibt ein Lerntag,
/// egal auf welchem Gerät gelernt wurde – der Streak soll durch einen
/// Download nie kürzer werden, und heute schon eingeführte neue Karten
/// zählen auf jedem Gerät gegen das Tagesbudget.
/// Fehlt ein Schlüssel (Cloud-Stand einer älteren App-Version), bleibt der
/// lokale Stand unverändert.
Future<void> applySyncedHistory(DatabaseClient txn, Map<String, dynamic> data) async {
  final chats = data['chatMessages'];
  if (chats is List) {
    await DatabaseService.chatMessages.delete(txn);
    for (final m in chats) {
      if (m is! Map) continue;
      final message = ChatMessage.fromMap(Map<String, dynamic>.from(m));
      await DatabaseService.chatMessages.record(message.id).put(txn, message.toMap());
    }
  }
  final unsupported = data['unsupportedTasks'];
  if (unsupported is List) {
    await DatabaseService.unsupportedTasks.delete(txn);
    for (final m in unsupported) {
      if (m is! Map) continue;
      final entry = UnsupportedTask.fromMap(Map<String, dynamic>.from(m));
      if (entry.id.isEmpty) continue;
      await DatabaseService.unsupportedTasks.record(entry.id).put(txn, entry.toMap());
    }
  }
  final exams = data['mockExamResults'];
  if (exams is List) {
    await MockExamRepository.replaceIn(txn, [
      for (final m in exams)
        if (m is Map) MockExamResult.fromMap(Map<String, dynamic>.from(m)),
    ]);
  }
  final snapshots = data['masterySnapshots'];
  if (snapshots is List) {
    for (final m in snapshots) {
      if (m is! Map) continue;
      final snapshot = MasterySnapshot.fromMap(Map<String, dynamic>.from(m));
      await DatabaseService.masterySnapshots.record(snapshot.dateKey).put(txn, snapshot.toMap());
    }
  }
  final days = data['studyDays'];
  if (days is List) {
    await StudyLogRepository.mergeDayKeysIn(txn, days.map((d) => d.toString()));
  }
  final session = data['dailySession'];
  if (session is Map) {
    final now = DateTime.now();
    final cloud = DailySessionState.fromMap(Map<String, dynamic>.from(session));
    if (cloud.isFor(now)) {
      final local = await DailySessionRepository.loadFrom(txn, now);
      await DailySessionRepository.saveIn(txn, local.mergedWith(cloud));
    }
  }
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

/// Der gesamte lokale Datenbestand für den Upload, die Diagnose und die lokalen
/// Sicherungen (siehe SyncBackupService).
Future<Map<String, dynamic>> buildSyncPayload(DatabaseClient db) async {
  return {
    'modules': (await DatabaseService.modules.find(db)).map((r) => r.value).toList(),
    'materials': (await DatabaseService.materials.find(db))
        .map((r) => SyncCodec.stripDeviceLocalMaterialFields(r.value))
        .toList(),
    'summaries': (await DatabaseService.summaries.find(db)).map((r) => r.value).toList(),
    'concepts': (await DatabaseService.concepts.find(db)).map((r) => r.value).toList(),
    'flashcards': (await DatabaseService.flashcards.find(db)).map((r) => r.value).toList(),
    'lectureUnits': (await DatabaseService.lectureUnits.find(db)).map((r) => r.value).toList(),
    'labExperiments': (await DatabaseService.labExperiments.find(db)).map((r) => r.value).toList(),
    // Verlauf und Statistik – ohne sie finge jedes weitere Gerät bei null
    // an (Streak, Probeklausur-Noten, Ampel-Trend, Frage-Chats).
    'chatMessages': (await DatabaseService.chatMessages.find(db)).map((r) => r.value).toList(),
    'unsupportedTasks': (await DatabaseService.unsupportedTasks.find(db)).map((r) => r.value).toList(),
    'masterySnapshots': (await DatabaseService.masterySnapshots.find(db)).map((r) => r.value).toList(),
    'mockExamResults': (await MockExamRepository.loadFrom(db)).map((r) => r.toMap()).toList(),
    'studyDays': await StudyLogRepository.dayKeysFrom(db),
    // Heute eingeführte neue Karten – damit ein zweites Gerät am selben Tag
    // nicht noch einmal das volle Neu-Karten-Budget verteilt.
    'dailySession': (await DailySessionRepository.loadFrom(db, DateTime.now())).toMap(),
  };
}

/// Ersetzt die lokalen Fächer, Materialien, Konzepte, Karten, Einheiten,
/// Laborversuche und den Verlauf durch [data] (ein Stand aus der Cloud oder aus
/// einer lokalen Sicherung). Lokal vorhandene PDFs bleiben erhalten (siehe
/// SyncCodec.withLocalMaterialFields). Gehört in eine Transaktion.
Future<void> applySyncPayload(DatabaseClient txn, Map<String, dynamic> data) async {
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
  // Laborversuche gibt es erst seit kurzem – ältere Stände kennen sie nicht.
  if (data.containsKey('labExperiments')) await DatabaseService.labExperiments.delete(txn);

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

  for (final e in (data['labExperiments'] as List? ?? [])) {
    final experiment = LabExperiment.fromMap(Map<String, dynamic>.from(e as Map));
    await DatabaseService.labExperiments.record(experiment.id).put(txn, experiment.toMap());
  }

  await applySyncedHistory(txn, data);

  // Lokale Daten zu Fächern, die es nach dem Download nicht mehr gibt,
  // würden sonst verwaist liegen bleiben (auch bei älteren Cloud-
  // Ständen ohne Chat/Probeklausuren, dann bleiben die lokalen).
  final moduleIds = {
    for (final m in (data['modules'] as List? ?? [])) (m as Map)['id']?.toString() ?? '',
  };
  await DatabaseService.chatMessages.delete(
    txn,
    finder: Finder(filter: Filter.not(Filter.inList('moduleId', moduleIds.toList()))),
  );
  await DatabaseService.labExperiments.delete(
    txn,
    finder: Finder(filter: Filter.not(Filter.inList('moduleId', moduleIds.toList()))),
  );
  await DatabaseService.unsupportedTasks.delete(
    txn,
    finder: Finder(filter: Filter.not(Filter.inList('moduleId', moduleIds.toList()))),
  );
  await MockExamRepository.retainModulesIn(txn, moduleIds);
  // Fotos zu Versuchen, die es nach dem Abgleich nicht mehr gibt (auf einem
  // anderen Gerät gelöscht), blieben sonst als ungesehene Altlast liegen –
  // Fotos selbst werden nicht synchronisiert und können groß sein.
  final labIds = (await DatabaseService.labExperiments.findKeys(txn)).toList();
  await DatabaseService.labPhotos.delete(
    txn,
    finder: Finder(filter: Filter.not(Filter.inList('experimentId', labIds))),
  );
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

/// Kennung des Teil-Dokuments [index] eines Cloud-Stands. Ab Format 3 trägt sie
/// die `pushId` des Uploads: ein neuer Upload schreibt neue Dokumente neben den
/// alten und schaltet erst am Ende das Hauptdokument um – bricht er ab, bleibt
/// der bisherige Stand vollständig lesbar. (Format 2 überschrieb die Teile
/// "0".."n-1" an Ort und Stelle; ein abgebrochener Upload machte den Stand
/// unlesbar.)
String syncPartId({required int format, required String? pushId, required int index}) =>
    format >= 3 ? '${pushId}_$index' : '$index';

/// Die Teile, die zu einem Cloud-Stand ([root] = sein Hauptdokument) gehören.
List<String> syncPartIdsOf(Map<String, dynamic>? root) {
  if (root == null) return const [];
  final count = (root['partCount'] as num?)?.toInt() ?? 0;
  final format = (root['format'] as num?)?.toInt() ?? 1;
  return [for (var i = 0; i < count; i++) syncPartId(format: format, pushId: root['pushId'] as String?, index: i)];
}

/// Kopfdaten des Cloud-Stands – wer ihn wann zuletzt hochgeladen hat.
/// Grundlage für den Schutz beim Auto-Sync (siehe AutoSyncService): hat
/// seit dem letzten eigenen Sync ein ANDERES Gerät hochgeladen, darf ein
/// automatischer Upload dessen Fortschritt nicht still überschreiben.
class CloudSyncMeta {
  const CloudSyncMeta({this.pushId, this.deviceId, this.updatedAt, this.modules, this.flashcards});

  final String? pushId;
  final String? deviceId;
  final DateTime? updatedAt;

  /// Umfang des Cloud-Stands (fehlt bei sehr alten Ständen).
  final int? modules;
  final int? flashcards;
}

/// Ergebnis von [SyncService.merge].
class SyncMergeOutcome {
  const SyncMergeOutcome({required this.pushId, required this.pushed, this.result});

  /// Die `pushId` des Cloud-Stands nach dem Abgleich (der eigene Upload oder der
  /// vorhandene, wenn nichts hochzuladen war).
  final String? pushId;

  /// Ob dabei etwas hochgeladen wurde.
  final bool pushed;

  /// Was zusammengeführt wurde; `null`, wenn es in der Cloud noch nichts gab.
  final SyncMergeResult? result;

  /// Ob sich auf diesem Gerät etwas geändert hat (die Ansichten müssen dann neu
  /// laden).
  bool get changedLocally => (result?.changedLocally ?? 0) > 0;

  /// Ein Satz für die Anzeige.
  String get message => result == null ? 'Es lag noch nichts in der Cloud – alles hochgeladen.' : describeMerge(result!);
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
/// selbst, siehe SyncCodec), Zusammenfassungen, Konzepte, Karteikarten,
/// Frage-Chats, Probeklausuren, Lerntage und Ampel-Trend (siehe
/// [applySyncedHistory]) sowie Vorlieben (siehe [syncedSettingsOf]).
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
/// Hauptdokument (`data`); sonst in Teilen unter `…/sync_parts/{pushId}_0..n-1`
/// (braucht die aktuellen Firestore-Regeln, siehe firestore.rules).
/// Jeder Upload trägt eine eigene `pushId` und schreibt seine Teile unter neuen
/// Kennungen; erst das Hauptdokument setzt den neuen Stand in Kraft. Ein
/// abgebrochener Upload lässt den bisherigen Stand deshalb unangetastet
/// lesbar, und ein Download setzt nie Teile zweier Uploads zusammen. Ältere
/// Cloud-Stände (Format 2 mit Teilen "0".."n-1", Format 1 als Klartext in EINEM
/// Dokument) werden weiterhin gelesen.
///
/// Setzt voraus, dass Firebase in main.dart erfolgreich initialisiert wurde.
/// Ist Firebase nicht konfiguriert, bleibt die App voll offline nutzbar –
/// [isAvailable] meldet das der UI, die den Sync-Bereich dann ausblendet.
class SyncService {
  bool get isAvailable => Firebase.apps.isNotEmpty;

  static const _settingsKey = 'app_settings';
  static const _partsCollection = 'sync_parts';
  static const syncFormat = 3;

  /// Frist für Lesezugriffe und Schreibvorgänge. Ohne sie hinge ein Upload bei
  /// abgerissener Verbindung endlos (Firestore reiht Schreibvorgänge dann still
  /// in seine Warteschlange ein und meldet erst nach dem Absenden Erfolg) – der
  /// Auto-Sync bliebe für immer im Zustand "lädt hoch".
  static const _readTimeout = Duration(seconds: 45);
  static const _writeTimeout = Duration(minutes: 2);

  /// Liest IMMER vom Server, nie aus dem lokalen Firestore-Zwischenspeicher.
  /// Der Standard liefert bei fehlender Verbindung stillschweigend einen alten
  /// Stand aus dem Cache: ein Download "gelingt" dann, bringt aber nichts
  /// Neues, und ein Upload prüft gegen veraltete Kopfdaten. Mit Server-Zwang
  /// kommt stattdessen ein sichtbarer Fehler.
  Future<DocumentSnapshot<Map<String, dynamic>>> _get(DocumentReference<Map<String, dynamic>> ref) =>
      ref.get(const GetOptions(source: Source.server)).timeout(_readTimeout);

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

  /// Gleicht diesen Stand mit der Cloud ab statt einen der beiden zu ersetzen
  /// (siehe [mergeSyncPayloads]): was auf einer Seite neu oder weiter ist,
  /// kommt auf die andere. Das Ergebnis liegt danach auf beiden Seiten.
  /// [alwaysUpload] lädt auch dann hoch, wenn die Cloud nichts Neues braucht
  /// (z.B. geänderte Einstellungen) – der Auto-Sync lässt das aus.
  Future<SyncMergeOutcome> merge(SyncTarget target, {required String deviceId, bool alwaysUpload = false}) =>
      _merge(_doc(target), includeApiKey: target.isAccount, deviceId: deviceId, alwaysUpload: alwaysUpload);

  /// Die früheren Cloud-Stände (neueste zuerst) neben den Kopfdaten des
  /// aktuellen – siehe [planCloudHistory].
  Future<({CloudSyncMeta? current, List<CloudStateEntry> previous})> cloudHistory(SyncTarget target) async {
    _ensureAvailable();
    final snapshot = await _get(_doc(target));
    return (current: _metaOf(snapshot), previous: CloudStateEntry.listFrom(snapshot.data()?['history']));
  }

  /// Macht einen früheren Cloud-Stand wieder zum aktuellen: erst lokal sichern,
  /// dann übernehmen und hochladen. Der ersetzte Stand wandert selbst in den
  /// Verlauf – auch das lässt sich also zurücknehmen. Liefert die neue `pushId`.
  Future<String> restoreCloudState(SyncTarget target, CloudStateEntry entry, {required String deviceId}) async {
    _ensureAvailable();
    final doc = _doc(target);
    final Map<String, dynamic> data;
    try {
      data = await _readPayload(doc, {'format': syncFormat, 'partCount': entry.partCount, 'pushId': entry.pushId});
    } on SyncException {
      throw SyncException('Dieser frühere Stand ist in der Cloud nicht mehr vollständig vorhanden.');
    }
    checkUsablePayload(data);
    final db = await DatabaseService.instance.database;
    try {
      await SyncBackupService.create(db, kind: SyncBackupService.kindRestore, reason: 'Vor dem Wiederherstellen eines Cloud-Stands');
    } catch (e) {
      throw SyncException('Die Sicherung vor dem Wiederherstellen ist fehlgeschlagen ($e) – es wurde nichts verändert.');
    }
    await db.transaction((txn) async {
      await applySyncPayload(txn, data);
      await SyncBaseStore.clear(txn);
    });
    return _push(doc, includeApiKey: target.isAccount, deviceId: deviceId, forceHistory: true);
  }

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
    final counts = data['counts'] is Map ? data['counts'] as Map : const {};
    return CloudSyncMeta(
      pushId: data['pushId'] as String?,
      deviceId: data['deviceId'] as String?,
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
      modules: (counts['modules'] as num?)?.toInt(),
      flashcards: (counts['flashcards'] as num?)?.toInt(),
    );
  }

  /// Kopfdaten des Cloud-Stands (ohne die Daten selbst zu laden), `null`,
  /// wenn dort noch nichts liegt – z.B. um nach der Anmeldung zu fragen, ob
  /// der Stand geholt werden soll.
  Future<CloudSyncMeta?> cloudMeta(SyncTarget target) async {
    _ensureAvailable();
    return _metaOf(await _get(_doc(target)));
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

  /// "Verbindung prüfen": geht die Wege des Syncs einmal durch und sagt, woran
  /// es hängt – Firebase verbunden? Welches Ziel (Konto oder Sync-Code)? Liegt
  /// dort ein Stand, ist er lesbar, und darf dieses Gerät schreiben? Ändert
  /// nichts an den Daten (die Schreibprobe legt ein Testdokument an und löscht
  /// es sofort wieder).
  Future<List<DiagLine>> diagnose(
    SyncTarget? target, {
    required String deviceId,
    required String? lastSyncedPushId,
    String? email,
  }) async {
    const wait = Duration(seconds: 25);
    final lines = <DiagLine>[DiagLine(DiagLevel.info, 'Gerät', kIsWeb ? 'Web' : defaultTargetPlatform.name)];
    if (!isAvailable) {
      return [
        ...lines,
        const DiagLine(
          DiagLevel.error,
          'Firebase ist nicht verbunden',
          'Die Initialisierung beim App-Start hat nicht geklappt (kein Netz beim Start, zu langsam?). '
              'App neu starten; besteht das Problem, ist der Cloud-Sync in diesem Build nicht nutzbar.',
        ),
      ];
    }
    lines.add(DiagLine(DiagLevel.ok, 'Firebase ist verbunden', 'Projekt ${Firebase.app().options.projectId}'));
    if (target == null) {
      return [
        ...lines,
        const DiagLine(
          DiagLevel.error,
          'Kein Sync-Ziel',
          'Weder ein Konto angemeldet noch ein Sync-Code eingetragen. Alle Geräte müssen dasselbe Ziel '
              'nutzen: dasselbe Konto ODER denselben Sync-Code.',
        ),
      ];
    }
    lines.add(
      DiagLine(
        DiagLevel.info,
        'Ziel: ${SyncDiagnostics.targetLabel(isAccount: target.isAccount, id: target.id, email: email)}',
        target.isAccount
            ? 'Die anderen Geräte müssen mit demselben Konto angemeldet sein. Wer auf einem Gerät ein Konto '
                  'nutzt und auf dem anderen einen Sync-Code, sieht nie dieselben Daten.'
            : 'Die anderen Geräte müssen denselben Sync-Code eingeben (und dürfen nicht mit einem Konto '
                  'angemeldet sein – dann läuft der Sync über das Konto).',
      ),
    );

    final doc = _doc(target);
    Map<String, dynamic>? root;
    try {
      final snapshot = await _get(doc);
      if (!snapshot.exists) {
        lines.add(
          const DiagLine(
            DiagLevel.warn,
            'Für dieses Ziel liegt in der Cloud noch nichts',
            'Auf dem Gerät mit den Daten „Hochladen“ (oder „Abgleichen“), danach hier „Abgleichen“.',
          ),
        );
      } else {
        root = snapshot.data();
        final meta = _metaOf(snapshot);
        final when = meta?.updatedAt == null
            ? ''
            : ' · hochgeladen ${SyncDiagnostics.since(meta!.updatedAt!, DateTime.now())}';
        lines.add(
          DiagLine(
            DiagLevel.ok,
            'Cloud-Stand gefunden',
            'Fächer: ${meta?.modules ?? '?'} · Karten: ${meta?.flashcards ?? '?'}$when · Format ${root?['format'] ?? 1}',
          ),
        );
        lines.add(
          SyncDiagnostics.compareWithCloud(
            cloudPushId: meta?.pushId,
            cloudDeviceId: meta?.deviceId,
            lastSyncedPushId: lastSyncedPushId,
            deviceId: deviceId,
          ),
        );
      }
    } catch (e) {
      lines.add(DiagLine(DiagLevel.error, 'Die Cloud lässt sich nicht lesen', SyncDiagnostics.describeError(e)));
    }

    if (root != null) {
      try {
        final data = await _readPayload(doc, root).timeout(const Duration(seconds: 90));
        checkUsablePayload(data);
        final parts = (root['partCount'] as num?)?.toInt() ?? 0;
        lines.add(
          DiagLine(
            DiagLevel.ok,
            'Cloud-Stand vollständig lesbar',
            parts == 0 ? 'in einem Dokument' : 'aus $parts Teilen',
          ),
        );
      } catch (e) {
        lines.add(
          DiagLine(
            DiagLevel.error,
            'Cloud-Stand nicht lesbar',
            e is SyncException ? e.message : SyncDiagnostics.describeError(e),
          ),
        );
      }
    }

    var partsNeeded = 1;
    try {
      final db = await DatabaseService.instance.database;
      final payload = await buildSyncPayload(db);
      final raw = utf8.encode(jsonEncode(payload)).length;
      final parts = SyncCodec.encode(payload);
      partsNeeded = parts.length;
      final compressed = parts.fold<int>(0, (total, p) => total + p.length);
      lines.add(
        DiagLine(
          parts.length == 1 ? DiagLevel.ok : DiagLevel.info,
          'Lokaler Stand: ${SyncDiagnostics.size(compressed)} komprimiert (${SyncDiagnostics.size(raw)} roh)',
          parts.length == 1
              ? 'passt in ein Cloud-Dokument'
              : 'wird in ${parts.length} Teilen hochgeladen – dafür müssen die Firestore-Regeln (sync_parts) '
                    'in der Firebase-Konsole veröffentlicht sein.',
        ),
      );
    } catch (e) {
      lines.add(DiagLine(DiagLevel.error, 'Der lokale Stand lässt sich nicht bündeln', e.toString()));
    }

    try {
      final probe = doc.collection(_partsCollection).doc('_probe');
      await probe.set({'probe': true}).timeout(wait);
      await probe.delete().timeout(wait);
      lines.add(const DiagLine(DiagLevel.ok, 'Schreiben in die Cloud funktioniert'));
    } catch (e) {
      final denied = e is FirebaseException && e.code == 'permission-denied';
      lines.add(
        DiagLine(
          DiagLevel.error,
          'Schreiben in die Cloud ist nicht möglich',
          '${SyncDiagnostics.describeError(e)}'
              '${denied && partsNeeded > 1 ? '\nDein Stand braucht mehrere Teile – der Upload scheitert daran.' : ''}',
        ),
      );
    }
    return lines;
  }

  void _ensureAvailable() {
    if (!isAvailable) {
      throw SyncException('Cloud-Sync ist nicht konfiguriert (kein Firebase-Projekt verbunden).');
    }
  }

  /// Der bisherige Cloud-Stand als Verlaufs-Eintrag, wenn er aufhebbar ist: seine
  /// Teile liegen unter `{pushId}_i` (Format 3) oder er steckt in einem Stück im
  /// Hauptdokument und wird beim Aufheben in ein Teil kopiert.
  static CloudStateEntry? _archivable(Map<String, dynamic>? root) {
    if (root == null) return null;
    final pushId = root['pushId'];
    if (pushId is! String || pushId.isEmpty) return null;
    final format = (root['format'] as num?)?.toInt() ?? 1;
    final partCount = (root['partCount'] as num?)?.toInt() ?? 0;
    if (partCount == 0 && root['data'] is! Blob) return null;
    if (partCount > 0 && format < 3) return null;
    final counts = root['counts'] is Map ? root['counts'] as Map : const {};
    final updatedAt = root['updatedAt'];
    return CloudStateEntry(
      pushId: pushId,
      partCount: partCount == 0 ? 1 : partCount,
      deviceId: root['deviceId'] as String?,
      at: updatedAt is Timestamp ? updatedAt.toDate() : null,
      modules: (counts['modules'] as num?)?.toInt(),
      flashcards: (counts['flashcards'] as num?)?.toInt(),
    );
  }

  Future<String> _push(
    DocumentReference<Map<String, dynamic>> doc, {
    required bool includeApiKey,
    required String deviceId,
    bool Function(CloudSyncMeta? cloud)? abortIf,
    bool forceHistory = false,
  }) async {
    _ensureAvailable();
    final previous = await _get(doc);
    if (abortIf != null && abortIf(_metaOf(previous))) {
      throw SyncConflictException('Der Cloud-Stand stammt von einem anderen Gerät.');
    }
    final db = await DatabaseService.instance.database;
    final payload = await buildSyncPayload(db);
    final parts = SyncCodec.encode(payload);
    final pushId = const Uuid().v4();
    final previousRoot = previous.data();
    final previousParts = syncPartIdsOf(previousRoot);
    final existingHistory = CloudStateEntry.listFrom(previousRoot?['history']);
    var plan = planCloudHistory(
      existing: existingHistory,
      previous: _archivable(previousRoot),
      newDeviceId: deviceId,
      force: forceHistory,
    );

    final written = <String>[];
    // Steckte der bisherige Stand in einem Stück im Hauptdokument, braucht er als
    // frühere Fassung ein eigenes Teil-Dokument (das Hauptdokument wird gleich
    // überschrieben). Gelingt das nicht, wird er nicht aufgehoben.
    final retired = plan.retired;
    if (retired != null && ((previousRoot?['partCount'] as num?)?.toInt() ?? 0) == 0) {
      final id = syncPartId(format: syncFormat, pushId: retired.pushId, index: 0);
      try {
        await doc
            .collection(_partsCollection)
            .doc(id)
            .set({'pushId': retired.pushId, 'data': previousRoot!['data']}).timeout(_writeTimeout);
        written.add(id);
      } catch (_) {
        plan = planCloudHistory(existing: existingHistory, previous: null, newDeviceId: deviceId);
      }
    }

    final meta = <String, dynamic>{
      'format': syncFormat,
      'updatedAt': FieldValue.serverTimestamp(),
      'pushId': pushId,
      'deviceId': deviceId,
      'counts': {
        for (final e in payload.entries)
          if (e.value case final List list) e.key: list.length,
      },
      'history': [for (final e in plan.keep) e.toMap()],
      'aiSettings': await _readAiSettings(db, includeApiKey: includeApiKey),
    };

    if (parts.length == 1) {
      try {
        await doc.set({...meta, 'partCount': 0, 'data': Blob(parts.single)}).timeout(_writeTimeout);
      } catch (_) {
        await _deleteParts(doc, written);
        rethrow;
      }
    } else {
      try {
        for (var i = 0; i < parts.length; i++) {
          final id = syncPartId(format: syncFormat, pushId: pushId, index: i);
          await doc
              .collection(_partsCollection)
              .doc(id)
              .set({'pushId': pushId, 'data': Blob(parts[i])}).timeout(_writeTimeout);
          written.add(id);
        }
        // Erst NACH allen Teilen wird der neue Stand im Hauptdokument in Kraft
        // gesetzt. Die Teile des bisherigen Stands liegen unter anderen
        // Kennungen und bleiben bis dahin unberührt.
        await doc.set({...meta, 'partCount': parts.length}).timeout(_writeTimeout);
      } on FirebaseException catch (e) {
        await _deleteParts(doc, written);
        if (e.code == 'permission-denied') {
          throw SyncException(
            'Deine Daten sind zu groß für ein einzelnes Cloud-Dokument und werden '
            'jetzt in Teilen hochgeladen – dafür müssen die Firestore-Regeln einmal '
            'aktualisiert werden: Inhalt von firestore.rules in der Firebase-Konsole '
            '(Firestore → Regeln) einfügen und veröffentlichen. In den Einstellungen '
            'unter "Verbindung prüfen" gibt es dafür "Regeln kopieren".',
          );
        }
        rethrow;
      } catch (_) {
        await _deleteParts(doc, written);
        rethrow;
      }
    }

    // Aufräumen – erst jetzt, wo der neue Stand gilt: die Teile des bisherigen
    // Stands (außer er wandert in den Verlauf) und die der Stände, die aus dem
    // Verlauf herausfallen.
    if (plan.retired == null) await _deleteParts(doc, previousParts);
    for (final dropped in plan.drop) {
      await _deleteParts(doc, [
        for (var i = 0; i < dropped.partCount; i++) syncPartId(format: syncFormat, pushId: dropped.pushId, index: i),
      ]);
    }
    // Cloud und dieses Gerät sind jetzt gleich – Ausgangspunkt für das nächste
    // Zusammenführen. Scheitert das, bleibt der ältere Basisstand: das führt nur
    // zu vorsichtigerem Vergleichen, nie zu Verlust.
    try {
      await SyncBaseStore.save(db, payload);
    } catch (_) {}
    return pushId;
  }

  Future<SyncMergeOutcome> _merge(
    DocumentReference<Map<String, dynamic>> doc, {
    required bool includeApiKey,
    required String deviceId,
    required bool alwaysUpload,
  }) async {
    _ensureAvailable();
    final snapshot = await _get(doc);
    if (!snapshot.exists) {
      // Noch nichts in der Cloud: einfach hochladen.
      return SyncMergeOutcome(pushId: await _push(doc, includeApiKey: includeApiKey, deviceId: deviceId), pushed: true);
    }
    final root = snapshot.data()!;
    final cloudPushId = root['pushId'] as String?;
    final remote = await _readPayload(doc, root);
    checkUsablePayload(remote);
    final db = await DatabaseService.instance.database;
    final result = await mergeRemoteIntoLocal(db, remote);

    // Die Einstellungen des anderen Geräts (Key, Modelle …) kommen mit, aber
    // nur von einem ANDEREN Gerät – der eigene Stand in der Cloud würde sonst
    // gerade geänderte, noch nicht hochgeladene Einstellungen zurücksetzen.
    final aiSettings = root['aiSettings'];
    if (root['deviceId'] != deviceId && aiSettings is Map) {
      await _writeAiSettings(
        db,
        syncedAiSettingsForPull(Map<String, dynamic>.from(aiSettings), acceptApiKey: includeApiKey),
      );
    }

    if (result.changedRemotely > 0 || alwaysUpload) {
      // Hat inzwischen ein weiteres Gerät hochgeladen, nicht überschreiben –
      // der nächste Abgleich holt auch das nach.
      final pushId = await _push(
        doc,
        includeApiKey: includeApiKey,
        deviceId: deviceId,
        abortIf: (cloud) => cloud?.pushId != cloudPushId,
      );
      return SyncMergeOutcome(pushId: pushId, pushed: true, result: result);
    }
    // Die Cloud braucht nichts: beide Seiten sind jetzt gleich.
    await SyncBaseStore.save(db, await buildSyncPayload(db));
    return SyncMergeOutcome(pushId: cloudPushId, pushed: false, result: result);
  }

  /// Löscht Teil-Dokumente. Aufräumen ist optional: ein übrig gebliebener Teil
  /// wird nie gelesen (das Hauptdokument nennt genau die Teile seines Stands).
  Future<void> _deleteParts(DocumentReference<Map<String, dynamic>> doc, List<String> ids) async {
    for (final id in ids) {
      try {
        await doc.collection(_partsCollection).doc(id).delete().timeout(const Duration(seconds: 20));
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _readPayload(
    DocumentReference<Map<String, dynamic>> doc,
    Map<String, dynamic> root,
  ) async {
    checkCloudFormat(root);
    final format = (root['format'] as num?)?.toInt() ?? 1;
    if (format < 2) return root; // alter Stand: alles im Hauptdokument
    final partCount = (root['partCount'] as num?)?.toInt() ?? 0;
    if (partCount == 0) {
      final blob = root['data'];
      if (blob is! Blob) throw SyncException('Der Cloud-Stand ist unvollständig.');
      return SyncCodec.decode([blob.bytes]);
    }
    final snapshots = await Future.wait([for (final id in syncPartIdsOf(root)) _get(doc.collection(_partsCollection).doc(id))]);
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
    final snapshot = await _get(doc);
    if (!snapshot.exists) {
      throw SyncException('Für dieses Ziel liegen noch keine Cloud-Daten vor.');
    }
    final root = snapshot.data()!;
    final data = await _readPayload(doc, root);
    checkUsablePayload(data);
    final db = await DatabaseService.instance.database;

    // Vorher eine Sicherung auf diesem Gerät: der Download ersetzt alles Lokale.
    // Schlägt sie fehl, wird lieber nichts heruntergeladen als etwas verloren.
    try {
      await SyncBackupService.create(db, kind: SyncBackupService.kindPull, reason: 'Vor dem Herunterladen');
    } catch (e) {
      throw SyncException(
        'Die Sicherung vor dem Herunterladen ist fehlgeschlagen ($e) – es wurde nichts verändert.',
      );
    }

    await db.transaction((txn) async {
      await applySyncPayload(txn, data);
      final aiSettings = root['aiSettings'] ?? data['aiSettings'];
      await _writeAiSettings(
        txn,
        aiSettings == null ? null : syncedAiSettingsForPull(Map<String, dynamic>.from(aiSettings as Map), acceptApiKey: acceptApiKey),
      );
      // Cloud und dieses Gerät sind jetzt gleich (Ausgangspunkt fürs Zusammenführen).
      await SyncBaseStore.save(txn, await buildSyncPayload(txn));
    });
    return root['pushId'] as String?;
  }

  Future<Map<String, dynamic>> _readAiSettings(DatabaseClient db, {required bool includeApiKey}) async {
    final record = await DatabaseService.settings.record(_settingsKey).get(db);
    final settings = record == null ? const AppSettings() : AppSettings.fromMap(record);
    return syncedSettingsOf(settings, includeSecrets: includeApiKey);
  }

  Future<void> _writeAiSettings(DatabaseClient db, Map<String, dynamic>? synced) async {
    if (synced == null) return;
    final record = await DatabaseService.settings.record(_settingsKey).get(db);
    final current = record == null ? const AppSettings() : AppSettings.fromMap(record);
    final updated = mergeAiSettings(current, synced);
    await DatabaseService.settings.record(_settingsKey).put(db, updated.toMap());
  }
}
