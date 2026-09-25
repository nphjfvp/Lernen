import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/repositories/study_log_repository.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('speichert jeden Tag nur einmal und liest ihn als Kalendertag zurück', () async {
    final db = await databaseFactoryMemory.openDatabase('study_log_${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(db.close);

    await StudyLogRepository.recordDayIn(db, DateTime(2026, 9, 24));
    await StudyLogRepository.recordDayIn(db, DateTime(2026, 9, 25));
    await StudyLogRepository.recordDayIn(db, DateTime(2026, 9, 25));

    expect(await StudyLogRepository.loadDaysFrom(db), {DateTime(2026, 9, 24), DateTime(2026, 9, 25)});
  });
}
