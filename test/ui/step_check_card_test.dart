import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/visual/step_check_card.dart';

void main() {
  test('StepCheck.fromMap: tolerant, aber nur mit genau einer richtigen Option', () {
    final check = StepCheck.fromMap({
      'question': 'Was passiert mit v, wenn s linear wächst?',
      'options': [
        {'text': 'konstant', 'correct': true},
        {'text': 'wächst linear', 'isCorrect': false, 'why': 'verwechselt s mit v'},
        'wird null',
      ],
      'explanation': 'Die Steigung bleibt gleich.',
    })!;
    expect(check.options, hasLength(3));
    expect(check.options[1].why, 'verwechselt s mit v');
    expect(StepCheck.fromMap(check.toMap())!.options[1].why, 'verwechselt s mit v');
    expect(StepCheck.fromMap({'question': 'Q', 'options': [{'text': 'a', 'correct': true}, {'text': 'b', 'correct': true}]}), isNull);
    final step = VisualStep.fromMap({'title': 'T', 'text': 'x', 'check': check.toMap()})!;
    expect(step.check, isNotNull);
    expect(VisualStep.fromMap(step.toMap())!.check!.question, check.question);
    expect(step.copyWith().check, isNotNull);
  });

  testWidgets('falsche Wahl zeigt Denkfehler und bietet „anders erklären“', (tester) async {
    String? repair;
    final check = StepCheck(question: 'Frage?', options: const [
      StepCheckOption(text: 'Richtig', correct: true),
      StepCheckOption(text: 'Falsch', correct: false, why: 'typischer Fehler'),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: ListView(children: [StepCheckCard(check: check, onRepair: (r) => repair = r)])),
    ));
    await tester.tap(find.byKey(const ValueKey('step-check-open')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-check-option-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('step-check-why')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('step-check-repair')));
    expect(repair, contains('„Falsch“'));
  });
}
