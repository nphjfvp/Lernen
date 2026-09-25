import 'dart:math';

import '../models/flashcard.dart';

/// Ergebnis einer Probeklausur – klein gehalten, damit der Verlauf lokal
/// gespeichert werden kann (siehe MockExamRepository).
class MockExamResult {
  const MockExamResult({
    required this.moduleId,
    required this.takenAt,
    required this.correct,
    required this.total,
    required this.durationSeconds,
  });

  final String moduleId;
  final DateTime takenAt;
  final int correct;
  final int total;
  final int durationSeconds;

  double get ratio => total == 0 ? 0 : correct / total;
  double get grade => MockExamService.germanGrade(ratio);

  Map<String, dynamic> toMap() => {
        'moduleId': moduleId,
        'takenAt': takenAt.toIso8601String(),
        'correct': correct,
        'total': total,
        'durationSeconds': durationSeconds,
      };

  factory MockExamResult.fromMap(Map<String, dynamic> map) => MockExamResult(
        moduleId: map['moduleId']?.toString() ?? '',
        takenAt: DateTime.tryParse(map['takenAt']?.toString() ?? '') ?? DateTime(1970),
        correct: (map['correct'] as num?)?.toInt() ?? 0,
        total: (map['total'] as num?)?.toInt() ?? 0,
        durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      );
}

/// Trefferquote je Vorlesungseinheit – zeigt nach der Probeklausur, WO die
/// Lücken liegen, nicht nur wie viele.
class UnitScore {
  const UnitScore({required this.unitId, required this.correct, required this.total});

  /// null = Karten ohne Einheit.
  final String? unitId;
  final int correct;
  final int total;

  double get ratio => total == 0 ? 0 : correct / total;
}

/// Reine Logik der Probeklausur: Fragen auswählen, Note berechnen,
/// Auswertung je Einheit.
class MockExamService {
  /// Wie in der Klausur: nur Stoff, der in der Vorlesung schon dran war
  /// (Einheit behandelt oder keine Einheit, gezielt selbst erstellte Fragen
  /// immer), gemischt, höchstens [count] Fragen.
  static List<Flashcard> selectQuestions(
    List<Flashcard> moduleCards, {
    required int count,
    Map<String, bool> unitCoveredById = const {},
    Random? random,
  }) {
    final pool = eligible(moduleCards, unitCoveredById: unitCoveredById)..shuffle(random ?? Random());
    return pool.take(count).toList();
  }

  static List<Flashcard> eligible(List<Flashcard> moduleCards, {Map<String, bool> unitCoveredById = const {}}) {
    return moduleCards.where((c) {
      final unitId = c.unitId;
      if (unitId == null || c.priorityIntroduction) return true;
      return unitCoveredById[unitId] ?? true;
    }).toList();
  }

  /// Wählbare Fragenanzahlen: die Standardgrößen, gedeckelt auf das, was
  /// überhaupt verfügbar ist (ohne Doppelte).
  static List<int> questionCountOptions(int available, {List<int> standard = const [10, 20, 30]}) {
    if (available <= 0) return const [];
    return {for (final n in standard) n < available ? n : available}.toList();
  }

  /// Übliche Notenskala deutscher Hochschulen: ab 50 % bestanden (4,0), in
  /// 5-Prozent-Schritten bis 1,0 ab 95 %.
  static double germanGrade(double ratio) {
    const steps = [
      (0.95, 1.0),
      (0.90, 1.3),
      (0.85, 1.7),
      (0.80, 2.0),
      (0.75, 2.3),
      (0.70, 2.7),
      (0.65, 3.0),
      (0.60, 3.3),
      (0.55, 3.7),
      (0.50, 4.0),
    ];
    for (final (threshold, grade) in steps) {
      if (ratio >= threshold - 1e-9) return grade;
    }
    return 5.0;
  }

  static String formatGrade(double grade) => grade.toStringAsFixed(1).replaceAll('.', ',');

  /// Trefferquote je Einheit, schwächste zuerst. [correctById] enthält jede
  /// gestellte Frage (true/false).
  static List<UnitScore> unitBreakdown(List<Flashcard> questions, Map<String, bool> correctById) {
    final totals = <String?, int>{};
    final corrects = <String?, int>{};
    for (final q in questions) {
      totals[q.unitId] = (totals[q.unitId] ?? 0) + 1;
      if (correctById[q.id] == true) corrects[q.unitId] = (corrects[q.unitId] ?? 0) + 1;
    }
    final scores = [
      for (final e in totals.entries) UnitScore(unitId: e.key, correct: corrects[e.key] ?? 0, total: e.value),
    ]..sort((a, b) => a.ratio.compareTo(b.ratio));
    return scores;
  }
}
