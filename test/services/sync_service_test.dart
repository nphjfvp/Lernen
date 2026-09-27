import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/pdf_storage_config.dart';
import 'package:lernen/services/sync_service.dart';

void main() {
  group('mergeAiSettings', () {
    test('übernimmt alle vier BYOK-Felder aus dem Sync-Dokument', () {
      const current = AppSettings();
      final merged = mergeAiSettings(current, {
        'openRouterApiKey': 'sk-cloud',
        'questionModelId': 'model-a',
        'visionModelId': 'model-b',
        'crosscheckModelId': 'model-c',
      });
      expect(merged.openRouterApiKey, 'sk-cloud');
      expect(merged.questionModelId, 'model-a');
      expect(merged.visionModelId, 'model-b');
      expect(merged.crosscheckModelId, 'model-c');
    });

    test('gibt current unverändert zurück, wenn kein Sync-Dokument vorliegt', () {
      const current = AppSettings(openRouterApiKey: 'sk-local');
      final merged = mergeAiSettings(current, null);
      expect(merged.openRouterApiKey, 'sk-local');
    });

    test('löscht einen lokal vorhandenen API-Key NICHT, wenn er in der Cloud fehlt', () {
      const current = AppSettings(openRouterApiKey: 'sk-local');
      final merged = mergeAiSettings(current, {
        'openRouterApiKey': null,
        'questionModelId': null,
        'visionModelId': null,
        'crosscheckModelId': null,
      });
      expect(merged.openRouterApiKey, 'sk-local');
    });

    test('übernimmt trotzdem die anderen Felder, wenn nur der Key in der Cloud fehlt', () {
      const current = AppSettings(openRouterApiKey: 'sk-local');
      final merged = mergeAiSettings(current, {
        'openRouterApiKey': null,
        'questionModelId': 'model-a',
        'visionModelId': null,
        'crosscheckModelId': null,
      });
      expect(merged.openRouterApiKey, 'sk-local');
      expect(merged.questionModelId, 'model-a');
    });
  });

  group('Vorlieben und Sprint-Rekord im Sync', () {
    test('Vorlieben reisen mit, auch über einen Sync-Code; Geheimes nur übers Konto', () {
      const settings = AppSettings(
        openRouterApiKey: 'sk',
        chunkGranularity: ChunkGranularity.fine,
        rollingContextEnabled: false,
        checkpointQuizPageInterval: 8,
        bestSprintScore: 12,
        dailyReminderEnabled: true,
      );
      final code = syncedSettingsOf(settings, includeSecrets: false);
      expect(code['openRouterApiKey'], isNull);
      expect(code['pdfStorage'], isNull);
      expect(code['chunkGranularity'], 'fine');
      expect(code.containsKey('dailyReminderEnabled'), isFalse); // geräte-lokal
      expect(syncedSettingsOf(settings, includeSecrets: true)['openRouterApiKey'], 'sk');

      final merged = mergeAiSettings(const AppSettings(), code);
      expect(merged.chunkGranularity, ChunkGranularity.fine);
      expect(merged.rollingContextEnabled, isFalse);
      expect(merged.checkpointQuizPageInterval, 8);
      expect(merged.bestSprintScore, 12);
    });

    test('der höhere Sprint-Rekord zählt, fehlende Felder lassen den lokalen Wert stehen', () {
      const local = AppSettings(bestSprintScore: 20, chunkGranularity: ChunkGranularity.coarse);
      final merged = mergeAiSettings(local, {'bestSprintScore': 15});
      expect(merged.bestSprintScore, 20);
      expect(merged.chunkGranularity, ChunkGranularity.coarse);
    });

    test('ein leerer API-Key aus der Cloud löscht den lokalen nicht', () {
      final merged = mergeAiSettings(const AppSettings(openRouterApiKey: 'sk-local'), {'openRouterApiKey': '  '});
      expect(merged.openRouterApiKey, 'sk-local');
    });
  });

  group('syncedAiSettingsForPull', () {
    test('Sync-Code: ein API-Key aus der Cloud wird verworfen, der lokale bleibt', () {
      final synced = syncedAiSettingsForPull(
        {'openRouterApiKey': 'sk-fremd', 'questionModelId': 'model-a'},
        acceptApiKey: false,
      );
      final merged = mergeAiSettings(const AppSettings(openRouterApiKey: 'sk-eigener'), synced);
      expect(merged.openRouterApiKey, 'sk-eigener');
      expect(merged.questionModelId, 'model-a');
    });

    test('Konto: der API-Key wird übernommen', () {
      final synced = syncedAiSettingsForPull({'openRouterApiKey': 'sk-konto'}, acceptApiKey: true);
      expect(mergeAiSettings(const AppSettings(), synced).openRouterApiKey, 'sk-konto');
    });
  });

  group('PDF-Speicher-Zugangsdaten im Sync', () {
    const storage = PdfStorageConfig(
      type: PdfStorageType.s3,
      endpoint: 'https://x.r2.cloudflarestorage.com',
      bucket: 'b',
      accessKey: 'ak',
      secret: 'sk',
    );

    test('Konto: vollständige Zugangsdaten werden übernommen', () {
      final merged = mergeAiSettings(const AppSettings(), {'pdfStorage': storage.toMap()});
      expect(merged.pdfStorage.isConfigured, isTrue);
      expect(merged.pdfStorage.bucket, 'b');
    });

    test('leere Cloud-Zugangsdaten löschen die lokalen nicht', () {
      final merged = mergeAiSettings(
        const AppSettings(pdfStorage: storage),
        {'pdfStorage': const PdfStorageConfig().toMap()},
      );
      expect(merged.pdfStorage.bucket, 'b');
    });

    test('Sync-Code: Zugangsdaten werden verworfen', () {
      final synced = syncedAiSettingsForPull({'pdfStorage': storage.toMap()}, acceptApiKey: false);
      expect(mergeAiSettings(const AppSettings(), synced).pdfStorage.isConfigured, isFalse);
    });
  });

  group('Download-Schutz', () {
    test('Cloud-Stand einer neueren App-Version wird nicht gelesen', () {
      expect(() => checkCloudFormat({'format': SyncService.syncFormat + 1}), throwsA(isA<SyncException>()));
      expect(() => checkCloudFormat({'format': SyncService.syncFormat}), returnsNormally);
      expect(() => checkCloudFormat({}), returnsNormally); // ältestes Format ohne Feld
    });

    test('ohne Fächerliste wird nichts ersetzt', () {
      expect(() => checkUsablePayload({}), throwsA(isA<SyncException>()));
      expect(() => checkUsablePayload({'modules': []}), returnsNormally);
    });
  });
}
