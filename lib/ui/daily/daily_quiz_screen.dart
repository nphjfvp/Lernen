import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/module_repository.dart';
import '../../services/daily_scheduler_service.dart';
import '../../services/fsrs_service.dart';
import '../../theme/app_colors.dart';

/// Daily Quiz / Exam-Scheduler: tägliche Lernsession über alle Fächer
/// hinweg. Fällige Wiederholungen + eine je nach Wissensstand und
/// Klausurnähe dosierte Menge neuer Karten.
class DailyQuizScreen extends StatefulWidget {
  const DailyQuizScreen({super.key});

  @override
  State<DailyQuizScreen> createState() => _DailyQuizScreenState();
}

class _DailyQuizScreenState extends State<DailyQuizScreen> {
  DailyPlan? _plan;
  int _index = 0;
  bool _showBack = false;
  int _reviewedCount = 0;
  final _fsrs = FsrsService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlan());
  }

  Future<void> _loadPlan() async {
    final modules = context.read<ModuleRepository>().modules;
    final allCards = await context.read<FlashcardRepository>().loadAll();
    final plan = DailySchedulerService().buildPlan(modules: modules, allCards: allCards);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _index = 0;
      _showBack = false;
      _reviewedCount = 0;
    });
  }

  Future<void> _grade(Grade grade) async {
    final plan = _plan!;
    final card = plan.allCards[_index];
    final updated = _fsrs.review(card, grade);
    await context.read<FlashcardRepository>().update(updated);
    setState(() {
      _index += 1;
      _showBack = false;
      _reviewedCount += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final c = context.colors;
    return Material(
      color: c.bg,
      child: SafeArea(
        child: plan == null
            ? const Center(child: CircularProgressIndicator())
            : plan.total == 0
                ? const _AllDoneView()
                : _index >= plan.total
                    ? _SessionDoneView(count: _reviewedCount, onRestart: _loadPlan)
                    : _SessionView(
                        card: plan.allCards[_index],
                        moduleName: context.read<ModuleRepository>().byId(plan.allCards[_index].moduleId)?.name ?? '',
                        progress: (_index + 1) / plan.total,
                        total: plan.total,
                        position: _index + 1,
                        isNew: plan.newCards.contains(plan.allCards[_index]),
                        showBack: _showBack,
                        onFlip: () => setState(() => _showBack = true),
                        onGrade: _grade,
                      ),
      ),
    );
  }
}

class _AllDoneView extends StatelessWidget {
  const _AllDoneView();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration_outlined, size: 56, color: c.good),
            const SizedBox(height: 16),
            Text(
              'Für heute nichts fällig!\nLege in einem Fach neue Karteikarten '
              'an (Nachbereiten-Modus) oder komm morgen wieder.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionDoneView extends StatelessWidget {
  const _SessionDoneView({required this.count, required this.onRestart});
  final int count;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: c.good),
            const SizedBox(height: 16),
            Text('Session abgeschlossen! $count Karten wiederholt.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRestart, child: const Text('Aktualisieren')),
          ],
        ),
      ),
    );
  }
}

class _SessionView extends StatelessWidget {
  const _SessionView({
    required this.card,
    required this.moduleName,
    required this.progress,
    required this.total,
    required this.position,
    required this.isNew,
    required this.showBack,
    required this.onFlip,
    required this.onGrade,
  });

  final Flashcard card;
  final String moduleName;
  final double progress;
  final int total;
  final int position;
  final bool isNew;
  final bool showBack;
  final VoidCallback onFlip;
  final void Function(Grade) onGrade;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: c.border,
                  valueColor: AlwaysStoppedAnimation(c.accent),
                ),
              ),
              const SizedBox(height: 13),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$position / $total', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                  if (moduleName.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        moduleName,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.accentOnSoft),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: showBack ? null : onFlip,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isNew)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(20)),
                          child: Text('NEU', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.warn, letterSpacing: 0.03)),
                        ),
                      if (isNew) const SizedBox(height: 16),
                      Text(
                        card.front,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.45),
                      ),
                      if (showBack) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1, color: c.border),
                        ),
                        Text(
                          card.back,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, height: 1.6, color: c.inkMuted),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        Text('Zum Umdrehen tippen', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showBack)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            child: Row(
              children: [
                Expanded(child: _GradeButton(label: 'Nochmal', fg: c.danger, bg: c.dangerSoft, onTap: () => onGrade(Grade.again))),
                const SizedBox(width: 9),
                Expanded(child: _GradeButton(label: 'Schwer', fg: c.warn, bg: c.warnSoft, onTap: () => onGrade(Grade.hard))),
                const SizedBox(width: 9),
                Expanded(child: _GradeButton(label: 'Gut', fg: c.good, bg: c.goodSoft, onTap: () => onGrade(Grade.good))),
                const SizedBox(width: 9),
                Expanded(child: _GradeButton(label: 'Leicht', fg: c.accentOnSoft, bg: c.accentSoft, onTap: () => onGrade(Grade.easy))),
              ],
            ),
          )
        else
          const SizedBox(height: 30),
      ],
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({required this.label, required this.fg, required this.bg, required this.onTap});
  final String label;
  final Color fg;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}
