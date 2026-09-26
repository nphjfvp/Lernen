import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/auto_sync_service.dart';
import 'package:lernen/services/sync_codec.dart';
import 'package:lernen/services/sync_service.dart';

void main() {
  group('SyncCodec', () {
    test('kodiert und dekodiert verlustfrei', () {
      final payload = {
        'modules': [
          {'id': 'm1', 'name': 'Mathe äöü ß 😀'},
        ],
        'flashcards': [
          {'id': 'f1', 'front': 'Frage', 'reps': 3, 'stability': 1.5, 'tags': null},
        ],
      };
      final parts = SyncCodec.encode(payload);
      expect(parts, hasLength(1));
      expect(SyncCodec.decode(parts), payload);
    });

    test('Text wird komprimiert – typische Lerndaten passen weit unter das Limit', () {
      final text = List.generate(20000, (i) => 'Die Zelle ist die kleinste Einheit des Lebens. ').join();
      final parts = SyncCodec.encode({
        'materials': [
          {'id': 'x', 'extractedText': text},
        ],
      });
      expect(text.length, greaterThan(900 * 1024));
      expect(parts, hasLength(1));
      expect(parts.single.length, lessThan(100 * 1024));
    });

    test('teilt große Bestände in Stücke unter dem Limit und setzt sie korrekt zusammen', () {
      final random = Random(42);
      // Zufallsdaten lassen sich kaum komprimieren – erzwingt mehrere Teile.
      final noise = String.fromCharCodes(List.generate(300000, (_) => 33 + random.nextInt(90)));
      final payload = {
        'flashcards': [
          {'id': 'f1', 'imageBase64': noise},
        ],
      };
      final parts = SyncCodec.encode(payload, maxPartBytes: 64 * 1024);
      expect(parts.length, greaterThan(1));
      expect(parts.every((p) => p.length <= 64 * 1024), isTrue);
      expect(SyncCodec.decode(parts), payload);
    });

    test('PDF-Pfad und PDF-Bytes werden nicht übertragen, der Verweis in den eigenen Speicher schon', () {
      final stripped = SyncCodec.stripDeviceLocalMaterialFields({
        'id': 'm',
        'extractedText': 'Text',
        'filePath': '/data/folien.pdf',
        'fileBytesBase64': 'JVBERi0x',
        'remotePdfKey': 'lernen-pdfs/m.pdf',
      });
      expect(stripped, {'id': 'm', 'extractedText': 'Text', 'remotePdfKey': 'lernen-pdfs/m.pdf'});
    });

    test('beim Download bleibt eine lokal vorhandene PDF erhalten', () {
      final merged = SyncCodec.withLocalMaterialFields(
        {'id': 'm', 'extractedText': 'neu'},
        {'id': 'm', 'extractedText': 'alt', 'filePath': '/data/folien.pdf'},
      );
      expect(merged, {'id': 'm', 'extractedText': 'neu', 'filePath': '/data/folien.pdf'});
      expect(SyncCodec.withLocalMaterialFields({'id': 'm'}, null), {'id': 'm'});
    });
  });

  group('AutoSyncService.isBlockedByOtherDevice', () {
    test('leere Cloud oder altes Format blockiert nie', () {
      expect(AutoSyncService.isBlockedByOtherDevice(meta: null, lastSyncedPushId: null, deviceId: 'a'), isFalse);
      expect(
        AutoSyncService.isBlockedByOtherDevice(meta: const CloudSyncMeta(), lastSyncedPushId: null, deviceId: 'a'),
        isFalse,
      );
    });

    test('Cloud-Stand ist der zuletzt abgeglichene: hochladen erlaubt', () {
      expect(
        AutoSyncService.isBlockedByOtherDevice(
          meta: const CloudSyncMeta(pushId: 'p1', deviceId: 'b'),
          lastSyncedPushId: 'p1',
          deviceId: 'a',
        ),
        isFalse,
      );
    });

    test('ein anderes Gerät hat seitdem hochgeladen: blockiert', () {
      expect(
        AutoSyncService.isBlockedByOtherDevice(
          meta: const CloudSyncMeta(pushId: 'p2', deviceId: 'b'),
          lastSyncedPushId: 'p1',
          deviceId: 'a',
        ),
        isTrue,
      );
    });

    test('eigener, noch nicht vermerkter Upload blockiert nicht', () {
      expect(
        AutoSyncService.isBlockedByOtherDevice(
          meta: const CloudSyncMeta(pushId: 'p2', deviceId: 'a'),
          lastSyncedPushId: 'p1',
          deviceId: 'a',
        ),
        isFalse,
      );
    });
  });
}
