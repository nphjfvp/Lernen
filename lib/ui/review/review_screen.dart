import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_settings.dart';
import '../../models/concept.dart';
import '../../models/flashcard.dart';
import '../../models/material_item.dart';
import '../../repositories/concept_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/content_analyzer.dart';
import '../../services/pdf_service.dart';
import '../widgets/analysis_recommendation_card.dart';
import '../widgets/raw_response_dialog.dart';

enum _Step { pick, generating, preview }

class _PickedFile {
  _PickedFile({required this.fileName, required this.text});
  final String fileName;
  final String text;
}

/// Nachbereiten-Modus: Folien UND Übungsaufgaben gemeinsam hochladen (auch
/// mehrere Dateien je Kategorie) → die KI erstellt gezielte Lernkonzepte
/// und Karteikarten mit Fokus auf tiefem Verständnis der Übungsaufgaben
/// (nicht nur Theorie-Wiedergabe). Ein optionaler Crosscheck-Pass mit einem
/// zweiten Modell kann die Ergebnisse anschließend gegenprüfen.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  _Step _step = _Step.pick;
  final List<_PickedFile> _slidesFiles = [];
  final List<_PickedFile> _exercisesFiles = [];
  Map<String, dynamic>? _result;
  String? _error;
  String? _rawResponse;
  bool _extracting = false;

  bool _crosschecking = false;
  Map<String, dynamic>? _crosscheckResult;
  String? _crosscheckError;

  bool get _readyToGenerate => _slidesFiles.isNotEmpty && _exercisesFiles.isNotEmpty;

  String get _slidesText =>
      _slidesFiles.map((f) => '=== Datei: ${f.fileName} ===\n${f.text}').join('\n\n');
  String get _exercisesText =>
      _exercisesFiles.map((f) => '=== Datei: ${f.fileName} ===\n${f.text}').join('\n\n');

  Future<void> _pick({required bool isSlides}) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked.isEmpty) return;

    setState(() {
      _extracting = true;
      _error = null;
    });
    final target = isSlides ? _slidesFiles : _exercisesFiles;
    for (final file in picked) {
      try {
        final bytes = await file.readAsBytes();
        final text = PdfService().extractText(bytes);
        if (text.isNotEmpty) {
          target.add(_PickedFile(fileName: file.name, text: text));
        }
      } catch (e) {
        setState(() => _error = '${file.name}: $e');
      }
    }
    setState(() => _extracting = false);
  }

  void _removeFile({required bool isSlides, required int index}) {
    setState(() {
      (isSlides ? _slidesFiles : _exercisesFiles).removeAt(index);
    });
  }

  Future<void> _applyRecommendation(ChunkGranularity granularity) async {
    final repo = context.read<SettingsRepository>();
    await repo.update(repo.settings.copyWith(chunkGranularity: granularity));
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
      _crosscheckResult = null;
      _crosscheckError = null;
    });

    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final result = await ai.generateConceptsAndFlashcards(
        slidesText: _slidesText,
        exercisesText: _exercisesText,
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
        _step = _Step.pick;
      });
    } catch (e) {
      setState(() {
        _error = 'Unerwarteter Fehler: $e';
        _step = _Step.pick;
      });
    }
  }

  Future<void> _crosscheck() async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey || _result == null) return;

    setState(() {
      _crosschecking = true;
      _crosscheckError = null;
    });
    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.crosscheckModelId);
      final result = await ai.crosscheckConceptsAndFlashcards(
        slidesText: _slidesText,
        exercisesText: _exercisesText,
        generated: _result!,
      );
      setState(() {
        _crosscheckResult = result;
        _crosschecking = false;
      });
    } on AiServiceException catch (e) {
      setState(() {
        _crosscheckError = e.message;
        _crosschecking = false;
      });
    } catch (e) {
      setState(() {
        _crosscheckError = 'Unerwarteter Fehler: $e';
        _crosschecking = false;
      });
    }
  }

  Future<void> _save() async {
    final result = _result!;
    final now = DateTime.now();
    final slidesMaterials = _slidesFiles
        .map((f) => MaterialItem(
              id: const Uuid().v4(),
              moduleId: widget.moduleId,
              fileName: f.fileName,
              kind: MaterialKind.slide,
              extractedText: f.text,
              createdAt: now,
            ))
        .toList();
    final exercisesMaterials = _exercisesFiles
        .map((f) => MaterialItem(
              id: const Uuid().v4(),
              moduleId: widget.moduleId,
              fileName: f.fileName,
              kind: MaterialKind.exercise,
              extractedText: f.text,
              createdAt: now,
            ))
        .toList();
    final sourceIds = [
      ...slidesMaterials.map((m) => m.id),
      ...exercisesMaterials.map((m) => m.id),
    ];

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

    final materialRepo = context.read<MaterialRepository>();
    for (final material in [...slidesMaterials, ...exercisesMaterials]) {
      await materialRepo.save(material);
      if (!mounted) return;
    }
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
        final settings = context.watch<SettingsRepository>().settings;
        final analysis = _readyToGenerate
            ? ContentAnalyzer.analyze('$_slidesText\n\n$_exercisesText')
            : null;
        return _PickView(
          slidesFiles: _slidesFiles.map((f) => f.fileName).toList(),
          exercisesFiles: _exercisesFiles.map((f) => f.fileName).toList(),
          extracting: _extracting,
          error: _error,
          rawResponse: _rawResponse,
          onPickSlides: () => _pick(isSlides: true),
          onPickExercises: () => _pick(isSlides: false),
          onRemoveSlide: (i) => _removeFile(isSlides: true, index: i),
          onRemoveExercise: (i) => _removeFile(isSlides: false, index: i),
          onGenerate: _readyToGenerate ? _generate : null,
          analysis: analysis,
          currentGranularity: settings.chunkGranularity,
          onApplyRecommendation: _applyRecommendation,
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
          crosschecking: _crosschecking,
          crosscheckResult: _crosscheckResult,
          crosscheckError: _crosscheckError,
          onCrosscheck: _crosscheck,
        );
    }
  }
}

class _PickView extends StatelessWidget {
  const _PickView({
    required this.slidesFiles,
    required this.exercisesFiles,
    required this.extracting,
    required this.onPickSlides,
    required this.onPickExercises,
    required this.onRemoveSlide,
    required this.onRemoveExercise,
    required this.onGenerate,
    required this.currentGranularity,
    required this.onApplyRecommendation,
    this.analysis,
    this.error,
    this.rawResponse,
  });

  final List<String> slidesFiles;
  final List<String> exercisesFiles;
  final bool extracting;
  final VoidCallback onPickSlides;
  final VoidCallback onPickExercises;
  final void Function(int index) onRemoveSlide;
  final void Function(int index) onRemoveExercise;
  final VoidCallback? onGenerate;
  final ChunkGranularity currentGranularity;
  final void Function(ChunkGranularity granularity) onApplyRecommendation;
  final ContentAnalysis? analysis;
  final String? error;
  final String? rawResponse;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Text(
          'Lade Folien und die zugehörigen Übungsaufgaben hoch (auch mehrere '
          'Dateien je Kategorie). Die KI analysiert beides zusammen – der '
          'Fokus liegt darauf, WARUM die Übungen so gelöst werden, nicht nur '
          'auf Theorie.',
        ),
        const SizedBox(height: 24),
        Text('Folien', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...slidesFiles.asMap().entries.map((e) => Card(
              child: ListTile(
                leading: const Icon(Icons.slideshow_outlined),
                title: Text(e.value),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemoveSlide(e.key),
                ),
              ),
            )),
        OutlinedButton.icon(
          onPressed: extracting ? null : onPickSlides,
          icon: const Icon(Icons.add),
          label: Text(slidesFiles.isEmpty ? 'Folien auswählen' : 'Weitere Folien hinzufügen'),
        ),
        const SizedBox(height: 16),
        Text('Übungsaufgaben', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...exercisesFiles.asMap().entries.map((e) => Card(
              child: ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: Text(e.value),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemoveExercise(e.key),
                ),
              ),
            )),
        OutlinedButton.icon(
          onPressed: extracting ? null : onPickExercises,
          icon: const Icon(Icons.add),
          label: Text(exercisesFiles.isEmpty ? 'Übungsaufgaben auswählen' : 'Weitere Übungen hinzufügen'),
        ),
        const SizedBox(height: 16),
        if (extracting) const Center(child: CircularProgressIndicator()),
        if (analysis case final a?) ...[
          AnalysisRecommendationCard(
            analysis: a,
            currentGranularity: currentGranularity,
            onApply: () => onApplyRecommendation(a.recommendedGranularity),
          ),
          const SizedBox(height: 16),
        ],
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
  const _PreviewView({
    required this.result,
    required this.onSave,
    required this.onDiscard,
    required this.crosschecking,
    required this.onCrosscheck,
    this.crosscheckResult,
    this.crosscheckError,
  });

  final Map<String, dynamic> result;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final bool crosschecking;
  final VoidCallback onCrosscheck;
  final Map<String, dynamic>? crosscheckResult;
  final String? crosscheckError;

  @override
  Widget build(BuildContext context) {
    final concepts = (result['concepts'] as List?) ?? [];
    final flashcards = (result['flashcards'] as List?) ?? [];
    final issues = (crosscheckResult?['issues'] as List?) ?? [];
    final crosscheckOk = crosscheckResult != null && issues.isEmpty;

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
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Crosscheck (zweites Modell prüft die Ergebnisse)',
                                style: Theme.of(context).textTheme.titleSmall),
                          ),
                          if (crosschecking)
                            const SizedBox(
                                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            TextButton(onPressed: onCrosscheck, child: const Text('Gegenprüfen')),
                        ],
                      ),
                      if (crosscheckError != null) ...[
                        const SizedBox(height: 8),
                        Text(crosscheckError!, style: const TextStyle(color: Colors.red)),
                      ],
                      if (crosscheckResult != null) ...[
                        const SizedBox(height: 8),
                        if (crosscheckOk)
                          const Text('Keine Probleme gefunden.')
                        else
                          ...issues.map((issue) => Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text((issue['title'] ?? '').toString(),
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text((issue['problem'] ?? '').toString()),
                                    if ((issue['suggestion'] ?? '').toString().isNotEmpty)
                                      Text('Vorschlag: ${issue['suggestion']}',
                                          style: const TextStyle(fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              )),
                      ],
                    ],
                  ),
                ),
              ),
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
