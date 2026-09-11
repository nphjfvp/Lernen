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
            card.reps == 0 ? 'Neu' : 'fällig ${_formatDate(card.due)}',
            style: TextStyle(fontSize: 11.5, color: c.inkMuted),
          ),
          iconColor: c.inkMuted,
          collapsedIconColor: c.inkMuted,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(card.back, style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.5)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
