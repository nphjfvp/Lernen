import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/import_reference.dart';
import 'package:lernen/services/pdf_question_import_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// PDF, dessen Seite i den Text [texts]\[i\] trägt.
Uint8List pdfWithTexts(List<String> texts) {
  final document = PdfDocument();
  for (final text in texts) {
    document.pages.add().graphics.drawString(text, PdfStandardFont(PdfFontFamily.helvetica, 10));
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

http.Response _chat(Object content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': jsonEncode(content)},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
String _system(http.Request r) => (_body(r)['messages'] as List)[0]['content'] as String;
List<Map<String, dynamic>> _content(http.Request r) =>
    [for (final c in (_body(r)['messages'] as List)[1]['content'] as List) Map<String, dynamic>.from(c as Map)];
String _allText(http.Request r) => [for (final c in _content(r)) if (c['type'] == 'text') c['text']].join('\n---\n');

/// Die gezeigten Seiten einer Anfrage.
List<int> _shown(http.Request r) => [
      for (final m in RegExp(r'Dokument-Seite (\d+)').allMatches(_content(r).first['text'] as String))
        int.parse(m.group(1)!),
    ];

Map<String, dynamic> _free(int page, String front, String answer) => {
      'page': page,
      'type': 'free_text',
      'front': front,
      'correctText': answer,
      'solutionFromDocument': true,
    };

PdfQuestionImportService _service(MockClient client, {int pagesPerRequest = 3, int charBudget = 100000}) =>
    PdfQuestionImportService(
      ai: AiService(apiKey: 'k', model: 'vision', client: client),
      pagesPerRequest: pagesPerRequest,
      charBudget: charBudget,
    );

void main() {
  group('Abschnitte planen', () {
    test('neue Seiten je Abschnitt, jeder weitere beginnt mit der letzten Seite des vorigen', () {
      final windows = planScanWindows(const [], firstPage: 1, lastPage: 10, maxNewPages: 4);
      expect([for (final w in windows) '${w.overlap}|${w.pages.join(',')}'], [
        'null|1,2,3,4',
        '4|5,6,7,8',
        '8|9,10',
      ]);
      expect(windows[1].shown, [4, 5, 6, 7, 8]);
      expect(windows[1].withoutOverlap.shown, [4, 5, 6, 7, 8]);
      expect(windows[1].withoutOverlap.overlap, isNull);
      expect(windows[0].label, 'Seite 1–4');
    });

    test('viel Text → weniger Seiten je Abschnitt (mindestens eine)', () {
      final dense = List.filled(6, 'x' * 3000);
      final windows = planScanWindows(dense, firstPage: 1, lastPage: 6, maxNewPages: 4, charBudget: 7000);
      expect([for (final w in windows) w.pages], [
        [1, 2],
        [3, 4],
        [5, 6],
      ]);
      // Eine einzelne Seite über dem Budget bekommt trotzdem einen Abschnitt.
      final huge = planScanWindows([('y' * 20000)], firstPage: 1, lastPage: 1, charBudget: 7000);
      expect(huge.single.pages, [1]);
    });

    test('Teilbereich: der erste Abschnitt hat keine Überlappung; eine Seite ergibt einen Abschnitt', () {
      final windows = planScanWindows(const [], firstPage: 5, lastPage: 7, maxNewPages: 2);
      expect([for (final w in windows) '${w.overlap}|${w.pages.join(',')}'], [
        'null|5,6',
        '6|7',
      ]);
      expect(planScanWindows(const [], firstPage: 3, lastPage: 3).single.label, 'Seite 3');
    });
  });

  group('Antwort eines Abschnitts lesen', () {
    test('Seite ohne Angabe → erste NEUE Seite; Überarbeitungen und gelesene Seiten', () {
      final reply = AiService.parseScanWindow({
        'pages': [
          {'page': 3, 'tasks': 1},
          {'page': '4', 'tasks': 0},
          {'tasks': 2},
        ],
        'questions': [
          {'front': 'Ohne Seite', 'type': 'free_text', 'correctText': 'x'},
          {'front': 'Auf Seite 4', 'page': 4},
        ],
        'revisions': [
          {
            'n': 1,
            'question': {'front': 'Überarbeitet', 'type': 'free_text', 'correctText': 'y'},
          },
          {'n': 'kaputt', 'question': {}},
          {'n': 2, 'question': 'kein Objekt'},
          {'n': 1, 'question': {'front': 'zweite Angabe zu 1'}},
        ],
      }, shownPages: [3, 4, 5], overlapPage: 3);
      expect([for (final q in reply.questions) (q['front'], q['page'])], [('Ohne Seite', 4), ('Auf Seite 4', 4)]);
      expect(reply.revisions.keys, [1]);
      expect(reply.revisions[1]!['front'], 'Überarbeitet');
      expect(reply.revisions[1]!['page'], 3); // ohne Angabe: die Überlappungsseite
      expect(reply.pagesSeen, [3, 4]);
    });

    test('ohne Überlappung gibt es keine Überarbeitungen; ohne "pages" keine Angabe', () {
      final reply = AiService.parseScanWindow({
        'questions': [],
        'revisions': [
          {'n': 1, 'question': {'front': 'x'}},
        ],
      }, shownPages: [1, 2]);
      expect(reply.revisions, isEmpty);
      expect(reply.pagesSeen, isNull);
    });
  });

  group('fortlaufend lesen', () {
    test('die letzte Seite geht mit den bisherigen Fragen erneut mit; Fortsetzung wird überarbeitet, Doppeltes fällt weg',
        () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final shown = _shown(request);
        if (shown.first == 1) {
          return _chat({
            'pages': [
              {'page': 1, 'tasks': 1},
              {'page': 2, 'tasks': 1},
              {'page': 3, 'tasks': 1},
            ],
            'questions': [
              _free(1, 'Aufgabe 1: Nenne das Ohmsche Gesetz.', 'U = R · I'),
              _free(2, 'Aufgabe 2: Was ist eine Spannung?', 'Potentialdifferenz'),
              // Die Aufgabe geht auf Seite 4 weiter, hier ist sie noch unvollständig.
              _free(3, 'Aufgabe 3a: Berechne den Strom.', '2 A'),
            ],
          });
        }
        if (shown.first == 3) {
          return _chat({
            'pages': [
              {'page': 3, 'tasks': 0},
              {'page': 4, 'tasks': 1},
              {'page': 5, 'tasks': 1},
              {'page': 6, 'tasks': 1},
            ],
            'questions': [
              // Dieselbe Frage wie schon übernommen: darf nicht doppelt erscheinen.
              _free(3, 'Aufgabe 3a: Berechne den Strom.', '2 A'),
              _free(4, 'Aufgabe 4: Was ist ein Widerstand?', 'Bauelement'),
              _free(5, 'Aufgabe 5: Was ist Leistung?', 'P = U · I'),
              _free(6, 'Aufgabe 6: Was ist ein Kondensator?', 'Speichert Ladung'),
            ],
            'revisions': [
              {
                'n': 1,
                'question': _free(3, 'Aufgabe 3a: Berechne den Strom. (Fortsetzung auf Seite 4: bei U = 10 V, R = 5 Ω)', '2 A'),
              },
            ],
          });
        }
        return _chat({
          'pages': [
            {'page': 6, 'tasks': 0},
            {'page': 7, 'tasks': 1},
          ],
          'questions': [_free(7, 'Aufgabe 7: Was ist eine Spule?', 'Speichert Energie im Magnetfeld')],
          'revisions': [],
        });
      });
      final progress = <(int, int)>[];
      final scan = await _service(client).scan(
        pdfWithTexts(List.generate(7, (i) => 'Seite ${i + 1}')),
        firstPage: 1,
        lastPage: 7,
        contentOnly: true,
        fillMissingSolutions: false,
        onProgress: (d, t) => progress.add((d, t)),
      );

      // Drei Abschnitte, jeder ab dem zweiten mit der letzten Seite des vorigen.
      expect([for (final r in requests) _shown(r)], [
        [1, 2, 3],
        [3, 4, 5, 6],
        [6, 7],
      ]);
      expect(scan.windows, 3);
      expect(progress.last, (3, 3));
      expect(_system(requests[0]), isNot(contains('FORTLAUFENDER IMPORT')));
      expect(_system(requests[1]), contains('FORTLAUFENDER IMPORT'));
      expect(_system(requests[1]), contains('Dokument-Seite 3'));
      expect(_system(requests[1]), isNot(contains('{{')));

      // Die bisherigen Fragen der Überlappungsseite gehen mit – nummeriert.
      final context = _allText(requests[1]);
      expect(context, contains('Seite 3 ist die schon bearbeitete letzte Seite'));
      expect(context, contains('1. [free_text] Aufgabe 3a: Berechne den Strom. — Lösung: 2 A'));
      expect(context, isNot(contains('Aufgabe 2: Was ist eine Spannung?')));
      // Ohne Fragen auf der Überlappungsseite steht das dort ebenfalls.
      expect(_allText(requests[2]), contains('Aufgabe 6: Was ist ein Kondensator? — Lösung: Speichert Ladung'));

      // Ergebnis: jede Frage einmal, die Fortsetzung eingearbeitet, nach Seite sortiert.
      expect(scan.questions.map((q) => q.page), [1, 2, 3, 4, 5, 6, 7]);
      expect(scan.questions[2].front, contains('Fortsetzung auf Seite 4'));
      expect(scan.revised, 1);
      expect(scan.failedBatches, isEmpty);
      expect(scan.errors, isEmpty);
    });

    test('ein fehlgeschlagener Abschnitt: der nächste liest seine letzte Seite als neue Seite, offen bleibt nur der Rest',
        () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final shown = _shown(request);
        if (shown.contains(4)) return http.Response('boom', 500); // Abschnitt [3 | 4,5,6]
        return _chat({
          'pages': [for (final p in shown) {'page': p, 'tasks': 1}],
          'questions': [for (final p in shown) _free(p, 'Frage auf Seite $p?', 'A$p')],
          'revisions': [],
        });
      });
      // Abschnitt 3 wäre [6 | 7, 8]; da Abschnitt 2 ausfiel, ist Seite 6 dort NEU.
      final scan = await _service(client).scan(
        pdfWithTexts(List.generate(8, (i) => 'Seite ${i + 1}')),
        firstPage: 1,
        lastPage: 8,
        contentOnly: true,
        fillMissingSolutions: false,
      );
      expect([for (final r in requests) _shown(r)], [
        [1, 2, 3],
        [3, 4, 5, 6],
        [6, 7, 8],
      ]);
      expect(_system(requests[2]), isNot(contains('FORTLAUFENDER IMPORT')));
      // Seite 6 hat der dritte Abschnitt gelesen – offen sind nur 4 und 5.
      expect(scan.failedBatches, [
        [4, 5],
      ]);
      expect(scan.errors.single, startsWith('Seite 4–6'));
      expect(scan.questions.map((q) => q.page), [1, 2, 3, 6, 7, 8]);
    });

    test('eine Seite, die die KI nicht gelesen zu haben meldet, wird einzeln nachgelesen', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final shown = _shown(request);
        if (shown.length == 1) {
          return _chat({
            'pages': [
              {'page': shown.single, 'tasks': 1},
            ],
            'questions': [_free(shown.single, 'Frage auf Seite ${shown.single}?', 'A')],
          });
        }
        // Seite 3 fehlt in "pages" und in den Fragen.
        return _chat({
          'pages': [
            {'page': 1, 'tasks': 1},
            {'page': 2, 'tasks': 1},
          ],
          'questions': [_free(1, 'Frage auf Seite 1?', 'A'), _free(2, 'Frage auf Seite 2?', 'A')],
        });
      });
      final scan = await _service(client).scan(
        pdfWithTexts(['Seite 1', 'Seite 2', 'Seite 3']),
        firstPage: 1,
        lastPage: 3,
        contentOnly: true,
        fillMissingSolutions: false,
      );
      expect([for (final r in requests) _shown(r)], [
        [1, 2, 3],
        [3],
      ]);
      expect(scan.questions.map((q) => q.page), [1, 2, 3]);
      expect(scan.notes.single, contains('Seite 3'));
    });

    test('wiederholen ohne Überlappung: nur die genannten Seiten', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return _chat({'questions': [_free(_shown(request).first, 'Frage?', 'A')]});
      });
      final scan = await _service(client).scan(
        pdfWithTexts(List.generate(6, (i) => 'Seite ${i + 1}')),
        firstPage: 1,
        lastPage: 6,
        contentOnly: true,
        fillMissingSolutions: false,
        onlyBatches: const [
          [4, 5],
        ],
      );
      expect([for (final r in requests) _shown(r)], [
        [4, 5],
      ]);
      expect(_system(requests.single), isNot(contains('FORTLAUFENDER IMPORT')));
      expect(scan.questions.map((q) => q.page), [4]);
    });
  });

  group('mehrere PDFs', () {
    test('jede Datei fortlaufend, Fragen tragen ihre Datei, Lösungen aus der anderen Datei stehen als Nachschlagewerk da',
        () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final shown = _shown(request);
        return _chat({
          'pages': [for (final p in shown) {'page': p, 'tasks': 1}],
          'questions': [
            for (final p in shown)
              if (!(shown.length > 1 && p == shown.first && _system(request).contains('FORTLAUFENDER IMPORT')))
                _free(p, 'Frage auf Seite $p?', 'A'),
          ],
          'revisions': [],
        });
      });
      final progress = <(int, int, String)>[];
      final scans = await _service(client, pagesPerRequest: 2).scanMany(
        [
          ImportSource(name: 'Blatt.pdf', bytes: pdfWithTexts(['Aufgabe A', 'Aufgabe B', 'Aufgabe C'])),
          ImportSource(name: 'Musterlösung.pdf', bytes: pdfWithTexts(['Lösung A: 42', 'Lösung B: 7'])),
        ],
        contentOnly: true,
        fillMissingSolutions: true,
        extraReference: [const ImportReferencePage(owner: 'Skript.docx', label: 'Skript.docx, Teil 1', text: 'Hinweis aus Word')],
        onProgress: (d, t, label) => progress.add((d, t, label)),
      );
      // Blatt: 3 Seiten → 2 Abschnitte (1,2 | 2,3); Lösung: 2 Seiten → 1 Abschnitt.
      expect(scans, hasLength(2));
      expect(scans[0].windows, 2);
      expect(scans[1].windows, 1);
      expect(progress.last.$1, 3);
      expect(progress.last.$2, 3);
      expect(progress.map((p) => p.$3).where((l) => l.startsWith('Blatt.pdf')), isNotEmpty);
      expect(scans[0].questions.every((q) => q.sourceFile == 'Blatt.pdf'), isTrue);
      expect(scans[1].questions.every((q) => q.sourceFile == 'Musterlösung.pdf'), isTrue);
      expect(scans[0].questions.map((q) => q.page), [1, 2, 3]);

      // Die Anfragen für das Blatt (beide Abschnitte) kennen die Lösungen der anderen Datei und das
      // Word-Dokument, nicht sich selbst; die für die Musterlösung dagegen das Blatt.
      final forBlatt = requests.where((r) => _allText(r).contains('=== Musterlösung.pdf, Seite 1 ===')).toList();
      expect(forBlatt, hasLength(2));
      final reference = _allText(forBlatt.first);
      expect(reference, contains('Lösung A: 42'));
      expect(reference, contains('Hinweis aus Word'));
      expect(reference, isNot(contains('=== Blatt.pdf, Seite')));
      final forLoesung = requests.where((r) => _allText(r).contains('=== Blatt.pdf, Seite 1 ===')).toList();
      expect(forLoesung, hasLength(1));
      expect(_allText(forLoesung.single), isNot(contains('=== Musterlösung.pdf, Seite')));
    });

    test('erneut lesen: nur die genannten Seiten der genannten Datei', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return _chat({'questions': [_free(_shown(request).first, 'Frage?', 'A')]});
      });
      final scans = await _service(client).scanMany(
        [
          ImportSource(name: 'A.pdf', bytes: pdfWithTexts(['Eins', 'Zwei', 'Drei'])),
          ImportSource(name: 'B.pdf', bytes: pdfWithTexts(['Vier'])),
        ],
        contentOnly: true,
        fillMissingSolutions: true,
        retry: const {
          'A.pdf': [
            [2, 3],
          ],
        },
      );
      expect([for (final r in requests) _shown(r)], [
        [2, 3],
      ]);
      expect(scans[0].questions.map((q) => q.sourceFile), ['A.pdf']);
      expect(scans[1].questions, isEmpty);
    });

    test('Abbrechen: keine weitere Datei wird begonnen', () async {
      var calls = 0;
      var cancelled = false;
      final client = MockClient((request) async {
        calls++;
        cancelled = true;
        return _chat({'questions': []});
      });
      await PdfQuestionImportService(
        ai: AiService(apiKey: 'k', model: 'vision', client: client),
        parallelRequests: 1,
      ).scanMany(
        [
          ImportSource(name: 'A.pdf', bytes: pdfWithTexts(['Eins'])),
          ImportSource(name: 'B.pdf', bytes: pdfWithTexts(['Zwei'])),
        ],
        contentOnly: true,
        fillMissingSolutions: true,
        isCancelled: () => cancelled,
      );
      expect(calls, 1);
    });
  });

  group('Nachschlagewerk', () {
    test('passt alles in den Umfang, kommt alles mit (ohne die eigene Datei)', () {
      final ref = ImportReference(const [
        ImportReferencePage(owner: 'A', label: 'A, Seite 1', text: 'Eigener Text'),
        ImportReferencePage(owner: 'B', label: 'B, Seite 1', text: 'Fremde Lösung'),
      ]);
      final text = ref.forWindow('irgendwas', excludeOwner: 'A');
      expect(text, '=== B, Seite 1 ===\nFremde Lösung');
      expect(ref.forWindow('egal', excludeOwner: 'B'), contains('Eigener Text'));
      expect(ImportReference(const []).forWindow('x'), isEmpty);
    });

    test('bei zu viel Text nur die zum Abschnitt passenden Seiten – beliebig viele Dateien', () {
      final pages = [
        for (var i = 0; i < 40; i++)
          ImportReferencePage(
            owner: 'Datei${i ~/ 4}.pdf',
            label: 'Datei${i ~/ 4}.pdf, Seite ${i % 4 + 1}',
            text: i == 27
                ? 'Kondensator Kapazität Ladung Plattenabstand Dielektrikum ${'x' * 800}'
                : 'Beliebiger Füllinhalt Nummer $i ${'y' * 800}',
          ),
      ];
      final ref = ImportReference(pages);
      final text = ref.forWindow(
        'Aufgabe: Berechne die Kapazität des Kondensators mit Plattenabstand und Dielektrikum.',
        excludeOwner: 'Datei0.pdf',
        charBudget: 3000,
      );
      expect(text, contains('=== Datei6.pdf, Seite 4 ==='));
      expect(text, contains('Kondensator Kapazität'));
      expect(text.length, lessThan(3200));
      // Ohne passende Begriffe bleibt nichts.
      expect(ref.forWindow('Abschnitt ohne Bezug zu irgendwas Wichtigem', charBudget: 3000), isEmpty);
    });

    test('Text ohne Seiten wird an Absätzen in Stücke geteilt', () {
      final text = List.generate(10, (i) => 'Absatz $i ${'z' * 900}').join('\n\n');
      final pages = ImportReference.pagesOfText('Skript.docx', text, chunk: 2500);
      expect(pages.length, greaterThan(2));
      expect(pages.every((p) => p.owner == 'Skript.docx'), isTrue);
      expect(pages.map((p) => p.text).join('\n\n'), contains('Absatz 9'));
      expect(pages.first.label, 'Skript.docx, Teil 1');
    });
  });
}
