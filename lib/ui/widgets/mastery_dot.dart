import 'package:flutter/material.dart';

import '../../services/mastery_service.dart';
import '../../theme/app_colors.dart';

/// Einheitliche Ampel-Farbe für eine [MasteryLevel]-Stufe, wiederverwendet
/// überall dort, wo der FSRS-Wissensstand einer Karte sichtbar gemacht wird
/// (FlashcardListScreen, ModuleDetailScreen, StatsScreen).
Color masteryColor(AppColors c, MasteryLevel level) => switch (level) {
      MasteryLevel.neu => c.inkMuted,
      MasteryLevel.red => c.danger,
      MasteryLevel.yellow => c.warn,
      MasteryLevel.green => c.good,
    };

/// Kleiner farbiger Punkt als Ampel-Indikator einer einzelnen Karte.
class MasteryDot extends StatelessWidget {
  const MasteryDot({super.key, required this.level, this.size = 10});

  final MasteryLevel level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: level.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: masteryColor(c, level), shape: BoxShape.circle),
      ),
    );
  }
}
