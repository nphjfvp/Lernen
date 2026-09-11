import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_settings.dart';
import '../../models/material_item.dart';
import '../../models/summary.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/summary_repository.dart';
import '../../services/ai_service.dart';
import '../../services/content_analyzer.dart';
import '../../services/pdf_service.dart';
import '../widgets/analysis_recommendation_card.dart';
import '../widgets/raw_response_dialog.dart';

enum _Step { pick, extracting, ready, generating, preview }

class _PickedFile {
  _PickedFile({required this.fileName, required this.text});
  final String fileName;
  final String text;
}

/// Vorbereiten-Modus: PDF-Vorlesungsfolien hochladen (auch mehrere auf
/// einmal) → KI erstellt daraus eine strukturierte Zusammenfassung mit
/// hervorgehobenen Kernkonzepten für den schnellen Überblick vor der
/// Sitzung.
class PrepareScreen extends StatefulWidget {
  const PrepareScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  State<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends State<PrepareScreen> {
  _Step _step = _Step.pick;
  final List<_PickedFile> _files = [];
  Map<String, dynamic>? _result;
  String? _error;
  String? _rawResponse;

  String get _combinedText => _files
      .map((f) => '=== Datei: ${f.fileName} ===\n${f.text}')
      .join('\n\n');

  Future<void> _pickAndExtract() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
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
        final text = PdfService().extractText(bytes);
        if (text.isNotEmpty) {
          newFiles.add(_PickedFile(fileName: file.name, text: text));
        }
      } catch (e) {
        setState(() => _error = '${file.name}: $e');
      }
    }

    setState(() {
      _files.addAll(newFiles);
      if (_files.isEmpty) {
        _error ??= 'Kein Text in den PDFs gefunden (evtl. gescannte Bilder ohne Text-Ebene).';
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

  Future<void> _applyRecommendation(ChunkGranularity granularity) async {
    final repo = context.read<SettingsRepository>();
    await repo.update(repo.settings.copyWith(chunkGranularity: granularity));
  }

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
    final materials = _files
        .map((f) => MaterialItem(
              id: const Uuid().v4(),
              moduleId: widget.moduleId,
              fileName: f.fileName,
              kind: MaterialKind.slide,
              extractedText: f.text,
              createdAt: now,
            ))
        .toList();

    final summary = Summary(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      sourceMaterialIds: materials.map((m) => m.id).toList(),
      title: (result['title'] as String?)?.trim().isNotEmpty == true
          ? result['title'] as String
          : _files.first.fileName,
      overview: result['overview'] as String? ?? '',
      keyPoints: (result['key_points'] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: now,
    );

    final materialRepo = context.read<MaterialRepository>();
    for (final material in materials) {
      await materialRepo.save(material);
      if (!mounted) return;
    }
    await context.read<SummaryRepository>().save(summary);
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
      case _Step.pick:
        return _PickView(
          error: _error,
          rawResponse: _rawResponse,
          onPick: _pickAndExtract,
        );
      case _Step.extracting:
        return const _LoadingView(label: 'Text wird aus PDFs extrahiert …');
      case _Step.ready:
        return _ReadyView(
          files: _files.map((f) => f.fileName).toList(),
          combinedText: _combinedText,
          error: _error,
          onAddMore: _pickAndExtract,
          onRemove: _removeFile,
          onApplyRecommendation: _applyRecommendation,
          onGenerate: _generate,
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
    }
  }
}

class _PickView extends StatelessWidget {
  const _PickView({required this.onPick, this.error, this.rawResponse});

  final VoidCallback onPick;
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
            'Lade Vorlesungsfolien als PDF hoch (auch mehrere auf einmal). '
            'Die KI erstellt daraus eine strukturierte Zusammenfassung mit '
            'den wichtigsten Konzepten.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDFs auswählen'),
          ),
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
          Text(label),
        ],
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.files,
    required this.combinedText,
    required this.onAddMore,
    required this.onRemove,
    required this.onApplyRecommendation,
    required this.onGenerate,
    this.error,
  });

  final List<String> files;
  final String combinedText;
  final VoidCallback onAddMore;
  final void Function(int index) onRemove;
  final void Function(ChunkGranularity granularity) onApplyRecommendation;
  final VoidCallback onGenerate;
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
                title: Text(e.value),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemove(e.key),
                ),
              ),
            )),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAddMore,
          icon: const Icon(Icons.add),
          label: const Text('Weitere PDF hinzufügen'),
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
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Zusammenfassung erstellen'),
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
