import 'package:flutter/material.dart';

import '../../services/stage_gate_service.dart';

/// Wert von [pickStageLevel] für "aus dem Fragetyp ableiten".
const int stageLevelAuto = -1;

/// Fragt eine Schwierigkeitsstufe ab (siehe Flashcard.stageLevel): 0–2 für
/// Leicht/Mittel/Schwer, [stageLevelAuto] für "automatisch aus dem
/// Fragetyp", null bei Abbruch.
Future<int?> pickStageLevel(BuildContext context, {int? current, String title = 'Schwierigkeitsstufe'}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Von Fragen, die zusammengehören (gleiches Konzept), kommt erst Leicht dran, '
            'dann Mittel, dann Schwer – jeweils erst, wenn die Stufe davor sitzt.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        for (final level in StageLevel.values)
          SimpleDialogOption(
            key: ValueKey('stage-option-${level.name}'),
            onPressed: () => Navigator.of(ctx).pop(level.index),
            child: Row(
              children: [
                Icon(current == level.index ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
                const SizedBox(width: 10),
                Text(level.label),
              ],
            ),
          ),
        SimpleDialogOption(
          key: const ValueKey('stage-option-auto'),
          onPressed: () => Navigator.of(ctx).pop(stageLevelAuto),
          child: Row(
            children: [
              Icon(current == null ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
              const SizedBox(width: 10),
              const Text('Automatisch (aus dem Fragetyp)'),
            ],
          ),
        ),
      ],
    ),
  );
}
