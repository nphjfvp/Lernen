import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/sync_cloud_history.dart';

CloudStateEntry _entry(String id, {String device = 'pc', DateTime? at, int parts = 1}) =>
    CloudStateEntry(pushId: id, partCount: parts, deviceId: device, at: at ?? DateTime(2026, 9, 1), modules: 2, flashcards: 40);

void main() {
  group('CloudStateEntry', () {
    test('Round-Trip über toMap/fromMap', () {
      final entry = _entry('p1', at: DateTime(2026, 9, 29, 14, 5), parts: 3);
      final back = CloudStateEntry.fromMap(entry.toMap())!;
      expect(back.pushId, 'p1');
      expect(back.partCount, 3);
      expect(back.deviceId, 'pc');
      expect(back.at, DateTime(2026, 9, 29, 14, 5));
      expect((back.modules, back.flashcards), (2, 40));
    });

    test('kaputte Einträge werden übergangen', () {
      final list = CloudStateEntry.listFrom([
        _entry('ok').toMap(),
        {'pushId': '', 'partCount': 1},
        {'pushId': 'ohne-teile', 'partCount': 0},
        'unsinn',
        null,
      ]);
      expect(list.map((e) => e.pushId), ['ok']);
      expect(CloudStateEntry.listFrom(null), isEmpty);
    });
  });

  group('planCloudHistory', () {
    test('Stand eines anderen Geräts wird aufgehoben, auch wenn er gerade erst entstand', () {
      final plan = planCloudHistory(
        existing: [_entry('alt', at: DateTime(2026, 9, 30, 8))],
        previous: _entry('vom-pc', device: 'pc', at: DateTime(2026, 9, 30, 8, 5)),
        newDeviceId: 'handy',
      );
      expect(plan.retired?.pushId, 'vom-pc');
      expect(plan.keep.map((e) => e.pushId), ['vom-pc', 'alt']);
      expect(plan.drop, isEmpty);
    });

    test('eigene Uploads füllen den Verlauf nicht, solange der letzte Eintrag jung ist', () {
      final plan = planCloudHistory(
        existing: [_entry('alt', at: DateTime(2026, 9, 30, 8))],
        previous: _entry('eigener', device: 'handy', at: DateTime(2026, 9, 30, 9)),
        newDeviceId: 'handy',
      );
      expect(plan.retired, isNull);
      expect(plan.keep.map((e) => e.pushId), ['alt']);
    });

    test('ein eigener Stand wird nach einem Tag Abstand doch aufgehoben', () {
      final plan = planCloudHistory(
        existing: [_entry('alt', at: DateTime(2026, 9, 28, 8))],
        previous: _entry('eigener', device: 'handy', at: DateTime(2026, 9, 29, 9)),
        newDeviceId: 'handy',
      );
      expect(plan.retired?.pushId, 'eigener');
    });

    test('der erste Stand kommt immer in den leeren Verlauf', () {
      final plan = planCloudHistory(existing: const [], previous: _entry('erster', device: 'handy'), newDeviceId: 'handy');
      expect(plan.retired?.pushId, 'erster');
    });

    test('force: auch der Stand desselben Geräts wird aufgehoben (Wiederherstellen)', () {
      final plan = planCloudHistory(
        existing: [_entry('alt', at: DateTime(2026, 9, 30, 8))],
        previous: _entry('eigener', device: 'handy', at: DateTime(2026, 9, 30, 9)),
        newDeviceId: 'handy',
        force: true,
      );
      expect(plan.retired?.pushId, 'eigener');
    });

    test('nur die letzten fünf bleiben, ältere fallen heraus', () {
      final existing = [for (var i = 5; i >= 1; i--) _entry('e$i', at: DateTime(2026, 9, i))];
      final plan = planCloudHistory(existing: existing, previous: _entry('neu', device: 'pc'), newDeviceId: 'handy');
      expect(plan.keep.map((e) => e.pushId), ['neu', 'e5', 'e4', 'e3', 'e2']);
      expect(plan.drop.map((e) => e.pushId), ['e1']);
    });

    test('kein bisheriger Stand oder schon im Verlauf: nichts Neues', () {
      final e = _entry('x');
      expect(planCloudHistory(existing: [e], previous: null, newDeviceId: 'a').keep, [e]);
      final again = planCloudHistory(existing: [e], previous: e, newDeviceId: 'a', force: true);
      expect(again.retired, isNull);
      expect(again.keep, [e]);
    });

    test('ohne Zeitangabe wird vorsichtshalber aufgehoben', () {
      final plan = planCloudHistory(
        existing: [_entry('alt')],
        previous: const CloudStateEntry(pushId: 'ohne-zeit', partCount: 1, deviceId: 'handy'),
        newDeviceId: 'handy',
      );
      expect(plan.retired?.pushId, 'ohne-zeit');
    });
  });
}
