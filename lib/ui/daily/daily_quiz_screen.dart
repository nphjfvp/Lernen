import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/daily_scheduler_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/question_parsing.dart';
import '../../theme/app_colors.dart';
import 'question_answer_view.dart';

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
      _reviewedCount = 0;
    });
  }

  Future<void> _handleComplete(Flashcard card, {Grade? selfGrade, bool? isCorrect}) async {
    final grade = selfGrade ?? _fsrs.gradeFromResult(isCorrect!);
    var updated = _fsrs.review(card, grade);

    if (isCorrect != null && updated.variantChain != null) {
      final boxResult = updated.copyWithBoxUpdate(isCorrect: isCorrect);
      updated = boxResult.card;
      await context.read<FlashcardRepository>().update(updated);
      final nextType = boxResult.nextType;
      if (nextType != null) {
        unawaited(_promoteInBackground(updated, nextType));
      }
    } else {
      await context.read<FlashcardRepository>().update(updated);
    }

    if (!mounted) return;
    setState(() {
      _index += 1;
      _reviewedCount += 1;
    });
  }

  /// Erzeugt lazy die nächste (schwerere) Eskalationsstufe per KI und
  /// speichert sie – läuft bewusst im Hintergrund weiter, auch nachdem die
  /// Session zur nächsten Frage übergegangen ist: schlägt es fehl oder ist
  /// kein API-Key hinterlegt, bleibt die Frage einfach auf ihrer aktuellen
  /// Stufe (nächster richtiger Versuch probiert die Beförderung erneut).
  Future<void> _promoteInBackground(Flashcard card, QuestionType nextType) async {
    try {
      final settings = context.read<SettingsRepository>().settings;
      if (!settings.hasApiKey) return;
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final result = await ai.generateHarderVariant(
        questionText: card.front,
        currentAnswer: card.answerSummary,
        targetType: nextType,
      );
      final promoted = card.copyWithPromotedVariant(
        newType: nextType,
        front: (result['front'] ?? card.front).toString(),
        back: (result['back'] ?? '').toString(),
        options: QuestionParsing.parseOptions(result['options']),
        correctText: result['correctText'] as String?,
        blanks: QuestionParsing.parseBlanks(result['blanks']),
        dragPairs: QuestionParsing.parseDragPairs(result['dragPairs']),
      );
      if (!mounted) return;
      await context.read<FlashcardRepository>().update(promoted);
    } catch (_) {
      // Stille Behandlung, siehe Doc-Kommentar oben.
    }
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
                        key: ValueKey(plan.allCards[_index].id),
                        card: plan.allCards[_index],
                        moduleName: context.read<ModuleRepository>().byId(plan.allCards[_index].moduleId)?.name ?? '',
                        progress: (_index + 1) / plan.total,
                        total: plan.total,
                        position: _index + 1,
                        isNew: plan.newCards.contains(plan.allCards[_index]),
                        onComplete: ({selfGrade, isCorrect}) => _handleComplete(
                          plan.allCards[_index],
                          selfGrade: selfGrade,
                          isCorrect: isCorrect,
                        ),
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
    super.key,
    required this.card,
    required this.moduleName,
    required this.progress,
    required this.total,
    required this.position,
    required this.isNew,
    required this.onComplete,
  });

  final Flashcard card;
  final String moduleName;
  final double progress;
  final int total;
  final int position;
  final bool isNew;
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;

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
          child: QuestionAnswerView(
            key: ValueKey(card.id),
            card: card,
            isNew: isNew,
            onComplete: onComplete,
          ),
        ),
      ],
    );
  }
}
