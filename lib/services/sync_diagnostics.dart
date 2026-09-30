import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;

/// Wie schwer wiegt eine Zeile der Sync-Diagnose.
enum DiagLevel { ok, info, warn, error }

/// Eine Zeile im Ergebnis von "Verbindung prüfen".
class DiagLine {
  const DiagLine(this.level, this.title, [this.detail = '']);

  final DiagLevel level;
  final String title;
  final String detail;

  String get symbol => switch (level) {
    DiagLevel.ok => '✓',
    DiagLevel.info => '•',
    DiagLevel.warn => '!',
    DiagLevel.error => '✗',
  };

  /// Für die Zwischenablage (Diagnose an jemanden schicken).
  String asText() => '$symbol $title${detail.isEmpty ? '' : '\n   $detail'}';
}

/// Reine Hilfen für die Sync-Diagnose (kein Firestore-Zugriff, damit testbar):
/// verständliche Fehlertexte und der Vergleich von lokalem Stand und Cloud.
class SyncDiagnostics {
  /// Übersetzt einen Sync-Fehler in einen Satz, der sagt, was zu tun ist. Der
  /// technische Code bleibt in Klammern stehen.
  static String describeError(Object error) {
    if (error is TimeoutException) {
      return 'Keine Antwort von der Cloud (Zeitüberschreitung) – Verbindung, Firewall oder VPN prüfen.';
    }
    // dart:io gibt es im Web nicht – der Typ wird deshalb am Namen erkannt.
    if (error.runtimeType.toString() == 'SocketException') {
      return 'Keine Netzwerkverbindung ($error).';
    }
    if (error is FirebaseException) {
      final code = error.code;
      final detail = (error.message ?? '').trim();
      final hint = switch (code) {
        'permission-denied' =>
          'Firestore verweigert den Zugriff. Die Regeln aus firestore.rules müssen in der Firebase-Konsole '
              '(Firestore → Regeln) veröffentlicht sein; bei einem Sync-Code muss er mindestens 6 Zeichen lang '
              'sein, beim Konto muss man angemeldet sein.',
        'unavailable' || 'deadline-exceeded' =>
          'Firestore ist nicht erreichbar – Internetverbindung prüfen; Firewall, Proxy oder VPN können die '
              'Verbindung blockieren (Firestore braucht ausgehend Port 443).',
        'unauthenticated' => 'Nicht angemeldet oder die Anmeldung ist abgelaufen – neu anmelden.',
        'not-found' => 'Das Firestore-Projekt oder die Datenbank wurde nicht gefunden.',
        'resource-exhausted' => 'Das Firestore-Kontingent ist aufgebraucht oder die Anfrage zu groß.',
        'invalid-argument' ||
        'failed-precondition' => 'Firestore hat die Daten abgelehnt (evtl. über dem Größenlimit).',
        'network-request-failed' => 'Keine Netzwerkverbindung.',
        _ => detail,
      };
      return hint.isEmpty ? code : '$hint ($code)';
    }
    return error.toString();
  }

  /// Bezeichnung des Sync-Ziels – ohne die Kennung ganz zu zeigen (ein Sync-Code
  /// wirkt wie ein Passwort).
  static String targetLabel({required bool isAccount, required String id, String? email}) {
    String tail(String s) => s.length <= 4 ? s : '…${s.substring(s.length - 4)}';
    return isAccount
        ? 'Konto${email == null ? '' : ' $email'} (Kennung ${tail(id)})'
        : 'Sync-Code ${id.isEmpty ? '(leer)' : '${id.substring(0, id.length < 2 ? id.length : 2)}…${id.length} Zeichen'}';
  }

  /// Vergleicht den Cloud-Stand mit dem, was dieses Gerät zuletzt gesehen hat.
  static DiagLine compareWithCloud({
    required String? cloudPushId,
    required String? cloudDeviceId,
    required String? lastSyncedPushId,
    required String deviceId,
  }) {
    if (cloudPushId == null) {
      return const DiagLine(DiagLevel.info, 'Cloud-Stand im alten Format', 'Ein Upload dieses Geräts ersetzt ihn.');
    }
    if (cloudPushId == lastSyncedPushId) {
      return const DiagLine(DiagLevel.ok, 'Dieses Gerät ist auf dem Stand der Cloud');
    }
    if (cloudDeviceId == deviceId) {
      return const DiagLine(
        DiagLevel.ok,
        'Der Cloud-Stand stammt von diesem Gerät',
        'Andere Geräte müssen ihn mit „Herunterladen“ holen.',
      );
    }
    return const DiagLine(
      DiagLevel.warn,
      'Ein anderes Gerät hat neuer hochgeladen',
      'Hier „Herunterladen“ drücken, um diesen Stand zu holen – ein Upload von hier würde ihn ersetzen.',
    );
  }

  /// Ein Satz zum Cloud-Stand für Bestätigungsfragen: "12 Fächer, 340 Karten ·
  /// hochgeladen vor 3 Std. von einem anderen Gerät".
  static String describeCloudState({
    required int? modules,
    required int? flashcards,
    required DateTime? updatedAt,
    required bool fromThisDevice,
    required DateTime now,
  }) {
    final counts = modules == null && flashcards == null
        ? 'Umfang unbekannt'
        : '${modules ?? '?'} Fächer, ${flashcards ?? '?'} Karten';
    final when = updatedAt == null ? '' : ' · hochgeladen ${since(updatedAt, now)}';
    return '$counts$when ${fromThisDevice ? 'von diesem Gerät' : 'von einem anderen Gerät'}';
  }

  /// "vor 5 Min." / "vor 3 Std." / "vor 2 Tagen".
  static String since(DateTime time, DateTime now) {
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
    return 'vor ${diff.inDays} Tagen';
  }

  /// KB/MB als Text.
  static String size(int bytes) =>
      bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';
}
