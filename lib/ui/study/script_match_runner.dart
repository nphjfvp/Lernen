import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../models/material_item.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/script_match_service.dart';
import '../../services/source_locator.dart';

/// Was für einen Abgleich mit dem Skript nötig ist – aus den App-Repositories
/// gelesen, bevor irgendetwas awaited wird (der Abgleich läuft auch weiter,
/// wenn der Screen inzwischen geschlossen ist).
class ScriptMatchContext {
  ScriptMatchContext._({
    required this.flashcards,
    required this.materials,
    required this.apiKey,
    required this.model,
    required this.messenger,
  });

  /// Nur für Tests: baut den KI-Zugang (sonst der echte [AiService]).
  static AiService Function(String apiKey, String model)? aiFactory;

  final FlashcardRepository flashcards;
  final MaterialRepository materials;
  final String apiKey;
  final String model;
  final ScaffoldMessengerState? messenger;

  /// `null`, wenn ein Abgleich nicht möglich ist (kein API-Key oder keine
  /// Material-Verwaltung).
  static ScriptMatchContext? of(BuildContext context) {
    final flashcards = context.read<FlashcardRepository?>();
    final materials = context.read<MaterialRepository?>();
    final settings = context.read<SettingsRepository?>()?.settings;
    if (flashcards == null || materials == null || settings == null || !settings.hasApiKey) return null;
    return ScriptMatchContext._(
      flashcards: flashcards,
      materials: materials,
      apiKey: settings.openRouterApiKey!,
      model: settings.questionModelId,
      messenger: ScaffoldMessenger.maybeOf(context),
    );
  }

  /// Materialien des Fachs (aktuell geladen).
  Future<List<MaterialItem>> materialsOf(String moduleId) async {
    await materials.loadForModule(moduleId);
    return materials.forModule(moduleId);
  }

  /// Gleicht [cards] eines Fachs ab und speichert die Fundstellen. `null`,
  /// wenn es nichts zu tun gab (keine Folien-PDF auf diesem Gerät).
  Future<ScriptMatchRun?> run(
    String moduleId,
    List<Flashcard> cards, {
    void Function(int done, int total)? onProgress,
  }) async {
    final mats = await materialsOf(moduleId);
    if (SourceLocator.scriptPdfs(mats).isEmpty || cards.isEmpty) return null;
    final result = await ScriptMatchService().match(
      cards,
      materials: mats,
      ai: aiFactory?.call(apiKey, model) ?? AiService(apiKey: apiKey, model: model),
      onProgress: onProgress,
    );
    await flashcards.updateScriptLocations({
      for (final m in result.matches) m.cardId: (materialId: m.materialId, page: m.page),
    });
    return result;
  }

  static String summary(ScriptMatchRun run, int total) {
    final parts = <String>[
      run.found == 0
          ? 'Keine Erklärung im Skript gefunden – „Im Skript“ zeigt weiter das Übungsblatt.'
          : '${run.found} von $total Fragen im Skript verortet – „Im Skript“ öffnet jetzt die Erklärung.',
      if (run.failedCards > 0)
        '${run.failedCards} ${run.failedCards == 1 ? 'Frage ist' : 'Fragen sind'} fehlgeschlagen – '
            'über die Kartenliste erneut versuchen.',
    ];
    return parts.join(' ');
  }
}

/// Nach dem Erstellen von Fragen aus einem Übungsblatt: die Fragen im
/// Hintergrund mit dem Skript abgleichen, damit "Im Skript" die Erklärung
/// zeigt statt nur das Übungsblatt. Ohne API-Key oder ohne Folien-PDF auf
/// diesem Gerät passiert nichts (dann vermutet "Im Skript" die Stelle beim
/// Öffnen per Textabgleich). Vor dem ersten await auslesen: darf mit einem
/// inzwischen geschlossenen Screen weiterlaufen.
Future<void> matchNewCardsToScript(BuildContext context, List<Flashcard> saved) async {
  final env = ScriptMatchContext.of(context);
  if (env == null || saved.isEmpty) return;
  try {
    for (final moduleId in {for (final c in saved) c.moduleId}) {
      final mats = await env.materialsOf(moduleId);
      final cards = ScriptMatchService.candidatesFrom([for (final c in saved) if (c.moduleId == moduleId) c], mats);
      if (cards.isEmpty || SourceLocator.scriptPdfs(mats).isEmpty) continue;
      env.messenger?.showSnackBar(SnackBar(
        content: Text('Suche die Erklärungen zu ${cards.length} '
            '${cards.length == 1 ? 'Frage' : 'Fragen'} im Skript …'),
        duration: const Duration(seconds: 3),
      ));
      final result = await env.run(moduleId, cards);
      if (result != null) {
        env.messenger?.showSnackBar(SnackBar(
          content: Text(ScriptMatchContext.summary(result, cards.length)),
          duration: const Duration(seconds: 6),
        ));
      }
    }
  } catch (_) {
    // Bewusst still: der Abgleich ist ein Zusatz, "Im Skript" geht auch ohne.
  }
}
