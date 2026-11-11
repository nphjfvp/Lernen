import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/visual_lesson_screen.dart';

import '../services/visual_math_test.dart' show carLessonJson;

/// Lektion im Lernpfad in Handybreite (412 px): Der Abschluss-Knopf nennt das
/// nächste Thema und ist deshalb lang; die Kurzfassung hat drei Knöpfe.
void main() {
  testWidgets('Lektion im Lernpfad am Handy: Kurzfassung und Abschluss-Knopf laufen nicht über', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lesson = VisualLesson.fromMap(
      {
        ...carLessonJson(),
        'short': {'title': 'Kurzfassung', 'text': '• Die Ableitung des Wegs ist die Geschwindigkeit.'},
      },
      id: 'l-phone',
      moduleId: 'm-phone',
      createdAt: DateTime(2026, 11, 11),
    )!;
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: VisualLessonScreen(
          lesson: lesson,
          startShort: true,
          finishLabel: 'Abschließen – weiter mit „Integralrechnung: Flächen unter Geschwindigkeitskurven“',
          onFinished: () => finished++,
        ),
      ),
    );
    await tester.pump();
    // Kurzfassung: Ändern, Ausführlich ansehen, Erledigt.
    expect(find.byKey(const ValueKey('visual-short-revise')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-short-finish')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('visual-short-full')));
    await tester.tap(find.byKey(const ValueKey('visual-short-full')));
    await tester.pump();
    // Bis zur letzten Seite blättern: dort steht der lange Abschluss-Knopf.
    for (var i = 0; i < 8 && find.byKey(const ValueKey('visual-finish')).evaluate().isEmpty; i++) {
      await tester.tap(find.byKey(const ValueKey('visual-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Die Seiten dazwischen sind hier nicht das Thema (mit der breiten
      // Test-Schrift wird dort manches enger als am Gerät).
      tester.takeException();
    }
    expect(find.byKey(const ValueKey('visual-finish')), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-prev')), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Der Knopf bleibt innerhalb des Bildschirms.
    expect(tester.getRect(find.byKey(const ValueKey('visual-finish'))).right, lessThanOrEqualTo(412));
    await tester.tap(find.byKey(const ValueKey('visual-finish')));
    await tester.pump();
    expect(finished, 1);
  });
}
