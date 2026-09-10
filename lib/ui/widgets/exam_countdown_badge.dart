import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Kleines Badge, das die verbleibenden Tage bis zur Klausur anzeigt und
/// bei Klausuren in den nächsten 3 Tagen (Wiederholungs-Endspurt) warnt.
class ExamCountdownBadge extends StatelessWidget {
  const ExamCountdownBadge({super.key, required this.daysUntilExam});

  final int? daysUntilExam;

  @override
  Widget build(BuildContext context) {
    if (daysUntilExam == null) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    final days = daysUntilExam!;
    late final String label;
    late final Color fg;
    late final Color bg;
    if (days < 0) {
      label = 'Klausur vorbei';
      fg = c.inkMuted;
      bg = c.surfaceAlt;
    } else if (days == 0) {
      label = 'Klausur heute!';
      fg = c.danger;
      bg = c.dangerSoft;
    } else if (days <= 3) {
      label = 'noch $days Tag${days == 1 ? '' : 'e'}';
      fg = c.danger;
      bg = c.dangerSoft;
    } else if (days <= 14) {
      label = 'noch $days Tage';
      fg = c.warn;
      bg = c.warnSoft;
    } else {
      label = 'noch $days Tage';
      fg = c.good;
      bg = c.goodSoft;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}
