import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/mastery_snapshot.dart';
import 'package:lernen/services/mastery_trend_service.dart';

MasterySnapshot _snap(DateTime date, {int red = 0, int yellow = 0, int green = 0, int neu = 0, double? avg}) =>
    MasterySnapshot(date: date, red: red, yellow: yellow, green: green, neu: neu, averageRetrievability: avg);

void main() {
  final today = DateTime(2026, 6, 8);

  test('liefert null ohne jede Historie', () {
    expect(MasteryTrendService.compare(today: _snap(today), history: const []), isNull);
  });

  test('ignoriert Einträge von heute oder aus der Zukunft', () {
    final history = [_snap(today), _snap(today.add(const Duration(days: 1)))];
    expect(MasteryTrendService.compare(today: _snap(today), history: history), isNull);
  });

  test('findet den Schnappschuss genau 7 Tage zurück als Wochenvergleich', () {
    final weekAgo = today.subtract(const Duration(days: 7));
    final history = [
      _snap(today.subtract(const Duration(days: 1))),
      _snap(weekAgo, red: 5, yellow: 3, green: 2, avg: 0.70),
      _snap(today.subtract(const Duration(days: 20))),
    ];
    final trend = MasteryTrendService.compare(
      today: _snap(today, red: 1, yellow: 3, green: 6, avg: 0.85),
      history: history,
    );
    expect(trend, isNotNull);
    expect(trend!.daysAgo, 7);
    expect(trend.retrievabilityDelta, closeTo(0.15, 1e-9));
    // damals: 2/10=0.2, heute: 6/10=0.6 -> Delta 0.4
    expect(trend.greenShareDelta, closeTo(0.4, 1e-9));
  });

  test('wählt den Schnappschuss, der am nächsten am Ziel-Abstand liegt', () {
    final history = [
      _snap(today.subtract(const Duration(days: 3))),
      _snap(today.subtract(const Duration(days: 9))),
    ];
    final trend = MasteryTrendService.compare(today: _snap(today), history: history, targetDaysAgo: 7);
    // 9 Tage liegt näher an 7 als 3 Tage (Abstand 2 vs 4).
    expect(trend!.daysAgo, 9);
  });

  test('Deltas sind null, wenn Behaltensrate an einem der Zeitpunkte fehlt', () {
    final weekAgo = today.subtract(const Duration(days: 7));
    final trend = MasteryTrendService.compare(
      today: _snap(today, avg: 0.9),
      history: [_snap(weekAgo)], // kein avg
    );
    expect(trend!.retrievabilityDelta, isNull);
  });

  test('greenShareDelta ist null, wenn damals noch keine Karte eingestuft war', () {
    final weekAgo = today.subtract(const Duration(days: 7));
    final trend = MasteryTrendService.compare(
      today: _snap(today, red: 1, green: 1),
      history: [_snap(weekAgo, neu: 10)], // alle Karten noch "neu"
    );
    expect(trend!.greenShareDelta, isNull);
  });
}
