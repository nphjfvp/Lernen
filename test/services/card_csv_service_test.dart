import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/card_csv_service.dart';

void main() {
  group('CardCsvService.export', () {
    test('Kopfzeile, Semikolon, Anführungszeichen bei Sonderzeichen', () {
      final csv = CardCsvService.export([
        Flashcard(
          id: '1',
          moduleId: 'm',
          front: 'Was ist "Osmose"?',
          back: 'Diffusion;\ndurch Membran',
          createdAt: DateTime(2026, 1, 1),
          due: DateTime(2026, 1, 1),
        ),
      ], now: DateTime(2026, 1, 1));
      expect(csv.startsWith('﻿Vorderseite;Rückseite;Typ;Ampel;Fällig;Wiederholungen\r\n'), isTrue);
      expect(csv, contains('"Was ist ""Osmose""?";"Diffusion;\ndurch Membran";Karteikarte;Neu;;0'));
    });

    test('Export und Import ergeben wieder dieselben Seiten', () {
      final cards = [
        Flashcard(
          id: '1',
          moduleId: 'm',
          front: 'A; mit "Zitat"',
          back: 'Zeile 1\nZeile 2',
          createdAt: DateTime(2026, 1, 1),
          due: DateTime(2026, 1, 1),
        ),
      ];
      final rows = CardCsvService.parse(CardCsvService.export(cards));
      expect(rows.single.front, 'A; mit "Zitat"');
      expect(rows.single.back, 'Zeile 1\nZeile 2');
    });
  });

  group('CardCsvService.parse', () {
    test('Anki-Textexport: Tab, Kopfzeilen mit #, einfaches HTML', () {
      const input = '#separator:tab\n#html:true\nHauptstadt von Frankreich?\tParis<br>an der Seine\nH&amp;M\t&lt;Firma&gt;\n';
      final rows = CardCsvService.parse(input);
      expect(rows, hasLength(2));
      expect(rows[0].back, 'Paris\nan der Seine');
      expect(rows[1].front, 'H&M');
      expect(rows[1].back, '<Firma>');
    });

    test('Komma-getrennt mit Kopfzeile, leere und einspaltige Zeilen werden übersprungen', () {
      const input = 'Front,Back\nFrage 1,Antwort 1\n\nnur eine Spalte\n,leer vorne\nFrage 2,"Antwort, mit Komma"\n';
      final rows = CardCsvService.parse(input);
      expect(rows.map((r) => r.front).toList(), ['Frage 1', 'Frage 2']);
      expect(rows.last.back, 'Antwort, mit Komma');
    });

    test('toFlashcards legt neue Karteikarten in Datei-Reihenfolge an', () {
      final cards = CardCsvService.toFlashcards(
        [(front: 'a', back: 'b'), (front: 'c', back: 'd')],
        'mod',
        now: DateTime(2026, 9, 26),
      );
      expect(cards.map((c) => c.front).toList(), ['a', 'c']);
      expect(cards.every((c) => c.moduleId == 'mod' && c.reps == 0 && c.type == QuestionType.flashcard), isTrue);
      expect(cards[0].createdAt.isBefore(cards[1].createdAt), isTrue);
    });
  });
}
