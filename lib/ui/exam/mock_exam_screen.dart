import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/mock_exam_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/mock_exam_service.dart';
import '../../theme/app_colors.dart';
import '../daily/card_review_mixin.dart';
import '../daily/question_answer_view.dart';
import '../practice/practice_screen.dart';

enum _Phase { setup, running, result }

/// Probeklausur für ein Fach: zufällige Auswahl aus dem bereits behandelten
/// Stoff, optional mit Zeitlimit, ohne Feedback und ohne Hilfen während der
/// Bearbeitung – am Ende Note (deutsche Hochschulskala), Trefferquote je
/// Einheit und eine Durchsicht aller Fragen mit KI-Erklärung. Jede
/// beantwortete Frage zählt normal für FSRS/Ampel (echter Abruf ohne
/// Hilfe); übersprungene Fragen gelten als falsch.
class MockExamScreen extends StatefulWidget {
  const MockExamScreen({super.key, required this.moduleId, required this.moduleName});

  final String moduleId;
  final String moduleName;

  @override
  State<MockExamScreen> createState() => _MockExamScreenState();
}

class _MockExamScreenState extends State<MockExamScreen> with CardReviewMixin<MockExamScreen> {
  static const _questionCounts = [10, 20, 30];
  static const _timeLimits = [0, 15, 30, 60]; // Minuten, 0 = ohne

  _Phase _phase = _Phase.setup;
  List<Flashcard> _moduleCards = [];
  Map<String, bool> _unitCoveredById = {};
  Map<String, String> _unitTitles = {};
  List<MockExamResult> _history = [];
  bool _loading = true;

  int _questionCount = 20;
  int _timeLimitMinutes = 30;

  List<Flashcard> _questions = [];
  final Map<String, bool> _correctById = {};
  int _index = 0;
  DateTime? _startedAt;
  Timer? _timer;
  int _remainingSeconds = 0;
  MockExamResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final flashcardRepo = context.read<FlashcardRepository>();
    final unitRepo = context.read<LectureUnitRepository>();
    await flashcardRepo.loadForModule(widget.moduleId);
    await unitRepo.loadForModule(widget.moduleId);
    final covered = await unitRepo.loadAllCoveredById();
    final history = await MockExamRepository().forModule(widget.moduleId);
    if (!mounted) return;
    setState(() {
      _moduleCards = flashcardRepo.forModule(widget.moduleId);
      _unitCoveredById = covered;
      _unitTitles = {for (final u in unitRepo.forModule(widget.moduleId)) u.id: u.title};
      _history = history;
      _loading = false;
      final options = MockExamService.questionCountOptions(_eligibleCount, standard: _questionCounts);
      if (options.isNotEmpty && !options.contains(_questionCount)) {
        _questionCount = options.length > 1 ? options[1] : options.first;
      }
    });
  }

  int get _eligibleCount => MockExamService.eligible(_moduleCards, unitCoveredById: _unitCoveredById).length;

  void _start() {
    final questions = MockExamService.selectQuestions(
      _moduleCards,
      count: _questionCount,
      unitCoveredById: _unitCoveredById,
    );
    if (questions.isEmpty) return;
    setState(() {
      _questions = questions;
      _correctById.clear();
      _index = 0;
      _startedAt = DateTime.now();
      _remainingSeconds = _timeLimitMinutes * 60;
      _phase = _Phase.running;
    });
    if (_timeLimitMinutes > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remainingSeconds -= 1);
        if (_remainingSeconds <= 0) _finish();
      });
    }
  }

  Future<void> _answer(Flashcard card, {Grade? selfGrade, bool? isCorrect}) async {
    final correct = isCorrect ?? (selfGrade != Grade.again);
    _correctById[card.id] = correct;
    unawaited(recordReview(card, selfGrade: selfGrade, isCorrect: isCorrect, showLevelFeedback: false));
    _next();
  }

  void _skip() {
    _correctById[_questions[_index].id] = false;
    _next();
  }

  void _next() {
    if (_phase != _Phase.running) return;
    if (_index + 1 >= _questions.length) {
      _finish();
    } else {
      setState(() => _index += 1);
    }
  }

  Future<void> _confirmFinishEarly() async {
    final open = _questions.length - _correctById.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jetzt abgeben?'),
        content: Text('$open Frage${open == 1 ? '' : 'n'} noch offen – sie zählen als falsch.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Weiter bearbeiten')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Abgeben')),
        ],
      ),
    );
    if (ok == true) _finish();
  }

  Future<void> _finish() async {
    if (_phase != _Phase.running) return;
    _timer?.cancel();
    for (final q in _questions) {
      _correctById.putIfAbsent(q.id, () => false); // unbeantwortet = falsch
    }
    final result = MockExamResult(
      moduleId: widget.moduleId,
      takenAt: DateTime.now(),
      correct: _correctById.values.where((c) => c).length,
      total: _questions.length,
      durationSeconds: DateTime.now().difference(_startedAt ?? DateTime.now()).inSeconds,
    );
    setState(() {
      _result = result;
      _phase = _Phase.result;
    });
    await MockExamRepository().add(result);
    final history = await MockExamRepository().forModule(widget.moduleId);
    if (mounted) setState(() => _history = history);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: _phase != _Phase.running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _Phase.running) _confirmFinishEarly();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(title: Text('Probeklausur · ${widget.moduleName}')),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : switch (_phase) {
                  _Phase.setup => _buildSetup(c),
                  _Phase.running => _buildRunning(c),
                  _Phase.result => _buildResult(c),
                },
        ),
      ),
    );
  }

  Widget _buildSetup(AppColors c) {
    final eligible = _eligibleCount;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Wie in der echten Klausur: zufällige Fragen aus dem bereits behandelten Stoff, '
          'kein Feedback und keine Tipps während der Bearbeitung. Am Ende gibt es eine Note, '
          'die Trefferquote je Einheit und eine Durchsicht mit Erklärungen. Jede Antwort zählt '
          'für Ampel und Wiederholungsplan.',
          style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 20),
        if (eligible == 0)
          Text('Noch keine Fragen aus behandelten Einheiten vorhanden.', style: TextStyle(color: c.inkMuted))
        else ...[
          Text('Anzahl Fragen ($eligible verfügbar)', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final n in MockExamService.questionCountOptions(eligible, standard: _questionCounts))
                ButtonSegment(value: n, label: Text('$n')),
            ],
            selected: {_questionCount},
            onSelectionChanged: (s) => setState(() => _questionCount = s.first),
          ),
          const SizedBox(height: 18),
          const Text('Zeitlimit', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final m in _timeLimits) ButtonSegment(value: m, label: Text(m == 0 ? 'Ohne' : '$m min')),
            ],
            selected: {_timeLimitMinutes},
            onSelectionChanged: (s) => setState(() => _timeLimitMinutes = s.first),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Probeklausur starten'),
          ),
        ],
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('BISHERIGE PROBEKLAUSUREN',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.04, color: c.inkMuted)),
          const SizedBox(height: 8),
          for (final r in _history.take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _GradeBadge(grade: r.grade),
              title: Text('${r.correct} von ${r.total} richtig (${(r.ratio * 100).round()} %)'),
              subtitle: Text(_formatDate(r.takenAt)),
            ),
        ],
      ],
    );
  }

  Widget _buildRunning(AppColors c) {
    final card = _questions[_index];
    final timed = _timeLimitMinutes > 0;
    final urgent = timed && _remainingSeconds <= 60;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (_index + 1) / _questions.length,
                  minHeight: 6,
                  backgroundColor: c.border,
                  valueColor: AlwaysStoppedAnimation(c.accent),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('${_index + 1} / ${_questions.length}', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                  const Spacer(),
                  if (timed)
                    Text(
                      _formatDuration(_remainingSeconds),
                      style: TextStyle(fontWeight: FontWeight.w700, color: urgent ? c.danger : c.ink),
                    ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _skip, child: const Text('Überspringen')),
                  TextButton(onPressed: _confirmFinishEarly, child: const Text('Abgeben')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: QuestionAnswerView(
            key: ValueKey('exam-${card.id}'),
            card: card,
            isNew: false,
            examMode: true,
            onComplete: ({selfGrade, isCorrect}) => _answer(card, selfGrade: selfGrade, isCorrect: isCorrect),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(AppColors c) {
    final result = _result!;
    final passed = result.grade <= 4.0;
    final units = MockExamService.unitBreakdown(_questions, _correctById);
    final wrong = [for (final q in _questions) if (_correctById[q.id] != true) q];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(child: _GradeBadge(grade: result.grade, large: true)),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '${result.correct} von ${result.total} richtig (${(result.ratio * 100).round()} %)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '${passed ? 'Bestanden' : 'Nicht bestanden'} · ${_formatDuration(result.durationSeconds)} gebraucht',
            style: TextStyle(color: passed ? c.good : c.danger),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            if (wrong.isNotEmpty)
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) => PracticeScreen.cards(title: 'Probeklausur-Fehler', cards: wrong),
                  )),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text('${wrong.length} falsche üben'),
                ),
              ),
            if (wrong.isNotEmpty) const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _phase = _Phase.setup),
                child: const Text('Neue Probeklausur'),
              ),
            ),
          ],
        ),
        if (units.length > 1 || (units.length == 1 && units.single.unitId != null)) ...[
          const SizedBox(height: 26),
          Text('NACH EINHEIT',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.04, color: c.inkMuted)),
          const SizedBox(height: 8),
          for (final u in units)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(u.unitId == null ? 'Ohne Einheit' : (_unitTitles[u.unitId] ?? 'Einheit'))),
                      Text('${u.correct}/${u.total}', style: TextStyle(color: c.inkMuted)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: u.ratio,
                      minHeight: 6,
                      backgroundColor: c.border,
                      valueColor: AlwaysStoppedAnimation(u.ratio >= 0.5 ? c.good : c.danger),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 26),
        Text('DURCHSICHT',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.04, color: c.inkMuted)),
        const SizedBox(height: 8),
        for (final q in _questions) _ReviewTile(card: q, correct: _correctById[q.id] == true),
      ],
    );
  }

  static String _formatDuration(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

class _GradeBadge extends StatelessWidget {
  const _GradeBadge({required this.grade, this.large = false});

  final double grade;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = grade <= 2.0
        ? c.good
        : grade <= 4.0
            ? c.warn
            : c.danger;
    final bg = grade <= 2.0
        ? c.goodSoft
        : grade <= 4.0
            ? c.warnSoft
            : c.dangerSoft;
    final size = large ? 96.0 : 44.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        MockExamService.formatGrade(grade),
        style: TextStyle(fontSize: large ? 30 : 14, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

/// Eine Frage in der Durchsicht: richtig/falsch, Lösung, KI-Erklärung auf
/// Wunsch.
class _ReviewTile extends StatefulWidget {
  const _ReviewTile({required this.card, required this.correct});

  final Flashcard card;
  final bool correct;

  @override
  State<_ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends State<_ReviewTile> {
  String? _explanation;
  bool _loading = false;
  String? _error;

  String get _answer => widget.card.answerSummary.isNotEmpty ? widget.card.answerSummary : widget.card.back;

  Future<void> _explain() async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final text = await ai.explainAnswer(
        question: widget.card.front,
        correctAnswer: _answer,
        wasCorrect: widget.correct,
      );
      if (mounted) setState(() => _explanation = text);
    } catch (e) {
      if (mounted) setState(() => _error = e is AiServiceException ? e.message : 'Erklärung fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasApiKey = context.watch<SettingsRepository>().settings.hasApiKey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // Material statt DecoratedBox: ExpansionTile malt Hintergrund und
      // Tipp-Effekt auf das nächste Material darunter.
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Icon(
              widget.correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: widget.correct ? c.good : c.danger,
            ),
            title: Text(widget.card.front, maxLines: 2, overflow: TextOverflow.ellipsis),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lösung', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
              const SizedBox(height: 4),
              SelectableText(_answer, style: const TextStyle(fontSize: 13.5, height: 1.4)),
              if (hasApiKey) ...[
                const SizedBox(height: 10),
                if (_explanation == null)
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _explain,
                    icon: _loading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.psychology_alt_outlined, size: 18),
                    label: const Text('Erklär mir das'),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
                    child: SelectableText(_explanation!, style: TextStyle(fontSize: 13, height: 1.45, color: c.ink)),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_error!, style: TextStyle(fontSize: 12, color: c.danger)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
