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

    test('befördert erst, wenn die Schwelle erreicht UND eine nächste Stufe vorhanden ist', () {
      final card = _base(
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
        variantLevel: 0,
        variantBox: Flashcard.promotionThreshold - 1,
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
        variantBox: Flashcard.promotionThreshold - 1,
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
        variantBox: Flashcard.promotionThreshold - 1,
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
        variantBox: Flashcard.promotionThreshold - 1,
      );
      final result = card.copyWithBoxUpdate(isCorrect: true);
      expect(result.nextType, isNull);
      expect(result.card.variantBox, Flashcard.promotionThreshold);
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
    test('zwei Fehlversuche in Folge auf einer beförderten Stufe (NICHT die letzte) stufen zurück', () {
      // Bewusst eine 3-stufige Kette und Beförderung nur bis zur MITTLEREN
      // Stufe: die schwerste Stufe hat eine höhere Schwelle
      // (demotionMissStreakThresholdOnLastStage, siehe eigene Tests unten).
      final promoted = _base(
        type: QuestionType.singleChoice,
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
        variantLevel: 0,
        variantBox: Flashcard.promotionThreshold - 1,
      ).copyWithPromotedVariant(
        newType: QuestionType.fillBlank,
        front: 'Frage mit ___ Lücke',
        blanks: const ['Lösung'],
      );
      expect(promoted.variantLevel, 1);
      expect(promoted.variantBox, 0);

      // Erster Fehlversuch auf der neuen Stufe: Box bleibt bei 0, noch keine Rückstufung.
      final firstMiss = promoted.copyWithBoxUpdate(isCorrect: false);
      expect(firstMiss.card.variantLevel, 1);
      expect(firstMiss.card.variantBox, 0);

      // Zweiter Fehlversuch in Folge: Rückstufung, alter Inhalt kommt zurück.
      final secondMiss = firstMiss.card.copyWithBoxUpdate(isCorrect: false);
      expect(secondMiss.card.variantLevel, 0);
      expect(secondMiss.card.type, QuestionType.singleChoice);
      expect(secondMiss.card.variantHistory, isEmpty);
      expect(secondMiss.nextType, isNull);
    });

    test(
        'auf der schwersten Stufe braucht eine Rückstufung '
        '${Flashcard.demotionMissStreakThresholdOnLastStage} statt '
        '${Flashcard.demotionMissStreakThreshold} Fehlversuche in Folge, '
        'und die Ampel startet danach bei Gelb statt Null', () {
      final promoted = _base(
        type: QuestionType.singleChoice,
        variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank],
        variantLevel: 0,
        variantBox: Flashcard.promotionThreshold - 1,
        masteryBox: Flashcard.masteryBoxCap,
      ).copyWithPromotedVariant(
        newType: QuestionType.fillBlank,
        front: 'Frage mit ___ Lücke',
        blanks: const ['Lösung'],
      );
      expect(promoted.variantLevel, 1); // letzte Stufe der Kette

      var current = promoted;
      for (var i = 0; i < Flashcard.demotionMissStreakThresholdOnLastStage - 1; i++) {
        final result = current.copyWithBoxUpdate(isCorrect: false);
        expect(result.card.variantLevel, 1, reason: 'nach ${i + 1} Fehlversuch(en) noch keine Rückstufung');
        current = result.card;
      }

      final finalMiss = current.copyWithBoxUpdate(isCorrect: false);
      expect(finalMiss.card.variantLevel, 0);
      expect(finalMiss.card.type, QuestionType.singleChoice);
      expect(finalMiss.card.masteryBox, Flashcard.masteryBoxCap - 1);
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
        variantBox: Flashcard.promotionThreshold - 1,
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
        variantBox: Flashcard.promotionThreshold - 1,
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
        variantBox: Flashcard.promotionThreshold - 1,
        masteryBox: 0,
      ).copyWithPromotedVariant(newType: QuestionType.fillBlank, front: 'Frage mittel', blanks: const ['x']);
      final demoted = promoted.copyWithDemotedVariant(masteryBoxOverride: Flashcard.masteryBoxCap - 1);
      expect(demoted.masteryBox, Flashcard.masteryBoxCap - 1);
    });
  });
}
