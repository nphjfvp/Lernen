import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/module_repository.dart';
import '../../services/ai_service.dart';
import '../../services/fsrs_service.dart';
import '../../theme/app_colors.dart';
import '../study/study_aids.dart';
import '../widgets/math_text.dart';
import 'question_answer_view.dart';

/// Die Fragen eines Fachs in den Lerneinheiten.
class _Group {
  _Group(this.moduleId, this.name, this.cards);
  final String moduleId;
  final String name;
  final List<Flashcard> cards;
}

enum _Phase { lesson, retryOffer, retry, retryDone, done }

/// Lerneinheiten nach dem Daily Quiz: zu jeder heute falsch beantworteten
/// Frage eine kurze Lerneinheit – Fach für Fach, nicht durcheinander. Jede
/// lässt sich überspringen, ein ganzes Fach auch; nach den Lerneinheiten eines
/// Fachs kann man dessen Fragen nochmal versuchen (zählt nicht für die
/// Planung – die Karten wurden heute schon bewertet).
class MissedLessonsScreen extends StatefulWidget {
  const MissedLessonsScreen({super.key, required this.cards});

  final List<Flashcard> cards;

  /// Test-Hook statt der KI aus den Einstellungen.
  static AiService? Function(Flashcard card)? aiFactory;

  @override
  State<MissedLessonsScreen> createState() => _MissedLessonsScreenState();
}

class _MissedLessonsScreenState extends State<MissedLessonsScreen> {
  late final List<_Group> _groups = _buildGroups();
  int _group = 0;
  int _lesson = 0;
  _Phase _phase = _Phase.lesson;

  /// Gelesen bzw. übersprungen (für die Zusammenfassung).
  int _read = 0;
  int _skipped = 0;

  /// Nochmal versuchen: die Fragen dieser Runde, Position, Ergebnisse.
  List<Flashcard> _retry = const [];
  int _retryIndex = 0;
  int _retryRound = 0;
  final List<Flashcard> _retryWrong = [];
  int _retryCorrect = 0;

  List<_Group> _buildGroups() {
    final modules = context.read<ModuleRepository?>();
    final byModule = <String, List<Flashcard>>{};
    for (final card in widget.cards) {
      byModule.putIfAbsent(card.moduleId, () => []).add(card);
    }
    final groups = [for (final e in byModule.entries) _Group(e.key, modules?.byId(e.key)?.name ?? 'Fach', e.value)];
    groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return groups;
  }

  _Group get _current => _groups[_group];
  bool get _lastGroup => _group >= _groups.length - 1;

  void _nextLesson({required bool skipped}) => setState(() {
    skipped ? _skipped++ : _read++;
    if (_lesson + 1 < _current.cards.length) {
      _lesson++;
    } else {
      _phase = _Phase.retryOffer;
    }
  });

  /// Restliche Lerneinheiten dieses Fachs überspringen.
  void _skipModule() => setState(() {
    _skipped += _current.cards.length - _lesson;
    _phase = _Phase.retryOffer;
  });

  void _startRetry(List<Flashcard> cards) => setState(() {
    _retry = List.of(cards);
    _retryIndex = 0;
    _retryRound++;
    _retryWrong.clear();
    _retryCorrect = 0;
    _phase = _Phase.retry;
  });

  void _retryAnswered(Flashcard card, {Grade? selfGrade, bool? isCorrect}) => setState(() {
    final wrong = isCorrect == false || (isCorrect == null && selfGrade == Grade.again);
    if (wrong) {
      _retryWrong.add(card);
    } else {
      _retryCorrect++;
    }
    if (_retryIndex + 1 < _retry.length) {
      _retryIndex++;
    } else {
      _phase = _Phase.retryDone;
    }
  });

  void _nextGroup() => setState(() {
    if (_lastGroup) {
      _phase = _Phase.done;
    } else {
      _group++;
      _lesson = 0;
      _phase = _Phase.lesson;
    }
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Lerneinheiten'),
        actions: [
          if (_phase != _Phase.done)
            TextButton(
              key: const ValueKey('lessons-end'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Beenden'),
            ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: _body(c)),
        ),
      ),
    );
  }

  Widget _body(AppColors c) {
    if (_phase == _Phase.done) return _done(c);
    if (_phase == _Phase.retry) {
      final card = _retry[_retryIndex];
      return Column(
        children: [
          _header(c, 'Nochmal versuchen · ${_retryIndex + 1} von ${_retry.length}'),
          Expanded(
            child: QuestionAnswerView(
              key: ValueKey('lessons-retry-$_retryRound-${card.id}'),
              card: card,
              isNew: false,
              onComplete: ({selfGrade, isCorrect}) => _retryAnswered(card, selfGrade: selfGrade, isCorrect: isCorrect),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        _header(
          c,
          _phase == _Phase.lesson ? 'Lerneinheit ${_lesson + 1} von ${_current.cards.length}' : 'Lerneinheiten durch',
        ),
        const SizedBox(height: 8),
        ...switch (_phase) {
          _Phase.lesson => _lessonView(c),
          _Phase.retryOffer => _retryOffer(c),
          _ => _retryDone(c),
        },
      ],
    );
  }

  /// Fach-Leiste (alle Fächer, das aktuelle hervorgehoben) und Fortschritt.
  Widget _header(AppColors c, String progress) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_groups.length > 1)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, g) in _groups.indexed)
                Chip(
                  key: ValueKey('lessons-module-$i'),
                  visualDensity: VisualDensity.compact,
                  avatar: i < _group ? Icon(Icons.check_circle, size: 16, color: c.good) : null,
                  backgroundColor: i == _group ? c.accentSoft : null,
                  label: Text('${g.name} (${g.cards.length})'),
                ),
            ],
          ),
        const SizedBox(height: 6),
        Text(
          '${_current.name} · $progress',
          key: const ValueKey('lessons-progress'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.inkMuted),
        ),
      ],
    ),
  );

  List<Widget> _lessonView(AppColors c) {
    final card = _current.cards[_lesson];
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MathText(card.front, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
            const SizedBox(height: 8),
            Text(
              'Richtige Antwort',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.good),
            ),
            MathText(answerTextOf(card), style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink)),
          ],
        ),
      ),
      const SizedBox(height: 14),
      MiniLessonContent(
        key: ValueKey('lessons-content-${card.id}'),
        card: card,
        ai: MissedLessonsScreen.aiFactory?.call(card) ?? studyAidsAi(context, card),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('lessons-skip'),
              onPressed: () => _nextLesson(skipped: true),
              child: const Text('Überspringen'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: const ValueKey('lessons-next'),
              onPressed: () => _nextLesson(skipped: false),
              child: const Text('Verstanden, weiter'),
            ),
          ),
        ],
      ),
      if (_lesson + 1 < _current.cards.length)
        Align(
          child: TextButton(
            key: const ValueKey('lessons-skip-module'),
            onPressed: _skipModule,
            child: Text('Restliche in ${_current.name} überspringen'),
          ),
        ),
    ];
  }

  String get _nextLabel => _lastGroup ? 'Fertig' : 'Weiter mit ${_groups[_group + 1].name}';

  List<Widget> _retryOffer(AppColors c) {
    final n = _current.cards.length;
    return [
      Text(
        n == 1
            ? 'Willst du die Frage aus ${_current.name} jetzt nochmal versuchen?'
            : 'Willst du die $n Fragen aus ${_current.name} jetzt nochmal versuchen?',
        style: const TextStyle(fontSize: 15, height: 1.4),
      ),
      const SizedBox(height: 4),
      Text(
        'Zählt nicht für die Planung – die Fragen wurden heute schon bewertet.',
        style: TextStyle(fontSize: 12.5, color: c.inkMuted),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const ValueKey('lessons-retry'),
        onPressed: () => _startRetry(_current.cards),
        icon: const Icon(Icons.replay),
        label: const Text('Nochmal versuchen'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(key: const ValueKey('lessons-next-module'), onPressed: _nextGroup, child: Text(_nextLabel)),
    ];
  }

  List<Widget> _retryDone(AppColors c) {
    final total = _retry.length;
    final allRight = _retryWrong.isEmpty;
    return [
      Container(
        key: const ValueKey('lessons-retry-result'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: allRight ? c.goodSoft : c.warnSoft, borderRadius: BorderRadius.circular(16)),
        child: Text(
          allRight ? 'Alle $total richtig!' : '$_retryCorrect von $total richtig.',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 14),
      if (!allRight) ...[
        FilledButton.icon(
          key: const ValueKey('lessons-retry-wrong'),
          onPressed: () => _startRetry(List.of(_retryWrong)),
          icon: const Icon(Icons.replay),
          label: Text(_retryWrong.length == 1 ? 'Die falsche nochmal' : 'Die ${_retryWrong.length} falschen nochmal'),
        ),
        const SizedBox(height: 8),
      ],
      OutlinedButton(key: const ValueKey('lessons-next-module'), onPressed: _nextGroup, child: Text(_nextLabel)),
    ];
  }

  Widget _done(AppColors c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_outlined, size: 56, color: c.good),
          const SizedBox(height: 16),
          Text(
            [
              'Lerneinheiten erledigt.',
              if (_read > 0) '$_read gelesen',
              if (_skipped > 0) '$_skipped übersprungen',
            ].join(_read > 0 || _skipped > 0 ? '\n' : ''),
            key: const ValueKey('lessons-summary'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('lessons-close'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zurück zum Daily Quiz'),
          ),
        ],
      ),
    ),
  );
}
