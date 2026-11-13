import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/ai_model_info.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/visual_scene3d.dart';
import 'package:lernen/models/visual_scene3d_blocks.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/scene3d_check.dart';
import 'package:lernen/services/scene3d_model.dart';
import 'package:lernen/services/sync_service.dart';

http.Response _chat(Object json) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': json is String ? json : jsonEncode(json)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

AiModelInfo _model(String id, {double? out, bool free = false}) => AiModelInfo(
  id: id,
  name: id,
  contextLength: 100000,
  promptPricePerMillion: out == null ? null : out / 5,
  completionPricePerMillion: out,
  supportsVision: false,
  isFree: free,
);

/// Auto aus Quader und vier Rädern; [gap] rückt ein Rad vom Wagen weg.
Map<String, dynamic> carScene({double gap = 0}) => {
  'box': [5, 2, 2],
  'objects': [
    {
      'type': 'box',
      'at': [0.5, 0.2, 0.4],
      'dims': [4, 1.6, 1],
      'text': 'Karosserie',
    },
    for (final x in [1.2, 3.8])
      for (final y in [0.0, 1.8])
        {
          'type': 'cylinder',
          'from': [x, y, 0.4 - (x == 3.8 && y == 1.8 ? gap : 0)],
          'to': [x, y + 0.2, 0.4 - (x == 3.8 && y == 1.8 ? gap : 0)],
          'r': 0.4,
          'text': x == 3.8 && y == 1.8 ? 'Rad vorn rechts' : '',
        },
    {
      'type': 'arrow',
      'from': [2.5, 1, 0.9],
      'to': [2.5, 1, -0.3],
      'text': 'F_G',
    },
  ],
};

void main() {
  tearDown(() => AiService.mechBlocksFor = null);

  group('Baustein „body“: Körper mit Kräften', () {
    test('Auto freigeschnitten: Karosserie, vier Räder, Kräfte an Schwerpunkt und Achsen', () {
      final scene = VisualScene3D.fromMap({
        'objects': [
          {
            'type': 'body',
            'body': 'car',
            'size': [4, 1.8, 1.4],
            'cut': true,
            'forces': [
              {'at': 'cg', 'dir': 'down', 'text': 'F_G'},
              {'at': 'front', 'dir': 'normal', 'text': 'F_N,v'},
              {'at': 'rear', 'dir': 'normal', 'text': 'F_N,h'},
            ],
            'measures': [
              {'from': 'rear', 'to': 'front', 'text': 'l = 2,4 m'},
            ],
          },
        ],
      })!;
      expect(scene.blocks, hasLength(1));
      expect(scene.objects.every((o) => o.fromBlock), isTrue);
      // Ohne "box": Der Raum richtet sich nach dem Körper, ohne Rahmen und Achsen.
      expect((scene.frame, scene.axes), (false, false));
      expect(scene.box[0], greaterThan(4));

      final wheels = scene.objects.where((o) => o.shape == Scene3DShape.cylinder).toList();
      expect(wheels, hasLength(4));
      final arrows = {for (final o in scene.objects.where((o) => o.shape == Scene3DShape.arrow)) o.text: o};
      expect(arrows.keys, containsAll(['F_G', 'F_N,v', 'F_N,h']));
      // Gewicht: beginnt im Schwerpunkt und zeigt nach unten.
      final weight = arrows['F_G']!;
      expect(weight.vectors['to']![2], lessThan(weight.vectors['from']![2]));
      expect(weight.vectors['to']![0], closeTo(weight.vectors['from']![0], 1e-9));
      // Normalkraft: kommt von unten und ENDET am Radaufstandspunkt (auf Höhe der Radunterkante).
      final normal = arrows['F_N,v']!;
      final ground = wheels.map((w) => w.vectors['from']![2] - w.numbers['r']!).reduce((a, b) => a < b ? a : b);
      expect(normal.vectors['to']![2], closeTo(ground, 1e-6));
      expect(normal.vectors['from']![2], lessThan(ground));
      // Vorn (+x) liegt die vordere Normalkraft, hinten die hintere – im Radstand-Abstand (0,6 · 4).
      expect(normal.vectors['to']![0] - arrows['F_N,h']!.vectors['to']![0], closeTo(2.4, 1e-6));
      // Schwerpunkt-Marke, Maßlinie und nichts im negativen Raum.
      expect(scene.objects.any((o) => o.shape == Scene3DShape.text && o.text == 'S'), isTrue);
      expect(scene.objects.any((o) => o.text == 'l = 2,4 m'), isTrue);
      for (final o in scene.objects) {
        for (final v in [o.vectors['at'], o.vectors['from'], o.vectors['to'], ...o.points]) {
          if (v != null) expect(v.every((c) => c >= -1e-9), isTrue, reason: '${o.shape} $v');
        }
      }
      // Gespeichert wird nur der Baustein – und er lässt sich wieder lesen.
      final saved = scene.toMap();
      expect((saved['objects'] as List).single['body'], 'car');
      expect(VisualScene3D.fromMap(saved)!.objects.length, scene.objects.length);
    });

    test('Klotz auf schiefer Ebene: Neigung dreht Körper und Kräfte, Winkel wird beschriftet', () {
      List<Scene3DObject> parts(double slope) => VisualScene3D.fromMap({
        'objects': [
          {
            'type': 'body',
            'body': 'block',
            'size': [1, 1, 1],
            'slope': slope,
            'forces': [
              {'at': 'cg', 'dir': 'down', 'text': 'G'},
              {'at': 'bottom', 'dir': 'normal', 'text': 'N'},
              {'at': 'bottom', 'dir': 'uphill', 'text': 'R'},
            ],
          },
        ],
      })!.objects;
      List<double> dir(Scene3DObject o) => [for (var q = 0; q < 3; q++) o.vectors['to']![q] - o.vectors['from']![q]];
      Scene3DObject arrow(List<Scene3DObject> all, String text) => all.firstWhere((o) => o.text == text);

      final flat = parts(0), tilted = parts(30);
      // Eben: Normalkraft senkrecht nach oben, Reibung waagrecht.
      expect(dir(arrow(flat, 'N'))[0], closeTo(0, 1e-9));
      expect(dir(arrow(flat, 'R'))[2], closeTo(0, 1e-9));
      // 30°: Normalkraft kippt um 30° gegen die Senkrechte, Reibung zeigt hangaufwärts; Gewicht bleibt senkrecht.
      final n = dir(arrow(tilted, 'N'));
      expect(n[0] / n[2], closeTo(-0.5774, 1e-3));
      final r = dir(arrow(tilted, 'R'));
      expect(r[2] / r[0], closeTo(0.5774, 1e-3));
      expect(dir(arrow(tilted, 'G'))[0], closeTo(0, 1e-9));
      expect(tilted.any((o) => o.text == 'α = 30°'), isTrue);
      expect(flat.any((o) => o.text.startsWith('α')), isFalse);
    });

    test('Balken: Lager, Kraft von oben, Streckenlast, Moment', () {
      final scene = VisualScene3D.fromMap({
        'objects': [
          {
            'type': 'body',
            'body': 'beam',
            'size': [6, 0.3, 0.4],
            'supports': [
              {'at': 0, 'kind': 'fixed', 'text': 'A'},
              {'at': 6, 'kind': 'roller', 'text': 'B'},
            ],
            'forces': [
              {'at': 2, 'text': 'F'},
            ],
            'loads': [
              {'from': 3, 'to': 6, 'text': 'q'},
            ],
            'moments': [
              {'at': 4.5, 'text': 'M', 'dir': 'cw'},
            ],
          },
        ],
      })!;
      final cones = scene.objects.where((o) => o.shape == Scene3DShape.cylinder && o.numbers['r2'] == 0).toList();
      expect(cones, hasLength(2), reason: 'je Lager ein Keil');
      // Loslager rollt auf zwei Walzen.
      expect(scene.objects.where((o) => o.shape == Scene3DShape.cylinder && o.numbers['r2'] == null), hasLength(2));
      final force = scene.objects.firstWhere((o) => o.text == 'F');
      // Zwei Meter vom linken Lager, von oben auf den Balken.
      expect(force.vectors['to']![0] - cones.first.vectors['from']![0], closeTo(2, 1e-6));
      expect(force.vectors['from']![2], greaterThan(force.vectors['to']![2]));
      // Streckenlast: Pfeilreihe (3 m von 6 m → 5 Felder, 6 Pfeile) + Kraft + Pfeilspitze des Moments.
      expect(scene.objects.where((o) => o.shape == Scene3DShape.arrow), hasLength(8));
      expect(scene.objects.any((o) => o.text == 'q'), isTrue);
      expect(scene.objects.any((o) => o.text == 'M'), isTrue);
      expect(scene.objects.any((o) => o.text == 'A') && scene.objects.any((o) => o.text == 'B'), isTrue);
    });

    test('unbekannte Körper sind kein Baustein; ein angegebener Raum wächst mit', () {
      expect(Scene3DBlocks.isBlock({'type': 'body', 'body': 'raumschiff'}), isFalse);
      expect(
        Scene3DBlocks.isBlock({
          'type': 'box',
          'at': [0, 0, 0],
        }),
        isFalse,
      );
      expect(Scene3DBlocks.sizesItself({'type': 'freischnitt', 'body': 'Klotz'}), isTrue);
      final scene = VisualScene3D.fromMap({
        'box': [1, 1, 1],
        'objects': [
          {
            'type': 'body',
            'body': 'ball',
            'd': 3,
            'forces': [
              {'at': 'cg', 'dir': 'down'},
            ],
          },
        ],
      })!;
      expect(scene.box.every((v) => v >= 3), isTrue);
    });
  });

  group('Prüfung der Szene', () {
    test('ein sauberes Auto hat keine Auffälligkeit; ein abgerücktes Rad wird gefunden', () {
      expect(Scene3DCheck.issues(VisualScene3D.fromMap(carScene())!), isEmpty);
      final issues = Scene3DCheck.issues(VisualScene3D.fromMap(carScene(gap: 0.9))!);
      expect(issues, hasLength(1));
      expect(
        issues.single,
        allOf(contains('Objekt 4'), contains('Rad vorn rechts'), contains('berührt kein anderes Teil')),
      );
    });

    test('Kristallgitter (Kugeln, Raster) und bewegte Teile gelten nie als schwebend', () {
      final lattice = VisualScene3D.fromMap({
        'box': [1, 1, 1],
        'objects': [
          {
            'type': 'sphere',
            'at': [0, 0, 0],
            'r': 0.08,
            'repeat': {
              'n': [2, 2, 2],
              'd': [1, 1, 1],
            },
          },
          {
            'type': 'sphere',
            'at': [0.5, 0.5, 0.5],
            'r': 0.08,
          },
          {
            'type': 'arrow',
            'from': [0, 0, 0],
            'to': [1, 1, 1],
            'text': '[111]',
          },
        ],
      })!;
      expect(Scene3DCheck.issues(lattice), isEmpty);
      final moving = VisualScene3D.fromMap({
        'box': [10, 2, 2],
        'objects': [
          {
            'type': 'box',
            'at': [0, 0, 0],
            'dims': [1, 1, 1],
            'keys': [
              {
                't': 1,
                'at': [8, 0, 0],
              },
            ],
          },
          {
            'type': 'box',
            'at': [9, 0, 0],
            'dims': [1, 1, 1],
          },
        ],
      })!;
      expect(Scene3DCheck.issues(moving).where((i) => i.contains('Objekt 0')), isEmpty);
    });

    test('Pfeil in der Luft, deckungsgleiche Teile, Teil außerhalb, Beschriftungen aufeinander', () {
      final scene = VisualScene3D.fromMap({
        'box': [4, 4, 4],
        'objects': [
          {
            'type': 'box',
            'at': [0, 0, 0],
            'dims': [1, 1, 1],
            'text': 'Klotz',
          },
          {
            'type': 'box',
            'at': [0, 0, 0],
            'dims': [1, 1, 1],
          },
          {
            'type': 'arrow',
            'from': [3, 3, 3],
            'to': [3, 3, 3.8],
            'text': 'F',
          },
          {
            'type': 'text',
            'at': [2, 2, 2],
            'text': 'a',
          },
          {
            'type': 'text',
            'at': [2, 2, 2],
            'text': 'b',
          },
        ],
      })!;
      final issues = Scene3DCheck.issues(scene, max: 20).join('\n');
      expect(issues, contains('liegen deckungsgleich aufeinander'));
      expect(issues, contains('hängt frei im Raum'));
      expect(issues, contains('Beschriftungen liegen aufeinander'));
      expect(Scene3DCheck.issues(scene, max: 2), hasLength(2));

      final far = VisualScene3D.fromMap({
        'box': [4, 4, 4],
        'objects': [
          {
            'type': 'box',
            'at': [0, 0, 0],
            'dims': [1, 1, 1],
          },
          {
            'type': 'sphere',
            'at': [30, 0, 0],
            'r': 0.3,
          },
        ],
      })!;
      expect(Scene3DCheck.issues(far).single, allOf(contains('Objekt 1'), contains('außerhalb des Raums')));
    });

    test('Formen aus Bausteinen werden nicht beanstandet', () {
      final scene = VisualScene3D.fromMap({
        'objects': [
          {
            'type': 'body',
            'body': 'car',
            'forces': [
              {'at': 'cg', 'dir': 'down', 'text': 'F_G'},
              {'at': 'front', 'dir': 'normal'},
            ],
          },
        ],
      })!;
      expect(Scene3DCheck.issues(scene), isEmpty);
    });
  });

  group('Nachbessern', () {
    AiService ai(List<Object> answers, List<String> seen) {
      var i = 0;
      return AiService(
        apiKey: 'sk-test',
        model: 'm',
        client: MockClient((r) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          seen.add((body['messages'] as List)[1]['content'] as String);
          final answer = answers[i < answers.length ? i : answers.length - 1];
          i++;
          return answer is http.Response ? answer : _chat(answer);
        }),
      );
    }

    test('bessere Fassung wird übernommen – mit den Auffälligkeiten im Auftrag', () async {
      final seen = <String>[];
      final result = await Scene3DRepair.run(
        ai: ai([
          {'scene3d': carScene()},
        ], seen),
        scene: carScene(gap: 0.9),
        wish: 'Auto mit vier Rädern',
      );
      expect((result.before.length, result.after.length, result.rounds, result.improved), (1, 0, 1, true));
      expect(Scene3DCheck.issues(VisualScene3D.fromMap(result.scene)!), isEmpty);
      expect(
        seen.single,
        allOf(contains('Rad vorn rechts'), contains('berührt kein anderes Teil'), contains('Auto mit vier Rädern')),
      );
    });

    test('schlechtere oder unlesbare Antwort: das Original bleibt', () async {
      final seen = <String>[];
      final original = carScene(gap: 0.9);
      final worse = await Scene3DRepair.run(
        ai: ai([
          {
            'scene3d': {
              'box': [5, 2, 2],
              'objects': [
                {
                  'type': 'box',
                  'at': [0, 0, 0],
                  'dims': [1, 1, 1],
                },
                {
                  'type': 'box',
                  'at': [0, 0, 0],
                  'dims': [1, 1, 1],
                },
                {
                  'type': 'cylinder',
                  'from': [4, 0, 0],
                  'to': [4, 0.2, 0],
                  'r': 0.1,
                },
              ],
            },
          },
          http.Response('{"error":{"message":"x","code":401}}', 401),
        ], seen),
        scene: original,
      );
      expect(worse.improved, isFalse);
      expect(worse.rounds, 2, reason: 'zwei Versuche, keiner besser');
      expect(identical(worse.scene, original), isTrue);
      expect(worse.after, worse.before);
    });

    test('ohne Auffälligkeit keine Anfrage', () async {
      final seen = <String>[];
      final result = await Scene3DRepair.run(ai: ai([{}], seen), scene: carScene());
      expect((result.rounds, result.improved, seen.length), (0, false, 0));
    });
  });

  group('Mechanik-Bausteine im Prompt', () {
    Future<String> systemOf(AiService Function(http.Client client) make) async {
      late String system;
      final ai = make(
        MockClient((r) async {
          system = ((jsonDecode(r.body) as Map)['messages'] as List)[0]['content'] as String;
          return _chat({
            'show': {
              'scene3d': {
                'objects': [
                  {
                    'type': 'box',
                    'at': [0, 0, 0],
                    'dims': [1, 1, 1],
                  },
                ],
              },
            },
          });
        }),
      );
      await ai.drawVisualScene(
        lesson: {
          'title': 'T',
          'steps': [
            {
              'title': 'S',
              'show': {'idea': 'Auto', 'kind': '3d'},
            },
          ],
        },
        stepIndex: 0,
      );
      return system;
    }

    test('ohne Hook wie bisher; mit Hook nur für die Modelle, für die er gilt; je Instanz erzwingbar', () async {
      expect(
        await systemOf((c) => AiService(apiKey: 'k', model: 'teuer', client: c)),
        isNot(contains('"type": "body"')),
      );

      AiService.mechBlocksFor = (model) => model == 'billig';
      final cheap = await systemOf((c) => AiService(apiKey: 'k', model: 'billig', client: c));
      expect(cheap, contains('"type": "body"'));
      expect(cheap, contains('"type": "shaft"'), reason: 'der Zusatz ergänzt, ersetzt nichts');
      expect(
        await systemOf((c) => AiService(apiKey: 'k', model: 'teuer', client: c)),
        isNot(contains('"type": "body"')),
      );

      expect(
        await systemOf((c) => AiService(apiKey: 'k', model: 'teuer', client: c)..mechBlocks = true),
        contains('"type": "body"'),
      );
      expect(
        await systemOf((c) => AiService(apiKey: 'k', model: 'billig', client: c)..mechBlocks = false),
        isNot(contains('"type": "body"')),
      );
    });

    test('Prompts ohne Werkzeugbeschreibung bleiben unberührt', () async {
      AiService.mechBlocksFor = (_) => true;
      late String system;
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          system = ((jsonDecode(r.body) as Map)['messages'] as List)[0]['content'] as String;
          return _chat('Erklärung');
        }),
      );
      await ai.explainAnswer(question: 'q', correctAnswer: 'a');
      expect(system, isNot(contains('"type": "body"')));
    });
  });

  test('günstig oder nicht: Preisgrenze, kostenlos, unbekannt; Einstellung auto/on/off', () {
    expect(Scene3dModel.isBudget(_model('flash', out: 2.5)), isTrue);
    expect(Scene3dModel.isBudget(_model('grenze', out: Scene3dModel.budgetOutputPrice)), isTrue);
    expect(Scene3dModel.isBudget(_model('stark', out: 25)), isFalse);
    expect(Scene3dModel.isBudget(_model('gratis', free: true)), isTrue);
    expect(Scene3dModel.isBudget(null), isFalse, reason: 'unbekannt: alles bleibt wie bisher');

    expect(Scene3dModel.helps('auto', _model('stark', out: 25)), isFalse);
    expect(Scene3dModel.helps('auto', _model('flash', out: 2.5)), isTrue);
    expect(Scene3dModel.helps('on', _model('stark', out: 25)), isTrue);
    expect(Scene3dModel.helps('off', _model('flash', out: 2.5)), isFalse);
    expect(Scene3dModel.helps('quatsch', null), isFalse);
  });

  test('Vorab-Klärung: Bauplan, Stichpunkte, Rückfrage, 2D nur als Vorschlag; Antwort geht mit', () async {
    final seen = <String>[];
    final ai = AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((r) async {
        final messages = (jsonDecode(r.body) as Map)['messages'] as List;
        expect(messages[0]['content'] as String, startsWith('Du bereitest in einer Lern-App'));
        seen.add(messages[1]['content'] as String);
        return _chat({
          'summary': 'Ein Auto im Stillstand, freigeschnitten.',
          'points': ['Auto von der Seite', '', 'Gewichtskraft im Schwerpunkt'],
          'plan': 'Zeichne ein Auto …',
          'question': 'Ebene Fahrbahn oder Hang?',
          'better2d': 'true',
          'reason2d': 'Alle Kräfte liegen in einer Ebene.',
        });
      }),
    );
    final first = await ai.clarifyScene3d(wish: 'auto freigeschnitten', context: 'Schritt: Kräfte am Auto');
    expect(first['summary'], 'Ein Auto im Stillstand, freigeschnitten.');
    expect(first['points'], ['Auto von der Seite', 'Gewichtskraft im Schwerpunkt']);
    expect(
      (first['plan'], first['question'], first['better2d']),
      ('Zeichne ein Auto …', 'Ebene Fahrbahn oder Hang?', true),
    );
    expect(seen.single, allOf(contains('auto freigeschnitten'), contains('Kräfte am Auto')));

    await ai.clarifyScene3d(
      wish: 'auto freigeschnitten',
      previousPlan: 'Zeichne ein Auto …',
      answer: 'am Hang, 10 Grad',
    );
    expect(seen.last, allOf(contains('Bisheriger Bauplan'), contains('am Hang, 10 Grad')));

    await expectLater(ai.clarifyScene3d(wish: ' '), throwsA(isA<AiServiceException>()));
  });

  test('Einstellungen: Vorgaben, Speichern/Lesen, Sync', () {
    const settings = AppSettings();
    expect((settings.clarifyScene3d, settings.scene3dBlocks, settings.scene3dRepair), (true, 'auto', 'auto'));
    final changed = settings.copyWith(clarifyScene3d: false, scene3dBlocks: 'on', scene3dRepair: 'off');
    final again = AppSettings.fromMap(changed.toMap());
    expect((again.clarifyScene3d, again.scene3dBlocks, again.scene3dRepair), (false, 'on', 'off'));
    // Unbekannter Wert (älterer oder kaputter Stand) → automatisch.
    expect(AppSettings.fromMap({...changed.toMap(), 'scene3dBlocks': 'x'}).scene3dBlocks, 'auto');
    expect(AppSettings.fromMap(const {}).clarifyScene3d, isTrue);

    final synced = syncedSettingsOf(changed, includeSecrets: false);
    expect((synced['clarifyScene3d'], synced['scene3dBlocks'], synced['scene3dRepair']), (false, 'on', 'off'));
    final merged = mergeAiSettings(const AppSettings(), synced);
    expect((merged.clarifyScene3d, merged.scene3dBlocks, merged.scene3dRepair), (false, 'on', 'off'));
  });
}
