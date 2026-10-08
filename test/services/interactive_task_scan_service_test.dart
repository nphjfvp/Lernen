import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/interactive_task.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/interactive_task_scan_service.dart';
import 'package:lernen/services/pdf_page_renderer.dart';
import 'package:lernen/services/pdf_question_import_service.dart';

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

/// Der Nutzer-Text einer Anfrage (ohne Bilder).
String _userText(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final content = (body['messages'] as List)[1]['content'];
  if (content is String) return content;
  return [
    for (final part in content as List)
      if (part is Map && part['type'] == 'text') part['text'] as String,
  ].join('\n');
}

/// Zählt die gerenderten Seiten und ob der Renderer geschlossen wurde.
class _FakeRenderer implements PageImageRenderer {
  final rendered = <int>[];
  bool closed = false;

  @override
  Future<Uint8List?> renderPng(int page) async {
    rendered.add(page);
    return Uint8List.fromList([page]);
  }

  @override
  Future<void> close() async => closed = true;
}

Map<String, dynamic> _steps(String front, {Object? page}) => {
      'kind': 'steps',
      'front': front,
      'page': ?page,
      'taskData': {
        'steps': [
          {
            'title': 'Ergebnis',
            'prompt': 'Rechne aus.',
            'fields': [
              {'label': 'x =', 'answer': '2'},
            ],
          },
        ],
      },
    };

void main() {
  test('Abschnitte: je zwei neue Seiten, ab dem zweiten mit der Seite davor als Kontext', () {
    List<(List<int>, int?)> plain(List<({List<int> pages, int? context})> w) => [for (final x in w) (x.pages, x.context)];
    final windows = plain(InteractiveTaskScanService.windowsFor(1, 5, 2));
    expect(windows.map((w) => w.$1), [
      [1, 2],
      [3, 4],
      [5],
    ]);
    expect(windows.map((w) => w.$2), [null, 2, 4]);
    final single = InteractiveTaskScanService.windowsFor(3, 3, 2).single;
    expect(single.pages, [3]);
    expect(single.context, isNull);
  });

  test('KI-Antwort: Seite wird gelesen, withPage behält alles andere', () {
    final d = AiService.parseInteractiveTask(_steps('Aufgabe 1', page: 3));
    expect(d.page, 3);
    expect(d.kind, InteractiveKind.steps);
    expect(AiService.parseInteractiveTask({..._steps('A'), 'seite': '4'}).page, 4);
    expect(AiService.parseInteractiveTask({..._steps('A'), 'page': 0}).page, isNull);
    final moved = d.withPage(5);
    expect(moved.page, 5);
    expect(moved.front, 'Aufgabe 1');
    expect(moved.steps!.steps, hasLength(1));
  });

  test('Wunsch und Seiten landen im Prompt; leere Antwort ist bei allowEmpty kein Fehler', () async {
    final texts = <String>[];
    final ai = AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((r) async {
        texts.add(_userText(r));
        return _chat({'tasks': []});
      }),
    );
    final drafts = await ai.buildInteractiveTasks(
      text: '--- Seite 3 ---\nAufgabe',
      instruction: 'alle Mathe-Aufgaben als Rechenweg',
      pages: [3, 4],
      contextPage: 2,
      allowEmpty: true,
    );
    expect(drafts, isEmpty);
    expect(texts.single, contains('Wunsch des Nutzers, welche Aufgaben und wie: alle Mathe-Aufgaben als Rechenweg'));
    expect(texts.single, contains('Seite 2 (nur Kontext), Seite 3, Seite 4'));
    expect(texts.single, contains('auf den Seiten 3–4 beginnt'));
    // Ohne allowEmpty bleibt es ein Fehler.
    await expectLater(ai.buildInteractiveTasks(text: 'Aufgabe'), throwsA(isA<AiServiceException>()));
  });

  test('Dokument lesen: Seiten zuordnen, leere Einträge weglassen, Fehler je Abschnitt', () async {
    final texts = <String>[];
    final client = MockClient((r) async {
      final text = _userText(r);
      texts.add(text);
      if (text.contains('--- Seite 1 ---')) {
        return _chat({
          'tasks': [
            _steps('1b) Berechne x.', page: 2),
            // Seite außerhalb des Abschnitts → erste neue Seite.
            {'kind': 'none', 'front': '1c) Skizziere.', 'reason': 'Zeichnen', 'page': 9},
            // Leerer Eintrag ohne Aufgabe und Begründung.
            {'kind': 'none'},
          ],
        });
      }
      if (text.contains('--- Seite 3 ---')) return http.Response('boom', 500);
      return _chat({'tasks': []});
    });
    final renderer = _FakeRenderer();
    final service = InteractiveTaskScanService(
      ai: AiService(apiKey: 'k', model: 'vision', client: client),
      renderer: (_) async => renderer,
    );
    final progress = <(int, int)>[];
    final scan = await service.scan(
      ImportSource(name: 'Blatt.pdf', bytes: Uint8List(0), pageTexts: const ['A', 'B', 'C', 'D', 'E']),
      instruction: 'alle Mathe-Aufgaben',
      kind: InteractiveKind.steps,
      materialId: 'mat1',
      onProgress: (done, total) => progress.add((done, total)),
    );

    expect(scan.windows, 3);
    expect(scan.drafts.map((d) => (d.page, d.draft.front)), [(2, '1b) Berechne x.'), (1, '1c) Skizziere.')]);
    expect(scan.drafts.every((d) => d.materialId == 'mat1' && d.sourceName == 'Blatt.pdf'), isTrue);
    expect(scan.drafts.first.pageImage, [2]);
    expect(scan.drafts.first.draft.page, 2);
    expect(scan.errors.single, startsWith('Seiten 3–4: '));
    expect(progress.last, (3, 3));
    // Die Seite davor geht als Kontext mit; jede Seite wird nur einmal gerendert.
    expect(texts[1], contains('--- Seite 2 (nur Kontext) ---\nB'));
    expect(texts[1], contains('Wunsch des Nutzers'));
    expect(texts[1], contains('Gewünscht: "kind": "steps"'));
    expect(renderer.rendered, [1, 2, 3, 4, 5]);
    expect(renderer.closed, isTrue);
  });

  test('Abbrechen: keine weiteren Abschnitte; ohne Render-Engine nur Text', () async {
    var calls = 0;
    final service = InteractiveTaskScanService(
      ai: AiService(
        apiKey: 'k',
        model: 'vision',
        client: MockClient((r) async {
          calls++;
          return _chat({
            'tasks': [_steps('Aufgabe')],
          });
        }),
      ),
      renderer: (_) async => null,
    );
    final scan = await service.scan(
      ImportSource(name: 'Blatt.pdf', bytes: Uint8List(0), pageTexts: const ['A', 'B', 'C', 'D']),
      isCancelled: () => calls >= 1,
    );
    expect(calls, 1);
    expect(scan.drafts.single.pageImage, isNull);
    expect(scan.drafts.single.page, 1);
  });

  test('Dokument ohne Seiten: verständlicher Hinweis statt Absturz', () async {
    final service = InteractiveTaskScanService(
      ai: AiService(apiKey: 'k', model: 'm', client: MockClient((r) async => _chat({}))),
      renderer: (_) async => null,
    );
    final scan = await service.scan(ImportSource(name: 'Leer.pdf', bytes: Uint8List(0), pageTexts: const []));
    expect(scan.drafts, isEmpty);
    expect(scan.errors.single, contains('keine lesbaren Seiten'));
  });
}
