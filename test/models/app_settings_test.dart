import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/pdf_storage_config.dart';

void main() {
  group('AppSettings – Lernerinnerung Defaults', () {
    test('ist standardmäßig deaktiviert, mit 18:00 als Vorgabe-Uhrzeit', () {
      const settings = AppSettings();
      expect(settings.dailyReminderEnabled, isFalse);
      expect(settings.dailyReminderHour, 18);
      expect(settings.dailyReminderMinute, 0);
    });
  });

  group('AppSettings.dailyReminderHour/Minute', () {
    test('leiten sich korrekt aus dailyReminderMinuteOfDay ab', () {
      const settings = AppSettings(dailyReminderMinuteOfDay: 9 * 60 + 30);
      expect(settings.dailyReminderHour, 9);
      expect(settings.dailyReminderMinute, 30);
    });
  });

  group('AppSettings.copyWith', () {
    test('aktualisiert Erinnerungs-Felder unabhängig voneinander', () {
      const settings = AppSettings();
      final updated = settings.copyWith(dailyReminderEnabled: true, dailyReminderMinuteOfDay: 7 * 60);
      expect(updated.dailyReminderEnabled, isTrue);
      expect(updated.dailyReminderHour, 7);
    });
  });

  group('AppSettings – PDF-Speicher', () {
    test('standardmäßig aus, Zugangsdaten überstehen den Round-Trip', () {
      expect(const AppSettings().pdfStorage.isConfigured, isFalse);
      const settings = AppSettings(
        pdfStorage: PdfStorageConfig(
          type: PdfStorageType.webdav,
          endpoint: 'https://cloud.example.de/dav',
          accessKey: 'nutzer',
          secret: 'pw',
        ),
      );
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.pdfStorage.type, PdfStorageType.webdav);
      expect(restored.pdfStorage.isConfigured, isTrue);
      final old = settings.toMap()..remove('pdfStorage');
      expect(AppSettings.fromMap(old).pdfStorage.type, PdfStorageType.none);
    });
  });

  group('AppSettings – Auto-Sync', () {
    test('ist standardmäßig aus und übersteht den Round-Trip', () {
      expect(const AppSettings().autoSyncEnabled, isFalse);
      const settings = AppSettings(autoSyncEnabled: true, deviceId: 'dev-1', lastSyncedPushId: 'push-9');
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.autoSyncEnabled, isTrue);
      expect(restored.deviceId, 'dev-1');
      expect(restored.lastSyncedPushId, 'push-9');
    });

    test('ältere Datensätze ohne Auto-Sync-Felder bleiben lesbar', () {
      final map = const AppSettings().toMap()
        ..remove('autoSyncEnabled')
        ..remove('deviceId')
        ..remove('lastSyncedPushId');
      final restored = AppSettings.fromMap(map);
      expect(restored.autoSyncEnabled, isFalse);
      expect(restored.deviceId, isNull);
    });
  });

  group('AppSettings – toMap/fromMap', () {
    test('Round-Trip erhält die Erinnerungs-Einstellungen', () {
      const settings = AppSettings(dailyReminderEnabled: true, dailyReminderMinuteOfDay: 20 * 60 + 15);
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.dailyReminderEnabled, isTrue);
      expect(restored.dailyReminderMinuteOfDay, 20 * 60 + 15);
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne Erinnerungs-Felder', () {
      final map = const AppSettings().toMap()
        ..remove('dailyReminderEnabled')
        ..remove('dailyReminderMinuteOfDay');
      final restored = AppSettings.fromMap(map);
      expect(restored.dailyReminderEnabled, isFalse);
      expect(restored.dailyReminderMinuteOfDay, AppSettings.defaultReminderMinuteOfDay);
    });
  });

  group('AppSettings.bestSprintScore', () {
    test('defaultet auf 0', () {
      expect(const AppSettings().bestSprintScore, 0);
    });

    test('Round-Trip erhält den Wert', () {
      const settings = AppSettings(bestSprintScore: 17);
      expect(AppSettings.fromMap(settings.toMap()).bestSprintScore, 17);
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne das Feld', () {
      final map = const AppSettings().toMap()..remove('bestSprintScore');
      expect(AppSettings.fromMap(map).bestSprintScore, 0);
    });
  });

  group('AppSettings.checkpointQuizPageInterval', () {
    test('defaultet auf 5', () {
      expect(const AppSettings().checkpointQuizPageInterval, 5);
    });

    test('Round-Trip erhält den Wert (inkl. 0 = deaktiviert)', () {
      const settings = AppSettings(checkpointQuizPageInterval: 0);
      expect(AppSettings.fromMap(settings.toMap()).checkpointQuizPageInterval, 0);
      const other = AppSettings(checkpointQuizPageInterval: 10);
      expect(AppSettings.fromMap(other.toMap()).checkpointQuizPageInterval, 10);
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne das Feld', () {
      final map = const AppSettings().toMap()..remove('checkpointQuizPageInterval');
      expect(AppSettings.fromMap(map).checkpointQuizPageInterval, 5);
    });
  });

  group('AppSettings.themeSkin', () {
    test('defaultet auf "klar"', () {
      expect(const AppSettings().themeSkin, 'klar');
    });

    test('Round-Trip erhält den gewählten Skin', () {
      const settings = AppSettings(themeSkin: 'lebendig');
      expect(AppSettings.fromMap(settings.toMap()).themeSkin, 'lebendig');
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne das Feld', () {
      final map = const AppSettings().toMap()..remove('themeSkin');
      expect(AppSettings.fromMap(map).themeSkin, 'klar');
    });

    test('copyWith ändert nur themeSkin', () {
      const settings = AppSettings(themeSkin: 'ruhig');
      final updated = settings.copyWith(themeSkin: 'lebendig');
      expect(updated.themeSkin, 'lebendig');
      expect(updated.dailyReminderEnabled, settings.dailyReminderEnabled);
    });
  });

  group('AppSettings.themeModePreference', () {
    test('defaultet auf "system"', () {
      expect(const AppSettings().themeModePreference, 'system');
    });

    test('Round-Trip erhält die gewählte Vorgabe', () {
      const settings = AppSettings(themeModePreference: 'dark');
      expect(AppSettings.fromMap(settings.toMap()).themeModePreference, 'dark');
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne das Feld', () {
      final map = const AppSettings().toMap()..remove('themeModePreference');
      expect(AppSettings.fromMap(map).themeModePreference, 'system');
    });

    test('copyWith ändert nur themeModePreference', () {
      const settings = AppSettings(themeModePreference: 'light');
      final updated = settings.copyWith(themeModePreference: 'dark');
      expect(updated.themeModePreference, 'dark');
      expect(updated.dailyReminderEnabled, settings.dailyReminderEnabled);
    });
  });
}
