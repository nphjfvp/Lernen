import 'package:sembast/sembast.dart';

import '../services/database_service.dart';

/// Kalendertage, an denen tatsächlich Karten wiederholt wurden – Grundlage
/// für den Streak (siehe StatsService). `Flashcard.lastReview` allein reicht
/// dafür nicht, weil es nur die LETZTE Wiederholung je Karte kennt.
/// Geräte-lokal (wie die Ampel-Schnappschüsse), nicht Teil des Cloud-Syncs.
class StudyLogRepository {
  static const _recordKey = 'study_days';

  /// Begrenzt die Liste, damit der Datensatz nicht unbegrenzt wächst – für
  /// einen Streak reicht über ein Jahr Rückblick mehr als aus.
  static const _maxDays = 400;

  static DateTime? _lastRecordedDay;

  Future<void> recordDay(DateTime when) async {
    final day = DateTime(when.year, when.month, when.day);
    if (_lastRecordedDay == day) return;
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) => recordDayIn(txn, day));
    _lastRecordedDay = day;
  }

  Future<Set<DateTime>> loadDays() async {
    final db = await DatabaseService.instance.database;
    return loadDaysFrom(db);
  }

  static Future<void> recordDayIn(DatabaseClient client, DateTime day) async {
    final key = _dayKey(day);
    final days = (await _readKeys(client)).toSet()..add(key);
    final sorted = days.toList()..sort();
    final kept = sorted.length > _maxDays ? sorted.sublist(sorted.length - _maxDays) : sorted;
    await DatabaseService.settings.record(_recordKey).put(client, {'days': kept});
  }

  static Future<Set<DateTime>> loadDaysFrom(DatabaseClient client) async {
    final keys = await _readKeys(client);
    return {for (final k in keys) if (DateTime.tryParse(k) != null) DateTime.parse(k)};
  }

  static Future<List<String>> _readKeys(DatabaseClient client) async {
    final record = await DatabaseService.settings.record(_recordKey).get(client);
    return (record?['days'] as List?)?.map((e) => e.toString()).toList() ?? [];
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
