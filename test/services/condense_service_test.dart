import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/condense.dart';
import 'package:lernen/services/condense_service.dart';

CondensePage _page(int number, List<String> blocks, {String label = 'Seite'}) => CondensePage(
      number: number,
      label: label,
      blocks: [for (var i = 0; i < blocks.length; i++) CondenseBlock(page: number, index: i + 1, text: blocks[i])],
    );

void main() {
  group('Blöcke', () {
    test('Zeilen werden bis etwa 240 Zeichen zu einem Block, Nummern zählen ab 1', () {
      final line = 'x' * 100;
      final blocks = CondenseService.blocksOfPage(7, [line, line, line, line, line].join('\n'));
      expect(blocks.map((b) => b.id), ['7.1', '7.2']);
      expect(blocks.first.text.split('\n'), hasLength(3));
      expect(blocks.last.text.split('\n'), hasLength(2));
    });

    test('eine Überschrift nach einem fertigen Satz beginnt einen neuen Block', () {
      final text = [
        'Die Funktion ist stetig, also gilt der Satz und wir können die Stammfunktion bilden.',
        'Damit folgt das Ergebnis direkt.',
        'Partielle Integration',
        'Hier steht die Formel.',
      ].join('\n');
      final blocks = CondenseService.blocksOfPage(1, text);
      expect(blocks, hasLength(2));
      expect(blocks.last.text, startsWith('Partielle Integration'));
    });

    test('leere Zeilen und \\r fallen weg, eine leere Seite hat keine Blöcke', () {
      expect(CondenseService.blocksOfPage(1, '\r\n  \n\r\n'), isEmpty);
      expect(CondenseService.blocksOfPage(1, 'a\r\n\r\nb').single.text, 'a\nb');
    });

    test('Seiten behalten ihre Nummer, auch wenn eine leer ist', () {
      final pages = CondenseService.pagesFromPageTexts(['eins', '', 'drei']);
      expect(pages.map((p) => p.number), [1, 2, 3]);
      expect(pages[1].blocks, isEmpty);
      expect(pages[2].blocks.single.id, '3.1');
    });

    test('PowerPoint-Text wird an den Folien-Marken geteilt', () {
      const text = '--- Folie 1 ---\nTitel\n\n--- Folie 2 ---\nInhalt A\nInhalt B\n\n--- Folie 4 ---\nSchluss';
      final pages = CondenseService.pagesFromText(text);
      expect(pages.map((p) => p.number), [1, 2, 4]);
      expect(pages.every((p) => p.label == 'Folie'), isTrue);
      expect(pages[1].blocks.single.text, 'Inhalt A\nInhalt B');
    });

    test('Text ohne Seitenstruktur wird in Abschnitte geteilt', () {
      final paragraph = 'Absatz ' * 60;
      final pages = CondenseService.pagesFromText([paragraph, paragraph, paragraph].join('\n\n'), sectionChars: 500);
      expect(pages.length, greaterThan(1));
      expect(pages.first.label, 'Abschnitt');
      expect(pages.map((p) => p.number), [for (var i = 1; i <= pages.length; i++) i]);
    });
  });

  group('Gruppieren und Darstellen', () {
    final pages = [for (var i = 1; i <= 6; i++) _page(i, ['a' * 100, 'b' * 100])];

    test('ohne Größe ein Aufruf, leere Seiten fallen heraus', () {
      final withEmpty = [...pages, const CondensePage(number: 7, blocks: [])];
      final groups = CondenseService.group(withEmpty, null);
      expect(groups, hasLength(1));
      expect(groups.single, hasLength(6));
    });

    test('mit Größe mehrere Aufrufe, jede Seite genau einmal und in Reihenfolge', () {
      final groups = CondenseService.group(pages, 500);
      expect(groups.length, greaterThan(1));
      expect([for (final g in groups) ...g.map((p) => p.number)], [1, 2, 3, 4, 5, 6]);
    });

    test('eine einzelne große Seite bleibt allein', () {
      final big = _page(1, ['x' * 5000]);
      final groups = CondenseService.group([big, pages[1]], 1000);
      expect(groups, hasLength(2));
      expect(groups.first.single.number, 1);
    });

    test('Darstellung für die KI: Seitenkopf und [Kennung] je Block', () {
      final text = CondenseService.render([_page(12, ['Erster', 'Zweiter'])]);
      expect(text, '=== Seite 12 ===\n[12.1] Erster\n[12.2] Zweiter');
    });
  });

  group('Blockangaben der KI einlesen', () {
    final ordered = ['11.1', '11.2', '12.1', '12.2', '12.3', '13.1'];

    test('einzelne Kennungen und Bereiche, auch über Seitengrenzen', () {
      expect(CondenseService.parseBlockRefs(['12.1-12.3'], ordered), ['12.1', '12.2', '12.3']);
      expect(CondenseService.parseBlockRefs(['11.2–12.1'], ordered), ['11.2', '12.1']);
      expect(CondenseService.parseBlockRefs(['13.1', '11.1'], ordered), ['11.1', '13.1']);
    });

    test('ganze Seiten per Nummer', () {
      expect(CondenseService.parseBlockRefs(['12'], ordered), ['12.1', '12.2', '12.3']);
      expect(CondenseService.parseBlockRefs(['11-12'], ordered), ['11.1', '11.2', '12.1', '12.2', '12.3']);
      expect(CondenseService.parseBlockRefs(['12.3-13'], ordered), ['12.3', '13.1']);
    });

    test('Kennungen außerhalb des Aufrufs und Unsinn fallen weg', () {
      expect(CondenseService.parseBlockRefs(['99.1', 'abc', '', '12.2'], ordered), ['12.2']);
      expect(CondenseService.parseBlockRefs(null, ordered), isEmpty);
      expect(CondenseService.parseBlockRefs(42, ordered), isEmpty);
    });

    test('ein Ende außerhalb: der gültige Anfang zählt allein', () {
      expect(CondenseService.parseBlockRefs(['12.2-99.9'], ordered), ['12.2']);
    });

    test('umgekehrter Bereich, Doppelte und Text als Aufzählung', () {
      expect(CondenseService.parseBlockRefs(['12.3-12.1', '12.2'], ordered), ['12.1', '12.2', '12.3']);
      expect(CondenseService.parseBlockRefs('12.1, 12.3; S13.1', ordered), ['12.1', '12.3', '13.1']);
      expect(CondenseService.parseBlockRefs(['12.1,12.3'], ordered), ['12.1', '12.3']);
      expect(CondenseService.parseBlockRefs(['12,2'], ordered), ['12.2']);
    });

    test('Abschnitt: Art und Felder tolerant, ohne gültigen Block verworfen', () {
      final s = CondenseService.parseSection(
        {'title': ' Substitution ', 'kind': 'Beispielaufgabe', 'why': 'Aufgabe 2', 'blocks': ['12.1-12.2'], 'covers': ['N1', ' n3 ', '']},
        ordered,
      )!;
      expect(s.title, 'Substitution');
      expect(s.kind, CondenseKind.beispiel);
      expect(s.covers, ['n1', 'n3']);
      expect(s.blockIds, ['12.1', '12.2']);
      expect(CondenseService.parseSection({'title': 'x', 'blocks': ['99.9']}, ordered), isNull);
      expect(CondenseService.parseSection('kein Objekt', ordered), isNull);
      expect(CondenseService.parseSection({'blocks': ['12.1']}, ordered)!.title, 'Abschnitt');
      expect(CondenseService.parseSection({'blocks': ['12.1']}, ordered)!.kind, CondenseKind.erklaerung);
    });
  });

  group('Zusammensetzen', () {
    final pages = [
      _page(1, ['Organisatorisches']),
      _page(2, ['Titel', 'Definition', 'Herleitung', 'Ausblick']),
      _page(3, ['A', 'B']),
    ];
    const sections = [
      CondenseSection(title: 'Definition', blockIds: ['2.2', '2.3']),
      CondenseSection(title: 'Alles auf Seite 3', blockIds: ['3.1', '3.2']),
      CondenseSection(title: 'Doppelt', blockIds: ['2.3', '2.1']),
    ];

    test('behaltene Blöcke in Dokumentreihenfolge, der erste Abschnitt gibt den Titel', () {
      final kept = CondenseService.keptBlocks(pages, sections);
      expect(kept.map((k) => k.block.id), ['2.1', '2.2', '2.3', '3.1', '3.2']);
      expect(kept.map((k) => k.title), ['Doppelt', 'Definition', 'Definition', 'Alles auf Seite 3', 'Alles auf Seite 3']);
      expect(CondenseService.keptPageNumbers(pages, sections), [2, 3]);
    });

    test('Markierungen: Anfang jedes zusammenhängenden Stücks, ganze Seiten bekommen keine', () {
      final runs = CondenseService.runsByPage(pages, const [
        CondenseSection(title: 'Definition', blockIds: ['2.2']),
        CondenseSection(title: 'Ausblick', blockIds: ['2.4']),
        CondenseSection(title: 'Seite 3', blockIds: ['3.1', '3.2']),
      ]);
      expect(runs.keys, [2]);
      expect(runs[2]!.map((r) => (r.from, r.to, r.title)), [(2, 2, 'Definition'), (4, 4, 'Ausblick')]);
    });

    test('ein durchgehendes Stück ab dem ersten Block bis zur Mitte wird markiert', () {
      final runs = CondenseService.runsByPage(pages, const [
        CondenseSection(title: 'Anfang', blockIds: ['2.1', '2.2']),
      ]);
      expect(runs[2]!.single.to, 2);
    });

    test('Text: Kopf mit Auftrag und Umfang, je Seite die behaltenen Blöcke', () {
      final text = CondenseService.textDocument(
        sourceName: 'Analysis.pdf',
        prompt: 'alles zum Lösen',
        pages: pages,
        sections: sections,
      );
      expect(text, startsWith('Gekürzte Fassung: Analysis.pdf\nAuftrag: alles zum Lösen\nBehalten: Seiten 2–3 von 3'));
      expect(text, contains('## Seite 2 · Doppelt / Definition\nTitel\nDefinition\nHerleitung'));
      expect(text, contains('## Seite 3 · Alles auf Seite 3\nA\nB'));
      expect(text, isNot(contains('Organisatorisches')));
      expect(text, isNot(contains('Ausblick')));
    });
  });

  group('Auswahl und Anforderungen', () {
    const plan = CondensePlan(needs: [
      CondenseNeed(id: 'n1', text: 'Partielle Integration'),
      CondenseNeed(id: 'n2', text: 'Substitution'),
      CondenseNeed(id: 'n3', text: 'Laplace'),
    ]);
    const selection = CondenseSelection(plan: plan, sections: [
      CondenseSection(title: 'A', blockIds: ['1.1'], covers: ['n1']),
      CondenseSection(title: 'Bsp', blockIds: ['1.2'], kind: CondenseKind.beispiel, covers: ['n2']),
    ]);

    test('ohne Beispielaufgaben nur die Erklärungen', () {
      expect(selection.visible(includeExamples: true), hasLength(2));
      expect(selection.visible(includeExamples: false).single.title, 'A');
    });

    test('nicht abgedeckt: was kein sichtbarer Abschnitt erklärt', () {
      expect(selection.uncovered(includeExamples: true).map((n) => n.id), ['n3']);
      // n2 wird nur im Beispiel behandelt – ohne Beispiele fehlt die Erklärung.
      expect(selection.uncovered(includeExamples: false).map((n) => n.id), ['n2', 'n3']);
    });

    test('Anforderungen mehrfach genannt: einmal geführt, Kennungen neu', () {
      final needs = CondenseService.mergeNeeds(['Partielle Integration', ' partielle  integration ', 'Substitution', '']);
      expect(needs.map((n) => (n.id, n.text)), [('n1', 'Partielle Integration'), ('n2', 'Substitution')]);
    });
  });

  group('Seitenangaben und gespeicherte Angaben', () {
    test('aufeinanderfolgende Seiten werden ein Bereich', () {
      expect(condensePageRanges([3, 5, 6, 7, 9]), 'Seiten 3, 5–7, 9');
      expect(condensePageRanges([4]), 'Seite 4');
      expect(condensePageRanges([2, 3], label: 'Folie'), 'Folien 2–3');
      expect(condensePageRanges([]), '');
      expect(condensePageRanges([5, 3, 3, 4]), 'Seiten 3–5');
    });

    test('CondensedInfo: Rundreise und tolerantes Lesen', () {
      const info = CondensedInfo(
        sourceMaterialId: 'm1',
        sourceName: 'Analysis.pdf',
        prompt: 'alles',
        exerciseNames: ['Blatt 3.pdf'],
        pages: [2, 3, 8],
        totalPages: 40,
        includeExamples: false,
        markers: false,
        notFound: ['Laplace'],
        skipped: ['Organisatorisches'],
      );
      final back = CondensedInfo.fromMap(info.toMap())!;
      expect(back.pages, [2, 3, 8]);
      expect(back.includeExamples, isFalse);
      expect(back.markers, isFalse);
      expect(back.notFound, ['Laplace']);
      expect(back.shareText, '3 von 40 Seiten');
      expect(back.pagesText, 'Seiten 2–3, 8');

      final odd = CondensedInfo.fromMap({'pages': ['4', 'x', 5.0, null], 'exerciseNames': 'kaputt', 'totalPages': '12'})!;
      expect(odd.pages, [4, 5]);
      expect(odd.exerciseNames, isEmpty);
      expect(odd.totalPages, 12);
      expect(CondensedInfo.fromMap('nichts'), isNull);
      expect(CondensedInfo.fromMap(null), isNull);
    });
  });
}
