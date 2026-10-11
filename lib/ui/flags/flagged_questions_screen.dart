import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/card_flag.dart';
import '../../models/flashcard.dart';
import '../../models/module.dart';
import '../../repositories/card_flag_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/visual_lesson_repository.dart';
import '../../theme/app_colors.dart';
import '../flashcards/card_edit_screen.dart';
import '../visual/visual_from_card.dart';
import '../widgets/math_text.dart';
import 'card_flag_sheet.dart';

/// Markierte Fragen eines Fachs ([moduleId]) oder aller Fächer: gemeldete
/// Fehler und gemerkte Fragen – zum Korrigieren, visuell erklären lassen oder
/// Markierung entfernen.
class FlaggedQuestionsScreen extends StatefulWidget {
  const FlaggedQuestionsScreen({super.key, this.moduleId});

  final String? moduleId;

  @override
  State<FlaggedQuestionsScreen> createState() => _FlaggedQuestionsScreenState();
}

class _FlaggedQuestionsScreenState extends State<FlaggedQuestionsScreen> {
  CardFlagKind? _filter;
  final Map<String, Flashcard?> _cards = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final flags = context.read<CardFlagRepository>();
    final cards = context.read<FlashcardRepository?>();
    await flags.load();
    for (final f in flags.list(moduleId: widget.moduleId)) {
      _cards[f.cardId] = await cards?.loadById(f.cardId);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit(Flashcard card, CardFlag flag) async {
    final repo = context.read<FlashcardRepository>();
    final flags = context.read<CardFlagRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final edited = await showCardEditor(context, card);
    if (edited == null) return;
    final stored = await repo.loadById(card.id);
    if (stored == null) return;
    final updated = stored.copyWithContent(
      front: edited.front,
      back: edited.back,
      options: edited.options,
      correctText: edited.correctText,
      blanks: edited.blanks,
      dragPairs: edited.dragPairs,
      tableRows: edited.tableRows,
      taskData: edited.taskData,
    );
    await repo.update(updated);
    if (!mounted) return;
    setState(() => _cards[card.id] = updated);
    if (flag.kind == CardFlagKind.error) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Frage korrigiert.'),
          action: SnackBarAction(label: 'Markierung entfernen', onPressed: () => flags.remove(card.id)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final flags = context.watch<CardFlagRepository>();
    final modules = <String, String>{
      for (final m in context.read<ModuleRepository?>()?.modules ?? const <Module>[]) m.id: m.name,
    };
    final all = flags.list(moduleId: widget.moduleId);
    final shown = [
      for (final f in all)
        if (_filter == null || f.kind == _filter) f,
    ];
    final errors = all.where((f) => f.kind == CardFlagKind.error).length;
    final canVisual = context.read<VisualLessonRepository?>() != null;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Markierte Fragen')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          key: const ValueKey('flags-filter-all'),
                          label: Text('Alle (${all.length})'),
                          selected: _filter == null,
                          onSelected: (_) => setState(() => _filter = null),
                        ),
                        ChoiceChip(
                          key: const ValueKey('flags-filter-error'),
                          label: Text('Fehler ($errors)'),
                          selected: _filter == CardFlagKind.error,
                          onSelected: (_) => setState(() => _filter = CardFlagKind.error),
                        ),
                        ChoiceChip(
                          key: const ValueKey('flags-filter-saved'),
                          label: Text('Gemerkt (${all.length - errors})'),
                          selected: _filter == CardFlagKind.saved,
                          onSelected: (_) => setState(() => _filter = CardFlagKind.saved),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Keine markierten Fragen. Im Daily Quiz markierst du eine Frage über das Lesezeichen oben.',
                          style: TextStyle(color: c.inkMuted),
                        ),
                      ),
                    for (final (i, f) in shown.indexed) _item(c, i, f, _cards[f.cardId], modules, canVisual),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _item(AppColors c, int i, CardFlag f, Flashcard? card, Map<String, String> modules, bool canVisual) {
    final error = f.kind == CardFlagKind.error;
    final front = card?.front ?? f.front;
    return Card(
      key: ValueKey('flag-$i'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(error ? Icons.report_outlined : Icons.bookmark, size: 18, color: error ? c.danger : c.accent),
                const SizedBox(width: 6),
                Text(
                  f.kindLabel,
                  style: TextStyle(fontWeight: FontWeight.w600, color: error ? c.danger : c.accent),
                ),
                if (widget.moduleId == null && modules[f.moduleId] != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '· ${modules[f.moduleId]}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.inkMuted, fontSize: 12.5),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            MathText(front, style: const TextStyle(fontSize: 14.5, height: 1.4)),
            if (f.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Notiz: ${f.note}',
                key: ValueKey('flag-note-$i'),
                style: TextStyle(color: c.inkMuted),
              ),
            ],
            if (card == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Diese Frage gibt es nicht mehr.', style: TextStyle(color: c.warn)),
              ),
            Wrap(
              spacing: 2,
              children: [
                if (card != null)
                  TextButton.icon(
                    key: ValueKey('flag-edit-$i'),
                    onPressed: () => _edit(card, f),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Bearbeiten'),
                  ),
                if (card != null && canVisual)
                  TextButton.icon(
                    key: ValueKey('flag-visual-$i'),
                    onPressed: () => openVisualForCard(context, card),
                    icon: const Icon(Icons.animation, size: 18),
                    label: const Text('Visuell erklären'),
                  ),
                if (card != null)
                  TextButton.icon(
                    key: ValueKey('flag-change-$i'),
                    onPressed: () => showCardFlagSheet(context, card),
                    icon: const Icon(Icons.bookmark_outline, size: 18),
                    label: const Text('Ändern'),
                  ),
                TextButton.icon(
                  key: ValueKey('flag-remove-$i'),
                  onPressed: () => context.read<CardFlagRepository>().remove(f.cardId),
                  icon: const Icon(Icons.bookmark_remove_outlined, size: 18),
                  label: const Text('Entfernen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
