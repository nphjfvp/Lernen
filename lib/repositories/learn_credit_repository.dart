import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/flashcard.dart';
import '../models/learn_credit.dart';
import '../models/visual_task_type.dart';
import '../services/database_service.dart';
import '../services/fsrs_service.dart';

/// Lernguthaben für die Lernzeit-Sperre (siehe [LearnCredit]): im Store
/// `settings` unter `learn_credit`, die Regeln unter `learn_credit_rules` –
/// beides reist mit dem Cloud-Abgleich.
class LearnCreditRepository {
  static const creditKey = 'learn_credit';
  static const rulesKey = 'learn_credit_rules';

  /// Meldet Änderungen (für Anzeigen, die das Guthaben zeigen).
  static final changes = ValueNotifier<int>(0);

  static Future<LearnCredit> loadFrom(DatabaseClient db) async =>
      LearnCredit.fromMap(await DatabaseService.settings.record(creditKey).get(db));

  static Future<void> saveIn(DatabaseClient db, LearnCredit credit) =>
      DatabaseService.settings.record(creditKey).put(db, credit.toMap());

  static Future<LearnCreditRules> loadRulesFrom(DatabaseClient db) async =>
      LearnCreditRules.fromMap(await DatabaseService.settings.record(rulesKey).get(db));

  static Future<void> saveRulesIn(DatabaseClient db, LearnCreditRules rules) =>
      DatabaseService.settings.record(rulesKey).put(db, rules.toMap());

  /// Das Thema einer Karte: ihr Konzept, sonst ihr erkannter Aufgabentyp,
  /// sonst ihre Vorlesungs-Einheit. null = die Karte zählt keinem Thema zu.
  static Future<({String key, String title})?> topicOf(DatabaseClient db, Flashcard card) async {
    final conceptId = card.conceptId;
    if (conceptId != null && conceptId.isNotEmpty) {
      final concept = await DatabaseService.concepts.record(conceptId).get(db);
      final title = '${concept?['title'] ?? ''}'.trim();
      return (key: 'concept:$conceptId', title: title.isEmpty ? 'Konzept' : title);
    }
    final catalog = VisualTaskCatalog.fromMap(await DatabaseService.visualTaskTypes.record(card.moduleId).get(db));
    for (final t in catalog?.types ?? const <VisualTaskType>[]) {
      if (t.cardIds.contains(card.id)) return (key: 'type:${card.moduleId}:${t.title}', title: t.title);
    }
    final unitId = card.unitId;
    if (unitId != null && unitId.isNotEmpty) {
      final unit = await DatabaseService.lectureUnits.record(unitId).get(db);
      final title = '${unit?['title'] ?? ''}'.trim();
      return (key: 'unit:$unitId', title: title.isEmpty ? 'Einheit' : title);
    }
    return null;
  }

  /// Eine Antwort verbuchen; liefert den Titel eines dadurch neu gelernten
  /// Themas (sonst null).
  static Future<String?> recordAnswerIn(
    DatabaseClient db,
    Flashcard card, {
    Grade? selfGrade,
    bool? isCorrect,
    DateTime? now,
  }) async {
    final topic = await topicOf(db, card);
    if (topic == null) return null;
    final rules = await loadRulesFrom(db);
    final credit = await loadFrom(db);
    final (updated, learned) = credit.withAnswer(
      topic: topic.key,
      title: topic.title,
      clean: LearnCredit.isClean(selfGrade: selfGrade, isCorrect: isCorrect),
      now: now ?? DateTime.now(),
      rules: rules,
    );
    await saveIn(db, updated);
    changes.value++;
    return learned;
  }

  static Future<String?> recordAnswer(Flashcard card, {Grade? selfGrade, bool? isCorrect}) async {
    final db = await DatabaseService.instance.database;
    return recordAnswerIn(db, card, selfGrade: selfGrade, isCorrect: isCorrect);
  }

  /// Das Daily Quiz ist für den heutigen Lerntag fertig.
  static Future<void> markDailyDoneIn(DatabaseClient db, {DateTime? now}) async {
    final rules = await loadRulesFrom(db);
    final credit = await loadFrom(db);
    final when = now ?? DateTime.now();
    if (credit.dailyDays.contains(LearnCredit.dayKey(when, rules.dayStartHour))) return;
    await saveIn(db, credit.withDailyDone(when, rules.dayStartHour));
    changes.value++;
  }

  static Future<void> markDailyDone() async => markDailyDoneIn(await DatabaseService.instance.database);

  /// Cloud-Abgleich: den Stand eines anderen Geräts einmischen.
  static Future<void> mergeIn(DatabaseClient db, Object? remote) async {
    if (remote is! Map) return;
    final local = await loadFrom(db);
    await saveIn(db, local.mergedWith(LearnCredit.fromMap(remote)));
    changes.value++;
  }

  /// Cloud-Abgleich: Regeln eines anderen Geräts übernehmen, wenn sie später
  /// geändert wurden als die eigenen.
  static Future<void> mergeRulesIn(DatabaseClient db, Object? remote) async {
    if (remote is! Map) return;
    final theirs = LearnCreditRules.fromMap(remote);
    final at = theirs.updatedAt;
    if (at == null) return;
    final mine = (await loadRulesFrom(db)).updatedAt;
    if (mine != null && !at.isAfter(mine)) return;
    await saveRulesIn(db, theirs);
    changes.value++;
  }

  static Future<Map<String, dynamic>> syncMapFrom(DatabaseClient db) async => (await loadFrom(db)).toSyncMap();
}
