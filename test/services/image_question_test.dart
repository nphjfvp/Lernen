import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/answer_checker.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/ui/widgets/page_question_creation_sheet.dart';

Flashcard _card({
  QuestionType type = QuestionType.diagramLabel,
  List<ImageTarget>? targets,
  String? image = 'aGVsbG8=',
  String back = '',
}) =>
    Flashcard(
      id: 'c1',
      moduleId: 'm1',
      front: 'Beschrifte die Zelle',
      back: back,
      createdAt: DateTime(2026, 9, 27),
      due: DateTime(2026, 9, 27),
      type: type,
      imageBase64: image,
      imageTargets: targets,
    );

const _cell = [
  ImageTarget(x: 0.2, y: 0.3, label: 'Zellkern'),
  ImageTarget(x: 0.7, y: 0.6, label: 'Mitochondrium'),
  ImageTarget(x: 0.5, y: 0.9, label: 'Zellmembran'),
];

void main() {
  group('ImageTarget', () {
    test('liest tolerant: Text-Zahlen, Begrenzung auf 0..1, Kreis und Vieleck der Vorgänger-App', () {
      final t = ImageTarget.fromMap({'x': '0.4', 'y': 1.7, 'label': ' A '});
      expect(t.x, 0.4);
      expect(t.y, 1.0);
      expect(t.label, 'A');

      final circle = ImageTarget.fromMap({'type': 'circle', 'x': 0.5, 'y': 0.5, 'radius': 0.1});
      expect(circle.w, closeTo(0.2, 1e-9));
      expect(circle.h, closeTo(0.2, 1e-9));

      final polygon = ImageTarget.fromMap({
        'type': 'polygon',
        'points': [
          [0.3, 0.3],
          [0.7, 0.3],
          [0.7, 0.6],
          [0.3, 0.6],
        ],
      });
      expect(polygon.x, closeTo(0.5, 1e-9));
      expect(polygon.y, closeTo(0.45, 1e-9));
      expect(polygon.w, closeTo(0.4, 1e-9));
      expect(polygon.h, closeTo(0.3, 1e-9));
    });

    test('contains mit Toleranz', () {
      const r = ImageTarget(x: 0.5, y: 0.5, w: 0.2, h: 0.2);
      expect(r.contains(0.55, 0.45), isTrue);
      expect(r.contains(0.61, 0.5), isTrue); // innerhalb der Toleranz
      expect(r.contains(0.7, 0.5), isFalse);
    });
  });

  group('Flashcard mit Bild-Zielen', () {
    test('überstehen Speichern/Laden und Stufenwechsel', () {
      final card = _card(targets: _cell);
      final loaded = Flashcard.fromMap(card.toMap());
      expect(loaded.type, QuestionType.diagramLabel);
      expect(loaded.imageTargets!.map((t) => t.label), ['Zellkern', 'Mitochondrium', 'Zellmembran']);
      expect(loaded.imageTargets!.first.x, 0.2);

      final promoted = card.copyWithPromotedVariant(newType: QuestionType.freeText, front: 'Was ist …?', correctText: 'x');
      expect(promoted.imageTargets, isNull);
      expect(promoted.variantHistory!.single.imageTargets!.length, 3);
      final snapshot = VariantSnapshot.fromMap(promoted.variantHistory!.single.toMap());
      expect(snapshot.imageTargets!.last.label, 'Zellmembran');
      final demoted = promoted.copyWithDemotedVariant();
      expect(demoted.type, QuestionType.diagramLabel);
      expect(demoted.imageTargets!.length, 3);
    });

    test('copyWithImage ersetzt Bild/Ziele und behält den Lernstand', () {
      final learned = _card(targets: _cell).copyWithReview(
        due: DateTime(2026, 10, 1),
        stability: 3,
        difficulty: 5,
        elapsedDays: 1,
        scheduledDays: 3,
        reps: 2,
        lapses: 0,
        state: 'review',
        lastReview: DateTime(2026, 9, 27),
        masteryBox: 2,
      );
      final edited = learned.copyWithImage(imageBase64: 'bmV1', imageTargets: _cell.take(2).toList());
      expect(edited.imageBase64, 'bmV1');
      expect(edited.imageTargets!.length, 2);
      expect(edited.reps, 2);
      expect(edited.masteryBox, 2);
      expect(edited.copyWithImage(clearImage: true).imageBase64, isNull);
    });

    test('answerSummary', () {
      expect(_card(targets: _cell).answerSummary, 'Zellkern, Mitochondrium, Zellmembran');
      expect(_card(type: QuestionType.markImage, targets: const [ImageTarget(x: 0.5, y: 0.5)]).answerSummary,
          'die markierte Stelle im Bild');
      expect(
          _card(type: QuestionType.markImage, back: 'der Zellkern', targets: const [ImageTarget(x: 0.5, y: 0.5)])
              .answerSummary,
          'der Zellkern');
    });
  });

  group('AnswerChecker – Bild beschriften', () {
    final card = _card(targets: [..._cell, const ImageTarget(x: 0.1, y: 0.1)]);

    test('nur Stellen mit Beschriftung zählen', () {
      expect(AnswerChecker.labelTargets(card).length, 3);
      expect(AnswerChecker.diagramLabelSolution(card), '1 = Zellkern, 2 = Mitochondrium, 3 = Zellmembran');
    });

    test('richtig nur, wenn jede Stelle ihre Beschriftung trägt', () {
      expect(AnswerChecker.checkDiagramLabel(card, {0: 0, 1: 1, 2: 2}).isCorrect, isTrue);
      expect(AnswerChecker.checkDiagramLabel(card, {0: 1, 1: 0, 2: 2}).isCorrect, isFalse);
      expect(AnswerChecker.checkDiagramLabel(card, {0: 0, 1: 1}).isCorrect, isFalse);
    });

    test('gleich lautende Beschriftungen sind austauschbar', () {
      final twins = _card(targets: const [
        ImageTarget(x: 0.2, y: 0.2, label: 'Ventil'),
        ImageTarget(x: 0.8, y: 0.2, label: 'Ventil'),
        ImageTarget(x: 0.5, y: 0.8, label: 'Kolben'),
      ]);
      expect(AnswerChecker.checkDiagramLabel(twins, {0: 1, 1: 0, 2: 2}).isCorrect, isTrue);
    });
  });

  group('AnswerChecker – Bild markieren', () {
    final card = _card(type: QuestionType.markImage, targets: const [
      ImageTarget(x: 0.5, y: 0.5, w: 0.2, h: 0.2),
      ImageTarget(x: 0.1, y: 0.9), // Punkt ohne Ausdehnung: Mindestgröße
    ]);

    test('Treffer in einem der Bereiche', () {
      expect(AnswerChecker.checkMarkImage(card, 0.52, 0.47).isCorrect, isTrue);
      expect(AnswerChecker.checkMarkImage(card, 0.12, 0.88).isCorrect, isTrue);
      expect(AnswerChecker.checkMarkImage(card, 0.9, 0.1).isCorrect, isFalse);
      expect(AnswerChecker.checkMarkImage(card, null, null).isCorrect, isFalse);
    });

    test('ohne Bild oder Ziele nicht beantwortbar (wird Karteikarte)', () {
      expect(AnswerChecker.isAnswerable(card), isTrue);
      expect(AnswerChecker.isAnswerable(_card(type: QuestionType.markImage, image: null, targets: card.imageTargets)),
          isFalse);
      expect(AnswerChecker.isAnswerable(_card(type: QuestionType.markImage, targets: null)), isFalse);
      expect(AnswerChecker.isAnswerable(_card(targets: const [ImageTarget(x: 0.5, y: 0.5)])), isFalse);
    });
  });

  group('QuestionParsing – Bildfragen', () {
    test('diagram_label mit "targets" wird übernommen (unter imageTargets)', () {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'diagram_label',
        'front': 'Beschrifte',
        'targets': [
          {'label': 'A', 'x': 0.1, 'y': 0.2},
          {'label': '', 'x': 0.3, 'y': 0.4},
        ],
      })!;
      expect(fixed['type'], 'diagram_label');
      final targets = parseImageTargets(fixed['imageTargets'])!;
      expect(targets.map((t) => t.label), ['A']);
    });

    test('Felder der Vorgänger-App (diagram_labels, mark_regions) werden gelesen', () {
      final label = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'diagram_label',
        'front': 'B',
        'diagram_labels': [
          {'label': 'X', 'x': 0.5, 'y': 0.5},
        ],
      })!;
      expect(parseImageTargets(label['imageTargets'])!.single.label, 'X');

      final mark = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'mark_image',
        'front': 'Wo?',
        'mark_regions': [
          {'type': 'circle', 'x': 0.5, 'y': 0.5, 'radius': 0.1},
        ],
      })!;
      expect(mark['type'], 'mark_image');
      expect(parseImageTargets(mark['imageTargets'])!.single.w, closeTo(0.2, 1e-9));
    });

    test('ohne Ziele: Beschriften wird Karteikarte, Markieren ohne Antwort verworfen', () {
      expect(
        QuestionParsing.normalizeGeneratedFlashcard({'type': 'mark_image', 'front': 'Wo?'}),
        isNull,
      );
      final fallback = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'mark_image',
        'front': 'Wo liegt der Kern?',
        'back': 'in der Mitte',
      })!;
      expect(fallback['type'], 'flashcard');
    });

    test('Frage erstellen: Bildfragen bekommen immer das Bild und ihre Ziele', () {
      final groups = [
        [
          {
            'type': 'diagram_label',
            'front': 'Beschrifte',
            'needsImage': false,
            'targets': [
              {'label': 'A', 'x': 0.1, 'y': 0.2},
            ],
          },
        ],
      ];
      final cards = buildPageQuestionCards(
        groups,
        moduleId: 'm1',
        questionCount: 1,
        tierCount: 1,
        attachImageBase64: 'QklMRA==',
        now: DateTime(2026, 9, 27),
      );
      final card = cards.single.single;
      expect(card.type, QuestionType.diagramLabel);
      expect(card.imageBase64, 'QklMRA==');
      expect(card.imageTargets!.single.label, 'A');
      expect(AnswerChecker.isAnswerable(card), isTrue);
    });
  });
}
