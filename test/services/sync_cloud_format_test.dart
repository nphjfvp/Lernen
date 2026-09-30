import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/firestore_rules.dart';
import 'package:lernen/services/sync_diagnostics.dart';
import 'package:lernen/services/sync_service.dart';

void main() {
  group('Teile im Cloud-Stand (Format 3)', () {
    test('ab Format 3 tragen die Teile die pushId, davor waren es fortlaufende Nummern', () {
      expect(syncPartId(format: 3, pushId: 'abc', index: 1), 'abc_1');
      expect(syncPartId(format: 2, pushId: 'abc', index: 1), '1');
      expect(syncPartId(format: 1, pushId: null, index: 0), '0');
    });

    test('zu einem Hauptdokument gehören genau seine Teile', () {
      expect(syncPartIdsOf({'format': 3, 'pushId': 'p1', 'partCount': 3}), ['p1_0', 'p1_1', 'p1_2']);
      expect(syncPartIdsOf({'format': 2, 'pushId': 'p0', 'partCount': 2}), ['0', '1']);
      expect(syncPartIdsOf({'format': 3, 'pushId': 'p1', 'partCount': 0}), isEmpty);
      expect(syncPartIdsOf({'format': 3, 'pushId': 'p1'}), isEmpty);
      expect(syncPartIdsOf(null), isEmpty);
    });

    test('zwei Uploads teilen sich nie eine Kennung – der neue überschreibt den alten nicht', () {
      final old = syncPartIdsOf({'format': 3, 'pushId': 'alt', 'partCount': 4}).toSet();
      final next = {for (var i = 0; i < 4; i++) syncPartId(format: SyncService.syncFormat, pushId: 'neu', index: i)};
      expect(old.intersection(next), isEmpty);
    }, );

    test('ein Stand aus Format 2 und 3 wird gelesen, ein späteres Format nicht', () {
      expect(() => checkCloudFormat({'format': 2}), returnsNormally);
      expect(() => checkCloudFormat({'format': 3}), returnsNormally);
      expect(() => checkCloudFormat({'format': 4}), throwsA(isA<SyncException>()));
      expect(SyncService.syncFormat, 3);
    });
  });

  test('Regeln kopieren: der eingebettete Text ist die Datei firestore.rules', () {
    String norm(String s) => s.replaceAll('\r\n', '\n').trimRight();
    expect(norm(firestoreRulesText), norm(File('firestore.rules').readAsStringSync()));
    expect(firestoreRulesText, contains('sync_parts'));
  });

  test('Cloud-Stand als Satz für Bestätigungen', () {
    final now = DateTime(2026, 9, 30, 12);
    expect(
      SyncDiagnostics.describeCloudState(
        modules: 12,
        flashcards: 340,
        updatedAt: now.subtract(const Duration(hours: 3)),
        fromThisDevice: false,
        now: now,
      ),
      '12 Fächer, 340 Karten · hochgeladen vor 3 Std. von einem anderen Gerät',
    );
    expect(
      SyncDiagnostics.describeCloudState(modules: null, flashcards: null, updatedAt: null, fromThisDevice: true, now: now),
      'Umfang unbekannt von diesem Gerät',
    );
  });
}
