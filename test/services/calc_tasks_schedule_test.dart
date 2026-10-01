import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/services/daily_scheduler_service.dart';
import 'package:lernen/services/question_parsing.dart';
import 'package:lernen/services/sync_service.dart';

Module _module(String id) =>
    Module(id: id, name: id, colorValue: 0xFF000000, icon: '📘', examDate: null, createdAt: DateTime(2026, 1, 1));

Flashcard _card(String id, {bool calc = false, int reps = 0, DateTime? due, DateTime? deferred, DateTime? created}) =>
    Flashcard(
      id: id,
      moduleId: 'm',
      front: 'Frage $id',
      back: 'Antwort',
      createdAt: created ?? DateTime(2026, 1, 1),
      due: due ?? DateTime(2026, 1, 1),
      reps: reps,
      stability: reps > 0 ? 5 : 0,
      lastReview: reps > 0 ? DateTime(2026, 5, 20) : null,
      needsCalculator: calc,
      calcDeferredAt: deferred,
    );

void main() {
  final scheduler = DailySchedulerService();
  final now = DateTime(2026, 6, 1, 9);

  group('Tagesplan mit Schalter "Rechenaufgaben"', () {
    test('aus: keine Rechenaufgaben, die zurückgestellten werden genannt', () {
      final cards = [
        _card('wissen-neu'),
        _card('rechnen-neu', calc: true),
        _card('wissen-fällig', reps: 3, due: DateTime(2026, 5, 30)),
        _card('rechnen-fällig', calc: true, reps: 3, due: DateTime(2026, 5, 31)),
      ];
      final plan = scheduler.buildPlan(modules: [_module('m')], allCards: cards, now: now, includeCalcTasks: false);
      expect(plan.allCards.map((c) => c.id), unorderedEquals(['wissen-neu', 'wissen-fällig']));
      expect(plan.deferredCalc.map((c) => c.id), unorderedEquals(['rechnen-neu', 'rechnen-fällig']));
    });

    test('an: alles dabei, nichts zurückgestellt', () {
      final cards = [_card('a'), _card('b', calc: true)];
      final plan = scheduler.buildPlan(modules: [_module('m')], allCards: cards, now: now);
      expect(plan.allCards.map((c) => c.id), unorderedEquals(['a', 'b']));
      expect(plan.deferredCalc, isEmpty);
      expect(plan.calcCatchUp, 0);
    });

    test('an nach Zurückstellen: aufgehobene Rechenaufgaben zuerst und ZUSÄTZLICH zum Budget', () {
      // 30 neue Wissenskarten (älter) und 6 aufgehobene Rechenaufgaben (neuer).
      final cards = [
        for (var i = 0; i < 30; i++) _card('w$i', created: DateTime(2026, 1, 1, 0, i)),
        for (var i = 0; i < 6; i++)
          _card('r$i', calc: true, created: DateTime(2026, 3, 1, 0, i), deferred: DateTime(2026, 5, 28 + (i % 3))),
      ];
      final without = scheduler.buildPlan(
        modules: [_module('m')],
        allCards: [for (final c in cards) c.copyWithCalcDeferred(null)],
        now: now,
      );
      final plan = scheduler.buildPlan(modules: [_module('m')], allCards: cards, now: now);
      final newIds = plan.newCards.map((c) => c.id).toList();
      expect(newIds.where((id) => id.startsWith('r')), hasLength(6)); // alle sechs dabei
      expect(plan.calcCatchUp, 6);
      expect(plan.newCards.length, without.newCards.length + 6); // zusätzlich, nicht statt
      // Ohne Markierung kämen die (neueren) Rechenaufgaben gar nicht dran.
      expect(without.newCards.where((c) => c.id.startsWith('r')), isEmpty);
    });

    test('Nachholen ist je Fach begrenzt', () {
      final cards = [
        for (var i = 0; i < 40; i++) _card('r$i', calc: true, deferred: DateTime(2026, 5, 1)),
      ];
      final plan = scheduler.buildPlan(modules: [_module('m')], allCards: cards, now: now);
      expect(plan.calcCatchUp, DailySchedulerService.maxCalcCatchUpPerModule);
    });

    test('freiwillig weiterlernen: Schalter gilt auch dort, aufgehobene zuerst', () {
      final cards = [
        _card('w', created: DateTime(2026, 1, 1)),
        _card('r', calc: true, created: DateTime(2026, 2, 1), deferred: DateTime(2026, 5, 1)),
      ];
      final off = scheduler.buildExtraBatch(
        modules: [_module('m')],
        allCards: cards,
        excludeIds: const {},
        includeCalcTasks: false,
      );
      expect(off.allCards.map((c) => c.id), ['w']);
      final on = scheduler.buildExtraBatch(modules: [_module('m')], allCards: cards, excludeIds: const {});
      expect(on.newCards.first.id, 'r');
    });
  });

  group('Kartenfelder', () {
    test('needsCalculator und calcDeferredAt überleben toMap/fromMap; ältere Karten ohne die Felder', () {
      final card = _card('x', calc: true, deferred: DateTime(2026, 5, 2));
      final back = Flashcard.fromMap(card.toMap());
      expect(back.needsCalculator, isTrue);
      expect(back.calcDeferredAt, DateTime(2026, 5, 2));
      final old = Flashcard.fromMap(card.toMap()..remove('needsCalculator')..remove('calcDeferredAt'));
      expect(old.needsCalculator, isNull);
      expect(old.calcDeferredAt, isNull);
    });

    test('beim Beantworten wird die Zurückstellung gelöscht, die Markierung bleibt', () {
      final card = _card('x', calc: true, deferred: DateTime(2026, 5, 2));
      final reviewed = card.copyWithReview(
        stability: 3,
        difficulty: 5,
        elapsedDays: 0,
        scheduledDays: 1,
        reps: 1,
        lapses: 0,
        state: 'learning',
        lastReview: now,
        due: now.add(const Duration(days: 1)),
      );
      expect(reviewed.calcDeferredAt, isNull);
      expect(reviewed.needsCalculator, isTrue);
      expect(card.copyWithCalculator(null).needsCalculator, isNull);
      expect(card.copyWithText(front: 'neu', back: 'b').calcDeferredAt, DateTime(2026, 5, 2));
    });
  });

  group('KI-Markierung einlesen', () {
    test('"calc" in verschiedenen Schreibweisen', () {
      expect(QuestionParsing.parseCalcFlag({'calc': true}), isTrue);
      expect(QuestionParsing.parseCalcFlag({'calc': 'false'}), isFalse);
      expect(QuestionParsing.parseCalcFlag({'needsCalculator': 'ja'}), isTrue);
      expect(QuestionParsing.parseCalcFlag({'front': 'x'}), isNull);
    });

    test('bleibt beim Normalisieren erhalten, auch wenn auf eine Karteikarte zurückgefallen wird', () {
      final complete = QuestionParsing.normalizeGeneratedFlashcard(
          {'type': 'free_text', 'front': 'Berechne', 'correctText': '5 V', 'calc': true})!;
      expect(QuestionParsing.parseCalcFlag(complete), isTrue);
      final fallback = QuestionParsing.normalizeGeneratedFlashcard(
          {'type': 'single_choice', 'front': 'Berechne', 'back': '5 V', 'calc': true})!;
      expect(fallback['type'], 'flashcard');
      expect(QuestionParsing.parseCalcFlag(fallback), isTrue);
    });
  });

  group('Einstellungen', () {
    test('Hilfe-Modell: ohne Wahl wie das Fragen-Modell; Rechenaufgaben-Schalter bleibt auf dem Gerät', () {
      const settings = AppSettings(questionModelId: 'q/model');
      expect(settings.effectiveHelpModelId, 'q/model');
      expect(settings.includeCalcTasks, isTrue);
      final chosen = settings.copyWith(helpModelId: 'h/model', includeCalcTasks: false);
      expect(chosen.effectiveHelpModelId, 'h/model');
      final back = AppSettings.fromMap(chosen.toMap());
      expect(back.helpModelId, 'h/model');
      expect(back.includeCalcTasks, isFalse);
      expect(chosen.copyWith(clearHelpModel: true).effectiveHelpModelId, 'q/model');

      final synced = syncedSettingsOf(chosen, includeSecrets: false);
      expect(synced['helpModelId'], 'h/model');
      expect(synced.containsKey('includeCalcTasks'), isFalse); // geräte-lokal
    });

    test('Hilfe-Modell im Sync: übernommen, "" setzt zurück, fehlendes Feld lässt es stehen', () {
      const local = AppSettings(helpModelId: 'lokal/model');
      expect(mergeAiSettings(local, {'helpModelId': 'cloud/model'}).helpModelId, 'cloud/model');
      expect(mergeAiSettings(local, {'helpModelId': ''}).helpModelId, isNull);
      expect(mergeAiSettings(local, {'questionModelId': 'x/y'}).helpModelId, 'lokal/model');
    });
  });
}
