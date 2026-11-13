import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/worked_solution.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/visual/calculator_sim.dart';

Future<void> _press(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('calc-key-$id')));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('Rechner rechnet selbst, übernimmt das Ergebnis, PC-Tastatur geht', (tester) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? used;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 380, child: CalculatorSim(onUseResult: (v) => used = v)),
          ),
        ),
      ),
    );
    for (final k in ['FRAC', '3', 'DOWN', '4', 'RIGHT', 'ADD', '1', 'EQ']) {
      await _press(tester, k);
    }
    expect(find.byKey(const ValueKey('calc-result')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calc-use')));
    expect(used, '7/4');
    await _press(tester, 'SD');
    await tester.tap(find.byKey(const ValueKey('calc-use')));
    expect(used, '1,75');
    await _press(tester, '2');
    await _press(tester, 'DIV');
    await _press(tester, '0');
    await _press(tester, 'EQ');
    expect(find.text('Math ERROR'), findsOneWidget);
    await _press(tester, 'AC');
    // PC-Tastatur
    await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadMultiply);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('calc-use')));
    expect(used, '42');
  });

  testWidgets('Vorführen: die App drückt die Tasten, danach selbst weiter', (tester) async {
    tester.view.physicalSize = const Size(500, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 380,
              child: CalculatorSim(
                calc: WorkCalc(keys: ['AC', 'SHIFT', 'LN', '5', 'RIGHT', 'EQ'], result: '148,41'),
                speed: Duration(milliseconds: 100),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('calc-result')), findsOneWidget);
    expect(find.byKey(const ValueKey('calc-mismatch')), findsNothing);
    await _press(tester, 'ADD');
    await _press(tester, '1');
    await _press(tester, 'EQ');
    expect(find.byKey(const ValueKey('calc-result')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calc-restart')));
    await tester.pump();
    expect(find.byKey(const ValueKey('calc-result')), findsNothing);
  });
}
