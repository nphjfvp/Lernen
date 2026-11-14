import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/visual_scene3d.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/scene3d_live.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/scene3d_live_view.dart';

Map<String, dynamic> _car() => {
  'objects': [
    {
      'type': 'body',
      'body': 'car',
      'size': [4, 2, 1.5],
      'wheelbase': 2.4,
      'cut': true,
      'forces': [
        {'at': 'cg', 'dir': 'down', 'text': 'F_G = 12 kN'},
      ],
    },
  ],
};

void main() {
  test('Ablauf: fehlende Werte erben, Zahlen gleiten, Räder wechseln am Schritt', () {
    final block = {
      ..._car()['objects'][0] as Map<String, dynamic>,
      'timeline': [
        {'at': 0, 'lifted': [], 'caption': 'fährt'},
        {'at': 0.4, 'lifted': ['fl', 'XX'], 'caption': 'vorn links im Schlagloch'},
        {'at': 0.6, 'lifted': [], 'slope': 10, 'caption': 'wieder auf der Straße'},
      ],
    };
    final timeline = Scene3DLive.timelineOf(block, Scene3DLive.initial(block));
    expect(timeline, hasLength(3));
    expect(timeline[1].state.lifted, {'fl'}, reason: 'unbekannte Räder fallen weg');
    expect(Scene3DLive.stateAt(timeline, 0.45).caption, 'vorn links im Schlagloch');
    expect(Scene3DLive.stateAt(timeline, 0.45).state.lifted, {'fl'});
    expect(Scene3DLive.stateAt(timeline, 0.5).state.slope, closeTo(5, 1e-9), reason: 'Neigung gleitet 0 → 10');
    expect(Scene3DLive.stateAt(timeline, 1).state.slope, 10);
    // Die App rechnet die Kräfte im Schlagloch.
    final scene = VisualScene3D.fromMap({
      'objects': [block],
    })!;
    final live = Scene3DLive.apply(scene, Scene3DLive.stateAt(timeline, 0.45).state);
    expect(live!.status, isNotEmpty);
  });

  testWidgets('Simulation erweitern: Wunsch an die KI, Ablauf abspielen, Rückgängig', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <String>[];
    VisualScene3D? stored;
    final ai = AiService(
      apiKey: 'sk-test',
      model: 'm',
      client: MockClient((r) async {
        sent.add('${((jsonDecode(r.body) as Map)['messages'] as List)[1]['content']}');
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'scene3d': _car(),
                    'timeline': [
                      {'at': 0, 'lifted': [], 'caption': 'Das Auto rollt auf das Schlagloch zu.'},
                      {'at': 0.5, 'lifted': ['fl'], 'caption': 'Vorn links im Schlagloch – die anderen tragen.'},
                      {'at': 0.8, 'lifted': [], 'caption': 'Wieder alle vier auf der Straße.'},
                    ],
                    'say': 'Das Auto fährt durch ein Schlagloch.',
                    'note': 'Statisch gerechnet – der Stoß beim Aufsetzen fehlt.',
                  }),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final scene = VisualScene3D.fromMap(_car())!;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Scene3DLiveView(
              scene: scene,
              autoplay: false,
              extendAi: () => ai,
              onSceneChanged: (s) => stored = s,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('scene3d-extend')), findsOneWidget);
    expect(find.byKey(const ValueKey('scene3d-timeline')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('scene3d-extend-input')), 'lass es durch ein Schlagloch fahren');
    await tester.tap(find.byKey(const ValueKey('scene3d-extend-go')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(sent.single, contains('Wunsch des Nutzers: lass es durch ein Schlagloch fahren'));
    expect(stored, isNotNull);
    expect(Scene3DLive.blockOf(stored!)!['timeline'], isA<List>(), reason: 'Ablauf hängt am Baustein');
    expect(find.byKey(const ValueKey('scene3d-timeline')), findsOneWidget);
    expect(find.byKey(const ValueKey('scene3d-extend-say')), findsOneWidget);
    expect(find.textContaining('Stoß beim Aufsetzen'), findsOneWidget);

    // Der Ablauf läuft: im Schlagloch rechnet die App die Kräfte neu.
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('scene3d-timeline-caption')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scene3d-timeline-play')));
    await tester.pump();
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('scene3d-timeline-slider')));
    slider.onChanged!(0.6);
    await tester.pump();
    expect(find.text('Vorn links im Schlagloch – die anderen tragen.'), findsOneWidget);
    expect(find.byKey(const ValueKey('scene3d-live-status')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scene3d-extend-undo')));
    await tester.pump();
    expect(find.byKey(const ValueKey('scene3d-timeline')), findsNothing);
    expect(Scene3DLive.blockOf(stored!)!['timeline'], isNull, reason: 'die alte Szene ist zurück');
  });
}
