import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/mastery_service.dart';
import '../../services/question_parsing.dart';
import '../../theme/app_colors.dart';
import '../daily/question_answer_view.dart';
import '../widgets/mastery_dot.dart';

enum _Filter { all, red, yellow, green, neu }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'Alle',
        _Filter.red => 'Schwach',
        _Filter.yellow => 'Mittel',
        _Filter.green => 'Gut',
        _Filter.neu => 'Neu',
      };

  MasteryLevel? get level => switch (this) {
        _Filter.all => null,
        _Filter.red => MasteryLevel.red,
        _Filter.yellow => MasteryLevel.yellow,
        _Filter.green => MasteryLevel.green,
        _Filter.neu => MasteryLevel.neu,
      };
}

/// Freier Übungsmodus ("Lernmodus"): anders als das Daily Quiz (das nur die
/// vom Scheduler für HEUTE vorgesehene, budgetierte Auswahl zeigt, siehe
/// DailySchedulerService) kann hier IMMER das gesamte Kartenset eines Fachs
/// geübt werden – unabhängig von Fälligkeit, Klausur-Pacing oder
/// Einheiten-"behandelt"-Status. Jede Antwort aktualisiert trotzdem den
/// echten FSRS-Zustand (siehe FsrsService.review) – kein folgenloses
/// "Probeüben", sondern zusätzliches, spaced-repetition-wirksames Training.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key, required this.moduleId, required this.moduleName});

  final String moduleId;
  final String moduleName;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final _fsrs = FsrsService();
  final _mastery = MasteryService();

  List<Flashcard>? _queue;
  int _index = 0;
  int _reviewedCount = 0;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<FlashcardRepository>().loadForModule(widget.moduleId));
  }

  bool _matches(Flashcard card, _Filter filter) {
    final level = filter.level;
    return level == null || _mastery.levelFor(card) == level;
  }

  void _start(_Filter filter) {
    final cards = context
        .read<FlashcardRepository>()
        .forModule(widget.moduleId)
        .where((c) => _matches(c, filter))
        .toList()
      ..shuffle();
    setState(() {
      _filter = filter;
      _queue = cards;
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

  /// Identisch zur Eskalations-Logik im Daily Quiz (siehe dort) – bewusst
  /// dupliziert statt geteilt, um diesen Screen unabhängig von
  /// DailyQuizScreen zu halten.
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
      // Stille Behandlung, siehe Doc-Kommentar in DailyQuizScreen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final queue = _queue;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text('Üben · ${widget.moduleName}')),
      body: SafeArea(
        child: queue == null
            ? _FilterPicker(
                cards: context.watch<FlashcardRepository>().forModule(widget.moduleId),
                mastery: _mastery,
                onStart: _start,
              )
            : queue.isEmpty
                ? _EmptyView(filter: _filter, onBack: () => setState(() => _queue = null))
                : _index >= queue.length
                    ? _DoneView(count: _reviewedCount, onRestart: () => setState(() => _queue = null))
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: (_index + 1) / queue.length,
                                minHeight: 6,
                                backgroundColor: c.border,
                                valueColor: AlwaysStoppedAnimation(c.accent),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('${_index + 1} / ${queue.length} · ${_filter.label}',
                              style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                          const SizedBox(height: 4),
                          Expanded(
                            child: QuestionAnswerView(
                              key: ValueKey(queue[_index].id),
                              card: queue[_index],
                              isNew: queue[_index].reps == 0,
                              onComplete: ({selfGrade, isCorrect}) => _handleComplete(
                                queue[_index],
                                selfGrade: selfGrade,
                                isCorrect: isCorrect,
                              ),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}

class _FilterPicker extends StatelessWidget {
  const _FilterPicker({required this.cards, required this.mastery, required this.onStart});

  final List<Flashcard> cards;
  final MasteryService mastery;
  final void Function(_Filter filter) onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (cards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Noch keine Karteikarten in diesem Fach.',
              style: TextStyle(color: c.inkMuted), textAlign: TextAlign.center),
        ),
      );
    }
    final breakdown = mastery.breakdown(cards);
    int countFor(_Filter f) => f.level == null ? cards.length : (breakdown[f.level] ?? 0);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Übe frei, unabhängig von Fälligkeit oder Klausur-Pacing – jede Antwort '
          'zählt trotzdem für die Spaced-Repetition-Planung im Daily Quiz.',
          style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 20),
        for (final f in _Filter.values)
          if (countFor(f) > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: () => onStart(f),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (f.level != null) ...[
                      MasteryDot(level: f.level!),
                      const SizedBox(width: 8),
                    ],
                    Text('${f.label} (${countFor(f)})'),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.filter, required this.onBack});
  final _Filter filter;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Keine Karten in Kategorie "${filter.label}" gefunden.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onBack, child: const Text('Zurück zur Auswahl')),
          ],
        ),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.count, required this.onRestart});
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
            Text('Runde abgeschlossen! $count Karten geübt.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRestart, child: const Text('Weitere Runde')),
          ],
        ),
      ),
    );
  }
}
