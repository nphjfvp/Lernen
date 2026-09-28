import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/answer_checker.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/services/stage_gate_service.dart';

Flashcard _table(List<List<QuestionTableCell>> rows) => Flashcard(
      id: 't1',
      moduleId: 'm1',
      front: 'Fülle die Tabelle aus.',
      back: '',
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      type: QuestionType.table,
      tableRows: rows,
    );

/// Kopfzeile + 5 Zeilen mit je einer auszufüllenden Zelle.
final _fiveBlanks = _table([
  const [QuestionTableCell(text: 'Element'), QuestionTableCell(text: 'Symbol')],
  const [QuestionTableCell(text: 'Wasserstoff'), QuestionTableCell(text: 'H', given: false)],
  const [QuestionTableCell(text: 'Helium'), QuestionTableCell(text: 'He', given: false)],
  const [QuestionTableCell(text: 'Lithium'), QuestionTableCell(text: 'Li', given: false)],
  const [QuestionTableCell(text: 'Kohlenstoff'), QuestionTableCell(text: 'C', given: false)],
  const [QuestionTableCell(text: 'Natrium'), QuestionTableCell(text: 'Na', given: false)],
]);

void main() {
  group('QuestionTableCell.parse', () {
    test('Text ist vorgegeben, [[…]] auszufüllen', () {
      final given = QuestionTableCell.parse('Druck');
      expect(given.text, 'Druck');
      expect(given.given, isTrue);

      final fill = QuestionTableCell.parse('[[ Pascal; Pa ]]');
      expect(fill.text, 'Pascal; Pa');
      expect(fill.given, isFalse);
    });

    test('Objekte: answer/solution oder fill/given:false sind auszufüllen', () {
      expect(QuestionTableCell.parse({'answer': 'N'}).given, isFalse);
      expect(QuestionTableCell.parse({'answer': 'N'}).text, 'N');
      expect(QuestionTableCell.parse({'solution': 'kg'}).given, isFalse);
      expect(QuestionTableCell.parse({'t': 'm', 'fill': true}).given, isFalse);
      expect(QuestionTableCell.parse({'text': 's', 'given': false}).given, isFalse);
      expect(QuestionTableCell.parse({'text': 'Zeit'}).given, isTrue);
      expect(QuestionTableCell.parse(null).text, '');
    });

    test('toMap ↔ parse bleibt gleich', () {
      for (final cell in const [QuestionTableCell(text: 'A'), QuestionTableCell(text: 'B; b', given: false)]) {
        final back = QuestionTableCell.parse(cell.toMap());
        expect(back.text, cell.text);
        expect(back.given, cell.given);
      }
    });
  });

  group('parseTableRows', () {
    test('leere Zeilen fallen weg, keine Liste = null', () {
      expect(parseTableRows(null), isNull);
      expect(parseTableRows('x'), isNull);
      expect(parseTableRows([[], []]), isNull);
      final rows = parseTableRows([
        ['a', 'b'],
        [],
        ['c', '[[d]]'],
      ])!;
      expect(rows.length, 2);
      expect(rows[1][1].given, isFalse);
    });
  });

  group('Flashcard mit Tabelle', () {
    test('toMap/fromMap behält Zellen und Ausfüllmarkierung', () {
      final card = _fiveBlanks;
      final back = Flashcard.fromMap(card.toMap());
      expect(back.type, QuestionType.table);
      expect(back.tableRows!.length, 6);
      expect(back.tableRows![1][1].text, 'H');
      expect(back.tableRows![1][1].given, isFalse);
      expect(back.tableRows![0][0].given, isTrue);
    });

    test('copyWithContent ersetzt die Tabelle, Lernstand bleibt', () {
      final card = _fiveBlanks.copyWithMissStreak(2);
      final edited = card.copyWithContent(tableRows: [
        const [QuestionTableCell(text: 'x'), QuestionTableCell(text: 'y', given: false)],
      ]);
      expect(edited.tableRows!.single[1].text, 'y');
      expect(edited.variantMissStreak, 2);
      expect(card.copyWithContent(front: 'Neu').tableRows!.length, 6);
    });

    test('answerSummary nennt die Lösungen', () {
      expect(_fiveBlanks.answerSummary, contains('He'));
      expect(_fiveBlanks.answerSummary, contains('Na'));
    });

    test('zählt als Stufe "schwer"', () {
      expect(StageGate.levelOf(_fiveBlanks), StageLevel.schwer);
    });
  });

  group('AnswerChecker – Tabelle', () {
    test('tableBlanks: nur auszufüllende Zellen mit Lösung', () {
      final card = _table([
        const [QuestionTableCell(text: 'a'), QuestionTableCell(text: '', given: false)],
        const [QuestionTableCell(text: 'b'), QuestionTableCell(text: 'B', given: false)],
      ]);
      final blanks = AnswerChecker.tableBlanks(card);
      expect(blanks.length, 1);
      expect((blanks.single.row, blanks.single.col), (1, 1));
      expect(AnswerChecker.isAnswerable(card), isTrue);
      expect(AnswerChecker.isAnswerable(_table([const [QuestionTableCell(text: 'a')]])), isFalse);
    });

    test('Varianten mit ; und kleine Tippfehler zählen', () {
      final card = _table([
        const [QuestionTableCell(text: 'Einheit'), QuestionTableCell(text: 'Pascal; Pa', given: false)],
      ]);
      expect(AnswerChecker.tableHits(card, ['Pa']), [true]);
      expect(AnswerChecker.tableHits(card, ['pascal']), [true]);
      expect(AnswerChecker.tableHits(card, ['Newton']), [false]);
      expect(AnswerChecker.tableHits(card, const []), [false]);
    });

    test('alle richtig = richtig', () {
      final hits = AnswerChecker.tableHits(_fiveBlanks, ['H', 'He', 'Li', 'C', 'Na']);
      final result = AnswerChecker.tableResult(_fiveBlanks, hits);
      expect(result.result.isCorrect, isTrue);
      expect(result.partial, isFalse);
      expect(result.share, 1.0);
    });

    test('ab 80 % richtig = fast richtig (Schwer), darunter falsch', () {
      final four = AnswerChecker.tableResult(
          _fiveBlanks, AnswerChecker.tableHits(_fiveBlanks, ['H', 'He', 'Li', 'C', 'K']));
      expect(four.result.isCorrect, isFalse);
      expect(four.partial, isTrue);
      expect(four.share, closeTo(0.8, 1e-9));

      final three = AnswerChecker.tableResult(
          _fiveBlanks, AnswerChecker.tableHits(_fiveBlanks, ['H', 'He', 'Li', 'O', 'K']));
      expect(three.result.isCorrect, isFalse);
      expect(three.partial, isFalse);
      expect(three.result.correctAnswerLabel, contains('Na'));
    });
  });

  group('QuestionParsing – Tabelle', () {
    test('KI-Format mit {"answer": …} wird zu tableRows im Speicherformat', () {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'table',
        'front': 'Ergänze die Einheiten.',
        'table': [
          ['Größe', 'Einheit'],
          ['Kraft', {'answer': 'Newton; N'}],
          ['Masse', '[[kg]]'],
        ],
      })!;
      expect(fixed['type'], 'table');
      final rows = parseTableRows(fixed['tableRows'])!;
      expect(rows.length, 3);
      expect(rows[1][1].text, 'Newton; N');
      expect(rows[1][1].given, isFalse);
      expect(rows[2][1].text, 'kg');
      expect(rows[2][1].given, isFalse);
    });

    test('Typ-Synonyme und Erkennung ohne Typ', () {
      expect(QuestionParsing.parseType('tabelle'), QuestionType.table);
      expect(QuestionParsing.parseType('table_fill'), QuestionType.table);
      final inferred = QuestionParsing.normalizeGeneratedFlashcard({
        'front': 'Tabelle ausfüllen',
        'tabelle': [
          ['a', '[[b]]'],
        ],
      })!;
      expect(inferred['type'], 'table');
    });

    test('Tabelle ohne auszufüllende Zelle wird nicht als Tabelle gespeichert', () {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard({
        'type': 'table',
        'front': 'Nur Text',
        'back': 'Antwort',
        'table': [
          ['a', 'b'],
        ],
      });
      expect(fixed?['type'], isNot('table'));
    });
  });
}
