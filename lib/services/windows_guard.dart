import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/learn_credit.dart';
import '../repositories/learn_credit_repository.dart';
import 'auto_sync_service.dart';
import 'database_service.dart';

/// Ein Fenster am PC (vom Windows-Teil der App, windows/runner/flutter_window.cpp).
class PcWindow {
  const PcWindow({required this.hwnd, required this.exe, required this.title, this.self = false});

  final int hwnd;

  /// Programmname, z.B. `chrome.exe`.
  final String exe;
  final String title;

  /// Das Fenster der Lern-App selbst.
  final bool self;

  static PcWindow? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final hwnd = raw['hwnd'];
    return PcWindow(
      hwnd: hwnd is int ? hwnd : 0,
      exe: '${raw['exe'] ?? ''}',
      title: '${raw['title'] ?? ''}',
      self: raw['self'] == true,
    );
  }
}

/// Wozu ein Fenster zählt: Tageszeit (Webseiten, mit dem Handy geteilt) oder
/// Spielzeit der Woche.
enum PcGroup { daily, game }

/// Browser, in denen [LearnCreditRules.pcSites] am Tab-Titel erkannt werden.
const pcBrowsers = {
  'chrome.exe',
  'msedge.exe',
  'firefox.exe',
  'brave.exe',
  'opera.exe',
  'vivaldi.exe',
  'arc.exe',
  'librewolf.exe',
  'waterfox.exe',
  'floorp.exe',
  'zen.exe',
  'chromium.exe',
  'iexplore.exe',
};

/// Wozu zählt das Fenster [w] nach [rules]? Webseiten nur in Browsern (am
/// Titel des aktiven Tabs), Spiele nur außerhalb von Browsern (Programmname
/// mit „.exe“ oder Teil des Fenstertitels); Ausnahmen zählen nie.
PcGroup? classifyPcWindow(PcWindow w, LearnCreditRules rules) {
  if (w.self) return null;
  final exe = w.exe.toLowerCase();
  final title = w.title.toLowerCase();
  bool inTitle(String pattern) {
    final p = pattern.trim().toLowerCase();
    return p.isNotEmpty && title.contains(p);
  }

  if (rules.pcExceptions.any(inTitle)) return null;
  if (pcBrowsers.contains(exe)) return rules.pcSites.any(inTitle) ? PcGroup.daily : null;
  for (final game in rules.pcGames) {
    final p = game.trim().toLowerCase();
    if (p.isEmpty) continue;
    if (p.endsWith('.exe') ? exe == p : title.contains(p)) return PcGroup.game;
  }
  return null;
}

/// Was der Sperrbildschirm am PC zeigt.
class PcBlock {
  const PcBlock({
    required this.group,
    required this.what,
    required this.usedMinutes,
    required this.allowedMinutes,
    required this.nextStep,
  });

  final PcGroup group;

  /// Was gesperrt wurde (Fenstertitel).
  final String what;
  final int usedMinutes;
  final int allowedMinutes;
  final String nextStep;
}

/// Lernzeit-Sperre am PC: schaut jede Sekunde, welches Fenster vorn ist,
/// zählt die Zeit (Webseiten zur Tageszeit, die sich Handy und PC teilen;
/// Spiele zur Wochenzeit), warnt kurz vor Ablauf und sperrt danach: Fenster
/// minimieren, die Lern-App mit Sperrbildschirm nach vorn (wird ein Spiel
/// trotzdem immer wieder geöffnet, wird es geschlossen). Im Hintergrund
/// laufendes (z.B. Musik von YouTube) zählt nicht – nur was vorn zu sehen ist.
class WindowsGuard {
  WindowsGuard._();

  static final instance = WindowsGuard._();

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Gibt es die Sperre hier (Windows-App – oder ein Test-Hook)?
  static bool get available => supported || invokeHook != null;

  static const _channel = MethodChannel('lernen/windows_guard');

  /// Test-Hook statt des Windows-Kanals.
  @visibleForTesting
  static Future<Object?> Function(String method, [Object? arguments])? invokeHook;

  /// Holt den Cloud-Stand (auf dem Handy genutzte Zeit, dort gelernte
  /// Themen) – setzt main.dart (Auto-Sync).
  static Future<void> Function()? pullCloud;

  /// Per Autostart unsichtbar gestartet (`--minimized`, setzt main.dart).
  static bool startedHidden = false;

  /// Merkt sich den Auto-Sync für [pullCloud] und gibt ihn zurück.
  static AutoSyncService pullCloudFrom(AutoSyncService sync) {
    pullCloud = sync.checkCloud;
    return sync;
  }

  /// Speichern der Nutzung – Test-Hook statt der Datenbank.
  @visibleForTesting
  static Future<void> Function(String key, int seconds, {required bool urgent})? persistHook;

  /// Im Test läuft kein Takt – dort ruft der Test [tick] selbst auf.
  @visibleForTesting
  static bool autoTick = true;

  /// Warnungen so viele Minuten vor Ablauf (aufsteigend).
  static const dailyWarnings = [1, 5];
  static const gameWarnings = [1, 5, 15];

  /// So oft wird ein Spiel trotz Sperre wieder geöffnet, bevor es geschlossen wird.
  static const closeAfterReopen = 3;

  /// Die gerade gezeigte Sperre (null = keine).
  final block = ValueNotifier<PcBlock?>(null);

  /// Läuft die Sperre auf diesem PC?
  final running = ValueNotifier<bool>(false);

  LearnCreditRules _rules = const LearnCreditRules();
  LearnCredit _credit = const LearnCredit();
  String _device = '';
  bool _loaded = false;
  bool _keepRunning = false;
  Timer? _timer;
  DateTime? _lastTick;
  DateTime? _lastPersist;
  DateTime? _lastPull;

  /// Eigene, noch nicht (ganz) gespeicherte Sekunden für den Tag bzw. die Woche.
  String _dayKey = '';
  String _weekKey = '';
  int _daySeconds = 0;
  int _gameSeconds = 0;
  final _warned = <String>{};
  final _reopened = <int, int>{};
  final _blockedAt = <int, DateTime>{};
  final _exhaustedReported = <String>{};

  static Future<Object?> _invoke(String method, [Object? arguments]) async {
    final hook = invokeHook;
    if (hook != null) return hook(method, arguments);
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Beim Start der App (nur Windows). [startedHidden]: per Autostart
  /// unsichtbar gestartet.
  Future<void> start() async {
    if (!supported && invokeHook == null) return;
    LearnCreditRepository.changes.removeListener(_onChanged);
    LearnCreditRepository.changes.addListener(_onChanged);
    await refresh();
    // Unsichtbar gestartet, aber die Sperre ist (nicht mehr) an: zeigen.
    if (startedHidden && !_rules.enabled) await _invoke('bringToFront');
  }

  void _onChanged() => unawaited(refresh());

  /// Regeln und Guthaben neu laden (nach Antworten, Abgleich, Einstellungen).
  Future<void> refresh() async {
    try {
      final db = await DatabaseService.instance.database;
      _device = await LearnCreditRepository.deviceIdIn(db);
      await applyState(
        await LearnCreditRepository.loadRulesFrom(db),
        await LearnCreditRepository.loadFrom(db),
        device: _device,
      );
    } catch (_) {
      // Die Sperre darf die App nie stören.
    }
  }

  /// Neuer Stand (auch für Tests): startet bzw. stoppt die Überwachung.
  @visibleForTesting
  Future<void> applyState(LearnCreditRules rules, LearnCredit credit, {required String device, DateTime? now}) async {
    _rules = rules;
    _credit = credit;
    _device = device;
    _loaded = true;
    _syncCounters(now ?? DateTime.now());
    final on = rules.enabled;
    if (on != _keepRunning) {
      _keepRunning = on;
      await _invoke('setKeepRunning', on);
    }
    running.value = on;
    if (on && autoTick) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => unawaited(tick(DateTime.now())));
    } else if (!on) {
      _timer?.cancel();
      _timer = null;
      block.value = null;
    }
  }

  @visibleForTesting
  void stop() {
    _timer?.cancel();
    _timer = null;
    LearnCreditRepository.changes.removeListener(_onChanged);
    _keepRunning = false;
    _loaded = false;
    _lastTick = null;
    _lastPersist = null;
    _lastPull = null;
    _dayKey = '';
    _weekKey = '';
    _daySeconds = 0;
    _gameSeconds = 0;
    _warned.clear();
    _reopened.clear();
    _blockedAt.clear();
    _exhaustedReported.clear();
    block.value = null;
    running.value = false;
  }

  /// Tages-/Wochenwechsel und gespeicherte Zahlen übernehmen (nie weniger
  /// als schon gezählt).
  void _syncCounters(DateTime now) {
    final day = LearnCredit.dayKey(now, _rules.dayStartHour);
    final week = LearnCredit.weekKey(now, _rules.dayStartHour);
    final storedDay = _credit.used[_device]?[LearnCredit.dailyUsageKey(day)] ?? 0;
    final storedWeek = _credit.used[_device]?[LearnCredit.gameUsageKey(week)] ?? 0;
    if (day != _dayKey) {
      _dayKey = day;
      _daySeconds = storedDay;
      _warned.removeWhere((w) => w.startsWith('d'));
      _reopened.clear();
      _blockedAt.clear();
    } else if (storedDay > _daySeconds) {
      _daySeconds = storedDay;
    }
    if (week != _weekKey) {
      _weekKey = week;
      _gameSeconds = storedWeek;
      _warned.removeWhere((w) => w.startsWith('g'));
    } else if (storedWeek > _gameSeconds) {
      _gameSeconds = storedWeek;
    }
  }

  /// Übrige Sekunden der Tageszeit (null = unbegrenzt), alle Geräte zusammen.
  int? dailyRemaining(DateTime now) {
    final allowance = LearnAllowance.of(_credit, _rules, now);
    if (allowance.unlimited) return null;
    final others = _credit.usedSeconds(LearnCredit.dailyUsageKey(_dayKey), exceptDevice: _device);
    return allowance.minutes * 60 - others - _daySeconds;
  }

  /// Übrige Sekunden der Spielzeit dieser Woche.
  int gameRemaining(DateTime now) {
    final allowance = GameAllowance.of(_credit, _rules, now);
    final others = _credit.usedSeconds(LearnCredit.gameUsageKey(_weekKey), exceptDevice: _device);
    return allowance.minutes * 60 - others - _gameSeconds;
  }

  /// Eine Runde: Fenster vorn prüfen, zählen, warnen, sperren, speichern.
  @visibleForTesting
  Future<void> tick(DateTime now) async {
    if (!_loaded || !_rules.enabled) return;
    _syncCounters(now);
    final last = _lastTick;
    _lastTick = now;
    // Nach Ruhezustand o.Ä. nicht die ganze Pause zählen.
    final elapsed = last == null ? 1 : now.difference(last).inSeconds.clamp(0, 5);
    final window = PcWindow.fromMap(await _invoke('foreground'));
    final group = window == null ? null : classifyPcWindow(window, _rules);
    var urgent = false;
    if (window != null && group != null) {
      if (group == PcGroup.daily) {
        _daySeconds += elapsed;
      } else {
        _gameSeconds += elapsed;
      }
      final remaining = group == PcGroup.daily ? dailyRemaining(now) : gameRemaining(now);
      if (remaining != null && remaining <= 0) {
        urgent = _exhaustedReported.add(group == PcGroup.daily ? 'd$_dayKey' : 'g$_weekKey');
        await _block(window, group, now);
      } else if (remaining != null) {
        await _warn(group, remaining);
      }
    }
    final persisted = _lastPersist;
    if (urgent || persisted == null || now.difference(persisted) >= const Duration(seconds: 60)) {
      _lastPersist = now;
      await _persist(now, urgent: urgent);
    }
    final pulled = _lastPull;
    if (pulled == null || now.difference(pulled) >= const Duration(minutes: 5)) {
      _lastPull = now;
      final pull = pullCloud;
      if (pull != null && persisted != null) unawaited(pull());
    }
  }

  Future<void> _persist(DateTime now, {bool urgent = false}) async {
    final hook = persistHook;
    if (hook != null) {
      await hook(LearnCredit.dailyUsageKey(_dayKey), _daySeconds, urgent: urgent);
      await hook(LearnCredit.gameUsageKey(_weekKey), _gameSeconds, urgent: urgent);
      return;
    }
    try {
      final db = await DatabaseService.instance.database;
      await LearnCreditRepository.recordUsageIn(
        db,
        LearnCredit.dailyUsageKey(_dayKey),
        _daySeconds,
        now: now,
        urgent: urgent,
      );
      await LearnCreditRepository.recordUsageIn(
        db,
        LearnCredit.gameUsageKey(_weekKey),
        _gameSeconds,
        now: now,
        urgent: urgent,
      );
      _credit = await LearnCreditRepository.loadFrom(db);
    } catch (_) {
      // Nächste Runde.
    }
  }

  Future<void> _warn(PcGroup group, int remainingSeconds) async {
    final minutes = group == PcGroup.daily ? dailyWarnings : gameWarnings;
    final prefix = group == PcGroup.daily ? 'd' : 'g';
    // Die kleinste erreichte Schwelle zählt; größere gelten damit als gewarnt.
    for (final m in minutes) {
      if (remainingSeconds > m * 60) continue;
      if (!_warned.add('$prefix$m')) return;
      for (final bigger in minutes.where((b) => b > m)) {
        _warned.add('$prefix$bigger');
      }
      final left = (remainingSeconds / 60).ceil();
      final what = group == PcGroup.daily ? 'Webseiten-Zeit heute' : 'Spielzeit diese Woche';
      await _invoke('notify', {
        'title': 'Noch $left ${left == 1 ? 'Minute' : 'Minuten'}',
        'body': '$what – danach sperrt die Lern-App. Lernen bringt mehr Zeit.',
      });
      return;
    }
  }

  Future<void> _block(PcWindow window, PcGroup group, DateTime now) async {
    await _invoke('minimize', window.hwnd);
    // Wieder geöffnet (nicht nur noch nicht fertig minimiert)? Dann zählt es.
    final last = _blockedAt[window.hwnd];
    final fresh = last == null || now.difference(last) > const Duration(seconds: 3);
    _blockedAt[window.hwnd] = now;
    if (!fresh) return;
    final reopened = (_reopened[window.hwnd] ?? 0) + 1;
    _reopened[window.hwnd] = reopened;
    if (group == PcGroup.game && reopened >= closeAfterReopen) {
      await _invoke('close', window.hwnd);
    }
    final PcBlock info;
    if (group == PcGroup.daily) {
      final allowance = LearnAllowance.of(_credit, _rules, now);
      final used = (_credit.usedSeconds(LearnCredit.dailyUsageKey(_dayKey), exceptDevice: _device) + _daySeconds) ~/ 60;
      info = PcBlock(
        group: group,
        what: window.title,
        usedMinutes: used,
        allowedMinutes: allowance.minutes,
        nextStep: allowance.nextStep,
      );
    } else {
      final allowance = GameAllowance.of(_credit, _rules, now);
      final used =
          (_credit.usedSeconds(LearnCredit.gameUsageKey(_weekKey), exceptDevice: _device) + _gameSeconds) ~/ 60;
      info = PcBlock(
        group: group,
        what: window.title,
        usedMinutes: used,
        allowedMinutes: allowance.minutes,
        nextStep: _rules.gameMinutesPerTopic > 0
            ? 'Lerne ein neues Thema (${_rules.correctInRow} Aufgaben bzw. Fragen dazu hintereinander fehlerfrei) '
                  'für +${_rules.gameMinutesPerTopic} Minuten Spielzeit.'
            : 'Neue Spielzeit gibt es am Montag ab ${_rules.dayStartHour}:00 Uhr.',
      );
    }
    block.value = info;
    await _invoke('bringToFront');
  }

  /// Programme mit sichtbarem Fenster (für die Auswahl der Spiele).
  Future<List<PcWindow>> openWindows() async {
    final raw = await _invoke('windows');
    final list = [for (final w in raw is List ? raw : const []) ?PcWindow.fromMap(w)];
    list.sort((a, b) => a.exe.toLowerCase().compareTo(b.exe.toLowerCase()));
    return list;
  }

  /// Sperrbildschirm schließen (die Lern-App bleibt offen).
  void dismissBlock() => block.value = null;

  /// Die Lern-App ausblenden (läuft im Infobereich weiter).
  Future<void> hideApp() async {
    block.value = null;
    await _invoke('hideSelf');
  }
}
