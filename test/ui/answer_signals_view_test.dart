import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/answer_signals.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:provider/provider.dart';

class _Settings extends SettingsRepository {
  _Settings(this._value);
  final AppSettings _value;
  @override
  AppSettings get settings => _value;
}

final _choice = Flashcard(
  id: 'q1',
  moduleId: 'm1',
  front: 'Wovon hängt die Gewichtskraft ab?',
  back: '',
  createdAt: DateTime(2026, 1, 1),
  due: DateTime(2026, 1, 1),
  type: QuestionType.singleChoice,
  options: const [
    QuizOption(text: 'Masse und Ortsfaktor', isCorrect: true),
    QuizOption(text: 'Nur vom Volumen', isCorrect: false, why: 'Volumen allein sagt nichts über die Masse.'),
    QuizOption(text: 'Von der Geschwindigkeit', isCorrect: false, why: 'Verwechselt Gewicht mit Impuls.'),
  ],
);

Widget _harness(
  Flashcard card, {
  AppSettings settings = const AppSettings(),
  bool canGiveUp = false,
  required AnswerCallback onComplete,
}) {
  return ChangeNotifierProvider<SettingsRepository>(
    create: (_) => _Settings(settings),
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: QuestionAnswerView(card: card, isNew: false, canGiveUp: canGiveUp, onComplete: onComplete),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _choose(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pump();
}

Future<void> _checkAndNext(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Prüfen'));
  await tester.tap(find.text('Prüfen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('falsche Option zeigt ihren Denkfehler, ohne KI', (tester) async {
    await tester.pumpWidget(_harness(_choice, onComplete: ({selfGrade, isCorrect, signals}) {}));
    await _choose(tester, 'Von der Geschwindigkeit');
    await _checkAndNext(tester);
    expect(find.byKey(const ValueKey('option-why')), findsOneWidget);
    expect(find.textContaining('Verwechselt Gewicht mit Impuls.'), findsOneWidget);
    expect(find.textContaining('Volumen allein'), findsNothing);
  });

  testWidgets('Sicherheit „geraten“ reist mit der richtigen Antwort und wird angesagt', (tester) async {
    AnswerSignals? reported;
    bool? correct;
    await tester.pumpWidget(_harness(_choice, onComplete: ({selfGrade, isCorrect, signals}) {
      reported = signals;
      correct = isCorrect;
    }));
    await _choose(tester, 'Masse und Ortsfaktor');
    await tester.ensureVisible(find.byKey(const ValueKey('confidence-guessed')));
    await tester.tap(find.byKey(const ValueKey('confidence-guessed')));
    await tester.pump();
    await _checkAndNext(tester);
    expect(find.byKey(const ValueKey('signal-note')), findsOneWidget);
    await tester.ensureVisible(find.text('Weiter'));
    await tester.tap(find.text('Weiter'));
    await tester.pump();
    expect(correct, isTrue);
    expect(reported?.confidence, AnswerConfidence.guessed);
    expect(AnswerSignals.gradeFor(isCorrect: correct, signals: reported!), Grade.hard);
  });

  testWidgets('sicher und falsch: Hinweis auf Fehlvorstellung', (tester) async {
    await tester.pumpWidget(_harness(_choice, onComplete: ({selfGrade, isCorrect, signals}) {}));
    await _choose(tester, 'Nur vom Volumen');
    await tester.ensureVisible(find.byKey(const ValueKey('confidence-sure')));
    await tester.tap(find.byKey(const ValueKey('confidence-sure')));
    await tester.pump();
    await _checkAndNext(tester);
    expect(find.textContaining('Fehlvorstellung'), findsOneWidget);
  });

  testWidgets('Sicherheits-Knöpfe lassen sich abschalten', (tester) async {
    await tester.pumpWidget(_harness(
      _choice,
      settings: const AppSettings(askConfidence: false),
      onComplete: ({selfGrade, isCorrect, signals}) {},
    ));
    expect(find.byKey(const ValueKey('confidence-sure')), findsNothing);
  });

  testWidgets('„Weiß ich nicht“ meldet dontKnow', (tester) async {
    AnswerSignals? reported;
    await tester.pumpWidget(_harness(
      _choice,
      canGiveUp: true,
      onComplete: ({selfGrade, isCorrect, signals}) => reported = signals,
    ));
    await tester.ensureVisible(find.text('Weiß ich nicht'));
    await tester.tap(find.text('Weiß ich nicht'));
    await tester.pump();
    await tester.ensureVisible(find.text('Weiter'));
    await tester.tap(find.text('Weiter'));
    await tester.pump();
    expect(reported?.dontKnow, isTrue);
  });

  testWidgets('Tipp-Knopf mit API-Key zeigt die Stufe im Hinweis', (tester) async {
    await tester.pumpWidget(_harness(
      _choice,
      settings: const AppSettings(openRouterApiKey: 'sk-test'),
      onComplete: ({selfGrade, isCorrect, signals}) {},
    ));
    expect(find.byKey(const ValueKey('hint-ladder-button')), findsOneWidget);
    expect(find.text('Tipp'), findsOneWidget);
  });
}
