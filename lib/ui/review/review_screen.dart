import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/concept.dart';
import '../../models/flashcard.dart';
import '../../models/material_item.dart';
import '../../repositories/concept_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/pdf_service.dart';
import '../widgets/raw_response_dialog.dart';

enum _Step { pick, generating, preview }

/// Nachbereiten-Modus: Folien UND Übungsaufgaben gemeinsam hochladen → die
/// KI erstellt gezielte Lernkonzepte und Karteikarten mit Fokus auf tiefem
/// Verständnis der Übungsaufgaben (nicht nur Theorie-Wiedergabe).
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  _Step _step = _Step.pick;
  String? _slidesFileName;
  String? _slidesText;
  String? _exercisesFileName;
  String? _exercisesText;
  Map<String, dynamic>? _result;
  String? _error;
  String? _rawResponse;
  bool _extracting = false;

  bool get _readyToGenerate => _slidesText != null && _exercisesText != null;

  Future<void> _pick({required bool isSlides}) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return;

    setState(() {
      _extracting = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final text = PdfService().extractText(bytes);
      setState(() {
        if (isSlides) {
          _slidesFileName = file.name;
          _slidesText = text;
        } else {
          _exercisesFileName = file.name;
          _exercisesText = text;
        }
        _extracting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _extracting = false;
      });
    }
  }

  Future<void> _generate() async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() => _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte zuerst in den Einstellungen eintragen.');
      return;
    }

    setState(() {
      _step = _Step.generating;
      _error = null;
      _rawResponse = null;
    });

    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.selectedModel);
      final result = await ai.generateConceptsAndFlashcards(
        slidesText: _slidesText!,
        exercisesText: _exercisesText!,
      );
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
    final now = DateTime.now();
    final slidesMaterial = MaterialItem(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      fileName: _slidesFileName!,
      kind: MaterialKind.slide,
      extractedText: _slidesText!,
      createdAt: now,
    );
    final exercisesMaterial = MaterialItem(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      fileName: _exercisesFileName!,
      kind: MaterialKind.exercise,
      extractedText: _exercisesText!,
      createdAt: now,
    );
    final sourceIds = [slidesMaterial.id, exercisesMaterial.id];

    final concepts = ((result['concepts'] as List?) ?? [])
        .map((c) => Concept(
              id: const Uuid().v4(),
              moduleId: widget.moduleId,
              title: (c['title'] ?? '').toString(),
              explanation: (c['explanation'] ?? '').toString(),
              sourceMaterialIds: sourceIds,
              createdAt: now,
            ))
        .toList();

    final flashcards = ((result['flashcards'] as List?) ?? [])
        .map((f) => Flashcard(
              id: const Uuid().v4(),
              moduleId: widget.moduleId,
              front: (f['front'] ?? '').toString(),
              back: (f['back'] ?? '').toString(),
              createdAt: now,
              due: now,
            ))
        .toList();

    await context.read<MaterialRepository>().save(slidesMaterial);
    if (!mounted) return;
    await context.read<MaterialRepository>().save(exercisesMaterial);
    if (!mounted) return;
    await context.read<ConceptRepository>().saveAll(concepts);
    if (!mounted) return;
    await context.read<FlashcardRepository>().saveAll(flashcards);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nachbereiten-Modus')),
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
          slidesFileName: _slidesFileName,
          exercisesFileName: _exercisesFileName,
          extracting: _extracting,
          error: _error,
          rawResponse: _rawResponse,
          onPickSlides: () => _pick(isSlides: true),
          onPickExercises: () => _pick(isSlides: false),
          onGenerate: _readyToGenerate ? _generate : null,
        );
      case _Step.generating:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('KI erstellt Konzepte und Karteikarten …'),
            ],
          ),
        );
      case _Step.preview:
        return _PreviewView(
          result: _result!,
          onSave: _save,
          onDiscard: () => setState(() {
            _step = _Step.pick;
            _result = null;
          }),
        );
    }
  }
}

class _PickView extends StatelessWidget {
  const _PickView({
    required this.slidesFileName,
    required this.exercisesFileName,
    required this.extracting,
    required this.onPickSlides,
    required this.onPickExercises,
    required this.onGenerate,
    this.error,
    this.rawResponse,
  });

  final String? slidesFileName;
  final String? exercisesFileName;
  final bool extracting;
  final VoidCallback onPickSlides;
  final VoidCallback onPickExercises;
  final VoidCallback? onGenerate;
  final String? error;
  final String? rawResponse;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Text(
          'Lade Folien und die zugehörigen Übungsaufgaben hoch. Die KI '
          'analysiert beides zusammen – der Fokus liegt darauf, WARUM die '
          'Übungen so gelöst werden, nicht nur auf Theorie.',
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: Text(slidesFileName ?? 'Folien auswählen'),
            trailing: const Icon(Icons.upload_file_outlined),
            onTap: extracting ? null : onPickSlides,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.assignment_outlined),
            title: Text(exercisesFileName ?? 'Übungsaufgaben auswählen'),
            trailing: const Icon(Icons.upload_file_outlined),
            onTap: extracting ? null : onPickExercises,
          ),
        ),
        const SizedBox(height: 24),
        if (extracting) const Center(child: CircularProgressIndicator()),
        FilledButton.icon(
          onPressed: onGenerate,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Konzepte & Karteikarten erstellen'),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: const TextStyle(color: Colors.red)),
          if (rawResponse != null)
            TextButton(
              onPressed: () => showRawResponseDialog(context, rawResponse!),
              child: const Text('KI-Antwort anzeigen'),
            ),
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
    final concepts = (result['concepts'] as List?) ?? [];
    final flashcards = (result['flashcards'] as List?) ?? [];
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Text('${concepts.length} Konzepte, ${flashcards.length} Karteikarten',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              ...concepts.map((c) => Card(
                    child: ExpansionTile(
                      title: Text((c['title'] ?? '').toString()),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text((c['explanation'] ?? '').toString()),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              Text('Karteikarten', style: Theme.of(context).textTheme.titleMedium),
              ...flashcards.map((f) => Card(
                    child: ListTile(
                      title: Text((f['front'] ?? '').toString()),
                      subtitle: Text((f['back'] ?? '').toString()),
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: onDiscard, child: const Text('Verwerfen'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: onSave, child: const Text('Speichern'))),
          ],
        ),
      ],
    );
  }
}
