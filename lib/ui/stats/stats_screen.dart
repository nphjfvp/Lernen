import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repositories/flashcard_repository.dart';
import '../../repositories/module_repository.dart';
import '../../services/mastery_service.dart';
import '../../services/stats_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/mastery_dot.dart';

/// Fortschritts-Übersicht: Streak, Gesamtzahl Wiederholungen, durchschnitt-
/// liche geschätzte Behaltensrate, und eine Aufschlüsselung pro Fach.
/// Komplett aus vorhandenen Daten berechnet (siehe StatsService) - kein
/// separates Tracking nötig, jede Daily-Quiz-Bewertung schreibt bereits
/// `Flashcard.lastReview`/`.stability`.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  OverallStats? _stats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final modules = context.read<ModuleRepository>().modules;
    final allCards = await context.read<FlashcardRepository>().loadAll();
    if (!mounted) return;
    setState(() {
      _stats = StatsService().compute(modules: modules, allCards: allCards);
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
