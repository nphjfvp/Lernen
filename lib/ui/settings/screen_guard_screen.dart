import 'package:flutter/material.dart';

import '../../models/learn_credit.dart';
import '../../repositories/learn_credit_repository.dart';
import '../../services/database_service.dart';
import '../../services/screen_guard.dart';
import '../../services/windows_guard.dart';
import '../../theme/app_colors.dart';
import '../widgets/safe_set_state.dart';

/// Lernzeit-Sperre einrichten: gesperrte Apps (z.B. Instagram) gibt es jeden
/// Tag (ab 4:00) eine Weile frei, jedes neu gelernte Thema bringt mehr Zeit,
/// mit neuen Themen und fertigem Daily Quiz ist sie unbegrenzt. Sperren kann
/// nur die Android-App; gelernt werden darf überall (Cloud-Abgleich).
class ScreenGuardScreen extends StatefulWidget {
  const ScreenGuardScreen({super.key});

  /// Test-Hook statt der Datenbank.
  static Future<({LearnCreditRules rules, LearnCredit credit})> Function()? loadHook;
  static Future<void> Function(LearnCreditRules rules)? saveHook;

  @override
  State<ScreenGuardScreen> createState() => _ScreenGuardScreenState();
}

class _ScreenGuardScreenState extends State<ScreenGuardScreen> with SafeSetState<ScreenGuardScreen> {
  LearnCreditRules? _rules;
  LearnCredit _credit = const LearnCredit();
  ({bool usageAccess, bool overlay, bool running})? _status;
  int? _used;
  String _device = '';
  Map<String, String> _labels = {};
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(onResume: _load);

  @override
  void initState() {
    super.initState();
    _lifecycle;
    LearnCreditRepository.changes.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    LearnCreditRepository.changes.removeListener(_load);
    super.dispose();
  }

  bool get _android => ScreenGuard.available;
  bool get _windows => !_android && WindowsGuard.available;

  Future<void> _load() async {
    final LearnCreditRules rules;
    final LearnCredit credit;
    final hook = ScreenGuardScreen.loadHook;
    if (hook != null) {
      final loaded = await hook();
      rules = loaded.rules;
      credit = loaded.credit;
    } else {
      final db = await DatabaseService.instance.database;
      rules = await LearnCreditRepository.loadRulesFrom(db);
      credit = await LearnCreditRepository.loadFrom(db);
      _device = await LearnCreditRepository.deviceIdIn(db);
    }
    final status = _android ? await ScreenGuard.status() : null;
    final used = _android ? await ScreenGuard.usedMinutes(rules.packages, rules.dayStartHour) : null;
    setState(() {
      _rules = rules;
      _credit = credit;
      _status = status;
      _used = used;
    });
    if (_android && _labels.isEmpty) {
      final apps = await ScreenGuard.installedApps();
      setState(() => _labels = {for (final a in apps) a.package: a.label});
    }
  }

  Future<void> _save(LearnCreditRules changed) async {
    final now = DateTime.now();
    // Eine festgelegte Sperre wird nur strenger (die Datenbank prüft es noch einmal).
    var rules = (_rules ?? const LearnCreditRules()).guard(changed.copyWith(updatedAt: now), now);
    setState(() => _rules = rules);
    final hook = ScreenGuardScreen.saveHook;
    if (hook != null) {
      await hook(rules);
      await ScreenGuard.pushWith(rules, LearnAllowance.of(_credit, rules, now));
    } else {
      final db = await DatabaseService.instance.database;
      rules = await LearnCreditRepository.saveRulesIn(db, rules, now: now);
      setState(() => _rules = rules);
      await ScreenGuard.push();
    }
    final status = _android ? await ScreenGuard.status() : null;
    setState(() => _status = status);
  }

  /// Einschalten bzw. erneut festlegen – vorher einmal bestätigen lassen.
  Future<void> _lock(LearnCreditRules rules) async {
    final until = DateTime.now().add(LearnCreditRules.lockDuration);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Für eine Woche festlegen?'),
        content: Text(
          'Bis ${formatLockDate(until)} lässt sich die Sperre dann nicht ausschalten. Die Regeln kannst du in '
          'der Zeit nur strenger stellen: keine App entfernen, nicht mehr Minuten, keine kürzere Serie – auch '
          'nicht auf einem anderen Gerät.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            key: const ValueKey('guard-lock-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Festlegen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save(rules.copyWith(enabled: true, lockedUntil: until));
  }

  Future<void> _pickApps(LearnCreditRules rules) async {
    final apps = await ScreenGuard.installedApps();
    if (!mounted) return;
    final locked = rules.isLocked(DateTime.now());
    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _AppPicker(apps: apps, selected: rules.packages.toSet(), fixed: locked ? rules.packages.toSet() : const {}),
    );
    if (chosen == null) return;
    setState(() => _labels = {..._labels, for (final a in apps) a.package: a.label});
    await _save(rules.copyWith(packages: chosen));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rules = _rules;
    final locked = rules?.isLocked(DateTime.now()) ?? false;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Lernzeit-Sperre')),
      body: rules == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text(
                  _intro(rules, pc: _windows),
                  style: TextStyle(color: c.inkMuted, height: 1.4),
                ),
                const SizedBox(height: 14),
                _today(c, rules),
                if (locked) ...[
                  const SizedBox(height: 12),
                  Container(
                    key: const ValueKey('guard-locked'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.lock_rounded, color: c.warn),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Festgelegt bis ${formatLockDate(rules.lockedUntil!)}: bis dahin nicht abschaltbar, '
                            'die Regeln lassen sich nur strenger stellen.',
                            style: const TextStyle(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (!_android && !_windows)
                  Container(
                    key: const ValueKey('guard-not-android'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Text(
                      'Sperren können die Android- und die Windows-App. Was du hier lernst, zählt dort mit, und die '
                      'Regeln gelten auf allen Geräten – dafür muss der Cloud-Abgleich an sein (Einstellungen → '
                      'Account).',
                      style: TextStyle(height: 1.4),
                    ),
                  )
                else ...[
                  SwitchListTile(
                    key: const ValueKey('guard-enabled'),
                    contentPadding: EdgeInsets.zero,
                    value: rules.enabled,
                    // Einschalten legt die Sperre für eine Woche fest; solange geht sie nicht aus.
                    onChanged: locked ? null : (v) => v ? _lock(rules) : _save(rules.copyWith(enabled: false)),
                    title: const Text('Sperre einschalten', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      locked
                          ? 'Festgelegt bis ${formatLockDate(rules.lockedUntil!)}.'
                          : rules.enabled
                          ? (_windows
                                ? 'Läuft – Symbol im Infobereich, startet mit Windows.'
                                : _status?.running == true
                                ? 'Läuft – mit Benachrichtigung in der Statusleiste.'
                                : 'An.')
                          : 'Aus. Beim Einschalten wird sie für eine Woche festgelegt.',
                    ),
                  ),
                  if (rules.enabled && !locked)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('guard-relock'),
                        onPressed: () => _lock(rules),
                        icon: const Icon(Icons.lock_clock_outlined, size: 18),
                        label: const Text('Wieder für eine Woche festlegen'),
                      ),
                    ),
                  if (_windows) ..._pcSection(context, c, rules, locked),
                  if (_android) ...[
                    _permission(
                      c,
                      key: 'guard-usage',
                      ok: _status?.usageAccess ?? false,
                      title: 'Nutzungszugriff',
                      detail: 'Damit die App misst, wie lange die gesperrten Apps heute offen waren.',
                      onFix: ScreenGuard.openUsageSettings,
                    ),
                    _permission(
                      c,
                      key: 'guard-overlay',
                      ok: _status?.overlay ?? false,
                      title: 'Über anderen Apps einblenden',
                      detail: 'Damit der Sperrbildschirm über Instagram erscheinen kann.',
                      onFix: ScreenGuard.openOverlaySettings,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Text('Gesperrte Apps', style: Theme.of(context).textTheme.titleSmall)),
                        TextButton.icon(
                          key: const ValueKey('guard-pick-apps'),
                          onPressed: () => _pickApps(rules),
                          icon: const Icon(Icons.apps, size: 18),
                          label: const Text('Auswählen'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in rules.packages)
                          InputChip(
                            label: Text(_labels[p] ?? p),
                            onDeleted: locked
                                ? null
                                : () => _save(rules.copyWith(packages: [...rules.packages]..remove(p))),
                          ),
                        if (rules.packages.isEmpty)
                          Text('Noch keine – „Auswählen“ tippen.', style: TextStyle(color: c.inkMuted)),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 22),
                Text('Regeln', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                _stepper(
                  c,
                  key: 'guard-free',
                  label: 'Frei am Tag',
                  value: rules.freeMinutes,
                  unit: 'min',
                  step: 5,
                  max: 240,
                  canUp: !locked,
                  onChanged: (v) => _save(rules.copyWith(freeMinutes: v)),
                ),
                _stepper(
                  c,
                  key: 'guard-per-topic',
                  label: 'Je neuem Thema',
                  value: rules.minutesPerTopic,
                  unit: 'min',
                  step: 5,
                  max: 240,
                  canUp: !locked,
                  onChanged: (v) => _save(rules.copyWith(minutesPerTopic: v)),
                ),
                _stepper(
                  c,
                  key: 'guard-in-row',
                  label: 'Thema gelernt nach … fehlerfrei hintereinander',
                  value: rules.correctInRow,
                  unit: '',
                  step: 1,
                  min: 1,
                  max: 10,
                  canDown: !locked,
                  onChanged: (v) => _save(rules.copyWith(correctInRow: v)),
                ),
                _stepper(
                  c,
                  key: 'guard-unlimited',
                  label: 'Unbegrenzt ab … neuen Themen (0 = nie)',
                  value: rules.topicsForUnlimited,
                  unit: '',
                  step: 1,
                  max: 20,
                  // 0 = nie unbegrenzt ist das Strengste, sonst sind mehr Themen strenger.
                  canUp: !locked || rules.topicsForUnlimited != 0,
                  canDown: !locked || rules.topicsForUnlimited == 1,
                  onChanged: (v) => _save(rules.copyWith(topicsForUnlimited: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('guard-daily'),
                  contentPadding: EdgeInsets.zero,
                  value: rules.dailyForUnlimited,
                  onChanged: locked && rules.dailyForUnlimited
                      ? null
                      : (v) => _save(rules.copyWith(dailyForUnlimited: v)),
                  title: const Text('Für unbegrenzt auch das Daily Quiz fertig'),
                ),
                _stepper(
                  c,
                  key: 'guard-day-start',
                  label: 'Lerntag beginnt um',
                  value: rules.dayStartHour,
                  unit: 'Uhr',
                  step: 1,
                  max: 12,
                  canUp: !locked,
                  canDown: !locked,
                  onChanged: (v) => _save(rules.copyWith(dayStartHour: v)),
                ),
              ],
            ),
    );
  }

  static String _intro(LearnCreditRules r, {bool pc = false}) {
    final unlimited = r.topicsForUnlimited <= 0
        ? ''
        : ' Mit ${r.topicsForUnlimited == 1 ? 'einem neuen Thema' : '${r.topicsForUnlimited} neuen Themen'}'
              '${r.dailyForUnlimited ? ' und fertigem Daily Quiz' : ''} ist die Zeit unbegrenzt.';
    return 'Gesperrte Apps (z.B. Instagram) gibt es jeden Lerntag (ab ${r.dayStartHour}:00 Uhr) ${r.freeMinutes} '
        'Minuten frei. Jedes neu gelernte Thema bringt +${r.minutesPerTopic} Minuten – ein Thema (z.B. „Variablen '
        'trennen“ unter DGL) zählt, wenn du ${r.correctInRow} Aufgaben bzw. Fragen dazu hintereinander fehlerfrei '
        'löst.$unlimited Gelernt zählt auf jedem Gerät (über den Cloud-Abgleich)'
        '${pc ? ', die Tageszeit teilen sich Handy und PC. Spiele gibt es ${formatHours(r.weeklyGameMinutes)} pro Woche '
                  '(ab Montag ${r.dayStartHour}:00 Uhr), jedes in der Woche neu gelernte Thema bringt '
                  '+${r.gameMinutesPerTopic} Minuten dazu.' : '.'}';
  }

  Widget _today(AppColors c, LearnCreditRules rules) {
    final now = DateTime.now();
    final allowance = LearnAllowance.of(_credit, rules, now);
    final key = LearnCredit.dailyUsageKey(allowance.day);
    // Gemeinsames Zeitkonto: Handy (hier frisch gemessen) und alle anderen Geräte.
    final local = _used;
    final used = local != null
        ? local + _credit.usedSeconds(key, exceptDevice: _device) ~/ 60
        : _credit.usedSeconds(key) > 0
        ? _credit.usedSeconds(key) ~/ 60
        : null;
    final games = GameAllowance.of(_credit, rules, now);
    final gamesUsed = _credit.usedSeconds(LearnCredit.gameUsageKey(games.week)) ~/ 60;
    return Container(
      key: const ValueKey('guard-today'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: allowance.unlimited ? c.goodSoft : c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            allowance.unlimited
                ? 'Heute: unbegrenzt'
                : 'Heute: ${allowance.minutes} Minuten${used == null ? '' : ' · $used genutzt'}',
            key: const ValueKey('guard-today-title'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            allowance.topicsToday.isEmpty
                ? 'Noch kein neues Thema heute.'
                : 'Neu gelernt: ${allowance.topicsToday.join(' · ')}',
            style: const TextStyle(height: 1.4),
          ),
          Text(
            allowance.dailyDone ? 'Daily Quiz: fertig ✓' : 'Daily Quiz: noch offen',
            style: TextStyle(color: allowance.dailyDone ? c.good : c.inkMuted),
          ),
          if (allowance.nextStep.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(allowance.nextStep, style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.35)),
          ],
          if (_windows) ...[
            const SizedBox(height: 8),
            Text(
              'Spiele diese Woche: ${formatHours(gamesUsed)} von ${formatHours(games.minutes)}',
              key: const ValueKey('guard-games-week'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  /// Am PC: Webseiten (Tageszeit), Ausnahmen, Spiele (Wochenzeit).
  List<Widget> _pcSection(BuildContext context, AppColors c, LearnCreditRules rules, bool locked) => [
    const SizedBox(height: 12),
    _ListEditor(
      key: const ValueKey('guard-pc-sites'),
      title: 'Webseiten im Browser – Tageszeit (mit dem Handy geteilt)',
      hint: 'Teil des Tab-Titels, z.B. YouTube',
      help: 'Gezählt wird nur, solange der Tab vorn zu sehen ist – im Hintergrund weiterhören zählt nicht.',
      items: rules.pcSites,
      canRemove: (_) => !locked,
      canAdd: true,
      onChanged: (list) => _save(rules.copyWith(pcSites: list)),
    ),
    _ListEditor(
      key: const ValueKey('guard-pc-exceptions'),
      title: 'Ausnahmen – zählen nie',
      hint: 'Teil des Fenstertitels, z.B. YouTube Music',
      help: locked ? 'Während der Festlegung lassen sich Ausnahmen nur entfernen.' : null,
      items: rules.pcExceptions,
      canRemove: (_) => true,
      canAdd: !locked,
      onChanged: (list) => _save(rules.copyWith(pcExceptions: list)),
    ),
    _ListEditor(
      key: const ValueKey('guard-pc-games'),
      title: 'Spiele und Programme – Wochenzeit',
      hint: 'Programm (z.B. VALORANT-Win64-Shipping.exe) oder Teil des Titels',
      help: 'Erkannt am Programmnamen („.exe“) oder Fenstertitel, nie in Browsern.',
      items: rules.pcGames,
      canRemove: (_) => !locked,
      canAdd: true,
      onPick: _pickWindow,
      onChanged: (list) => _save(rules.copyWith(pcGames: list)),
    ),
    _stepper(
      c,
      key: 'guard-game-week',
      label: 'Spielzeit pro Woche',
      value: rules.weeklyGameMinutes,
      unit: '',
      display: formatHours(rules.weeklyGameMinutes),
      step: 30,
      max: 2400,
      canUp: !locked,
      onChanged: (v) => _save(rules.copyWith(weeklyGameMinutes: v)),
    ),
    _stepper(
      c,
      key: 'guard-game-topic',
      label: 'Spielzeit je neuem Thema',
      value: rules.gameMinutesPerTopic,
      unit: 'min',
      step: 5,
      max: 240,
      canUp: !locked,
      onChanged: (v) => _save(rules.copyWith(gameMinutesPerTopic: v)),
    ),
  ];

  /// Ein offenes Programm wählen – Programmname oder Fenstertitel kommt ins Feld.
  Future<String?> _pickWindow() async {
    final windows = await WindowsGuard.instance.openWindows();
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: windows.isEmpty
            ? const Center(child: Text('Keine offenen Programme gefunden – Spiel starten und noch einmal öffnen.'))
            : ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('Gerade offen – Programm oder Titel übernehmen:'),
                  ),
                  for (final w in windows)
                    ListTile(
                      key: ValueKey('guard-window-${w.exe}-${w.hwnd}'),
                      title: Text(w.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(w.exe),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          TextButton(onPressed: () => Navigator.of(context).pop(w.exe), child: const Text('Programm')),
                          TextButton(onPressed: () => Navigator.of(context).pop(w.title), child: const Text('Titel')),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _permission(
    AppColors c, {
    required String key,
    required bool ok,
    required String title,
    required String detail,
    required Future<void> Function() onFix,
  }) => ListTile(
    key: ValueKey(key),
    contentPadding: EdgeInsets.zero,
    leading: Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? c.good : c.warn),
    title: Text(title),
    subtitle: Text(detail),
    trailing: ok ? null : TextButton(onPressed: onFix, child: const Text('Freigeben')),
  );

  Widget _stepper(
    AppColors c, {
    required String key,
    required String label,
    required int value,
    required String unit,
    required int step,
    int min = 0,
    required int max,
    bool canUp = true,
    bool canDown = true,
    String? display,
    required ValueChanged<int> onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: ValueKey('$key-minus'),
          onPressed: !canDown || value - step < min ? null : () => onChanged(value - step),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 64,
          child: Text(
            display ?? (unit.isEmpty ? '$value' : '$value $unit'),
            key: ValueKey('$key-value'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          key: ValueKey('$key-plus'),
          onPressed: !canUp || value + step > max ? null : () => onChanged(value + step),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
  );
}

/// „45 min“, „4 h“, „4 h 30 min“.
String formatHours(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Eine Liste von Mustern (Chips) mit Feld zum Ergänzen.
class _ListEditor extends StatefulWidget {
  const _ListEditor({
    super.key,
    required this.title,
    required this.hint,
    this.help,
    required this.items,
    required this.canRemove,
    required this.canAdd,
    required this.onChanged,
    this.onPick,
  });

  final String title;
  final String hint;
  final String? help;
  final List<String> items;
  final bool Function(String item) canRemove;
  final bool canAdd;
  final ValueChanged<List<String>> onChanged;
  final Future<String?> Function()? onPick;

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    _controller.clear();
    if (widget.items.any((e) => e.toLowerCase() == value.toLowerCase())) return;
    widget.onChanged([...widget.items, value]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pick = widget.onPick;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
          if (widget.help != null) ...[
            const SizedBox(height: 2),
            Text(widget.help!, style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.35)),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in widget.items)
                InputChip(
                  label: Text(item),
                  onDeleted: widget.canRemove(item) ? () => widget.onChanged([...widget.items]..remove(item)) : null,
                ),
              if (widget.items.isEmpty) Text('Keine.', style: TextStyle(color: c.inkMuted)),
            ],
          ),
          if (widget.canAdd)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('${(widget.key as ValueKey?)?.value}-field'),
                      controller: _controller,
                      onSubmitted: (_) => _add(),
                      decoration: InputDecoration(hintText: widget.hint, isDense: true),
                    ),
                  ),
                  if (pick != null)
                    IconButton(
                      key: ValueKey('${(widget.key as ValueKey?)?.value}-pick'),
                      tooltip: 'Aus offenen Programmen',
                      onPressed: () async {
                        final value = await pick();
                        if (value != null && mounted) setState(() => _controller.text = value);
                      },
                      icon: const Icon(Icons.window_outlined),
                    ),
                  IconButton(
                    key: ValueKey('${(widget.key as ValueKey?)?.value}-add'),
                    tooltip: 'Hinzufügen',
                    onPressed: _add,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// „Sa 22.11. um 18:05“.
String formatLockDate(DateTime d) {
  const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  String two(int v) => v.toString().padLeft(2, '0');
  return '${days[d.weekday - 1]} ${two(d.day)}.${two(d.month)}. um ${two(d.hour)}:${two(d.minute)}';
}

class _AppPicker extends StatefulWidget {
  const _AppPicker({required this.apps, required this.selected, this.fixed = const {}});

  final List<({String package, String label})> apps;
  final Set<String> selected;

  /// Während der Festlegung: diese Apps bleiben gesperrt.
  final Set<String> fixed;

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  late final Set<String> _chosen = {...widget.selected};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final apps = [
      for (final a in widget.apps)
        if (q.isEmpty || a.label.toLowerCase().contains(q) || a.package.contains(q)) a,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              key: const ValueKey('guard-app-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'App suchen …',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final a in apps)
                  CheckboxListTile(
                    key: ValueKey('guard-app-${a.package}'),
                    value: _chosen.contains(a.package),
                    onChanged: widget.fixed.contains(a.package)
                        ? null
                        : (v) => setState(() => v == true ? _chosen.add(a.package) : _chosen.remove(a.package)),
                    title: Text(a.label),
                    subtitle: Text(a.package, style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('guard-apps-done'),
                onPressed: () => Navigator.of(context).pop(_chosen.toList()),
                child: Text('Übernehmen (${_chosen.length})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
