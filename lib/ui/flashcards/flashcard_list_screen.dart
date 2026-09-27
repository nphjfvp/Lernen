import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../services/answer_checker.dart';
import '../../services/card_csv_service.dart';
import '../../services/mastery_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/image_editor_screen.dart';
import '../widgets/mastery_dot.dart';
import '../widgets/math_text.dart';
import 'card_edit_screen.dart';

/// Listet alle Karteikarten eines Fachs auf – zum gezielten Bearbeiten oder
/// Löschen einzelner Karten, unabhängig vom Daily-Quiz-Wiederholungsflow
/// (dort sieht man immer nur die jeweils fällige Karte, keine Übersicht).
/// Lang drücken auf eine Karte startet den Auswahlmodus (mehrere Karten
/// markieren, dann gemeinsam löschen) – für Aufräumarbeiten nach einer
/// größeren Generierung, ohne jede Karte einzeln aufklappen zu müssen.
class FlashcardListScreen extends StatefulWidget {
  const FlashcardListScreen({super.key, required this.moduleId, required this.moduleName});

  final String moduleId;
  final String moduleName;

  @override
  State<FlashcardListScreen> createState() => _FlashcardListScreenState();
}

/// Suche in der Kartenliste: jedes Wort der Anfrage muss in Frage, Antwort,
/// Optionen oder Lückentext vorkommen (Groß-/Kleinschreibung egal).
bool flashcardMatchesQuery(Flashcard card, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final text = [
    card.front,
    card.back,
    card.answerSummary,
    ...?card.options?.map((o) => o.text),
  ].join(' ').toLowerCase();
  return words.every(text.contains);
}

class _FlashcardListScreenState extends State<FlashcardListScreen> {
  final Set<String> _selected = {};
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _deleteSelected(List<Flashcard> cards) async {
    final count = _selected.length;
    final ok = await confirmDelete(
      context,
      title: '$count ${count == 1 ? 'Karte' : 'Karten'} löschen?',
      message: 'Diese Karteikarten werden endgültig gelöscht.',
    );
    if (!ok || !mounted) return;
    await context.read<FlashcardRepository>().deleteMany(_selected.toList(), widget.moduleId);
    if (!mounted) return;
    setState(() => _selected.clear());
  }

  /// Backup bzw. Weitergabe an Tabellenkalkulation/Anki (siehe CardCsvService).
  Future<void> _exportCsv(List<Flashcard> cards) async {
    final messenger = ScaffoldMessenger.of(context);
    final bytes = Uint8List.fromList(utf8.encode(CardCsvService.export(cards)));
    final safeName = widget.moduleName.replaceAll(RegExp(r'[^\w\säöüÄÖÜß-]'), '').trim();
    try {
      final uri = await FilePicker.saveFile(
        fileName: '${safeName.isEmpty ? 'Karten' : safeName} – Karten.csv',
        bytes: bytes,
        mimeType: 'text/csv',
      );
      if (uri != null) messenger.showSnackBar(SnackBar(content: Text('${cards.length} Karten exportiert.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
    }
  }

  /// Übernimmt Vorder-/Rückseiten aus einer CSV/TSV (z.B. Anki-Export
  /// "Notizen als Text") als neue Karteikarten dieses Fachs.
  Future<void> _importCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<FlashcardRepository>();
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['csv', 'tsv', 'txt']);
    if (picked.isEmpty) return;
    final List<({String front, String back})> rows;
    try {
      rows = CardCsvService.parse(utf8.decode(await picked.first.readAsBytes(), allowMalformed: true));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Datei konnte nicht gelesen werden: $e')));
      return;
    }
    if (rows.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Keine Karten gefunden – erwartet werden zwei Spalten: Vorderseite und Rückseite.'),
      ));
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${rows.length} Karten importieren?'),
        content: Text('Beispiel:\n„${rows.first.front}“ → „${rows.first.back}“\n\n'
            'Sie landen als neue Karteikarten in diesem Fach und werden wie andere neue Karten '
            'nach und nach im Daily Quiz eingeführt.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Importieren')),
        ],
      ),
    );
    if (ok != true) return;
    await repo.saveAll(CardCsvService.toFlashcards(rows, widget.moduleId));
    messenger.showSnackBar(SnackBar(content: Text('${rows.length} Karten importiert.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final allCards = context.watch<FlashcardRepository>().forModule(widget.moduleId);
    final cards = [for (final card in allCards) if (flashcardMatchesQuery(card, _query)) card];

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(_selecting ? '${_selected.length} ausgewählt' : 'Karteikarten · ${widget.moduleName}'),
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Auswahl aufheben',
                onPressed: () => setState(_selected.clear),
              )
            : null,
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Alle auswählen',
                  onPressed: () => setState(() => _selected.addAll(cards.map((c) => c.id))),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Ausgewählte löschen',
                  onPressed: () => _deleteSelected(cards),
                ),
              ]
            : [
                PopupMenuButton<String>(
                  tooltip: 'Export/Import',
                  onSelected: (value) => value == 'export' ? _exportCsv(allCards) : _importCsv(),
                  itemBuilder: (_) => [
                    if (allCards.isNotEmpty)
                      const PopupMenuItem(value: 'export', child: Text('Als CSV exportieren')),
                    const PopupMenuItem(value: 'import', child: Text('CSV importieren (Vorder-/Rückseite)')),
                  ],
                ),
              ],
      ),
      body: allCards.isEmpty
          ? Center(child: Text('Noch keine Karteikarten.', style: TextStyle(color: c.inkMuted)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Karten durchsuchen (${allCards.length})',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Suche leeren',
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() {
                                _searchController.clear();
                                _query = '';
                              }),
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: cards.isEmpty
                      ? Center(child: Text('Keine Karte passt zur Suche.', style: TextStyle(color: c.inkMuted)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: cards.length,
                          itemBuilder: (ctx, i) {
                            final card = cards[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _FlashcardTile(
                                card: card,
                                selecting: _selecting,
                                selected: _selected.contains(card.id),
                                onToggleSelected: () => _toggle(card.id),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _FlashcardTile extends StatelessWidget {
  const _FlashcardTile({
    required this.card,
    required this.selecting,
    required this.selected,
    required this.onToggleSelected,
  });
  final Flashcard card;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelected;

  /// Inhalt korrigieren – für jeden Fragetyp (siehe CardEditScreen). Auf
  /// den gespeicherten Stand angewendet, damit ein zwischenzeitlich
  /// verbuchter Lernfortschritt nicht verloren geht.
  Future<void> _edit(BuildContext context) async {
    final repo = context.read<FlashcardRepository>();
    final edited = await showCardEditor(context, card);
    if (edited == null) return;
    final stored = await repo.loadById(card.id);
    if (stored == null) return;
    await repo.update(stored.copyWithContent(
      front: edited.front,
      back: edited.back,
      options: edited.options,
      correctText: edited.correctText,
      blanks: edited.blanks,
      dragPairs: edited.dragPairs,
    ));
  }

  /// Bild der Karte bearbeiten (abdecken, beschriften) – bei Bildfragen
  /// auch die Stellen bzw. Bereiche. Der Lernstand bleibt.
  Future<void> _editImage(BuildContext context) async {
    final base64 = card.imageBase64;
    if (base64 == null) return;
    final Uint8List bytes;
    try {
      bytes = base64Decode(base64);
    } catch (_) {
      return;
    }
    final mode = switch (card.type) {
      QuestionType.diagramLabel => ImageTargetMode.labels,
      QuestionType.markImage => ImageTargetMode.regions,
      _ => null,
    };
    final repo = context.read<FlashcardRepository>();
    final result = await showImageEditor(context, bytes, targetMode: mode, targets: card.imageTargets ?? const []);
    if (result == null) return;
    // Auf den gespeicherten Stand anwenden (die Liste kann veraltet sein).
    final stored = await repo.loadById(card.id);
    if (stored == null) return;
    await repo.update(stored.copyWithImage(
      imageBase64: result.imageChanged ? base64Encode(result.bytes) : null,
      imageTargets: mode != null ? result.targets : null,
    ));
  }

  /// Unnötig angehängtes Bild entfernen (nur bei Fragen, die kein Bild
  /// brauchen – Bildfragen gehen ohne Bild nicht).
  Future<void> _removeImage(BuildContext context) async {
    final repo = context.read<FlashcardRepository>();
    final ok = await confirmDelete(
      context,
      title: 'Bild entfernen?',
      message: 'Das Bild wird aus dieser Frage gelöscht – die Frage selbst bleibt.',
    );
    if (!ok) return;
    final stored = await repo.loadById(card.id);
    if (stored == null) return;
    await repo.update(stored.copyWithImage(clearImage: true));
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
    final level = MasteryService().levelFor(card);
    final statusParts = [
      card.type.label,
      card.reps == 0 ? 'Neu' : 'fällig ${_formatDate(card.due)}',
      if (card.variantChain != null) 'Stufe ${card.variantLevel + 1}/${card.variantChain!.length}',
    ];
    // Material statt DecoratedBox: ListTile/ExpansionTile malen Hintergrund
    // und Tipp-Effekt auf das nächste Material (sonst Debug-Assertion und
    // unsichtbares Feedback).
    Widget framed(Widget child) => Material(
          color: selected ? c.accentSoft : c.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: selected ? c.accent : c.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        );

    if (selecting) {
      // Kein ExpansionTile im Auswahlmodus: ein Tippen soll ausschließlich
      // (De-)Selektieren, nicht Auf-/Zuklappen auslösen.
      return framed(
        ListTile(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          leading: Checkbox(value: selected, onChanged: (_) => onToggleSelected()),
          title: Text(card.front, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          subtitle: Text(statusParts.join(' · '), style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
          onTap: onToggleSelected,
        ),
      );
    }

    return framed(
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: GestureDetector(
          onLongPress: onToggleSelected,
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            leading: MasteryDot(level: level),
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
                    if (card.imageBase64 != null &&
                        card.type != QuestionType.diagramLabel &&
                        card.type != QuestionType.markImage)
                      IconButton(
                        tooltip: 'Bild entfernen',
                        onPressed: () => _removeImage(context),
                        icon: const Icon(Icons.hide_image_outlined, size: 18),
                      ),
                    if (card.imageBase64 != null)
                      TextButton.icon(
                        onPressed: () => _editImage(context),
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: Text(switch (card.type) {
                          QuestionType.diagramLabel => 'Stellen',
                          QuestionType.markImage => 'Bereich',
                          _ => 'Bild',
                        }),
                      ),
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
        return MathText(card.back, style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.5));

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
        return MathText(card.correctText ?? '', style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.5));

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

      case QuestionType.html:
        return Text(
          card.back.isEmpty ? '(Interaktive Seite – Antwort-Prüfung steckt im HTML-Inhalt.)' : card.back,
          style: TextStyle(color: c.inkMuted, fontSize: 12.5, height: 1.5),
        );
      case QuestionType.diagramLabel:
        final targets = AnswerChecker.labelTargets(card);
        return Text(
          targets.isEmpty ? 'Keine Beschriftungen hinterlegt.' : AnswerChecker.diagramLabelSolution(card),
          style: TextStyle(color: targets.isEmpty ? c.danger : c.inkMuted, fontSize: 12.5, height: 1.5),
        );
      case QuestionType.markImage:
        final regions = card.imageTargets?.length ?? 0;
        return Text(
          regions == 0
              ? 'Kein Bereich im Bild hinterlegt.'
              : '${card.answerSummary} ($regions Bereich${regions == 1 ? '' : 'e'} im Bild)',
          style: TextStyle(color: regions == 0 ? c.danger : c.inkMuted, fontSize: 12.5, height: 1.5),
        );
    }
  }
}
