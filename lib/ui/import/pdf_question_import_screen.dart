import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/flashcard.dart';
import '../../models/material_item.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/material_file_store.dart';
import '../../services/pdf_question_import_service.dart';
import '../../services/pdf_service.dart';
import '../../theme/app_colors.dart';
import '../practice/practice_screen.dart';
import '../study/script_match_runner.dart';
import '../widgets/discard_guard.dart';
import '../widgets/math_text.dart';
import '../widgets/safe_set_state.dart';

enum _Step { pick, scanning, preview }

enum _UncertainDecision { keep, skip }

/// "Fragen aus PDF importieren": die KI sucht jede Seite einer PDF nach den
/// dort vorhandenen Fragen und Aufgaben ab (Altklausur, Übungsblatt, Fragen
/// auf Folien) und übernimmt sie – vorher wählt man, ob wirklich jede Frage
/// oder nur inhaltliche Fragen, und ob fehlende Lösungen ergänzt werden.
/// Die Treffer lassen sich vor dem Import einzeln abwählen; danach landen sie
/// als Karten im Fach und lassen sich sofort üben.
class PdfQuestionImportScreen extends StatefulWidget {
  const PdfQuestionImportScreen({
    super.key,
    required this.moduleId,
    this.moduleName = '',
    this.material,
    this.serviceFactory,
  });

  final String moduleId;
  final String moduleName;

  /// Direkt mit diesem Material starten (Knopf an einer PDF im Fach).
  final MaterialItem? material;

  /// Nur für Tests: eigener Import-Dienst statt des Vision-Modells aus den
  /// Einstellungen.
  @visibleForTesting
  final PdfQuestionImportService Function()? serviceFactory;

  @override
  State<PdfQuestionImportScreen> createState() => _PdfQuestionImportScreenState();
}

class _PdfQuestionImportScreenState extends State<PdfQuestionImportScreen>
    with SafeSetState<PdfQuestionImportScreen> {
  _Step _step = _Step.pick;

  MaterialItem? _material;
  String? _fileName;
  Uint8List? _bytes;
  int _pageCount = 0;
  final _fromController = TextEditingController(text: '1');
  final _toController = TextEditingController();
  bool _loadingPdf = false;

  bool _contentOnly = true;
  bool _fillMissing = true;

  int _done = 0;
  int _total = 0;
  bool _cancelled = false;

  List<ScannedQuestion> _questions = [];
  List<List<int>> _failed = [];
  List<String> _errors = [];
  int _dropped = 0;
  bool _saving = false;

  /// Die KI hat die Seiten als Bild gesehen – nur dann können Abbildungen
  /// an den Fragen hängen.
  bool _usedPageImages = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final material = widget.material;
    if (material != null) WidgetsBinding.instance.addPostFrameCallback((_) => _useMaterial(material));
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  void _setPdf({required Uint8List bytes, required String fileName, MaterialItem? material}) {
    final int pages;
    try {
      pages = PdfService().pageCount(bytes);
    } catch (e) {
      setState(() => _error = 'Die PDF konnte nicht gelesen werden: $e');
      return;
    }
    setState(() {
      _bytes = bytes;
      _fileName = fileName;
      _material = material;
      _pageCount = pages;
      _fromController.text = '1';
      _toController.text = '$pages';
      _error = null;
    });
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
    _setPdf(bytes: bytes, fileName: material.fileName, material: material);
  }

  /// Eine hier hochgeladene PDF landet beim Import als Übung im Fach – so
  /// führen die Fragen später per "Im Skript ansehen" zu ihrer Seite.
  Future<MaterialItem?> _saveUploadedPdf() async {
    final bytes = _bytes;
    if (bytes == null) return null;
    final repo = context.read<MaterialRepository>();
    try {
      final id = const Uuid().v4();
      var text = '';
      try {
        text = PdfService().extractText(bytes);
      } catch (_) {}
      final (filePath, fileBytesBase64) = await MaterialFileStore.store(id, bytes);
      final material = MaterialItem(
        id: id,
        moduleId: widget.moduleId,
        fileName: _fileName ?? 'Import.pdf',
        kind: MaterialKind.exercise,
        extractedText: text,
        createdAt: DateTime.now(),
        filePath: filePath,
        fileBytesBase64: fileBytesBase64,
      );
      await repo.save(material);
      _material = material;
      return material;
    } catch (_) {
      return null;
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (picked.isEmpty || !mounted) return;
    setState(() => _loadingPdf = true);
    final bytes = await picked.first.readAsBytes();
    if (!mounted) return;
    setState(() => _loadingPdf = false);
    _setPdf(bytes: bytes, fileName: picked.first.name);
  }

  ({int from, int to})? get _range {
    final from = int.tryParse(_fromController.text.trim());
    final to = int.tryParse(_toController.text.trim());
    if (from == null || to == null || from < 1 || to > _pageCount || from > to) return null;
    return (from: from, to: to);
  }

  Future<void> _scan({List<List<int>>? retry}) async {
    final bytes = _bytes;
    final range = _range;
    if (bytes == null || range == null) return;
    final settings = context.read<SettingsRepository>().settings;
    final factory = widget.serviceFactory;
    if (factory == null && !settings.hasApiKey) {
      setState(() => _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte in den Einstellungen eintragen.');
      return;
    }
    final service = factory?.call() ??
        PdfQuestionImportService(ai: AiService(apiKey: settings.openRouterApiKey!, model: settings.visionModelId));
    setState(() {
      _step = _Step.scanning;
      _cancelled = false;
      _done = 0;
      _total = 0;
      _error = null;
    });
    final result = await service.scan(
      bytes,
      firstPage: range.from,
      lastPage: range.to,
      contentOnly: _contentOnly,
      fillMissingSolutions: _fillMissing,
      onlyBatches: retry,
      onProgress: (done, total) => setState(() {
        _done = done;
        _total = total;
      }),
      isCancelled: () => _cancelled,
    );
    if (!mounted) return;
    setState(() {
      if (retry == null) {
        _questions = result.questions;
        _dropped = result.dropped;
        _usedPageImages = result.usedPageImages;
      } else {
        _questions = [..._questions, ...result.questions]..sort((a, b) => a.page.compareTo(b.page));
        _dropped += result.dropped;
        _usedPageImages = _usedPageImages || result.usedPageImages;
      }
      _failed = result.failedBatches;
      _errors = result.errors;
      _step = _Step.preview;
    });
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
    final material = _material ?? await _saveUploadedPdf();
    if (!mounted) return;
    final cards = PdfQuestionImportService.toFlashcards(
      selected,
      moduleId: widget.moduleId,
      unitId: material?.unitId,
      sourceMaterialId: material?.id,
      sourceKind: material?.kind ?? MaterialKind.exercise,
      now: DateTime.now(),
    );
    await context.read<FlashcardRepository>().saveAll(cards);
    if (!mounted) return;
    // Fragen aus einem Arbeitsblatt: Erklärung im Skript suchen.
    unawaited(matchNewCardsToScript(context, cards));
    setState(() {
      _saving = false;
      _questions = [];
      _step = _Step.pick;
    });
    if (material == null) {
      // Das Arbeitsblatt konnte nicht gespeichert werden (z.B. kein
      // Speicherplatz) – die Karten sind trotzdem da, nur "Im Skript" findet
      // dafür keine exakte Seite mehr (nur noch die Textsuche über andere
      // Materialien des Fachs, falls vorhanden).
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Das Arbeitsblatt konnte nicht gespeichert werden – die Fragen sind trotzdem importiert, '
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
        builder: (_) => PracticeScreen.cards(title: 'Import · ${_fileName ?? 'PDF'}', cards: cards),
      ));
    } else {
      Navigator.of(context).pop();
    }
  }

  // -- Darstellung -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      active: _step == _Step.preview && _questions.isNotEmpty,
      message: 'Die gefundenen Fragen sind noch nicht importiert.',
      child: Scaffold(
        appBar: AppBar(title: const Text('Fragen aus PDF importieren')),
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
    final pdfs = context
        .watch<MaterialRepository>()
        .forModule(widget.moduleId)
        .where((m) => m.hasViewablePdf && m.fileName.toLowerCase().endsWith('.pdf'))
        .toList();
    final range = _range;
    final requests = range == null
        ? 0
        : PdfQuestionImportService.batches(range.from, range.to, PdfQuestionImportService.defaultPagesPerRequest).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Die KI sucht jede Seite nach Fragen und Aufgaben ab, die dort schon stehen (z.B. Altklausur, '
          'Übungsblatt, Fragen auf Folien), und übernimmt sie ins Quiz – sie erfindet keine neuen.',
          style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 16),
        Text('PDF', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_loadingPdf)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else if (_bytes != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(_fileName ?? 'PDF'),
              subtitle: Text('$_pageCount Seite${_pageCount == 1 ? '' : 'n'}'),
              trailing: TextButton(
                onPressed: () => setState(() {
                  _bytes = null;
                  _material = null;
                }),
                child: const Text('Ändern'),
              ),
            ),
          )
        else ...[
          for (final m in pdfs)
            Card(
              child: ListTile(
                key: ValueKey('import-material-${m.id}'),
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(m.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _useMaterial(m),
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _upload,
            icon: const Icon(Icons.upload_file),
            label: const Text('PDF hochladen'),
          ),
        ],
        if (_bytes != null) ...[
          const SizedBox(height: 20),
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
              'Sonst werden Fragen übersprungen, zu denen im Dokument keine Lösung steht.',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
          ),
          const SizedBox(height: 8),
          if (range == null)
            Text('Bitte einen gültigen Seitenbereich (1–$_pageCount) angeben.', style: TextStyle(color: c.danger))
          else
            Text(
              '$requests KI-Anfrage${requests == 1 ? '' : 'n'} an dein Vision-Modell (je bis zu '
              '${PdfQuestionImportService.defaultPagesPerRequest} Seiten). Die KI sieht jede Seite als Bild, '
              'übernimmt die Aufgabenform (Ankreuzen, Lücken, Zuordnen, Tabellen, Beschriften) und hängt '
              'nötige Abbildungen als Ausschnitt an.',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: range == null ? null : () => _scan(),
            icon: const Icon(Icons.manage_search),
            label: const Text('Fragen suchen'),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
          ),
      ],
    );
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
                  : 'Seiten werden durchsucht … $_done von $_total Paketen',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _cancelled ? null : () => setState(() => _cancelled = true),
              child: const Text('Abbrechen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final c = context.colors;
    final selected = _questions.where((q) => q.selected).length;
    final pages = {for (final q in _questions) q.page}.length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _questions.isEmpty
                    ? 'Keine passenden Fragen gefunden.'
                    : '${_questions.length} Frage${_questions.length == 1 ? '' : 'n'} auf $pages '
                        'Seite${pages == 1 ? '' : 'n'} gefunden.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_dropped > 0)
                Text('$_dropped unvollständige Einträge der KI wurden verworfen.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted)),
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
                    onPressed: () => _scan(retry: _failed),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Fehlgeschlagene Seiten erneut versuchen'),
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
                if (i == 0 || _questions[i - 1].page != q.page)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text('Seite ${q.page}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
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
                if (q.solutionByAi) _chip(c, 'Lösung von der KI', warn: true),
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
