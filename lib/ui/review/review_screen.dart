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
import '../../services/material_text_extractor.dart';
import '../../services/question_parsing.dart';
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
  final Set<int> _appliedIssueIndices = {};

  /// Anzahl der Karteikarten, die die KI unvollständig geliefert hat (z.B.
  /// "options" bei einer Single-Choice-Frage vergessen) und die sich auch
  /// nicht zu einer einfachen Karteikarte retten ließen (siehe
  /// QuestionParsing.normalizeGeneratedFlashcard) – wurden verworfen statt
  /// als stumme "nur Vorderseite"-Karte gespeichert zu werden.
  int _droppedFlashcardCount = 0;

  bool get _readyToGenerate => _slidesFiles.isNotEmpty && _exercisesFiles.isNotEmpty;

  String get _slidesText =>
      _slidesFiles.map((f) => '=== Datei: ${f.fileName} ===\n${f.text}').join('\n\n');
  String get _exercisesText =>
      _exercisesFiles.map((f) => '=== Datei: ${f.fileName} ===\n${f.text}').join('\n\n');

  Future<void> _pick({required bool isSlides}) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: MaterialTextExtractor.supportedExtensions,
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
        final text = MaterialTextExtractor().extractText(file.name, bytes);
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

      // Manche Modelle liefern trotz Anweisung unvollständige Karten (z.B.
      // "options" bei einer Single-Choice-Frage vergessen). Statt eine
      // stumme "nur Vorderseite"-Karte zu speichern: retten, wenn irgendwo
      // im Eintrag noch eine brauchbare Antwort steckt, sonst verwerfen und
      // dem Nutzer sichtbar melden statt es zu verschweigen.
      final normalized = <Map<String, dynamic>>[];
      var dropped = 0;
      for (final entry in (result['flashcards'] as List? ?? const [])) {
        final fixed = QuestionParsing.normalizeGeneratedFlashcard(Map<String, dynamic>.from(entry as Map));
        if (fixed == null) {
          dropped++;
        } else {
          normalized.add(fixed);
        }
      }
      result['flashcards'] = normalized;

      setState(() {
        _result = result;
        _droppedFlashcardCount = dropped;
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
      _appliedIssueIndices.clear();
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

  /// Übernimmt den vom Crosscheck vorgeschlagenen Korrektur-Eintrag
  /// ("fix") anstelle des Original-Konzepts/der Original-Karteikarte an
  /// derselben Stelle. [issueIndex] ist die Position INNERHALB der
  /// issues-Liste (für die "Übernommen"-Markierung in der UI), nicht der
  /// targetIndex des betroffenen Konzepts/der Karteikarte selbst.
  void _applyCrosscheckFix(int issueIndex) {
    final issues = (_crosscheckResult?['issues'] as List?) ?? const [];
    if (issueIndex < 0 || issueIndex >= issues.length || _result == null) return;
    final issue = Map<String, dynamic>.from(issues[issueIndex] as Map);
    final targetType = issue['targetType'] as String?;
    final targetIndex = (issue['targetIndex'] as num?)?.toInt();
    final fix = issue['fix'];
    if (targetType == null || targetIndex == null || fix is! Map) return;

    final listKey = switch (targetType) {
      'concept' => 'concepts',
      'flashcard' => 'flashcards',
      _ => null,
    };
    if (listKey == null) return;

    setState(() {
      final list = List<dynamic>.from(_result![listKey] as List? ?? const []);
      if (targetIndex >= 0 && targetIndex < list.length) {
        list[targetIndex] = Map<String, dynamic>.from(fix);
        _result![listKey] = list;
      }
      _appliedIssueIndices.add(issueIndex);
    });
  }

  void _applyAllCrosscheckFixes() {
    final issues = (_crosscheckResult?['issues'] as List?) ?? const [];
    for (var i = 0; i < issues.length; i++) {
      if (!_appliedIssueIndices.contains(i)) _applyCrosscheckFix(i);
    }
  }

  Future<void> _save() async {
    final result = _result!;
    final now = DateTime.now();
    // Nachbereiten setzt "behandelt" standardmäßig auf true: wer Folien UND
    // Übungen gemeinsam nachbereitet, hat das Thema damit i.d.R. bereits in
    // der Vorlesung gehabt (Übungen kommen meist erst danach). Lässt sich im
    // Modul-Detail jederzeit manuell umstellen.
    final slidesMaterials = _slidesFiles
        .map((f) => MaterialItem(
              id: const Uuid().v4(),
              moduleId: widget.moduleId,
              fileName: f.fileName,
              kind: MaterialKind.slide,
              extractedText: f.text,
              createdAt: now,
              covered: true,
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
              covered: true,
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

    final flashcards = ((result['flashcards'] as List?) ?? []).map((raw) {
      final f = Map<String, dynamic>.from(raw as Map);
      final type = QuestionParsing.parseType(f['type'] as String?);
      final escalate = f['escalate'] == true && type == QuestionType.singleChoice;
      return Flashcard(
        id: const Uuid().v4(),
        moduleId: widget.moduleId,
        front: (f['front'] ?? '').toString(),
        back: (f['back'] ?? '').toString(),
        createdAt: now,
        due: now,
        type: type,
        options: QuestionParsing.parseOptions(f['options']),
        correctText: f['correctText'] as String?,
        blanks: QuestionParsing.parseBlanks(f['blanks']),
        dragPairs: QuestionParsing.parseDragPairs(f['dragPairs']),
        variantChain: escalate ? QuestionParsing.escalationChain : null,
      );
    }).toList();

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
          droppedFlashcardCount: _droppedFlashcardCount,
          onSave: _save,
          onDiscard: () => setState(() {
            _step = _Step.pick;
            _result = null;
            _droppedFlashcardCount = 0;
          }),
          crosschecking: _crosschecking,
          crosscheckResult: _crosscheckResult,
          crosscheckError: _crosscheckError,
          appliedIssueIndices: _appliedIssueIndices,
          onCrosscheck: _crosscheck,
          onApplyFix: _applyCrosscheckFix,
          onApplyAllFixes: _applyAllCrosscheckFixes,
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
    required this.droppedFlashcardCount,
    required this.onSave,
    required this.onDiscard,
    required this.crosschecking,
    required this.onCrosscheck,
    required this.appliedIssueIndices,
    required this.onApplyFix,
    required this.onApplyAllFixes,
    this.crosscheckResult,
    this.crosscheckError,
  });

  final Map<String, dynamic> result;
  final int droppedFlashcardCount;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final bool crosschecking;
  final VoidCallback onCrosscheck;
  final Set<int> appliedIssueIndices;
  final void Function(int issueIndex) onApplyFix;
  final VoidCallback onApplyAllFixes;
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
              if (droppedFlashcardCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '⚠️ $droppedFlashcardCount Karte${droppedFlashcardCount == 1 ? '' : 'n'} '
                  'wegen unvollständiger KI-Antwort übersprungen.',
                  style: const TextStyle(color: Colors.orange, fontSize: 12.5),
                ),
              ],
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
              ...flashcards.map((raw) {
                final f = Map<String, dynamic>.from(raw as Map);
                final type = QuestionParsing.parseType(f['type'] as String?);
                return Card(
                  child: ListTile(
                    leading: Icon(_iconFor(type)),
                    title: Text((f['front'] ?? '').toString()),
                    subtitle: Text('${type.label} · ${_answerPreview(f, type)}'),
                  ),
                );
              }),
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
                        else ...[
                          ...issues.asMap().entries.map((entry) {
                            final i = entry.key;
                            final issue = Map<String, dynamic>.from(entry.value as Map);
                            final targetType = issue['targetType'] as String?;
                            final targetIndex = (issue['targetIndex'] as num?)?.toInt();
                            final fix = issue['fix'];
                            final applied = appliedIssueIndices.contains(i);
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(_issueLabel(targetType, targetIndex),
                                            style: const TextStyle(fontWeight: FontWeight.w600)),
                                      ),
                                      if (applied)
                                        const Text('✓ übernommen',
                                            style: TextStyle(color: Colors.green, fontSize: 12))
                                      else if (fix is Map)
                                        TextButton(
                                          onPressed: () => onApplyFix(i),
                                          child: const Text('Übernehmen'),
                                        ),
                                    ],
                                  ),
                                  Text((issue['problem'] ?? '').toString()),
                                ],
                              ),
                            );
                          }),
                          if (issues.where((it) => it is Map && it['fix'] is Map).length > 1)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: onApplyAllFixes,
                                child: const Text('Alle Vorschläge übernehmen'),
                              ),
                            ),
                        ],
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

  /// Beschriftung für eine Crosscheck-Zeile: zeigt den AKTUELLEN Titel/die
  /// aktuelle Frage des betroffenen Eintrags (spiegelt bereits übernommene
  /// Korrekturen anderer Issues an derselben Stelle wider).
  String _issueLabel(String? targetType, int? targetIndex) {
    if (targetType == null || targetIndex == null) return 'Änderungsvorschlag';
    final listKey = switch (targetType) {
      'concept' => 'concepts',
      'flashcard' => 'flashcards',
      _ => null,
    };
    if (listKey == null) return 'Änderungsvorschlag';
    final list = (result[listKey] as List?) ?? const [];
    if (targetIndex < 0 || targetIndex >= list.length) return 'Änderungsvorschlag';
    final entry = Map<String, dynamic>.from(list[targetIndex] as Map);
    final prefix = targetType == 'concept' ? 'Konzept' : 'Karteikarte';
    final text = (targetType == 'concept' ? entry['title'] : entry['front']) ?? '';
    return '$prefix: $text';
  }

  IconData _iconFor(QuestionType type) => switch (type) {
        QuestionType.flashcard => Icons.style_outlined,
        QuestionType.singleChoice => Icons.radio_button_checked_outlined,
        QuestionType.multipleChoice => Icons.check_box_outlined,
        QuestionType.freeText => Icons.short_text,
        QuestionType.fillBlank => Icons.space_bar,
        QuestionType.dragDrop => Icons.compare_arrows,
        QuestionType.dragCategory => Icons.category_outlined,
      };

  String _answerPreview(Map<String, dynamic> f, QuestionType type) {
    switch (type) {
      case QuestionType.flashcard:
        return (f['back'] ?? '').toString();
      case QuestionType.singleChoice:
      case QuestionType.multipleChoice:
        final options = (f['options'] as List?) ?? const [];
        return options
            .where((o) => o is Map && o['isCorrect'] == true)
            .map((o) => (o as Map)['text'])
            .join(', ');
      case QuestionType.freeText:
        return (f['correctText'] ?? '').toString();
      case QuestionType.fillBlank:
        return ((f['blanks'] as List?) ?? const []).join(', ');
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        final pairs = (f['dragPairs'] as List?) ?? const [];
        return pairs.map((p) => '${(p as Map)['source']} → ${p['target']}').join(', ');
    }
  }
}
