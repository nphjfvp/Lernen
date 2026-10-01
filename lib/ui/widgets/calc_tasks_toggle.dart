import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repositories/settings_repository.dart';
import '../../theme/app_colors.dart';

/// Schalter "Rechenaufgaben" für Daily Quiz, Üben und Sprint: aus,
/// wenn gerade kein Taschenrechner zur Hand ist (Handy im Bett), an am
/// Schreibtisch. Gilt nur auf diesem Gerät (siehe AppSettings.includeCalcTasks).
/// [note] ergänzt eine kurze Zeile, z.B. wie viele zurückgestellt sind.
class CalcTasksToggle extends StatelessWidget {
  const CalcTasksToggle({super.key, this.onChanged, this.note});

  /// Nach dem Umschalten (der Wert ist dann schon gespeichert).
  final ValueChanged<bool>? onChanged;
  final String? note;

  /// Der aktuelle Wert ohne Abhängigkeit (für Logik außerhalb von build()).
  static bool includeOf(BuildContext context) =>
      context.read<SettingsRepository?>()?.settings.includeCalcTasks ?? true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final repo = context.watch<SettingsRepository?>();
    final include = repo?.settings.includeCalcTasks ?? true;
    return Row(
      children: [
        FilterChip(
          key: const ValueKey('calc-tasks-toggle'),
          avatar: Icon(include ? Icons.calculate : Icons.calculate_outlined, size: 18),
          label: Text(include ? 'Rechenaufgaben: an' : 'Rechenaufgaben: aus'),
          selected: include,
          showCheckmark: false,
          tooltip: include
              ? 'Aufgaben mit Taschenrechner kommen dran – antippen, um sie für später aufzuheben.'
              : 'Aufgaben mit Taschenrechner werden aufgehoben und später bevorzugt nachgeholt.',
          onSelected: repo == null
              ? null
              : (value) async {
                  await repo.update(repo.settings.copyWith(includeCalcTasks: value));
                  onChanged?.call(value);
                },
        ),
        if (note != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note!,
              key: const ValueKey('calc-tasks-note'),
              style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
