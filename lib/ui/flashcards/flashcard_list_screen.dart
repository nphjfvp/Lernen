import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/concept_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/answer_checker.dart';
import '../../services/card_csv_service.dart';
import '../../services/mastery_service.dart';
import '../../services/module_export_service.dart';
import '../../services/script_match_service.dart';
import '../../services/source_locator.dart';
import '../../services/stage_gate_service.dart';
import '../../theme/app_colors.dart';
import '../study/script_match_runner.dart';
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
  /// So viele Fragen sieht die KI beim Zuordnen der Stufen auf einmal. Die
  /// Ordnernamen früherer Portionen bekommt sie jeweils mit, damit
  /// Zusammengehöriges auch über Portionsgrenzen in einem Ordner landet.
  static const _stageBatchSize = 80;

  /// So viele Ordnernamen früherer Portionen gehen höchstens mit (die
  /// jüngsten – die Karten sind nach Konzept sortiert, Zusammengehöriges
  /// steht also nah beieinander).
  static const _maxKnownGroups = 200;

  /// Aufgeklappte Ordner (Gruppenschlüssel, siehe StageGate.groupOf).
  final Set<String> _openFolders = {};

  @override
  void initState() {
    super.initState();
    // Konzepttitel für die Ordnernamen (Gruppe = Konzept, solange nichts
    // anderes zugeordnet ist).
    final concepts = context.read<ConceptRepository?>();
    if (concepts != null && concepts.forModule(widget.moduleId).isEmpty) {
      concepts.loadForModule(widget.moduleId).catchError((_) {});
    }
  }

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
        title: const Text('Fragen per KI in Ordner sortieren?'),
        content: Text('Die KI geht alle ${cards.length} Fragen dieses Fachs durch und legt Fragen, die '
            'dasselbe Wissen verschieden schwer abfragen, in einen gemeinsamen Ordner '
            '(Leicht/Mittel/Schwer). Beim Lernen kommt je Ordner erst Leicht dran, dann Mittel, dann '
            'Schwer – jeweils erst, wenn die Stufe davor sitzt. Fragen ohne Partner bleiben einzeln.\n\n'
            'Die bisherige Einteilung wird dabei neu gemacht. Inhalt und Lernstand bleiben; das '
            'Ergebnis siehst du danach als Ordner in dieser Liste und kannst es dort ändern.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sortieren')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _assignProgress = 0);
    final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
    final runTag = DateTime.now().millisecondsSinceEpoch.toString();
    final assigned = <Flashcard>[];
    final knownGroups = <String>[];
    try {
      for (var start = 0; start < cards.length; start += _stageBatchSize) {
        final batch = cards.sublist(start, min(start + _stageBatchSize, cards.length));
        final results = await ai.assignStages([
          for (var i = 0; i < batch.length; i++)
            (n: i + 1, type: batch[i].type.label, front: batch[i].front, answer: batch[i].answerSummary),
        ], knownGroups: knownGroups.length > _maxKnownGroups
            ? knownGroups.sublist(knownGroups.length - _maxKnownGroups)
            : knownGroups);
        final updated = StageGate.applyAssignments(batch, results, runTag: runTag);
        await repo.updateAll(updated);
        assigned.addAll(updated);
        for (final r in results.values) {
          final g = r.group;
          if (g != null && !knownGroups.any((k) => k.toLowerCase() == g.toLowerCase())) knownGroups.add(g);
        }
        if (mounted) setState(() => _assignProgress = (start + batch.length) / cards.length);
      }
      final sizes = <String, int>{};
      for (final c in assigned) {
        final key = StageGate.groupOf(c);
        if (key != null) sizes[key] = (sizes[key] ?? 0) + 1;
      }
      final folders = sizes.values.where((n) => n >= 2).length;
      final inFolders = sizes.values.where((n) => n >= 2).fold<int>(0, (a, n) => a + n);
      messenger.showSnackBar(SnackBar(
        content: Text('${assigned.length} von ${cards.length} Fragen einsortiert: $inFolders in $folders '
            '${folders == 1 ? 'Ordner' : 'Ordnern'}, ${assigned.length - inFolders} einzeln.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Sortieren abgebrochen (${assigned.length} einsortiert): '
            '${e is AiServiceException ? e.message : e}'),
      ));
    } finally {
      if (mounted) setState(() => _assignProgress = null);
    }
  }

  /// Fragt einen Ordnernamen ab (null = abgebrochen).
  Future<String?> _askFolderName({String initial = '', required String title}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FolderNameDialog(title: title, initial: initial),
    );
    return name?.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Neuer Gruppenwert für einen Ordner mit [name].
  static String _folderGroup(String name) =>
      name.isEmpty ? 'manuell-${DateTime.now().millisecondsSinceEpoch}' : '$name#${DateTime.now().millisecondsSinceEpoch}';

  /// Wendet [change] auf den gespeicherten Stand aller Karten des Ordners an.
  Future<void> _applyToFolder(StageFolder folder, Flashcard Function(Flashcard) change, String? doneMessage) async {
    final repo = context.read<FlashcardRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final stored = (await repo.loadModuleCards(widget.moduleId)).where((c) => StageGate.groupOf(c) == folder.key);
    await repo.updateAll([for (final c in stored) change(c)]);
    if (doneMessage != null) messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
  }

  Future<void> _renameFolder(StageFolder folder) async {
    final name = await _askFolderName(initial: folder.name ?? '', title: 'Ordner umbenennen');
    if (name == null || !mounted) return;
    final group = _folderGroup(name);
    await _applyToFolder(folder, (c) => c.copyWithStage(group: group), 'Ordner umbenannt');
  }

  Future<void> _dissolveFolder(StageFolder folder, int size) async {
    final ok = await confirmDelete(
      context,
      title: 'Ordner auflösen?',
      message: 'Die $size Fragen laufen danach einzeln: jede wird unabhängig von den anderen Stufen '
          'abgefragt. Gelöscht wird nichts.',
      confirmLabel: 'Auflösen',
    );
    if (!ok || !mounted) return;
    await _applyToFolder(folder, (c) => c.copyWithStage(group: 'einzeln-${c.id}'), 'Ordner aufgelöst');
  }

  /// Fortschritt von [_matchScript] (0..1), null wenn nicht aktiv.
  double? _scriptProgress;

  /// So viele Fragen je Speicherschritt – ein Abbruch verliert höchstens einen
  /// Teil.
  static const _scriptChunk = 40;

  /// Sucht per KI im Skript die Seite mit der Erklärung zu den Fragen des
  /// Fachs (siehe ScriptMatchService) – vor allem für Fragen aus
  /// Übungsblättern, bei denen "Im Skript" sonst nur aufs Blatt zeigt.
  Future<void> _matchScript(List<Flashcard> allCards) async {
    final messenger = ScaffoldMessenger.of(context);
    final env = ScriptMatchContext.of(context);
    if (env == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Dafür wird ein OpenRouter-API-Key gebraucht (Einstellungen).'),
      ));
      return;
    }
    final mats = await env.materialsOf(widget.moduleId);
    if (SourceLocator.scriptPdfs(mats).isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Im Fach liegt kein Skript (Folien als PDF) auf diesem Gerät – lade zuerst die '
            'Vorlesungsfolien hoch.'),
      ));
      return;
    }
    final open = ScriptMatchService.candidatesFrom(allCards, mats, includeUnsourced: true);
    final all = ScriptMatchService.candidatesFrom(allCards, mats, includeUnsourced: true, force: true);
    if (all.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Alle Fragen stammen schon aus dem Skript.')));
      return;
    }
    if (!mounted) return;
    var again = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Erklärungen im Skript suchen?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                open.isEmpty
                    ? 'Für alle Fragen wurde schon gesucht.'
                    : 'Die KI sucht für ${open.length} ${open.length == 1 ? 'Frage' : 'Fragen'} aus Übungsblättern '
                        '(oder ohne bekannte Quelle) in deinem Skript die Seite, auf der die Erklärung bzw. '
                        'Lösung steht. Danach öffnet "Im Skript" genau diese Seite; das Übungsblatt bleibt '
                        'als "Aufgabenblatt" erreichbar.',
              ),
              if (all.length > open.length)
                CheckboxListTile(
                  key: const ValueKey('script-match-again'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: again,
                  onChanged: (v) => setLocal(() => again = v ?? false),
                  title: Text('Auch die ${all.length - open.length} schon gesuchten erneut prüfen'),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: open.isEmpty && !again ? null : () => Navigator.of(ctx).pop(true),
              child: const Text('Suchen'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final todo = again ? all : open;
    setState(() => _scriptProgress = 0);
    var found = 0;
    var failed = 0;
    try {
      for (var start = 0; start < todo.length; start += _scriptChunk) {
        final chunk = todo.sublist(start, min(start + _scriptChunk, todo.length));
        final run = await env.run(widget.moduleId, chunk);
        if (run == null) break;
        found += run.found;
        failed += run.failedCards;
        if (mounted) setState(() => _scriptProgress = (start + chunk.length) / todo.length);
      }
      messenger.showSnackBar(SnackBar(
        content: Text('$found von ${todo.length} Fragen im Skript verortet'
            '${failed > 0 ? ' ($failed fehlgeschlagen – bitte nochmal versuchen)' : ''}.'),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Suche abgebrochen: $e')));
    } finally {
      if (mounted) setState(() => _scriptProgress = null);
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
        final concepts = context.read<ConceptRepository?>()?.forModule(widget.moduleId) ?? const [];
        final folders = [
          for (final e in StageGate.listEntries(allCards, allCards,
              conceptTitles: {for (final k in concepts) k.id: k.title}))
            if (e.folder != null) e.folder!,
        ];
        const newFolder = '\u0000neu';
        final picked = await showDialog<Object>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text('$label in Ordner legen'),
            children: [
              SimpleDialogOption(
                key: const ValueKey('folder-new'),
                onPressed: () => Navigator.of(ctx).pop(newFolder),
                child: const Text('Neuer Ordner …', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              for (final f in folders)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(f),
                  child: Text(f.name ?? f.hardest.front, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        );
        if (picked == null || !mounted) return;
        final String group;
        if (picked is StageFolder) {
          final stored = picked.hardest.stageGroup?.trim() ?? '';
          if (stored.isEmpty || stored == picked.hardest.conceptId) {
            // Ordner nur aus dem Konzept: bekommt jetzt einen eigenen Namen,
            // damit Ordner und hinzugelegte Fragen sicher zusammenbleiben.
            group = _folderGroup(picked.name ?? '');
            await _applyToFolder(picked, (c) => c.copyWithStage(group: group), null);
            if (!mounted) return;
          } else {
            group = stored;
          }
        } else {
          final name = await _askFolderName(title: 'Neuer Ordner');
          if (name == null || !mounted) return;
          group = _folderGroup(name);
        }
        await _applyToSelected(
          (c) => c.copyWithStage(group: group),
          '$label im Ordner: erst Leicht, dann Mittel, dann Schwer',
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
    final concepts = context.watch<ConceptRepository?>()?.forModule(widget.moduleId) ?? const [];
    final entries = StageGate.listEntries(
      allCards,
      cards,
      conceptTitles: {for (final k in concepts) k.id: k.title},
    );
    // Komplette Gruppen (für Stufenstand und Größe eines Ordners, auch wenn
    // die Suche nur einen Teil zeigt).
    final groups = <String, List<Flashcard>>{};
    for (final card in allCards) {
      final key = StageGate.groupOf(card);
      if (key != null) groups.putIfAbsent(key, () => []).add(card);
    }
    final conceptOnly = _query.isEmpty && entries.any((e) => e.folder?.byConceptOnly ?? false);

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
                    PopupMenuItem(value: 'group', child: Text('In Ordner legen (Leicht → Schwer)')),
                    PopupMenuItem(value: 'ungroup', child: Text('Aus Ordner nehmen (einzeln lernen)')),
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
                    'script' => _matchScript(allCards),
                    _ => _importCsv(),
                  },
                  itemBuilder: (_) => [
                    if (allCards.isNotEmpty && _assignProgress == null)
                      const PopupMenuItem(value: 'stages', child: Text('Per KI in Ordner sortieren')),
                    if (allCards.isNotEmpty && _scriptProgress == null)
                      const PopupMenuItem(value: 'script', child: Text('Erklärungen im Skript suchen')),
                    if (allCards.isNotEmpty)
                      const PopupMenuItem(value: 'export', child: Text('Als CSV exportieren')),
                    const PopupMenuItem(value: 'import', child: Text('CSV importieren (Vorder-/Rückseite)')),
                  ],
                ),
              ],
        bottom: (_assignProgress ?? _scriptProgress) == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: _assignProgress ?? _scriptProgress),
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
                          itemCount: entries.length + (conceptOnly ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (conceptOnly && i == 0) {
                              return _ConceptFolderHint(
                                onSort: _assignProgress == null ? () => _assignStagesWithAi(allCards) : null,
                              );
                            }
                            final entry = entries[i - (conceptOnly ? 1 : 0)];
                            final folder = entry.folder;
                            if (folder != null) {
                              final open = _query.isNotEmpty || _openFolders.contains(folder.key);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _StageFolderTile(
                                  folder: folder,
                                  group: groups[folder.key] ?? folder.cards,
                                  stages: stages,
                                  open: open,
                                  onToggleOpen: () => setState(() {
                                    if (!_openFolders.remove(folder.key)) _openFolders.add(folder.key);
                                  }),
                                  selecting: _selecting,
                                  selected: _selected,
                                  onToggleSelected: _toggle,
                                  onSelectAll: (ids, select) => setState(() {
                                    select ? _selected.addAll(ids) : _selected.removeAll(ids);
                                  }),
                                  onRename: () => _renameFolder(folder),
                                  onDissolve: () => _dissolveFolder(folder, (groups[folder.key] ?? folder.cards).length),
                                ),
                              );
                            }
                            final card = entry.card!;
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

/// Eingabe eines Ordnernamens – eigenes State-Objekt, damit das Textfeld
/// seinen Controller erst nach dem Schließen des Dialogs freigibt.
class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('folder-name'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name (was die Fragen abfragen)'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text), child: const Text('Speichern')),
      ],
    );
  }
}

/// Hinweis, solange Ordner nur nach Konzept gebildet sind – ob die Fragen
/// darin wirklich dasselbe abfragen, hat dann niemand geprüft.
class _ConceptFolderHint extends StatelessWidget {
  const _ConceptFolderHint({required this.onSort});
  final VoidCallback? onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Einige Ordner sind nur nach Konzept gebildet. Ob die Fragen darin wirklich dasselbe Wissen '
            'abfragen (sonst würde eine leichte Frage zu früh aus dem Plan genommen), prüft die KI beim '
            'Sortieren.',
            style: TextStyle(fontSize: 12.5, color: c.ink),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('concept-hint-sort'),
              onPressed: onSort,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Per KI sortieren'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ein Ordner der Kartenliste: dieselbe Frage in Leicht/Mittel/Schwer.
/// Zugeklappt stehen Name, schwerste Frage und der Stufenstand darauf,
/// aufgeklappt die Karten je Stufe.
class _StageFolderTile extends StatelessWidget {
  const _StageFolderTile({
    required this.folder,
    required this.group,
    required this.stages,
    required this.open,
    required this.onToggleOpen,
    required this.selecting,
    required this.selected,
    required this.onToggleSelected,
    required this.onSelectAll,
    required this.onRename,
    required this.onDissolve,
  });

  /// Die sichtbaren Karten des Ordners (bei einer Suche ggf. nur ein Teil).
  final StageFolder folder;

  /// Die komplette Gruppe – für Stufenstand und Anzahl.
  final List<Flashcard> group;
  final Map<String, StageStatus> stages;
  final bool open;
  final VoidCallback onToggleOpen;
  final bool selecting;
  final Set<String> selected;
  final void Function(String id) onToggleSelected;
  final void Function(List<String> ids, bool select) onSelectAll;
  final VoidCallback onRename;
  final VoidCallback onDissolve;

  static String _levelState(StageLevel level, StageLevel active, bool allMastered) {
    if (level.index < active.index) return 'geschafft – ruht';
    if (level.index > active.index) return 'wartet';
    return allMastered ? 'sitzt – nur noch Wiederholung' : 'gerade dran';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = StageGate.activeLevel(group) ?? StageLevel.leicht;
    final allMastered = group.every(StageGate.isMastered);
    final levels = {for (final card in group) StageGate.levelOf(card)}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final ids = [for (final card in folder.cards) card.id];
    final chosen = ids.where(selected.contains).length;
    final hardest = StageGate.byLevel(group).last;
    final title = folder.name ?? hardest.front;

    Widget chip(StageLevel level) {
      final count = group.where((card) => StageGate.levelOf(card) == level).length;
      final (fg, bg, icon) = level.index < active.index || (allMastered && level == active)
          ? (c.good, c.goodSoft, Icons.check)
          : level == active
              ? (c.accent, c.accentSoft, Icons.play_arrow_rounded)
              : (c.inkMuted, c.surfaceAlt, Icons.lock_outline);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 3),
            Text(count > 1 ? '${level.label} ($count)' : level.label,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      );
    }

    final header = InkWell(
      key: ValueKey('folder-${folder.key}'),
      onTap: onToggleOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selecting)
              Checkbox(
                tristate: true,
                value: chosen == 0 ? false : (chosen == ids.length ? true : null),
                onChanged: (_) => onSelectAll(ids, chosen < ids.length),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 12, 0),
                child: Icon(open ? Icons.folder_open_outlined : Icons.folder_outlined, color: c.accent),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  if (folder.name != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hardest.front,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final level in levels) chip(level),
                      Text('${group.length} Fragen${folder.byConceptOnly ? ' · nach Konzept' : ''}',
                          style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                    ],
                  ),
                ],
              ),
            ),
            if (!selecting)
              PopupMenuButton<String>(
                tooltip: 'Ordner bearbeiten',
                icon: Icon(Icons.more_vert, color: c.inkMuted, size: 20),
                onSelected: (v) => v == 'rename' ? onRename() : onDissolve(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
                  PopupMenuItem(value: 'dissolve', child: Text('Auflösen (alle einzeln lernen)')),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Icon(open ? Icons.expand_less : Icons.expand_more, color: c.inkMuted),
            ),
          ],
        ),
      ),
    );

    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: chosen > 0 ? c.accent : c.border, width: 1.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final level in levels)
                    if (folder.cards.any((card) => StageGate.levelOf(card) == level)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                        child: Text(
                          '${level.label} · ${_levelState(level, active, allMastered)}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted),
                        ),
                      ),
                      for (final card in folder.cards.where((card) => StageGate.levelOf(card) == level))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _FlashcardTile(
                            card: card,
                            stage: StageGate.statusOf(stages, card),
                            selecting: selecting,
                            selected: selected.contains(card.id),
                            onToggleSelected: () => onToggleSelected(card.id),
                          ),
                        ),
                    ],
                ],
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
      if (card.hasScript) 'Erklärung im Skript, S. ${card.scriptPage}',
      if ((card.type == QuestionType.dragDrop || card.type == QuestionType.dragCategory) &&
          AnswerChecker.isTrivialDrag(card))
        'zu wenig Paare – wird als Karteikarte abgefragt',
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
              if (chain != null && chain.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _ChainStages(card: card),
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

/// Die Stufen einer Karte mit eigener Stufenkette (z.B. aus "Frage
/// erstellen" mit Leicht/Mittel/Schwer): welche geschafft ist, welche gerade
/// dran ist und welche noch kommt – mit der Frage, soweit schon bekannt.
class _ChainStages extends StatelessWidget {
  const _ChainStages({required this.card});
  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chain = card.variantChain!;
    final history = card.variantHistory ?? const <VariantSnapshot>[];
    final pending = card.pendingVariants ?? const <VariantSnapshot>[];
    String? frontAt(int i) {
      if (i == card.variantLevel) return card.front;
      if (i < card.variantLevel) {
        final h = history.length - (card.variantLevel - i);
        return h >= 0 && h < history.length ? history[h].front : null;
      }
      final p = i - card.variantLevel - 1;
      return p < pending.length ? pending[p].front : null;
    }

    String name(int i) => chain.length == 3 ? StageLevel.values[i].label : 'Stufe ${i + 1}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stufen dieser Frage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
          for (var i = 0; i < chain.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    i < card.variantLevel
                        ? Icons.check
                        : i == card.variantLevel
                            ? Icons.play_arrow_rounded
                            : Icons.lock_outline,
                    size: 15,
                    color: i < card.variantLevel ? c.good : (i == card.variantLevel ? c.accent : c.inkMuted),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${name(i)} · ${chain[i].label}'
                      '${i == card.variantLevel ? ' (gerade dran)' : ''}: '
                      '${frontAt(i) ?? 'wird beim Erreichen von der KI erstellt'}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: i == card.variantLevel ? c.ink : c.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
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
      case QuestionType.learn:
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
