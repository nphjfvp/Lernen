import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';

Flashcard _base({
  QuestionType type = QuestionType.flashcard,
  List<QuestionType>? variantChain,
  int variantLevel = 0,
  int variantBox = 0,
  int masteryBox = 0,
  List<VariantSnapshot>? pendingVariants,
  String? unitId,
  int variantMissStreak = 0,
}) {
  return Flashcard(
    id: 'f1',
    moduleId: 'm1',
    front: 'Frage',
    back: 'Antwort',
    createdAt: DateTime(2026, 1, 1),
    due: DateTime(2026, 1, 1),
    type: type,
    variantChain: variantChain,
    variantLevel: variantLevel,
    variantBox: variantBox,
    masteryBox: masteryBox,
    pendingVariants: pendingVariants,
    unitId: unitId,
    variantMissStreak: variantMissStreak,
  );
}

void main() {
  group('Flashcard – type/Feld-Defaults', () {
    test('type defaultet auf flashcard, wenn nicht angegeben', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'F',
        back: 'B',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
      );
      expect(card.type, QuestionType.flashcard);
      expect(card.variantChain, isNull);
    });
  });

  group('Flashcard – toMap/fromMap Round-Trip', () {
    test('erhält Typ, Optionen, Varianten-Felder', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'Was ist die Hauptstadt von Frankreich?',
        back: '',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        type: QuestionType.singleChoice,
        options: const [
          QuizOption(text: 'Paris', isCorrect: true),
          QuizOption(text: 'Lyon', isCorrect: false),
        ],
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
        variantLevel: 1,
        variantBox: 2,
      );

      final restored = Flashcard.fromMap(card.toMap());

      expect(restored.type, QuestionType.singleChoice);
      expect(restored.options?.length, 2);
      expect(restored.options?.first.text, 'Paris');
      expect(restored.options?.first.isCorrect, isTrue);
      expect(restored.variantChain, [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText]);
      expect(restored.variantLevel, 1);
      expect(restored.variantBox, 2);
    });

    test('erhält dragPairs und blanks', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'Ordne zu',
        back: '',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        type: QuestionType.dragDrop,
        dragPairs: const [DragPair(source: 'Hund', target: 'Tier')],
        blanks: const ['Lücke1'],
      );
      final restored = Flashcard.fromMap(card.toMap());
      expect(restored.dragPairs?.single.source, 'Hund');
      expect(restored.dragPairs?.single.target, 'Tier');
      expect(restored.blanks, ['Lücke1']);
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne die neuen Felder', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'front': 'F',
        'back': 'B',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'due': DateTime(2026, 1, 1).toIso8601String(),
        'stability': 0.0,
        'difficulty': 0.0,
        'elapsedDays': 0,
        'scheduledDays': 0,
        'reps': 0,
        'lapses': 0,
        'state': 'new',
      };
      final restored = Flashcard.fromMap(legacyMap);
      expect(restored.type, QuestionType.flashcard);
      expect(restored.options, isNull);
      expect(restored.variantChain, isNull);
      expect(restored.variantLevel, 0);
      expect(restored.variantBox, 0);
      expect(restored.unitId, isNull);
    });

    test('erhält unitId', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'F',
        back: 'B',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        unitId: 'u1',
      );
      final restored = Flashcard.fromMap(card.toMap());
      expect(restored.unitId, 'u1');
    });

    test('erhält htmlContent für den html-Typ', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'Frage',
        back: 'Kurzfassung der Lösung',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        type: QuestionType.html,
        htmlContent: '<div>Interaktives Quiz</div>',
      );
      final restored = Flashcard.fromMap(card.toMap());
      expect(restored.type, QuestionType.html);
      expect(restored.htmlContent, '<div>Interaktives Quiz</div>');
    });

    test('htmlContent ist bei älteren Datensätzen ohne das Feld null', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'front': 'F',
        'back': 'B',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'due': DateTime(2026, 1, 1).toIso8601String(),
        'stability': 0.0,
        'difficulty': 0.0,
        'elapsedDays': 0,
        'scheduledDays': 0,
        'reps': 0,
        'lapses': 0,
        'state': 'new',
      };
      final restored = Flashcard.fromMap(legacyMap);
      expect(restored.htmlContent, isNull);
    });

    test('erhält masteryBox und defaultet bei älteren Datensätzen auf 0', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'F',
        back: 'B',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        masteryBox: 3,
      );
      expect(Flashcard.fromMap(card.toMap()).masteryBox, 3);

      final legacyMap = Map<String, dynamic>.from(card.toMap())..remove('masteryBox');
      expect(Flashcard.fromMap(legacyMap).masteryBox, 0);
    });

    test('erhält imageBase64 und ist bei älteren Datensätzen ohne das Feld null', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'F',
        back: 'B',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        imageBase64: 'YWJj',
      );
      expect(Flashcard.fromMap(card.toMap()).imageBase64, 'YWJj');

      final legacyMap = Map<String, dynamic>.from(card.toMap())..remove('imageBase64');
      expect(Flashcard.fromMap(legacyMap).imageBase64, isNull);
    });

    test('erhält priorityIntroduction und defaultet bei älteren Datensätzen auf false', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'F',
        back: 'B',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        priorityIntroduction: true,
      );
      expect(Flashcard.fromMap(card.toMap()).priorityIntroduction, isTrue);

      final legacyMap = Map<String, dynamic>.from(card.toMap())..remove('priorityIntroduction');
      expect(Flashcard.fromMap(legacyMap).priorityIntroduction, isFalse);
    });
  });

  group('Flashcard.answerSummary', () {
    test('Lückentext: Varianten einer Lücke als "a / b", Lücken per "; "', () {
      final card = Flashcard(
        id: 'fb',
        moduleId: 'm1',
        front: 'Die ___ liefert ___.',
        back: '',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        type: QuestionType.fillBlank,
        blanks: const ['Mitochondrium; Mitochondrien', 'ATP'],
      );
      expect(card.answerSummary, 'Mitochondrium / Mitochondrien; ATP');
    });

    test('flashcard nutzt back', () {
      expect(_base().answerSummary, 'Antwort');
    });

    test('choice-Typen nutzen die als richtig markierten Optionen', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'F',
        back: '',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        type: QuestionType.multipleChoice,
        options: const [
          QuizOption(text: 'A', isCorrect: true),
          QuizOption(text: 'B', isCorrect: false),
          QuizOption(text: 'C', isCorrect: true),
        ],
      );
      expect(card.answerSummary, 'A; C');
    });

    test('dragPairs werden als Quelle -> Ziel dargestellt', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'F',
        back: '',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        type: QuestionType.dragDrop,
        dragPairs: const [DragPair(source: 'Hund', target: 'Tier')],
      );
      expect(card.answerSummary, 'Hund -> Tier');
    });

    test('html-Typ nutzt back als Kurzfassung (die eigentliche Prüfung steckt im HTML)', () {
      final card = Flashcard(
        id: '1',
        moduleId: 'm1',
        front: 'F',
        back: 'Kurzfassung der Lösung',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        type: QuestionType.html,
        htmlContent: '<div>Quiz</div>',
      );
      expect(card.answerSummary, 'Kurzfassung der Lösung');
    });
  });

  group('Flashcard.copyWithBoxUpdate – Eskalations-Logik', () {
    test('ohne variantChain wird nie befördert', () {
      final card = _base();
      final result = card.copyWithBoxUpdate(isCorrect: true);
      expect(result.nextType, isNull);
    });

    test('Box steigt bei richtiger Antwort, sinkt bei falscher', () {
      final card = _base(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantBox: 1,
      );
      final correct = card.copyWithBoxUpdate(isCorrect: true);
      expect(correct.card.variantBox, 2);

      final incorrect = card.copyWithBoxUpdate(isCorrect: false);
      expect(incorrect.card.variantBox, 0);
    });

    test('noch nicht grün: keine Beförderung, auch nach vielen richtigen Antworten in Folge', () {
      final card = _base(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantBox: 10,
        masteryBox: Flashcard.masteryBoxCap - 1,
      );
      final result = card.copyWithBoxUpdate(isCorrect: true);
      expect(result.nextType, isNull);
      expect(result.card.variantLevel, 0);
    });

    test('grüne Stufe + falsche Antwort: keine Beförderung', () {
      final card = _base(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        masteryBox: Flashcard.masteryBoxCap,
      );
      expect(card.copyWithBoxUpdate(isCorrect: false).nextType, isNull);
    });

    test('befördert, sobald die Stufe grün ist UND eine nächste Stufe vorhanden ist', () {
      final card = _base(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
        variantLevel: 0,
        masteryBox: Flashcard.masteryBoxCap,
      );
      final result = card.copyWithBoxUpdate(isCorrect: true);
      expect(result.nextType, QuestionType.fillBlank);
      // Box wird bei einer Beförderung zurückgesetzt.
      expect(result.card.variantBox, 0);
    });

    test('Beförderung ohne pendingVariants bleibt lazy (Aufrufer muss die KI bemühen)', () {
      final card = _base(
        type: QuestionType.singleChoice,
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantLevel: 0,
        masteryBox: Flashcard.masteryBoxCap,
      );
      final result = card.copyWithBoxUpdate(isCorrect: true);
      expect(result.needsGeneration, isTrue);
      expect(result.nextType, QuestionType.fillBlank);
      expect(result.card.type, QuestionType.singleChoice); // noch nicht umgewandelt
    });

    test('Beförderung mit pendingVariants passiert sofort, ohne dass der Aufrufer die KI bemühen muss', () {
      final card = Flashcard(
        id: 'f1',
        moduleId: 'm1',
        front: 'Frage leicht',
        back: '',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 1),
        type: QuestionType.singleChoice,
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
        variantLevel: 0,
        masteryBox: Flashcard.masteryBoxCap,
        pendingVariants: const [
          VariantSnapshot(type: QuestionType.fillBlank, front: 'Frage mittel ___', back: '', blanks: ['Lösung']),
          VariantSnapshot(type: QuestionType.freeText, front: 'Frage schwer', back: '', correctText: 'Lösung'),
        ],
      );
      final result = card.copyWithBoxUpdate(isCorrect: true);
      expect(result.needsGeneration, isFalse);
      expect(result.nextType, QuestionType.fillBlank);
      expect(result.card.type, QuestionType.fillBlank);
      expect(result.card.front, 'Frage mittel ___');
      expect(result.card.variantLevel, 1);
      expect(result.card.variantBox, 0);
      expect(result.card.pendingVariants, hasLength(1));
      expect(result.card.pendingVariants!.first.type, QuestionType.freeText);
      expect(result.card.variantHistory, hasLength(1));
      expect(result.card.variantHistory!.first.type, QuestionType.singleChoice);
    });

    test('auf der letzten Stufe wird nicht mehr weiter befördert', () {
      final card = _base(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantLevel: 1, // bereits auf der letzten Stufe
        masteryBox: Flashcard.masteryBoxCap,
      );
      final result = card.copyWithBoxUpdate(isCorrect: true);
      expect(result.nextType, isNull);
      expect(result.card.variantBox, 1);
    });

    test('Box sinkt nicht unter 0', () {
      final card = _base(variantChain: const [QuestionType.singleChoice], variantBox: 0);
      final result = card.copyWithBoxUpdate(isCorrect: false);
      expect(result.card.variantBox, 0);
    });
  });

  group('Flashcard.copyWithPromotedVariant', () {
    test('setzt neuen Typ/Inhalt, erhöht variantLevel, setzt Box zurück', () {
      final card = _base(
        type: QuestionType.singleChoice,
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantLevel: 0,
        variantBox: 3,
        unitId: 'u1',
      );
      final promoted = card.copyWithPromotedVariant(
        newType: QuestionType.fillBlank,
        front: 'Die Hauptstadt von ___ ist ___.',
        blanks: const ['Frankreich', 'Paris'],
      );
      expect(promoted.type, QuestionType.fillBlank);
      expect(promoted.front, 'Die Hauptstadt von ___ ist ___.');
      expect(promoted.blanks, ['Frankreich', 'Paris']);
      expect(promoted.variantLevel, 1);
      expect(promoted.variantBox, 0);
      // FSRS-Zustand bleibt unangetastet.
      expect(promoted.id, card.id);
      expect(promoted.due, card.due);
      // unitId bleibt bei allen copyWith*-Methoden erhalten.
      expect(promoted.unitId, 'u1');
      // Der Inhalt VOR der Beförderung landet in der Historie.
      expect(promoted.variantHistory, hasLength(1));
      expect(promoted.variantHistory!.single.type, QuestionType.singleChoice);
      expect(promoted.variantHistory!.single.front, card.front);
    });
  });

  group('Flashcard.copyWithBoxUpdate – Rückstufung', () {
    test('Fehler-Leiter: erst nach ${Flashcard.fallbackMissStreak} Fehlern in Folge zurück, alter Inhalt kommt wieder',
        () {
      final promoted = _base(
        type: QuestionType.singleChoice,
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
        variantLevel: 0,
        masteryBox: Flashcard.masteryBoxCap,
      ).copyWithPromotedVariant(
        newType: QuestionType.fillBlank,
        front: 'Frage mit ___ Lücke',
        blanks: const ['Lösung'],
      );
      expect(promoted.variantLevel, 1);

      var current = promoted;
      for (var i = 1; i < Flashcard.fallbackMissStreak; i++) {
        final result = current.copyWithBoxUpdate(isCorrect: false);
        expect(result.card.variantLevel, 1, reason: 'nach $i Fehler(n) noch keine Rückstufung');
        expect(result.card.variantMissStreak, i);
        current = result.card;
      }
      final fallback = current.copyWithBoxUpdate(isCorrect: false);
      expect(fallback.card.variantLevel, 0);
      expect(fallback.card.type, QuestionType.singleChoice);
      expect(fallback.card.variantHistory, isEmpty);
      expect(fallback.card.variantMissStreak, 0);
      expect(fallback.nextType, isNull);
    });

    test('auch von der schwersten Stufe nach derselben Leiter zurück, Ampel dann gelb statt null', () {
      final promoted = _base(
        type: QuestionType.singleChoice,
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantLevel: 0,
        masteryBox: Flashcard.masteryBoxCap,
      ).copyWithPromotedVariant(newType: QuestionType.fillBlank, front: 'Frage mit ___ Lücke', blanks: const ['L']);
      var current = promoted;
      for (var i = 1; i < Flashcard.fallbackMissStreak; i++) {
        current = current.copyWithBoxUpdate(isCorrect: false).card;
      }
      final fallback = current.copyWithBoxUpdate(isCorrect: false);
      expect(fallback.card.variantLevel, 0);
      expect(fallback.card.masteryBox, Flashcard.masteryBoxCap - 1);
    });

    test('eine richtige Antwort setzt die Leiter zurück', () {
      final card = _base(variantMissStreak: 3);
      expect(card.copyWithBoxUpdate(isCorrect: true).card.variantMissStreak, 0);
    });

    test('mit Hilfe gewusst (nicht beförderbar) befördert nicht, obwohl grün', () {
      final card = _base(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        masteryBox: Flashcard.masteryBoxCap,
      );
      final result = card.copyWithBoxUpdate(isCorrect: true, promotable: false);
      expect(result.nextType, isNull);
      expect(result.card.variantLevel, 0);
    });

    test('hintsDueFor: ab 2 Fehlern ein Tipp, ab 3 zwei', () {
      expect(Flashcard.hintsDueFor(0), 0);
      expect(Flashcard.hintsDueFor(1), 0);
      expect(Flashcard.hintsDueFor(2), 1);
      expect(Flashcard.hintsDueFor(3), 2);
      expect(Flashcard.hintsDueFor(7), 2);
    });

    test('ohne Historie (Level 0) keine Rückstufung möglich', () {
      final card = _base(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantLevel: 0,
        variantBox: 0,
      );
      final result = card.copyWithBoxUpdate(isCorrect: false);
      expect(result.card.variantLevel, 0);
      expect(result.card.variantBox, 0);
    });

    test('ein einzelner Fehlversuch stuft noch nicht zurück', () {
      final promoted = _base(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantLevel: 0,
        masteryBox: Flashcard.masteryBoxCap,
      ).copyWithPromotedVariant(newType: QuestionType.fillBlank, front: 'Neu', blanks: const ['x']);
      final result = promoted.copyWithBoxUpdate(isCorrect: false);
      expect(result.card.variantLevel, 1);
    });
  });

  group('Flashcard.copyWithDemotedVariant', () {
    test('ohne Historie bleibt die Karte unverändert', () {
      final card = _base();
      expect(card.copyWithDemotedVariant(), same(card));
    });

    test('legt den verlassenen (schwereren) Inhalt in pendingVariants zurück', () {
      final promoted = _base(
        type: QuestionType.singleChoice,
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantLevel: 0,
        masteryBox: Flashcard.masteryBoxCap,
      ).copyWithPromotedVariant(newType: QuestionType.fillBlank, front: 'Frage mittel', blanks: const ['x']);
      final demoted = promoted.copyWithDemotedVariant();
      expect(demoted.type, QuestionType.singleChoice);
      expect(demoted.pendingVariants, hasLength(1));
      expect(demoted.pendingVariants!.first.type, QuestionType.fillBlank);
      expect(demoted.pendingVariants!.first.front, 'Frage mittel');
    });

    test('masteryBoxOverride überschreibt den Ampel-Stand', () {
      final promoted = _base(
        type: QuestionType.singleChoice,
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantLevel: 0,
        masteryBox: 0,
      ).copyWithPromotedVariant(newType: QuestionType.fillBlank, front: 'Frage mittel', blanks: const ['x']);
      final demoted = promoted.copyWithDemotedVariant(masteryBoxOverride: Flashcard.masteryBoxCap - 1);
      expect(demoted.masteryBox, Flashcard.masteryBoxCap - 1);
    });
  });

  group('Flashcard.fromMap – robust gegen unvollständige Datensätze', () {
    test('fehlende FSRS-Felder und Kommazahlen führen nicht zum Absturz', () {
      final card = Flashcard.fromMap({
        'id': 'x',
        'moduleId': 'm1',
        'front': 'F',
        'reps': 3.0,
        'variantLevel': 1.0,
      });
      expect(card.back, '');
      expect(card.reps, 3);
      expect(card.variantLevel, 1);
      expect(card.stability, 0);
      expect(card.state, 'new');
      expect(card.lastReview, isNull);
    });
  });

  group('Flashcard – Quelle und Lerneinheit', () {
    Flashcard card() => Flashcard(
          id: 'c1',
          moduleId: 'm1',
          front: 'Was ist U?',
          back: 'Spannung',
          createdAt: DateTime(2026, 9, 1),
          due: DateTime(2026, 9, 1),
          sourceMaterialId: 'mat1',
          sourcePage: 7,
          miniLesson: 'Kurz erklärt …',
        );

    test('Round-Trip und ältere Datensätze ohne die Felder', () {
      final restored = Flashcard.fromMap(card().toMap());
      expect(restored.sourceMaterialId, 'mat1');
      expect(restored.sourcePage, 7);
      expect(restored.miniLesson, 'Kurz erklärt …');
      final old = card().toMap()..removeWhere((k, _) => k.startsWith('source') || k == 'miniLesson');
      final legacy = Flashcard.fromMap(old);
      expect(legacy.sourceMaterialId, isNull);
      expect(legacy.sourcePage, isNull);
      expect(legacy.miniLesson, isNull);
    });

    test('bleiben beim Lernen, Bearbeiten und Stufenwechsel erhalten', () {
      final reviewed = card().copyWithReview(
        due: DateTime(2026, 9, 3),
        stability: 2,
        difficulty: 5,
        elapsedDays: 0,
        scheduledDays: 2,
        reps: 1,
        lapses: 0,
        state: 'review',
        lastReview: DateTime(2026, 9, 1),
      );
      final edited = reviewed.copyWithContent(front: 'Was ist die Spannung U?');
      final boxed = edited.copyWithBoxUpdate(isCorrect: false).card;
      for (final c in [reviewed, edited, boxed]) {
        expect(c.sourceMaterialId, 'mat1');
        expect(c.sourcePage, 7);
        expect(c.miniLesson, 'Kurz erklärt …');
      }
    });

    test('copyWithStudyAids ergänzt nur, was angegeben ist', () {
      final base = Flashcard(
        id: 'c2',
        moduleId: 'm1',
        front: 'F',
        back: 'B',
        createdAt: DateTime(2026, 9, 1),
        due: DateTime(2026, 9, 5),
        reps: 3,
      );
      final withSource = base.copyWithStudyAids(sourceMaterialId: 'mat2', sourcePage: 4);
      expect(withSource.sourceMaterialId, 'mat2');
      expect(withSource.sourcePage, 4);
      expect(withSource.reps, 3);
      expect(withSource.due, DateTime(2026, 9, 5));
      final withLesson = withSource.copyWithStudyAids(miniLesson: 'Lektion');
      expect(withLesson.miniLesson, 'Lektion');
      expect(withLesson.sourcePage, 4);
    });
  });

  group('Flashcard – Stufe, Gruppe, KI-Hilfestellungen', () {
    test('Round-Trip, ältere Datensätze ohne Felder, kaputte Werte', () {
      final card = _base().copyWithStage(level: 2, group: 'Stücklisten').copyWithHints(const ['Tipp 1']);
      final restored = Flashcard.fromMap(card.toMap());
      expect(restored.stageLevel, 2);
      expect(restored.stageGroup, 'Stücklisten');
      expect(restored.aiHints, ['Tipp 1']);

      final legacy = _base().toMap()
        ..remove('stageLevel')
        ..remove('stageGroup')
        ..remove('aiHints');
      final fromLegacy = Flashcard.fromMap(legacy);
      expect(fromLegacy.stageLevel, isNull);
      expect(fromLegacy.stageGroup, isNull);
      expect(fromLegacy.aiHints, isNull);

      final broken = Flashcard.fromMap({..._base().toMap(), 'stageLevel': 7, 'stageGroup': '  '});
      expect(broken.stageLevel, isNull);
      expect(broken.stageGroup, isNull);
    });

    test('copyWithStage setzt und löscht einzeln', () {
      final card = _base().copyWithStage(level: 1, group: 'G');
      expect(card.copyWithStage(clearLevel: true).stageLevel, isNull);
      expect(card.copyWithStage(clearLevel: true).stageGroup, 'G');
      expect(card.copyWithStage(clearGroup: true).stageGroup, isNull);
      expect(card.copyWithStage(level: 0).stageLevel, 0);
    });

    test('Stufe/Gruppe bleiben über Antworten und Stufenwechsel, Tipps nur bis zum Stufenwechsel', () {
      final card = _base(
        type: QuestionType.singleChoice,
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        masteryBox: Flashcard.masteryBoxCap,
      ).copyWithStage(level: 0, group: 'G').copyWithHints(const ['Tipp']);
      final answered = card.copyWithBoxUpdate(isCorrect: false).card;
      expect(answered.stageGroup, 'G');
      expect(answered.aiHints, ['Tipp']);
      final promoted = card.copyWithPromotedVariant(newType: QuestionType.fillBlank, front: 'x ___', blanks: const ['y']);
      expect(promoted.stageGroup, 'G');
      expect(promoted.aiHints, isNull);
    });

    test('copyWithStageReopened: knapp unter grün, spätestens heute fällig, Leiter von vorn', () {
      final today = DateTime(2026, 3, 10);
      final green = Flashcard(
        id: 'g',
        moduleId: 'm1',
        front: 'F',
        back: 'B',
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 5, 1),
        masteryBox: Flashcard.masteryBoxCap,
        variantMissStreak: 2,
      );
      final reopened = green.copyWithStageReopened(dueBy: today);
      expect(reopened.masteryBox, Flashcard.masteryBoxCap - 1);
      expect(reopened.due, today);
      expect(reopened.variantMissStreak, 0);

      // Ein niedrigerer Stand und eine frühere Fälligkeit bleiben.
      final weak = _base(masteryBox: 1);
      final kept = weak.copyWithStageReopened(dueBy: today);
      expect(kept.masteryBox, 1);
      expect(kept.due, weak.due);
    });
  });

  group('Flashcard.weight – Gewichtung', () {
    Flashcard weighted(double weight) => Flashcard(
          id: 'w1',
          moduleId: 'm1',
          front: 'F',
          back: 'B',
          createdAt: DateTime(2026, 9, 1),
          due: DateTime(2026, 9, 1),
          variantChain: const [QuestionType.singleChoice, QuestionType.freeText],
          weight: weight,
        );

    test('defaultet auf 1.0 und übersteht den Round-Trip', () {
      expect(_base().weight, 1.0);
      expect(Flashcard.fromMap(weighted(1.5).toMap()).weight, 1.5);
    });

    test('ältere Datensätze ohne Feld zählen einfach, kaputte Werte werden begrenzt', () {
      final legacy = weighted(1.5).toMap()..remove('weight');
      expect(Flashcard.fromMap(legacy).weight, 1.0);
      // 0 (oder darunter) heißt stumm; kleine positive Werte werden auf das Minimum gehoben.
      expect(Flashcard.fromMap({...weighted(1).toMap(), 'weight': 0}).weight, 0.0);
      expect(Flashcard.fromMap({...weighted(1).toMap(), 'weight': -3}).weight, 0.0);
      expect(Flashcard.fromMap({...weighted(1).toMap(), 'weight': 0.1}).weight, Flashcard.minWeight);
      expect(Flashcard.fromMap({...weighted(1).toMap(), 'weight': 99}).weight, Flashcard.maxWeight);
    });

    test('Gewicht 0 = stummgeschaltet: übersteht den Round-Trip, wieder einschalten geht', () {
      final muted = weighted(1.5).copyWithWeight(0);
      expect(muted.weight, 0.0);
      expect(muted.isMuted, isTrue);
      expect(Flashcard.fromMap(muted.toMap()).isMuted, isTrue);
      expect(weighted(1.0).isMuted, isFalse);
      final back = muted.copyWithWeight(1.0);
      expect(back.isMuted, isFalse);
      expect(back.weight, 1.0);
    });

    test('copyWithWeight ändert nur das Gewicht, Lernstand bleibt', () {
      final base = weighted(1.0).copyWithReview(
        due: DateTime(2026, 9, 5),
        stability: 4,
        difficulty: 5,
        elapsedDays: 0,
        scheduledDays: 4,
        reps: 2,
        lapses: 0,
        state: 'review',
        lastReview: DateTime(2026, 9, 1),
      );
      final changed = base.copyWithWeight(2.0);
      expect(changed.weight, 2.0);
      expect(changed.reps, 2);
      expect(changed.due, DateTime(2026, 9, 5));
      expect(changed.front, 'F');
    });

    test('bleibt beim Lernen, Bearbeiten und Stufenwechsel erhalten', () {
      final card = weighted(1.5);
      final reviewed = card.copyWithReview(
        due: DateTime(2026, 9, 3),
        stability: 2,
        difficulty: 5,
        elapsedDays: 0,
        scheduledDays: 2,
        reps: 1,
        lapses: 0,
        state: 'review',
        lastReview: DateTime(2026, 9, 1),
      );
      final edited = reviewed.copyWithContent(front: 'F2');
      final boxed = edited.copyWithBoxUpdate(isCorrect: false).card;
      final promoted = edited.copyWithPromotedVariant(newType: QuestionType.freeText, front: 'F3');
      final demoted = promoted.copyWithDemotedVariant();
      final withImage = edited.copyWithImage(clearImage: true);
      final withAids = edited.copyWithStudyAids(miniLesson: 'x');
      for (final c in [reviewed, edited, boxed, promoted, demoted, withImage, withAids]) {
        expect(c.weight, 1.5);
      }
    });
  });
}
