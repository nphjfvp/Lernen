import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/weakness_service.dart';
import '../../theme/app_colors.dart';
import '../practice/practice_screen.dart';
import '../widgets/mastery_dot.dart';

/// Fehlertagebuch: die Karten, mit denen man sich gerade am schwersten tut
/// (siehe WeaknessService), fachübergreifend oder je Fach – mit Grund,
/// aufklappbarer Lösung, "Diese üben" und optional einer KI-Analyse der
/// gemeinsamen Muster.
class WeaknessScreen extends StatefulWidget {
  const WeaknessScreen({super.key});

  @override
  State<WeaknessScreen> createState() => _WeaknessScreenState();
}

class _WeaknessScreenState extends State<WeaknessScreen> {
  /// Höchstens so viele Karten auf einmal üben bzw. der KI zeigen.
  static const _batchSize = 20;

  List<WeakCard>? _all;
  String? _moduleFilter;
  String? _analysis;
  bool _analysisLoading = false;
  String? _analysisError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final cards = await context.read<FlashcardRepository>().loadAll();
    if (!mounted) return;
    setState(() => _all = WeaknessService().rank(cards));
  }

  List<WeakCard> get _visible {
    final all = _all ?? const [];
    final filter = _moduleFilter;
    return filter == null ? all : all.where((w) => w.card.moduleId == filter).toList();
  }

  Future<void> _practice() async {
    final cards = _visible.take(_batchSize).map((w) => w.card).toList();
    if (cards.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PracticeScreen.cards(title: 'Schwachstellen', cards: cards),
    ));
    if (mounted) await _load();
  }

  Future<void> _analyze() async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return;
    setState(() {
      _analysisLoading = true;
      _analysisError = null;
    });
    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final items = [
        for (final w in _visible.take(_batchSize))
          (
            question: w.card.front,
            answer: w.card.answerSummary.isNotEmpty ? w.card.answerSummary : w.card.back,
            reasons: w.reasons.join(', '),
          ),
      ];
      final text = await ai.analyzeWeaknesses(items);
      if (mounted) setState(() => _analysis = text);
    } catch (e) {
      if (mounted) setState(() => _analysisError = e is AiServiceException ? e.message : 'Analyse fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _analysisLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = _all;
    final modules = context.watch<ModuleRepository>();
    final hasApiKey = context.watch<SettingsRepository>().settings.hasApiKey;
    final visible = _visible;
    final moduleIds = {for (final w in all ?? const <WeakCard>[]) w.card.moduleId};

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Schwachstellen')),
      body: SafeArea(
        child: all == null
            ? const Center(child: CircularProgressIndicator())
            : all.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Keine Schwachstellen – bisher wurde keine gelernte Karte vergessen. 🎉',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.inkMuted),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                      children: [
                        Text(
                          '${visible.length} Karte${visible.length == 1 ? '' : 'n'}, mit denen du dich gerade '
                          'schwertust – sortiert nach Dringlichkeit (wie oft vergessen, zuletzt falsch, Ampel rot).',
                          style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
                        ),
                        if (moduleIds.length > 1) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Alle Fächer'),
                                selected: _moduleFilter == null,
                                onSelected: (_) => setState(() {
                                  _moduleFilter = null;
                                  _analysis = null;
                                }),
                              ),
                              for (final id in moduleIds)
                                ChoiceChip(
                                  label: Text(modules.byId(id)?.name ?? 'Fach'),
                                  selected: _moduleFilter == id,
                                  onSelected: (_) => setState(() {
                                    _moduleFilter = id;
                                    _analysis = null;
                                  }),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: visible.isEmpty ? null : _practice,
                          icon: const Icon(Icons.fitness_center_rounded),
                          label: Text('Die ${visible.length.clamp(0, _batchSize)} schwächsten üben'),
                        ),
                        if (hasApiKey) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _analysisLoading || visible.isEmpty ? null : _analyze,
                            icon: _analysisLoading
                                ? const SizedBox(
                                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.insights_rounded),
                            label: const Text('KI: Muster erkennen'),
                          ),
                        ],
                        if (_analysisError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_analysisError!, style: TextStyle(fontSize: 12, color: c.danger)),
                          ),
                        if (_analysis != null)
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(14),
                            decoration:
                                BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14)),
                            child: SelectableText(_analysis!,
                                style: TextStyle(fontSize: 13.5, height: 1.45, color: c.ink)),
                          ),
                        const SizedBox(height: 20),
                        for (final w in visible)
                          _WeakCardTile(weak: w, moduleName: modules.byId(w.card.moduleId)?.name ?? ''),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _WeakCardTile extends StatelessWidget {
  const _WeakCardTile({required this.weak, required this.moduleName});

  final WeakCard weak;
  final String moduleName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = weak.card;
    final answer = card.answerSummary.isNotEmpty ? card.answerSummary : card.back;
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
            leading: MasteryDot(level: weak.level),
            title: Text(card.front, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              [if (moduleName.isNotEmpty) moduleName, card.type.label, ...weak.reasons].join(' · '),
              style: TextStyle(fontSize: 11.5, color: c.inkMuted),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lösung', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
              const SizedBox(height: 4),
              SelectableText(answer, style: const TextStyle(fontSize: 13.5, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}
