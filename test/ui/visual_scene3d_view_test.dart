import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/models/visual_scene3d.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/visual_lesson_screen.dart';
import 'package:lernen/ui/visual/visual_scene3d_view.dart';

import '../services/visual_scene3d_test.dart' show fccScene;

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: child,
      ),
    );
  }

  String text(WidgetTester tester, String key) {
    final w = tester.widget(find.byKey(ValueKey(key)));
    if (w is Text) return w.data ?? '';
    return tester
        .widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join(' ');
  }

  Scene3DPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(of: find.byKey(const ValueKey('visual-scene3d')), matching: find.byType(CustomPaint)),
      )
      .map((p) => p.painter)
      .whereType<Scene3DPainter>()
      .single;

  testWidgets('3D-Szene: abspielen (Packungsdichte läuft mit), drehen, Ansicht zurück, alle Formen ohne Fehler', (
    tester,
  ) async {
    final s = VisualScene3D.fromMap({...fccScene(), 'spin': true})!;
    await pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(child: VisualScene3DView(scene: s)),
      ),
    );
    expect(text(tester, 'scene3d-param'), 'Packungsdichte = 2 %');
    expect(text(tester, 'scene3d-caption'), contains('viel Platz'));
    final theta0 = painter(tester).theta;

    for (var i = 0; i < 26; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(text(tester, 'scene3d-param'), 'Packungsdichte = 74 %');
    expect(text(tester, 'scene3d-caption'), contains('Berühren sich'));
    expect(painter(tester).theta, closeTo(theta0 + 180, 1e-6), reason: 'spin: einmal halb herum');
    expect(tester.takeException(), isNull);

    // Drehen per Ziehen und Knopf, dann Ansicht zurück.
    await tester.drag(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is Scene3DPainter),
      const Offset(100, 50),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scene3d-rot-left')));
    await tester.pump();
    final turned = painter(tester);
    expect(turned.theta, isNot(closeTo(theta0 + 180, 1e-6)));
    expect(turned.phi, greaterThan(20));
    await tester.tap(find.byKey(const ValueKey('scene3d-view')));
    await tester.pump();
    expect(painter(tester).theta, closeTo(theta0 + 180, 1e-6));
    expect(painter(tester).phi, 20);

    await tester.drag(find.byKey(const ValueKey('scene3d-time')), const Offset(-2000, 0));
    await tester.pump();
    expect(text(tester, 'scene3d-param'), 'Packungsdichte = 2 %');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lektion mit räumlicher Szene im Schritt', (tester) async {
    final lesson = VisualLesson.fromMap({
      'title': 'Packungsdichte kfz',
      'steps': [
        {
          'title': 'Atome wachsen',
          'text': 'Bis sie sich berühren.',
          'show': {'scene3d': fccScene()},
        },
      ],
    }, createdAt: DateTime(2026))!;
    await pump(tester, VisualLessonScreen(lesson: lesson));
    expect(find.byKey(const ValueKey('visual-scene3d')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-diagram')), findsNothing);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('3D: Texte mit Formeln echt gesetzt, normale Texte gezeichnet', (tester) async {
    final s = VisualScene3D.fromMap({
      'objects': [
        {
          'type': 'sphere',
          'at': [0.5, 0.5, 0.5],
          'r': 0.2,
          'text': 'Fe',
        },
        {
          'type': 'text',
          'at': [0.5, 0.5, 1.2],
          'text': r'$r = \frac{a\sqrt{2}}{4}$',
        },
      ],
    })!;
    await pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(child: VisualScene3DView(scene: s, autoplay: false)),
      ),
    );
    expect(find.byKey(const ValueKey('scene3d-formula-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('scene3d-formula-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
