import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/chat_message.dart';
import 'package:lernen/models/daily_session_state.dart';
import 'package:lernen/models/mastery_snapshot.dart';
import 'package:lernen/repositories/daily_session_repository.dart';
import 'package:lernen/repositories/mock_exam_repository.dart';
import 'package:lernen/repositories/study_log_repository.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/mock_exam_service.dart';
import 'package:lernen/services/sync_service.dart';
import 'package:sembast/sembast_memory.dart';

ChatMessage _message(String id, String content) => ChatMessage(
      id: id,
      moduleId: 'm1',
      role: ChatRole.user,
      content: content,
      createdAt: DateTime(2026, 9, 20),
    );

MockExamResult _exam(DateTime takenAt, int correct) =>
    MockExamResult(moduleId: 'm1', takenAt: takenAt, correct: correct, total: 10, durationSeconds: 600);

void main() {
  late Database db;

  setUp(() async {
    db = await databaseFactoryMemory.openDatabase('sync_history_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() => db.close());

  test('Frage-Chats und Probeklausuren werden durch den Cloud-Stand ersetzt', () async {
    await DatabaseService.chatMessages.record('lokal').put(db, _message('lokal', 'alt').toMap());
    await MockExamRepository.addIn(db, _exam(DateTime(2026, 9, 1), 3));

    await db.transaction((txn) => applySyncedHistory(txn, {
          'chatMessages': [_message('cloud', 'vom Handy').toMap()],
          'mockExamResults': [
            _exam(DateTime(2026, 9, 10), 6).toMap(),
            _exam(DateTime(2026, 9, 20), 8).toMap(),
          ],
        }));

    final chats = await DatabaseService.chatMessages.find(db);
    expect(chats.map((r) => r.key), ['cloud']);
    final exams = await MockExamRepository.loadFrom(db);
    expect(exams.map((e) => e.correct), [8, 6]); // neueste zuerst
  });

  test('Lerntage und Ampel-Trend werden zusammengeführt – der Streak wird nie kürzer', () async {
    await StudyLogRepository.recordDayIn(db, DateTime(2026, 9, 25));
    final local = MasterySnapshot(date: DateTime(2026, 9, 25), red: 1, yellow: 1, green: 1, neu: 1);
    await DatabaseService.masterySnapshots.record(local.dateKey).put(db, local.toMap());

    final cloud = MasterySnapshot(date: DateTime(2026, 9, 26), red: 0, yellow: 2, green: 5, neu: 0);
    await db.transaction((txn) => applySyncedHistory(txn, {
          'studyDays': ['2026-09-26', 'kaputt'],
          'masterySnapshots': [cloud.toMap()],
        }));

    expect(await StudyLogRepository.dayKeysFrom(db), ['2026-09-25', '2026-09-26']);
    final snapshots = await DatabaseService.masterySnapshots.find(db);
    expect(snapshots.map((r) => r.key), containsAll(['2026-09-25', '2026-09-26']));
  });

  test('Cloud-Stand einer älteren App-Version (ohne diese Felder) lässt alles lokal stehen', () async {
    await DatabaseService.chatMessages.record('lokal').put(db, _message('lokal', 'bleibt').toMap());
    await MockExamRepository.addIn(db, _exam(DateTime(2026, 9, 1), 3));
    await StudyLogRepository.recordDayIn(db, DateTime(2026, 9, 25));

    await db.transaction((txn) => applySyncedHistory(txn, {'modules': []}));

    expect((await DatabaseService.chatMessages.find(db)).length, 1);
    expect((await MockExamRepository.loadFrom(db)).length, 1);
    expect(await StudyLogRepository.dayKeysFrom(db), ['2026-09-25']);
  });

  test('heute auf einem anderen Gerät eingeführte Karten zählen auch hier gegen das Tagesbudget', () async {
    final now = DateTime.now();
    await DailySessionRepository.saveIn(
      db,
      DailySessionState.empty(now).copyWith(introducedIds: {'a'}, reviewedCount: 3),
    );
    final cloud = DailySessionState.empty(now).copyWith(introducedIds: {'b', 'c'}, reviewedCount: 7);
    await db.transaction((txn) => applySyncedHistory(txn, {'dailySession': cloud.toMap()}));

    final merged = await DailySessionRepository.loadFrom(db, now);
    expect(merged.introducedIds, {'a', 'b', 'c'});
    expect(merged.reviewedCount, 7);
  });

  test('ein Daily-Stand von einem anderen Tag wird ignoriert', () async {
    final now = DateTime.now();
    await DailySessionRepository.saveIn(db, DailySessionState.empty(now).copyWith(introducedIds: {'a'}));
    final yesterday = DailySessionState(day: DateTime(now.year, now.month, now.day - 1), introducedIds: const {'x'});
    await db.transaction((txn) => applySyncedHistory(txn, {'dailySession': yesterday.toMap()}));

    expect((await DailySessionRepository.loadFrom(db, now)).introducedIds, {'a'});
  });
}
