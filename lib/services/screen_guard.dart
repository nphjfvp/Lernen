import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/learn_credit.dart';
import '../repositories/learn_credit_repository.dart';
import 'database_service.dart';
import 'windows_guard.dart';

/// Brücke zur Lernzeit-Sperre der Android-App (MainActivity, Kanal
/// `lernen/screen_guard`): misst die Zeit in den gesperrten Apps über die
/// Nutzungsstatistik und legt einen Sperrbildschirm darüber, sobald das
/// Lernguthaben aufgebraucht ist. Auf anderen Plattformen zählt nur das
/// Lernen (über den Cloud-Abgleich).
class ScreenGuard {
  ScreenGuard._();

  static const _channel = MethodChannel('lernen/screen_guard');

  /// Nur die Android-App kann andere Apps sperren.
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Test-Hook statt des Android-Kanals.
  @visibleForTesting
  static Future<Object?> Function(String method, [Object? arguments])? invokeHook;

  /// Gibt es die Sperre hier (Android-App – oder ein Test-Hook)?
  static bool get available => supported || invokeHook != null;

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    final hook = invokeHook;
    if (hook != null) return await hook(method, arguments) as T?;
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Berechtigungen und ob die Sperre läuft.
  static Future<({bool usageAccess, bool overlay, bool running})> status() async {
    final raw = await _invoke<Map>('status');
    return (
      usageAccess: raw?['usageAccess'] == true,
      overlay: raw?['overlay'] == true,
      running: raw?['running'] == true,
    );
  }

  static Future<void> openUsageSettings() => _invoke('openUsageSettings');
  static Future<void> openOverlaySettings() => _invoke('openOverlaySettings');

  /// Apps auf dem Handy (mit Startsymbol), nach Namen sortiert.
  static Future<List<({String package, String label})>> installedApps() async {
    final raw = await _invoke<List>('installedApps');
    final apps = [
      for (final a in raw ?? const [])
        if (a is Map) (package: '${a['package']}', label: '${a['label']}'),
    ];
    apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return apps;
  }

  /// Heute (seit Beginn des Lerntags) in [packages] verbrachte Minuten.
  static Future<int?> usedMinutes(List<String> packages, int dayStartHour) async {
    final raw = await _invoke<num>('usedMinutes', {'packages': packages, 'dayStartHour': dayStartHour});
    return raw?.round();
  }

  /// Regeln und heutiges Guthaben ans Handy geben – startet bzw. stoppt die
  /// Sperre. Nach jeder Antwort, nach dem Abgleich und beim Öffnen der App.
  ///
  /// Das Zeitkonto teilen sich Handy und PC: die hier genutzten Minuten
  /// werden verbucht (reisen mit dem Abgleich), die der anderen Geräte gehen
  /// als `otherUsedMinutes` mit. Auf Windows übernimmt [WindowsGuard].
  static Future<void> push({DateTime? now}) async {
    if (WindowsGuard.supported) return WindowsGuard.instance.refresh();
    if (!available) return;
    try {
      final when = now ?? DateTime.now();
      final db = await DatabaseService.instance.database;
      final rules = await LearnCreditRepository.loadRulesFrom(db);
      var credit = await LearnCreditRepository.loadFrom(db);
      final device = await LearnCreditRepository.deviceIdIn(db);
      final allowance = LearnAllowance.of(credit, rules, when);
      final key = LearnCredit.dailyUsageKey(allowance.day);
      if (rules.enabled) {
        final mine = await usedMinutes(rules.packages, rules.dayStartHour);
        if (mine != null && mine > 0) {
          final total = mine + credit.usedSeconds(key, exceptDevice: device) ~/ 60;
          await LearnCreditRepository.recordUsageIn(
            db,
            key,
            mine * 60,
            now: when,
            urgent: !allowance.unlimited && total >= allowance.minutes,
          );
          credit = await LearnCreditRepository.loadFrom(db);
        }
      }
      await pushWith(rules, allowance, otherUsedMinutes: credit.usedSeconds(key, exceptDevice: device) ~/ 60);
    } catch (_) {
      // Die Sperre darf das Lernen nie stören.
    }
  }

  static Future<void> pushWith(LearnCreditRules rules, LearnAllowance allowance, {int otherUsedMinutes = 0}) =>
      _invoke('configure', {
        'enabled': rules.enabled && rules.packages.isNotEmpty,
        'packages': rules.packages,
        'dayStartHour': rules.dayStartHour,
        'freeMinutes': rules.freeMinutes,
        'dayKey': allowance.day,
        'allowedMinutes': allowance.minutes,
        'unlimited': allowance.unlimited,
        'nextStep': allowance.nextStep,
        'topicsToday': allowance.topicsToday.length,
        'otherUsedMinutes': otherUsedMinutes,
      });
}
