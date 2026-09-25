import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/daily_session_state.dart';
import 'package:lernen/repositories/daily_session_repository.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('Stand vom selben Tag übersteht Speichern und Laden', () async {
    final db = await databaseFactoryMemory.openDatabase('daily_session_${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(db.close);

    final now = DateTime(2026, 9, 25, 10);
    final state = DailySessionState.empty(now).copyWith(
      reviewedCount: 7,
      introducedIds: {'a', 'b'},
      wrongIds: ['c', 'a'],
      wrongAttempts: {'c': 1},
    );
    await DailySessionRepository.saveIn(db, state);

    final loaded = await DailySessionRepository.loadFrom(db, DateTime(2026, 9, 25, 22));
    expect(loaded.reviewedCount, 7);
    expect(loaded.introducedIds, {'a', 'b'});
    expect(loaded.wrongIds, ['c', 'a']);
    expect(loaded.wrongAttempts, {'c': 1});
  });

  test('am nächsten Tag beginnt ein leerer Stand', () async {
    final db = await databaseFactoryMemory.openDatabase('daily_session_${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(db.close);

    await DailySessionRepository.saveIn(
      db,
      DailySessionState.empty(DateTime(2026, 9, 25)).copyWith(reviewedCount: 12, introducedIds: {'x'}),
    );
    final loaded = await DailySessionRepository.loadFrom(db, DateTime(2026, 9, 26, 8));
    expect(loaded.reviewedCount, 0);
    expect(loaded.introducedIds, isEmpty);
    expect(loaded.day, DateTime(2026, 9, 26));
  });

  test('introducedByModule zählt je Fach und ignoriert gelöschte Karten', () {
    final state = DailySessionState.empty(DateTime(2026, 9, 25)).copyWith(introducedIds: {'a', 'b', 'c', 'weg'});
    expect(state.introducedByModule({'a': 'm1', 'b': 'm1', 'c': 'm2'}), {'m1': 2, 'm2': 1});
  });
}
