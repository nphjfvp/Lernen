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

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_weight_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  test('formatWeight: deutsches Komma, keine überflüssigen Nullen', () {
    expect(formatWeight(1.0), '1');
    expect(formatWeight(1.5), '1,5');
    expect(formatWeight(1.25), '1,25');
    expect(formatWeight(0.5), '0,5');
    expect(formatWeight(3), '3');
  });

  testWidgets('Fach-Formular zeigt die gespeicherte Gewichtung des Fachs', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final module = Module(
      id: 'm1',
      name: 'Technik',
      colorValue: 0xFF3D5AFE,
      icon: '⚙️',
      examDate: null,
      createdAt: DateTime(2026, 1, 1),
      weight: 2.0,
    );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: ModuleFormScreen(existing: module),
    ));

    expect(find.text('Gewichtung'), findsOneWidget);
    final slider = tester.widget<Slider>(
        find.descendant(of: find.byKey(const ValueKey('module-weight-slider')), matching: find.byType(Slider)));
    expect(slider.value, 2.0);
    expect(find.text('2×'), findsOneWidget);
  });

  testWidgets('Kartenliste: Gewichtung einer Karte ändern und speichern', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final flashcards = FlashcardRepository();
    final card = Flashcard(
      id: 'weight-card',
      moduleId: 'weight-module',
      front: 'Was ist Spannung?',
      back: 'Potentialdifferenz',
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      weight: 1.5,
    );
    await tester.runAsync(() async {
      await flashcards.saveAll([card]);
      await flashcards.loadForModule('weight-module');
    });

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: flashcards,
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const FlashcardListScreen(moduleId: 'weight-module', moduleName: 'Technik'),
      ),
    ));
    await tester.pump();

    // Nicht-Standard-Gewicht steht in der Statuszeile.
    expect(find.textContaining('1,5× gewichtet'), findsOneWidget);

    await tester.tap(find.text('Was ist Spannung?'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('card-weight-weight-card')));
    await tester.pumpAndSettle();

    final sliderFinder =
        find.descendant(of: find.byKey(const ValueKey('card-weight-slider')), matching: find.byType(Slider));
    expect(tester.widget<Slider>(sliderFinder).value, 1.5);
    // Ganz nach rechts ziehen -> Maximum (3×).
    await tester.drag(sliderFinder, const Offset(600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    Flashcard? stored;
    for (var i = 0; i < 20; i++) {
      stored = await tester.runAsync<Flashcard?>(() async {
        final db = await DatabaseService.instance.database;
        final raw = await DatabaseService.flashcards.record('weight-card').get(db);
        return raw == null ? null : Flashcard.fromMap(raw);
      });
      if (stored?.weight == WeightSlider.maxValue) break;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(stored!.weight, WeightSlider.maxValue);
    // Lernstand/Inhalt unverändert.
    expect(stored.front, 'Was ist Spannung?');
  });
}
