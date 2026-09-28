import 'package:flutter/material.dart';

import '../../services/mastery_service.dart';
import '../../theme/app_colors.dart';
import 'mastery_dot.dart';

/// Anteile der gelernten Karten eines Fachs nach Ampel (siehe
/// MasteryService.breakdown), in Prozent – Grundlage für [MasteryBar].
({int green, int yellow, int red, int learned, int neu}) masteryShares(Map<MasteryLevel, int> breakdown) {
  final green = breakdown[MasteryLevel.green] ?? 0;
  final yellow = breakdown[MasteryLevel.yellow] ?? 0;
  final red = breakdown[MasteryLevel.red] ?? 0;
  final learned = green + yellow + red;
  if (learned == 0) return (green: 0, yellow: 0, red: 0, learned: 0, neu: breakdown[MasteryLevel.neu] ?? 0);
  final g = (green * 100 / learned).round();
  final y = (yellow * 100 / learned).round();
  return (green: g, yellow: y, red: 100 - g - y, learned: learned, neu: breakdown[MasteryLevel.neu] ?? 0);
}

/// Ampel eines Fachs als Balken: grün/gelb/rot anteilig an den bereits
/// gelernten Karten, darunter die Prozente (wie im Design-Entwurf).
class MasteryBar extends StatelessWidget {
  const MasteryBar({super.key, required this.breakdown, this.showLabels = true});

  final Map<MasteryLevel, int> breakdown;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shares = masteryShares(breakdown);
    if (shares.learned == 0) {
      return Text(
        shares.neu == 0 ? 'Noch keine Karten' : 'Noch nichts gelernt · ${shares.neu} neu',
        style: TextStyle(fontSize: 11.5, color: c.inkMuted),
      );
    }
    final segments = [
      (level: MasteryLevel.green, percent: shares.green),
      (level: MasteryLevel.yellow, percent: shares.yellow),
      (level: MasteryLevel.red, percent: shares.red),
    ].where((s) => s.percent > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Row(
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: segments[i].percent,
                    child: ColoredBox(color: masteryColor(c, segments[i].level)),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showLabels) ...[
          const SizedBox(height: 5),
          Text(
            [
              '${shares.green} % gut',
              '${shares.yellow} % mittel',
              '${shares.red} % schwach',
              if (shares.neu > 0) '${shares.neu} neu',
            ].join(' · '),
            style: TextStyle(fontSize: 11.5, color: c.inkMuted),
          ),
        ],
      ],
    );
  }
}
