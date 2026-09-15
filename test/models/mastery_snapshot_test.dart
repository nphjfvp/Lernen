import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/mastery_snapshot.dart';

void main() {
  group('MasterySnapshot.greenShare', () {
    test('Anteil grüner an allen eingestuften Karten (ohne neu)', () {
      final snapshot = MasterySnapshot(date: DateTime(2026, 1, 1), red: 2, yellow: 2, green: 6, neu: 10);
      expect(snapshot.greenShare, 0.6);
    });

    test('null, wenn noch keine Karte eingestuft ist', () {
      final snapshot = MasterySnapshot(date: DateTime(2026, 1, 1), red: 0, yellow: 0, green: 0, neu: 5);
      expect(snapshot.greenShare, isNull);
    });
  });

  group('MasterySnapshot.dateKey', () {
    test('formatiert als YYYY-MM-DD, nullgepolstert', () {
      final snapshot = MasterySnapshot(date: DateTime(2026, 3, 5), red: 0, yellow: 0, green: 0, neu: 0);
      expect(snapshot.dateKey, '2026-03-05');
    });
  });

  group('MasterySnapshot – toMap/fromMap Round-Trip', () {
    test('erhält alle Felder inkl. averageRetrievability', () {
      final snapshot = MasterySnapshot(
        date: DateTime(2026, 3, 5),
        red: 1,
        yellow: 2,
        green: 3,
        neu: 4,
        averageRetrievability: 0.87,
      );
      final restored = MasterySnapshot.fromMap(snapshot.toMap());
      expect(restored.date, DateTime(2026, 3, 5));
      expect(restored.red, 1);
      expect(restored.yellow, 2);
      expect(restored.green, 3);
      expect(restored.neu, 4);
      expect(restored.averageRetrievability, 0.87);
    });

    test('averageRetrievability ist null, wenn nicht angegeben', () {
      final snapshot = MasterySnapshot(date: DateTime(2026, 3, 5), red: 0, yellow: 0, green: 0, neu: 0);
      expect(MasterySnapshot.fromMap(snapshot.toMap()).averageRetrievability, isNull);
    });
  });
}
