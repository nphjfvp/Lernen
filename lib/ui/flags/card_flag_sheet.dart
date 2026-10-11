import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/card_flag.dart';
import '../../models/flashcard.dart';
import '../../repositories/card_flag_repository.dart';
import '../../theme/app_colors.dart';

/// Lesezeichen-Knopf für eine Frage (z.B. im Daily Quiz): leer = nicht
/// markiert, rot = Fehler gemeldet, gefüllt = gemerkt. Öffnet
/// [showCardFlagSheet]. Ohne [CardFlagRepository] unsichtbar.
class CardFlagButton extends StatelessWidget {
  const CardFlagButton({super.key, required this.card});

  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<CardFlagRepository?>();
    if (repo == null) return const SizedBox.shrink();
    if (!repo.isLoaded) WidgetsBinding.instance.addPostFrameCallback((_) => repo.load());
    final c = context.colors;
    final flag = repo.flagOf(card.id);
    return IconButton(
      key: const ValueKey('card-flag'),
      visualDensity: VisualDensity.compact,
      tooltip: flag == null ? 'Frage markieren' : 'Markiert: ${flag.kindLabel}',
      onPressed: () => showCardFlagSheet(context, card),
      icon: Icon(
        flag == null
            ? Icons.bookmark_border
            : (flag.kind == CardFlagKind.error ? Icons.report_outlined : Icons.bookmark),
        color: flag == null ? c.inkMuted : (flag.kind == CardFlagKind.error ? c.danger : c.accent),
      ),
    );
  }
}

/// Frage markieren: Fehler gemeldet oder gemerkt, mit Notiz; vorhandene
/// Markierung ändern oder entfernen.
Future<void> showCardFlagSheet(BuildContext context, Flashcard card) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ChangeNotifierProvider.value(
    value: context.read<CardFlagRepository>(),
    child: _CardFlagSheet(card: card),
  ),
);

class _CardFlagSheet extends StatefulWidget {
  const _CardFlagSheet({required this.card});

  final Flashcard card;

  @override
  State<_CardFlagSheet> createState() => _CardFlagSheetState();
}

class _CardFlagSheetState extends State<_CardFlagSheet> {
  late final CardFlag? _existing = context.read<CardFlagRepository>().flagOf(widget.card.id);
  late CardFlagKind _kind = _existing?.kind ?? CardFlagKind.error;
  late final _note = TextEditingController(text: _existing?.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = context.read<CardFlagRepository>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final flag =
        (_existing ??
                CardFlag(
                  cardId: widget.card.id,
                  moduleId: widget.card.moduleId,
                  kind: _kind,
                  createdAt: DateTime.now(),
                ))
            .copyWith(kind: _kind, note: _note.text.trim(), front: widget.card.front.trim());
    await repo.set(flag);
    navigator.pop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          _kind == CardFlagKind.error
              ? 'Als fehlerhaft markiert – im Fach unter „Markierte Fragen“.'
              : 'Gemerkt – im Fach unter „Markierte Fragen“.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _remove() async {
    final repo = context.read<CardFlagRepository>();
    final navigator = Navigator.of(context);
    await repo.remove(widget.card.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Frage markieren', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Du findest sie danach im Fach unter „Markierte Fragen“ – zum Korrigieren oder Wiederansehen.',
            style: TextStyle(fontSize: 12.5, color: c.inkMuted),
          ),
          const SizedBox(height: 12),
          SegmentedButton<CardFlagKind>(
            key: const ValueKey('card-flag-kind'),
            segments: const [
              ButtonSegment(
                value: CardFlagKind.error,
                label: Text('Fehler in der Frage'),
                icon: Icon(Icons.report_outlined),
              ),
              ButtonSegment(value: CardFlagKind.saved, label: Text('Merken'), icon: Icon(Icons.bookmark_outline)),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('card-flag-note'),
            controller: _note,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _kind == CardFlagKind.error ? 'Was stimmt nicht? (optional)' : 'Notiz (optional)',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_existing != null)
                TextButton.icon(
                  key: const ValueKey('card-flag-remove'),
                  onPressed: _remove,
                  icon: const Icon(Icons.bookmark_remove_outlined, size: 18),
                  label: const Text('Markierung entfernen'),
                ),
              const Spacer(),
              FilledButton(key: const ValueKey('card-flag-save'), onPressed: _save, child: const Text('Speichern')),
            ],
          ),
        ],
      ),
    );
  }
}
