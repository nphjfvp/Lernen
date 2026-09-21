import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_settings.dart';
import '../../models/lecture_unit.dart';
import '../../models/material_item.dart';
import '../../models/summary.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/summary_repository.dart';
import '../../services/ai_service.dart';
import '../../services/content_analyzer.dart';
import '../../services/highlight_context.dart';
import '../../services/material_file_store.dart';
import '../../services/material_text_extractor.dart';
import '../../theme/app_colors.dart';
import '../widgets/analysis_recommendation_card.dart';
import '../widgets/existing_material_picker.dart';
import '../widgets/pdf_preview_screen.dart';
import '../widgets/raw_response_dialog.dart';

enum _Mode { kurz, ausfuehrlich }

enum _Step { modeSelect, pick, extracting, ready, generating, preview, preparingSession, session }

class _PickedFile {
  _PickedFile({required this.fileName, required this.text, required this.bytes, this.existingMaterialId});
  final String fileName;
  final String text;
  final Uint8List bytes;

  /// Gesetzt, wenn diese Datei nicht frisch hochgeladen, sondern aus bereits
  /// vorhandenem Fach-Material übernommen wurde (siehe
  /// showExistingMaterialPicker) – beim Speichern wird für sie KEIN neues
  /// MaterialItem angelegt (existiert ja schon), nur ihr Text fließt in die
  /// KI-Generierung ein.
  final String? existingMaterialId;
}

/// Vorbereiten-Modus, in zwei Varianten:
///  - "Kurz": PDF-Vorlesungsfolien hochladen → KI erstellt daraus eine
///    strukturierte Zusammenfassung mit hervorgehobenen Kernkonzepten für
///    den schnellen Überblick (der ursprüngliche, unveränderte Ablauf).
///  - "Ausführlich": die KI liest ALLE hochgeladenen Folien, markiert die
///    relevantesten Stellen (siehe AiService.suggestHighlights, dieselbe
///    Grundlage wie in MaterialViewerScreen) UND beantwortet direkte
///    Rückfragen dazu (siehe AiService.answerQuestion) – jede gestellte
///    Frage wird dabei als "hier hakte es" gewertet und automatisch als
///    Merkpunkt an die gewählte Einheit angehängt (siehe LectureUnit.notes),
///    damit man beim nächsten Mal genau dort ansetzen kann.
class PrepareScreen extends StatefulWidget {
  const PrepareScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  State<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends State<PrepareScreen> {
  _Step _step = _Step.modeSelect;
  _Mode? _mode;
  final List<_PickedFile> _files = [];
  Map<String, dynamic>? _result;
  String? _error;
  String? _rawResponse;

  String _unitChoice = '';

  // -- Ausführlich-Modus-Zustand -------------------------------------------
  Map<String, List<MaterialHighlight>> _highlightsByFile = {};
  String? _sessionError;
  final List<({String question, String answer})> _qaTurns = [];
  final _questionController = TextEditingController();
  bool _asking = false;
  String? _askError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<LectureUnitRepository>().loadForModule(widget.moduleId));
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  String get _combinedText => _files
      .map((f) => '=== Datei: ${f.fileName} ===\n${f.text}')
      .join('\n\n');

  void _chooseMode(_Mode mode) {
    setState(() {
      _mode = mode;
      _step = _Step.pick;
    });
  }

  Future<void> _pickAndExtract() async {
    // Wurde für dieses Fach bereits ein gleichnamiges Material hochgeladen
    // und dort markiert (siehe MaterialViewerScreen), fließen dessen
    // Markierungen + Notiz als zusätzlicher "besonders wichtig"-Kontext mit
    // ein – auch wenn die Datei hier gerade frisch neu ausgewählt wurde. Vor
    // dem ersten await gelesen, um BuildContext-Nutzung über einen
    // Async-Gap hinweg zu vermeiden.
    final existing = context.read<MaterialRepository>().forModule(widget.moduleId);

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: MaterialTextExtractor.supportedExtensions,
    );
    if (picked.isEmpty) return;

    setState(() {
      _step = _Step.extracting;
      _error = null;
    });

    final newFiles = <_PickedFile>[];
    for (final file in picked) {
      try {
        final Uint8List bytes = await file.readAsBytes();
        final text = MaterialTextExtractor().extractText(file.name, bytes);
        if (text.isNotEmpty) {
          MaterialItem? match;
          for (final m in existing) {
            if (m.fileName == file.name) {
              match = m;
              break;
            }
          }
          final highlightBlock = match != null ? HighlightContext.build(match) : '';
          final combined = highlightBlock.isEmpty ? text : '$text\n\n$highlightBlock';
          newFiles.add(_PickedFile(fileName: file.name, text: combined, bytes: bytes));
        }
      } catch (e) {
        setState(() => _error = '${file.name}: $e');
      }
    }

    setState(() {
      _files.addAll(newFiles);
      if (_files.isEmpty) {
        _error ??= 'Kein Text in den Dateien gefunden (evtl. gescannte Bilder ohne Text-Ebene).';
        _step = _Step.pick;
      } else {
        _step = _Step.ready;
      }
    });
  }

  void _removeFile(int index) {
    setState(() {
      _files.removeAt(index);
      if (_files.isEmpty) _step = _Step.pick;
    });
  }

  /// Statt jedes Mal neu hochzuladen: bereits im Fach abgelegtes Material
  /// (z.B. über ModuleDetailScreen direkt hochgeladen) direkt übernehmen –
  /// kein erneuter FilePicker, keine erneute Textextraktion.
  Future<void> _pickExisting() async {
    final available = context.read<MaterialRepository>().forModule(widget.moduleId);
    final alreadyPicked = _files.map((f) => f.existingMaterialId).whereType<String>().toSet();

    final selected = await showExistingMaterialPicker(
      context,
      available: available,
      alreadyPickedIds: alreadyPicked,
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() {
      for (final material in selected) {
        final highlightBlock = HighlightContext.build(material);
        final combined = highlightBlock.isEmpty ? material.extractedText : '${material.extractedText}\n\n$highlightBlock';
        _files.add(_PickedFile(
          fileName: material.fileName,
          text: combined,
          bytes: material.fileBytesBase64 == null ? Uint8List(0) : base64Decode(material.fileBytesBase64!),
          existingMaterialId: material.id,
        ));
      }
      _step = _Step.ready;
    });
  }

  Future<void> _applyRecommendation(ChunkGranularity granularity) async {
    final repo = context.read<SettingsRepository>();
    await repo.update(repo.settings.copyWith(chunkGranularity: granularity));
  }

  Future<void> _handleUnitChanged(String? value) async {
    if (value == null) return;
    if (value != '_new') {
      setState(() => _unitChoice = value);
      return;
    }
    final title = await _promptNewUnitTitle();
    if (title == null || !mounted) return;
    final unit = LectureUnit(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      title: title,
      createdAt: DateTime.now(),
    );
    await context.read<LectureUnitRepository>().save(unit);
    if (!mounted) return;
    setState(() => _unitChoice = unit.id);
  }

  Future<String?> _promptNewUnitTitle() async {
    final existingCount = context.read<LectureUnitRepository>().forModule(widget.moduleId).length;
    final controller = TextEditingController(text: 'Einheit ${existingCount + 1}');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neue Einheit'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Titel')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Anlegen')),
        ],
      ),
    );
    return (title == null || title.isEmpty) ? null : title;
  }

  // -- Kurz-Modus -----------------------------------------------------------

  Future<void> _generate() async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() {
        _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte zuerst in den Einstellungen eintragen.';
        _step = _Step.ready;
      });
      return;
    }

    setState(() {
      _step = _Step.generating;
      _error = null;
      _rawResponse = null;
    });

    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final result = await ai.generateSummary(
        _combinedText,
        granularity: settings.chunkGranularity,
        rollingContext: settings.rollingContextEnabled,
      );
      setState(() {
        _result = result;
        _step = _Step.preview;
      });
    } on AiServiceException catch (e) {
      setState(() {
        _error = e.message;
        _rawResponse = e.rawResponse;
        _step = _Step.ready;
      });
    } catch (e) {
      setState(() {
        _error = 'Unerwarteter Fehler: $e';
        _step = _Step.ready;
      });
    }
  }

  Future<void> _save() async {
    final result = _result!;
    final now = DateTime.now();
    final unitId = _unitChoice.isEmpty ? null : _unitChoice;
    // Wiederverwendetes Material (existingMaterialId gesetzt, siehe
    // _pickExisting) bekommt KEIN neues MaterialItem – das gibt es ja schon.
    final materials = <MaterialItem>[];
    for (final f in _files) {
      if (f.existingMaterialId != null) continue;
      final id = const Uuid().v4();
      // Original-PDF-Bytes zusätzlich speichern (wie beim direkten Upload in
      // ModuleDetailScreen) – sonst bleibt die Folie unsichtbar: ohne
      // filePath/fileBytesBase64 ist hasViewablePdf false und weder
      // MaterialViewerScreen noch die "Frage zur Seite"-Funktion darin sind
      // erreichbar.
      String? filePath;
      String? fileBytesBase64;
      if (f.fileName.toLowerCase().endsWith('.pdf')) {
        (filePath, fileBytesBase64) = await MaterialFileStore.store(id, f.bytes);
      }
      materials.add(MaterialItem(
        id: id,
        moduleId: widget.moduleId,
        fileName: f.fileName,
        kind: MaterialKind.slide,
        extractedText: f.text,
        createdAt: now,
        unitId: unitId,
        filePath: filePath,
        fileBytesBase64: fileBytesBase64,
      ));
    }

    final summary = Summary(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      sourceMaterialIds: [
        ...materials.map((m) => m.id),
        ..._files.map((f) => f.existingMaterialId).whereType<String>(),
      ],
      title: (result['title'] as String?)?.trim().isNotEmpty == true
          ? result['title'] as String
          : _files.first.fileName,
      overview: result['overview'] as String? ?? '',
      keyPoints: (result['key_points'] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: now,
      unitId: unitId,
    );

    final materialRepo = context.read<MaterialRepository>();
    for (final material in materials) {
      await materialRepo.save(material);
      if (!mounted) return;
    }
    await context.read<SummaryRepository>().save(summary);
    if (mounted) Navigator.of(context).pop();
  }

  // -- Ausführlich-Modus ------------------------------------------------------

  Future<void> _startSession() async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() => _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte zuerst in den Einstellungen eintragen.');
      return;
    }

    setState(() {
      _step = _Step.preparingSession;
      _error = null;
    });

    final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
    final highlightsByFile = <String, List<MaterialHighlight>>{};
    final failed = <String>[];
    for (final file in _files) {
      try {
        final suggestions = await ai.suggestHighlights(file.text);
        highlightsByFile[file.fileName] = suggestions
            .map((s) {
              final text = (s['text'] ?? '').toString().trim();
              return MaterialHighlight(
                id: const Uuid().v4(),
                text: text,
                color: highlightColorFromString(s['color'] as String?),
                source: HighlightSource.ai,
                reason: (s['reason'] as String?)?.trim(),
              );
            })
            .where((h) => h.text.isNotEmpty)
            .toList();
      } catch (_) {
        failed.add(file.fileName);
        highlightsByFile[file.fileName] = const [];
      }
    }

    if (!mounted) return;
    setState(() {
      _highlightsByFile = highlightsByFile;
      _sessionError = failed.isEmpty ? null : 'KI-Markierung fehlgeschlagen für: ${failed.join(', ')}';
      _step = _Step.session;
    });
  }

  Future<void> _ask() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() => _askError = 'Kein OpenRouter-API-Key hinterlegt.');
      return;
    }

    setState(() {
      _asking = true;
      _askError = null;
    });
    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final history = _qaTurns
          .expand((t) => [(isUser: true, content: t.question), (isUser: false, content: t.answer)])
          .toList();
      final answer = await ai.answerQuestion(question: question, materialsContext: _combinedText, history: history);
      if (!mounted) return;
      setState(() {
        _qaTurns.add((question: question, answer: answer));
        _questionController.clear();
        _asking = false;
      });
    } on AiServiceException catch (e) {
      setState(() {
        _askError = e.message;
        _asking = false;
      });
    } catch (e) {
      setState(() {
        _askError = 'Unerwarteter Fehler: $e';
        _asking = false;
      });
    }
  }

  Future<void> _finishSession() async {
    final now = DateTime.now();
    final unitId = _unitChoice.isEmpty ? null : _unitChoice;
    // Wiederverwendetes Material (existingMaterialId gesetzt, siehe
    // _pickExisting) bekommt KEIN neues MaterialItem – die für diese Session
    // ggf. neu vorgeschlagenen Markierungen bleiben dafür bewusst nur
    // session-lokal sichtbar (siehe _SessionView), statt das Risiko
    // einzugehen, bereits vorhandene Markierungen/Notizen des Materials zu
    // überschreiben.
    final materials = <MaterialItem>[];
    for (final f in _files) {
      if (f.existingMaterialId != null) continue;
      final id = const Uuid().v4();
      String? filePath;
      String? fileBytesBase64;
      if (f.fileName.toLowerCase().endsWith('.pdf')) {
        (filePath, fileBytesBase64) = await MaterialFileStore.store(id, f.bytes);
      }
      materials.add(MaterialItem(
        id: id,
        moduleId: widget.moduleId,
        fileName: f.fileName,
        kind: MaterialKind.slide,
        extractedText: f.text,
        createdAt: now,
        unitId: unitId,
        highlights: _highlightsByFile[f.fileName] ?? const [],
        filePath: filePath,
        fileBytesBase64: fileBytesBase64,
      ));
    }

    final materialRepo = context.read<MaterialRepository>();
    for (final material in materials) {
      await materialRepo.save(material);
      if (!mounted) return;
    }

    if (_qaTurns.isNotEmpty) {
      final noteText = _qaTurns.map((t) => 'F: ${t.question}\nA: ${t.answer}').join('\n\n');
      if (unitId != null) {
        final unitRepo = context.read<LectureUnitRepository>();
        final unit = unitRepo.forModule(widget.moduleId).firstWhere((u) => u.id == unitId);
        await unitRepo.setNotes(unit.id, unit.moduleId, [...unit.notes, noteText]);
      } else if (materials.isNotEmpty) {
        await materialRepo.saveHighlights(
          materials.first.id,
          widget.moduleId,
          highlights: materials.first.highlights,
          notes: noteText,
        );
      }
      if (!mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vorbereiten-Modus')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.modeSelect:
        return _ModeSelectView(onChoose: _chooseMode);
      case _Step.pick:
        return _PickView(
          error: _error,
          rawResponse: _rawResponse,
          onPick: _pickAndExtract,
          onPickExisting: _pickExisting,
          onChangeMode: () => setState(() {
            _step = _Step.modeSelect;
            _mode = null;
          }),
        );
      case _Step.extracting:
        return const _LoadingView(label: 'Text wird extrahiert …');
      case _Step.ready:
        final units = context.watch<LectureUnitRepository>().forModule(widget.moduleId);
        return _ReadyView(
          mode: _mode!,
          files: _files,
          combinedText: _combinedText,
          error: _error,
          onAddMore: _pickAndExtract,
          onAddExisting: _pickExisting,
          onRemove: _removeFile,
          onApplyRecommendation: _applyRecommendation,
          onGenerate: _mode == _Mode.kurz ? _generate : _startSession,
          units: units,
          selectedUnitChoice: _unitChoice,
          onUnitChanged: _handleUnitChanged,
        );
      case _Step.generating:
        return const _LoadingView(label: 'KI erstellt Zusammenfassung …');
      case _Step.preview:
        return _PreviewView(result: _result!, onSave: _save, onDiscard: () {
          setState(() {
            _step = _Step.ready;
            _result = null;
          });
        });
      case _Step.preparingSession:
        return const _LoadingView(label: 'KI liest die Folien und markiert relevante Stellen …');
      case _Step.session:
        return _SessionView(
          files: _files,
          highlightsByFile: _highlightsByFile,
          sessionError: _sessionError,
          qaTurns: _qaTurns,
          questionController: _questionController,
          asking: _asking,
          askError: _askError,
          onAsk: _ask,
          onFinish: _finishSession,
        );
    }
  }
}

class _ModeSelectView extends StatelessWidget {
  const _ModeSelectView({required this.onChoose});
  final void Function(_Mode mode) onChoose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      children: [
        Text(
          'Wie möchtest du vorbereiten?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        _ModeOption(
          icon: Icons.bolt_outlined,
          title: 'Kurz vorbereiten',
          subtitle: 'Folien hochladen → KI erstellt eine strukturierte Zusammenfassung mit Kernkonzepten. Schnell, für den groben Überblick.',
          onTap: () => onChoose(_Mode.kurz),
        ),
        const SizedBox(height: 12),
        _ModeOption(
          icon: Icons.travel_explore_outlined,
          title: 'Ausführlich vorbereiten',
          subtitle: 'Die KI liest ALLE Folien, markiert die relevantesten Stellen und beantwortet '
              'direkt gestellte Rückfragen dazu. Deine Fragen werden automatisch als Merkpunkte '
              'zur Einheit gespeichert – für spätere Vertiefung.',
          onTap: () => onChoose(_Mode.ausfuehrlich),
        ),
        const SizedBox(height: 16),
        Text(
          'Beide Modi legen die hochgeladenen Folien als Material im Fach ab.',
          style: TextStyle(fontSize: 12, color: c.inkMuted),
        ),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: c.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickView extends StatelessWidget {
  const _PickView({
    required this.onPick,
    required this.onPickExisting,
    required this.onChangeMode,
    this.error,
    this.rawResponse,
  });

  final VoidCallback onPick;
  final VoidCallback onPickExisting;
  final VoidCallback onChangeMode;
  final String? error;
  final String? rawResponse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.upload_file_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Lade Vorlesungsfolien als PDF, Word oder PowerPoint hoch (auch mehrere '
            'auf einmal).',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Dateien auswählen'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPickExisting,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Vorhandenes Material verwenden'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onChangeMode, child: const Text('Anderen Modus wählen')),
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            if (rawResponse != null)
              TextButton(
                onPressed: () => showRawResponseDialog(context, rawResponse!),
                child: const Text('KI-Antwort anzeigen'),
              ),
          ],
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.mode,
    required this.files,
    required this.combinedText,
    required this.onAddMore,
    required this.onAddExisting,
    required this.onRemove,
    required this.onApplyRecommendation,
    required this.onGenerate,
    required this.units,
    required this.selectedUnitChoice,
    required this.onUnitChanged,
    this.error,
  });

  final _Mode mode;
  final List<_PickedFile> files;
  final String combinedText;
  final VoidCallback onAddMore;
  final VoidCallback onAddExisting;
  final void Function(int index) onRemove;
  final void Function(ChunkGranularity granularity) onApplyRecommendation;
  final VoidCallback onGenerate;
  final List<LectureUnit> units;
  final String selectedUnitChoice;
  final void Function(String? choice) onUnitChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsRepository>().settings;
    final analysis = ContentAnalyzer.analyze(combinedText);

    return ListView(
      children: [
        Text('${files.length} Datei${files.length == 1 ? '' : 'en'} ausgewählt',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...files.asMap().entries.map((e) => Card(
              child: ListTile(
                leading: const Icon(Icons.slideshow_outlined),
                title: Text(e.value.fileName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (e.value.fileName.toLowerCase().endsWith('.pdf') && e.value.bytes.isNotEmpty)
                      IconButton(
                        tooltip: 'Folie ansehen',
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PdfPreviewScreen(
                            fileName: e.value.fileName,
                            bytes: e.value.bytes,
                            documentText: e.value.text,
                          ),
                        )),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => onRemove(e.key),
                    ),
                  ],
                ),
              ),
            )),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onAddMore,
              icon: const Icon(Icons.add),
              label: const Text('Weitere Datei hinzufügen'),
            ),
            OutlinedButton.icon(
              onPressed: onAddExisting,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Vorhandenes Material verwenden'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: selectedUnitChoice,
          decoration: const InputDecoration(
            labelText: 'Einheit',
            helperText: 'Ordnet die hochgeladenen Folien einer Vorlesungseinheit zu.',
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Keine Einheit')),
            ...units.map((u) => DropdownMenuItem(value: u.id, child: Text(u.title))),
            const DropdownMenuItem(value: '_new', child: Text('+ Neue Einheit anlegen')),
          ],
          onChanged: onUnitChanged,
        ),
        const SizedBox(height: 16),
        AnalysisRecommendationCard(
          analysis: analysis,
          currentGranularity: settings.chunkGranularity,
          onApply: () => onApplyRecommendation(analysis.recommendedGranularity),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onGenerate,
          icon: Icon(mode == _Mode.kurz ? Icons.auto_awesome_outlined : Icons.travel_explore_outlined),
          label: Text(mode == _Mode.kurz ? 'Zusammenfassung erstellen' : 'Ausführlich vorbereiten starten'),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}

class _PreviewView extends StatelessWidget {
  const _PreviewView({required this.result, required this.onSave, required this.onDiscard});

  final Map<String, dynamic> result;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final keyPoints = (result['key_points'] as List?)?.map((e) => e.toString()).toList() ?? [];
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Text(result['title'] as String? ?? '', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (keyPoints.isNotEmpty) ...[
                Text('Kernkonzepte', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...keyPoints.map((k) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [const Text('•  '), Expanded(child: Text(k))],
                      ),
                    )),
                const SizedBox(height: 16),
              ],
              Text('Zusammenfassung', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(result['overview'] as String? ?? ''),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: onDiscard, child: const Text('Verwerfen')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(onPressed: onSave, child: const Text('Speichern')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Interaktiver Teil des "Ausführlich"-Modus: zeigt die von der KI markierten
/// relevantesten Stellen je Datei sowie einen Frage-Chat, der direkt auf den
/// gerade hochgeladenen Folientext gestützt ist (nicht auf das gesamte
/// Fach-Material wie ModuleChatScreen). Jede gestellte Frage wird beim
/// Abschließen (siehe onFinish) automatisch als Merkpunkt gespeichert.
class _SessionView extends StatelessWidget {
  const _SessionView({
    required this.files,
    required this.highlightsByFile,
    required this.qaTurns,
    required this.questionController,
    required this.asking,
    required this.onAsk,
    required this.onFinish,
    this.sessionError,
    this.askError,
  });

  final List<_PickedFile> files;
  final Map<String, List<MaterialHighlight>> highlightsByFile;
  final String? sessionError;
  final List<({String question, String answer})> qaTurns;
  final TextEditingController questionController;
  final bool asking;
  final String? askError;
  final VoidCallback onAsk;
  final VoidCallback onFinish;

  Color _dotColor(AppColors c, HighlightColor color) => switch (color) {
        HighlightColor.red => c.danger,
        HighlightColor.green => c.good,
        HighlightColor.yellow => c.warn,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final totalHighlights = highlightsByFile.values.fold<int>(0, (sum, l) => sum + l.length);

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              if (sessionError != null) ...[
                Text(sessionError!, style: TextStyle(color: c.danger, fontSize: 12.5)),
                const SizedBox(height: 12),
              ],
              Text('Markierte Stellen ($totalHighlights)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (totalHighlights == 0)
                Text('Keine relevanten Stellen gefunden.', style: TextStyle(color: c.inkMuted))
              else
                ...highlightsByFile.entries.where((e) => e.value.isNotEmpty).map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surface,
                          border: Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(entry.key,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                ),
                                if (entry.key.toLowerCase().endsWith('.pdf'))
                                  _FileViewButton(
                                    fileName: entry.key,
                                    files: files,
                                  ),
                              ],
                            ),
                            subtitle: Text('${entry.value.length} markiert', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                            children: entry.value
                                .map((h) => Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Container(
                                              width: 9,
                                              height: 9,
                                              decoration: BoxDecoration(color: _dotColor(c, h.color), shape: BoxShape.circle),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(h.text, style: const TextStyle(fontSize: 12.5)),
                                                if (h.reason != null && h.reason!.isNotEmpty)
                                                  Text(h.reason!, style: TextStyle(fontSize: 11, color: c.inkMuted)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    )),
              const SizedBox(height: 20),
              Text('Direkt nachfragen', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Deine Fragen werden automatisch als Merkpunkte zur gewählten Einheit gespeichert.',
                style: TextStyle(fontSize: 11.5, color: c.inkMuted),
              ),
              const SizedBox(height: 10),
              ...qaTurns.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.question, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(t.answer, style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4)),
                      ],
                    ),
                  )),
              if (asking)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              if (askError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(askError!, style: TextStyle(color: c.danger, fontSize: 12.5)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: questionController,
                enabled: !asking,
                decoration: InputDecoration(
                  hintText: 'Frage zu den Folien …',
                  filled: true,
                  fillColor: c.surfaceAlt,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => asking ? null : onAsk(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: asking ? null : onAsk,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: onFinish, child: const Text('Fertig & speichern')),
      ],
    );
  }
}

/// Öffnet die tatsächliche Folie (noch ungespeicherte Bytes aus [files]) in
/// [PdfPreviewScreen] – siehe Doc-Kommentar dort: ohne das sähe man in
/// dieser Session nur die von der KI markierten Textstellen, nie das
/// eigentliche Dokument.
class _FileViewButton extends StatelessWidget {
  const _FileViewButton({required this.fileName, required this.files});

  final String fileName;
  final List<_PickedFile> files;

  @override
  Widget build(BuildContext context) {
    _PickedFile? match;
    for (final f in files) {
      if (f.fileName == fileName) {
        match = f;
        break;
      }
    }
    if (match == null) return const SizedBox.shrink();
    final file = match;
    return IconButton(
      tooltip: 'Folie ansehen',
      icon: const Icon(Icons.visibility_outlined, size: 20),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          fileName: file.fileName,
          bytes: file.bytes,
          documentText: file.text,
        ),
      )),
    );
  }
}
