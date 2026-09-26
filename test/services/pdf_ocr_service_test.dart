import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/pdf_ocr_service.dart';
import 'package:lernen/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// PDF mit [pages] Seiten; Seiten, deren Eintrag null ist, bleiben leer
/// (wie ein Scan ohne Text-Ebene).
Uint8List _pdf(List<String?> pages) {
  final document = PdfDocument();
  for (final text in pages) {
    final page = document.pages.add();
    if (text != null) {
      page.graphics.drawString(text, PdfStandardFont(PdfFontFamily.helvetica, 12),
          bounds: const Rect.fromLTWH(0, 0, 400, 100));
    }
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

void main() {
  group('PdfOcrService – Seitenauswahl', () {
    const long = 'Dies ist eine ganz normale Seite mit genug Text.';

    test('automatisch nur, wenn mindestens die Hälfte der Seiten leer ist', () {
      expect(PdfOcrService.shouldOcr([long, long, long, '']), isFalse);
      expect(PdfOcrService.shouldOcr([long, '', '', long]), isTrue);
      expect(PdfOcrService.shouldOcr([long, long, long, ''], force: true), isTrue);
      expect(PdfOcrService.shouldOcr([long, long], force: true), isFalse);
    });

    test('gruppiert aufeinanderfolgende leere Seiten, höchstens maxGroupSize', () {
      expect(PdfOcrService.pagesNeedingOcr(['', '', long, '', long, '', '', '']), [
        [0, 1],
        [3],
        [5, 6, 7],
      ]);
      expect(PdfOcrService.pagesNeedingOcr(['', '', '', ''], maxGroupSize: 3), [
        [0, 1, 2],
        [3],
      ]);
    });
  });

  test('AiService.splitTranscribedPages teilt an den Seitenmarkern', () {
    final pages = AiService.splitTranscribedPages(
      'Vorwort\n<<<SEITE 1>>>\nErste Seite\n<<< seite 2 >>>\nZweite Seite',
      pageCount: 3,
    );
    expect(pages, ['Erste Seite', 'Zweite Seite', '']);
    expect(AiService.splitTranscribedPages('ohne Marker', pageCount: 2), ['ohne Marker', '']);
  });

  test('PdfService: Text je Seite und Seiten-Auszug', () {
    final bytes = _pdf(['Erste Seite mit ausreichend viel Text darauf.', null, 'Dritte Seite mit ebenfalls genug Text.']);
    final texts = PdfService().extractPageTexts(bytes);
    expect(texts, hasLength(3));
    expect(texts[0], contains('Erste Seite'));
    expect(texts[1], isEmpty);
    final sub = PdfService().extractPages(bytes, [1, 2]);
    final subTexts = PdfService().extractPageTexts(sub);
    expect(subTexts, hasLength(2));
    expect(subTexts[1], contains('Dritte Seite'));
  });

  test('recognize: nur leere Seiten gehen an die KI, Ergebnis wird eingefügt', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '<<<SEITE 1>>>\nErkannter Text der Scan-Seite'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final ocr = PdfOcrService(visionAi: AiService(apiKey: 'k', model: 'vision', client: client));
    final bytes = _pdf(['Erste Seite mit ausreichend viel Text darauf.', null]);
    final pages = PdfService().extractPageTexts(bytes);

    final text = await ocr.recognize(bytes, pages);

    expect(requests, hasLength(1));
    final parts = (requests.single['messages'] as List).last['content'] as List;
    expect(parts.any((p) => (p as Map)['type'] == 'file'), isTrue);
    expect(text, contains('Erste Seite'));
    expect(text, contains('Erkannter Text der Scan-Seite'));
  });
}
