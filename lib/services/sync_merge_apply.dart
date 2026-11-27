import 'package:sembast/sembast.dart';

import 'sync_backup_service.dart';
import 'sync_base_store.dart';
import 'sync_merge.dart';
import 'sync_service.dart';

/// Führt den Cloud-Stand [remote] mit dem Stand dieses Geräts zusammen (siehe
/// [mergeSyncPayloads]) und schreibt das Ergebnis in die lokale Datenbank.
///
/// Ändert sich dabei etwas auf diesem Gerät, entsteht vorher eine Sicherung
/// ([SyncBackupService.kindMerge]); scheitert sie, wird nichts verändert. Der
/// Basisstand wird hier bewusst NICHT fortgeschrieben – erst wenn die Cloud den
/// zusammengeführten Stand hat (siehe SyncService.merge). Lesen, Sichern,
/// Zusammenführen und Schreiben laufen in EINER Transaktion, damit
/// zwischendurch getätigte Antworten nicht überschrieben werden – und der
/// ganze Datenbestand nur einmal eingelesen und verglichen wird.
Future<SyncMergeResult> mergeRemoteIntoLocal(Database db, Map<String, dynamic> remote) async {
  checkUsablePayload(remote);
  late SyncMergeResult result;
  await db.transaction((txn) async {
    final local = await buildSyncPayload(txn);
    final base = await SyncBaseStore.load(txn);
    result = mergeSyncPayloads(local: local, remote: remote, base: base);
    if (result.changedLocally > 0) {
      try {
        await SyncBackupService.createIn(txn, local, kind: SyncBackupService.kindMerge, reason: 'Vor dem Zusammenführen');
      } catch (e) {
        // Wirft aus der Transaktion heraus – sie wird verworfen.
        throw SyncException('Die Sicherung vor dem Zusammenführen ist fehlgeschlagen ($e) – es wurde nichts verändert.');
      }
      await applySyncPayload(txn, result.payload);
    } else {
      // Nichts Neues – aber der heutige Daily-Stand des anderen Geräts zählt
      // trotzdem gegen das Tagesbudget.
      await applySyncedHistory(txn, {
        'dailySession': remote['dailySession'],
        'learnCredit': remote['learnCredit'],
        'learnCreditRules': remote['learnCreditRules'],
      });
    }
  });
  return result;
}
