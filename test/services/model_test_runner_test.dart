import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/ai_model_info.dart';
import 'package:lernen/models/ai_usage.dart';
import 'package:lernen/models/model_test_result.dart';
import 'package:lernen/repositories/model_test_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/model_test_runner.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

http.Response _chat(Object json, {Map<String, dynamic>? usage}) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': json is String ? json : jsonEncode(json)},
      },
    ],
    'usage': ?usage,
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _priced = AiModelInfo(
  id: 'm',
  name: 'Modell M',
  contextLength: 200000,
  promptPricePerMillion: 2,
  completionPricePerMillion: 10,
  supportsVision: true,
  isFree: false,
);

void main() {
  late List<({String system, String user})> requests;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_model_test_runner_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  setUp(() => requests = []);
  tearDown(() => AiService.onUsage = null);

  AiService ai(http.Response Function(String system, String user) answer) => AiService(
    apiKey: 'sk-test',
    model: 'm',
    client: MockClient((r) async {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final system = (body['messages'] as List)[0]['content'] as String;
      final content = (body['messages'] as List)[1]['content'];
      final user = content is String ? content : jsonEncode(content);
      requests.add((system: system, user: user));
      return answer(system, user);
    }),
  );

  test('Rollen und Tests: jede Modell-Rolle hat ihre Tests', () {
    expect(ModelTestKind.forRole('question'), [ModelTestKind.questions, ModelTestKind.lesson]);
    expect(ModelTestKind.forRole('help'), [ModelTestKind.explain]);
    expect(ModelTestKind.forRole('vision'), [ModelTestKind.vision]);
    expect(ModelTestKind.forRole('crosscheck'), [ModelTestKind.crosscheck]);
    expect(ModelTestKind.forRole('scene3d'), [ModelTestKind.scene3d]);
    expect(ModelTestKind.scene3d.needsDocument, isFalse);
    expect(ModelTestKind.vision.needsDocument, isTrue);
  });

  test('Fragen erstellen: Ergebnis mit Dauer, Tokens und gemeldeten Kosten; zählt auch in die KI-Kosten', () async {
    final global = <AiUsage>[];
    AiService.onUsage = global.add;
    final service = ai(
      (_, _) => _chat(
        {
          'concepts': [
            {'title': 'Hebelgesetz', 'explanation': 'Kraft mal Kraftarm.'},
          ],
          'flashcards': [
            {'type': 'flashcard', 'front': 'Was besagt das Hebelgesetz?', 'back': 'F1·a1 = F2·a2'},
            {'type': 'flashcard', 'front': 'Einheit des Drehmoments?', 'back': 'Nm'},
          ],
        },
        usage: {'prompt_tokens': 900, 'completion_tokens': 300, 'cost': 0.0021},
      ),
    );
    final result = await ModelTestRunner.run(
      id: 'r1',
      kind: ModelTestKind.questions,
      ai: service,
      input: const ModelTestInput(label: 'Seite 2 von hebel.pdf', text: 'Der Hebel: Kraft mal Kraftarm.'),
    );
    expect(result.failed, isFalse);
    expect((result.modelId, result.calls, result.promptTokens, result.completionTokens), ('m', 1, 900, 300));
    expect(result.cost, closeTo(0.0021, 1e-9));
    expect(result.costEstimated, isFalse);
    expect(result.inputLabel, 'Seite 2 von hebel.pdf');
    expect(ModelTestRunner.flashcardsOf(result.output), hasLength(2));
    expect(ModelTestRunner.conceptsOf(result.output).single['title'], 'Hebelgesetz');
    expect(requests.single.user, contains('Der Hebel: Kraft mal Kraftarm.'));
    // Der Test kostet echtes Geld – er steht auch in der Kostenanzeige.
    expect(global, hasLength(1));
    expect(service.usageListener, isNull, reason: 'der Lauscher hängt nur während des Tests');
  });

  test('Ohne gemeldete Kosten: aus dem Listenpreis geschätzt', () async {
    final result = await ModelTestRunner.run(
      id: 'r2',
      kind: ModelTestKind.explain,
      ai: ai(
        (_, _) => _chat('Weil die Steigung überall 2x ist.', usage: {'prompt_tokens': 1000, 'completion_tokens': 500}),
      ),
      input: const ModelTestInput(label: 'Warum 2x?', text: 'Warum ist die Ableitung von x² gleich 2x?'),
      modelInfo: (id) => id == 'm' ? _priced : null,
    );
    expect(result.output['text'], 'Weil die Steigung überall 2x ist.');
    expect(result.cost, closeTo((1000 * 2 + 500 * 10) / 1000000, 1e-12));
    expect(result.costEstimated, isTrue);
    // Ohne Lösung bekommt das Modell den Auftrag, sie selbst herzuleiten.
    expect(requests.single.user, contains('leite sie kurz her'));
  });

  test('Ein Fehler des Modells ist auch ein Ergebnis', () async {
    final result = await ModelTestRunner.run(
      id: 'r3',
      kind: ModelTestKind.questions,
      ai: ai((_, _) => http.Response('{"error":{"message":"No auth","code":401}}', 401)),
      input: const ModelTestInput(label: 'Text', text: 'Irgendein Text.'),
    );
    expect(result.failed, isTrue);
    expect(result.error, isNotEmpty);
    expect(result.output, isEmpty);
  });

  test('3D-Modell aus einer Beschreibung; eine flache Zeichnung gilt als Fehler', () async {
    final good = await ModelTestRunner.run(
      id: 'r4',
      kind: ModelTestKind.scene3d,
      ai: ai(
        (_, _) => _chat({
          'show': {
            'scene3d': {
              'box': [2, 1, 1],
              'objects': [
                {
                  'type': 'box',
                  'at': [0, 0, 0],
                  'dims': [1, 1, 1],
                },
              ],
            },
          },
        }),
      ),
      input: const ModelTestInput(label: 'Welle', text: 'Welle mit zwei Lagern'),
    );
    expect(good.failed, isFalse);
    expect((good.output['scene3d'] as Map)['objects'], hasLength(1));
    expect(requests.single.user, contains('Bauplan: Welle mit zwei Lagern'));
    expect(requests.single.user, contains('Art: räumlich'));

    final flat = await ModelTestRunner.run(
      id: 'r5',
      kind: ModelTestKind.scene3d,
      ai: ai(
        (_, _) => _chat({
          'show': {
            'scene': {
              'elements': [
                {'type': 'circle', 'x': 1, 'y': 1, 'r': 1},
              ],
            },
          },
        }),
      ),
      input: const ModelTestInput(label: 'Welle', text: 'Welle mit zwei Lagern'),
    );
    expect(flat.error, contains('flache Zeichnung'));
  });

  test('Seite abschreiben schickt die PDF; Gegenprüfen schickt die erstellten Fragen', () async {
    final vision = await ModelTestRunner.run(
      id: 'r6',
      kind: ModelTestKind.vision,
      ai: ai((_, _) => _chat('<<<SEITE 1>>>\nErkannter Text')),
      input: ModelTestInput(label: 'Seite 1 von scan.pdf', pdfBytes: Uint8List.fromList([1, 2, 3])),
    );
    expect(vision.output['pages'], ['Erkannter Text']);
    expect(requests.single.user, contains('application/pdf'));

    requests.clear();
    final generated = {
      'concepts': <Object>[],
      'flashcards': [
        {'type': 'flashcard', 'front': 'Einheit der Kraft?', 'back': 'Joule'},
      ],
    };
    final check = await ModelTestRunner.run(
      id: 'r7',
      kind: ModelTestKind.crosscheck,
      ai: ai(
        (_, _) => _chat({
          'ok': false,
          'issues': [
            {
              'targetType': 'flashcard',
              'targetIndex': 0,
              'problem': 'Die Einheit der Kraft ist Newton.',
              'fix': {'type': 'flashcard', 'front': 'Einheit der Kraft?', 'back': 'Newton'},
            },
          ],
        }),
      ),
      input: const ModelTestInput(label: 'Text', text: 'Kraft wird in Newton gemessen.'),
      generated: generated,
    );
    expect(ModelTestRunner.issuesOf(check.output).single['problem'], contains('Newton'));
    expect(check.output['generated'], generated);
    expect(requests.single.user, contains('Joule'));

    final none = await ModelTestRunner.run(
      id: 'r8',
      kind: ModelTestKind.crosscheck,
      ai: ai((_, _) => _chat({'ok': true, 'issues': <Object>[]})),
      input: const ModelTestInput(label: 'Text', text: 'x'),
    );
    expect(none.error, contains('keine Fragen'));
  });

  test('Gleiche Eingabe, gleicher Schlüssel', () {
    const a = ModelTestInput(label: 'Seite 1 von a.pdf', text: 'abc');
    const b = ModelTestInput(label: 'Seite 1 von a.pdf', text: 'abc');
    const c = ModelTestInput(label: 'Seite 2 von a.pdf', text: 'abd');
    expect(a.key, b.key);
    expect(a.key, isNot(c.key));
  });

  test('Ergebnis: 30 Minuten oder behalten; übersteht Speichern und Lesen', () {
    final at = DateTime(2026, 11, 12, 10);
    final result = ModelTestResult(
      id: 'x',
      kind: ModelTestKind.lesson,
      modelId: 'm',
      createdAt: at,
      inputLabel: 'Seite 1',
      inputKey: 'k',
      duration: const Duration(milliseconds: 4200),
      cost: 0.01,
      costEstimated: true,
      promptTokens: 10,
      completionTokens: 20,
      calls: 3,
      output: const {
        'lesson': {'title': 'T'},
      },
    );
    expect(result.isExpired(at.add(const Duration(minutes: 29))), isFalse);
    expect(result.isExpired(at.add(const Duration(minutes: 30))), isTrue);
    expect(result.remaining(at.add(const Duration(minutes: 10))), const Duration(minutes: 20));
    final pinned = result.copyWith(pinned: true);
    expect(pinned.isExpired(at.add(const Duration(days: 400))), isFalse);
    expect(pinned.remaining(at), isNull);

    final again = ModelTestResult.fromMap(jsonDecode(jsonEncode(pinned.toMap())) as Map<String, dynamic>)!;
    expect((again.id, again.kind, again.modelId, again.pinned, again.calls), ('x', ModelTestKind.lesson, 'm', true, 3));
    expect((again.duration.inMilliseconds, again.cost, again.costEstimated, again.inputKey), (4200, 0.01, true, 'k'));
    expect((again.output['lesson'] as Map)['title'], 'T');
    expect(ModelTestResult.fromMap(const {'id': 'y', 'kind': 'gibtsnicht', 'at': 1}), isNull);
  });

  test('Ablage: Abgelaufenes verschwindet, Behaltenes bleibt, je Test getrennt', () async {
    var now = DateTime(2026, 11, 12, 10);
    final repo = ModelTestRepository(clock: () => now);
    ModelTestResult make(String id, ModelTestKind kind, {int minutesAgo = 0}) => ModelTestResult(
      id: id,
      kind: kind,
      modelId: 'm-$id',
      createdAt: now.subtract(Duration(minutes: minutesAgo)),
      inputLabel: 'Eingabe',
    );
    await repo.clear(ModelTestKind.questions);
    await repo.clear(ModelTestKind.scene3d);
    await repo.save(make('alt', ModelTestKind.questions, minutesAgo: 20));
    await repo.save(make('neu', ModelTestKind.questions));
    await repo.save(make('drei-d', ModelTestKind.scene3d));
    expect((await repo.all(kind: ModelTestKind.questions)).map((r) => r.id), ['neu', 'alt'], reason: 'jüngste zuerst');
    expect((await repo.all(kind: ModelTestKind.scene3d)).single.id, 'drei-d');

    await repo.setPinned('alt', true);
    now = now.add(const Duration(minutes: 31));
    final later = await repo.all();
    expect(later.map((r) => r.id), ['alt'], reason: 'nur das Behaltene überlebt 30 Minuten');
    expect(later.single.pinned, isTrue);

    await repo.setPinned('alt', false);
    expect(await repo.all(), isEmpty, reason: 'ohne Behalten gilt wieder die Frist');

    await repo.save(make('weg', ModelTestKind.questions));
    await repo.delete('weg');
    expect(await repo.all(), isEmpty);
  });
}
