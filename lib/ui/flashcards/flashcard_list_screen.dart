import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../theme/app_colors.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/edit_text_dialog.dart';

/// Listet alle Karteikarten eines Fachs auf – zum gezielten Bearbeiten oder
/// Löschen einzelner Karten, unabhängig vom Daily-Quiz-Wiederholungsflow
/// (dort sieht man immer nur die jeweils fällige Karte, keine Übersicht).
class FlashcardListScreen extends StatelessWidget {
  const FlashcardListScreen({super.key, required this.moduleId, required this.moduleName});

  final String moduleId;
  final String moduleName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cards = context.watch<FlashcardRepository>().forModule(moduleId);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text('Karteikarten · $moduleName')),
      body: cards.isEmpty
          ? Center(child: Text('Noch keine Karteikarten.', style: TextStyle(color: c.inkMuted)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: cards.length,
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FlashcardTile(card: cards[i]),
              ),
            ),
    );
  }
}

class _FlashcardTile extends StatelessWidget {
  const _FlashcardTile({required this.card});
  final Flashcard card;

  Future<void> _edit(BuildContext context) async {
    final result = await editTwoFieldsDialog(
      context,
      title: 'Karteikarte bearbeiten',
      label1: 'Vorderseite',
      initial1: card.front,
      label2: 'Rückseite',
      initial2: card.back,
    );
    if (result == null || !context.mounted) return;
    final (front, back) = result;
    await context.read<FlashcardRepository>().update(card.copyWithText(front: front, back: back));
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirmDelete(
      context,
      title: 'Karteikarte löschen?',
      message: 'Diese Karteikarte wird endgültig gelöscht.',
    );
    if (ok && context.mounted) {
      await context.read<FlashcardRepository>().delete(card.id, card.moduleId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statusParts = [
      card.type.label,
      card.reps == 0 ? 'Neu' : 'fällig ${_formatDate(card.due)}',
      if (card.variantChain != null) 'Stufe ${card.variantLevel + 1}/${card.variantChain!.length}',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text(card.front, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          subtitle: Text(
            statusParts.join(' · '),
            style: TextStyle(fontSize: 11.5, color: c.inkMuted),
          ),
          iconColor: c.inkMuted,
          collapsedIconColor: c.inkMuted,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _AnswerDetail(card: card),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (card.type == QuestionType.flashcard)
                    TextButton.icon(
                      onPressed: () => _edit(context),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Bearbeiten'),
                    ),
                  TextButton.icon(
                    onPressed: () => _delete(context),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Löschen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}.${d.month}.${d.year}';
}

/// Zeigt die vollständige Antwort-Struktur einer Karte passend zu ihrem
/// [Flashcard.type] – anders als [Flashcard.answerSummary] (das nur die
/// richtige(n) Antwort(en) als Kurzfassung zusammenfasst) sieht man hier bei
/// Single-/Multiple-Choice ALLE Optionen inkl. der falschen, bei Lückentext
/// jede Lücke einzeln nummeriert und bei Zuordnungsfragen alle Paare – das,
/// was beim Aufklappen einer Karte tatsächlich erwartet wird, nicht nur ein
/// einzelner Antwort-Text.
class _AnswerDetail extends StatelessWidget {
  const _AnswerDetail({required this.card});
  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    switch (card.type) {
      case QuestionType.flashcard:
        return Text(card.back, style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.5));

      case QuestionType.singleChoice:
      case QuestionType.multipleChoice:
        final options = card.options ?? const [];
        if (options.isEmpty) {
          return Text('Keine Antwortoptionen hinterlegt.',
              style: TextStyle(color: c.danger, fontSize: 12.5, height: 1.5));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          o.isCorrect ? Icons.check_circle : Icons.circle_outlined,
                          size: 16,
                          color: o.isCorrect ? c.good : c.inkMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            o.text,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: o.isCorrect ? c.ink : c.inkMuted,
                              fontWeight: o.isCorrect ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        );

      case QuestionType.freeText:
        return Text(card.correctText ?? '', style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.5));

      case QuestionType.fillBlank:
        final blanks = card.blanks ?? const [];
        if (blanks.isEmpty) {
          return Text('Keine Lücken-Lösungen hinterlegt.',
              style: TextStyle(color: c.danger, fontSize: 12.5, height: 1.5));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: blanks
              .asMap()
              .entries
              .map((e) => Text(
                    'Lücke ${e.key + 1}: ${e.value}',
                    style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.4),
                  ))
              .toList(),
        );

      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        final pairs = card.dragPairs ?? const [];
        if (pairs.isEmpty) {
          return Text('Keine Zuordnungspaare hinterlegt.',
              style: TextStyle(color: c.danger, fontSize: 12.5, height: 1.5));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: pairs
              .map((p) => Text(
                    '${p.source} → ${p.target}',
                    style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.4),
                  ))
              .toList(),
        );
    }
  }
}
