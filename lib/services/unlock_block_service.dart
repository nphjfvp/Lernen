import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/learn_credit.dart';
import '../models/unlock_block.dart';
import '../repositories/learn_credit_repository.dart';
import '../repositories/unlock_block_repository.dart';
import 'ai_service.dart';
import 'database_service.dart';
import 'unlock_task_card.dart';

/// Bereitet Entsperr-Blöcke vor und passt sie an: nach neuem Material (beim
/// Hochladen) und nach Fehlern beim Üben – je Fach höchstens [maxOpen] offene
/// Blöcke, angefangene bleiben, unberührte werden ersetzt, wenn sie nicht mehr
/// passen. Läuft nur, wenn die Lernzeit-Sperre an ist (oder auf Wunsch).
class UnlockBlockService {
  UnlockBlockService._();

  static final instance = UnlockBlockService._();

  /// KI mit den Einstellungen der App (setzt main.dart); null = kein Key.
  static AiService? Function()? aiFactory;

  /// Test-Hooks.
  @visibleForTesting
  static Future<DatabaseClient> Function()? openDatabase;

  static const maxOpen = 3;
  static const minInterval = Duration(minutes: 20);

  final _timers = <String, Timer>{};
  final _last = <String, DateTime>{};

  /// Fächer, die gerade angepasst werden.
  final running = ValueNotifier<Set<String>>(const {});

  Future<DatabaseClient> _db() => (openDatabase ?? () => DatabaseService.instance.database)();

  UnlockBlockRepository get _repo => UnlockBlockRepository(openDatabase: _db);

  /// Nach neuem Material oder Fehlern beim Üben: bald anpassen.
  void markDirty(String moduleId, {Duration delay = const Duration(minutes: 1)}) {
    if (aiFactory == null || moduleId.isEmpty) return;
    _timers[moduleId]?.cancel();
    _timers[moduleId] = Timer(delay, () {
      _timers.remove(moduleId);
      unawaited(refresh(moduleId).catchError((_) => 0));
    });
  }

  @visibleForTesting
  void reset() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _last.clear();
    running.value = const {};
  }

  /// Blöcke eines Fachs anpassen; liefert die Zahl neuer Blöcke. [force]:
  /// auch ohne eingeschaltete Sperre und vor Ablauf von [minInterval].
  Future<int> refresh(String moduleId, {bool force = false, DateTime? now}) async {
    if (running.value.contains(moduleId)) return 0;
    final when = now ?? DateTime.now();
    final last = _last[moduleId];
    if (!force && last != null && when.difference(last) < minInterval) return 0;
    final ai = aiFactory?.call();
    if (ai == null) return 0;
    final db = await _db();
    final rules = await LearnCreditRepository.loadRulesFrom(db);
    if (!force && !rules.enabled) return 0;
    running.value = {...running.value, moduleId};
    try {
      final blocks = await _repo.forModule(moduleId);
      final open = [
        for (final b in blocks)
          if (!b.solved) b,
      ];
      final untouched = [
        for (final b in open)
          if (b.untouched) b,
      ];
      final inProgress = open.length - untouched.length;
      final room = maxOpen - inProgress;
      if (room <= 0) return 0;

      final module = await DatabaseService.modules.record(moduleId).get(db);
      final concepts = await DatabaseService.concepts.find(
        db,
        finder: Finder(filter: Filter.equals('moduleId', moduleId)),
      );
      final credit = await LearnCreditRepository.loadFrom(db);
      final learnedIds = {
        for (final k in credit.earned.keys)
          if (k.startsWith('concept:')) k.substring('concept:'.length),
      };
      final cards = await DatabaseService.flashcards.find(
        db,
        finder: Finder(filter: Filter.equals('moduleId', moduleId)),
      );
      final mistakes = [
        for (final c in cards)
          if (c.value['lapses'] case final num lapses when lapses > 0)
            (question: '${c.value['front'] ?? ''}', answer: '${c.value['back'] ?? ''}', lapses: lapses.toInt()),
      ]..sort((a, b) => b.lapses.compareTo(a.lapses));
      final materials = await DatabaseService.materials.find(
        db,
        finder: Finder(filter: Filter.equals('moduleId', moduleId), sortOrders: [SortOrder('createdAt', false)]),
      );
      final sources = [
        for (final m in materials)
          if ('${m.value['extractedText'] ?? ''}'.trim().isNotEmpty)
            (
              name: '${m.value['fileName'] ?? ''}',
              kind: switch ('${m.value['kind'] ?? ''}') {
                'exercise' => 'Übungsblatt',
                'practiceExam' => 'Übungsklausur',
                _ => 'Vorlesung',
              },
              text: '${m.value['extractedText']}',
            ),
      ]..sort((a, b) => (a.kind == 'Vorlesung' ? 1 : 0).compareTo(b.kind == 'Vorlesung' ? 1 : 0));
      if (sources.isEmpty && concepts.isEmpty && mistakes.isEmpty) return 0;

      final plan = await ai.planUnlockBlocks(
        moduleId: moduleId,
        moduleName: '${module?['name'] ?? 'Fach'}',
        notLearned: [
          for (final c in concepts)
            if (!learnedIds.contains(c.key)) '${c.value['title'] ?? ''}',
        ],
        learned: [
          for (final c in concepts)
            if (learnedIds.contains(c.key)) '${c.value['title'] ?? ''}',
        ],
        mistakes: mistakes,
        materials: sources.take(6).toList(),
        open: untouched,
        maxNew: room,
        now: when,
      );
      _last[moduleId] = when;
      final keep = {
        for (final b in untouched)
          if (plan.keep.contains(b.id)) b.id,
      };
      for (final b in untouched) {
        if (!keep.contains(b.id)) await _repo.delete(b.id);
      }
      final added = plan.blocks.take(room - keep.length).toList();
      for (final b in added) {
        await _repo.save(b);
      }
      // Gleich lösbar machen: Mathe als Rechenweg (Stift, Schritte, Tafel).
      for (final b in added) {
        await prepareCards(b, ai);
      }
      return added.length;
    } finally {
      running.value = {...running.value}..remove(moduleId);
    }
  }

  /// Zu jeder Aufgabe ohne Karte die lösbare Karte bauen (siehe
  /// buildUnlockCard) – Fehler lassen die Aufgabe ohne Karte (dann beim Lösen).
  Future<UnlockBlock> prepareCards(UnlockBlock block, AiService ai) async {
    var current = block;
    for (var i = 0; i < current.tasks.length; i++) {
      if (current.tasks[i].card != null) continue;
      try {
        final card = await buildUnlockCard(ai, current, i);
        current = current.withTask(i, current.tasks[i].withCard(card.toMap()));
        await _repo.save(current);
      } catch (_) {
        // Später beim Lösen noch einmal.
      }
    }
    return current;
  }

  /// Alle Fächer anpassen (z.B. beim Öffnen der Übersicht).
  Future<int> refreshAll({bool force = false}) async {
    final db = await _db();
    final modules = await DatabaseService.modules.findKeys(db);
    var added = 0;
    for (final id in modules) {
      try {
        added += await refresh(id, force: force);
      } catch (_) {
        // Ein Fach ohne Erfolg hält die anderen nicht auf.
      }
    }
    return added;
  }

  /// Fachnamen (für Anzeigen).
  Future<Map<String, String>> moduleNames() async {
    final records = await DatabaseService.modules.find(await _db());
    return {for (final r in records) r.key: '${r.value['name'] ?? ''}'};
  }

  /// Die Regeln, die gerade gelten (für Anzeigen).
  Future<LearnCreditRules> rules() async => LearnCreditRepository.loadRulesFrom(await _db());
}
