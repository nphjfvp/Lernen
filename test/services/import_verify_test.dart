import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/import_stage_service.dart';
import 'package:lernen/services/import_verify_service.dart';
import 'package:lernen/services/pdf_question_import_service.dart';

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

AiService _ai(MockClient client) => AiService(apiKey: 'k', model: 'm', client: client);

Map<String, dynamic> _body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
String _system(http.Request r) => (_body(r)['messages'] as List)[0]['content'] as String;
String _user(http.Request r) => (_body(r)['messages'] as List)[1]['content'] as String;

const _longText = 'Aufgabe mit genug Text, damit die Seite als lesbar gilt.';

void main() {
  group('Antwort der Prüfung lesen', () {
    test('fehlende/fremde Seite → erste Seite des Pakets, unbekannte Art → not_in_document, Unbrauchbares fällt weg', () {
      final v = AiService.parseImportVerification({
        'documentCount': 7,
        'missing': [
          {'page': 3, 'task': 'Aufgabe 2b', 'reason': 'Steht auf Seite 3.'},
          {'page': 99, 'task': 'Aufgabe 5', 'reason': ''},
          {'page': 3, 'task': '   ', 'reason': 'ohne Text'},
        ],
        'surplus': [
          {'n': 2, 'kind': 'duplicate', 'reason': 'doppelt'},
          {'n': '4', 'kind': 'gibtEsNicht', 'reason': 'erfunden'},
          {'kind': 'altered', 'reason': 'ohne Nummer'},
        ],
        'note': ' unleserlich ',
      }, [3, 4]);
      expect(v.documentCount, 7);
      expect(v.missing.map((m) => (m.page, m.task)), [(3, 'Aufgabe 2b'), (3, 'Aufgabe 5')]);
      expect(v.missing.last.reason, 'Keine Begründung angegeben.');
      expect(v.surplus.map((s) => (s.n, s.kind)), [(2, 'duplicate'), (4, 'not_in_document')]);
      expect(v.note, 'unleserlich');
    });

    test('nichts gemeldet → alles leer', () {
      final v = AiService.parseImportVerification(const {}, [1]);
      expect(v.documentCount, isNull);
      expect(v.missing, isEmpty);
      expect(v.surplus, isEmpty);
    });
  });

  group('ImportVerifyService', () {
    test('zählt, gleicht ab und begründet – Bezug (ref) und Seiten bleiben erhalten', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final user = _user(request);
        if (user.contains('=== Seite 1 ===')) {
          return _chat({
            'documentCount': 2,
            'missing': [],
            'surplus': [
              {'n': 2, 'kind': 'not_in_document', 'reason': 'Im Dokument gibt es keine Aufgabe zu Induktivität.'},
            ],
            'note': '',
          });
        }
        return _chat({
          'documentCount': 3,
          'missing': [
            {'page': 3, 'task': 'Aufgabe 2b: Berechnen Sie R.', 'reason': 'Steht auf Seite 3, keine Frage deckt sie ab.'},
          ],
          'surplus': [],
          'note': 'Seite 4 war teilweise unleserlich.',
        });
      });
      final service = ImportVerifyService(ai: _ai(client), pagesPerRequest: 2, parallelRequests: 1);
      final report = await service.verify(
        pageTexts: [_longText, _longText, _longText, _longText, ''],
        items: const [
          ImportedItem(ref: 10, page: 1, front: 'Frage A', answer: 'a'),
          ImportedItem(ref: 11, page: 2, front: 'Frage Induktivität', answer: 'b'),
          ImportedItem(ref: 12, page: 4, front: 'Frage C', answer: 'c'),
          ImportedItem(ref: 13, page: 5, front: 'Frage auf Seite ohne Text', answer: 'd'),
        ],
        contentOnly: true,
        fileName: 'Blatt.pdf',
      );

      // Vier lesbare Seiten → zwei Anfragen; die Seite ohne Text wird nicht geprüft.
      expect(requests, hasLength(2));
      expect(report.uncheckedPages, [5]);
      expect(report.documentCount, 5);
      expect(report.importedCount, 3); // die Frage auf Seite 5 zählt nicht mit
      expect(report.agrees, isFalse);
      expect(report.findings.map((f) => (f.kind, f.page, f.ref)), [
        (ImportFindingKind.notInDocument, 2, 11),
        (ImportFindingKind.missing, 3, null),
      ]);
      expect(report.findings.first.text, 'Frage Induktivität');
      expect(report.findings.first.reason, contains('Induktivität'));
      expect(report.findings.first.fileName, 'Blatt.pdf');
      expect(report.missingCount, 1);
      expect(report.surplusCount, 1);
      expect(report.notes, ['Seite 4 war teilweise unleserlich.']);

      // Die zweite KI bekommt den Seitentext und die nummerierte Liste.
      final first = requests.firstWhere((r) => _user(r).contains('=== Seite 1 ==='));
      expect(_user(first), contains('1. (Seite 1) Frage A — Lösung: a'));
      expect(_user(first), contains('2. (Seite 2) Frage Induktivität'));
      expect(_system(first), contains('nur inhaltliche Fragen'));
    });

    test('stimmt alles überein, sind beide KIs einig', () async {
      final client = MockClient((_) async => _chat({'documentCount': 1, 'missing': [], 'surplus': []}));
      final report = await ImportVerifyService(ai: _ai(client)).verify(
        pageTexts: [_longText],
        items: const [ImportedItem(ref: 0, page: 1, front: 'Nur eine Frage')],
        contentOnly: false,
      );
      expect(report.agrees, isTrue);
      expect(report.documentCount, 1);
      expect(report.findings, isEmpty);
    });

    test('ein fehlgeschlagenes Paket wird gemeldet und gilt nicht als Einigkeit', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final report = await ImportVerifyService(ai: _ai(client)).verify(
        pageTexts: [_longText],
        items: const [ImportedItem(ref: 0, page: 1, front: 'Frage')],
        contentOnly: false,
      );
      expect(report.errors, hasLength(1));
      expect(report.errors.single, contains('Seite 1'));
      expect(report.documentCount, isNull);
      expect(report.agrees, isFalse);
    });

    test('Berichte mehrerer Dateien werden zusammengeführt', () {
      const a = ImportCheckReport(documentCount: 2, importedCount: 2, findings: [], uncheckedPages: [3]);
      const b = ImportCheckReport(
        documentCount: 4,
        importedCount: 3,
        findings: [
          ImportFinding(kind: ImportFindingKind.missing, page: 1, text: 'T', reason: 'R', fileName: 'b.pdf'),
        ],
      );
      final merged = ImportCheckReport.merge([(fileName: 'a.pdf', report: a), (fileName: 'b.pdf', report: b)]);
      expect(merged.documentCount, 6);
      expect(merged.importedCount, 5);
      expect(merged.findings, hasLength(1));
      expect(merged.notes.single, contains('a.pdf'));
      expect(merged.notes.single, contains('Seite 3'));
      // Eine einzelne Datei behält ihren Bericht.
      expect(ImportCheckReport.merge([(fileName: 'a.pdf', report: a)]), same(a));
    });
  });

  group('Stufen ergänzen', () {
    test('Antwort: unerwünschte, doppelte und Original-Stufen fallen weg', () {
      final expansions = AiService.parseStageExpansions({
        'cards': [
          {
            'n': 1,
            'level': 'mittel',
            'group': '  Ohmsches   Gesetz ',
            'variants': [
              {'level': 'leicht', 'type': 'single_choice', 'front': 'A'},
              {'level': 'leicht', 'type': 'single_choice', 'front': 'A2'}, // doppelt
              {'level': 'mittel', 'type': 'fill_blank', 'front': 'B'}, // Stufe des Originals
              {'level': 'schwer', 'type': 'free_text', 'front': 'C'}, // nicht gewünscht
              {'level': 'kaputt', 'front': 'D'},
            ],
          },
          {'n': 'x'},
        ],
      }, ['leicht', 'mittel']);
      expect(expansions.keys, [1]);
      expect(expansions[1]!.level, 1);
      expect(expansions[1]!.group, 'Ohmsches Gesetz');
      expect(expansions[1]!.variants.map((v) => v['front']), ['A']);
    });

    test('Dienst: Portionen, Normalisierung, Ordner- und Stufen-Ersatz, Fehler zählen', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        final user = _user(request);
        if (user.contains('1. [free_text] Fehlerfrage')) return http.Response('boom', 500);
        return _chat({
          'cards': [
            {
              'n': 1,
              // Keine Stufe und kein Ordner genannt → aus dem Typ bzw. der Frage abgeleitet.
              'variants': [
                {
                  'level': 'leicht',
                  'type': 'single_choice',
                  'front': 'Welche Einheit hat die Spannung?',
                  'options': [
                    {'text': 'Volt', 'isCorrect': true},
                    {'text': 'Ampere', 'isCorrect': false},
                    {'text': 'Ohm', 'isCorrect': false},
                  ],
                },
                // Ohne Optionen wäre das eine zurückgestufte Notlösung → verworfen.
                {'level': 'mittel', 'type': 'single_choice', 'front': 'Unvollständig', 'back': 'x'},
              ],
            },
          ],
        });
      });
      final run = await ImportStageService(ai: _ai(client), batchSize: 1).expand(
        const [
          StageInput(ref: 5, type: 'free_text', front: 'Nenne die Einheit der Spannung.', answer: 'Volt'),
          StageInput(ref: 6, type: 'free_text', front: 'Fehlerfrage', answer: 'x'),
        ],
        levels: const ['leicht', 'mittel'],
      );
      expect(calls, 2);
      expect(run.failedCards, 1);
      expect(run.droppedVariants, 1);
      final r = run.results[5]!;
      expect(r.level, 2); // freeText = schwer
      expect(r.group, 'Nenne die Einheit der Spannung.');
      expect(r.variants, hasLength(1));
      expect(r.variants.single['level'], 'leicht');
      expect(r.variants.single['type'], 'single_choice');
      expect(run.results.containsKey(6), isFalse);
    });

    test('Ordnernamen sind je Frage eindeutig – auch gegen schon vergebene', () async {
      final client = MockClient((_) async => _chat({
            'cards': [
              {'n': 1, 'level': 'leicht', 'group': 'Ohmsches Gesetz', 'variants': []},
              {'n': 2, 'level': 'leicht', 'group': 'ohmsches gesetz', 'variants': []},
              {'n': 3, 'level': 'leicht', 'group': 'Kirchhoff', 'variants': []},
            ],
          }));
      final run = await ImportStageService(ai: _ai(client)).expand(
        const [
          StageInput(ref: 0, type: 'flashcard', front: 'A', answer: 'a'),
          StageInput(ref: 1, type: 'flashcard', front: 'B', answer: 'b'),
          StageInput(ref: 2, type: 'flashcard', front: 'C', answer: 'c'),
        ],
        levels: const ['mittel'],
        takenGroups: const ['Kirchhoff'],
      );
      expect([for (final i in [0, 1, 2]) run.results[i]!.group], ['Ohmsches Gesetz', 'ohmsches gesetz 2', 'Kirchhoff 2']);
    });

    test('Anfrage nennt gewünschte Stufen und den Typ je Stufe', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return _chat({'cards': []});
      });
      await _ai(client).expandQuestionStages(
        const [(n: 1, type: 'flashcard', front: 'Frage', answer: 'Antwort')],
        levels: const ['schwer', 'leicht'],
        tierTypes: const {'schwer': QuestionType.table},
      );
      final system = _system(seen);
      expect(system, contains('leicht, schwer'));
      expect(system, contains('- "leicht": Zieltyp "single_choice"'));
      expect(system, contains('- "schwer": Zieltyp "table"'));
      expect(system, isNot(contains('- "mittel"')));
      expect(_user(seen), contains('1. [flashcard] Frage — Lösung: Antwort'));
    });
  });

  test('Nachholen einer Aufgabe: "focus" geht mit in die Seiten-Anfrage', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return _chat({'questions': []});
    });
    await _ai(client).scanPdfPagesForQuestions(
      null,
      pageNumbers: const [3],
      contentOnly: false,
      fillMissingSolutions: true,
      pageImages: [Uint8List.fromList([1, 2, 3])],
      pageTexts: const ['Text'],
      focus: 'Aufgabe 2b: Berechnen Sie R.',
    );
    final content = (_body(seen)['messages'] as List)[1]['content'] as List;
    final texts = [for (final c in content) if (c['type'] == 'text') c['text'] as String];
    expect(texts.any((t) => t.contains('NUR EINE AUFGABE') && t.contains('Aufgabe 2b: Berechnen Sie R.')), isTrue);
  });

  test('Import → Karten: Stufe und Ordner werden mitgenommen (Ordner je Import eindeutig)', () {
    final original = ScannedQuestion(
      page: 1,
      data: {'type': 'free_text', 'front': 'Frage?', 'correctText': 'A', 'level': 'schwer', 'group': 'Ohm'},
      solutionByAi: false,
    );
    final variant = ScannedQuestion(
      page: 1,
      data: {'type': 'free_text', 'front': 'Leichter?', 'correctText': 'B', 'level': 'leicht', 'group': 'Ohm'},
      solutionByAi: true,
    )..variantOf = original;
    final plain = ScannedQuestion(
      page: 2,
      data: {'type': 'free_text', 'front': 'Ohne Ordner?', 'correctText': 'C'},
      solutionByAi: false,
    );
    final now = DateTime(2026, 9, 29, 12);
    final cards = PdfQuestionImportService.toFlashcards([original, variant, plain], moduleId: 'm', now: now);
    expect(cards[0].stageLevel, 2);
    expect(cards[1].stageLevel, 0);
    expect(cards[0].stageGroup, cards[1].stageGroup);
    expect(cards[0].stageGroup, 'Ohm#${now.millisecondsSinceEpoch}');
    expect(cards[2].stageGroup, isNull);
    expect(cards[2].stageLevel, isNull);
  });
}
