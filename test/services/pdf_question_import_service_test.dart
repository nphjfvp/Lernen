import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/pdf_page_renderer.dart';
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

/// Seitenbild 400×600: links rot, rechts blau.
Future<Uint8List> _pagePng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawRect(const ui.Rect.fromLTWH(0, 0, 200, 600), ui.Paint()..color = const ui.Color(0xFFFF0000))
    ..drawRect(const ui.Rect.fromLTWH(200, 0, 200, 600), ui.Paint()..color = const ui.Color(0xFF0000FF));
  final image = await recorder.endRecording().toImage(400, 600);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// Größe und RGBA-Farbe eines Pixels (relativ 0..1) eines PNG.
Future<({int width, int height, int rgba})> _probe(String base64Png, double x, double y) async {
  final image = (await (await ui.instantiateImageCodec(base64Decode(base64Png))).getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final px = (x * (image.width - 1)).round();
  final py = (y * (image.height - 1)).round();
  return (width: image.width, height: image.height, rgba: data.getUint32((py * image.width + px) * 4));
}

class _FakeRenderer implements PageImageRenderer {
  _FakeRenderer(this.png, {this.missing = const {}});
  final Uint8List png;
  final Set<int> missing;
  final rendered = <int>[];
  bool closed = false;

  @override
  Future<Uint8List?> renderPng(int page) async {
    rendered.add(page);
    return missing.contains(page) ? null : png;
  }

  @override
  Future<void> close() async => closed = true;
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

  group('mit Seitenbildern', () {
    test('KI sieht Bilder und Text, Abbildungen werden ausgeschnitten, Stellen umgerechnet', () async {
      final png = await _pagePng();
      final renderer = _FakeRenderer(png);
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return _chat({
          'questions': [
            {
              'page': 1,
              'type': 'free_text',
              'front': 'Welche Farbe hat die rechte Hälfte?',
              'correctText': 'Blau',
              'imageBox': [0.5, 0.0, 1.0, 0.5],
              'imageCovers': [
                [0.6, 0.1, 0.8, 0.2],
              ],
            },
            {'page': 1, 'type': 'free_text', 'front': 'Ohne Bild?', 'correctText': 'Ja'},
            {
              'page': 2,
              'type': 'diagram_label',
              'front': 'Beschrifte die Abbildung.',
              'imageBox': [0.0, 0.0, 0.5, 0.5],
              'targets': [
                {'box': [0.1, 0.1, 0.2, 0.2], 'label': 'A'},
              ],
            },
            {
              'page': 2,
              'type': 'mark_image',
              'front': 'Markiere die Mitte.',
              'targets': [
                {'box': [0.4, 0.4, 0.6, 0.6]},
              ],
            },
          ],
        });
      });
      final scan = await PdfQuestionImportService(
        ai: AiService(apiKey: 'k', model: 'vision', client: client),
        renderer: (_) async => renderer,
      ).scan(pdfWithPages(2), firstPage: 1, lastPage: 2, contentOnly: false, fillMissingSolutions: true);

      // Anfrage: Seitenbilder statt PDF-Datei, dazu der Seitentext.
      final content = (body['messages'] as List)[1]['content'] as List;
      expect(content.where((c) => c['type'] == 'image_url').length, 2);
      expect(content.where((c) => c['type'] == 'file'), isEmpty);
      expect(content.map((c) => c['text'] ?? '').join('\n'), contains('Seite 2'));
      expect((body['messages'] as List)[0]['content'], contains('imageBox'));
      expect(scan.usedPageImages, isTrue);
      expect(renderer.rendered, [1, 2]);
      expect(renderer.closed, isTrue);

      expect(scan.questions.map((q) => q.front), [
        'Welche Farbe hat die rechte Hälfte?',
        'Ohne Bild?',
        'Beschrifte die Abbildung.',
        'Markiere die Mitte.',
      ]);

      // Ausschnitt oben rechts (mit etwas Rand), Abdeckung weiß.
      final figure = scan.questions[0].imageBase64!;
      final middle = await _probe(figure, 0.5, 0.75);
      expect(middle.width, closeTo(208, 2));
      expect(middle.height, closeTo(312, 2));
      expect(middle.rgba, 0x0000FFFF);
      expect((await _probe(figure, 0.42, 0.29)).rgba, 0xFFFFFFFF);

      expect(scan.questions[1].imageBase64, isNull);

      // Stelle in Ausschnitt-Koordinaten: 0.15 / 0.52.
      final label = parseImageTargets(scan.questions[2].data['imageTargets'])!.single;
      expect(label.label, 'A');
      expect(label.x, closeTo(0.15 / 0.52, 0.01));
      expect(label.w, closeTo(0.1 / 0.52, 0.01));

      // Bildfrage ohne Bereich: ganze Seite.
      final mark = parseImageTargets(scan.questions[3].data['imageTargets'])!.single;
      expect(mark.x, closeTo(0.5, 0.01));
      expect((await _probe(scan.questions[3].imageBase64!, 0.5, 0.5)).width, 400);

      final cards = PdfQuestionImportService.toFlashcards(scan.questions, moduleId: 'm1', now: DateTime(2026, 9, 27));
      expect(cards[0].imageBase64, figure);
      expect(cards[2].type, QuestionType.diagramLabel);
      expect(cards[2].imageTargets!.single.label, 'A');
      expect(cards[1].imageBase64, isNull);
    });

    test('fehlt ein Seitenbild, geht das Paket als PDF an die KI; Bildfragen ohne Bild fallen weg', () async {
      final png = await _pagePng();
      final types = <String>[];
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        types.addAll([for (final c in (body['messages'] as List)[1]['content'] as List) c['type'] as String]);
        return _chat({
          'questions': [
            {'page': 1, 'type': 'free_text', 'front': 'Frage?', 'correctText': 'x', 'imageBox': [0, 0, 1, 1]},
            {
              'page': 1,
              'type': 'mark_image',
              'front': 'Markiere.',
              'targets': [
                {'box': [0.4, 0.4, 0.6, 0.6]},
              ],
            },
          ],
        });
      });
      final scan = await PdfQuestionImportService(
        ai: AiService(apiKey: 'k', model: 'vision', client: client),
        renderer: (_) async => _FakeRenderer(png, missing: {2}),
      ).scan(pdfWithPages(2), firstPage: 1, lastPage: 2, contentOnly: false, fillMissingSolutions: true);

      expect(types, contains('file'));
      expect(types, isNot(contains('image_url')));
      expect(scan.usedPageImages, isFalse);
      expect(scan.questions.map((q) => q.front), ['Frage?']);
      expect(scan.questions.single.imageBase64, isNull);
      expect(scan.dropped, 1);
    });
  });
}
