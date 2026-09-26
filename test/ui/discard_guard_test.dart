import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/ui/widgets/discard_guard.dart';

void main() {
  Future<void> openGuarded(WidgetTester tester, {required bool active}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DiscardGuard(
              active: active,
              message: 'Noch nicht gespeichert.',
              child: const Scaffold(body: Text('Vorschau')),
            ),
          )),
          child: const Text('Öffnen'),
        ),
      ),
    ));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
  }

  testWidgets('Zurück mit ungespeichertem Ergebnis fragt nach; Abbrechen bleibt', (tester) async {
    await openGuarded(tester, active: true);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ergebnis verwerfen?'), findsOneWidget);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Vorschau'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();
    expect(find.text('Vorschau'), findsNothing);
    expect(find.text('Öffnen'), findsOneWidget);
  });

  testWidgets('ohne ungespeichertes Ergebnis geht Zurück sofort', (tester) async {
    await openGuarded(tester, active: false);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ergebnis verwerfen?'), findsNothing);
    expect(find.text('Öffnen'), findsOneWidget);
  });
}
