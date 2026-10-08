import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/step_task.dart';
import 'package:lernen/models/step_task_review.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/tasks/step_task_editor.dart';
import 'package:lernen/ui/tasks/step_task_review_sheet.dart';
import 'package:provider/provider.dart';

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

http.Response _chat(Object json) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': jsonEncode(json)},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Exponentialterm mit einem „typischen Fehler“, der in Wahrheit richtig ist.
StepTask _task({bool withBadMistake = true}) => StepTask(steps: [
      TaskStep(title: 'Exponentialterm', fields: [
        StepField(
          label: 'e^(-x) =',
          answer: '8.63*10^-9',
          kind: StepFieldKind.number,
          tolerance: 0.01,
          mistakes: [
            if (withBadMistake) const StepMistake(answer: '8.63e-9', feedback: 'Vorzeichen im Exponenten?'),
            const StepMistake(answer: '8.63*10^9', feedback: 'Minus im Exponenten vergessen.'),
          ],
        ),
      ]),
    ]);

void main() {
  tearDown(() => StepTaskReviewSheet.aiFactory = null);

  test('Antwort der KI lesen: Urteil und Korrektur', () {
    final r = StepTaskReview.fromJson({
      'answer': 'Nur die Rückmeldung ist falsch.',
      'verdict': 'rueckmeldung_falsch',
      'corrected': _task(withBadMistake: false).toMap(),
    });
    expect(r.verdict, StepReviewVerdict.feedbackWrong);
    expect(r.corrected!.steps.single.fields.single.mistakes, hasLength(1));
    expect(stepReviewVerdictFrom('loesung_falsch'), StepReviewVerdict.solutionWrong);
    expect(StepTaskReview.fromJson({'answer': 'x', 'corrected': null}).corrected, isNull);
  });

  testWidgets('Was heißt das? KI erklärt, Nachfrage, Korrektur von der App nachgerechnet übernehmen', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prompts = <String>[];
    StepTaskReviewSheet.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            prompts.add(((jsonDecode(r.body)['messages'] as List).last['content']) as String);
            return prompts.length == 1
                ? _chat({
                    'answer': 'Die Aufgabe stimmt. Als typischer Fehler war dieselbe Zahl hinterlegt – das ist nur eine falsche Rückmeldung.',
                    'verdict': 'rueckmeldung_falsch',
                    'corrected': _task(withBadMistake: false).toMap(),
                  })
                : _chat({'answer': 'Nein, deine Aufgabe ist richtig – nur die Rückmeldung fliegt raus.', 'verdict': 'ok', 'corrected': null});
          }),
        );
    StepTask? changed;
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey())],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StepTaskEditor(task: _task(), taskText: 'Berechne e^(-18.57).', onChanged: (t) => changed = t),
          ),
        ),
      ),
    ));
    expect(find.text('Bitte prüfen – die App hat Unstimmigkeiten gefunden'), findsOneWidget);
    expect(find.textContaining('ist als typischer Fehler hinterlegt'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('step-verify-ask-ai')));
    await tester.pumpAndSettle();
    expect(prompts.single, contains('Berechne e^(-18.57).'));
    expect(prompts.single, contains('typischer Fehler hinterlegt'));
    expect(find.text('Nur eine Rückmeldung ist falsch'), findsOneWidget);
    expect(find.text('Die App hat die korrigierte Aufgabe nachgerechnet: keine Unstimmigkeiten mehr.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('step-review-question')), 'Ist meine Aufgabe jetzt falsch?');
    await tester.tap(find.byKey(const ValueKey('step-review-send')));
    await tester.pumpAndSettle();
    expect(prompts.last, contains('Neue Frage des Nutzers: Ist meine Aufgabe jetzt falsch?'));
    expect(prompts.last, contains('Deine Antwort: Die Aufgabe stimmt.'));
    expect(find.textContaining('deine Aufgabe ist richtig', findRichText: true), findsWidgets);

    // Die Korrektur aus der ersten Antwort bleibt übernehmbar.
    await tester.ensureVisible(find.byKey(const ValueKey('step-review-apply')));
    await tester.tap(find.byKey(const ValueKey('step-review-apply')));
    await tester.pumpAndSettle();
    expect(changed!.steps.single.fields.single.mistakes.map((m) => m.answer), ['8.63*10^9']);
    expect(find.text('Bitte prüfen – die App hat Unstimmigkeiten gefunden'), findsNothing);
  });
}
