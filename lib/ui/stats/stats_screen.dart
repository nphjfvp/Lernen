import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mastery_snapshot.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/mastery_snapshot_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/study_log_repository.dart';
import '../../services/mastery_service.dart';
import '../../services/mastery_trend_service.dart';
import '../../services/stats_service.dart';
import '../../services/weakness_service.dart';
import '../../theme/app_colors.dart';
import '../sprint/sprint_screen.dart';
import '../widgets/mastery_dot.dart';
import 'weakness_screen.dart';

/// Fortschritts-Übersicht: Streak, Gesamtzahl Wiederholungen, durchschnitt-
/// liche geschätzte Behaltensrate, und eine Aufschlüsselung pro Fach.
/// Komplett aus vorhandenen Daten berechnet (siehe StatsService) - kein
/// separates Tracking nötig, jede Daily-Quiz-Bewertung schreibt bereits
/// `Flashcard.lastReview`/`.stability`.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.isActive = true});

  /// Ob der Fortschritt-Tab gerade sichtbar ist (siehe RootShell).
  final bool isActive;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  OverallStats? _stats;
  MasteryTrend? _trend;
  int _weakCount = 0;
  final _snapshotRepo = MasterySnapshotRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant StatsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sonst zeigte der Tab bis zum manuellen Pull-to-Refresh den Stand vom
    // App-Start, auch nachdem im Daily Quiz längst weitergelernt wurde.
    if (widget.isActive && !oldWidget.isActive) _load();
  }

  Future<void> _load() async {
    final modules = context.read<ModuleRepository>().modules;
    final allCards = await context.read<FlashcardRepository>().loadAll();
    final studyDays = await StudyLogRepository().loadDays();
    if (!mounted) return;
    final stats = StatsService().compute(modules: modules, allCards: allCards, studyDays: studyDays);

    // Ampel-Trend ("mehr Grün als letzte Woche"): einmal täglich einen
    // Schnappschuss der aktuellen Ampel-Aufschlüsselung + Behaltensrate
    // sichern (überschreibt bei mehrfachem Aufruf am selben Tag denselben
    // Eintrag), dann mit dem Stand von vor ~7 Tagen vergleichen.
    final breakdown = MasteryService().breakdown(allCards);
    final today = MasterySnapshot(
      date: DateTime.now(),
      red: breakdown[MasteryLevel.red] ?? 0,
      yellow: breakdown[MasteryLevel.yellow] ?? 0,
      green: breakdown[MasteryLevel.green] ?? 0,
      neu: breakdown[MasteryLevel.neu] ?? 0,
      averageRetrievability: stats.averageRetrievability,
    );
    await _snapshotRepo.recordToday(today);
    final history = await _snapshotRepo.loadRecent(14);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _trend = MasteryTrendService.compare(today: today, history: history);
      _weakCount = WeaknessService().rank(allCards).length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stats = _stats;

    return Material(
      color: c.bg,
      child: SafeArea(
        child: stats == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
                  children: [
                    Text(
                      'Fortschritt',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.local_fire_department_rounded,
                            value: '${stats.streakDays}',
                            label: stats.streakDays == 1 ? 'Tag Streak' : 'Tage Streak',
                            fg: c.warn,
                            bg: c.warnSoft,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.style_outlined,
                            value: '${stats.totalReviews}',
                            label: 'Wiederholungen',
                            fg: c.accentOnSoft,
                            bg: c.accentSoft,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _StatCard(
                      icon: Icons.psychology_outlined,
                      value: stats.averageRetrievability == null
                          ? '–'
                          : '${(stats.averageRetrievability! * 100).round()}%',
                      label: 'Ø geschätzte Behaltensrate',
                      fg: c.good,
                      bg: c.goodSoft,
                      wide: true,
                    ),
                    if (_trend != null) ...[
                      const SizedBox(height: 10),
                      _TrendCard(trend: _trend!),
                    ],
                    const SizedBox(height: 10),
                    _WeaknessEntryCard(
                      count: _weakCount,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const WeaknessScreen()),
                        );
                        if (mounted) await _load();
                      },
                    ),
                    const SizedBox(height: 10),
                    _SprintEntryCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SprintScreen()),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'PRO FACH',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.04, color: c.inkMuted),
                    ),
                    const SizedBox(height: 10),
                    if (stats.moduleStats.isEmpty)
                      Text('Noch keine Fächer angelegt.', style: TextStyle(color: c.inkMuted))
                    else
                      ...stats.moduleStats.map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ModuleStatsRow(stats: m),
                          )),
                  ],
                ),
              ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.fg,
    required this.bg,
    this.wide = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color fg;
  final Color bg;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: fg)),
              Text(label, style: TextStyle(fontSize: 12, color: context.colors.inkMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Vergleicht den heutigen Stand mit dem Schnappschuss von vor ~7 Tagen
/// (siehe MasteryTrendService) – Kompetenz-Feedback gegen den EIGENEN
/// früheren Stand statt Fremdvergleich/Leaderboard (Selbstbestimmungstheorie).
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend});
  final MasteryTrend trend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final retrievability = trend.retrievabilityDelta;
    final greenShare = trend.greenShareDelta;
    if (retrievability == null && greenShare == null) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.trending_up_rounded, color: c.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gegenüber vor ${trend.daysAgo} Tagen', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                  const SizedBox(height: 4),
                  if (retrievability != null) _TrendLine(c: c, label: 'Behaltensrate', delta: retrievability),
                  if (greenShare != null) _TrendLine(c: c, label: 'Grün-Anteil', delta: greenShare),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendLine extends StatelessWidget {
  const _TrendLine({required this.c, required this.label, required this.delta});
  final AppColors c;
  final String label;
  final double delta;

  @override
  Widget build(BuildContext context) {
    final rounded = (delta * 100).round();
    final color = rounded > 0 ? c.good : (rounded < 0 ? c.danger : c.inkMuted);
    final sign = rounded > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$label: $sign$rounded Prozentpunkte',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// Einstieg ins Fehlertagebuch (siehe WeaknessScreen).
class _WeaknessEntryCard extends StatelessWidget {
  const _WeaknessEntryCard({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.report_gmailerrorred_rounded, color: c.danger, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Schwachstellen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
                    const SizedBox(height: 2),
                    Text(
                      count == 0
                          ? 'Aktuell keine – gut so!'
                          : '$count Karte${count == 1 ? '' : 'n'} gezielt wiederholen',
                      style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Einstieg in den Sprint-Pausenmodus (siehe SprintScreen) – bewusst hier
/// im Fortschritts-Tab statt neben Vorbereiten/Nachbereiten/Daily Quiz, um
/// es klar vom Kernlernkreislauf abzugrenzen: eine optionale Auflockerung,
/// kein Ersatz dafür.
class _SprintEntryCard extends StatelessWidget {
  const _SprintEntryCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.bolt_rounded, color: c.warn, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sprint (Pause)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
                    const SizedBox(height: 2),
                    Text('60 Sekunden gegen deine schwächsten Karten – zur Auflockerung',
                        style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleStatsRow extends StatelessWidget {
  const _ModuleStatsRow({required this.stats});
  final ModuleStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = stats.module.daysUntilExam;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(stats.module.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
                if (days != null)
                  Text('Klausur in $days Tagen', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _MiniStat(value: '${stats.totalCards}', label: 'Karten gesamt')),
                Expanded(child: _MiniStat(value: '${stats.newCards}', label: 'neu')),
                Expanded(
                  child: _MiniStat(
                    value: stats.averageRetrievability == null
                        ? '–'
                        : '${(stats.averageRetrievability! * 100).round()}%',
                    label: 'Behaltensrate',
                  ),
                ),
              ],
            ),
            if ([MasteryLevel.red, MasteryLevel.yellow, MasteryLevel.green]
                .any((l) => (stats.masteryBreakdown[l] ?? 0) > 0)) ...[
              const SizedBox(height: 10),
              Row(
                children: [MasteryLevel.red, MasteryLevel.yellow, MasteryLevel.green]
                    .map((level) => Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MasteryDot(level: level, size: 8),
                              const SizedBox(width: 5),
                              Text('${stats.masteryBreakdown[level] ?? 0}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        Text(label, style: TextStyle(fontSize: 10.5, color: c.inkMuted)),
      ],
    );
  }
}
