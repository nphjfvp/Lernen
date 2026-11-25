import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/answer_signals.dart';
import '../../services/think_aloud_service.dart';
import '../../theme/app_colors.dart';
import '../daily/card_review_mixin.dart';
import '../widgets/math_text.dart';
import 'explain_chat.dart';

/// Modus „Laut denken“: Fragen aus den gewählten Fächern, zu denen man seinen
/// Gedankengang spricht (Diktieren über die Tastatur) oder tippt. Die KI liest
/// den WEG, nicht nur das Ergebnis: sie sagt, was trägt und wo der Weg
/// abbiegt, gibt den kleinsten nötigen Anstoß (Hilfe-Leiter) und zeigt die
/// Lösung erst, wenn man sie gefunden hat oder aufgibt. Verbucht wird wie
/// jede Antwort (FSRS, Ampel, Antwort-Protokoll).
class ThinkAloudScreen extends StatefulWidget {
  const ThinkAloudScreen({super.key, this.moduleIds});

  /// Vorauswahl (z.B. aus einem Fach heraus); null = alle Fächer.
  final Set<String>? moduleIds;

  @override
  State<ThinkAloudScreen> createState() => _ThinkAloudScreenState();
}

class _ThinkAloudScreenState extends State<ThinkAloudScreen> with CardReviewMixin {
  static const _counts = [5, 10, 20];

  late final Set<String> _selected =
      {...(widget.moduleIds ?? {for (final m in context.read<ModuleRepository>().modules) m.id})};
  int _count = 10;
  bool _loading = false;
  List<Flashcard>? _queue;
  int _index = 0;

  final _field = TextEditingController();
  List<({bool user, String text})> _turns = [];
  bool _busy = false;
  String? _error;
  int _maxLevel = 0;
  bool _done = false;
  bool _correct = false;
  ThinkError _lastError = ThinkError.none;
  String _read = '';

  int _solved = 0;
  int _solvedWithHelp = 0;
  int _open = 0;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final cardsRepo = context.read<FlashcardRepository>();
    final units = context.read<LectureUnitRepository?>();
    setState(() => _loading = true);
    final cards = await cardsRepo.loadAll();
    final covered = units == null ? const <String, bool>{} : await units.loadAllCoveredById();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _queue = ThinkAloudService.pick(cards, moduleIds: _selected, unitCoveredById: covered, count: _count);
      _index = 0;
    });
  }

  Future<void> _send() async {
    final text = _field.text.trim();
    if (text.isEmpty || _busy) return;
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return;
    final card = _queue![_index];
    final turns = [..._turns, (user: true, text: text)];
    setState(() {
      _turns = turns;
      _busy = true;
      _error = null;
      _field.clear();
    });
    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.effectiveHelpModelId);
      final verdict = await ai.assessThinking(
        question: ThinkAloudService.questionText(card),
        correctAnswer: card.answerSummary,
        turns: turns,
      );
      if (!mounted) return;
      setState(() {
        _turns = [...turns, (user: false, text: verdict.reply)];
        if (verdict.level > _maxLevel) _maxLevel = verdict.level;
        if (verdict.error != ThinkError.none) _lastError = verdict.error;
        if (verdict.read.isNotEmpty) _read = verdict.read;
      });
      if (verdict.status == ThinkStatus.correct) await _conclude(correct: true);
    } catch (e) {
      if (mounted) setState(() => _error = e is AiServiceException ? e.message : 'Fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _conclude({required bool correct}) async {
    if (_done) return;
    final card = _queue![_index];
    setState(() {
      _done = true;
      _correct = correct;
      if (!correct) {
        _open++;
      } else if (_maxLevel >= 2) {
        _solvedWithHelp++;
      } else {
        _solved++;
      }
    });
    await recordReview(
      card,
      isCorrect: correct,
      signals: AnswerSignals(hintLevel: _maxLevel, dontKnow: !correct),
    );
  }

  void _next() {
    setState(() {
      _index++;
      _turns = [];
      _field.clear();
      _busy = false;
      _error = null;
      _maxLevel = 0;
      _done = false;
      _correct = false;
      _lastError = ThinkError.none;
      _read = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    final Widget body;
    if (!(context.read<SettingsRepository?>()?.settings.hasApiKey ?? false)) {
      body = const _Centered(
        text: 'Laut denken braucht die KI: Trag in den Einstellungen deinen OpenRouter-Key ein.',
      );
    } else if (queue == null) {
      body = _setup(context);
    } else if (queue.isEmpty) {
      body = const _Centered(
        text: 'In den gewählten Fächern gibt es gerade keine passenden Fragen (behandelte Einheiten, offene '
            'Fragetypen wie Karteikarte, Freitext, Lückentext, Auswahl).',
      );
    } else if (_index >= queue.length) {
      body = _Centered(
        text: 'Fertig: $_solved selbst gelöst, $_solvedWithHelp mit Anstoß, $_open noch offen. '
            'Alles ist für Ampel und Wiederholung verbucht.',
      );
    } else {
      body = _question(context, queue[_index], queue.length);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Laut denken')),
      body: SafeArea(child: body),
    );
  }

  Widget _setup(BuildContext context) {
    final c = context.colors;
    final modules = context.read<ModuleRepository>().modules;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Du bekommst Fragen und sagst oder schreibst dazu einfach, was dir durch den Kopf geht – auch Unsicheres '
          'und Halbfertiges. Die KI liest deinen Weg, sagt dir, wo er trägt und wo er abbiegt, und gibt nur den '
          'kleinsten nötigen Anstoß. Die Lösung kommt erst am Ende.',
          style: TextStyle(fontSize: 14.5, height: 1.45, color: c.ink),
        ),
        const SizedBox(height: 18),
        Text('FÄCHER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.inkMuted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in modules)
              FilterChip(
                key: ValueKey('think-module-${m.id}'),
                label: Text(m.name),
                selected: _selected.contains(m.id),
                onSelected: (on) => setState(() => on ? _selected.add(m.id) : _selected.remove(m.id)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text('WIE VIELE FRAGEN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.inkMuted)),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: [for (final n in _counts) ButtonSegment(value: n, label: Text('$n'))],
          selected: {_count},
          onSelectionChanged: (s) => setState(() => _count = s.first),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('think-start'),
          onPressed: _selected.isEmpty || _loading ? null : _start,
          icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.record_voice_over_outlined),
          label: const Text('Los geht’s'),
        ),
        const SizedBox(height: 12),
        Text(
          'Zuerst kommt, was fällig ist, dann Wackeliges, dann Neues – Fächer abwechselnd.',
          style: TextStyle(fontSize: 12, color: c.inkMuted),
        ),
      ],
    );
  }

  Widget _question(BuildContext context, Flashcard card, int total) {
    final c = context.colors;
    final moduleName = context.read<ModuleRepository>().byId(card.moduleId)?.name ?? '';
    final image = card.imageBase64;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: ValueKey('think-q-$_index'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            children: [
              LinearProgressIndicator(value: (_index + 1) / total, minHeight: 5),
              const SizedBox(height: 8),
              Text('Frage ${_index + 1} von $total${moduleName.isEmpty ? '' : ' · $moduleName'}',
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((image ?? '').isNotEmpty) ...[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: Image.memory(base64Decode(image!), fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 10),
                    ],
                    MathText(
                      ThinkAloudService.questionText(card),
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final t in _turns) _Bubble(user: t.user, text: t.text),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_error!, style: TextStyle(fontSize: 12.5, color: c.danger)),
                ),
              if (_done) _result(context, card),
            ],
          ),
        ),
        if (!_done) _input(context) else _nextBar(context),
      ],
    );
  }

  Widget _input(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('think-field'),
            controller: _field,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _turns.isEmpty
                  ? 'Denk laut: Was fällt dir ein? Wie gehst du vor? Wo bist du unsicher?'
                  : 'Weiterdenken …',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '🎤 Sprechen statt tippen: Mikrofon auf der Tastatur (Handy, iPad) bzw. Win + H (Windows).',
            style: TextStyle(fontSize: 11.5, color: c.inkMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                key: const ValueKey('think-give-up'),
                onPressed: _busy ? null : () => _conclude(correct: false),
                child: const Text('Lösung zeigen'),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const ValueKey('think-send'),
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Gedanken schicken'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _result(BuildContext context, Flashcard card) {
    final c = context.colors;
    final misconception = !_correct && _lastError == ThinkError.misconception;
    return Container(
      key: const ValueKey('think-result'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _correct ? c.goodSoft : c.warnSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _correct
                ? (_maxLevel >= 2 ? 'Gelöst – mit Anstoß (${HintLadder.costOf(_maxLevel)}).' : 'Selbst gelöst.')
                : 'Noch offen – hier ist die Lösung.',
            style: TextStyle(fontWeight: FontWeight.w700, color: _correct ? c.good : c.warn),
          ),
          const SizedBox(height: 6),
          MathText('Lösung: ${card.answerSummary}', style: TextStyle(fontSize: 13.5, color: c.ink)),
          if (_read.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Dein Weg: $_read', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
          ],
          if (misconception) ...[
            const SizedBox(height: 6),
            Text(
              'Das klingt nach einer Fehlvorstellung, nicht nur nach einer Lücke – frag ruhig unten nach.',
              style: TextStyle(fontSize: 12.5, color: c.ink),
            ),
          ],
          ExplainChat(
            question: ThinkAloudService.questionText(card),
            correctAnswer: card.answerSummary,
            userAnswer: [for (final t in _turns) if (t.user) t.text].join('\n'),
            wasCorrect: _correct,
          ),
        ],
      ),
    );
  }

  Widget _nextBar(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('think-next'),
            onPressed: _next,
            child: const Text('Nächste Frage'),
          ),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.user, required this.text});

  final bool user;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: user ? c.accentSoft : c.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: MathText(text, style: TextStyle(fontSize: 14, height: 1.4, color: c.ink)),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.4)),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Zurück')),
            ],
          ),
        ),
      );
}
