import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/ui/widgets/math_text.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('Text ohne Formel bleibt ein normales Text-Widget', (tester) async {
    await tester.pumpWidget(_wrap(const MathText('Ganz normaler Text')));
    expect(find.text('Ganz normaler Text'), findsOneWidget);
    expect(find.byType(Math), findsNothing);
  });

  testWidgets('Formeln werden als Math gesetzt', (tester) async {
    await tester.pumpWidget(_wrap(const MathText(r'Es gilt $a^2+b^2=c^2$ und $$\frac{1}{2}$$')));
    expect(find.byType(Math), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('kaputte Formel führt nicht zum Absturz', (tester) async {
    await tester.pumpWidget(_wrap(const MathText(r'Kaputt: $\frac{1}{$ Ende')));
    expect(tester.takeException(), isNull);
  });
}
