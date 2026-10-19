import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/firestore_rules.dart';
import 'package:lernen/services/sync_codes.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/settings/sync_code_hint.dart';

void main() {
  test('Erzeugte Codes: zufällig, 4×4 Zeichen ohne Verwechsler, lang genug für die Regeln', () {
    final codes = {for (var i = 0; i < 200; i++) SyncCodes.generate()};
    expect(codes, hasLength(200));
    for (final c in codes) {
      expect(c, matches(RegExp(r'^[a-hjkmnp-z2-9]{4}(-[a-hjkmnp-z2-9]{4}){3}$')));
      expect(SyncCodes.isStrong(c), isTrue);
    }
    expect(SyncCodes.generate(random: Random(1)), SyncCodes.generate(random: Random(1)));
    expect(SyncCodes.isStrong('mein-code'), isFalse);
    expect(SyncCodes.isStrong('  ${'a' * 15}  '), isFalse);
    expect(SyncCodes.isStrong('a' * 16), isTrue);
  });

  test('Firestore-Regeln verlangen dieselbe Mindestlänge (App-Kopie und Datei)', () {
    for (final rules in [firestoreRulesText, File('firestore.rules').readAsStringSync()]) {
      expect(rules, contains('code.size() >= ${SyncCodes.minLength}'));
      expect(rules, isNot(contains('code.size() >= 6')));
    }
  });

  testWidgets('Hinweis: leer → erzeugen, kurz → umziehen, sicher → nichts', (tester) async {
    final controller = TextEditingController();
    var moves = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: SyncCodeHint(
            controller: controller,
            onGenerate: () => controller.text = SyncCodes.generate(),
            onMove: () => moves++,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('sync-code-generate')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sync-code-generate')));
    await tester.pump();
    expect(SyncCodes.isStrong(controller.text), isTrue);
    expect(find.byKey(const ValueKey('sync-code-generate')), findsNothing);
    expect(find.byKey(const ValueKey('sync-code-weak')), findsNothing);

    controller.text = 'abc123';
    await tester.pump();
    expect(find.byKey(const ValueKey('sync-code-weak')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sync-code-move')));
    expect(moves, 1);
  });
}
