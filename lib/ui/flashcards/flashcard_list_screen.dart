import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/answer_checker.dart';
import '../../services/card_csv_service.dart';
import '../../services/mastery_service.dart';
import '../../services/module_export_service.dart';
import '../../services/stage_gate_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/image_editor_screen.dart';
import '../widgets/mastery_dot.dart';
import '../widgets/math_text.dart';
import '../widgets/stage_picker.dart';
import '../widgets/table_preview.dart';
import '../widgets/weight_slider.dart';
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
  /// So viele Fragen sieht die KI beim Zuordnen der Stufen auf einmal.
  static const _stageBatchSize = 60;

  final Set<String> _selected = {};
  final _searchController = TextEditingController();
  String _query = '';

  /// Fortschritt von [_assignStagesWithAi] (0..1), null wenn nicht aktiv.
  double? _assignProgress;

  /// Ordnet bestehende Fragen per KI Sachverhalten und Stufen zu (siehe
  /// StageGate) – für Karten, die vor der Stufen-Aufteilung entstanden sind.
  /// Bereits fertige Portionen bleiben auch bei einem späteren Fehler
  /// gespeichert.
  Future<void> _assignStagesWithAi(List<Flashcard> allCards) async {
    final messenger = ScaffoldMessenger.of(context);
    final settings = context.read<SettingsRepository>().settings;
    final repo = context.read<FlashcardRepository>();
    if (!settings.hasApiKey) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Dafür wird ein OpenRouter-API-Key gebraucht (Einstellungen).'),
      ));
      return;
    }
    final cards = StageGate.assignable(allCards);
    if (cards.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stufen per KI zuordnen?'),
        content: Text('Die KI ordnet ${cards.length} Fragen nach Sachverhalt und Schwierigkeit '
            '(Leicht/Mittel/Schwer). Danach kommt je Sachverhalt erst Leicht dran, dann Mittel, '
            'dann Schwer – jeweils erst, wenn die Stufe davor sitzt.\n\n'
            'Inhalt und Lernstand bleiben unverändert; einzelne Stufen lassen sich danach per '
            '„Stufe“ ändern. Ohne diesen Schritt gilt: gleiches Konzept = eine Gruppe, die Stufe '
            'folgt aus dem Fragetyp.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Zuordnen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _assignProgress = 0);
    final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
    final runTag = DateTime.now().millisecondsSinceEpoch.toString();
    var changed = 0;
    try {
      for (var start = 0; start < cards.length; start += _stageBatchSize) {
        final batch = cards.sublist(start, min(start + _stageBatchSize, cards.length));
        final results = await ai.assignStages([
          for (var i = 0; i < batch.length; i++)
            (n: i + 1, type: batch[i].type.label, front: batch[i].front, answer: batch[i].answerSummary),
        ]);
        final updated = StageGate.applyAssignments(batch, results, runTag: runTag);
        await repo.updateAll(updated);
        changed += updated.length;
        if (mounted) setState(() => _assignProgress = (start + batch.length) / cards.length);
      }
      messenger.showSnackBar(SnackBar(content: Text('$changed von ${cards.length} Fragen eingeordnet.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Zuordnung abgebrochen ($changed eingeordnet): ${e is AiServiceException ? e.message : e}'),
      ));
    } finally {
      if (mounted) setState(() => _assignProgress = null);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Auswahlmodus per Knopf (auch ohne schon ausgewählte Karte) – zusätzlich
  /// zum langen Drücken auf eine Karte.
  bool _selectMode = false;

  bool get _selecting => _selectMode || _selected.isNotEmpty;

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _endSelection() => setState(() {
        _selected.clear();
        _selectMode = false;
      });

  /// Wendet [change] auf den GESPEICHERTEN Stand aller ausgewählten Karten an
  /// (zwischenzeitlich verbuchter Lernfortschritt bleibt) und beendet die
  /// Auswahl.
  Future<void> _applyToSelected(Flashcard Function(Flashcard) change, String doneMessage) async {
    final repo = context.read<FlashcardRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final ids = _selected.toSet();
    final stored = (await repo.loadModuleCards(widget.moduleId)).where((c) => ids.contains(c.id));
    await repo.updateAll([for (final c in stored) change(c)]);
    if (!mounted) return;
    _endSelection();
    messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
  }

  /// Sammel-Bearbeiten der ausgewählten Karten.
  Future<void> _bulkAction(String action, List<Flashcard> allCards) async {
    final count = _selected.length;
    if (count == 0) return;
    final label = '$count ${count == 1 ? 'Karte' : 'Karten'}';
    final selected = [for (final c in allCards) if (_selected.contains(c.id)) c];
    switch (action) {
      case 'weight':
        final weights = selected.map((c) => c.weight).toSet();
        final picked = await showDialog<double>(
          context: context,
          builder: (_) => _WeightDialog(initial: weights.length == 1 ? weights.single : 1.0),
        );
        if (picked == null) return;
        await _applyToSelected((c) => c.copyWithWeight(picked), '$label: ${formatWeight(picked)}× gewichtet');
      case 'stage':
        final levels = selected.map((c) => c.stageLevel).toSet();
        final picked = await pickStageLevel(
          context,
          current: levels.length == 1 ? levels.single : null,
          title: 'Stufe für $label',
        );
        if (picked == null) return;
        await _applyToSelected(
          (c) => picked == stageLevelAuto ? c.copyWithStage(clearLevel: true) : c.copyWithStage(level: picked),
          picked == stageLevelAuto
              ? '$label: Stufe wieder aus dem Fragetyp'
              : '$label: Stufe ${StageLevel.values[picked].label}',
        );
      case 'group':
        final key = 'manuell-${DateTime.now().millisecondsSinceEpoch}';
        await _applyToSelected(
          (c) => c.copyWithStage(group: key),
          '$label zu einer Frage zusammengefasst: erst Leicht, dann Mittel, dann Schwer',
        );
      case 'ungroup':
        await _applyToSelected(
          (c) => c.copyWithStage(group: 'einzeln-${c.id}'),
          '$label laufen jetzt einzeln, unabhängig von anderen Stufen',
        );
      case 'unit':
        final units = context.read<LectureUnitRepository?>();
        await units?.loadForModule(widget.moduleId);
        if (!mounted) return;
        final options = units?.forModule(widget.moduleId) ?? const [];
        if (options.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('In diesem Fach sind noch keine Einheiten angelegt.')),
          );
          return;
        }
        final picked = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text('Einheit für $label'),
            children: [
              for (final u in options)
                SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(u.id), child: Text(u.title)),
              SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(''), child: const Text('Keine Einheit')),
            ],
          ),
        );
        if (picked == null) return;
        await _applyToSelected(
          (c) => c.copyWithUnit(picked.isEmpty ? null : picked),
          picked.isEmpty ? '$label ohne Einheit' : '$label der Einheit zugeordnet',
        );
      case 'reset':
        final ok = await confirmDelete(
          context,
          title: 'Lernstand von $label zurücksetzen?',
          message: 'Die Karten gelten danach wieder als neu (Ampel leer, Stufenketten wieder auf der '
              'leichtesten Stufe). Inhalt, Stufe und Gewichtung bleiben.',
        );
        if (!ok) return;
        await _applyToSelected(ModuleExportService.resetLearningState, 'Lernstand von $label zurückgesetzt');
    }
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
    _endSelection();
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
    final stages = StageGate.statuses(allCards);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(_selecting
            ? (_selected.isEmpty ? 'Karten auswählen' : '${_selected.length} ausgewählt')
            : 'Karteikarten · ${widget.moduleName}'),
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Auswahl beenden',
                onPressed: _endSelection,
              )
            : null,
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Alle auswählen',
                  onPressed: () => setState(() => _selected.addAll(cards.map((c) => c.id))),
                ),
                PopupMenuButton<String>(
                  key: const ValueKey('bulk-edit'),
                  tooltip: 'Ausgewählte bearbeiten',
                  icon: const Icon(Icons.edit_note),
                  enabled: _selected.isNotEmpty,
                  onSelected: (action) => _bulkAction(action, allCards),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'weight', child: Text('Gewichtung setzen')),
                    PopupMenuItem(value: 'stage', child: Text('Stufe setzen (Leicht/Mittel/Schwer)')),
                    PopupMenuItem(value: 'group', child: Text('Zu einer Frage zusammenfassen')),
                    PopupMenuItem(value: 'ungroup', child: Text('Einzeln lernen (aus Gruppe lösen)')),
                    PopupMenuItem(value: 'unit', child: Text('Einheit zuordnen')),
                    PopupMenuItem(value: 'reset', child: Text('Lernstand zurücksetzen')),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Ausgewählte löschen',
                  onPressed: _selected.isEmpty ? null : () => _deleteSelected(cards),
                ),
              ]
            : [
                if (allCards.isNotEmpty)
                  IconButton(
                    key: const ValueKey('select-mode'),
                    icon: const Icon(Icons.checklist),
                    tooltip: 'Mehrere auswählen',
                    onPressed: () => setState(() => _selectMode = true),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Weitere Aktionen',
                  onSelected: (value) => switch (value) {
                    'export' => _exportCsv(allCards),
                    'stages' => _assignStagesWithAi(allCards),
                    _ => _importCsv(),
                  },
                  itemBuilder: (_) => [
                    if (allCards.isNotEmpty && _assignProgress == null)
                      const PopupMenuItem(value: 'stages', child: Text('Stufen per KI zuordnen')),
                    if (allCards.isNotEmpty)
                      const PopupMenuItem(value: 'export', child: Text('Als CSV exportieren')),
                    const PopupMenuItem(value: 'import', child: Text('CSV importieren (Vorder-/Rückseite)')),
                  ],
                ),
              ],
        bottom: _assignProgress == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: _assignProgress),
              ),
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
                                stage: StageGate.statusOf(stages, card),
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
    required this.stage,
    required this.selecting,
    required this.selected,
    required this.onToggleSelected,
  });
  final Flashcard card;
  final StageStatus stage;
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
      tableRows: edited.tableRows,
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

  /// Gewichtung ändern – wie oft die Karte im Vergleich drankommt (siehe
  /// Flashcard.weight). Auf den gespeicherten Stand angewendet.
  Future<void> _editWeight(BuildContext context) async {
    final repo = context.read<FlashcardRepository>();
    final picked = await showDialog<double>(
      context: context,
      builder: (_) => _WeightDialog(initial: card.weight),
    );
    if (picked == null) return;
    final stored = await repo.loadById(card.id);
    if (stored == null) return;
    await repo.update(stored.copyWithWeight(picked));
  }

  /// Schwierigkeitsstufe von Hand setzen (siehe Flashcard.stageLevel) –
  /// oder zurück auf "aus dem Fragetyp".
  Future<void> _editStage(BuildContext context) async {
    final repo = context.read<FlashcardRepository>();
    final picked = await pickStageLevel(context, current: card.stageLevel);
    if (picked == null) return;
    final stored = await repo.loadById(card.id);
    if (stored == null) return;
    await repo.update(
        picked == stageLevelAuto ? stored.copyWithStage(clearLevel: true) : stored.copyWithStage(level: picked));
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
    final level = MasteryService().levelFor(card, stage: stage);
    final chain = card.variantChain;
    final statusParts = [
      card.type.label,
      if (chain != null && chain.length > 1)
        'Stufe ${card.variantLevel + 1}/${chain.length}'
      else
        StageGate.levelOf(card).label,
      if (stage != StageStatus.active) stage.label,
      if (stage == StageStatus.active) card.reps == 0 ? 'Neu' : 'fällig ${_formatDate(card.due)}',
      if (card.weight != 1.0) '${formatWeight(card.weight)}× gewichtet',
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
                    if (chain == null || chain.length < 2)
                      TextButton.icon(
                        key: ValueKey('card-stage-${card.id}'),
                        onPressed: () => _editStage(context),
                        icon: const Icon(Icons.stairs_outlined, size: 16),
                        label: const Text('Stufe'),
                      ),
                    TextButton.icon(
                      key: ValueKey('card-weight-${card.id}'),
                      onPressed: () => _editWeight(context),
                      icon: const Icon(Icons.fitness_center_outlined, size: 16),
                      label: const Text('Gewichtung'),
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

/// Dialog zum Ändern der Gewichtung einer Karte (siehe Flashcard.weight).
class _WeightDialog extends StatefulWidget {
  const _WeightDialog({required this.initial});
  final double initial;

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  late double _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gewichtung'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Wie oft diese Frage im Vergleich drankommt: 1× ist normal (Folien-Fragen), '
            'Übungsaufgaben starten mit 1,5×. Wirkt zusammen mit der Gewichtung des Fachs.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          WeightSlider(
            key: const ValueKey('card-weight-slider'),
            value: _value,
            onChanged: (w) => setState(() => _value = w),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_value), child: const Text('Speichern')),
      ],
    );
  }
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
      case QuestionType.table:
        return TablePreview(rows: card.tableRows ?? const []);
    }
  }
}
