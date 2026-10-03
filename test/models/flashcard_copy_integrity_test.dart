import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';

/// Eine Karte, bei der JEDES Feld einen ungewöhnlichen Wert hat. Fügt jemand ein
/// Feld hinzu und vergisst es hier, schlägt der erste Test fehl – damit eine
/// der vielen Kopier-Methoden das neue Feld nicht stillschweigend verliert.
Flashcard _full() {
  const snapshot = VariantSnapshot(type: QuestionType.singleChoice, front: 'alt', back: 'alt-b');
  return Flashcard(
    id: 'c1',
    moduleId: 'm1',
    conceptId: 'k1',
    front: 'Frage ___',
    back: 'Antwort',
    createdAt: DateTime(2026, 1, 2, 3, 4, 5),
    due: DateTime(2026, 5, 6),
    type: QuestionType.fillBlank,
    options: const [QuizOption(text: 'a', isCorrect: true), QuizOption(text: 'b', isCorrect: false)],
    correctText: 'Muster',
    blanks: const ['x'],
    dragPairs: const [DragPair(source: 's', target: 't')],
    htmlContent: '<p>x</p>',
    imageBase64: 'AAAA',
    imageTargets: const [ImageTarget(x: .1, y: .2, w: .3, h: .4, label: 'L', group: 'g')],
    tableRows: const [
      [QuestionTableCell(text: 'a'), QuestionTableCell(text: 'b', given: false)],
    ],
    variantChain: const [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText],
    variantLevel: 1,
    variantBox: 2,
    variantHistory: const [snapshot],
    pendingVariants: const [snapshot],
    variantMissStreak: 3,
    masteryBox: 2,
    stability: 4.5,
    difficulty: 6.5,
    elapsedDays: 7,
    scheduledDays: 8,
    reps: 9,
    lapses: 1,
    state: 'review',
    lastReview: DateTime(2026, 4, 1),
    unitId: 'u1',
    priorityIntroduction: true,
    needsCalculator: true,
    calcDeferredAt: DateTime(2026, 4, 2),
    sourceMaterialId: 'mat',
    sourcePage: 12,
    scriptMaterialId: 'script',
    scriptPage: 34,
    miniLesson: 'Lerneinheit',
    weight: 2.5,
    stageLevel: 1,
    stageGroup: 'Gruppe',
    aiHints: const ['Tipp 1'],
  );
}

Set<String> _diff(Flashcard a, Flashcard b) {
  final ma = a.toMap(), mb = b.toMap();
  return {
    for (final k in {...ma.keys, ...mb.keys})
      if ('${ma[k]}' != '${mb[k]}') k,
  };
}

void main() {
  test('Testkarte füllt wirklich jedes Feld (neues Feld → hier ergänzen)', () {
    final map = _full().toMap();
    final empty = [for (final e in map.entries) if (e.value == null) e.key];
    expect(empty, isEmpty, reason: 'Diese Felder sind in _full() nicht gesetzt: $empty');
    // Und toMap/fromMap verliert nichts.
    expect(_diff(_full(), Flashcard.fromMap(map)), isEmpty);
  });

  group('Kopier-Methoden verlieren keine Felder (nur das Gewollte ändert sich)', () {
    final card = _full();

    test('copyWithReview: nur Lernstand, und die Rechenaufgaben-Zurückstellung wird gelöscht', () {
      final r = card.copyWithReview(
        due: DateTime(2027),
        stability: 1,
        difficulty: 2,
        elapsedDays: 3,
        scheduledDays: 4,
        reps: 5,
        lapses: 6,
        state: 'learning',
        lastReview: DateTime(2026, 9, 9),
        masteryBox: 1,
      );
      expect(_diff(card, r), {
        'due', 'stability', 'difficulty', 'elapsedDays', 'scheduledDays', 'reps', 'lapses', 'state', 'lastReview',
        'masteryBox', 'calcDeferredAt',
      });
    });

    test('copyWithContent: Inhalt ja, alles andere bleibt (Hilfen werden nur bei geänderter Frage verworfen)', () {
      expect(_diff(card, card.copyWithContent(options: const [QuizOption(text: 'z', isCorrect: true)])), {'options'});
      expect(_diff(card, card.copyWithContent(back: 'Neu')), {'back'}); // answerSummary hängt bei fillBlank an blanks
      final changedQuestion = card.copyWithContent(front: 'Andere Frage ___');
      expect(_diff(card, changedQuestion), {'front', 'aiHints'});
      expect(changedQuestion.aiHints, isNull);
      expect(_diff(card, card.copyWithContent(clearImage: true)), {'imageBase64'});
    });

    test('Ein-Feld-Kopien ändern genau ein Feld', () {
      expect(_diff(card, card.copyWithWeight(3.5)), {'weight'});
      expect(_diff(card, card.copyWithUnit('u2')), {'unitId'});
      expect(_diff(card, card.copyWithUnit(null)), {'unitId'});
      expect(_diff(card, card.copyWithCalculator(false)), {'needsCalculator'});
      expect(_diff(card, card.copyWithCalculator(null)), {'needsCalculator'});
      expect(_diff(card, card.copyWithCalcDeferred(DateTime(2026, 9, 9))), {'calcDeferredAt'});
      expect(_diff(card, card.copyWithCalcDeferred(null)), {'calcDeferredAt'});
      expect(_diff(card, card.copyWithHints(const ['a', 'b'])), {'aiHints'});
      expect(_diff(card, card.copyWithMissStreak(0)), {'variantMissStreak'});
      expect(_diff(card, card.copyWithScript(materialId: 'x', page: 5)), {'scriptMaterialId', 'scriptPage'});
      expect(_diff(card, card.copyWithStage(level: 2, group: 'Neu')), {'stageLevel', 'stageGroup'});
      expect(_diff(card, card.copyWithStudyAids(miniLesson: 'Neu')), {'miniLesson'});
      expect(_diff(card, card.copyWithStudyAids(sourceMaterialId: 'm2', sourcePage: 3)),
          {'sourceMaterialId', 'sourcePage'});
    });

    test('copyWithStageReopened ändert nur Ampel-Stand, Fälligkeit und Fehler-Leiter', () {
      final r = card.copyWithStageReopened(dueBy: DateTime(2026, 1, 1));
      expect(_diff(card, r).difference({'masteryBox', 'due', 'variantMissStreak'}), isEmpty);
    });

    test('Beförderung/Rückstufung: Inhalt und Stufen ändern sich, Lernstand/Herkunft/Gewicht/Rechenaufgabe bleiben', () {
      const keep = {
        'id', 'moduleId', 'conceptId', 'createdAt', 'due', 'variantChain', 'masteryBox', 'stability', 'difficulty',
        'elapsedDays', 'scheduledDays', 'reps', 'lapses', 'state', 'lastReview', 'unitId', 'priorityIntroduction',
        'needsCalculator', 'calcDeferredAt', 'sourceMaterialId', 'sourcePage', 'scriptMaterialId', 'scriptPage',
        'miniLesson', 'weight', 'stageLevel', 'stageGroup',
      };
      final promoted = card.copyWithPromotedVariant(newType: QuestionType.freeText, front: 'Neu', correctText: 'x');
      expect(_diff(card, promoted).intersection(keep), isEmpty);
      final fromPending = card.copyWithPromotedVariantFromPending();
      expect(_diff(card, fromPending).intersection(keep), isEmpty);
      final demoted = card.copyWithDemotedVariant();
      expect(_diff(card, demoted).intersection(keep), isEmpty);
    });
  });
}
