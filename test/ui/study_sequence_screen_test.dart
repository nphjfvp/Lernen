import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/models/study_sequence.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/study_sequence_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/practice/study_sequence_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Flashcard _card(int i) => Flashcard(
  id: 'k$i',
  moduleId: 'sm',
  front: 'Aufgabe Nummer $i',
  back: 'Lösung $i',
  createdAt: DateTime(2026, 11, 1, 10, i),
  due: DateTime(2026, 11, 1),
  sourceMaterialId: 'blatt',
  sourcePage: 1,
);

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_sequence_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  const source = StudySequenceSource(kind: StudySequenceKind.material, id: 'blatt', title: 'Übungsblatt 3');

  Future<void> settle(WidgetTester tester, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('Der Reihe nach: lösen, nicht geschafft, kann ich schon, Stand bleibt, Neustart ab Aufgabe', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flashcards = FlashcardRepository();
    final modules = ModuleRepository();
    final settings = SettingsRepository();
    await tester.runAsync(() async {
      await settings.update(const AppSettings());
      await modules.save(
        Module(
          id: 'sm',
          name: 'Mathe',
          colorValue: 0xFF336699,
          icon: 'calculate',
          examDate: null,
          createdAt: DateTime(2026),
        ),
      );
      // Absichtlich ungeordnet gespeichert.
      await flashcards.saveAll([_card(3), _card(1), _card(4), _card(2)]);
    });

    Widget app() => MultiProvider(
      providers: [
        ChangeNotifierProvider<FlashcardRepository>.value(value: flashcards),
        ChangeNotifierProvider<ModuleRepository>.value(value: modules),
        ChangeNotifierProvider<SettingsRepository>.value(value: settings),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const StudySequenceScreen(moduleId: 'sm', source: source),
      ),
    );

    String summary() => tester.widget<Text>(find.byKey(const ValueKey('sequence-summary'))).data!;

    await tester.pumpWidget(app());
    await settle(tester);
    expect(summary(), '0 von 4 erledigt');
    expect(find.text('Bei Aufgabe 1 beginnen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sequence-continue')));
    await settle(tester);

    Future<void> answer(String grade) async {
      await tester.tap(find.text('Zum Umdrehen tippen'));
      await settle(tester, 4);
      await tester.ensureVisible(find.text(grade));
      await tester.pump();
      await tester.tap(find.text(grade));
      await settle(tester, 30);
    }

    expect(find.text('Aufgabe Nummer 1'), findsOneWidget);
    expect(find.textContaining('Aufgabe 1 von 4'), findsOneWidget);
    await answer('Gut');
    expect(find.text('Aufgabe Nummer 2'), findsOneWidget);
    await answer('Nochmal');
    expect(find.text('Aufgabe Nummer 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sequence-understood')));
    await settle(tester);
    expect(find.text('Aufgabe Nummer 4'), findsOneWidget);
    await answer('Gut');
    expect(find.text('Runde fertig: 2 gelöst, 1 noch nicht geschafft, 1 übersprungen.'), findsOneWidget);
    expect(find.text('Nächste Runde: 1 offen, ab Aufgabe 2'), findsOneWidget);
    final stored = await tester.runAsync(() => StudySequenceRepository().load('sm', source));
    expect(stored!.status['k2'], StudySequenceStatus.failed);
    expect(stored.status['k3'], StudySequenceStatus.skipped);

    // Später wieder öffnen: der Stand ist da.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await settle(tester);
    expect(summary(), '3 von 4 erledigt · 1 noch nicht geschafft');
    expect(find.text('Weiter bei Aufgabe 2'), findsOneWidget);

    // Aufgabe 3 wieder öffnen und dort neu starten.
    await tester.tap(find.byKey(const ValueKey('sequence-item-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sequence-item-start')));
    await settle(tester);
    expect(find.text('Aufgabe Nummer 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sequence-overview')));
    await settle(tester);
    expect(summary(), '2 von 4 erledigt', reason: '1 gelöst, 2 davor gilt als erledigt, ab 3 offen');

    // Neu starten von vorn über den Dialog.
    await tester.tap(find.byKey(const ValueKey('sequence-restart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sequence-restart-ok')));
    await settle(tester);
    expect(find.text('Bei Aufgabe 1 beginnen'), findsNothing);
    expect(find.text('Weiter bei Aufgabe 1'), findsOneWidget);
    expect(summary(), '0 von 4 erledigt');
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
