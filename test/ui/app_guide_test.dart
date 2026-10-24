import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/guide/app_guide.dart';
import 'package:lernen/ui/guide/app_guide_screen.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppGuideScreen())),
              child: const Text('öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
  }

  test('Inhalt: jedes Kapitel mit Einleitung und Punkten, nichts leer', () {
    expect(appGuideChapters.length, greaterThanOrEqualTo(10));
    for (final ch in appGuideChapters) {
      expect(ch.intro.trim(), isNotEmpty, reason: ch.title);
      expect(ch.items, isNotEmpty, reason: ch.title);
      for (final item in ch.items) {
        expect(item.title.trim(), isNotEmpty);
        expect(item.text.trim(), isNotEmpty, reason: item.title);
      }
    }
    final titles = appGuideChapters.map((c) => c.title).toList();
    expect(titles, containsAll(['Der Lernkreislauf', 'Daily Quiz und Lernstand', 'Visuell lernen', 'Spiele']));
  });

  testWidgets('Übersicht, Kapitel anspringen, blättern, zurück zum Inhalt, Fertig schließt', (tester) async {
    await open(tester);
    expect(find.text('Willkommen bei Lernen'), findsOneWidget);
    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-prev')), findsNothing);

    // Direkt zu „Spiele“.
    final games = appGuideChapters.indexWhere((c) => c.title == 'Spiele');
    await tester.ensureVisible(find.byKey(ValueKey('guide-chapter-$games')));
    await tester.tap(find.byKey(ValueKey('guide-chapter-$games')));
    await tester.pumpAndSettle();
    expect(find.text('Boss-Kampf'), findsOneWidget);
    expect(find.text('Kapitel ${games + 1} von ${appGuideChapters.length}'), findsOneWidget);
    expect(find.text('Fortschritt → Spiele'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('guide-next')));
    await tester.pumpAndSettle();
    expect(find.text(appGuideChapters[games + 1].title), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-prev')));
    await tester.pumpAndSettle();
    expect(find.text('Spiele'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guide-toc')));
    await tester.pumpAndSettle();
    expect(find.text('Willkommen bei Lernen'), findsOneWidget);

    // Bis zum Ende blättern: der letzte Knopf heißt „Fertig“ und schließt.
    for (var i = 0; i < appGuideChapters.length; i++) {
      await tester.tap(find.byKey(const ValueKey('guide-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Fertig'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-next')));
    await tester.pumpAndSettle();
    expect(find.byType(AppGuideScreen), findsNothing);
    expect(find.text('öffnen'), findsOneWidget);
  });
}
