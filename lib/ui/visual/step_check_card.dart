import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/visual_lesson.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';

/// Prüffrage am Ende eines Lektionsschritts: erst erklärt, dann geprüft. Bei
/// einer falschen Wahl steht der Denkfehler dieser Option da, und
/// [onRepair] lässt den Schritt anders erklären – bevor darauf aufgebaut wird.
class StepCheckCard extends StatefulWidget {
  const StepCheckCard({super.key, required this.check, this.onRepair});

  final StepCheck check;

  /// Bekommt eine fertige Bitte an die KI („Ich habe … gewählt, erklär den
  /// Schritt anders“).
  final void Function(String request)? onRepair;

  @override
  State<StepCheckCard> createState() => _StepCheckCardState();
}

class _StepCheckCardState extends State<StepCheckCard> {
  late final List<int> _order = List.generate(widget.check.options.length, (i) => i)..shuffle(Random());
  int? _chosen;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final check = widget.check;
    final chosen = _chosen;
    final answered = chosen != null;
    final right = answered && check.options[chosen].correct;
    return Container(
      key: const ValueKey('step-check'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: answered ? (right ? c.good : c.danger) : c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: !_open
          ? Row(
              children: [
                Icon(Icons.fact_check_outlined, color: c.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Hat der Schritt gesessen?', style: TextStyle(fontSize: 14, color: c.ink))),
                FilledButton.tonal(
                  key: const ValueKey('step-check-open'),
                  onPressed: () => setState(() => _open = true),
                  child: const Text('Prüffrage'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MathText(check.question, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
                const SizedBox(height: 10),
                for (final i in _order)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: OutlinedButton(
                      key: ValueKey('step-check-option-$i'),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        backgroundColor: !answered
                            ? null
                            : check.options[i].correct
                            ? c.goodSoft
                            : (i == chosen ? c.dangerSoft : null),
                      ),
                      onPressed: answered ? null : () => setState(() => _chosen = i),
                      child: MathText(check.options[i].text, style: TextStyle(fontSize: 14, color: c.ink)),
                    ),
                  ),
                if (answered) ...[
                  const SizedBox(height: 6),
                  Text(
                    right ? 'Richtig – darauf kannst du aufbauen.' : 'Nicht ganz – das sollte sitzen, bevor es weitergeht.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: right ? c.good : c.danger),
                  ),
                  if (!right && check.options[chosen].why.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    MathText(
                      'Warum das nicht passt: ${check.options[chosen].why}',
                      key: const ValueKey('step-check-why'),
                      style: TextStyle(fontSize: 13, color: c.ink),
                    ),
                  ],
                  if (check.explanation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    MathText(check.explanation, style: TextStyle(fontSize: 13, color: c.inkMuted)),
                  ],
                  if (!right && widget.onRepair != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TextButton.icon(
                        key: const ValueKey('step-check-repair'),
                        onPressed: () => widget.onRepair!(
                          'Bei der Prüffrage „${check.question}“ habe ich „${check.options[chosen].text}“ gewählt – '
                          'das war falsch. Erklär mir diesen Schritt bitte noch einmal anders, genau an meinem Denkfehler, '
                          'in kleinen Schritten.',
                        ),
                        icon: const Icon(Icons.healing_outlined, size: 18),
                        label: const Text('Schritt anders erklären'),
                      ),
                    ),
                  if (!right)
                    TextButton(
                      key: const ValueKey('step-check-retry'),
                      onPressed: () => setState(() {
                        _chosen = null;
                        _order.shuffle(Random());
                      }),
                      child: const Text('Nochmal versuchen'),
                    ),
                ],
              ],
            ),
    );
  }
}
