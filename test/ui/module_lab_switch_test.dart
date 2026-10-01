import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/modules/module_form_screen.dart';

Module _module({bool isLab = false}) => Module(
      id: 'm1',
      name: 'Technik',
      colorValue: 0xFF3D5AFE,
      icon: '⚙️',
      examDate: null,
      createdAt: DateTime(2026, 1, 1),
      isLab: isLab,
    );

void main() {
  Future<void> pump(WidgetTester tester, {Module? existing}) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: ModuleFormScreen(existing: existing),
    ));
  }

  SwitchListTile tile(WidgetTester tester) => tester.widget<SwitchListTile>(find.byKey(const ValueKey('module-is-lab')));

  testWidgets('neues Fach: Laborfach ist aus und lässt sich schon beim Anlegen einschalten', (tester) async {
    await pump(tester);
    expect(find.text('Laborfach'), findsOneWidget);
    expect(tile(tester).value, isFalse);
    await tester.tap(find.byKey(const ValueKey('module-is-lab')));
    await tester.pump();
    expect(tile(tester).value, isTrue);
  });

  testWidgets('bestehendes Laborfach zeigt den Schalter an', (tester) async {
    await pump(tester, existing: _module(isLab: true));
    expect(tile(tester).value, isTrue);
  });
}
