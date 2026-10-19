import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/error_hunt.dart';
import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/boss_battle.dart';
import '../../services/stage_gate_service.dart';
import '../../services/weakness_service.dart';
import '../../theme/app_colors.dart';
import '../practice/practice_screen.dart';
import '../widgets/math_text.dart';

enum _Phase { intro, loading, playing, done }

/// Fehlerjagd: die KI macht aus den schwächsten Karten kurze Aussagen, etwa
/// die Hälfte mit einem typischen Denkfehler – stimmt’s oder nicht? Nach
/// jeder Antwort die Begründung. Zählt bewusst NICHT für Ampel/FSRS (eine
/// Wahr/Falsch-Entscheidung über eine umformulierte Aussage ist kein echter
/// Abruf der Karte); am Ende lassen sich die Karten, die gehakt haben, im
/// normalen Üben wiederholen – das zählt dann.
class ErrorHuntScreen extends StatefulWidget {
  const ErrorHuntScreen({super.key});

  /// Tests ersetzen die KI.
  static AiService Function(String apiKey, String model)? aiFactory;

  static const maxCards = 12;
  static const minCards = 3;

  /// Karten für eine Runde: zuerst das Fehlertagebuch (oft falsch, zuletzt
  /// falsch, rot), dann die übrigen schwächsten schon gelernten.
  static List<Flashcard> pickCards(List<Flashcard> cards) {
    final weak = WeaknessService().rank(cards).map((w) => w.card).toList();
    final ids = {for (final c in weak) c.id};
    return [...weak, ...BossBattle.pickCards(cards).where((c) => !ids.contains(c.id))].take(maxCards).toList();
  }

  @override
  State<ErrorHuntScreen> createState() => _ErrorHuntScreenState();
}

class _ErrorHuntScreenState extends State<ErrorHuntScreen> {
  _Phase _phase = _Phase.intro;
  String? _moduleId;
  List<Flashcard> _cards = [];
  bool _cardsLoaded = false;
  List<ErrorHuntStatement> _statements = [];
  int _index = 0;
  bool? _answer;
  int _correct = 0;
  int _streak = 0;
  int _bestStreak = 0;
  final Set<String> _missedCardIds = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCards());
  }

  Future<void> _loadCards() async {
    final all = StageGate.learnable(await context.read<FlashcardRepository>().loadAll())
        .where((c) => !StageGate.isTaskType(c.type) && (_moduleId == null || c.moduleId == _moduleId))
        .toList();
    if (!mounted) return;
    setState(() {
      _cards = ErrorHuntScreen.pickCards(all);
      _cardsLoaded = true;
    });
  }

  Future<void> _start() async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return;
    final ai = (ErrorHuntScreen.aiFactory ?? (key, model) => AiService(apiKey: key, model: model))(
      settings.openRouterApiKey!,
      settings.effectiveHelpModelId,
    );
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final statements = await ai.generateErrorHunt([
        for (final c in _cards) (id: c.id, question: c.promptText, answer: c.back),
      ], count: (_cards.length * 2).clamp(6, 12));
      if (!mounted) return;
      setState(() {
        _statements = statements;
        _index = 0;
        _answer = null;
        _correct = 0;
        _streak = 0;
        _bestStreak = 0;
        _missedCardIds.clear();
        _phase = _Phase.playing;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AiServiceException ? e.message : 'Fehlerjagd ließ sich nicht starten: $e';
        _phase = _Phase.intro;
      });
    }
  }

  void _decide(bool saysTrue) {
    if (_answer != null) return;
    final s = _statements[_index];
    final right = saysTrue == s.isTrue;
    setState(() {
      _answer = saysTrue;
      if (right) {
        _correct++;
        _streak++;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
        if (s.cardId != null) _missedCardIds.add(s.cardId!);
      }
    });
  }

  void _next() {
    setState(() {
      _answer = null;
      if (_index + 1 >= _statements.length) {
        _phase = _Phase.done;
      } else {
        _index++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Fehlerjagd')),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.intro => _intro(c),
          _Phase.loading => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Die KI versteckt Fehler in deinem Stoff …', style: TextStyle(color: c.inkMuted)),
              ],
            ),
          ),
          _Phase.playing => _playing(c),
          _Phase.done => _done(c),
        },
      ),
    );
  }

  Widget _intro(AppColors c) {
    final modules = context.watch<ModuleRepository>().modules;
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    final enough = _cards.length >= ErrorHuntScreen.minCards;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.travel_explore_rounded, size: 64, color: c.accent),
        const SizedBox(height: 12),
        Text(
          'Die KI baut aus deinen schwächsten Karten kurze Aussagen – in etwa der Hälfte steckt ein typischer '
          'Denkfehler. Stimmt’s oder nicht? Nach jeder Antwort siehst du, warum. Zählt nicht für die Ampel; '
          'am Ende kannst du die Karten, die gehakt haben, gezielt üben.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String?>(
          key: const ValueKey('hunt-module'),
          initialValue: _moduleId,
          decoration: const InputDecoration(labelText: 'Fach', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: null, child: Text('Alle Fächer')),
            for (final m in modules) DropdownMenuItem(value: m.id, child: Text(m.name)),
          ],
          onChanged: (id) {
            _moduleId = id;
            _loadCards();
          },
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              key: const ValueKey('hunt-error'),
              style: TextStyle(color: c.danger),
            ),
          ),
        if (_cardsLoaded)
          Text(
            !hasKey
                ? 'Für die Fehlerjagd braucht es einen OpenRouter-Key (Einstellungen).'
                : enough
                ? '${_cards.length} Karten als Grundlage'
                : 'Noch zu wenig gelernte Karten (mindestens ${ErrorHuntScreen.minCards}) – erst ein bisschen '
                      'im Daily Quiz lernen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.inkMuted),
          ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            key: const ValueKey('hunt-start'),
            onPressed: hasKey && enough ? _start : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Jagd starten'),
          ),
        ),
      ],
    );
  }

  Widget _playing(AppColors c) {
    final s = _statements[_index];
    final answered = _answer != null;
    final right = answered && _answer == s.isTrue;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${_index + 1} / ${_statements.length}', style: TextStyle(color: c.inkMuted)),
              const Spacer(),
              if (_streak >= 2)
                Text(
                  'Serie ×$_streak',
                  style: TextStyle(color: c.good, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (_index + (answered ? 1 : 0)) / _statements.length, minHeight: 4),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: answered ? (right ? c.good : c.danger) : c.border, width: answered ? 2 : 1),
            ),
            child: MathText(
              s.text,
              key: const ValueKey('hunt-statement'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, height: 1.4, color: c.ink, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 16),
          if (answered)
            Container(
              key: const ValueKey('hunt-feedback'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: right ? c.goodSoft : c.dangerSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${right ? 'Richtig erkannt' : 'Daneben'} – die Aussage ${s.isTrue ? 'stimmt' : 'stimmt nicht'}.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: right ? c.good : c.danger),
                  ),
                  if (s.explanation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    MathText(s.explanation, style: TextStyle(color: c.ink, height: 1.4)),
                  ],
                ],
              ),
            ),
          const Spacer(),
          if (!answered)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('hunt-false'),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.dangerSoft,
                      foregroundColor: c.danger,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => _decide(false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Stimmt nicht'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('hunt-true'),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.goodSoft,
                      foregroundColor: c.good,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => _decide(true),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Stimmt'),
                  ),
                ),
              ],
            )
          else
            FilledButton(
              key: const ValueKey('hunt-next'),
              onPressed: _next,
              child: Text(_index + 1 >= _statements.length ? 'Auswertung' : 'Weiter'),
            ),
        ],
      ),
    );
  }

  Widget _done(AppColors c) {
    final missed = [
      for (final card in _cards)
        if (_missedCardIds.contains(card.id)) card,
    ];
    return ListView(
      key: const ValueKey('hunt-result'),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.travel_explore_rounded, size: 56, color: c.accent),
        const SizedBox(height: 12),
        Text(
          '$_correct von ${_statements.length} richtig erkannt',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Längste Serie: $_bestStreak',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.inkMuted),
        ),
        if (missed.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Hier hat es gehakt',
            style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
          ),
          const SizedBox(height: 6),
          for (final card in missed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• ${card.promptText}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.inkMuted, fontSize: 13),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('hunt-practice'),
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => PracticeScreen.cards(title: 'Fehlerjagd: nachüben', cards: missed),
              ),
            ),
            icon: const Icon(Icons.school_outlined),
            label: Text('Diese ${missed.length} Karte${missed.length == 1 ? '' : 'n'} üben'),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig')),
            const SizedBox(width: 10),
            FilledButton(key: const ValueKey('hunt-restart'), onPressed: _start, child: const Text('Neue Runde')),
          ],
        ),
      ],
    );
  }
}
