import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/material_item.dart';
import '../../models/summary.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/summary_repository.dart';
import '../../services/ai_service.dart';
import '../../services/pdf_service.dart';
import '../widgets/raw_response_dialog.dart';

enum _Step { pick, extracting, generating, preview }

/// Vorbereiten-Modus: PDF-Vorlesungsfolien hochladen → KI erstellt eine
/// strukturierte Zusammenfassung mit hervorgehobenen Kernkonzepten für den
/// schnellen Überblick vor der Sitzung.
class PrepareScreen extends StatefulWidget {
  const PrepareScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  State<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends State<PrepareScreen> {
  _Step _step = _Step.pick;
  String? _fileName;
  String? _extractedText;
  Map<String, dynamic>? _result;
  String? _error;
  String? _rawResponse;

  Future<void> _pickAndExtract() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      setState(() => _error = 'Datei konnte nicht gelesen werden: $e');
      return;
    }

    setState(() {
      _fileName = file.name;
      _step = _Step.extracting;
      _error = null;
    });

    try {
      final text = PdfService().extractText(bytes);
      if (text.isEmpty) {
        setState(() {
          _error = 'Kein Text im PDF gefunden (evtl. gescannte Bilder ohne Text-Ebene).';
          _step = _Step.pick;
        });
        return;
      }
      setState(() {
        _extractedText = text;
      });
      await _generate();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _step = _Step.pick;
      });
    }
  }

  Future<void> _generate() async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() {
        _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte zuerst in den Einstellungen eintragen.';
        _step = _Step.pick;
      });
      return;
    }

    setState(() {
      _step = _Step.generating;
      _error = null;
      _rawResponse = null;
    });

    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.selectedModel);
      final result = await ai.generateSummary(_extractedText!);
      setState(() {
        _result = result;
        _step = _Step.preview;
      });
    } on AiServiceException catch (e) {
      setState(() {
        _error = e.message;
        _rawResponse = e.rawResponse;
        _step = _Step.pick;
      });
    } catch (e) {
      setState(() {
        _error = 'Unerwarteter Fehler: $e';
        _step = _Step.pick;
      });
    }
  }

  Future<void> _save() async {
    final result = _result!;
    final materialId = const Uuid().v4();
    final material = MaterialItem(
      id: materialId,
      moduleId: widget.moduleId,
      fileName: _fileName!,
      kind: MaterialKind.slide,
      extractedText: _extractedText!,
      createdAt: DateTime.now(),
    );
    final summary = Summary(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      sourceMaterialIds: [materialId],
      title: (result['title'] as String?)?.trim().isNotEmpty == true
          ? result['title'] as String
          : _fileName!,
      overview: result['overview'] as String? ?? '',
      keyPoints: (result['key_points'] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: DateTime.now(),
    );

    await context.read<MaterialRepository>().save(material);
    if (!mounted) return;
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
        return const _LoadingView(label: 'Text wird aus PDF extrahiert …');
      case _Step.generating:
        return const _LoadingView(label: 'KI erstellt Zusammenfassung …');
      case _Step.preview:
        return _PreviewView(result: _result!, onSave: _save, onDiscard: () {
          setState(() {
            _step = _Step.pick;
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
            'Lade Vorlesungsfolien als PDF hoch. Die KI erstellt daraus eine '
            'strukturierte Zusammenfassung mit den wichtigsten Konzepten.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF auswählen'),
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
