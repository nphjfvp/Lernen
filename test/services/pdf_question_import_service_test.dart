import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/pdf_question_import_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Kleine PDF mit [pages] Seiten ("Seite n" als Text).
Uint8List pdfWithPages(int pages) {
  final document = PdfDocument();
  for (var i = 1; i <= pages; i++) {
    document.pages.add().graphics.drawString('Seite $i', PdfStandardFont(PdfFontFamily.helvetica, 12));
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

http.Response _chat(Object json) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': jsonEncode(json)},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Die Dokument-Seiten, die eine Anfrage laut Nachricht enthält.
List<int> requestedPages(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final text = ((body['messages'] as List)[1]['content'] as List).first['text'] as String;
  return [for (final m in RegExp(r'Dokument-Seite (\d+)').allMatches(text)) int.parse(m.group(1)!)];
}

void main() {
  test('Seiten werden in Pakete aufgeteilt', () {
    expect(PdfQuestionImportService.batches(1, 7, 3), [
      [1, 2, 3],
      [4, 5, 6],
      [7],
    ]);
    expect(PdfQuestionImportService.batches(5, 5, 3), [
      [5],
    ]);
  });

  test('KI-Antwort: fehlende oder fremde Seitenzahl wird zur ersten Seite des Pakets', () {
    final parsed = AiService.parseScannedQuestions({
      'questions': [
        {'front': 'A', 'page': 5},
        {'front': 'B', 'page': 99},
        {'front': 'C'},
        'kaputt',
      ],
    }, [4, 5, 6]);
    expect(parsed.map((q) => q['page']), [5, 4, 4]);
  });

  test('sucht jede Seite ab, sortiert nach Seite, merkt fehlgeschlagene Pakete und kann sie wiederholen', () async {
    final pdf = pdfWithPages(5);
    var failOnce = true;
    final prompts = <String>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      prompts.add((body['messages'] as List)[0]['content'] as String);
      final pages = requestedPages(request);
      if (pages.contains(4) && failOnce) {
        failOnce = false;
        return http.Response('boom', 500);
      }
      return _chat({
        'questions': [
          for (final p in pages)
            {
              'page': p,
              'type': 'free_text',
              'front': 'Frage auf Seite $p?',
              'correctText': 'Antwort $p',
              'solutionFromDocument': p != 2,
            },
          if (pages.contains(1)) {'type': 'single_choice', 'front': 'Ohne Optionen', 'page': 1},
        ],
      });
    });
    final service = PdfQuestionImportService(
      ai: AiService(apiKey: 'k', model: 'vision', client: client),
      pagesPerRequest: 3,
      parallelRequests: 2,
    );

    final progress = <int>[];
    final scan = await service.scan(
      pdf,
      firstPage: 1,
      lastPage: 5,
      contentOnly: true,
      fillMissingSolutions: false,
      onProgress: (done, _) => progress.add(done),
    );
    expect(scan.questions.map((q) => q.page), [1, 2, 3]);
    expect(scan.questions[1].solutionByAi, isTrue);
    expect(scan.questions[0].solutionByAi, isFalse);
    expect(scan.dropped, 1); // Single-Choice ohne Optionen
    expect(scan.failedBatches, [
      [4, 5],
    ]);
    expect(scan.errors.single, startsWith('Seite 4–5'));
    expect(progress.last, 2);
    expect(prompts.first, contains('NUR inhaltliche'));
    expect(prompts.first, contains('lass die Frage weg'));

    final retry = await service.scan(
      pdf,
      firstPage: 1,
      lastPage: 5,
      contentOnly: true,
      fillMissingSolutions: false,
      onlyBatches: scan.failedBatches,
    );
    expect(retry.questions.map((q) => q.page), [4, 5]);
    expect(retry.failedBatches, isEmpty);
  });

  test('"Jede Frage" und Lösungen ergänzen stehen im Prompt', () async {
    String? system;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      system = (body['messages'] as List)[0]['content'] as String;
      return _chat({'questions': []});
    });
    await PdfQuestionImportService(ai: AiService(apiKey: 'k', model: 'vision', client: client)).scan(
      pdfWithPages(1),
      firstPage: 1,
      lastPage: 1,
      contentOnly: false,
      fillMissingSolutions: true,
    );
    expect(system, contains('JEDE Frage und Aufgabe'));
    expect(system, contains('beantworte die Frage selbst'));
    expect(system, isNot(contains('{{')));
  });

  test('Abbrechen startet keine weiteren Pakete', () async {
    var calls = 0;
    var cancelled = false;
    final client = MockClient((request) async {
      calls++;
      cancelled = true;
      return _chat({'questions': []});
    });
    await PdfQuestionImportService(
      ai: AiService(apiKey: 'k', model: 'vision', client: client),
      pagesPerRequest: 1,
      parallelRequests: 1,
    ).scan(
      pdfWithPages(4),
      firstPage: 1,
      lastPage: 4,
      contentOnly: true,
      fillMissingSolutions: true,
      isCancelled: () => cancelled,
    );
    expect(calls, 1);
  });

  test('Import als Karten: Reihenfolge der PDF, Fach/Einheit, sofort fürs Daily Quiz', () {
    final questions = [
      ScannedQuestion(page: 1, data: {'type': 'free_text', 'front': 'Eins?', 'correctText': '1'}, solutionByAi: false),
      ScannedQuestion(
        page: 2,
        data: {
          'type': 'single_choice',
          'front': 'Zwei?',
          'options': [
            {'text': 'a', 'isCorrect': true},
            {'text': 'b', 'isCorrect': false},
          ],
        },
        solutionByAi: true,
      ),
    ];
    final cards = PdfQuestionImportService.toFlashcards(
      questions,
      moduleId: 'm1',
      unitId: 'u1',
      now: DateTime(2026, 9, 27),
    );
    expect(cards.map((c) => c.front), ['Eins?', 'Zwei?']);
    expect(cards[1].type, QuestionType.singleChoice);
    expect(cards[1].options!.length, 2);
    expect(cards.every((c) => c.priorityIntroduction && c.unitId == 'u1' && c.moduleId == 'm1'), isTrue);
    expect(cards[0].createdAt.isBefore(cards[1].createdAt), isTrue);
  });
}
