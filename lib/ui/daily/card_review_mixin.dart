import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/study_log_repository.dart';
import '../../services/ai_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/review_service.dart';

/// Gemeinsame Antwort-Verbuchung für alle Lernmodi (Daily Quiz, Üben,
/// Sprint): wendet [ReviewService.evaluate] an, speichert, protokolliert
/// den Lerntag, zeigt Feedback bei Stufenwechseln und erzeugt eine fällige
/// nächste Stufe im Hintergrund per KI.
mixin CardReviewMixin<T extends StatefulWidget> on State<T> {
  final ReviewService _reviewService = ReviewService();

  /// [showLevelFeedback] false unterdrückt die Stufenwechsel-SnackBar (z.B.
  /// in der Probeklausur, die kein Feedback während der Bearbeitung zeigt).
  Future<ReviewOutcome> recordReview(
    Flashcard card, {
    Grade? selfGrade,
    bool? isCorrect,
    bool showLevelFeedback = true,
  }) async {
    final outcome = _reviewService.evaluate(card, selfGrade: selfGrade, isCorrect: isCorrect);
    // Vor dem ersten await auslesen: die Hintergrund-Beförderung soll auch
    // dann noch gespeichert werden, wenn der Screen inzwischen geschlossen
    // wurde.
    final repo = context.read<FlashcardRepository>();
    final settings = context.read<SettingsRepository>().settings;
    await repo.update(outcome.card);
    unawaited(StudyLogRepository().recordDay(DateTime.now()));

    final target = outcome.targetType;
    if (outcome.needsGeneration && target != null && settings.hasApiKey) {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      unawaited(_promoteInBackground(repo, ai, outcome.card, target));
    }
    final message = outcome.levelChangeMessage;
    if (message != null && showLevelFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
    return outcome;
  }

  /// Schlägt die KI-Erzeugung fehl (offline, kein Guthaben …), bleibt die
  /// Karte einfach auf ihrer aktuellen Stufe – der nächste richtige Versuch
  /// probiert die Beförderung erneut.
  Future<void> _promoteInBackground(
    FlashcardRepository repo,
    AiService ai,
    Flashcard card,
    QuestionType nextType,
  ) async {
    try {
      final content = await ReviewService.fetchPromotionContent(ai, card, nextType);
      // Der KI-Aufruf dauert Sekunden – in der Zeit kann dieselbe Karte
      // woanders erneut beantwortet worden sein. Deshalb auf den AKTUELLEN
      // Stand anwenden, nicht auf den alten Schnappschuss, und nur, wenn sie
      // noch auf derselben Stufe steht.
      final current = await repo.loadById(card.id);
      if (current == null || current.variantLevel != card.variantLevel || current.type != card.type) return;
      await repo.update(ReviewService.applyPromotion(current, nextType, content));
    } catch (_) {
      // Bewusst still, siehe Doc-Kommentar.
    }
  }
}
