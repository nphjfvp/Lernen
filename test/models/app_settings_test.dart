import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';

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
}
