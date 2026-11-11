import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/flashcards/flashcard_list_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_card_list_phone_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  testWidgets('Kartenliste in Handybreite: die Knopfzeile einer Karte bricht um statt überzulaufen', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final flashcards = FlashcardRepository();
    final card = Flashcard(
      id: 'phone-card',
      moduleId: 'phone-module',
      front: 'Was trägt der Träger?',
      back: 'Einen Träger',
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
    );
    await tester.runAsync(() async {
      await flashcards.saveAll([card]);
      await flashcards.loadForModule('phone-module');
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: flashcards,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const FlashcardListScreen(moduleId: 'phone-module', moduleName: 'Technik'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Was trägt der Träger?'));
    await tester.pumpAndSettle();
    // Alle Knöpfe sind da – und nichts läuft über.
    for (final label in ['Stufe', 'Gewichtung', 'Bearbeiten', 'Löschen']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('card-actions-phone-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
