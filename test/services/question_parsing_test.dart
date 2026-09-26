import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/html_question_contract.dart';
import 'package:lernen/services/question_parsing.dart';

void main() {
  group('QuestionParsing.parseOptions', () {
    test('akzeptiert isCorrect auch als 1 bzw. "1"', () {
      final options = QuestionParsing.parseOptions([
        {'text': 'A', 'isCorrect': 1},
        {'text': 'B', 'isCorrect': '1'},
        {'text': 'C', 'isCorrect': 0},
      ])!;
      expect(options.map((o) => o.isCorrect).toList(), [true, true, false]);
    });

    test('parst eine Liste von Optionen', () {
      final options = QuestionParsing.parseOptions([
        {'text': 'Paris', 'isCorrect': true},
        {'text': 'Lyon', 'isCorrect': false},
      ]);
      expect(options, isNotNull);
      expect(options!.length, 2);
      expect(options.first.text, 'Paris');
      expect(options.first.isCorrect, isTrue);
    });

    test('gibt null zurück, wenn kein Feld vorhanden ist', () {
      expect(QuestionParsing.parseOptions(null), isNull);
    });

    test('toleriert typische KI-Abweichungen statt zu crashen', () {
      final options = QuestionParsing.parseOptions([
        {'text': 'Paris', 'isCorrect': 'true'},
        'Lyon',
        {'isCorrect': true},
        {'text': 42, 'isCorrect': false},
      ]);
      expect(options!.map((o) => o.text), ['Paris', 'Lyon', '42']);
      expect(options.map((o) => o.isCorrect), [true, false, false]);
      expect(QuestionParsing.parseOptions('kein Array'), isNull);
    });
  });

  test('parseDragPairs überspringt unvollständige Paare statt zu crashen', () {
    final pairs = QuestionParsing.parseDragPairs([
      {'source': 'Hund', 'target': 'Tier'},
      {'source': 'Rose'},
      'Unsinn',
    ]);
    expect(pairs!.single.source, 'Hund');
  });

  test('normalizeGeneratedFlashcard wandelt Nicht-String-Felder in Strings um', () {
    final fixed = QuestionParsing.normalizeGeneratedFlashcard(
        {'type': 'free_text', 'front': 'Wie viel ist 6*7?', 'correctText': 42});
    expect(fixed!['correctText'], '42');
    expect(fixed['correctText'] as String?, '42');
  });

  group('QuestionParsing.parseBlanks', () {
    test('parst eine Liste von Strings', () {
      expect(QuestionParsing.parseBlanks(['Frankreich', 'Paris']), ['Frankreich', 'Paris']);
    });

    test('gibt null zurück, wenn kein Feld vorhanden ist', () {
      expect(QuestionParsing.parseBlanks(null), isNull);
    });
  });

  group('QuestionParsing.parseDragPairs', () {
    test('parst eine Liste von Zuordnungspaaren', () {
      final pairs = QuestionParsing.parseDragPairs([
        {'source': 'Hund', 'target': 'Tier'},
      ]);
      expect(pairs, isNotNull);
      expect(pairs!.single.source, 'Hund');
      expect(pairs.single.target, 'Tier');
    });

    test('gibt null zurück, wenn kein Feld vorhanden ist', () {
      expect(QuestionParsing.parseDragPairs(null), isNull);
    });
  });

  test('escalationChain ist single_choice -> fill_blank -> free_text', () {
    expect(QuestionParsing.escalationChain,
        [QuestionType.singleChoice, QuestionType.fillBlank, QuestionType.freeText]);
  });

  group('QuestionParsing.normalizeGeneratedFlashcard', () {
    test('lässt einen vollständigen flashcard-Eintrag unverändert', () {
      final raw = {'type': 'flashcard', 'front': 'Frage?', 'back': 'Antwort'};
      expect(QuestionParsing.normalizeGeneratedFlashcard(raw), raw);
    });

    test('lässt einen vollständigen single_choice-Eintrag unverändert', () {
      final raw = {
        'type': 'single_choice',
        'front': 'Frage?',
        'options': [
          {'text': 'A', 'isCorrect': true},
          {'text': 'B', 'isCorrect': false},
        ],
      };
      expect(QuestionParsing.normalizeGeneratedFlashcard(raw), raw);
    });

    test('rettet eine flashcard ohne "back" als flashcard mit "correctText" als Antwort', () {
      final raw = {'type': 'flashcard', 'front': 'Frage?', 'correctText': 'Eigentliche Antwort'};
      final fixed = QuestionParsing.normalizeGeneratedFlashcard(raw);
      expect(fixed, isNotNull);
      expect(fixed!['type'], 'flashcard');
      expect(fixed['back'], 'Eigentliche Antwort');
    });

    test('rettet eine single_choice ohne "options" über die Blanks-Lösung', () {
      final raw = {
        'type': 'single_choice',
        'front': 'Frage?',
        'blanks': ['Die richtige Lösung'],
      };
      final fixed = QuestionParsing.normalizeGeneratedFlashcard(raw);
      expect(fixed, isNotNull);
      expect(fixed!['type'], 'flashcard');
      expect(fixed['back'], 'Die richtige Lösung');
    });

    test('rettet über die als richtig markierten Optionen, wenn nur die fehlen', () {
      final raw = {
        'type': 'single_choice',
        'front': 'Frage?',
        'options': [
          {'text': 'Richtig', 'isCorrect': true},
          {'text': 'Falsch', 'isCorrect': false},
        ],
      };
      // Vollständig -> bleibt unverändert (kein Rettungsfall).
      expect(QuestionParsing.normalizeGeneratedFlashcard(raw)!['options'], isNotNull);
    });

    test('gibt null zurück, wenn nirgends eine Antwort zu finden ist', () {
      final raw = {'type': 'single_choice', 'front': 'Frage ohne jede Antwort?'};
      expect(QuestionParsing.normalizeGeneratedFlashcard(raw), isNull);
    });

    test('gibt null zurück, wenn "front" leer ist', () {
      final raw = {'type': 'flashcard', 'front': '', 'back': 'Antwort'};
      expect(QuestionParsing.normalizeGeneratedFlashcard(raw), isNull);
    });

    test('fill_blank ohne nicht-leere Lücken wird über "back" gerettet', () {
      final raw = {
        'type': 'fill_blank',
        'front': 'Text mit ___ Lücke',
        'blanks': [''],
        'back': 'Lösung',
      };
      final fixed = QuestionParsing.normalizeGeneratedFlashcard(raw);
      expect(fixed, isNotNull);
      expect(fixed!['type'], 'flashcard');
      expect(fixed['back'], 'Lösung');
    });

    test('drag_drop ohne dragPairs wird nicht gerettet, wenn keine Antwort auffindbar ist', () {
      final raw = {'type': 'drag_drop', 'front': 'Ordne zu'};
      expect(QuestionParsing.normalizeGeneratedFlashcard(raw), isNull);
    });

    test('übernimmt conceptTitle beim Retten in eine einfache flashcard', () {
      final raw = {
        'type': 'single_choice',
        'front': 'Frage?',
        'conceptTitle': 'Newtons zweites Gesetz',
        'blanks': ['Die richtige Lösung'],
      };
      final fixed = QuestionParsing.normalizeGeneratedFlashcard(raw);
      expect(fixed!['conceptTitle'], 'Newtons zweites Gesetz');
    });
  });

  group('QuestionParsing.parseType – html', () {
    test('"html" wird auf QuestionType.html gemappt (nicht auf den flashcard-Default)', () {
      expect(QuestionParsing.parseType('html'), QuestionType.html);
    });
  });

  group('QuestionParsing.normalizeGeneratedFlashcard – html-Typ', () {
    test('lässt einen vollständigen html-Eintrag mit Rückkanal-Aufruf unverändert', () {
      final raw = {
        'type': 'html',
        'front': 'Frage',
        'back': 'Kurzfassung der Lösung',
        'htmlContent': '<div>...</div><script>window.$htmlAnswerChannelName.postMessage("{}");</script>',
      };
      final fixed = QuestionParsing.normalizeGeneratedFlashcard(raw);
      expect(fixed, raw);
      expect(fixed!['type'], 'html');
    });

    test('rettet html ohne Rückkanal-Aufruf über "back" als einfache flashcard', () {
      final raw = {
        'type': 'html',
        'front': 'Frage',
        'back': 'Kurzfassung der Lösung',
        'htmlContent': '<div>Seite ohne jede Prüf-Logik</div>',
      };
      final fixed = QuestionParsing.normalizeGeneratedFlashcard(raw);
      expect(fixed, isNotNull);
      expect(fixed!['type'], 'flashcard');
      expect(fixed['back'], 'Kurzfassung der Lösung');
    });

    test('gibt null zurück, wenn html ohne Rückkanal-Aufruf UND ohne jeden Fallback-Inhalt ist', () {
      final raw = {'type': 'html', 'front': 'Frage', 'htmlContent': '<div>Kaputte Seite</div>'};
      expect(QuestionParsing.normalizeGeneratedFlashcard(raw), isNull);
    });

    test('gibt null zurück, wenn "htmlContent" ganz fehlt und kein Fallback existiert', () {
      final raw = {'type': 'html', 'front': 'Frage'};
      expect(QuestionParsing.normalizeGeneratedFlashcard(raw), isNull);
    });
  });

  group('QuestionParsing.matchConceptId', () {
    test('findet die ID case- und whitespace-tolerant', () {
      final idByTitle = {'newtons zweites gesetz': 'concept-1'};
      expect(QuestionParsing.matchConceptId('  Newtons Zweites Gesetz  ', idByTitle), 'concept-1');
    });

    test('gibt null zurück, wenn kein Titel angegeben wurde', () {
      expect(QuestionParsing.matchConceptId(null, {'a': 'id-a'}), isNull);
      expect(QuestionParsing.matchConceptId('', {'a': 'id-a'}), isNull);
    });

    test('gibt null zurück, wenn kein Konzept mit diesem Titel existiert', () {
      expect(QuestionParsing.matchConceptId('Unbekanntes Konzept', {'a': 'id-a'}), isNull);
    });
  });
}
