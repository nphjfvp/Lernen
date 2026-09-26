import 'calendar_days.dart';
import '../models/mastery_snapshot.dart';

/// Vergleich des heutigen Stands mit einem Schnappschuss aus der Vergangenheit
/// – Grundlage für die Trend-Anzeige in StatsScreen ("mehr Grün als vor einer
/// Woche"). Bewusst als reiner Kompetenz-Vergleich mit dem EIGENEN früheren
/// Stand statt mit anderen Nutzern (Selbstbestimmungstheorie: Feedback zur
/// eigenen Entwicklung motiviert nachhaltiger als sozialer Vergleich/
/// Leaderboards, siehe Deci & Ryan).
class MasteryTrend {
  const MasteryTrend({
    required this.daysAgo,
    this.retrievabilityDelta,
    this.greenShareDelta,
  });

  /// Tatsächlicher Abstand zum gefundenen Vergleichs-Schnappschuss (kann vom
  /// gewünschten Zielwert abweichen, wenn z.B. an genau diesem Tag kein
  /// Schnappschuss vorliegt).
  final int daysAgo;

  /// Heutige minus damalige Ø-Behaltensrate (positiv = besser als damals).
  /// Null, wenn für einen der beiden Zeitpunkte kein Wert vorlag.
  final double? retrievabilityDelta;

  /// Heutiger minus damaliger Grün-Anteil (siehe MasterySnapshot.greenShare).
  final double? greenShareDelta;
}

class MasteryTrendService {
  MasteryTrendService._();

  /// Sucht in [history] den Schnappschuss, der am nächsten an
  /// [targetDaysAgo] Tage VOR [today] liegt (Standard: Wochenvergleich), und
  /// vergleicht ihn mit [today]. Liefert `null`, wenn [history] keinen
  /// Eintrag aus der echten Vergangenheit enthält (z.B. erste Woche der
  /// Nutzung – noch keine Vergleichsbasis).
  static MasteryTrend? compare({
    required MasterySnapshot today,
    required List<MasterySnapshot> history,
    int targetDaysAgo = 7,
  }) {
    MasterySnapshot? reference;
    int? bestDistanceToTarget;
    for (final snapshot in history) {
      final daysAgo = calendarDaysBetween(snapshot.date, today.date);
      if (daysAgo <= 0) continue; // nur echte Vergangenheit, nicht heute/Zukunft
      final distanceToTarget = (daysAgo - targetDaysAgo).abs();
      if (bestDistanceToTarget == null || distanceToTarget < bestDistanceToTarget) {
        bestDistanceToTarget = distanceToTarget;
        reference = snapshot;
      }
    }
    if (reference == null) return null;

    double? retrievabilityDelta;
    if (today.averageRetrievability != null && reference.averageRetrievability != null) {
      retrievabilityDelta = today.averageRetrievability! - reference.averageRetrievability!;
    }
    double? greenShareDelta;
    if (today.greenShare != null && reference.greenShare != null) {
      greenShareDelta = today.greenShare! - reference.greenShare!;
    }

    return MasteryTrend(
      daysAgo: calendarDaysBetween(reference.date, today.date),
      retrievabilityDelta: retrievabilityDelta,
      greenShareDelta: greenShareDelta,
    );
  }
}
