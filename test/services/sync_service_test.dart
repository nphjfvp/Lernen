import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
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
}
