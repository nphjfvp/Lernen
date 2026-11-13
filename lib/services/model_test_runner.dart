import 'dart:typed_data';

import '../models/ai_model_info.dart';
import '../models/ai_usage.dart';
import '../models/app_settings.dart' show ChunkGranularity;
import '../models/model_test_result.dart';
import '../models/visual_scene3d.dart';
import 'ai_service.dart';
import 'scene3d_check.dart';

/// Womit ein Modell-Test arbeitet: eine Seite bzw. ein Text, eine Frage oder
/// eine Beschreibung.
class ModelTestInput {
  const ModelTestInput({required this.label, this.text = '', this.answer = '', this.pdfBytes, this.pageCount = 1});

  /// Für die Ergebnisliste („Seite 3 von folien.pdf“).
  final String label;

  /// Text der Seite, die Frage (Erklärung) oder die Beschreibung (3D-Modell).
  final String text;

  /// Lösung zur Frage (nur Erklärung, darf leer sein).
  final String answer;

  /// Die Seite(n) als kleine PDF (nur „Seite abschreiben“).
  final Uint8List? pdfBytes;
  final int pageCount;

  /// So viel Text geht höchstens in einen Test – er soll klein bleiben.
  static const maxChars = 12000;

  /// Gleiche Eingabe = gleicher Schlüssel.
  String get key {
    var hash = 0x811c9dc5;
    void add(int v) => hash = ((hash ^ v) * 0x01000193) & 0x7fffffff;
    for (final unit in '$label\n$text\n$answer'.codeUnits) {
      add(unit);
    }
    add(pdfBytes?.length ?? 0);
    return hash.toRadixString(16);
  }
}

/// Führt EINEN Modell-Test aus und misst dabei Dauer, Tokens und Kosten. Ein
/// Fehler des Modells ist auch ein Ergebnis (steht dann in
/// [ModelTestResult.error]) – beim Vergleichen will man ihn sehen.
class ModelTestRunner {
  /// Nur 3D-Modell: [plan] = bestätigter Bauplan der Vorab-Klärung (statt der
  /// Beschreibung), [mechBlocks] = Mechanik-Bausteine anbieten (null = wie
  /// eingestellt), [repairRounds] = so oft darf das Modell nachbessern (0 =
  /// nur prüfen).
  ///
  /// [ai] arbeitet mit dem zu testenden Modell. [generated]: die Fragen, die
  /// der Gegenprüf-Test prüfen soll. [staged]: Lektion in zwei Stufen, wie in
  /// den Einstellungen. [modelInfo]: Listenpreis, falls OpenRouter keine
  /// Kosten meldet.
  static Future<ModelTestResult> run({
    required String id,
    required ModelTestKind kind,
    required AiService ai,
    required ModelTestInput input,
    Map<String, dynamic>? generated,
    bool staged = true,
    String plan = '',
    bool? mechBlocks,
    int repairRounds = 0,
    AiModelInfo? Function(String model)? modelInfo,
    DateTime Function()? clock,
  }) async {
    final now = clock ?? DateTime.now;
    final started = now();
    final watch = Stopwatch()..start();
    final usages = <AiUsage>[];
    final before = ai.usageListener;
    ai.usageListener = usages.add;
    Map<String, dynamic> output = const {};
    String? error;
    try {
      output = await _call(
        kind,
        ai,
        input,
        generated: generated,
        staged: staged,
        plan: plan,
        mechBlocks: mechBlocks,
        repairRounds: repairRounds,
      );
    } on AiServiceException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Der Test ist fehlgeschlagen: $e';
    } finally {
      ai.usageListener = before;
      watch.stop();
    }

    final info = modelInfo?.call(ai.model);
    double? cost;
    var estimated = false;
    var promptTokens = 0;
    var completionTokens = 0;
    for (final raw in usages) {
      final usage = raw.withEstimate(info?.promptPricePerMillion, info?.completionPricePerMillion);
      promptTokens += usage.promptTokens;
      completionTokens += usage.completionTokens;
      if (usage.cost != null) {
        cost = (cost ?? 0) + usage.cost!;
        estimated = estimated || usage.estimated;
      }
    }
    return ModelTestResult(
      id: id,
      kind: kind,
      modelId: ai.model,
      createdAt: started,
      inputLabel: input.label,
      inputKey: input.key,
      duration: watch.elapsed,
      cost: cost,
      costEstimated: estimated,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      calls: usages.length,
      output: output,
      error: error,
    );
  }

  static String _capped(String text) =>
      text.length <= ModelTestInput.maxChars ? text : text.substring(0, ModelTestInput.maxChars);

  static Future<Map<String, dynamic>> _call(
    ModelTestKind kind,
    AiService ai,
    ModelTestInput input, {
    Map<String, dynamic>? generated,
    required bool staged,
    String plan = '',
    bool? mechBlocks,
    int repairRounds = 0,
  }) async {
    switch (kind) {
      case ModelTestKind.questions:
        return ai.generateConceptsAndFlashcards(
          slidesText: _capped(input.text),
          exercisesText: '',
          granularity: ChunkGranularity.off,
        );
      case ModelTestKind.lesson:
        final lessons = await ai.generateVisualLessons(material: _capped(input.text), maxLessons: 1, staged: staged);
        if (lessons.isEmpty) throw AiServiceException('Das Modell hat keine Lektion geliefert.');
        return {'lesson': lessons.first};
      case ModelTestKind.explain:
        final text = await ai.explainAnswer(
          question: input.text,
          correctAnswer: input.answer.trim().isEmpty
              ? '(nicht vorgegeben – leite sie kurz her und erkläre sie)'
              : input.answer.trim(),
        );
        if (text.isEmpty) throw AiServiceException('Das Modell hat nichts geantwortet.');
        return {'text': text};
      case ModelTestKind.vision:
        final pdf = input.pdfBytes;
        if (pdf == null) throw AiServiceException('Für diesen Test braucht es eine PDF-Seite.');
        final pages = await ai.transcribePdfPages(pdf, pageCount: input.pageCount);
        if (pages.every((p) => p.trim().isEmpty)) throw AiServiceException('Das Modell hat keinen Text erkannt.');
        return {'pages': pages};
      case ModelTestKind.crosscheck:
        if (generated == null) throw AiServiceException('Es gibt keine Fragen, die geprüft werden könnten.');
        final check = await ai.crosscheckConceptsAndFlashcards(
          slidesText: _capped(input.text),
          exercisesText: '',
          generated: generated,
        );
        return {'generated': generated, 'check': check};
      case ModelTestKind.scene3d:
        final wish = input.text.trim();
        final description = plan.trim().isEmpty ? wish : plan.trim();
        final title = wish.length > 60 ? '${wish.substring(0, 60)}…' : wish;
        if (mechBlocks != null) ai.mechBlocks = mechBlocks;
        final drawn = await ai.drawVisualScene(
          lesson: {
            'title': title,
            'steps': [
              {
                'title': title,
                'text': description,
                'show': {'idea': description, 'kind': '3d'},
              },
            ],
          },
          stepIndex: 0,
        );
        final show = drawn['show'] is Map ? drawn['show'] as Map : drawn;
        if (show['scene3d'] is! Map) {
          throw AiServiceException('Das Modell hat eine flache Zeichnung statt eines 3D-Modells geliefert.');
        }
        final scene = Map<String, dynamic>.from(show['scene3d'] as Map);
        // Die App prüft das Modell – und lässt es auf Wunsch nachbessern.
        if (repairRounds > 0) {
          final result = await Scene3DRepair.run(ai: ai, scene: scene, wish: description, maxRounds: repairRounds);
          return {
            'scene3d': result.scene,
            'issues': result.after,
            'issuesBefore': result.before.length,
            'repairs': result.rounds,
            if (result.improved) 'original': scene,
          };
        }
        final parsed = VisualScene3D.fromMap(scene);
        return {'scene3d': scene, 'issues': parsed == null ? const <String>[] : Scene3DCheck.issues(parsed, max: 50)};
    }
  }

  /// Die Fragen eines „Fragen erstellen“- oder Gegenprüf-Ergebnisses.
  static List<Map<String, dynamic>> flashcardsOf(Map<String, dynamic> output) => [
    if (output['flashcards'] is List)
      for (final f in output['flashcards'] as List)
        if (f is Map) Map<String, dynamic>.from(f),
  ];

  static List<Map<String, dynamic>> conceptsOf(Map<String, dynamic> output) => [
    if (output['concepts'] is List)
      for (final c in output['concepts'] as List)
        if (c is Map) Map<String, dynamic>.from(c),
  ];

  /// Was der Gegenprüfer beanstandet hat.
  static List<Map<String, dynamic>> issuesOf(Map<String, dynamic> output) {
    final check = output['check'];
    return [
      if (check is Map && check['issues'] is List)
        for (final i in check['issues'] as List)
          if (i is Map) Map<String, dynamic>.from(i),
    ];
  }
}
