import 'package:flutter/painting.dart' show Rect;
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

  group('AnswerChecker – austauschbare Stellen und Eintippen', () {
    final card = _card(targets: const [
      ImageTarget(x: 0.1, y: 0.2, label: 'Arbeit', group: 'Input'),
      ImageTarget(x: 0.1, y: 0.4, label: 'Kapital', group: 'Input'),
      ImageTarget(x: 0.1, y: 0.6, label: 'Boden', group: 'Input'),
      ImageTarget(x: 0.9, y: 0.4, label: 'Produkt'),
    ]);

    test('innerhalb einer Gruppe ist die Reihenfolge egal', () {
      final result = AnswerChecker.checkDiagramLabelTexts(card, {0: 'Boden', 1: 'Arbeit', 2: 'Kapital', 3: 'Produkt'});
      expect(result.isCorrect, isTrue);
    });

    test('jede Beschriftung einer Gruppe zählt nur einmal; außerhalb der Gruppe zählt der Ort', () {
      final zones = AnswerChecker.diagramLabelZones(card, {0: 'Arbeit', 1: 'Arbeit', 2: 'Kapital', 3: 'Boden'});
      expect(zones.map((z) => z.correct), [true, false, true, false]);
      expect(zones[1].allowed, ['Boden']); // die noch offene der Gruppe
      expect(zones[3].allowed, ['Produkt']);
    });

    test('Zuordnen per Chip-Index nutzt dieselbe Regel', () {
      // Stelle 0 bekommt "Kapital" (Index 1), Stelle 1 "Arbeit" (Index 0).
      expect(AnswerChecker.checkDiagramLabel(card, {0: 1, 1: 0, 2: 2, 3: 3}).isCorrect, isTrue);
    });

    test('Eintippen: kleine Tippfehler zählen, ohne Toleranz nicht', () {
      final typed = {0: 'Kapitl', 1: 'arbeit', 2: 'Boden', 3: 'Produckt'};
      expect(AnswerChecker.checkDiagramLabelTexts(card, typed, tolerant: true).isCorrect, isTrue);
      expect(AnswerChecker.checkDiagramLabelTexts(card, typed).isCorrect, isFalse);
    });

    test('ein genauer Treffer wird vor einem Tippfehler-Treffer vergeben', () {
      final similar = _card(targets: const [
        ImageTarget(x: 0.1, y: 0.1, label: 'Anode', group: 'Pol'),
        ImageTarget(x: 0.2, y: 0.1, label: 'Anoden', group: 'Pol'),
      ]);
      // "Anodn" passt zu beiden – "Anode" ist aber genau vergeben.
      final zones = AnswerChecker.diagramLabelZones(similar, {0: 'Anodn', 1: 'Anode'}, tolerant: true);
      expect(zones.every((z) => z.correct), isTrue);
    });

    test('Lösungstext fasst austauschbare Stellen zusammen', () {
      expect(AnswerChecker.diagramLabelSolution(card),
          '1/2/3 = Arbeit, Kapital, Boden (beliebige Reihenfolge), 4 = Produkt');
    });

    test('Gruppe übersteht Speichern/Laden, KI-Kasten und Prozent-Koordinaten werden gelesen', () {
      final loaded = Flashcard.fromMap(card.toMap());
      expect(loaded.imageTargets!.first.group, 'Input');

      final box = ImageTarget.fromMap({
        'label': 'Kern',
        'group': 'Innen',
        'box': [0.2, 0.3, 0.4, 0.5],
      });
      expect(box.x, closeTo(0.3, 1e-9));
      expect(box.y, closeTo(0.4, 1e-9));
      expect(box.w, closeTo(0.2, 1e-9));
      expect(box.group, 'Innen');

      final percent = ImageTarget.fromMap({'x': 50, 'y': 25, 'label': 'P'});
      expect(percent.x, closeTo(0.5, 1e-9));
      expect(percent.y, closeTo(0.25, 1e-9));
      final permille = ImageTarget.fromMap({'box': [100, 200, 300, 400]});
      expect(permille.x, closeTo(0.2, 1e-9));
      expect(permille.h, closeTo(0.2, 1e-9));
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

    test('Frage erstellen: Kästen der Beschriftungen und weitere Abdeckungen werden abgedeckt', () {
      final covers = <String, List<Rect>>{};
      final cards = buildPageQuestionCards(
        [
          [
            {
              'type': 'diagram_label',
              'front': 'Beschrifte',
              'targets': [
                {'label': 'Arbeit', 'box': [0.10, 0.20, 0.30, 0.25], 'group': 'Input'},
                {'label': 'Produkt', 'x': 0.8, 'y': 0.5},
              ],
              'covers': [
                [0.6, 0.0, 0.9, 0.1],
              ],
            },
          ],
        ],
        moduleId: 'm1',
        questionCount: 1,
        tierCount: 1,
        attachImageBase64: 'QklMRA==',
        now: DateTime(2026, 9, 27),
        coversOut: covers,
      );
      final card = cards.single.single;
      final rects = covers[card.id]!;
      // Weitere Abdeckung + Kasten der Beschriftung (der Punkt ohne Kasten nicht).
      expect(rects, hasLength(2));
      final label = rects.firstWhere((r) => r.center.dx < 0.5);
      expect(label.left, lessThan(0.10)); // etwas größer als der Kasten
      expect(label.right, greaterThan(0.30));
      expect(card.imageTargets!.first.group, 'Input');
      expect(card.imageTargets!.first.x, closeTo(0.2, 1e-9));
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
