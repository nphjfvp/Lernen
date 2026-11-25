import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/review_log_repository.dart';
import 'package:lernen/services/answer_signals.dart';
import 'package:lernen/services/mastery_service.dart';
import 'package:lernen/services/weakness_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/stats/stats_screen.dart';
import 'package:lernen/ui/stats/weakness_screen.dart';

WeakCard _weak(String id) => WeakCard(
      card: Flashcard(
        id: id,
        moduleId: 'm',
        front: 'F $id',
        back: 'A',
        createdAt: DateTime(2026),
        due: DateTime(2026),
      ),
      level: MasteryLevel.red,
      score: 1,
      reasons: const [],
    );

void main() {
  testWidgets('Kalibrierung: Trefferquote je Sicherheit, Urteil erst ab 10 Antworten', (tester) async {
    Future<void> show(List<CalibrationBucket> buckets) => tester.pumpWidget(MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: Scaffold(body: CalibrationCard(buckets: buckets)),
        ));
    await show(const [
      CalibrationBucket(AnswerConfidence.guessed, 4, 1),
      CalibrationBucket(AnswerConfidence.unsure, 0, 0),
      CalibrationBucket(AnswerConfidence.sure, 12, 9),
    ]);
    expect(find.text('„geraten“: 25 % richtig (4 Antworten)'), findsOneWidget);
    expect(find.text('„sicher“: 75 % richtig (12 Antworten)'), findsOneWidget);
    expect(find.textContaining('eher sicher'), findsNothing, reason: 'ohne Antworten keine Zeile');
    expect(find.textContaining('öfter daneben'), findsOneWidget);

    await show(const [CalibrationBucket(AnswerConfidence.sure, 3, 1)]);
    expect(find.textContaining('öfter daneben'), findsNothing, reason: 'zu wenige Antworten für ein Urteil');
  });

  test('Fehlertagebuch: mögliche Fehlvorstellungen zuerst, sonst Reihenfolge wie gehabt', () {
    final ranked = [_weak('a'), _weak('b'), _weak('c'), _weak('d')];
    final sorted = WeaknessScreen.misconceptionsFirst(ranked, {'c', 'a'});
    expect(sorted.map((w) => w.card.id), ['a', 'c', 'b', 'd']);
  });
}
