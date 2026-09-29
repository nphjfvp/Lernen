import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../services/ai_service.dart';

/// Auswahl eines Fragetyps beim Erstellen: "KI entscheidet" (null) oder einer
/// der wählbaren Typen (siehe [AiService.selectablePageQuestionTypes]). Wird
/// im Fenster "Frage erstellen" je Stufe und in den Einstellungen für die
/// Vorgaben je Stufe verwendet.
class QuestionTypeDropdown extends StatelessWidget {
  const QuestionTypeDropdown({super.key, required this.value, required this.onChanged});

  final QuestionType? value;

  /// null = nicht änderbar (ausgegraut).
  final ValueChanged<QuestionType?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<QuestionType?>(
      isExpanded: true,
      value: value,
      hint: const Text('KI entscheidet', style: TextStyle(fontSize: 13.5)),
      disabledHint: Text(value?.label ?? 'KI entscheidet', style: const TextStyle(fontSize: 13.5)),
      onChanged: onChanged,
      items: [
        const DropdownMenuItem<QuestionType?>(
          value: null,
          child: Text('KI entscheidet', style: TextStyle(fontSize: 13.5)),
        ),
        for (final t in AiService.selectablePageQuestionTypes)
          DropdownMenuItem<QuestionType?>(
            value: t,
            child: Text(t.label, style: const TextStyle(fontSize: 13.5)),
          ),
      ],
    );
  }
}
