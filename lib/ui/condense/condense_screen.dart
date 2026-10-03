
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/condense.dart';
import '../../models/material_item.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/condense_pdf.dart';
import '../../services/condense_service.dart';
import '../../services/material_file_store.dart';
import '../../services/material_text_extractor.dart';
import '../../services/pdf_ocr_service.dart';
import '../../services/pdf_service.dart';
import '../../theme/app_colors.dart';
import '../modules/material_opener.dart';
import '../widgets/discard_guard.dart';
import '../widgets/existing_material_picker.dart';
import '../widgets/ocr_notice.dart';
import '../widgets/raw_response_dialog.dart';
import '../widgets/safe_set_state.dart';

/// Der Auftrag, der im Textfeld vorbelegt ist.
const condenseDefaultPrompt = 'Alles, was man braucht, um diese Übungsaufgaben zu lösen.';

enum _Step { setup, running, preview }

class _Exercise {
  const _Exercise({required this.name, required this.text, this.materialId});
  final String name;
  final String text;
  final String? materialId;
}

/// "Kürzen": Eine hochgeladene Vorlesung wird anhand von Übungsaufgaben und
/// einem Auftrag ("alles, was man zum Lösen braucht") auf das Nötige
/// verkürzt. Die KI geht die Vorlesung abschnittsweise durch (mit
/// Rolling-Kontext) und wählt Textblöcke aus – sie schreibt nichts um. Im
/// Ergebnis bestimmt der Nutzer, ob weitere Beispielaufgaben mitkommen und ob
/// Markierungen gesetzt werden (wo auf der Seite der relevante Teil beginnt),
/// und speichert es als gekürztes Dokument im Fach (PDF mit nur den
/// behaltenen Seiten, dazu die Textfassung).
class CondenseScreen extends StatefulWidget {
  const CondenseScreen({super.key, required this.moduleId, this.lectureId});

  final String moduleId;

  /// Vorgewählte Vorlesung (z.B. aus dem Menü einer Folie).
  final String? lectureId;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  /// Nur für Tests: statt des Datei-Dialogs (Name, Bytes).
  @visibleForTesting
  static Future<List<({String name, Uint8List bytes})>> Function()? pickFilesHook;

  @override
  State<CondenseScreen> createState() => _CondenseScreenState();
}

class _CondenseScreenState extends State<CondenseScreen> with SafeSetState<CondenseScreen> {
  _Step _step = _Step.setup;
  String? _lectureId;
  final List<_Exercise> _exercises = [];
  final _prompt = TextEditingController(text: condenseDefaultPrompt);
  CondenseStrictness _strictness = CondenseStrictness.ausgewogen;
  bool _picking = false;
  String? _error;
  String? _raw;

  // Lauf
  String _what = '';
  int _done = 0;
  int _total = 0;

  /// Zählt die Läufe – ein abgebrochener Lauf erkennt daran, dass sein Ergebnis
  /// nicht mehr gebraucht wird.
  int _run = 0;

  // Vorschau
  MaterialItem? _lecture;
  List<CondensePage> _pages = const [];
  Uint8List? _pdfBytes;
  CondenseSelection? _selection;
  bool _includeExamples = true;
  bool _markers = true;
  final Set<int> _off = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lectureId = widget.lectureId;
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  List<MaterialItem> get _lectures => [
        for (final m in context.read<MaterialRepository>().forModule(widget.moduleId))
          if (m.kind == MaterialKind.slide && (m.extractedText.trim().isNotEmpty || m.hasViewablePdf || m.hasRemotePdf)) m,
      ];

  MaterialItem? get _selectedLecture {
    final lectures = _lectures;
    for (final m in lectures) {
      if (m.id == _lectureId) return m;
    }
    return lectures.length == 1 ? lectures.first : null;
  }

  bool get _canStart => _selectedLecture != null && (_exercises.isNotEmpty || _prompt.text.trim().isNotEmpty);

  // -- Übungsaufgaben ---------------------------------------------------------

  Future<List<({String name, Uint8List bytes})>> _pickFiles() async {
    final hook = CondenseScreen.pickFilesHook;
    if (hook != null) return hook();
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: MaterialTextExtractor.supportedExtensions,
    );
    return [for (final f in files) (name: f.name, bytes: await f.readAsBytes())];
  }

  /// Neue Übungsaufgaben: Text auslesen und – wie bei jedem Upload – als
  /// Material des Fachs ablegen, damit sie sich später wiederverwenden lassen.
  Future<void> _uploadExercises() async {
    final picked = await _pickFiles();
    if (picked.isEmpty || !mounted) return;
    final repo = context.read<MaterialRepository>();
    final ocr = PdfOcrService.fromSettings(context.read<SettingsRepository>().settings);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _picking = true;
      _error = null;
      _raw = null;
    });
    final errors = <String>[];
    for (final file in picked) {
      try {
        final text = await MaterialTextExtractor()
            .extractTextWithOcr(file.name, file.bytes, ocr: ocr, onProgress: ocrStartNotice(messenger, file.name));
        if (text.trim().isEmpty) {
          errors.add('${file.name}: kein Text gefunden.');
          continue;
        }
        final id = const Uuid().v4();
        String? filePath;
        String? fileBytesBase64;
        if (file.name.toLowerCase().endsWith('.pdf')) {
          (filePath, fileBytesBase64) = await MaterialFileStore.store(id, file.bytes);
        }
        await repo.save(MaterialItem(
          id: id,
          moduleId: widget.moduleId,
          fileName: file.name,
          kind: MaterialKind.exercise,
          extractedText: text,
          createdAt: DateTime.now(),
          filePath: filePath,
          fileBytesBase64: fileBytesBase64,
        ));
        _exercises.add(_Exercise(name: file.name, text: text, materialId: id));
      } catch (e) {
        errors.add('${file.name}: $e');
      }
    }
    setState(() {
      _picking = false;
      if (errors.isNotEmpty) _error = errors.join('\n');
    });
  }

  Future<void> _pickExisting() async {
    final lecture = _selectedLecture;
    final selected = await showExistingMaterialPicker(
      context,
      available: [
        for (final m in context.read<MaterialRepository>().forModule(widget.moduleId))
          if (m.id != lecture?.id && m.kind != MaterialKind.condensed) m,
      ],
      alreadyPickedIds: {for (final e in _exercises) ?e.materialId},
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    setState(() {
      for (final m in selected) {
        _exercises.add(_Exercise(name: m.fileName, text: m.extractedText, materialId: m.id));
      }
    });
  }

  String get _exercisesText => [
        for (final e in _exercises) '### ${e.name}\n${e.text.trim()}',
      ].join('\n\n');

  // -- Kürzen -----------------------------------------------------------------

  Future<Uint8List?> _bytesOf(MaterialItem lecture) async {
    var material = lecture;
    if (!material.hasViewablePdf && material.hasRemotePdf) {
      final local = await ensureLocalPdf(context, material);
      if (local == null) return null;
      material = local;
    }
    if (!material.hasViewablePdf) return null;
    return MaterialFileStore.load(filePath: material.filePath, fileBytesBase64: material.fileBytesBase64);
  }

  Future<void> _start() async {
    final lecture = _selectedLecture;
    if (lecture == null) return;
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() {
        _error = 'Zum Kürzen braucht die App deinen OpenRouter-Key (Einstellungen).';
        _raw = null;
      });
      return;
    }
    final run = ++_run;
    setState(() {
      _step = _Step.running;
      _error = null;
      _raw = null;
      _what = 'Vorlesung wird gelesen …';
      _done = 0;
      _total = 0;
    });
    try {
      final bytes = lecture.fileName.toLowerCase().endsWith('.pdf') ? await _bytesOf(lecture) : null;
      List<CondensePage> pages;
      if (bytes != null) {
        var texts = PdfService().extractPageTexts(bytes);
        final ocr = PdfOcrService.fromSettings(settings);
        if (ocr != null && PdfOcrService.shouldOcr(texts)) {
          setState(() => _what = 'Gescannte Seiten werden per KI gelesen …');
          texts = await ocr.recognizePages(bytes, texts);
        }
        pages = CondenseService.pagesFromPageTexts(texts);
      } else {
        pages = CondenseService.pagesFromText(lecture.extractedText);
      }
      final ai = CondenseScreen.aiFactory?.call(settings.openRouterApiKey!, settings.questionModelId) ??
          AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final selection = await ai.condenseLecture(
        pages: pages,
        task: _prompt.text,
        exercisesText: _exercisesText,
        strictness: _strictness,
        granularity: settings.chunkGranularity,
        rollingContext: settings.rollingContextEnabled,
        onProgress: (what, done, total) {
          if (run != _run) return;
          setState(() {
            _what = what;
            _done = done;
            _total = total;
          });
        },
      );
      if (run != _run) return;
      setState(() {
        _lecture = lecture;
        _pages = pages;
        _pdfBytes = bytes;
        _selection = selection;
        _off.clear();
        _markers = bytes != null;
        _step = _Step.preview;
      });
    } on AiServiceException catch (e) {
      if (run != _run) return;
      setState(() {
        _step = _Step.setup;
        _error = e.message;
        _raw = e.rawResponse;
      });
    } catch (e) {
      if (run != _run) return;
      setState(() {
        _step = _Step.setup;
        _error = 'Kürzen fehlgeschlagen: $e';
        _raw = null;
      });
    }
  }

  void _cancel() => setState(() {
        _run++;
        _step = _Step.setup;
      });

  // -- Vorschau ---------------------------------------------------------------

  /// Die Abschnitte, wie sie gerade gelten: ohne abgewählte und – je nach
  /// Schalter – ohne Beispielaufgaben.
  List<CondenseSection> get _active {
    final selection = _selection;
    if (selection == null) return const [];
    return [
      for (final (i, s) in selection.sections.indexed)
        if (!_off.contains(i) && (_includeExamples || s.kind != CondenseKind.beispiel)) s,
    ];
  }

  List<CondenseNeed> get _uncovered {
    final selection = _selection;
    if (selection == null) return const [];
    final covered = {for (final s in _active) ...s.covers};
    return [
      for (final n in selection.plan.needs)
        if (!covered.contains(n.id)) n,
    ];
  }

  String get _label => _pages.isEmpty ? 'Seite' : _pages.first.label;

  String _baseName(String fileName) => fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');

  String _text() => CondenseService.textDocument(
        sourceName: _lecture?.fileName ?? '',
        prompt: _prompt.text,
        pages: _pages,
        sections: _active,
      );

  Future<void> _save() async {
    final lecture = _lecture;
    if (_saving || lecture == null) return;
    final active = _active;
    final keep = CondenseService.keptPageNumbers(_pages, active);
    if (keep.isEmpty) {
      setState(() => _error = 'Es ist nichts ausgewählt – wähle mindestens einen Abschnitt.');
      return;
    }
    final repo = context.read<MaterialRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = const Uuid().v4();
      var name = '${_baseName(lecture.fileName)} – gekürzt';
      String? filePath;
      String? fileBytesBase64;
      final bytes = _pdfBytes;
      if (bytes != null) {
        final pdf = CondensePdf.build(
          bytes,
          keepPages: keep,
          pages: _pages,
          runs: CondenseService.runsByPage(_pages, active),
          markers: _markers,
          label: _label,
        );
        (filePath, fileBytesBase64) = await MaterialFileStore.store(id, pdf);
        name += '.pdf';
      }
      final info = CondensedInfo(
        sourceMaterialId: lecture.id,
        sourceName: lecture.fileName,
        prompt: _prompt.text.trim(),
        exerciseNames: [for (final e in _exercises) e.name],
        pages: keep,
        totalPages: _pages.length,
        label: _label,
        includeExamples: _includeExamples,
        markers: bytes != null && _markers,
        notFound: [for (final n in _uncovered) n.text],
        skipped: _selection?.skipped ?? const [],
      );
      await repo.save(MaterialItem(
        id: id,
        moduleId: widget.moduleId,
        fileName: name,
        kind: MaterialKind.condensed,
        extractedText: _text(),
        createdAt: DateTime.now(),
        unitId: lecture.unitId,
        filePath: filePath,
        fileBytesBase64: fileBytesBase64,
        condensed: info,
      ));
      messenger.showSnackBar(SnackBar(content: Text('Gekürzt gespeichert: „$name“ (${info.shareText}).')));
      if (mounted) navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Speichern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // -- Darstellung ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    context.watch<MaterialRepository>();
    final c = context.colors;
    return DiscardGuard(
      active: _step == _Step.preview && !_saving,
      message: 'Das gekürzte Ergebnis ist noch nicht gespeichert und geht verloren (die KI-Anfragen waren umsonst).',
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vorlesung kürzen', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text(
                'Nur, was für die Aufgaben nötig ist',
                style: TextStyle(fontSize: 12, color: c.inkMuted),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: switch (_step) {
                _Step.setup => _setup(c),
                _Step.running => _running(c),
                _Step.preview => _preview(c),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(AppColors c, Widget child, {Color? tint}) => DecoratedBox(
        decoration: BoxDecoration(
          color: tint ?? c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(type: MaterialType.transparency, child: Padding(padding: const EdgeInsets.all(14), child: child)),
      );

  Widget _label0(AppColors c, String text) =>
      Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted));

  Widget _errorCard(AppColors c) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _card(
          c,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error!, key: const ValueKey('condense-error'), style: TextStyle(color: c.danger, height: 1.35)),
              if (_raw != null)
                TextButton(
                  onPressed: () => showRawResponseDialog(context, _raw!),
                  child: const Text('KI-Antwort ansehen'),
                ),
            ],
          ),
          tint: c.dangerSoft,
        ),
      );

  Widget _setup(AppColors c) {
    final lectures = _lectures;
    final selected = _selectedLecture;
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        _card(
          c,
          Text(
            'Wähle eine Vorlesung und lade Übungsaufgaben dazu hoch. Die KI geht die Vorlesung durch und behält alles, '
            'was man zum Lösen braucht – vollständig mit allen Erklärungen –, und lässt den Rest weg. Sie schreibt '
            'nichts um: das gekürzte Dokument besteht aus dem Originaltext. Du bekommst die behaltenen Seiten als '
            'PDF, auf Wunsch mit Markierungen, wo der relevante Teil auf der Seite beginnt.',
            style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),
        _card(
          c,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label0(c, 'Vorlesung'),
              const SizedBox(height: 8),
              if (lectures.isEmpty)
                Text(
                  'In diesem Fach ist noch keine Vorlesung hochgeladen. Lade sie zuerst unter „Material hochladen“ hoch.',
                  key: const ValueKey('condense-no-lecture'),
                  style: TextStyle(fontSize: 13, color: c.inkMuted),
                )
              else
                DropdownButtonFormField<String>(
                  key: const ValueKey('condense-lecture'),
                  initialValue: selected?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  hint: const Text('Vorlesung wählen'),
                  items: [
                    for (final m in lectures)
                      DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          m.hasViewablePdf || m.hasRemotePdf ? m.fileName : '${m.fileName} (nur Text)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _lectureId = id),
                ),
              if (selected != null && !selected.hasViewablePdf && !selected.hasRemotePdf) ...[
                const SizedBox(height: 6),
                Text(
                  'Ohne PDF auf diesem Gerät entsteht nur die Textfassung (keine gekürzte PDF, keine Markierungen).',
                  style: TextStyle(fontSize: 12, color: c.inkMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          c,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label0(c, 'Übungsaufgaben'),
              const SizedBox(height: 4),
              Text(
                'Optional – ohne Aufgaben richtet sich die KI nur nach deinem Auftrag.',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (i, e) in _exercises.indexed)
                    InputChip(
                      key: ValueKey('condense-exercise-$i'),
                      avatar: const Icon(Icons.assignment_outlined, size: 16),
                      label: Text(e.name, overflow: TextOverflow.ellipsis),
                      onDeleted: () => setState(() => _exercises.removeAt(i)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('condense-upload'),
                    onPressed: _picking ? null : _uploadExercises,
                    icon: _picking
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Aufgaben hochladen'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('condense-existing'),
                    onPressed: _picking ? null : _pickExisting,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Aus dem Fach wählen'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          c,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label0(c, 'Auftrag'),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('condense-prompt'),
                controller: _prompt,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'z.B. „Alles, was man braucht, um diese Übungsaufgaben zu lösen“',
                ),
              ),
              const SizedBox(height: 12),
              _label0(c, 'Wie streng gekürzt wird'),
              const SizedBox(height: 8),
              SegmentedButton<CondenseStrictness>(
                key: const ValueKey('condense-strictness'),
                showSelectedIcon: false,
                segments: [
                  for (final s in CondenseStrictness.values) ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {_strictness},
                onSelectionChanged: (s) => setState(() => _strictness = s.first),
              ),
              const SizedBox(height: 4),
              Text(
                switch (_strictness) {
                  CondenseStrictness.knapp => 'Nur, was die Aufgaben direkt brauchen.',
                  CondenseStrictness.ausgewogen => 'Das Nötige samt dem Zusammenhang, den man zum Verstehen braucht.',
                  CondenseStrictness.grosszuegig => 'Im Zweifel behalten, damit nichts fehlt.',
                },
                style: TextStyle(fontSize: 12, color: c.inkMuted),
              ),
            ],
          ),
        ),
        if (_error != null) _errorCard(c),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('condense-start'),
          onPressed: _canStart && !_picking ? _start : null,
          icon: const Icon(Icons.content_cut),
          label: const Text('Kürzen starten'),
        ),
        const SizedBox(height: 8),
        Text(
          hasKey
              ? 'Die KI liest die ganze Vorlesung – bei langen Skripten dauert das ein paar Minuten und kostet '
                  'KI-Anfragen (ein Abschnitt je Anfrage).'
              : 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).',
          style: TextStyle(fontSize: 12, color: c.inkMuted),
        ),
      ],
    );
  }

  Widget _running(AppColors c) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 260,
                child: LinearProgressIndicator(value: _total > 0 && _done > 0 ? _done / _total : null),
              ),
              const SizedBox(height: 16),
              Text(_what, key: const ValueKey('condense-progress'), textAlign: TextAlign.center),
              if (_total > 1) ...[
                const SizedBox(height: 4),
                Text('$_done von $_total Abschnitten', style: TextStyle(fontSize: 12, color: c.inkMuted)),
              ],
              const SizedBox(height: 20),
              TextButton(key: const ValueKey('condense-cancel'), onPressed: _cancel, child: const Text('Abbrechen')),
            ],
          ),
        ),
      );

  String _pagesOf(CondenseSection s) {
    final pages = {for (final id in s.blockIds) int.tryParse(id.split('.').first)}.whereType<int>().toList()..sort();
    return condensePageRanges(pages, label: _label);
  }

  Widget _preview(AppColors c) {
    final selection = _selection!;
    final active = _active;
    final keptPages = CondenseService.keptPageNumbers(_pages, active);
    final percent = _pages.isEmpty ? 0 : (keptPages.length * 100 / _pages.length).round();
    final examples = selection.sections.where((s) => s.kind == CondenseKind.beispiel).length;
    final uncovered = _uncovered;
    final hasPdf = _pdfBytes != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        _card(
          c,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                keptPages.isEmpty
                    ? 'Nichts ausgewählt'
                    : '${keptPages.length} von ${_pages.length} ${_label == 'Seite' ? 'Seiten' : _label == 'Folie' ? 'Folien' : 'Abschnitten'} '
                        'behalten ($percent %)',
                key: const ValueKey('condense-summary'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              if (keptPages.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(condensePageRanges(keptPages, label: _label),
                    key: const ValueKey('condense-pages'), style: TextStyle(fontSize: 13, color: c.inkMuted)),
              ],
              const SizedBox(height: 2),
              Text('aus ${_lecture?.fileName ?? ''}', style: TextStyle(fontSize: 12, color: c.inkMuted)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _card(
          c,
          Column(
            children: [
              SwitchListTile(
                key: const ValueKey('condense-examples'),
                contentPadding: EdgeInsets.zero,
                value: _includeExamples,
                onChanged: examples == 0 ? null : (v) => setState(() => _includeExamples = v),
                title: const Text('Beispielaufgaben der Vorlesung mitnehmen'),
                subtitle: Text(
                  examples == 0
                      ? 'Die KI hat keine weiteren Beispielaufgaben gefunden.'
                      : '$examples Abschnitt${examples == 1 ? '' : 'e'} mit Beispielen in die Richtung der Aufgaben. '
                          'Die Erklärungen bleiben in jedem Fall.',
                ),
              ),
              SwitchListTile(
                key: const ValueKey('condense-markers'),
                contentPadding: EdgeInsets.zero,
                value: hasPdf && _markers,
                onChanged: hasPdf ? (v) => setState(() => _markers = v) : null,
                title: const Text('Markierungen setzen'),
                subtitle: Text(
                  hasPdf
                      ? 'Gelber Streifen, wo der relevante Teil auf der Seite beginnt, und die Seitenzahl im Original.'
                      : 'Nur bei Vorlesungen als PDF.',
                ),
              ),
            ],
          ),
        ),
        if (uncovered.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            c,
            Column(
              key: const ValueKey('condense-notfound'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: c.warn),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Das erklärt die Vorlesung nicht (oder nur im Beispiel)',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final n in uncovered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('• ${n.text}', style: TextStyle(fontSize: 13, color: c.inkMuted)),
                  ),
              ],
            ),
            tint: c.warnSoft,
          ),
        ],
        const SizedBox(height: 12),
        _label0(c, 'Behaltene Abschnitte'),
        const SizedBox(height: 6),
        for (final (i, s) in selection.sections.indexed)
          Builder(builder: (context) {
            final isExample = s.kind == CondenseKind.beispiel;
            final disabled = isExample && !_includeExamples;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _card(
                c,
                CheckboxListTile(
                  key: ValueKey('condense-section-$i'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: !disabled && !_off.contains(i),
                  onChanged: disabled
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              _off.remove(i);
                            } else {
                              _off.add(i);
                            }
                          }),
                  title: Text(s.title, style: TextStyle(fontWeight: FontWeight.w600, color: disabled ? c.inkMuted : null)),
                  subtitle: Text(
                    [
                      _pagesOf(s),
                      isExample ? 'Beispielaufgabe' : 'Erklärung',
                      if (s.why.isNotEmpty) s.why,
                    ].join(' · '),
                    style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                  ),
                ),
              ),
            );
          }),
        if (selection.skipped.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const ValueKey('condense-skipped'),
              tilePadding: EdgeInsets.zero,
              title: Text('Weggelassen (${selection.skipped.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(selection.skipped.join(' · '), style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4)),
                ),
              ],
            ),
          ),
        if (_error != null) _errorCard(c),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('condense-save'),
          onPressed: _saving || keptPages.isEmpty ? null : _save,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(hasPdf ? 'Als gekürzte PDF speichern' : 'Als gekürztes Dokument speichern'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('condense-copy'),
              onPressed: keptPages.isEmpty
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: _text()));
                      messenger.showSnackBar(const SnackBar(content: Text('Text kopiert.')));
                    },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Text kopieren'),
            ),
            TextButton(
              key: const ValueKey('condense-back'),
              onPressed: _saving ? null : () => setState(() => _step = _Step.setup),
              child: const Text('Zurück zu den Angaben'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Zeigt die Textfassung eines gekürzten Dokuments zum Lesen und Kopieren.
Future<void> showCondensedTextDialog(BuildContext context, MaterialItem material) {
  final info = material.condensed;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(material.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info != null && info.notFound.isNotEmpty) ...[
                Text('Nicht in der Vorlesung: ${info.notFound.join('; ')}',
                    style: TextStyle(color: ctx.colors.warn, fontSize: 13)),
                const SizedBox(height: 10),
              ],
              SelectableText(material.extractedText),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: material.extractedText));
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          child: const Text('Kopieren'),
        ),
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Schließen')),
      ],
    ),
  );
}
