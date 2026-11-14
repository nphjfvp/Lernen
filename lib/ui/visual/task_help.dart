import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/flashcard.dart';
import '../../services/fsrs_service.dart';
import '../../theme/app_colors.dart';
import '../daily/question_answer_view.dart';
import 'calculator_sim.dart';
import 'worked_solution_screen.dart';

/// Eine Aufgabe zum Lernen (Daily Quiz, Üben, Der Reihe nach) mit Hilfen in
/// der Kopfzeile: Vorrechnen an der Tafel (auch Rezept und sokratisch) und
/// ein Taschenrechner zum Auf- und Zuklappen. Wer vor dem Lösen vorrechnen
/// lässt, bekommt die Aufgabe ehrlich als „Nochmal“ verbucht – außer er hat
/// sokratisch jeden Schritt selbst gewusst.
///
/// Rechenweg-Aufgaben haben Vorrechnen und Taschenrechner schon in ihrer
/// eigenen Ansicht – dort zeigt die Kopfzeile nur [info] und [actions].
class QuestionWithHelp extends StatefulWidget {
  const QuestionWithHelp({
    super.key,
    required this.card,
    required this.isNew,
    required this.onComplete,
    this.info,
    this.actions = const [],
    this.onImageEdited,
    this.onSkip,
    this.canGiveUp = false,
  });

  final Flashcard card;
  final bool isNew;
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;

  /// Links in der Kopfzeile (z.B. „Aufgabe 3 von 12“).
  final Widget? info;

  /// Rechts in der Kopfzeile, nach den Hilfen.
  final List<Widget> actions;
  final Future<void> Function(Uint8List? bytes)? onImageEdited;
  final VoidCallback? onSkip;
  final bool canGiveUp;

  /// Taschenrechner offen – bleibt für die Sitzung, auch über Aufgaben hinweg.
  static bool calculatorOpen = false;

  @override
  State<QuestionWithHelp> createState() => _QuestionWithHelpState();
}

class _QuestionWithHelpState extends State<QuestionWithHelp> {
  bool _watched = false;

  bool get _hasOwnHelp => widget.card.type == QuestionType.steps;

  Future<void> _openWorked() async {
    final card = widget.card;
    final selfSolved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkedSolutionScreen(
          moduleId: card.moduleId,
          problem: card.front,
          reference: WorkedSolutionScreen.referenceFor(card),
          image: WorkedSolutionScreen.imageOf(card),
          cardId: card.id,
        ),
      ),
    );
    if (!mounted) return;
    if (selfSolved == true) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Jeden Schritt selbst gewusst – das zählt nicht als Hilfe.')));
      return;
    }
    setState(() => _watched = true);
  }

  void _complete({Grade? selfGrade, bool? isCorrect}) {
    if (_watched) {
      widget.onComplete(selfGrade: Grade.again, isCorrect: false);
      return;
    }
    widget.onComplete(selfGrade: selfGrade, isCorrect: isCorrect);
  }

  void _copy(String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Ergebnis kopiert: $value – zum Einfügen ins Antwortfeld'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = QuestionWithHelp.calculatorOpen && !_hasOwnHelp;
    final question = QuestionAnswerView(
      card: widget.card,
      isNew: widget.isNew,
      canGiveUp: widget.canGiveUp,
      onSkip: widget.onSkip,
      onImageEdited: widget.onImageEdited,
      onComplete: _complete,
    );
    final calculator = CalculatorSim(onUseResult: _copy);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 8, 0),
          child: Row(
            children: [
              Expanded(child: widget.info ?? const SizedBox.shrink()),
              if (!_hasOwnHelp) ...[
                IconButton(
                  key: const ValueKey('help-worked'),
                  tooltip:
                      'An der Tafel vorrechnen lassen – auch als Rezept oder „Selbst überlegen“ '
                      '(vor dem Lösen zählt es als „Nochmal“)',
                  onPressed: _openWorked,
                  icon: Icon(Icons.functions, color: c.accent),
                ),
                IconButton(
                  key: const ValueKey('help-calc'),
                  tooltip: open ? 'Taschenrechner ausblenden' : 'Taschenrechner',
                  isSelected: open,
                  onPressed: () => setState(() => QuestionWithHelp.calculatorOpen = !QuestionWithHelp.calculatorOpen),
                  icon: const Icon(Icons.calculate_outlined),
                  selectedIcon: Icon(Icons.calculate, color: c.accent),
                ),
              ],
              ...widget.actions,
            ],
          ),
        ),
        if (_watched)
          Container(
            key: const ValueKey('help-watched'),
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 2, 20, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'Vorgerechnet angesehen – rechne sie jetzt selbst nach. Sie zählt als „Nochmal“ und kommt bald '
              'wieder, dann ohne Hilfe.',
              style: TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              if (!open) return question;
              // Breit: Rechner daneben; schmal: aufziehbar über der Aufgabe.
              if (box.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: question),
                    SizedBox(
                      width: 380,
                      child: SingleChildScrollView(
                        key: const ValueKey('help-calc-panel'),
                        padding: const EdgeInsets.fromLTRB(0, 8, 20, 24),
                        child: calculator,
                      ),
                    ),
                  ],
                );
              }
              return Stack(
                children: [
                  Positioned.fill(child: question),
                  DraggableScrollableSheet(
                    key: const ValueKey('help-calc-panel'),
                    initialChildSize: 0.62,
                    minChildSize: 0.12,
                    maxChildSize: 0.96,
                    builder: (context, scroll) => Material(
                      color: c.surface,
                      elevation: 8,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: ListView(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Center(
                                  child: Container(
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('help-calc-close'),
                                tooltip: 'Ausblenden',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() => QuestionWithHelp.calculatorOpen = false),
                                icon: const Icon(Icons.close, size: 20),
                              ),
                            ],
                          ),
                          Center(
                            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: calculator),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
