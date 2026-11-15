import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/learn_credit.dart';
import 'package:lernen/services/screen_guard.dart';
import 'package:lernen/services/windows_guard.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/settings/screen_guard_screen.dart';

void main() {
  late List<(String, Object?)> calls;
  late LearnCreditRules saved;

  setUp(() {
    calls = [];
    saved = const LearnCreditRules();
    ScreenGuardScreen.loadHook = () async => (
      rules: saved,
      credit: LearnCredit(
        earned: {
          'concept:c1': EarnedTopic(
            day: LearnCredit.dayKey(DateTime.now(), 4),
            title: 'Variablen trennen',
            at: DateTime.now(),
          ),
        },
      ),
    );
    ScreenGuardScreen.saveHook = (rules) async => saved = rules;
  });

  tearDown(() {
    ScreenGuardScreen.loadHook = null;
    ScreenGuardScreen.saveHook = null;
    ScreenGuard.invokeHook = null;
    WindowsGuard.invokeHook = null;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const ScreenGuardScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('Android: Guthaben, Berechtigungen, Apps und Regeln', (tester) async {
    ScreenGuard.invokeHook = (method, [args]) async {
      calls.add((method, args));
      return switch (method) {
        'status' => {'usageAccess': true, 'overlay': false, 'running': saved.enabled},
        'usedMinutes' => 12,
        'installedApps' => [
          {'package': 'com.instagram.android', 'label': 'Instagram'},
          {'package': 'com.zhiliaoapp.musically', 'label': 'TikTok'},
        ],
        _ => null,
      };
    };
    await pump(tester);

    expect(find.text('Heute: 60 Minuten · 12 genutzt'), findsOneWidget);
    expect(find.textContaining('Variablen trennen'), findsWidgets);
    expect(find.text('Daily Quiz: noch offen'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    // Overlay fehlt noch → Knopf zum Freigeben.
    expect(
      find.descendant(of: find.byKey(const ValueKey('guard-overlay')), matching: find.text('Freigeben')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('guard-usage')), matching: find.text('Freigeben')),
      findsNothing,
    );
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('guard-overlay')), matching: find.text('Freigeben')),
    );
    expect(calls.map((c) => c.$1), contains('openOverlaySettings'));

    // Noch nicht festgelegt: alles frei einstellbar.
    await tester.tap(find.byKey(const ValueKey('guard-free-plus')));
    await tester.pumpAndSettle();
    expect(saved.freeMinutes, 35);
    expect(find.text('35 min'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guard-pick-apps')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guard-app-com.zhiliaoapp.musically')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guard-apps-done')));
    await tester.pumpAndSettle();
    expect(saved.packages, ['com.instagram.android', 'com.zhiliaoapp.musically']);
    expect(find.text('TikTok'), findsOneWidget);

    // Einschalten fragt nach: dann eine Woche festgelegt.
    await tester.tap(find.byKey(const ValueKey('guard-enabled')));
    await tester.pumpAndSettle();
    expect(find.text('Für eine Woche festlegen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(saved.enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('guard-enabled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guard-lock-confirm')));
    await tester.pumpAndSettle();
    expect(saved.enabled, isTrue);
    expect(saved.lockedUntil!.difference(DateTime.now()).inHours, inInclusiveRange(167, 168));
    final configure = calls.lastWhere((c) => c.$1 == 'configure').$2! as Map;
    expect(configure['enabled'], isTrue);
    expect(configure['packages'], ['com.instagram.android', 'com.zhiliaoapp.musically']);
    expect(configure['allowedMinutes'], 65);
    expect(configure['unlimited'], isFalse);

    // Festgelegt: nicht abschaltbar, nur strenger.
    expect(find.byKey(const ValueKey('guard-locked')), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('guard-enabled'))).onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('guard-enabled')));
    await tester.pumpAndSettle();
    expect(saved.enabled, isTrue);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('guard-free-plus'))).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('guard-per-topic-plus'))).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('guard-in-row-minus'))).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('guard-day-start-minus'))).onPressed, isNull);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('guard-daily'))).onChanged, isNull);
    expect(tester.widget<InputChip>(find.widgetWithText(InputChip, 'Instagram')).onDeleted, isNull);
    await tester.tap(find.byKey(const ValueKey('guard-free-minus')));
    await tester.pumpAndSettle();
    expect(saved.freeMinutes, 30, reason: 'strenger geht');

    await tester.tap(find.byKey(const ValueKey('guard-pick-apps')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byKey(const ValueKey('guard-app-com.instagram.android'))).onChanged,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('guard-apps-done')));
    await tester.pumpAndSettle();
    expect(saved.packages, containsAll(['com.instagram.android', 'com.zhiliaoapp.musically']));
  });

  testWidgets('ohne Android: Hinweis, dass Lernen hier mitzählt', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pump(tester);
    expect(find.byKey(const ValueKey('guard-not-android')), findsOneWidget);
    expect(find.byKey(const ValueKey('guard-enabled')), findsNothing);
    expect(find.text('Heute: 60 Minuten'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guard-per-topic-minus')));
    await tester.pumpAndSettle();
    expect(saved.minutesPerTopic, 25);
    expect(find.text('Heute: 55 Minuten'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows: Webseiten, Ausnahmen, Spiele mit Wochenzeit, gemeinsames Zeitkonto', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final now = DateTime.now();
    final day = LearnCredit.dayKey(now, 4);
    final week = LearnCredit.weekKey(now, 4);
    ScreenGuardScreen.loadHook = () async => (
      rules: saved,
      credit: LearnCredit(
        earned: {'concept:c1': EarnedTopic(day: day, title: 'Variablen trennen', at: now)},
        used: {
          'handy': {LearnCredit.dailyUsageKey(day): 20 * 60},
          'pc': {LearnCredit.gameUsageKey(week): 90 * 60},
        },
      ),
    );
    WindowsGuard.invokeHook = (method, [args]) async => switch (method) {
      'windows' => [
        {'hwnd': 7, 'exe': 'VALORANT-Win64-Shipping.exe', 'title': 'VALORANT  '},
      ],
      _ => null,
    };
    await pump(tester);

    expect(find.byKey(const ValueKey('guard-not-android')), findsNothing);
    expect(find.text('Heute: 60 Minuten · 20 genutzt'), findsOneWidget, reason: 'Handy und PC zusammen');
    expect(find.text('Spiele diese Woche: 1 h 30 min von 4 h 30 min'), findsOneWidget);
    expect(find.byKey(const ValueKey('guard-usage')), findsNothing, reason: 'Android-Berechtigungen nur am Handy');
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('YouTube Music'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('guard-pc-sites-field')), 'Twitch');
    await tester.ensureVisible(find.byKey(const ValueKey('guard-pc-sites-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guard-pc-sites-add')));
    await tester.pumpAndSettle();
    expect(saved.pcSites, ['YouTube', 'Instagram', 'Twitch']);

    await tester.ensureVisible(find.byKey(const ValueKey('guard-pc-games-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guard-pc-games-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Programm'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('guard-pc-games-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guard-pc-games-add')));
    await tester.pumpAndSettle();
    expect(saved.pcGames, ['Minecraft', 'VALORANT', 'VALORANT-Win64-Shipping.exe']);

    await tester.ensureVisible(find.byKey(const ValueKey('guard-game-week-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guard-game-week-plus')));
    await tester.pumpAndSettle();
    expect(saved.weeklyGameMinutes, 270);

    // Festlegen: dann nur strenger.
    await tester.ensureVisible(find.byKey(const ValueKey('guard-enabled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guard-enabled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guard-lock-confirm')));
    await tester.pumpAndSettle();
    expect(saved.enabled, isTrue);
    expect(tester.widget<InputChip>(find.widgetWithText(InputChip, 'Twitch')).onDeleted, isNull);
    expect(tester.widget<InputChip>(find.widgetWithText(InputChip, 'YouTube Music')).onDeleted, isNotNull);
    expect(find.byKey(const ValueKey('guard-pc-exceptions-field')), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('guard-game-week-plus'))).onPressed, isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('guard-game-week-minus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guard-game-week-minus')));
    await tester.pumpAndSettle();
    expect(saved.weeklyGameMinutes, 240);
    debugDefaultTargetPlatformOverride = null;
  });
}
