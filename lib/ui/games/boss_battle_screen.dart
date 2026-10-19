import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/boss_battle.dart';
import '../../services/calc_task_detector.dart';
import '../../services/fsrs_service.dart';
import '../../services/stage_gate_service.dart';
import '../../theme/app_colors.dart';
import '../daily/card_review_mixin.dart';
import '../daily/question_answer_view.dart';
import '../widgets/calc_tasks_toggle.dart';

enum _Phase { loading, intro, playing, done }

/// Boss-Kampf: die schwächsten Karten eines Fachs als „Endgegner“ (Logik in
/// [BossBattle]). Falsch Beantwortetes kommt kurz darauf wieder, bis jede
/// Karte einmal saß. Jede Antwort zählt wie im Daily Quiz (FSRS, Ampel,
/// Stufen – siehe CardReviewMixin); keine Münzen, nur die eigene Zahl
/// besiegter Bosse (AppSettings.bossesDefeated).
class BossBattleScreen extends StatefulWidget {
  const BossBattleScreen({super.key, this.moduleId});

  /// Vorausgewähltes Fach (null = alle Fächer).
  final String? moduleId;

  @override
  State<BossBattleScreen> createState() => _BossBattleScreenState();
}

class _BossBattleScreenState extends State<BossBattleScreen> with CardReviewMixin<BossBattleScreen> {
  _Phase _phase = _Phase.loading;
  String? _moduleId;
  List<Flashcard> _cards = [];
  BossBattle? _battle;
  bool _hasCalcCards = false;

  /// Zählt Treffer/Fehler hoch – startet die Wackel-Animation neu.
  int _hits = 0;
  int _misses = 0;

  @override
  void initState() {
    super.initState();
    _moduleId = widget.moduleId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _phase = _Phase.loading);
    final includeCalc = CalcTasksToggle.includeOf(context);
    final all = StageGate.learnable(await context.read<FlashcardRepository>().loadAll())
        .where((c) => _moduleId == null || c.moduleId == _moduleId)
        .toList();
    // Lernaufgaben sind zu lang für eine Kampfrunde (wie im Sprint).
    final cards = all
        .where((c) => !StageGate.isTaskType(c.type) && (includeCalc || !CalcTaskDetector.isCalcTask(c)))
        .toList();
    if (!mounted) return;
    setState(() {
      _hasCalcCards = all.any(CalcTaskDetector.isCalcTask);
      _cards = BossBattle.pickCards(cards);
      _phase = _Phase.intro;
    });
  }

  void _start() {
    setState(() {
      _battle = BossBattle(_cards);
      _hits = 0;
      _misses = 0;
      _phase = _Phase.playing;
    });
  }

  void _handleComplete(Flashcard card, {Grade? selfGrade, bool? isCorrect}) {
    final battle = _battle;
    if (battle == null || battle.current?.id != card.id) return;
    // "Schwer" ist ein erfolgreicher, nur mühsamer Abruf – zählt als Treffer.
    final correct = isCorrect ?? (selfGrade != Grade.again);
    unawaited(recordReview(card, selfGrade: selfGrade, isCorrect: isCorrect));
    setState(() {
      if (battle.answer(correct: correct) == BossHit.hit) {
        _hits++;
      } else {
        _misses++;
      }
    });
    if (battle.over) unawaited(_finish());
  }

  Future<void> _finish() async {
    final battle = _battle!;
    if (battle.won) {
      final repo = context.read<SettingsRepository>();
      await repo.update(repo.settings.copyWith(bossesDefeated: repo.settings.bossesDefeated + 1));
    }
    if (mounted) setState(() => _phase = _Phase.done);
  }

  String get _bossName {
    final id = _moduleId;
    if (id == null) return 'Endgegner aller Fächer';
    return 'Endgegner ${context.read<ModuleRepository>().byId(id)?.name ?? 'Fach'}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final battle = _battle;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Boss-Kampf')),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.loading => const Center(child: CircularProgressIndicator()),
          _Phase.intro => _intro(c),
          _Phase.playing =>
            battle?.current == null
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      _BossHeader(name: _bossName, battle: battle!, hits: _hits, misses: _misses),
                      Expanded(
                        child: QuestionAnswerView(
                          key: ValueKey('${battle.current!.id}-${battle.answered}'),
                          card: battle.current!,
                          isNew: false,
                          onImageEdited: (bytes) => saveEditedImage(battle.current!, bytes),
                          onSkip: () => setState(battle.skip),
                          canGiveUp: true,
                          onComplete: ({selfGrade, isCorrect}) =>
                              _handleComplete(battle.current!, selfGrade: selfGrade, isCorrect: isCorrect),
                        ),
                      ),
                    ],
                  ),
          _Phase.done => _BossResult(
            battle: battle!,
            name: _bossName,
            total: context.watch<SettingsRepository>().settings.bossesDefeated,
            onRestart: _start,
          ),
        },
      ),
    );
  }

  Widget _intro(AppColors c) {
    final modules = context.watch<ModuleRepository>().modules;
    final enough = _cards.length >= BossBattle.minCards;
    final defeated = context.watch<SettingsRepository>().settings.bossesDefeated;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.pest_control_rounded, size: 64, color: c.danger),
        const SizedBox(height: 12),
        Text(
          'Deine schwächsten Karten sind der Boss. Jede richtige Antwort trifft ihn, jede falsche kostet '
          'ein Herz – und die Karte kommt kurz darauf noch einmal. Besiegt ist er, wenn jede Karte einmal saß.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String?>(
          key: const ValueKey('boss-module'),
          initialValue: _moduleId,
          decoration: const InputDecoration(labelText: 'Fach', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: null, child: Text('Alle Fächer')),
            for (final m in modules) DropdownMenuItem(value: m.id, child: Text(m.name)),
          ],
          onChanged: (id) {
            _moduleId = id;
            _load();
          },
        ),
        if (_hasCalcCards) ...[const SizedBox(height: 8), CalcTasksToggle(onChanged: (_) => _load())],
        const SizedBox(height: 16),
        Text(
          enough
              ? '${_cards.length} Karten · ${BossBattle.defaultHearts} Herzen'
              : 'Hier gibt es noch zu wenig gelernte Karten für einen Kampf (mindestens ${BossBattle.minCards}) – '
                    'erst ein bisschen im Daily Quiz lernen.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.inkMuted),
        ),
        if (defeated > 0) ...[
          const SizedBox(height: 6),
          Text(
            'Bisher besiegt: $defeated',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.inkMuted, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            key: const ValueKey('boss-start'),
            onPressed: enough ? _start : null,
            icon: const Icon(Icons.sports_martial_arts_rounded),
            label: const Text('Kampf beginnen'),
          ),
        ),
      ],
    );
  }
}

class _BossHeader extends StatelessWidget {
  const _BossHeader({required this.name, required this.battle, required this.hits, required this.misses});

  final String name;
  final BossBattle battle;
  final int hits;
  final int misses;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final share = battle.maxHp == 0 ? 0.0 : battle.hp / battle.maxHp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          // Wackelt bei jedem Treffer (Schlüssel = Trefferzahl), färbt sich
          // kurz rot.
          TweenAnimationBuilder<double>(
            key: ValueKey('hit-$hits'),
            tween: Tween(begin: hits == 0 ? 0 : 1, end: 0),
            duration: const Duration(milliseconds: 450),
            builder: (context, t, child) => Transform.translate(
              offset: Offset(8 * t * sin(t * pi * 6), 0),
              child: Icon(Icons.pest_control_rounded, size: 44, color: Color.lerp(c.danger, c.warn, t)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: share),
                    duration: const Duration(milliseconds: 400),
                    builder: (context, v, _) => LinearProgressIndicator(
                      key: const ValueKey('boss-hp'),
                      value: v,
                      minHeight: 8,
                      backgroundColor: c.border,
                      valueColor: AlwaysStoppedAnimation(c.danger),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${battle.hp} / ${battle.maxHp}',
                      key: const ValueKey('boss-hp-text'),
                      style: TextStyle(fontSize: 12, color: c.inkMuted),
                    ),
                    const Spacer(),
                    if (battle.combo >= 2)
                      Text(
                        'Combo ×${battle.combo}  ',
                        style: TextStyle(fontSize: 12, color: c.good, fontWeight: FontWeight.w700),
                      ),
                    for (var i = 0; i < BossBattle.defaultHearts; i++)
                      Icon(
                        i < battle.hearts ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 16,
                        color: c.danger,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BossResult extends StatelessWidget {
  const _BossResult({required this.battle, required this.name, required this.total, required this.onRestart});

  final BossBattle battle;
  final String name;
  final int total;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final review = battle.toReview;
    return ListView(
      key: const ValueKey('boss-result'),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          battle.won ? Icons.emoji_events_outlined : Icons.directions_run_rounded,
          size: 64,
          color: battle.won ? c.warn : c.inkMuted,
        ),
        const SizedBox(height: 12),
        Text(
          battle.won ? '$name besiegt!' : '$name ist entkommen.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          battle.won
              ? 'Alle ${battle.maxHp} Karten saßen – mit ${battle.hearts} Herzen übrig. Längste Combo: ${battle.bestCombo}. '
                    'Insgesamt besiegt: $total.'
              : '${battle.maxHp - battle.hp} von ${battle.maxHp} Karten saßen. Revanche?',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.inkMuted, height: 1.4),
        ),
        if (review.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Diese Karten haben gehakt',
            style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
          ),
          const SizedBox(height: 6),
          for (final card in review)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• ${card.promptText}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.inkMuted, fontSize: 13),
              ),
            ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig')),
            const SizedBox(width: 10),
            FilledButton(
              key: const ValueKey('boss-restart'),
              onPressed: onRestart,
              child: Text(battle.won ? 'Nochmal' : 'Revanche'),
            ),
          ],
        ),
      ],
    );
  }
}
