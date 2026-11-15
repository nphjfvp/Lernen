import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/windows_guard.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/settings/pc_block_layer.dart';

void main() {
  tearDown(() {
    WindowsGuard.instance.block.value = null;
    WindowsGuard.invokeHook = null;
  });

  testWidgets('Sperrbildschirm am PC über der App, „Jetzt lernen“ schließt ihn', (tester) async {
    final calls = <String>[];
    WindowsGuard.invokeHook = (method, [args]) async {
      calls.add(method);
      return null;
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => PcBlockLayer(child: child!),
        home: const Scaffold(body: Text('Fächer')),
      ),
    );
    expect(find.byKey(const ValueKey('pc-block')), findsNothing);

    WindowsGuard.instance.block.value = const PcBlock(
      group: PcGroup.game,
      what: 'VALORANT',
      usedMinutes: 270,
      allowedMinutes: 270,
      nextStep: 'Lerne ein neues Thema für +30 Minuten Spielzeit.',
    );
    await tester.pump();
    expect(find.text('Spielzeit aufgebraucht'), findsOneWidget);
    expect(find.text('Diese Woche 4 h 30 min von 4 h 30 min gespielt.'), findsOneWidget);
    expect(find.text('„VALORANT“ wurde minimiert.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pc-block-learn')));
    await tester.pump();
    expect(find.byKey(const ValueKey('pc-block')), findsNothing);
    expect(find.text('Fächer'), findsOneWidget);

    WindowsGuard.instance.block.value = const PcBlock(
      group: PcGroup.daily,
      what: 'YouTube',
      usedMinutes: 30,
      allowedMinutes: 30,
      nextStep: '',
    );
    await tester.pump();
    expect(find.textContaining('Handy und PC'), findsOneWidget);
    expect(find.textContaining('Im Hintergrund weiterhören'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pc-block-hide')));
    await tester.pump();
    expect(calls, contains('hideSelf'));
    expect(find.byKey(const ValueKey('pc-block')), findsNothing);
  });
}
