import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/flashcard.dart';
import '../../models/interactive_task.dart';
import '../../models/material_item.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/import_reference.dart';
import '../../services/import_stage_service.dart';
import '../../services/import_verify_service.dart';
import '../../services/interactive_task_scan_service.dart';
import '../../services/material_file_store.dart';
import '../../services/pdf_question_import_service.dart';
import '../../services/pdf_service.dart';
import '../../services/question_parsing.dart';
import '../../services/stage_gate_service.dart';
import '../../theme/app_colors.dart';
import '../practice/practice_screen.dart';
import '../study/script_match_runner.dart';
import '../tasks/task_import_screen.dart';
import '../widgets/discard_guard.dart';
import '../widgets/import_check_panel.dart';
import '../widgets/import_options_card.dart';
import '../widgets/math_text.dart';
import '../widgets/safe_set_state.dart';

enum _Step { pick, scanning, preview }

enum _UncertainDecision { keep, skip }

/// "Fragen aus PDF importieren": beliebig viele PDFs auf einmal (aus dem Fach
/// oder hochgeladen, auch per Drag-and-drop). Die KI liest jede fortlaufend in
/// überlappenden Abschnitten – ein paar Seiten, dann die letzte davon noch
/// einmal mit den nächsten, damit eine Aufgabe über den Seitenumbruch nicht
/// zerrissen wird (siehe PdfQuestionImportService) – und übernimmt jede dort
/// vorhandene Frage. Vorher wählt man, ob wirklich jede Frage oder nur
/// inhaltliche, und ob fehlende Lösungen ergänzt werden. Die Treffer lassen
/// sich vor dem Import einzeln abwählen; danach landen sie als Karten im Fach
/// und lassen sich sofort üben.
///
/// Im Modus „Interaktive Aufgaben“ ([interactive]) baut die KI stattdessen
/// interaktive Aufgaben (Rechenweg, Terminierung, Kristall, Stückliste,
/// Skizze) aus dem Dokument – auf Wunsch nur bestimmte, z.B. „alle
/// Mathe-Aufgaben als Rechenweg“ (InteractiveTaskScanService). Die Funde
/// kommen zum Prüfen in „Aufgabe übernehmen“ (TaskImportScreen).
class PdfQuestionImportScreen extends StatefulWidget {
  const PdfQuestionImportScreen({
    super.key,
    required this.moduleId,
    this.moduleName = '',
    this.material,
    this.materials = const [],
    this.serviceFactory,
    this.aiFactory,
    this.interactive = false,
    this.initialInstruction = '',
    this.interactiveServiceFactory,
  });

  final String moduleId;
  final String moduleName;

  /// Direkt mit diesem Material starten (Knopf an einer PDF im Fach).
  final MaterialItem? material;

  /// Direkt mit diesen Materialien starten (z.B. gerade hochgeladen).
  final List<MaterialItem> materials;

  /// Nur für Tests: eigener Import-Dienst statt des Vision-Modells aus den
  /// Einstellungen.
  @visibleForTesting
  final PdfQuestionImportService Function()? serviceFactory;

  /// Nur für Tests: KI-Zugang für die Prüfung durch die zweite KI und die
  /// Stufen-Erweiterung (Argument = Modell-ID), statt des echten
  /// [AiService] mit dem API-Key aus den Einstellungen.
  @visibleForTesting
  final AiService Function(String model)? aiFactory;

  /// Gleich im Modus „Interaktive Aufgaben“ starten.
  final bool interactive;

  /// Vorbelegter Wunsch, welche Aufgaben übernommen werden.
  final String initialInstruction;

  /// Nur für Tests: eigener Dienst für interaktive Aufgaben.
  @visibleForTesting
  final InteractiveTaskScanService Function()? interactiveServiceFactory;

  @override
  State<PdfQuestionImportScreen> createState() => _PdfQuestionImportScreenState();
}

/// Eine für den Import gewählte PDF.
class _ImportFile {
  _ImportFile({required this.name, required this.bytes, required this.pageTexts, this.material});

  final String name;
  final Uint8List bytes;

  /// Text je Seite (Index 0 = Seite 1) – die Zahl der Seiten und die Grundlage
  /// für Abschnittsplanung und Prüfung.
  final List<String> pageTexts;

  /// Schon im Fach vorhandenes Material (sonst wird die PDF beim Import als
  /// Übung abgelegt).
  final MaterialItem? material;
  MaterialItem? saved;

  int get pageCount => pageTexts.length;
}

class _PdfQuestionImportScreenState extends State<PdfQuestionImportScreen>
    with SafeSetState<PdfQuestionImportScreen> {
  _Step _step = _Step.pick;

  /// Interaktive Aufgaben statt Quizfragen (siehe [PdfQuestionImportScreen.interactive]).
  late bool _interactive = widget.interactive;
  late final _instruction = TextEditingController(text: widget.initialInstruction);

  /// Vorgegebene Art; null = die KI entscheidet je Aufgabe.
  InteractiveKind? _kind;

  final List<_ImportFile> _files = [];
  final _fromController = TextEditingController(text: '1');
  final _toController = TextEditingController();
  bool _loadingPdf = false;
  bool _dragOver = false;

  bool _contentOnly = true;
  bool _fillMissing = true;

  /// Prüfung durch die zweite KI und Schwierigkeitsstufen (siehe
  /// [ImportOptionsCard]).
  ImportOptions _options = const ImportOptions();

  /// Text der laufenden Nachbearbeitung (Stufen, Prüfung) statt des
  /// Abschnitt-Zählers; leer = die Seiten werden noch gelesen.
  String _phase = '';
  String _scanLabel = '';

  ImportCheckReport? _report;

  /// Die Fragen, gegen die geprüft wurde – [ImportFinding.ref] ist die
  /// Position darin.
  List<ScannedQuestion> _checked = const [];
  bool _checking = false;
  String? _checkProgress;
  final Map<int, FindingDecision> _decisions = {};
  final Set<int> _busyFindings = {};
  String? _stageNote;

  int _done = 0;
  int _total = 0;
  bool _cancelled = false;

  List<ScannedQuestion> _questions = [];

  /// Nicht gelesene Seiten je Datei (zum erneuten Versuch).
  Map<String, List<List<int>>> _failed = {};
  List<String> _errors = [];
  List<String> _notes = [];
  int _dropped = 0;
  bool _saving = false;

  /// Die KI hat die Seiten als Bild gesehen – nur dann können Abbildungen
  /// an den Fragen hängen.
  bool _usedPageImages = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final start = [?widget.material, ...widget.materials];
    if (start.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _useAllMaterials(start));
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _instruction.dispose();
    super.dispose();
  }

  bool get _single => _files.length == 1;

  /// Nimmt eine PDF auf – false, wenn sie schon dabei ist oder sich nicht
  /// lesen lässt.
  bool _addFile({required Uint8List bytes, required String name, MaterialItem? material}) {
    if (_files.any((f) => (material != null && f.material?.id == material.id) || (f.name == name && f.bytes.length == bytes.length))) {
      return false;
    }
    final List<String> texts;
    try {
      texts = PdfService().extractPageTexts(bytes);
    } catch (e) {
      setState(() => _error = '„$name“ konnte nicht gelesen werden: $e');
      return false;
    }
    if (texts.isEmpty) {
      setState(() => _error = '„$name“ hat keine Seiten.');
      return false;
    }
    setState(() {
      _files.add(_ImportFile(name: name, bytes: bytes, pageTexts: texts, material: material));
      _error = null;
      if (_single) {
        _fromController.text = '1';
        _toController.text = '${texts.length}';
      }
    });
    return true;
  }

  Future<void> _useMaterial(MaterialItem material) async {
    setState(() => _loadingPdf = true);
    final bytes = await MaterialFileStore.load(filePath: material.filePath, fileBytesBase64: material.fileBytesBase64);
    if (!mounted) return;
    setState(() => _loadingPdf = false);
    if (bytes == null) {
      setState(() => _error = 'Die PDF von „${material.fileName}“ liegt nicht auf diesem Gerät – öffne sie '
          'einmal im Fach (lädt sie aus deinem Speicher) oder lade sie hier hoch.');
      return;
    }
    _addFile(bytes: bytes, name: material.fileName, material: material);
  }

  /// Alle noch nicht gewählten PDFs des Fachs auf einmal.
  Future<void> _useAllMaterials(List<MaterialItem> materials) async {
    for (final m in materials) {
      await _useMaterial(m);
      if (!mounted) return;
    }
  }

  /// Eine hier hochgeladene PDF landet beim Import als Übung im Fach – so
  /// führen die Fragen später per "Im Skript ansehen" zu ihrer Seite.
  Future<MaterialItem?> _saveUploadedPdf(_ImportFile file) async {
    final repo = context.read<MaterialRepository>();
    try {
      final id = const Uuid().v4();
      final (filePath, fileBytesBase64) = await MaterialFileStore.store(id, file.bytes);
      final material = MaterialItem(
        id: id,
        moduleId: widget.moduleId,
        fileName: file.name,
        kind: MaterialKind.exercise,
        extractedText: file.pageTexts.join('\n'),
        createdAt: DateTime.now(),
        filePath: filePath,
        fileBytesBase64: fileBytesBase64,
      );
      await repo.save(material);
      file.saved = material;
      return material;
    } catch (_) {
      return null;
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (picked.isEmpty || !mounted) return;
    await _addPicked([for (final f in picked) (name: f.name, readBytes: f.readAsBytes)]);
  }

  Future<void> _handleDrop(List<XFile> files) async {
    setState(() => _dragOver = false);
    await _addPicked([
      for (final f in files)
        if (f.name.toLowerCase().endsWith('.pdf')) (name: f.name, readBytes: f.readAsBytes),
    ]);
  }

  Future<void> _addPicked(List<({String name, Future<Uint8List> Function() readBytes})> files) async {
    if (files.isEmpty) return;
    setState(() => _loadingPdf = true);
    for (final f in files) {
      final bytes = await f.readBytes();
      if (!mounted) return;
      _addFile(bytes: bytes, name: f.name);
    }
    if (mounted) setState(() => _loadingPdf = false);
  }

  ({int from, int to})? get _range {
    if (_files.isEmpty) return null;
    if (!_single) return (from: 1, to: 0);
    final from = int.tryParse(_fromController.text.trim());
    final to = int.tryParse(_toController.text.trim());
    if (from == null || to == null || from < 1 || to > _files.single.pageCount || from > to) return null;
    return (from: from, to: to);
  }

  /// Bei mehreren PDFs immer alles, bei einer der gewählte Bereich.
  List<ImportSource> _sources() {
    final range = _range;
    return [
      for (final f in _files)
        ImportSource(
          name: f.name,
          bytes: f.bytes,
          pageTexts: f.pageTexts,
          firstPage: _single ? range?.from : null,
          lastPage: _single ? range?.to : null,
        ),
    ];
  }

  Future<void> _scan({bool retry = false}) async {
    if (_files.isEmpty || _range == null) return;
    final service = _importService();
    if (service == null) {
      setState(() => _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte in den Einstellungen eintragen.');
      return;
    }
    setState(() {
      _step = _Step.scanning;
      _cancelled = false;
      _done = 0;
      _total = 0;
      _phase = '';
      _scanLabel = '';
      _error = null;
    });
    final results = await service.scanMany(
      _sources(),
      contentOnly: _contentOnly,
      fillMissingSolutions: _fillMissing,
      retry: retry ? _failed : null,
      onProgress: (done, total, label) => setState(() {
        _done = done;
        _total = total;
        _scanLabel = label;
      }),
      isCancelled: () => _cancelled,
    );
    if (!mounted) return;
    final fresh = [for (final r in results) ...r.questions];
    setState(() {
      String tag(String file, String text) => _single ? text : '$file: $text';
      final failed = <String, List<List<int>>>{};
      final errors = <String>[];
      final notes = <String>[];
      var dropped = 0;
      var allImages = true;
      for (final (i, r) in results.indexed) {
        final name = _files[i].name;
        if (r.failedBatches.isNotEmpty) failed[name] = r.failedBatches;
        errors.addAll([for (final e in r.errors) tag(name, e)]);
        if (r.revised > 0) {
          notes.add(tag(
              name,
              '${r.revised} ${r.revised == 1 ? 'Frage wurde' : 'Fragen wurden'} durch die nächste Seite '
              'vervollständigt.'));
        }
        notes.addAll([for (final n in r.notes) tag(name, n)]);
        dropped += r.dropped;
        if (r.windows > 0 && !r.usedPageImages) allImages = false;
      }
      if (!retry) {
        _questions = fresh;
        _dropped = dropped;
        _usedPageImages = allImages;
        _notes = notes;
        _report = null;
        _checked = const [];
        _decisions.clear();
        _busyFindings.clear();
        _stageNote = null;
      } else {
        _questions = _sortedByFile([..._questions, ...fresh]);
        _dropped += dropped;
        _usedPageImages = _usedPageImages && allImages;
        _notes = [..._notes, ...notes];
      }
      _failed = failed;
      _errors = errors;
      // Bei einem Abbruch oder ohne Treffer gibt es nichts nachzubearbeiten.
      if (_cancelled || fresh.isEmpty) _step = _Step.preview;
    });
    if (_cancelled || fresh.isEmpty) return;
    if (_options.expandStages) await _expandStages(fresh);
    if (!mounted) return;
    if (_options.verify) await _runCheck();
    if (!mounted) return;
    setState(() {
      _phase = '';
      _step = _Step.preview;
    });
  }

  /// Nach Datei (Reihenfolge der Auswahl) und Seite, sonst in der bisherigen
  /// Reihenfolge.
  List<ScannedQuestion> _sortedByFile(List<ScannedQuestion> questions) {
    int fileIndex(ScannedQuestion q) => _files.indexWhere((f) => f.name == q.sourceFile);
    final indexed = questions.indexed.toList()
      ..sort((a, b) {
        final byFile = fileIndex(a.$2).compareTo(fileIndex(b.$2));
        if (byFile != 0) return byFile;
        final byPage = a.$2.page.compareTo(b.$2.page);
        return byPage != 0 ? byPage : a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$2];
  }

  /// Der Import-Dienst mit dem Vision-Modell; null ohne API-Key.
  PdfQuestionImportService? _importService() {
    final factory = widget.serviceFactory;
    if (factory != null) return factory();
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return null;
    return PdfQuestionImportService(ai: AiService(apiKey: settings.openRouterApiKey!, model: settings.visionModelId));
  }

  /// KI-Zugang mit [model] für Prüfung und Stufen; null ohne API-Key.
  AiService? _aiFor(String model) {
    final factory = widget.aiFactory;
    if (factory != null) return factory(model);
    final settings = context.read<SettingsRepository>().settings;
    return settings.hasApiKey ? AiService(apiKey: settings.openRouterApiKey!, model: model) : null;
  }

  String _answerOf(ScannedQuestion q) =>
      PdfQuestionImportService.toFlashcards([q], moduleId: widget.moduleId, now: DateTime(2000)).single.answerSummary;

  List<ScannedQuestion> get _originals => [for (final q in _questions) if (!q.isStageVariant) q];

  /// Ergänzt zu [fresh] (im Dokument gefundene Fragen) die gewählten
  /// Schwierigkeitsstufen: das Original behält seinen Wortlaut und bekommt
  /// Stufe und Ordner, die KI schreibt die übrigen Stufen dazu. Ein Fehler
  /// lässt die Fragen einfach ohne Stufen.
  Future<void> _expandStages(List<ScannedQuestion> fresh) async {
    final settings = context.read<SettingsRepository>().settings;
    final ai = _aiFor(settings.questionModelId);
    if (ai == null || fresh.isEmpty) return;
    setState(() => _phase = 'Schwierigkeitsstufen werden ergänzt …');
    final run = await ImportStageService(ai: ai).expand(
      [
        for (final (i, q) in fresh.indexed)
          StageInput(ref: i, type: (q.data['type'] ?? 'flashcard').toString(), front: q.front, answer: _answerOf(q)),
      ],
      levels: _options.levels.toList(),
      takenGroups: [for (final q in _questions) ?QuestionParsing.parseStageGroup(q.data['group'])],
      tierTypes: {
        for (final level in AiService.stageLevelNames) level: ?settings.pageTierType(level),
      },
      onProgress: (done, total) => setState(() => _phase = 'Schwierigkeitsstufen werden ergänzt … $done von $total'),
    );
    if (!mounted) return;
    setState(() {
      final variants = <ScannedQuestion, List<ScannedQuestion>>{};
      for (final (i, q) in fresh.indexed) {
        final r = run.results[i];
        if (r == null) continue;
        q.data['level'] = AiService.stageLevelNames[r.level];
        if (r.group != null) q.data['group'] = r.group;
        variants[q] = [
          for (final v in r.variants)
            ScannedQuestion(page: q.page, data: {...v, 'group': r.group}, solutionByAi: true)
              ..variantOf = q
              ..sourceFile = q.sourceFile,
        ];
      }
      _questions = [
        for (final q in _questions) ...[q, ...?variants[q]],
      ];
      final missing = run.failedCards + run.droppedVariants;
      _stageNote = missing == 0
          ? null
          : '${run.failedCards > 0 ? '${run.failedCards} ${run.failedCards == 1 ? 'Frage bleibt' : 'Fragen bleiben'} ohne Stufen (KI-Anfrage fehlgeschlagen). ' : ''}'
              '${run.droppedVariants > 0 ? '${run.droppedVariants} ${run.droppedVariants == 1 ? 'Stufe war' : 'Stufen waren'} unvollständig und ${run.droppedVariants == 1 ? 'wurde' : 'wurden'} verworfen.' : ''}';
    });
  }

  /// Die zweite KI prüft, ob alle Fragen der PDFs übernommen wurden (siehe
  /// ImportVerifyService). Ändert nichts – nur ein Bericht mit
  /// Begründungen, über den der Nutzer entscheidet.
  Future<void> _runCheck() async {
    final settings = context.read<SettingsRepository>().settings;
    final ai = _aiFor(settings.crosscheckModelId);
    if (_files.isEmpty) return;
    if (ai == null) {
      setState(() => _error = 'Für die Prüfung wird ein OpenRouter-API-Key gebraucht (Einstellungen).');
      return;
    }
    final originals = _originals;
    final range = _range;
    setState(() {
      _checking = true;
      _checkProgress = 'Zweite KI liest das Dokument …';
      _report = null;
      _decisions.clear();
      _busyFindings.clear();
      _phase = 'Zweite KI prüft die Vollständigkeit …';
    });
    final parts = <({String fileName, ImportCheckReport report})>[];
    for (final file in _files) {
      final report = await ImportVerifyService(ai: ai).verify(
        pageTexts: file.pageTexts,
        items: [
          for (final (i, q) in originals.indexed)
            if ((q.sourceFile ?? _files.first.name) == file.name)
              ImportedItem(ref: i, page: q.page, front: q.front, answer: _answerOf(q)),
        ],
        contentOnly: _contentOnly,
        fileName: file.name,
        firstPage: _single ? range?.from ?? 1 : 1,
        lastPage: _single ? range?.to : null,
        onProgress: (done, total) => setState(() {
          _checkProgress = '${file.name}: zweite KI liest das Dokument … $done von $total';
          _phase = 'Zweite KI prüft die Vollständigkeit … $done von $total';
        }),
      );
      parts.add((fileName: file.name, report: report));
    }
    if (!mounted) return;
    setState(() {
      _report = ImportCheckReport.merge(parts);
      _checked = originals;
      _checking = false;
      _checkProgress = null;
      _phase = '';
    });
  }

  /// "Ergänzen" (fehlende Aufgabe nachholen) bzw. "Entfernen" (zu viel:
  /// abwählen) bei einem Befund.
  Future<void> _acceptFinding(int index) async {
    final finding = _report?.findings[index];
    if (finding == null) return;
    if (!finding.isMissing) {
      final q = finding.ref == null || finding.ref! >= _checked.length ? null : _checked[finding.ref!];
      setState(() {
        if (q != null) {
          q.selected = false;
          for (final v in _questions.where((v) => v.variantOf == q)) {
            v.selected = false;
          }
        }
        _decisions[index] = FindingDecision.accepted;
      });
      return;
    }
    final file = _files.where((f) => f.name == (finding.fileName ?? _files.first.name)).firstOrNull;
    final service = _importService();
    if (file == null || service == null) return;
    setState(() => _busyFindings.add(index));
    final result = await service.scan(
      file.bytes,
      firstPage: finding.page,
      lastPage: finding.page,
      contentOnly: false,
      fillMissingSolutions: _fillMissing,
      pageTexts: file.pageTexts,
      focus: finding.text,
    );
    if (!mounted) return;
    for (final q in result.questions) {
      q.addedByCheck = true;
      q.sourceFile = file.name;
    }
    setState(() {
      _busyFindings.remove(index);
      if (result.questions.isEmpty) {
        _error = 'Die KI konnte diese Aufgabe nicht übernehmen'
            '${result.errors.isEmpty ? '.' : ': ${result.errors.first}'}';
        return;
      }
      _error = null;
      _questions = _sortedByFile([..._questions, ...result.questions]);
      _decisions[index] = FindingDecision.accepted;
    });
    if (_options.expandStages && result.questions.isNotEmpty) await _expandStages(result.questions);
    if (mounted) setState(() => _phase = '');
  }

  /// Fragen, bei denen die KI eine präzisere Struktur wollte (z.B.
  /// single_choice/free_text/html), ihre Antwort dafür aber unvollständig
  /// war, landen NICHT stumm als schlichte Karteikarte: am Ende des Imports
  /// wird gefragt, wie damit verfahren werden soll – trotzdem als Karteikarte
  /// speichern oder weglassen (in der Vorschau bleiben sie ausgewählt, damit
  /// man sie vor dem Import auch selbst noch abwählen oder als html-Frage
  /// nachbauen kann).
  Future<_UncertainDecision?> _resolveUncertainQuestions(int count) => showDialog<_UncertainDecision>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$count ${count == 1 ? 'Frage' : 'Fragen'} unsicher erkannt'),
          content: Text(
            'Bei $count ${count == 1 ? 'Frage konnte' : 'Fragen konnten'} die KI die eigentlich passende '
            'Struktur (z.B. Auswahl, Freitext oder eine interaktive Aufgabe) nicht sauber umsetzen – sie '
            'wurden stattdessen als einfache Karteikarte vorbereitet. Trotzdem so speichern (später in der '
            'Kartenliste bearbeitbar) oder weglassen?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(_UncertainDecision.skip),
              child: const Text('Weglassen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_UncertainDecision.keep),
              child: const Text('Als Karteikarte speichern'),
            ),
          ],
        ),
      );

  Future<void> _import() async {
    var selected = _questions.where((q) => q.selected).toList();
    if (selected.isEmpty) return;
    final uncertain = selected.where((q) => q.typeDowngraded).toList();
    if (uncertain.isNotEmpty) {
      final decision = await _resolveUncertainQuestions(uncertain.length);
      if (!mounted || decision == null) return;
      if (decision == _UncertainDecision.skip) {
        selected = selected.where((q) => !q.typeDowngraded).toList();
        if (selected.isEmpty) return;
      }
    }
    setState(() => _saving = true);
    final base = DateTime.now();
    final cards = <Flashcard>[];
    var unsaved = 0;
    for (final (i, file) in _files.indexed) {
      final mine = [
        for (final q in selected)
          if ((q.sourceFile ?? _files.first.name) == file.name) q,
      ];
      if (mine.isEmpty) continue;
      final material = file.material ?? file.saved ?? await _saveUploadedPdf(file);
      if (!mounted) return;
      if (material == null) unsaved++;
      cards.addAll(PdfQuestionImportService.toFlashcards(
        mine,
        moduleId: widget.moduleId,
        unitId: material?.unitId,
        sourceMaterialId: material?.id,
        sourceKind: material?.kind ?? MaterialKind.exercise,
        // Jede Datei ein eigener Zeitpunkt: die Reihenfolge der Dateien und
        // ihre Ordner (Stufen) bleiben getrennt.
        now: base.add(Duration(seconds: i)),
      ));
    }
    await context.read<FlashcardRepository>().saveAll(cards);
    if (!mounted) return;
    // Fragen aus einem Arbeitsblatt: Erklärung im Skript suchen.
    unawaited(matchNewCardsToScript(context, cards));
    setState(() {
      _saving = false;
      _questions = [];
      _step = _Step.pick;
    });
    if (unsaved > 0) {
      // Das Arbeitsblatt konnte nicht gespeichert werden (z.B. kein
      // Speicherplatz) – die Karten sind trotzdem da, nur "Im Skript" findet
      // dafür keine exakte Seite mehr (nur noch die Textsuche über andere
      // Materialien des Fachs, falls vorhanden).
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Ein Arbeitsblatt konnte nicht gespeichert werden – die Fragen sind trotzdem importiert, '
            '„Im Skript“ findet dafür aber keine genaue Seite.'),
        duration: Duration(seconds: 5),
      ));
    }
    final practice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${cards.length} ${cards.length == 1 ? 'Frage' : 'Fragen'} importiert'),
        content: const Text('Sie kommen nach und nach ins Daily Quiz. Du kannst sie auch gleich üben.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Fertig')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Jetzt üben')),
        ],
      ),
    );
    if (!mounted) return;
    if (practice == true) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PracticeScreen.cards(
          title: 'Import · ${_single ? _files.single.name : '${_files.length} PDFs'}',
          cards: cards,
        ),
      ));
    } else {
      Navigator.of(context).pop();
    }
  }

  // -- Interaktive Aufgaben ---------------------------------------------------

  /// Der Dienst für interaktive Aufgaben mit dem Vision-Modell; null ohne
  /// API-Key.
  InteractiveTaskScanService? _interactiveService() {
    final factory = widget.interactiveServiceFactory;
    if (factory != null) return factory();
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return null;
    return InteractiveTaskScanService(
      ai: AiService(apiKey: settings.openRouterApiKey!, model: settings.visionModelId),
    );
  }

  /// KI-Anfragen für die interaktiven Aufgaben (Abschnitte aller PDFs).
  int _interactiveRequests(({int from, int to}) range) => _files.fold<int>(
    0,
    (sum, f) =>
        sum +
        InteractiveTaskScanService.windowsFor(
          _single ? range.from : 1,
          _single ? range.to : f.pageCount,
          InteractiveTaskScanService.defaultPagesPerRequest,
        ).length,
  );

  /// Liest alle PDFs und öffnet die Funde in „Aufgabe übernehmen“.
  /// Hochgeladene PDFs werden vorher als Übung im Fach abgelegt, damit die
  /// Aufgaben später zu ihrer Seite führen.
  Future<void> _scanInteractive() async {
    final range = _range;
    if (_files.isEmpty || range == null) return;
    final service = _interactiveService();
    if (service == null) {
      setState(() => _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte in den Einstellungen eintragen.');
      return;
    }
    final total = _interactiveRequests(range);
    setState(() {
      _step = _Step.scanning;
      _cancelled = false;
      _done = 0;
      _total = total;
      _phase = '';
      _scanLabel = '';
      _error = null;
    });
    final drafts = <ScannedTaskDraft>[];
    final notes = <String>[];
    var offset = 0;
    for (final (i, file) in _files.indexed) {
      if (_cancelled) break;
      final material = file.material ?? file.saved ?? await _saveUploadedPdf(file);
      if (!mounted) return;
      final source = _sources()[i];
      setState(() => _scanLabel = file.name);
      final result = await service.scan(
        source,
        instruction: _instruction.text.trim(),
        kind: _kind,
        materialId: material?.id,
        onProgress: (done, _) => setState(() => _done = offset + done),
        isCancelled: () => _cancelled,
      );
      if (!mounted) return;
      offset += result.windows;
      drafts.addAll(result.drafts);
      notes.addAll([for (final e in result.errors) _single ? e : '${file.name}: $e']);
    }
    if (!mounted) return;
    final cancelled = _cancelled;
    if (drafts.isEmpty) {
      setState(() {
        _step = _Step.pick;
        _error = [
          cancelled
              ? 'Abgebrochen – bis dahin wurde keine passende Aufgabe gefunden.'
              : 'Keine passende Aufgabe gefunden.${_instruction.text.trim().isEmpty ? '' : ' Formuliere den Wunsch '
                    'vielleicht etwas allgemeiner.'}',
          ...notes,
        ].join('\n');
      });
      return;
    }
    if (cancelled) notes.insert(0, 'Abgebrochen – hier stehen die bis dahin gefundenen Aufgaben.');
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TaskImportScreen(
          moduleId: widget.moduleId,
          moduleName: widget.moduleName,
          initialDrafts: drafts,
          scanNotes: notes,
        ),
      ),
    );
  }

  // -- Darstellung -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      active: _step == _Step.preview && _questions.isNotEmpty,
      message: 'Die gefundenen Fragen sind noch nicht importiert.',
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _interactive && _step != _Step.preview ? 'Interaktive Aufgaben aus PDF' : 'Fragen aus PDF importieren',
          ),
          actions: [
            if (_step == _Step.pick)
              TextButton.icon(
                key: const ValueKey('import-json'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TaskImportScreen(
                      moduleId: widget.moduleId,
                      moduleName: widget.moduleName,
                      startWithJsonImport: true,
                    ),
                  ),
                ),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('JSON importieren'),
              ),
          ],
        ),
        body: SafeArea(
          child: switch (_step) {
            _Step.pick => _buildPick(context),
            _Step.scanning => _buildScanning(context),
            _Step.preview => _buildPreview(context),
          },
        ),
      ),
    );
  }

  Widget _buildPick(BuildContext context) {
    final c = context.colors;
    final available = context
        .watch<MaterialRepository>()
        .forModule(widget.moduleId)
        .where((m) =>
            m.hasViewablePdf &&
            m.fileName.toLowerCase().endsWith('.pdf') &&
            !_files.any((f) => f.material?.id == m.id))
        .toList();
    final range = _range;
    final totalPages = _files.fold<int>(0, (sum, f) => sum + f.pageCount);
    final requests = range == null
        ? 0
        : _files.fold<int>(0, (sum, f) {
            final first = _single ? range.from : 1;
            final last = _single ? range.to : f.pageCount;
            return sum +
                planScanWindows(
                  f.pageTexts,
                  firstPage: first,
                  lastPage: last,
                  maxNewPages: PdfQuestionImportService.defaultPagesPerRequest,
                  charBudget: PdfQuestionImportService.defaultCharBudget,
                ).length;
          });
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<bool>(
          key: const ValueKey('import-mode'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.quiz_outlined), label: Text('Fragen')),
            ButtonSegment(value: true, icon: Icon(Icons.touch_app_outlined), label: Text('Interaktive Aufgaben')),
          ],
          selected: {_interactive},
          onSelectionChanged: (s) => setState(() {
            _interactive = s.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 12),
        Text(
          _interactive
              ? 'Die KI liest deine PDFs Seite für Seite und macht aus den Aufgaben darin interaktive Aufgaben – '
                    'Rechenweg Schritt für Schritt, Terminierung, Kristallgitter, Stückliste oder Diagramm-Skizze. '
                    'Sag ihr, welche du willst (z.B. „alle Mathe-Aufgaben als Rechenweg“). Danach prüfst du jede '
                    'Aufgabe mit ihrer Seite und speicherst sie.'
              : 'Die KI sucht in deinen PDFs nach Fragen und Aufgaben, die dort schon stehen (z.B. Altklausur, '
                    'Übungsblatt, Fragen auf Folien), und übernimmt sie ins Quiz – sie erfindet keine neuen. Wähle '
                    'beliebig viele PDFs auf einmal.',
          style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 16),
        Text('PDFs', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropTarget(
          onDragEntered: (_) => setState(() => _dragOver = true),
          onDragExited: (_) => setState(() => _dragOver = false),
          onDragDone: (details) => _handleDrop(details.files),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: _dragOver ? Border.all(color: c.accent, width: 2) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, f) in _files.indexed)
                  Card(
                    key: ValueKey('import-file-$i'),
                    child: ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${f.pageCount} Seite${f.pageCount == 1 ? '' : 'n'}'),
                      trailing: IconButton(
                        key: ValueKey('import-remove-file-$i'),
                        tooltip: 'Entfernen',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _files.removeAt(i);
                          if (_single) {
                            _fromController.text = '1';
                            _toController.text = '${_files.single.pageCount}';
                          }
                        }),
                      ),
                    ),
                  ),
                if (_loadingPdf)
                  const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
                if (available.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Im Fach', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                        ),
                        if (available.length > 1)
                          TextButton(
                            key: const ValueKey('import-add-all'),
                            onPressed: () => _useAllMaterials(available),
                            child: const Text('Alle hinzufügen'),
                          ),
                      ],
                    ),
                  ),
                  for (final m in available)
                    Card(
                      child: ListTile(
                        key: ValueKey('import-material-${m.id}'),
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: Text(m.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.add),
                        onTap: () => _useMaterial(m),
                      ),
                    ),
                ],
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _loadingPdf ? null : _upload,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_files.isEmpty ? 'PDFs hochladen oder hierher ziehen' : 'Weitere PDFs hochladen'),
                ),
              ],
            ),
          ),
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 20),
          if (_single) ...[
            Text('Seiten', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('import-from'),
                    controller: _fromController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'von', border: OutlineInputBorder(), isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('import-to'),
                    controller: _toController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'bis', border: OutlineInputBorder(), isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ] else
            Text(
              'Alle $totalPages Seiten aller ${_files.length} PDFs werden gelesen – ohne Begrenzung.',
              style: TextStyle(fontSize: 13, color: c.inkMuted),
            ),
          if (_interactive)
            ..._interactiveOptions(context, range)
          else ...[
            const SizedBox(height: 20),
            Text('Welche Fragen?', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Jede Frage')),
                ButtonSegment(value: true, label: Text('Nur inhaltliche')),
              ],
              selected: {_contentOnly},
              onSelectionChanged: (s) => setState(() => _contentOnly = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              _contentOnly
                  ? 'Nur Fragen und Aufgaben, die fachliches Wissen prüfen – ohne Organisatorisches, rhetorische '
                      'Einstiegsfragen oder Meinungsfragen.'
                  : 'Wirklich jede Frage und Aufgabe, auch Teilaufgaben und kleine Zwischenfragen auf Folien.',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _fillMissing,
              onChanged: (v) => setState(() => _fillMissing = v),
              title: const Text('Fehlende Lösungen von der KI ergänzen'),
              subtitle: Text(
                'Sonst werden Fragen übersprungen, zu denen im Dokument keine Lösung steht. Eine Musterlösung '
                'in einer anderen der gewählten PDFs wird dafür nachgeschlagen.',
                style: TextStyle(fontSize: 12, color: c.inkMuted),
              ),
            ),
            const SizedBox(height: 8),
            ImportOptionsCard(options: _options, onChanged: (o) => setState(() => _options = o)),
            const SizedBox(height: 12),
            if (range == null)
              Text('Bitte einen gültigen Seitenbereich (1–${_files.single.pageCount}) angeben.',
                  style: TextStyle(color: c.danger))
            else
              Text(
                '$requests KI-Anfrage${requests == 1 ? '' : 'n'} an dein Vision-Modell. Die KI liest fortlaufend: '
                'ein paar neue Seiten (bei viel Text weniger) plus die letzte Seite des vorigen Abschnitts – dort '
                'prüft sie, ob eine begonnene Aufgabe auf den neuen Seiten weitergeht, und ergänzt sie dann. Sie '
                'sieht jede Seite als Bild, übernimmt die Aufgabenform (Ankreuzen, Lücken, Zuordnen, Tabellen, '
                'Beschriften) und hängt nötige Abbildungen als Ausschnitt an.'
                '${_options.verify ? ' Danach prüft die zweite KI die Vollständigkeit.' : ''}'
                '${_options.expandStages ? ' Danach ergänzt die KI die gewählten Stufen.' : ''}',
                style: TextStyle(fontSize: 12, color: c.inkMuted),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: range == null ? null : () => _scan(),
              icon: const Icon(Icons.manage_search),
              label: const Text('Fragen suchen'),
            ),
          ],
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
          ),
      ],
    );
  }

  /// Wunsch, Art und Start für die interaktiven Aufgaben.
  List<Widget> _interactiveOptions(BuildContext context, ({int from, int to})? range) {
    final c = context.colors;
    final requests = range == null ? 0 : _interactiveRequests(range);
    final uploaded = _files.where((f) => f.material == null && f.saved == null).length;
    return [
      const SizedBox(height: 20),
      Text('Welche Aufgaben?', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('import-interactive-instruction'),
        controller: _instruction,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          hintText: 'z.B. alle Mathe-Aufgaben als Rechenweg',
          helperText: 'Leer lassen = jede Aufgabe, die sich interaktiv machen lässt.',
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      Text('Art', style: TextStyle(fontSize: 12, color: c.inkMuted)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          ChoiceChip(
            key: const ValueKey('import-interactive-kind-auto'),
            label: const Text('Automatisch'),
            selected: _kind == null,
            onSelected: (_) => setState(() => _kind = null),
          ),
          for (final k in InteractiveKind.values)
            ChoiceChip(
              key: ValueKey('import-interactive-kind-${k.name}'),
              label: Text(k.label),
              selected: _kind == k,
              onSelected: (_) => setState(() => _kind = k),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (range == null)
        Text(
          'Bitte einen gültigen Seitenbereich (1–${_files.single.pageCount}) angeben.',
          style: TextStyle(color: c.danger),
        )
      else
        Text(
          '$requests KI-Anfrage${requests == 1 ? '' : 'n'} an dein Vision-Modell – je zwei neue Seiten plus die '
          'Seite davor, damit eine Aufgabe über den Seitenumbruch ganz bleibt. Was nicht interaktiv geht, kommt '
          'mit Begründung auf die Sammelliste „Noch nicht interaktiv“.'
          '${uploaded > 0 ? ' Hochgeladene PDFs werden als Übung im Fach abgelegt.' : ''}',
          style: TextStyle(fontSize: 12, color: c.inkMuted),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('import-interactive-start'),
        onPressed: range == null ? null : _scanInteractive,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Interaktive Aufgaben erstellen'),
      ),
    ];
  }

  Widget _buildScanning(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            const SizedBox(height: 16),
            Text(
              _cancelled
                  ? 'Wird abgebrochen – laufende Anfragen werden noch beendet …'
                  : _phase.isNotEmpty
                      ? _phase
                      : 'Seiten werden fortlaufend gelesen … $_done von $_total Abschnitten',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted),
            ),
            if (!_cancelled && _phase.isEmpty && _scanLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_scanLabel, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.inkMuted)),
            ],
            const SizedBox(height: 16),
            if (_phase.isEmpty)
              TextButton(
                onPressed: _cancelled ? null : () => setState(() => _cancelled = true),
                child: const Text('Abbrechen'),
              ),
          ],
        ),
      ),
    );
  }

  String _headline() {
    if (_questions.isEmpty) return 'Keine passenden Fragen gefunden.';
    final originals = _originals;
    final pages = {for (final q in originals) '${q.sourceFile}#${q.page}'}.length;
    final files = {for (final q in originals) q.sourceFile}.length;
    final variants = _questions.length - originals.length;
    return '${originals.length} Frage${originals.length == 1 ? '' : 'n'} auf $pages '
        'Seite${pages == 1 ? '' : 'n'}${files > 1 ? ' in $files PDFs' : ''} gefunden'
        '${variants > 0 ? ' (+ $variants ergänzte ${variants == 1 ? 'Stufe' : 'Stufen'})' : ''}.';
  }

  Widget _buildPreview(BuildContext context) {
    final c = context.colors;
    final selected = _questions.where((q) => q.selected).length;
    final failedCount = _failed.values.fold<int>(0, (sum, batches) => sum + batches.length);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(_headline(), style: Theme.of(context).textTheme.titleMedium),
              if (_dropped > 0)
                Text('$_dropped unvollständige Einträge der KI wurden verworfen.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted)),
              for (final n in _notes) Text(n, style: TextStyle(fontSize: 12, color: c.inkMuted)),
              if (_stageNote != null) Text(_stageNote!, style: TextStyle(fontSize: 12, color: c.warn)),
              if (_error != null) Text(_error!, style: TextStyle(fontSize: 12, color: c.danger)),
              const SizedBox(height: 10),
              ImportCheckPanel(
                report: _report,
                running: _checking,
                progress: _checkProgress,
                decisions: _decisions,
                busy: _busyFindings,
                onRun: _checking || _questions.isEmpty ? null : _runCheck,
                onAccept: _acceptFinding,
                onDismiss: (i) => setState(() => _decisions[i] = FindingDecision.dismissed),
              ),
              const SizedBox(height: 6),
              if (!_usedPageImages && _questions.isNotEmpty)
                Text(
                  'Die Seiten ließen sich auf diesem Gerät nicht als Bild darstellen – Abbildungen sind '
                  'deshalb nur beschrieben statt angehängt.',
                  style: TextStyle(fontSize: 12, color: c.inkMuted),
                ),
              if (_failed.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final e in _errors) Text(e, style: TextStyle(fontSize: 12, color: c.danger)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _scan(retry: true),
                    icon: const Icon(Icons.refresh),
                    label: Text('Fehlgeschlagene Seiten erneut versuchen ($failedCount)'),
                  ),
                ),
              ],
              if (_questions.isNotEmpty)
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        for (final q in _questions) {
                          q.selected = true;
                        }
                      }),
                      child: const Text('Alle'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        for (final q in _questions) {
                          q.selected = false;
                        }
                      }),
                      child: const Text('Keine'),
                    ),
                  ],
                ),
              for (final (i, q) in _questions.indexed) ...[
                if (i == 0 || _questions[i - 1].page != q.page || _questions[i - 1].sourceFile != q.sourceFile)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      _files.length > 1 && q.sourceFile != null ? '${q.sourceFile} · Seite ${q.page}' : 'Seite ${q.page}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted),
                    ),
                  ),
                _questionTile(c, q, i),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _step = _Step.pick),
                child: const Text('Zurück'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: selected == 0 || _saving ? null : _import,
                child: Text('$selected ${selected == 1 ? 'Frage' : 'Fragen'} importieren'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _questionTile(AppColors c, ScannedQuestion q, int index) {
    final preview = PdfQuestionImportService.toFlashcards([q], moduleId: widget.moduleId, now: DateTime(2000))
        .single
        .answerSummary;
    return Card(
      child: CheckboxListTile(
        key: ValueKey('import-question-$index'),
        value: q.selected,
        onChanged: (v) => setState(() => q.selected = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: MathText(q.front, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chip(c, q.type.label),
                if (q.stageLevel case final level?)
                  _chip(c, q.isStageVariant
                      ? 'Stufe ${StageGate.levelFromIndex(level)?.label ?? ''} · von der KI ergänzt'
                      : 'Original · ${StageGate.levelFromIndex(level)?.label ?? ''}'),
                if (q.addedByCheck) _chip(c, 'Nach der Prüfung ergänzt'),
                if (q.solutionByAi && !q.isStageVariant) _chip(c, 'Lösung von der KI', warn: true),
                if (q.typeDowngraded)
                  _chip(c, 'Unsicher: sollte ${q.requestedType?.label ?? 'ein anderer Typ'} sein', warn: true),
              ],
            ),
            if (q.imageBytes case final image?) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true),
                      ),
                    ),
                  ),
                  if (q.canRemoveImage)
                    IconButton(
                      key: ValueKey('import-remove-image-$index'),
                      tooltip: 'Bild entfernen',
                      icon: const Icon(Icons.hide_image_outlined, size: 20),
                      onPressed: () => setState(q.removeImage),
                    ),
                ],
              ),
            ],
            if (preview.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              MathText('Lösung: $preview', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(AppColors c, String text, {bool warn = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: warn ? c.warnSoft : c.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: warn ? c.warn : c.accentOnSoft)),
      );
}
