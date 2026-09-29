import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/flashcards/flashcard_list_screen.dart';
import 'package:lernen/ui/modules/module_form_screen.dart';
import 'package:lernen/ui/widgets/weight_slider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void _ignore(double _) {}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_muted_weight_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  test('Regler-Beschriftung: "Aus" bei 0; nur der Regler einer Karte darf bis 0', () {
    expect(weightLabel(0), 'Aus');
    expect(weightLabel(1.5), '1,5×');
    expect(const WeightSlider(value: 1, onChanged: _ignore).allowZero, isFalse);
    expect(const WeightSlider(value: 1, onChanged: _ignore, allowZero: true).allowZero, isTrue);
  });

  testWidgets('Fach-Formular: der Regler des Fachs geht nicht bis 0', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: ModuleFormScreen(
        existing: Module(
          id: 'mm1',
          name: 'Technik',
          colorValue: 0xFF3D5AFE,
          icon: '⚙️',
          examDate: null,
          createdAt: DateTime(2026, 1, 1),
        ),
      ),
    ));
    await tester.pump();
    final slider = tester.widget<Slider>(
        find.descendant(of: find.byKey(const ValueKey('module-weight-slider')), matching: find.byType(Slider)));
    expect(slider.min, WeightSlider.minValue);
  });

  testWidgets('Kartenliste: Gewichtung ganz auf 0 = stummgeschaltet und wieder einschaltbar', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final flashcards = FlashcardRepository();
    await tester.runAsync(() async {
      await flashcards.saveAll([
        Flashcard(
          id: 'mute-card',
          moduleId: 'mute-module',
          front: 'Was ist Induktivität?',
          back: 'Eigenschaft einer Spule',
          createdAt: DateTime(2026, 9, 1),
          due: DateTime(2026, 9, 1),
        ),
      ]);
      await flashcards.loadForModule('mute-module');
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: flashcards,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const FlashcardListScreen(moduleId: 'mute-module', moduleName: 'Technik'),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('Stummgeschaltet'), findsNothing);

    Future<Flashcard?> stored() => tester.runAsync<Flashcard?>(() async {
          final db = await DatabaseService.instance.database;
          final raw = await DatabaseService.flashcards.record('mute-card').get(db);
          return raw == null ? null : Flashcard.fromMap(raw);
        });
    /// Wartet auf die Datenbank UND darauf, dass die Liste den neuen Stand zeigt
    /// (das Repository lädt nach dem Speichern erst noch nach).
    Future<void> waitFor(bool Function(Flashcard) inDb, bool Function() onScreen) async {
      for (var i = 0; i < 60; i++) {
        final card = await stored();
        if (card != null && inDb(card)) {
          // Der Screen lädt nach dem Speichern selbst nach; hier im echten
          // Zeitablauf, damit der Test nicht von dessen Timing abhängt.
          await tester.runAsync(() => flashcards.loadForModule('mute-module'));
          await tester.pump(const Duration(milliseconds: 50));
          if (onScreen()) break;
        }
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    final sliderFinder =
        find.descendant(of: find.byKey(const ValueKey('card-weight-slider')), matching: find.byType(Slider));

    await tester.tap(find.text('Was ist Induktivität?'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('card-weight-mute-card')));
    await tester.pumpAndSettle();

    // Der Regler der Karte reicht bis 0.
    expect(tester.widget<Slider>(sliderFinder).min, 0.0);
    expect(find.byKey(const ValueKey('card-weight-muted-hint')), findsNothing);
    // Ganz nach links ziehen -> "Aus".
    await tester.drag(sliderFinder, const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(sliderFinder).value, 0.0);
    expect(find.text('Aus'), findsOneWidget);
    expect(find.byKey(const ValueKey('card-weight-muted-hint')), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await waitFor((c) => c.weight == 0, () => find.textContaining('Stummgeschaltet').evaluate().isNotEmpty);

    final muted = await stored();
    expect(muted!.weight, 0.0);
    expect(muted.isMuted, isTrue);
    // In der Liste steht es an der Karte – nicht als "0× gewichtet".
    expect(find.textContaining('Stummgeschaltet'), findsWidgets);
    expect(find.textContaining('× gewichtet'), findsNothing);

    // Wieder einschalten: Regler zurück auf die Mitte.
    await tester.tap(find.byKey(const ValueKey('card-weight-mute-card')));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(sliderFinder).value, 0.0);
    await tester.drag(sliderFinder, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(sliderFinder).value, greaterThan(0));
    await tester.tap(find.text('Speichern'));
    await waitFor((c) => c.weight > 0, () => find.textContaining('Stummgeschaltet').evaluate().isEmpty);
    final back = await stored();
    expect(back!.isMuted, isFalse);
    expect(find.textContaining('Stummgeschaltet'), findsNothing);
  });
}
