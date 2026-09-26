import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/fsrs_service.dart';
import '../../services/mastery_service.dart';
import '../../theme/app_colors.dart';
import '../daily/card_review_mixin.dart';
import '../daily/question_answer_view.dart';

enum _Phase { loading, intro, playing, done }

/// Sprint-Pausenmodus: eine kurze, zeitdruckbasierte Runde über die aktuell
/// schwächsten (Ampel-rot) Karten, fachübergreifend.
///  - Jede Antwort zählt wie im Daily Quiz/Üben (FSRS, Ampel, Stufen – siehe
///    CardReviewMixin): gerade die schwachen Karten profitieren davon, und
///    eine richtige Antwort unter Zeitdruck ist ein echter Abruf.
///  - KEINE Münzen/Shop/Fremdvergleich – nur eine rein geräte-lokale
///    persönliche Bestleistung (siehe AppSettings.bestSprintScore), im
///    Sinne der Selbstbestimmungstheorie (Kompetenz-Feedback gegen den
///    eigenen Stand statt Leaderboard-Druck, siehe Deci & Ryan).
class SprintScreen extends StatefulWidget {
  const SprintScreen({super.key});

  @override
  State<SprintScreen> createState() => _SprintScreenState();
}

class _SprintScreenState extends State<SprintScreen> with CardReviewMixin<SprintScreen> {
  static const _durationSeconds = 60;
  static const _minPoolSize = 3;
  static const _maxQueueLength = 30;

  _Phase _phase = _Phase.loading;
  List<Flashcard> _queue = [];
  int _index = 0;
  int _correct = 0;
  int _remainingSeconds = _durationSeconds;
  bool _isNewBest = false;
  bool _usedYellowFallback = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPool());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadPool() async {
    setState(() => _phase = _Phase.loading);
    final cards = await context.read<FlashcardRepository>().loadAll();
    final mastery = MasteryService();
    var pool = cards.where((c) => mastery.levelFor(c) == MasteryLevel.red).toList();
    var usedFallback = false;
    if (pool.length < _minPoolSize) {
      // Nicht genug rote Karten für eine sinnvolle Runde: gelbe (mittel)
      // dazunehmen, statt den Sprint komplett zu verweigern.
      pool = cards
          .where((c) => mastery.levelFor(c) == MasteryLevel.red || mastery.levelFor(c) == MasteryLevel.yellow)
          .toList();
      usedFallback = true;
    }
    pool.shuffle();
    if (!mounted) return;
    setState(() {
      _queue = pool.take(_maxQueueLength).toList();
      _usedYellowFallback = usedFallback;
      _phase = _Phase.intro;
    });
  }

  void _start() {
    setState(() {
      _phase = _Phase.playing;
      _index = 0;
      _correct = 0;
      _remainingSeconds = _durationSeconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remainingSeconds -= 1);
      if (_remainingSeconds <= 0) _finish();
    });
  }

  void _handleComplete(Flashcard card, {Grade? selfGrade, bool? isCorrect}) {
    // "Schwer" ist ein erfolgreicher, nur mühsamer Abruf – zählt als richtig.
    final wasCorrect = isCorrect ?? (selfGrade != Grade.again);
    unawaited(recordReview(card, selfGrade: selfGrade, isCorrect: isCorrect));
    // Eine Antwort nach Zeitablauf (z.B. während der KI-Prüfung einer
    // Freitextantwort) zählt fürs Lernen, aber nicht mehr für die Punkte –
    // die Bestleistung ist dann schon ausgewertet.
    if (_phase != _Phase.playing) return;
    setState(() {
      if (wasCorrect) _correct += 1;
      _index += 1;
    });
    if (_index >= _queue.length) _finish();
  }

  Future<void> _finish() async {
    if (_phase == _Phase.done) return;
    _timer?.cancel();
    final repo = context.read<SettingsRepository>();
    final isNewBest = _correct > repo.settings.bestSprintScore;
    if (isNewBest) {
      await repo.update(repo.settings.copyWith(bestSprintScore: _correct));
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.done;
      _isNewBest = isNewBest;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bestScore = context.watch<SettingsRepository>().settings.bestSprintScore;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Sprint')),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.loading => const Center(child: CircularProgressIndicator()),
          _Phase.intro => _IntroView(
              count: _queue.length,
              usedYellowFallback: _usedYellowFallback,
              bestScore: bestScore,
              onStart: _queue.length >= _minPoolSize ? _start : null,
            ),
          _Phase.playing => _index >= _queue.length
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    _SprintHeader(
                      remainingSeconds: _remainingSeconds,
                      totalSeconds: _durationSeconds,
                      index: _index,
                      total: _queue.length,
                      correct: _correct,
                    ),
                    Expanded(
                      child: QuestionAnswerView(
                        key: ValueKey(_queue[_index].id),
                        card: _queue[_index],
                        isNew: false,
                        onComplete: ({selfGrade, isCorrect}) =>
                            _handleComplete(_queue[_index], selfGrade: selfGrade, isCorrect: isCorrect),
                      ),
                    ),
                  ],
                ),
          _Phase.done => _DoneView(
              correct: _correct,
              total: _index,
              bestScore: bestScore,
              isNewBest: _isNewBest,
              onRestart: _loadPool,
            ),
        },
      ),
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({
    required this.count,
    required this.usedYellowFallback,
    required this.bestScore,
    required this.onStart,
  });

  final int count;
  final bool usedYellowFallback;
  final int bestScore;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 56, color: c.warn),
            const SizedBox(height: 16),
            Text(
              onStart == null
                  ? 'Noch nicht genug schwache Karten für einen Sprint – erst ein '
                      'bisschen mehr üben, dann gibt es hier was zu tun.'
                  : '60 Sekunden, $count Karte${count == 1 ? '' : 'n'} '
                      '(${usedYellowFallback ? 'schwach & mittel' : 'deine schwächsten'}). '
                      'Jede Antwort zählt für Ampel und Wiederholungsplan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted, height: 1.4),
            ),
            if (bestScore > 0) ...[
              const SizedBox(height: 12),
              Text('Bestleistung: $bestScore',
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted, fontWeight: FontWeight.w600)),
            ],
            if (onStart != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Sprint starten'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SprintHeader extends StatelessWidget {
  const _SprintHeader({
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.index,
    required this.total,
    required this.correct,
  });

  final int remainingSeconds;
  final int totalSeconds;
  final int index;
  final int total;
  final int correct;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final urgent = remainingSeconds <= 10;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (remainingSeconds / totalSeconds).clamp(0, 1),
              minHeight: 6,
              backgroundColor: c.border,
              valueColor: AlwaysStoppedAnimation(urgent ? c.danger : c.accent),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${index + 1} / $total', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
              Text('$correct richtig', style: TextStyle(fontSize: 12.5, color: c.good, fontWeight: FontWeight.w600)),
              Text('$remainingSeconds s',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: urgent ? c.danger : c.ink)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({
    required this.correct,
    required this.total,
    required this.bestScore,
    required this.isNewBest,
    required this.onRestart,
  });

  final int correct;
  final int total;
  final int bestScore;
  final bool isNewBest;
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
            Icon(isNewBest ? Icons.emoji_events_outlined : Icons.timer_outlined,
                size: 56, color: isNewBest ? c.warn : c.accent),
            const SizedBox(height: 16),
            Text('$correct von $total richtig', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              isNewBest ? 'Neue Bestleistung!' : 'Bisherige Bestleistung: $bestScore',
              style: TextStyle(
                fontSize: 13,
                color: isNewBest ? c.good : c.inkMuted,
                fontWeight: isNewBest ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig')),
                const SizedBox(width: 10),
                FilledButton(onPressed: onRestart, child: const Text('Nochmal')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
