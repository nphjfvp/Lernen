import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/module_repository.dart';
import '../../services/daily_scheduler_service.dart';
import '../../services/fsrs_service.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Quiz')),
      body: plan == null
          ? const Center(child: CircularProgressIndicator())
          : plan.total == 0
              ? const _AllDoneView()
              : _index >= plan.total
                  ? _SessionDoneView(count: _reviewedCount, onRestart: _loadPlan)
                  : _SessionView(
                      card: plan.allCards[_index],
                      progress: _index / plan.total,
                      total: plan.total,
                      position: _index + 1,
                      isNew: plan.newCards.contains(plan.allCards[_index]),
                      showBack: _showBack,
                      onFlip: () => setState(() => _showBack = true),
                      onGrade: _grade,
                    ),
    );
  }
}

class _AllDoneView extends StatelessWidget {
  const _AllDoneView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration_outlined, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Für heute nichts fällig!\nLege in einem Fach neue Karteikarten '
              'an (Nachbereiten-Modus) oder komm morgen wieder.',
              textAlign: TextAlign.center,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
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
    required this.progress,
    required this.total,
    required this.position,
    required this.isNew,
    required this.showBack,
    required this.onFlip,
    required this.onGrade,
  });

  final Flashcard card;
  final double progress;
  final int total;
  final int position;
  final bool isNew;
  final bool showBack;
  final VoidCallback onFlip;
  final void Function(Grade) onGrade;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$position / $total'),
              if (isNew)
                const Chip(label: Text('Neu'), visualDensity: VisualDensity.compact),
            ],
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: showBack ? null : onFlip,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: double.infinity),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(card.front, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                          if (showBack) ...[
                            const Divider(height: 32),
                            Text(card.back, textAlign: TextAlign.center),
                          ] else ...[
                            const SizedBox(height: 16),
                            Text('Zum Umdrehen tippen', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showBack)
            Row(
              children: [
                Expanded(child: _GradeButton(label: 'Nochmal', color: Colors.red, onTap: () => onGrade(Grade.again))),
                const SizedBox(width: 8),
                Expanded(child: _GradeButton(label: 'Schwer', color: Colors.orange, onTap: () => onGrade(Grade.hard))),
                const SizedBox(width: 8),
                Expanded(child: _GradeButton(label: 'Gut', color: Colors.green, onTap: () => onGrade(Grade.good))),
                const SizedBox(width: 8),
                Expanded(child: _GradeButton(label: 'Leicht', color: Colors.blue, onTap: () => onGrade(Grade.easy))),
              ],
            ),
        ],
      ),
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: color),
      onPressed: onTap,
      child: Text(label),
    );
  }
}
