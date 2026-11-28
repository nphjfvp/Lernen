import 'package:sembast/sembast.dart';

import '../models/flashcard.dart';
import '../services/answer_signals.dart';
import '../services/database_service.dart';
import '../services/fsrs_service.dart';

/// Eine verbuchte Antwort (siehe CardReviewMixin.recordReview): Ergebnis,
/// Signale (Sicherheit, „Weiß ich nicht“, Tipp-Stufe) und der FSRS-Stand
/// VOR der Antwort. Grundlage für Kalibrierung und Fehlvorstellungen – und
/// später für FSRS-Parameter, die zu einem selbst passen.
class ReviewLogEntry {
  const ReviewLogEntry({
    required this.cardId,
    required this.moduleId,
    required this.at,
    required this.grade,
    this.correct,
    this.confidence,
    this.dontKnow = false,
    this.hintLevel = 0,
    this.variant = false,
    this.type = '',
    this.stateBefore = '',
    this.stabilityBefore = 0,
    this.difficultyBefore = 0,
    this.elapsedDays = 0,
    this.errorCause,
    this.errorStep,
  });

  final String cardId;
  final String moduleId;
  final DateTime at;
  final Grade grade;

  /// Automatisch geprüft: richtig/falsch; selbst bewertet: null.
  final bool? correct;
  final AnswerConfidence? confidence;
  final bool dontKnow;
  final int hintLevel;
  final bool variant;
  final String type;
  final String stateBefore;
  final double stabilityBefore;
  final double difficultyBefore;

  /// Kalendertage seit der vorigen Wiederholung (0 bei einer neuen Karte).
  final int elapsedDays;

  /// Rechenweg auf Papier (Panik-Modus): Ursache und Schritt des ersten Fehlers.
  final ErrorCause? errorCause;
  final int? errorStep;

  bool get confidentMiss =>
      AnswerSignals.isConfidentMiss(isCorrect: correct, signals: AnswerSignals(confidence: confidence, dontKnow: dontKnow));

  factory ReviewLogEntry.of(
    Flashcard before, {
    required Grade grade,
    bool? correct,
    AnswerSignals signals = AnswerSignals.none,
    DateTime? at,
  }) {
    final when = at ?? DateTime.now();
    final last = before.lastReview;
    return ReviewLogEntry(
      cardId: before.id,
      moduleId: before.moduleId,
      at: when,
      grade: grade,
      correct: correct,
      confidence: signals.confidence,
      dontKnow: signals.dontKnow,
      hintLevel: signals.hintLevel,
      variant: signals.variant,
      type: before.type.name,
      stateBefore: before.state,
      stabilityBefore: before.stability,
      difficultyBefore: before.difficulty,
      elapsedDays: last == null ? 0 : _days(last, when),
      errorCause: signals.errorCause,
      errorStep: signals.errorStep,
    );
  }

  static int _days(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  Map<String, dynamic> toMap() => {
        'cardId': cardId,
        'moduleId': moduleId,
        'at': at.toIso8601String(),
        'grade': grade.name,
        if (correct != null) 'correct': correct,
        if (confidence != null) 'confidence': confidence!.key,
        if (dontKnow) 'dontKnow': true,
        if (hintLevel > 0) 'hintLevel': hintLevel,
        if (variant) 'variant': true,
        'type': type,
        'stateBefore': stateBefore,
        'stabilityBefore': stabilityBefore,
        'difficultyBefore': difficultyBefore,
        'elapsedDays': elapsedDays,
        if (errorCause != null) 'errorCause': errorCause!.name,
        if (errorStep != null) 'errorStep': errorStep,
      };

  factory ReviewLogEntry.fromMap(Map<String, dynamic> map) {
    Grade grade = Grade.good;
    for (final g in Grade.values) {
      if (g.name == map['grade']) grade = g;
    }
    double num0(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final correct = map['correct'];
    return ReviewLogEntry(
      cardId: '${map['cardId'] ?? ''}',
      moduleId: '${map['moduleId'] ?? ''}',
      at: DateTime.tryParse('${map['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      grade: grade,
      correct: correct is bool ? correct : null,
      confidence: AnswerConfidence.fromKey(map['confidence']),
      dontKnow: map['dontKnow'] == true,
      hintLevel: (map['hintLevel'] as num?)?.toInt() ?? 0,
      variant: map['variant'] == true,
      type: '${map['type'] ?? ''}',
      stateBefore: '${map['stateBefore'] ?? ''}',
      stabilityBefore: num0(map['stabilityBefore']),
      difficultyBefore: num0(map['difficultyBefore']),
      elapsedDays: (map['elapsedDays'] as num?)?.toInt() ?? 0,
      errorCause: ErrorCause.fromKey(map['errorCause']),
      errorStep: (map['errorStep'] as num?)?.toInt(),
    );
  }
}

/// Trefferquote je Sicherheitsstufe – „wenn du ‚sicher‘ sagst, liegst du zu
/// x % richtig“.
class CalibrationBucket {
  const CalibrationBucket(this.confidence, this.total, this.correct);

  final AnswerConfidence confidence;
  final int total;
  final int correct;

  double? get rate => total == 0 ? null : correct / total;
}

/// Auswertungen des Antwort-Protokolls (rein, testbar).
class ReviewLogAnalysis {
  ReviewLogAnalysis._();

  /// Nur automatisch geprüfte Antworten mit angegebener Sicherheit zählen.
  static List<CalibrationBucket> calibration(Iterable<ReviewLogEntry> entries) {
    return [
      for (final level in AnswerConfidence.values)
        () {
          final rated = entries.where((e) => e.confidence == level && e.correct != null && !e.dontKnow);
          return CalibrationBucket(level, rated.length, rated.where((e) => e.correct == true).length);
        }(),
    ];
  }

  /// Karten, deren LETZTE Antwort sicher und falsch war – Kandidaten für eine
  /// Fehlvorstellung (nicht nur eine Lücke). Eine spätere richtige Antwort
  /// hebt das wieder auf.
  static Set<String> confidentMissCards(Iterable<ReviewLogEntry> entries) {
    final latest = <String, ReviewLogEntry>{};
    for (final e in entries) {
      final known = latest[e.cardId];
      if (known == null || !e.at.isBefore(known.at)) latest[e.cardId] = e;
    }
    return {for (final e in latest.values) if (e.confidentMiss) e.cardId};
  }
}

/// Antwort-Protokoll dieses Geräts (Store `review_log`). Wird nicht
/// synchronisiert und ist auf [maxEntries] Einträge begrenzt.
class ReviewLogRepository {
  ReviewLogRepository._();

  static const int maxEntries = 20000;

  static final _store = DatabaseService.reviewLog;

  static Future<void> add(ReviewLogEntry entry) async {
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) => addIn(txn, entry));
  }

  static Future<void> addIn(DatabaseClient client, ReviewLogEntry entry) async {
    final key = '${entry.at.microsecondsSinceEpoch.toString().padLeft(20, '0')}-${entry.cardId}';
    await _store.record(key).put(client, entry.toMap());
    final count = await _store.count(client);
    if (count > maxEntries) {
      final oldest = await _store.findKeys(client, finder: Finder(sortOrders: [SortOrder(Field.key)], limit: count - maxEntries));
      await _store.records(oldest).delete(client);
    }
  }

  static Future<List<ReviewLogEntry>> load({String? moduleId}) async {
    final db = await DatabaseService.instance.database;
    return loadFrom(db, moduleId: moduleId);
  }

  static Future<List<ReviewLogEntry>> loadFrom(DatabaseClient client, {String? moduleId}) async {
    final records = await _store.find(
      client,
      finder: Finder(
        filter: moduleId == null ? null : Filter.equals('moduleId', moduleId),
        sortOrders: [SortOrder(Field.key)],
      ),
    );
    return [for (final r in records) ReviewLogEntry.fromMap(r.value)];
  }

  /// Beim Löschen eines Fachs (siehe ModuleRepository) mit aufräumen.
  static Future<void> deleteModuleIn(DatabaseClient client, String moduleId) async {
    await _store.delete(client, finder: Finder(filter: Filter.equals('moduleId', moduleId)));
  }
}
