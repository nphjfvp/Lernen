import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/review_log_repository.dart';
import 'package:lernen/services/answer_signals.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/services/review_service.dart';

Flashcard _card({String id = 'c1', int reps = 1, int box = 1}) => Flashcard(
      id: id,
      moduleId: 'm1',
      front: 'Frage',
      back: 'Antwort',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      type: QuestionType.singleChoice,
      options: const [QuizOption(text: 'A', isCorrect: true), QuizOption(text: 'B', isCorrect: false)],
      reps: reps,
      masteryBox: box,
      state: reps == 0 ? 'new' : 'review',
      stability: reps == 0 ? 0 : 3,
      difficulty: 5,
      lastReview: reps == 0 ? null : DateTime(2026, 1, 5),
    );

void main() {
  group('AnswerSignals.gradeFor', () {
    test('ohne Signale wie bisher: richtig = Gut, falsch = Nochmal', () {
      expect(AnswerSignals.gradeFor(isCorrect: true), Grade.good);
      expect(AnswerSignals.gradeFor(isCorrect: false), Grade.again);
      expect(AnswerSignals.gradeFor(selfGrade: Grade.easy), Grade.easy);
    });

    test('„Weiß ich nicht“ zählt immer als Nochmal', () {
      expect(AnswerSignals.gradeFor(isCorrect: true, signals: const AnswerSignals(dontKnow: true)), Grade.again);
    });

    test('richtig, aber geraten → höchstens Schwer', () {
      const guessed = AnswerSignals(confidence: AnswerConfidence.guessed);
      expect(AnswerSignals.gradeFor(isCorrect: true, signals: guessed), Grade.hard);
      expect(AnswerSignals.gradeFor(isCorrect: false, signals: guessed), Grade.again);
      expect(AnswerSignals.gradeFor(isCorrect: true, signals: const AnswerSignals(confidence: AnswerConfidence.sure)),
          Grade.good);
    });

    test('Tipp-Leiter: Stufe 1 kostet nichts, 2–3 → Schwer, ab 4 → Nochmal', () {
      expect(AnswerSignals.gradeFor(isCorrect: true, signals: const AnswerSignals(hintLevel: 1)), Grade.good);
      expect(AnswerSignals.gradeFor(isCorrect: true, signals: const AnswerSignals(hintLevel: 2)), Grade.hard);
      expect(AnswerSignals.gradeFor(isCorrect: true, signals: const AnswerSignals(hintLevel: 3)), Grade.hard);
      expect(AnswerSignals.gradeFor(isCorrect: true, signals: const AnswerSignals(hintLevel: 4)), Grade.again);
      // Selbst bewertet: Hilfe deckelt auch dort.
      expect(AnswerSignals.gradeFor(selfGrade: Grade.easy, signals: const AnswerSignals(hintLevel: 2)), Grade.hard);
      expect(AnswerSignals.gradeFor(selfGrade: Grade.good, signals: const AnswerSignals(hintLevel: 5)), Grade.again);
    });

    test('Tabelle fast richtig (Schwer) bleibt Schwer', () {
      expect(AnswerSignals.gradeFor(isCorrect: true, selfGrade: Grade.hard), Grade.hard);
    });

    test('sicher und falsch = mögliche Fehlvorstellung, „Weiß ich nicht“ nicht', () {
      const sure = AnswerSignals(confidence: AnswerConfidence.sure);
      expect(AnswerSignals.isConfidentMiss(isCorrect: false, signals: sure), isTrue);
      expect(AnswerSignals.isConfidentMiss(isCorrect: true, signals: sure), isFalse);
      expect(
        AnswerSignals.isConfidentMiss(isCorrect: false, signals: const AnswerSignals(confidence: AnswerConfidence.sure, dontKnow: true)),
        isFalse,
      );
    });
  });

  group('ReviewService mit Signalen', () {
    test('geraten richtig: Ampel steigt nicht, kein Fehler', () {
      final outcome = ReviewService().evaluate(
        _card(box: 1),
        isCorrect: true,
        now: DateTime(2026, 1, 10),
        signals: const AnswerSignals(confidence: AnswerConfidence.guessed),
      );
      expect(outcome.wasWrong, isFalse);
      expect(outcome.card.masteryBox, 1);
    });

    test('Tipp Stufe 4: richtig, zählt aber als nicht gewusst (Wiederholungsrunde)', () {
      final outcome = ReviewService().evaluate(
        _card(box: 2),
        isCorrect: true,
        now: DateTime(2026, 1, 10),
        signals: const AnswerSignals(hintLevel: 4),
      );
      expect(outcome.wasWrong, isTrue);
      expect(outcome.card.masteryBox, 1);
    });

    test('„Weiß ich nicht“ ohne Ergebnis wird als falsch verbucht', () {
      final outcome = ReviewService().evaluate(
        _card(box: 2),
        now: DateTime(2026, 1, 10),
        signals: const AnswerSignals(dontKnow: true),
      );
      expect(outcome.wasWrong, isTrue);
    });
  });

  group('Antwort-Protokoll', () {
    test('Eintrag hält Signale und Stand vor der Antwort fest, übersteht toMap/fromMap', () {
      final entry = ReviewLogEntry.of(
        _card(),
        grade: Grade.again,
        correct: false,
        signals: const AnswerSignals(confidence: AnswerConfidence.sure, hintLevel: 2),
        at: DateTime(2026, 1, 8, 12),
      );
      expect(entry.elapsedDays, 3);
      expect(entry.stateBefore, 'review');
      final back = ReviewLogEntry.fromMap(entry.toMap());
      expect(back.confidence, AnswerConfidence.sure);
      expect(back.hintLevel, 2);
      expect(back.grade, Grade.again);
      expect(back.correct, isFalse);
      expect(back.confidentMiss, isTrue);
    });

    test('Kalibrierung: Trefferquote je Sicherheitsstufe, ohne Selbstbewertung und „Weiß ich nicht“', () {
      ReviewLogEntry e(AnswerConfidence? c, bool? correct, {bool dontKnow = false}) => ReviewLogEntry(
            cardId: 'x',
            moduleId: 'm',
            at: DateTime(2026),
            grade: Grade.good,
            correct: correct,
            confidence: c,
            dontKnow: dontKnow,
          );
      final buckets = ReviewLogAnalysis.calibration([
        e(AnswerConfidence.sure, true),
        e(AnswerConfidence.sure, true),
        e(AnswerConfidence.sure, false),
        e(AnswerConfidence.guessed, false),
        e(AnswerConfidence.sure, null), // selbst bewertet
        e(AnswerConfidence.sure, false, dontKnow: true),
        e(null, true),
      ]);
      final sure = buckets.firstWhere((b) => b.confidence == AnswerConfidence.sure);
      expect(sure.total, 3);
      expect(sure.correct, 2);
      expect(buckets.firstWhere((b) => b.confidence == AnswerConfidence.guessed).rate, 0);
      expect(buckets.firstWhere((b) => b.confidence == AnswerConfidence.unsure).rate, isNull);
    });

    test('Fehlvorstellung: nur, wenn die LETZTE Antwort sicher und falsch war', () {
      ReviewLogEntry e(String card, int day, bool correct) => ReviewLogEntry(
            cardId: card,
            moduleId: 'm',
            at: DateTime(2026, 1, day),
            grade: correct ? Grade.good : Grade.again,
            correct: correct,
            confidence: AnswerConfidence.sure,
          );
      final cards = ReviewLogAnalysis.confidentMissCards([e('a', 1, false), e('a', 2, true), e('b', 3, false)]);
      expect(cards, {'b'});
    });
  });

  group('Denkfehler je Option', () {
    test('parseOptions liest why/misconception, toMap/fromMap behalten es', () {
      final options = QuestionParsing.parseOptions([
        {'text': 'A', 'isCorrect': true},
        {'text': 'B', 'isCorrect': false, 'why': 'verwechselt Masse und Gewicht'},
        {'text': 'C', 'isCorrect': false, 'misconception': 'Vorzeichen vertauscht'},
      ])!;
      expect(options[0].hasWhy, isFalse);
      expect(options[1].why, 'verwechselt Masse und Gewicht');
      expect(options[2].why, 'Vorzeichen vertauscht');
      expect(QuizOption.fromMap(options[1].toMap()).why, 'verwechselt Masse und Gewicht');
    });

    test('canonicalize behält den Denkfehler bei abweichend geformten Optionen', () {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'single_choice',
        'front': 'Was gilt?',
        'options': [
          {'option': 'A', 'correct': true},
          {'option': 'B', 'correct': false, 'denkfehler': 'nur Spezialfall'},
          {'option': 'C', 'correct': false},
        ],
      });
      final options = QuestionParsing.parseOptions(fixed!['options'])!;
      expect(options[1].why, 'nur Spezialfall');
    });
  });
}
