import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_diagram.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/visual_diagram_view.dart';
import 'package:lernen/ui/visual/visual_lesson_screen.dart';

import '../services/visual_diagram_test.dart' show latticeScene;

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

  testWidgets('Szene spielt ab: Beschriftung und Temperatur laufen mit, Regler und Neustart', (tester) async {
    final d = VisualDiagram.fromMap(latticeScene())!;
    await pump(tester, Scaffold(body: VisualDiagramView(diagram: d)));
    expect(find.byKey(const ValueKey('visual-diagram')), findsOneWidget);
    expect(text(tester, 'diagram-param'), 'Temperatur = 20 °C');
    expect(text(tester, 'diagram-caption'), contains('Kalt'));

    // 8 s Durchlauf: nach 6 s ist es warm.
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(text(tester, 'diagram-param'), 'Temperatur = 620 °C');
    expect(text(tester, 'diagram-caption'), contains('größerer Abstand'));
    await tester.pump(const Duration(seconds: 3));
    expect(text(tester, 'diagram-param'), 'Temperatur = 820 °C');

    await tester.drag(find.byKey(const ValueKey('diagram-time')), const Offset(-2000, 0));
    await tester.pump();
    expect(text(tester, 'diagram-param'), 'Temperatur = 20 °C');
    await tester.tap(find.byKey(const ValueKey('diagram-restart')));
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('Alle Formen werden gezeichnet (auch gestrichelt, gedreht, Hex-Farben, ohne Größe)', (tester) async {
    final d = VisualDiagram.fromMap({
      'width': 80,
      'height': 40,
      'elements': [
        {'type': 'circle', 'x': 5, 'y': 5, 'r': 2, 'stroke': '#c33', 'text': 'C'},
        {'type': 'rect', 'x': 10, 'y': 10, 'w': 20, 'h': 6, 'fill': '#0a0', 'text': 'Korn', 'rotate': 20},
        {'type': 'line', 'x1': 0, 'y1': 30, 'x2': 80, 'y2': 30, 'dashed': true},
        {'type': 'arrow', 'x1': 40, 'y1': 5, 'x2': 40, 'y2': 25, 'stroke': 'red', 'text': 'F', 'draw': 0.5},
        {
          'type': 'polygon',
          'points': [
            [50, 35],
            [60, 20],
            [70, 35],
          ],
          'stroke': 'purple',
          'dashed': true,
          'text': 'α',
        },
        {
          'type': 'path',
          'points': [
            [0, 39],
            [40, 20],
            [79, 1],
          ],
          'dashed': true,
          'text': 'Kurve',
        },
        {'type': 'text', 'x': 40, 'y': 38, 'text': 'Beschriftung', 'fill': 'gelbgrün'},
        {
          'type': 'circle',
          'x': 70,
          'y': 5,
          'r': 2,
          'opacity': 0,
          'keys': [
            {'at': 1, 'opacity': 1, 'scale': 2},
          ],
        },
      ],
    })!;
    expect(d.elements, hasLength(8));
    await pump(tester, Scaffold(body: VisualDiagramView(diagram: d, autoplay: false)));
    await tester.drag(find.byKey(const ValueKey('diagram-time')), const Offset(150, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(text(tester, 'diagram-param'), endsWith('%'));
    expect(find.byKey(const ValueKey('diagram-caption')), findsNothing);
  });

  testWidgets('Lektion ohne Funktionen: Szene im Schritt, kein Auto, kein Graph', (tester) async {
    final lesson = VisualLesson.fromMap({
      'title': 'Wärmeausdehnung',
      'intro': 'Ein Stahlstab wird erwärmt.',
      'steps': [
        {
          'title': 'Atome schwingen',
          'text': 'Mit der Temperatur steigt die Schwingung.',
          'show': {'scene': latticeScene()},
        },
      ],
    }, createdAt: DateTime(2026))!;
    await pump(tester, VisualLessonScreen(lesson: lesson));
    expect(find.byKey(const ValueKey('visual-diagram')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-car')), findsNothing);
    expect(find.byKey(const ValueKey('visual-plot')), findsNothing);
    await tester.pump(const Duration(seconds: 9));
  });
}
