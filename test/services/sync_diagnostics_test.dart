import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/auto_sync_service.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/sync_diagnostics.dart';

void main() {
  group('describeError', () {
    String describe(String code, [String? message]) => SyncDiagnostics.describeError(
          FirebaseException(plugin: 'cloud_firestore', code: code, message: message),
        );

    test('permission-denied nennt die Regeln und die Mindestlänge des Sync-Codes', () {
      final text = describe('permission-denied', 'Missing or insufficient permissions.');
      expect(text, contains('firestore.rules'));
      expect(text, contains('6 Zeichen'));
      expect(text, endsWith('(permission-denied)'));
    });

    test('unavailable: Netz, Firewall, Port 443', () {
      final text = describe('unavailable');
      expect(text, contains('Port 443'));
      expect(text, endsWith('(unavailable)'));
    });

    test('Unbekannter Code: die Meldung von Firebase samt Code, ohne Meldung nur der Code', () {
      expect(describe('exotisch', 'Etwas ist passiert'), 'Etwas ist passiert (exotisch)');
      expect(describe('exotisch'), 'exotisch');
    });

    test('Zeitüberschreitung und Sonstiges', () {
      expect(SyncDiagnostics.describeError(TimeoutException('x')), contains('Zeitüberschreitung'));
      expect(SyncDiagnostics.describeError(StateError('kaputt')), contains('kaputt'));
    });
  });

  group('Ziel und Vergleich', () {
    test('ein Sync-Code wird nie ganz gezeigt', () {
      final label = SyncDiagnostics.targetLabel(isAccount: false, id: 'geheim-code-123');
      expect(label, isNot(contains('geheim-code-123')));
      expect(label, contains('15 Zeichen'));
      expect(SyncDiagnostics.targetLabel(isAccount: false, id: ''), 'Sync-Code (leer)');
    });

    test('Konto: E-Mail und nur das Ende der Kennung', () {
      final label = SyncDiagnostics.targetLabel(isAccount: true, id: 'uid-abcdef123456', email: 'a@b.de');
      expect(label, 'Konto a@b.de (Kennung …3456)');
    });

    DiagLine compare({String? cloud, String? device, String? last}) => SyncDiagnostics.compareWithCloud(
          cloudPushId: cloud,
          cloudDeviceId: device,
          lastSyncedPushId: last,
          deviceId: 'ich',
        );

    test('auf dem Stand der Cloud / selbst hochgeladen / anderes Gerät neuer / altes Format', () {
      expect(compare(cloud: 'p1', device: 'anderes', last: 'p1').level, DiagLevel.ok);
      expect(compare(cloud: 'p2', device: 'ich', last: 'p1').title, contains('von diesem Gerät'));
      final other = compare(cloud: 'p2', device: 'anderes', last: 'p1');
      expect(other.level, DiagLevel.warn);
      expect(other.detail, contains('Herunterladen'));
      expect(compare().level, DiagLevel.info);
    });
  });

  test('Zeit und Größe als Text', () {
    final now = DateTime(2026, 9, 30, 12);
    expect(SyncDiagnostics.since(now.subtract(const Duration(seconds: 20)), now), 'gerade eben');
    expect(SyncDiagnostics.since(now.subtract(const Duration(minutes: 5)), now), 'vor 5 Min.');
    expect(SyncDiagnostics.since(now.subtract(const Duration(hours: 3)), now), 'vor 3 Std.');
    expect(SyncDiagnostics.since(now.subtract(const Duration(days: 2)), now), 'vor 2 Tagen');
    expect(SyncDiagnostics.size(100), '1 KB');
    expect(SyncDiagnostics.size(300 * 1024), '300 KB');
    expect(SyncDiagnostics.size(3 * 1024 * 1024 + 512 * 1024), '3.5 MB');
  });

  test('DiagLine für die Zwischenablage', () {
    expect(const DiagLine(DiagLevel.error, 'Kaputt', 'Weil').asText(), '✗ Kaputt\n   Weil');
    expect(const DiagLine(DiagLevel.ok, 'Gut').asText(), '✓ Gut');
  });

  test('Auto-Sync beobachtet die Laborversuche (sonst bleiben sie bis zur nächsten Kartenänderung lokal)', () {
    expect(AutoSyncService.watchedStores, contains(DatabaseService.labExperiments));
    expect(AutoSyncService.watchedStores, contains(DatabaseService.flashcards));
  });
}
