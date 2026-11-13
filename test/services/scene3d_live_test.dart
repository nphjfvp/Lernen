import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_scene3d.dart';
import 'package:lernen/services/scene3d_live.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/scene3d_live_view.dart';
import 'package:lernen/ui/visual/visual_scene3d_view.dart';

VisualScene3D carScene({Object? cg, String weight = 'F_G'}) => VisualScene3D.fromMap({
  'objects': [
    {
      'type': 'body',
      'body': 'car',
      'size': [4, 2, 1.5],
      'wheelbase': 2.4,
      'cut': true,
      'cg': ?cg,
      'forces': [
        {'at': 'cg', 'dir': 'down', 'text': weight},
        {'at': 'front', 'dir': 'normal', 'text': 'F_N,v'},
        {'at': 'rear', 'dir': 'normal', 'text': 'F_N,h'},
      ],
    },
  ],
})!;

VisualScene3D blockScene() => VisualScene3D.fromMap({
  'objects': [
    {
      'type': 'body',
      'body': 'block',
      'size': [1, 1, 1],
      'slope': 20,
      'mu': 0.5,
      'forces': [
        {'at': 'cg', 'dir': 'down', 'text': 'F_G = 100 N'},
      ],
    },
  ],
})!;

VisualScene3D beamScene({List<Object>? extra}) => VisualScene3D.fromMap({
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
        {'at': 2, 'text': 'F = 12 kN'},
        ...?extra,
      ],
    },
  ],
})!;

Map<String, Scene3DObject> arrowsOf(VisualScene3D scene) => {
  for (final o in scene.objects)
    if (o.shape == Scene3DShape.arrow) o.text: o,
};

void main() {
  group('Radlasten', () {
    const wheels = {'fl': (3.2, 0.14), 'fr': (3.2, 1.86), 'rl': (0.8, 0.14), 'rr': (0.8, 1.86)};

    test('Schwerpunkt mittig: jedes Rad ein Viertel; weiter vorn: vorn mehr', () {
      final even = Scene3DLive.wheelLoads(wheels, (2.0, 1.0))!;
      for (final v in even.values) {
        expect(v, closeTo(0.25, 1e-9));
      }
      // 60 % des Radstands vor der Hinterachse → 60 % auf der Vorderachse.
      final front = Scene3DLive.wheelLoads(wheels, (0.8 + 0.6 * 2.4, 1.0))!;
      expect(front['fl']! + front['fr']!, closeTo(0.6, 1e-9));
      expect(front['fl'], closeTo(front['fr']!, 1e-9));
      expect(front.values.fold<double>(0, (s, v) => s + v), closeTo(1, 1e-9));
    });

    test('ein Rad angehoben: die Diagonale trägt, das gegenüberliegende Rad wird entlastet', () {
      final three = {...wheels}..remove('fl');
      final loads = Scene3DLive.wheelLoads(three, (2.0, 1.0))!;
      // Starrer Körper, Schwerpunkt mittig: vorn rechts und hinten links je die Hälfte.
      expect(loads['fr'], closeTo(0.5, 1e-9));
      expect(loads['rl'], closeTo(0.5, 1e-9));
      expect(loads['rr'], closeTo(0, 1e-9));
      // Momentengleichgewicht stimmt.
      var mx = 0.0, my = 0.0;
      for (final e in loads.entries) {
        mx += e.value * three[e.key]!.$1;
        my += e.value * three[e.key]!.$2;
      }
      expect(mx, closeTo(2.0, 1e-9));
      expect(my, closeTo(1.0, 1e-9));
    });

    test('kippt, wenn die Last außerhalb der Räder liegt, die aufliegen', () {
      final three = {...wheels}..remove('fl');
      // Schwerpunkt weit vorn links – dort steht kein Rad mehr.
      expect(Scene3DLive.wheelLoads(three, (3.0, 0.3)), isNull);
      // Zwei Räder: nur genau auf ihrer Linie.
      expect(Scene3DLive.wheelLoads({'rl': wheels['rl']!, 'rr': wheels['rr']!}, (2.0, 1.0)), isNull);
      final onAxle = Scene3DLive.wheelLoads({'rl': wheels['rl']!, 'rr': wheels['rr']!}, (0.8, 1.0))!;
      expect(onAxle['rl'], closeTo(0.5, 1e-9));
      expect(onAxle['rr'], closeTo(0.5, 1e-9));
      expect(Scene3DLive.wheelLoads({'rl': wheels['rl']!}, (0.8, 0.14)), isNull);
    });

    test('vier Räder, Last so weit außen, dass eines ziehen müsste: es hebt ab, drei tragen', () {
      final loads = Scene3DLive.wheelLoads(wheels, (3.1, 0.3))!;
      expect(loads['rr'], 0);
      expect(loads.values.every((v) => v >= 0), isTrue);
      expect(loads.values.fold<double>(0, (s, v) => s + v), closeTo(1, 1e-9));
    });
  });

  group('Auto ausprobieren', () {
    test('nur Körper-Bausteine, an denen die App rechnen kann', () {
      expect(Scene3DLive.blockOf(carScene()), isNotNull);
      expect(Scene3DLive.kindOf(Scene3DLive.blockOf(blockScene())!), 'block');
      expect(Scene3DLive.kindOf(Scene3DLive.blockOf(beamScene())!), 'beam');
      final free = VisualScene3D.fromMap({
        'objects': [
          {
            'type': 'box',
            'at': [0, 0, 0],
            'dims': [1, 1, 1],
          },
        ],
      })!;
      expect(Scene3DLive.blockOf(free), isNull);
      final ball = VisualScene3D.fromMap({
        'objects': [
          {'type': 'body', 'body': 'ball'},
        ],
      })!;
      expect(Scene3DLive.blockOf(ball), isNull);
    });

    test('Ausgangslage: vier Radlasten statt zwei Achskräften, zusammen das ganze Gewicht', () {
      final scene = carScene();
      final block = Scene3DLive.blockOf(scene)!;
      final start = Scene3DLive.initial(block);
      expect(start.cg, closeTo(0.5, 1e-9));
      expect(start.slope, 0);
      expect(start.lifted, isEmpty);
      final live = Scene3DLive.apply(scene, start)!;
      final arrows = arrowsOf(live.scene);
      expect(arrows.keys, containsAll(['F_G', 'VL 25 %', 'VR 25 %', 'HL 25 %', 'HR 25 %']));
      expect(live.status, contains('Vorderachse 50 %, Hinterachse 50 % von F_G'));
      expect(live.warn, isFalse);
      // Die Original-Szene bleibt, wie sie war.
      expect(arrowsOf(scene).keys, containsAll(['F_N,v', 'F_N,h']));
    });

    test('Rad anheben: Pfeil weg, Rad sichtbar oben, die anderen tragen mehr', () {
      final scene = carScene();
      final state = Scene3DLive.initial(Scene3DLive.blockOf(scene)!).copyWith(lifted: {'fl'});
      final live = Scene3DLive.apply(scene, state)!;
      final arrows = arrowsOf(live.scene);
      expect(arrows.keys.where((k) => k.startsWith('VL')), isEmpty);
      expect(arrows.keys, containsAll(['VR 50 %', 'HL 50 %']));
      expect(live.status, contains('Am meisten tragen jetzt die Räder vorn rechts und hinten links (je 50 %)'));
      expect(live.status, contains('Das Rad hinten rechts trägt nichts mehr'));
      expect(live.warn, isFalse);
      // Größere Last = längerer Pfeil.
      double len(Scene3DObject o) => (o.vectors['to']![2] - o.vectors['from']![2]).abs();
      expect(
        len(arrows['VR 50 %']!),
        greaterThan(
          len(arrowsOf(Scene3DLive.apply(scene, Scene3DLive.initial(Scene3DLive.blockOf(scene)!))!.scene)['VR 25 %']!),
        ),
      );
      // Das angehobene Rad steht höher als die anderen.
      final wheels = live.scene.objects.where((o) => o.shape == Scene3DShape.cylinder).toList();
      final heights = wheels.map((w) => w.vectors['from']![2]).toList()..sort();
      expect(heights.last - heights.first, greaterThan(0.1));
      expect(wheels.where((w) => w.fill == 'orange'), hasLength(1));
    });

    test('drei Räder angehoben oder Schwerpunkt daneben: das Auto kippt', () {
      final scene = carScene();
      final start = Scene3DLive.initial(Scene3DLive.blockOf(scene)!);
      final tipped = Scene3DLive.apply(scene, start.copyWith(lifted: {'fl', 'fr', 'rl'}))!;
      expect(tipped.warn, isTrue);
      expect(tipped.status, contains('kippt'));
      expect(arrowsOf(tipped.scene).keys, ['F_G'], reason: 'keine Aufstandskräfte mehr');
      final diagonal = Scene3DLive.apply(scene, start.copyWith(lifted: {'fl'}, cg: 0.9))!;
      expect(diagonal.warn, isTrue);
      expect(diagonal.status, contains('kippt'));
    });

    test('Schwerpunkt und Neigung: Lasten verschieben sich; Gewicht mit Einheit gibt Werte in dieser Einheit', () {
      final scene = carScene(weight: 'F_G = 12 kN');
      final start = Scene3DLive.initial(Scene3DLive.blockOf(scene)!);
      final forward = Scene3DLive.apply(scene, start.copyWith(cg: 0.75))!;
      expect(forward.status, contains('Vorderachse 75 %, Hinterachse 25 % von F_G'));
      expect(arrowsOf(forward.scene).keys, containsAll(['VL 4,5 kN', 'HL 1,5 kN']));
      // Bergauf (vorn höher): Die Last wandert auf die Hinterachse, die Reibung hält den Hangabtrieb.
      final uphill = Scene3DLive.apply(scene, start.copyWith(slope: 20))!;
      final m = RegExp(r'Vorderachse (\d+) %, Hinterachse (\d+) %').firstMatch(uphill.status)!;
      expect(int.parse(m.group(2)!), greaterThan(int.parse(m.group(1)!)));
      expect(uphill.status, contains('Reibung der Räder hält 34 % von F_G'));
    });
  });

  test('Klotz auf schiefer Ebene: Normalkraft, Reibung, haftet oder rutscht', () {
    final scene = blockScene();
    final start = Scene3DLive.initial(Scene3DLive.blockOf(scene)!);
    expect((start.slope, start.mu), (20, 0.5));
    final holds = Scene3DLive.apply(scene, start)!;
    expect(holds.warn, isFalse);
    expect(holds.status, startsWith('Haftet'));
    // 100 N · cos 20° = 94 N, · sin 20° = 34,2 N.
    expect(arrowsOf(holds.scene).keys, containsAll(['F_G = 100 N', 'F_N = 94 N', 'F_R = 34,2 N']));

    final slides = Scene3DLive.apply(scene, start.copyWith(slope: 40))!;
    expect(slides.warn, isTrue);
    expect(slides.status, allOf(startsWith('Rutscht'), contains('m/s²')));
    // Gleitet: Die Reibung ist auf μ · F_N begrenzt (0,5 · 76,6 N).
    expect(arrowsOf(slides.scene).keys, contains('F_R = 38,3 N'));

    final flat = Scene3DLive.apply(scene, start.copyWith(slope: 0))!;
    expect(flat.status, startsWith('Eben'));
    expect(arrowsOf(flat.scene).keys.where((k) => k.startsWith('F_R')), isEmpty);
  });

  group('Balken', () {
    test('Kraft wandert: Lagerkräfte nach dem Hebelgesetz, in der Einheit der Kraft', () {
      final scene = beamScene();
      final block = Scene3DLive.blockOf(scene)!;
      final start = Scene3DLive.initial(block);
      expect(start.forceAt, 2);
      // F = 12 kN bei 2 m von 6 m: A = 8 kN, B = 4 kN.
      final live = Scene3DLive.apply(scene, start)!;
      expect(arrowsOf(live.scene).keys, containsAll(['F = 12 kN', 'A = 8 kN', 'B = 4 kN']));
      expect(live.status, contains('Lager A trägt 67 %, Lager B 33 %'));
      // In die Mitte: je die Hälfte.
      final mid = Scene3DLive.apply(scene, start.copyWith(forceAt: 3))!;
      expect(arrowsOf(mid.scene).keys, containsAll(['A = 6 kN', 'B = 6 kN']));
      // Die Kraft selbst steht jetzt bei 3 m.
      final force = arrowsOf(mid.scene)['F = 12 kN']!, before = arrowsOf(live.scene)['F = 12 kN']!;
      expect(force.vectors['to']![0] - before.vectors['to']![0], closeTo(1, 1e-6));
    });

    test('zweite Kraft zählt mit; ohne Zahlen in Vielfachen der Kraft', () {
      final two = beamScene(
        extra: [
          {'at': 5, 'text': 'F_2 = 6 kN'},
        ],
      );
      final live = Scene3DLive.apply(two, Scene3DLive.initial(Scene3DLive.blockOf(two)!))!;
      // A = 12·4/6 + 6·1/6 = 9, B = 18 − 9 = 9.
      expect(arrowsOf(live.scene).keys, containsAll(['A = 9 kN', 'B = 9 kN']));

      final plain = VisualScene3D.fromMap({
        'objects': [
          {
            'type': 'body',
            'body': 'beam',
            'size': [4, 0.3, 0.3],
            'supports': [
              {'at': 0},
              {'at': 4},
            ],
            'forces': [
              {'at': 1, 'text': 'F'},
            ],
          },
        ],
      })!;
      final shares = Scene3DLive.apply(plain, Scene3DLive.initial(Scene3DLive.blockOf(plain)!))!;
      expect(arrowsOf(shares.scene).keys, containsAll(['A = 0,75 · F', 'B = 0,25 · F']));
    });

    test('nicht angeboten: Einspannung, Streckenlast, nur ein Lager', () {
      Map<String, dynamic>? live(Map<String, dynamic> beam) => Scene3DLive.blockOf(
        VisualScene3D.fromMap({
          'objects': [
            {'type': 'body', 'body': 'beam', ...beam},
          ],
        })!,
      );
      const force = [
        {'at': 1, 'text': 'F'},
      ];
      expect(
        live({
          'supports': [
            {'at': 0, 'kind': 'clamp'},
          ],
          'forces': force,
        }),
        isNull,
      );
      expect(
        live({
          'supports': [
            {'at': 0},
            {'at': 4},
          ],
          'forces': force,
          'loads': [
            {'from': 0, 'to': 2},
          ],
        }),
        isNull,
      );
      expect(
        live({
          'supports': [
            {'at': 0},
          ],
          'forces': force,
        }),
        isNull,
      );
    });
  });

  test('Zahl mit Einheit aus der Beschriftung', () {
    final q = Scene3DLive.quantityIn('F_G = 12,5 kN')!;
    expect((q.value, q.unit, q.symbol), (12.5, 'kN', 'F_G'));
    expect(Scene3DLive.quantityIn('F_G'), isNull);
    expect(Scene3DLive.quantityIn('m·g = 981')!.unit, '');
  });

  group('Ansicht', () {
    Future<void> pump(WidgetTester tester, VisualScene3D scene) async {
      tester.view.physicalSize = const Size(412, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: Scaffold(
            body: SingleChildScrollView(child: Scene3DLiveView(scene: scene, autoplay: false)),
          ),
        ),
      );
    }

    Finder key(String name) => find.byKey(ValueKey(name));
    String status(WidgetTester tester) => tester.widget<Text>(key('scene3d-live-status')).data!;
    VisualScene3D shown(WidgetTester tester) => tester.widget<VisualScene3DView>(find.byType(VisualScene3DView)).scene;

    testWidgets('ohne Körper-Baustein: die gewohnte Ansicht, nichts zum Ausprobieren', (tester) async {
      final scene = VisualScene3D.fromMap({
        'objects': [
          {
            'type': 'sphere',
            'at': [0.5, 0.5, 0.5],
            'r': 0.2,
          },
        ],
      })!;
      await pump(tester, scene);
      expect(key('scene3d-live'), findsNothing);
      expect(identical(shown(tester), scene), isTrue);
    });

    testWidgets('Auto: erst nach dem Einschalten ändert sich etwas; Rad anheben, zurücksetzen, ausschalten', (
      tester,
    ) async {
      final scene = carScene();
      await pump(tester, scene);
      // Aus: genau die Szene der KI.
      expect(key('scene3d-live'), findsOneWidget);
      expect(key('scene3d-live-status'), findsNothing);
      expect(identical(shown(tester), scene), isTrue);

      await tester.tap(key('scene3d-live-toggle'));
      await tester.pump();
      expect(status(tester), contains('Vorderachse 50 %, Hinterachse 50 %'));
      expect(arrowsOf(shown(tester)).keys, contains('VL 25 %'));

      await tester.tap(key('scene3d-live-wheel-fl'));
      await tester.pump();
      expect(status(tester), contains('Am meisten tragen jetzt die Räder'));
      expect(arrowsOf(shown(tester)).keys, containsAll(['VR 50 %', 'HL 50 %']));

      // Zwei weitere Räder hoch: kippt.
      await tester.tap(key('scene3d-live-wheel-fr'));
      await tester.tap(key('scene3d-live-wheel-rl'));
      await tester.pump();
      expect(status(tester), contains('kippt'));

      await tester.tap(key('scene3d-live-reset'));
      await tester.pump();
      expect(status(tester), contains('Vorderachse 50 %, Hinterachse 50 %'));

      // Neigung per Regler (ganz nach rechts = 30°).
      final slider = tester.getRect(key('scene3d-live-slope'));
      await tester.tapAt(Offset(slider.right - 4, slider.center.dy));
      await tester.pump();
      expect(status(tester), contains('Reibung der Räder'));
      expect(tester.widget<Text>(key('scene3d-live-slope-value')).data, '30°');

      await tester.tap(key('scene3d-live-toggle'));
      await tester.pump();
      expect(identical(shown(tester), scene), isTrue, reason: 'ausgeschaltet: wieder das Original');
    });

    testWidgets('Klotz und Balken haben ihre eigenen Regler', (tester) async {
      await pump(tester, blockScene());
      await tester.tap(key('scene3d-live-toggle'));
      await tester.pump();
      expect(key('scene3d-live-mu'), findsOneWidget);
      expect(key('scene3d-live-wheel-fl'), findsNothing);
      expect(status(tester), startsWith('Haftet'));
      final slope = tester.getRect(key('scene3d-live-slope'));
      await tester.tapAt(Offset(slope.right - 4, slope.center.dy));
      await tester.pump();
      expect(status(tester), startsWith('Rutscht'));

      await tester.pumpWidget(const SizedBox());
      await pump(tester, beamScene());
      await tester.tap(key('scene3d-live-toggle'));
      await tester.pump();
      expect(status(tester), contains('Lager A trägt 67 %'));
      final force = tester.getRect(key('scene3d-live-force'));
      await tester.tapAt(force.center);
      await tester.pump();
      expect(status(tester), contains('Lager A trägt 50 %'));
    });
  });
}
