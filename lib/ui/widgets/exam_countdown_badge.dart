import 'package:flutter/material.dart';

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
    final days = daysUntilExam!;
    late final String label;
    late final Color color;
    if (days < 0) {
      label = 'Klausur vorbei';
      color = Colors.grey;
    } else if (days == 0) {
      label = 'Klausur heute!';
      color = Colors.red;
    } else if (days <= 3) {
      label = 'noch $days Tag${days == 1 ? '' : 'e'}';
      color = Colors.red;
    } else if (days <= 14) {
      label = 'noch $days Tage';
      color = Colors.orange;
    } else {
      label = 'noch $days Tage';
      color = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
