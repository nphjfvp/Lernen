import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/services/calc_engine.dart';
import 'package:lernen/services/lab_photo_reading.dart';
import 'package:lernen/services/question_parsing.dart';

/// Code-Analyse 2: kleine Härtungen, die einzeln zu klein für eine eigene
/// Testdatei sind.
void main() {
  group('CalcEngine: Fehlermeldungen bleiben kurz', () {
    test('ein riesiger Ausdruck steht nur gekürzt in der Meldung', () {
      final expr = '(' * 20000;
      try {
        CalcEngine.evaluate(expr, const {});
        fail('hätte eine CalcException geben müssen');
      } on CalcException catch (e) {
        expect(e.message.length, lessThan(300));
        expect(e.message, contains('…'));
      }
    });

    test('ein kurzer Ausdruck steht unverändert in der Meldung', () {
      try {
        CalcEngine.evaluate('1 + * 2', const {});
        fail('hätte eine CalcException geben müssen');
      } on CalcException catch (e) {
        expect(e.message, contains('1 + * 2'));
        expect(e.message, isNot(contains('…')));
      }
    });

    test('ein unerlaubtes Zeichen in einem langen Ausdruck wird ebenfalls gekürzt', () {
      final expr = '1+' * 500 + '§';
      try {
        CalcEngine.evaluate(expr, const {});
        fail('hätte eine CalcException geben müssen');
      } on CalcException catch (e) {
        expect(e.message.length, lessThan(300));
      }
    });
  });

  group('QuestionParsing.aiTypeName', () {
    test('liefert für jeden Fragetyp einen Namen, den parseType wieder versteht', () {
      for (final type in QuestionType.values) {
        final name = QuestionParsing.aiTypeName(type);
        expect(QuestionParsing.parseType(name), type, reason: '$type → $name');
      }
    });
  });

  group('LabPhotoReading.fromJson: kaputte KI-Antworten', () {
    final experiment = LabExperiment.fromStructure(
      {
        'title': 'Oszilloskop',
        'parts': [
          {
            'title': 'Teil A',
            'steps': ['x'],
          },
          {
            'title': 'Teil B',
            'steps': ['y'],
          },
        ],
      },
      moduleId: 'm1',
      now: DateTime(2026, 9, 1),
      id: 'lab-osc-0001',
    );

    test('"cells" als Text oder Objekt statt als Liste wird ignoriert statt zu werfen', () {
      for (final bad in <Object?>['keine', {'a': 1}, 5, null]) {
        final r = LabPhotoReading.fromJson({'description': 'x', 'cells': bad}, [experiment]);
        expect(r.cells, isEmpty);
        expect(r.description, 'x');
      }
    });

    test('ein Teil-Name aus lauter Sonderzeichen trifft keinen Teil mit leerem Namen', () {
      final blank = LabExperiment.fromStructure(
        {
          'title': 'V',
          'parts': [
            {
              'title': '',
              'steps': ['x'],
            },
            {
              'title': 'Teil B',
              'steps': ['y'],
            },
          ],
        },
        moduleId: 'm1',
        now: DateTime(2026, 9, 1),
        id: 'lab-blank-01',
      );
      final r = LabPhotoReading.fromJson({'experimentId': blank.id, 'partId': '---'}, [blank]);
      expect(r.experimentId, blank.id);
      expect(r.partId, isNull);
    });
  });
}
