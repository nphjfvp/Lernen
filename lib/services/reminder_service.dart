import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_settings.dart';

/// Plant die tägliche Lernerinnerung als lokale Push-Benachrichtigung (kein
/// eigener Server nötig). Nur auf Android/iOS aktiv – auf Web, Windows,
/// macOS und Linux hat `flutter_local_notifications` keine native
/// Implementierung (siehe dessen `pubspec.yaml`: nur android/ios/macos/linux
/// deklariert, und selbst macOS/Linux sind hier nicht als Zielplattform
/// eingebunden); dort bleibt die Einstellung sichtbar, hat aber keine
/// Wirkung. Nutzt `matchDateTimeComponents: DateTimeComponents.time`, damit
/// die Benachrichtigung sich nach dem ersten Planen selbst täglich
/// wiederholt.
class ReminderService {
  static const _notificationId = 1001;
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } catch (_) {
      // Unbekannte/nicht gefundene Zeitzone: UTC ist ein sicherer Fallback,
      // die Erinnerung kommt dann evtl. zu einer leicht verschobenen Uhrzeit.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(initSettings);

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  /// Plant die tägliche Erinnerung neu (oder löscht sie), passend zu den
  /// übergebenen Einstellungen. Sicher mehrfach aufzurufen, z.B. bei jeder
  /// Änderung in den Einstellungen oder beim App-Start.
  Future<void> reschedule(AppSettings settings) async {
    if (!isSupported) return;
    try {
      await _ensureInitialized();
      await _plugin.cancel(_notificationId);
      if (!settings.dailyReminderEnabled) return;

      await _plugin.zonedSchedule(
        _notificationId,
        'Zeit zum Lernen',
        'Deine tägliche Lernsession wartet.',
        _nextInstanceOf(settings.dailyReminderHour, settings.dailyReminderMinute),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminder',
            'Tägliche Lernerinnerung',
            channelDescription: 'Erinnert einmal täglich ans Lernen.',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      // Fehlertolerant wie die anderen Hintergrund-Integrationen der App
      // (KI-Beförderung, Home-Widget): eine fehlgeschlagene Erinnerung darf
      // nie die eigentliche App-Funktion stören.
    }
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
