import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/concept.dart';
import '../../repositories/concept_repository.dart';
import '../../theme/app_colors.dart';

/// Nachbereiten-Speedrun: schneller Durchlauf durch ALLE Konzepte eines
/// Fachs (Titel zeigen -> selbst einschätzen, ob man die Erklärung parat
/// hätte -> aufdecken). Bewusst KEIN FSRS-Effekt (siehe FsrsService/
/// DailyQuizScreen) – das ist ein Verständnis-Check direkt nach dem
/// Nachbereiten, keine spaced-repetition-wirksame Wiederholung. Konzepte,
/// bei denen man selbst "nicht gewusst" angibt, landen in einer
/// "Vertiefen"-Runde: dieselbe Runde nochmal, aber NUR mit den Ausrutschern,
/// wiederholbar bis nichts mehr übrig bleibt.
class SpeedrunScreen extends StatefulWidget {
  const SpeedrunScreen({super.key, required this.moduleId, required this.moduleName});

  final String moduleId;
  final String moduleName;

  @override
  State<SpeedrunScreen> createState() => _SpeedrunScreenState();
}

class _SpeedrunScreenState extends State<SpeedrunScreen> {
  List<Concept> _queue = [];
  final List<Concept> _missed = [];
  int _index = 0;
  bool _showBack = false;
  bool _started = false;
  int _round = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<ConceptRepository>().loadForModule(widget.moduleId));
  }

  void _startRound(List<Concept> concepts) {
    setState(() {
      _queue = List.of(concepts)..shuffle();
      _missed.clear();
      _index = 0;
      _showBack = false;
      _started = true;
    });
  }

  void _grade(bool knew) {
    if (!knew) _missed.add(_queue[_index]);
    setState(() {
      _index += 1;
      _showBack = false;
    });
  }

  void _deepen() {
    final missedCopy = List<Concept>.of(_missed);
    setState(() => _round += 1);
    _startRound(missedCopy);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final concepts = context.watch<ConceptRepository>().forModule(widget.moduleId);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text('Speedrun · ${widget.moduleName}')),
      body: SafeArea(
        child: !_started
            ? _IntroView(count: concepts.length, onStart: () => _startRound(concepts))
            : _index >= _queue.length
                ? _RoundSummaryView(
                    round: _round,
                    total: _queue.length,
                    missed: _missed,
                    onDeepen: _missed.isEmpty ? null : _deepen,
                    onFinish: () => Navigator.of(context).pop(),
                  )
                : _ConceptCard(
                    concept: _queue[_index],
                    index: _index,
                    total: _queue.length,
                    round: _round,
                    showBack: _showBack,
                    onFlip: () => setState(() => _showBack = true),
                    onGrade: _grade,
                  ),
      ),
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({required this.count, required this.onStart});
  final int count;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_outlined, size: 56, color: c.accent),
            const SizedBox(height: 16),
            Text(
              count == 0
                  ? 'Noch keine Konzepte – entstehen im Nachbereiten-Modus.'
                  : '$count Konzept${count == 1 ? '' : 'e'} bereit. Du siehst jeweils nur den Titel, '
                      'schätzt dich selbst ein und deckst dann die Erklärung auf. Was du nicht '
                      'wusstest, kommt danach in eine Vertiefen-Runde.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted, height: 1.4),
            ),
            if (count > 0) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Speedrun starten'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConceptCard extends StatelessWidget {
  const _ConceptCard({
    required this.concept,
    required this.index,
    required this.total,
    required this.round,
    required this.showBack,
    required this.onFlip,
    required this.onGrade,
  });

  final Concept concept;
  final int index;
  final int total;
  final int round;
  final bool showBack;
  final VoidCallback onFlip;
  final ValueChanged<bool> onGrade;

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
                  value: (index + 1) / total,
                  minHeight: 6,
                  backgroundColor: c.border,
                  valueColor: AlwaysStoppedAnimation(c.accent),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                round == 1 ? '${index + 1} / $total' : 'Vertiefen (Runde $round) · ${index + 1} / $total',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: showBack ? null : onFlip,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        concept.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.45),
                      ),
                      if (showBack) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1, color: c.border),
                        ),
                        Text(
                          concept.explanation,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, height: 1.6, color: c.inkMuted),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        Text('Zum Aufdecken tippen', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showBack)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            child: Row(
              children: [
                Expanded(
                  child: _GradeButton(
                    label: 'Nicht gewusst',
                    fg: c.danger,
                    bg: c.dangerSoft,
                    onTap: () => onGrade(false),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _GradeButton(
                    label: 'Gewusst',
                    fg: c.good,
                    bg: c.goodSoft,
                    onTap: () => onGrade(true),
                  ),
                ),
              ],
            ),
          )
        else
          const SizedBox(height: 30),
      ],
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({required this.label, required this.fg, required this.bg, required this.onTap});
  final String label;
  final Color fg;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}

class _RoundSummaryView extends StatelessWidget {
  const _RoundSummaryView({
    required this.round,
    required this.total,
    required this.missed,
    required this.onDeepen,
    required this.onFinish,
  });

  final int round;
  final int total;
  final List<Concept> missed;
  final VoidCallback? onDeepen;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final knew = total - missed.length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              missed.isEmpty ? Icons.celebration_outlined : Icons.flag_outlined,
              size: 56,
              color: missed.isEmpty ? c.good : c.warn,
            ),
            const SizedBox(height: 16),
            Text(
              round == 1
                  ? 'Runde abgeschlossen: $knew von $total gewusst.'
                  : 'Vertiefen-Runde $round abgeschlossen: $knew von $total gewusst.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (missed.isNotEmpty) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Zu vertiefen:', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
              ),
              const SizedBox(height: 6),
              ...missed.map((concept) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('• ${concept.title}', style: TextStyle(fontSize: 13, color: c.ink)),
                    ),
                  )),
            ],
            const SizedBox(height: 24),
            if (onDeepen != null)
              FilledButton.icon(
                onPressed: onDeepen,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('Vertiefen starten (${missed.length})'),
              ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onFinish, child: const Text('Fertig')),
          ],
        ),
      ),
    );
  }
}
