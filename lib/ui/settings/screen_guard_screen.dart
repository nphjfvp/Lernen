import 'package:flutter/material.dart';

import '../../models/learn_credit.dart';
import '../../repositories/learn_credit_repository.dart';
import '../../services/database_service.dart';
import '../../services/screen_guard.dart';
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
    final rules = changed.copyWith(updatedAt: DateTime.now());
    setState(() => _rules = rules);
    final hook = ScreenGuardScreen.saveHook;
    if (hook != null) {
      await hook(rules);
    } else {
      final db = await DatabaseService.instance.database;
      await LearnCreditRepository.saveRulesIn(db, rules);
    }
    await ScreenGuard.pushWith(rules, LearnAllowance.of(_credit, rules, DateTime.now()));
    final status = _android ? await ScreenGuard.status() : null;
    setState(() => _status = status);
  }

  Future<void> _pickApps(LearnCreditRules rules) async {
    final apps = await ScreenGuard.installedApps();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AppPicker(apps: apps, selected: rules.packages.toSet()),
    );
    if (chosen == null) return;
    setState(() => _labels = {..._labels, for (final a in apps) a.package: a.label});
    await _save(rules.copyWith(packages: chosen));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rules = _rules;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Lernzeit-Sperre')),
      body: rules == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text(_intro(rules), style: TextStyle(color: c.inkMuted, height: 1.4)),
                const SizedBox(height: 14),
                _today(c, rules),
                const SizedBox(height: 20),
                if (!_android)
                  Container(
                    key: const ValueKey('guard-not-android'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Text(
                      'Sperren kann nur die Android-App. Was du hier lernst, zählt dort mit, und die Regeln '
                      'gelten auf allen Geräten – dafür muss der Cloud-Abgleich an sein (Einstellungen → Account).',
                      style: TextStyle(height: 1.4),
                    ),
                  )
                else ...[
                  SwitchListTile(
                    key: const ValueKey('guard-enabled'),
                    contentPadding: EdgeInsets.zero,
                    value: rules.enabled,
                    onChanged: (v) => _save(rules.copyWith(enabled: v)),
                    title: const Text('Sperre einschalten', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _status?.running == true ? 'Läuft – mit Benachrichtigung in der Statusleiste.' : 'Aus.',
                    ),
                  ),
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
                          onDeleted: () => _save(rules.copyWith(packages: [...rules.packages]..remove(p))),
                        ),
                      if (rules.packages.isEmpty)
                        Text('Noch keine – „Auswählen“ tippen.', style: TextStyle(color: c.inkMuted)),
                    ],
                  ),
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
                  onChanged: (v) => _save(rules.copyWith(topicsForUnlimited: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('guard-daily'),
                  contentPadding: EdgeInsets.zero,
                  value: rules.dailyForUnlimited,
                  onChanged: (v) => _save(rules.copyWith(dailyForUnlimited: v)),
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
                  onChanged: (v) => _save(rules.copyWith(dayStartHour: v)),
                ),
              ],
            ),
    );
  }

  static String _intro(LearnCreditRules r) {
    final unlimited = r.topicsForUnlimited <= 0
        ? ''
        : ' Mit ${r.topicsForUnlimited == 1 ? 'einem neuen Thema' : '${r.topicsForUnlimited} neuen Themen'}'
              '${r.dailyForUnlimited ? ' und fertigem Daily Quiz' : ''} ist die Zeit unbegrenzt.';
    return 'Gesperrte Apps (z.B. Instagram) gibt es jeden Lerntag (ab ${r.dayStartHour}:00 Uhr) ${r.freeMinutes} '
        'Minuten frei. Jedes neu gelernte Thema bringt +${r.minutesPerTopic} Minuten – ein Thema (z.B. „Variablen '
        'trennen“ unter DGL) zählt, wenn du ${r.correctInRow} Aufgaben bzw. Fragen dazu hintereinander fehlerfrei '
        'löst.$unlimited Gelernt zählt auf jedem Gerät (über den Cloud-Abgleich).';
  }

  Widget _today(AppColors c, LearnCreditRules rules) {
    final allowance = LearnAllowance.of(_credit, rules, DateTime.now());
    final used = _used;
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
        ],
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
    required ValueChanged<int> onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: ValueKey('$key-minus'),
          onPressed: value - step < min ? null : () => onChanged(value - step),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 64,
          child: Text(
            unit.isEmpty ? '$value' : '$value $unit',
            key: ValueKey('$key-value'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          key: ValueKey('$key-plus'),
          onPressed: value + step > max ? null : () => onChanged(value + step),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
  );
}

class _AppPicker extends StatefulWidget {
  const _AppPicker({required this.apps, required this.selected});

  final List<({String package, String label})> apps;
  final Set<String> selected;

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
                    onChanged: (v) => setState(() => v == true ? _chosen.add(a.package) : _chosen.remove(a.package)),
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
