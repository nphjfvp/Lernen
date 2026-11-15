import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/learn_credit.dart';
import 'package:lernen/services/windows_guard.dart';

PcWindow _w(String exe, String title, {int hwnd = 1, bool self = false}) =>
    PcWindow(hwnd: hwnd, exe: exe, title: title, self: self);

void main() {
  group('Erkennung', () {
    const rules = LearnCreditRules(enabled: true);

    test('Webseiten im Browser am Tab-Titel, Spiele außerhalb, Ausnahmen nie', () {
      expect(classifyPcWindow(_w('chrome.exe', 'Lofi Mix - YouTube - Google Chrome'), rules), PcGroup.daily);
      expect(classifyPcWindow(_w('msedge.exe', 'Instagram'), rules), PcGroup.daily);
      expect(classifyPcWindow(_w('firefox.exe', 'YouTube Music'), rules), isNull, reason: 'Ausnahme');
      expect(classifyPcWindow(_w('chrome.exe', 'Minecraft Wiki'), rules), isNull, reason: 'Spiele nicht im Browser');
      expect(classifyPcWindow(_w('javaw.exe', 'Minecraft* 1.21.1 - Einzelspieler'), rules), PcGroup.game);
      expect(classifyPcWindow(_w('Minecraft.Windows.exe', 'Minecraft'), rules), PcGroup.game);
      expect(classifyPcWindow(_w('MinecraftLauncher.exe', 'Minecraft Launcher'), rules), isNull);
      expect(classifyPcWindow(_w('VALORANT-Win64-Shipping.exe', 'VALORANT  '), rules), PcGroup.game);
      expect(classifyPcWindow(_w('explorer.exe', 'YouTube-Downloads'), rules), isNull, reason: 'kein Browser');
      expect(classifyPcWindow(_w('lernen.exe', 'YouTube', self: true), rules), isNull);
      final exe = rules.copyWith(pcGames: ['Steam.exe']);
      expect(classifyPcWindow(_w('steam.exe', 'Bibliothek'), exe), PcGroup.game);
      expect(classifyPcWindow(_w('code.exe', 'steam.exe – Notizen'), exe), isNull, reason: '.exe nur als Programm');
    });
  });

  group('Wächter', () {
    late List<(String, Object?)> calls;
    late Map<String, ({int seconds, bool urgent})> persisted;
    late PcWindow? front;
    var pulls = 0;
    final guard = WindowsGuard.instance;
    final t0 = DateTime(2026, 11, 16, 18); // Montag
    final day = LearnCredit.dayKey(t0, 4);
    final week = LearnCredit.weekKey(t0, 4);

    setUp(() {
      calls = [];
      persisted = {};
      front = null;
      pulls = 0;
      WindowsGuard.autoTick = false;
      WindowsGuard.invokeHook = (method, [args]) async {
        calls.add((method, args));
        if (method == 'foreground') {
          final w = front;
          return w == null ? null : {'hwnd': w.hwnd, 'exe': w.exe, 'title': w.title, 'self': w.self};
        }
        return null;
      };
      WindowsGuard.persistHook = (key, seconds, {required urgent}) async =>
          persisted[key] = (seconds: seconds, urgent: urgent);
      WindowsGuard.pullCloud = () async => pulls++;
    });

    tearDown(() {
      guard.stop();
      WindowsGuard.invokeHook = null;
      WindowsGuard.persistHook = null;
      WindowsGuard.pullCloud = null;
      WindowsGuard.autoTick = true;
    });

    List<String> methods() => [for (final c in calls) c.$1];

    Future<DateTime> run(DateTime from, int seconds, {int step = 5}) async {
      var t = from;
      for (var i = 0; i < seconds ~/ step; i++) {
        t = t.add(Duration(seconds: step));
        await guard.tick(t);
      }
      return t;
    }

    test('Tageszeit mit dem Handy geteilt: zählt nur vorn, warnt, sperrt dann', () async {
      await guard.applyState(
        const LearnCreditRules(enabled: true),
        LearnCredit(
          used: {
            'handy': {LearnCredit.dailyUsageKey(day): 25 * 60},
          },
        ),
        device: 'pc',
        now: t0,
      );
      expect(calls.first, ('setKeepRunning', true));
      expect(guard.running.value, isTrue);
      expect(guard.dailyRemaining(t0), 5 * 60, reason: '30 min frei, 25 davon am Handy');

      // YouTube nur im Hintergrund (vorn ist etwas anderes): zählt nicht.
      front = _w('code.exe', 'Lernen – Notizen');
      var t = await guard.tick(t0).then((_) => run(t0, 60));
      expect(guard.dailyRemaining(t), 5 * 60);

      // Vorn: zählt, Warnung bei 5 und bei 1 Minute.
      front = _w('chrome.exe', 'Lofi - YouTube', hwnd: 42);
      t = await run(t, 30);
      expect(calls.where((c) => c.$1 == 'notify'), hasLength(1));
      expect((calls.lastWhere((c) => c.$1 == 'notify').$2! as Map)['title'], 'Noch 5 Minuten');
      t = await run(t, 220);
      expect((calls.lastWhere((c) => c.$1 == 'notify').$2! as Map)['title'], 'Noch 1 Minute');
      expect(methods(), isNot(contains('minimize')));

      t = await run(t, 60);
      expect(methods(), containsAllInOrder(['minimize', 'bringToFront']));
      expect(calls.firstWhere((c) => c.$1 == 'minimize').$2, 42);
      final block = guard.block.value!;
      expect(block.group, PcGroup.daily);
      expect(block.allowedMinutes, 30);
      expect(block.usedMinutes, 30);
      expect(block.nextStep, contains('neues Thema'));
      expect(persisted[LearnCredit.dailyUsageKey(day)]!.urgent, isTrue, reason: 'gleich hochladen');
      // Browser werden nie geschlossen, nur minimiert.
      await run(t, 30);
      expect(methods(), isNot(contains('close')));

      // Neues Thema (z.B. am Handy gelernt) bringt +30 min.
      guard.dismissBlock();
      await guard.applyState(
        const LearnCreditRules(enabled: true),
        LearnCredit(
          earned: {'x': EarnedTopic(day: day, title: 'Substitution', at: t)},
          used: {
            'handy': {LearnCredit.dailyUsageKey(day): 25 * 60},
          },
        ),
        device: 'pc',
        now: t,
      );
      expect(guard.dailyRemaining(t), greaterThan(29 * 60));
    });

    test('Spielzeit pro Woche, Lernen bringt mehr, wieder geöffnet → geschlossen', () async {
      await guard.applyState(
        const LearnCreditRules(enabled: true, weeklyGameMinutes: 60),
        LearnCredit(
          earned: {'x': EarnedTopic(day: day, title: 'Variablen trennen', at: t0)},
          used: {
            'pc': {LearnCredit.gameUsageKey(week): 85 * 60},
          },
        ),
        device: 'pc',
        now: t0,
      );
      expect(guard.gameRemaining(t0), 5 * 60, reason: '60 min + 30 für ein Thema der Woche, 85 gespielt');
      front = _w('VALORANT-Win64-Shipping.exe', 'VALORANT', hwnd: 9);
      var t = await run(t0, 305);
      expect(guard.block.value?.group, PcGroup.game);
      expect(guard.block.value!.allowedMinutes, 90);
      expect(methods().where((m) => m == 'close'), isEmpty);

      // Noch nicht fertig minimiert (gleiche Sekunden) zählt nicht als Wiederöffnen …
      t = await run(t, 2, step: 1);
      expect(methods().where((m) => m == 'close'), isEmpty);
      // … zweimal wirklich wieder geöffnet: dann wird es geschlossen.
      t = t.add(const Duration(seconds: 10));
      await guard.tick(t);
      expect(methods().where((m) => m == 'close'), isEmpty);
      t = t.add(const Duration(seconds: 10));
      await guard.tick(t);
      expect(calls.lastWhere((c) => c.$1 == 'close').$2, 9);
    });

    test('alle 5 Minuten den Cloud-Stand holen, minütlich speichern; aus = Überwachung aus', () async {
      await guard.applyState(const LearnCreditRules(enabled: true), const LearnCredit(), device: 'pc', now: t0);
      front = _w('chrome.exe', 'YouTube');
      await guard.tick(t0);
      final t = await run(t0, 330);
      expect(pulls, 1);
      expect(persisted[LearnCredit.dailyUsageKey(day)]!.seconds, greaterThanOrEqualTo(300));
      expect(persisted[LearnCredit.dailyUsageKey(day)]!.urgent, isFalse);

      await guard.applyState(const LearnCreditRules(), const LearnCredit(), device: 'pc', now: t);
      expect(calls.last, ('setKeepRunning', false));
      expect(guard.running.value, isFalse);
    });

    test('Wochenschlüssel: Montag ab 4 Uhr', () {
      expect(LearnCredit.weekKey(DateTime(2026, 11, 16, 3, 59), 4), '2026-11-09', reason: 'noch Sonntag-Lerntag');
      expect(LearnCredit.weekKey(DateTime(2026, 11, 16, 4), 4), '2026-11-16');
      expect(LearnCredit.weekKey(DateTime(2026, 11, 22, 23), 4), '2026-11-16');
      expect(LearnCredit.weekOfDay('2026-11-22'), '2026-11-16');
    });
  });
}
