import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/tasks/paper_check_screen.dart';
import 'package:lernen/ui/tasks/step_task_view.dart';
import 'package:provider/provider.dart';

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

Flashcard _card() => Flashcard(
  id: 'w1',
  moduleId: 'm1',
  front: r"Löse $y' = 2x$ mit $y(0) = 1$.",
  back: r'$y = x^2 + 1$',
  createdAt: DateTime(2026, 1, 1),
  due: DateTime(2026, 1, 1),
  type: QuestionType.steps,
  taskData: {
    'kind': 'steps',
    'steps': [
      {
        'title': 'Integrieren',
        'prompt': 'Integriere.',
        'fields': [
          {
            'label': 'y(x) =',
            'answer': 'x^2 + C',
            'variables': ['x'],
            'constants': ['C'],
          },
        ],
        'result': r'$y = x^2 + C$',
      },
      {
        'title': 'Ergebnis',
        'prompt': 'Setze ein.',
        'fields': [
          {
            'label': 'y(x) =',
            'answer': 'x^2 + 1',
            'variables': ['x'],
          },
        ],
        'result': r'$y = x^2 + 1$',
      },
    ],
  },
);

void main() {
  tearDown(() {
    PaperCheckScreen.aiFactory = null;
    StepTaskView.aiFactory = null;
  });

  testWidgets('Selbst rechnen: getippten Rechenweg Zeile für Zeile von der KI prüfen lassen', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <String>[];
    PaperCheckScreen.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        sent.add('${((jsonDecode(r.body) as Map)['messages'] as List)[1]['content']}');
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'lines': [
                      {'n': 1, 'text': r'$y = x^2 + C$', 'status': 'ok'},
                      {'n': 2, 'text': r'$y(0) = C = 1$', 'status': 'ok'},
                      {'n': 3, 'text': r'$y = x^2 + 1$', 'status': 'ok'},
                    ],
                    'finalAnswer': 'x^2 + 1',
                    'firstErrorStep': null,
                    'summary': 'Alles richtig.',
                    'grade': 'gut',
                  }),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final results = <({Grade? grade, bool? correct})>[];
    final card = _card();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsRepository>.value(
        value: _SettingsWithKey(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: QuestionAnswerView(
              key: ValueKey(card.id),
              card: card,
              isNew: false,
              onComplete: ({Grade? selfGrade, bool? isCorrect}) => results.add((grade: selfGrade, correct: isCorrect)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-mode-write')));
    await tester.pump();
    expect(find.byKey(const ValueKey('step-write-ai')), findsNothing, reason: 'erst mit eigenen Zeilen');
    await tester.enterText(find.byKey(const ValueKey('step-line-0')), 'y = x^2 + C');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-line-add')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('step-line-1')), 'y(0) = C = 1');
    await tester.tap(find.byKey(const ValueKey('step-line-add')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('step-line-2')), 'y = x^2 + 1');
    await tester.pump();

    await tester.ensureVisible(find.byKey(const ValueKey('step-write-ai')));
    await tester.tap(find.byKey(const ValueKey('step-write-ai')));
    await tester.pumpAndSettle();
    expect(find.byType(PaperCheckScreen), findsOneWidget);
    expect(sent.single, contains('NICHT fotografiert'));
    expect(sent.single, contains('1: y = x^2 + C'));
    expect(sent.single, contains('3: y = x^2 + 1'));
    expect(find.text('Rechenweg prüfen'), findsOneWidget);
    expect(find.text('Rechenweg weiter bearbeiten'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('paper-grade-good')));
    await tester.tap(find.byKey(const ValueKey('paper-grade-good')));
    await tester.pumpAndSettle();
    expect(find.byType(PaperCheckScreen), findsNothing);
    expect(results.single.grade, Grade.good);
  });

  testWidgets('Selbst rechnen: eine Zeile prüft die KI – Fehler mit Erklärung, Korrektur erst auf Wunsch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <String>[];
    StepTaskView.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        final messages = (jsonDecode(r.body) as Map)['messages'] as List;
        sent.add('${messages[0]['content']}\n${messages[1]['content']}');
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'status': 'fehler',
                    'comment': r'Der Vorfaktor stimmt nicht – welche Funktion ergibt abgeleitet $2x$?',
                    'fix': r'$y = x^2 + C$',
                  }),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final card = _card();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsRepository>.value(
        value: _SettingsWithKey(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: QuestionAnswerView(
              key: ValueKey(card.id),
              card: card,
              isNew: false,
              onComplete: ({Grade? selfGrade, bool? isCorrect}) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-mode-write')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('step-line-0')), 'y = ∫ 2x dx = 2x^2 + C');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-line-check-0')));
    await tester.pumpAndSettle();
    expect(sent.single, contains('EINEN Rechenschritt'));
    expect(sent.single, contains('Zu prüfen – Zeile 1: y = ∫ 2x dx = 2x^2 + C'));
    expect(find.byKey(const ValueKey('step-line-result-0')), findsOneWidget);
    expect(find.textContaining('Vorfaktor'), findsOneWidget);
    expect(find.textContaining('Richtig wäre'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('step-line-fix-0')));
    await tester.pump();
    expect(find.textContaining('Richtig wäre'), findsOneWidget);
  });

  testWidgets('Selbst rechnen: einen Schritt mit der KI besprechen – vor und nach dem Prüfen', (tester) async {
    tester.view.physicalSize = const Size(600, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <String>[];
    StepTaskView.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        final messages = (jsonDecode(r.body) as Map)['messages'] as List;
        final system = '${messages[0]['content']}';
        sent.add('$system\n${messages[1]['content']}');
        final content = system.contains('Tutor')
            ? r'Hier integrierst du: gesucht ist eine Funktion, deren Ableitung $2x$ ist.'
            : jsonEncode({'status': 'fehler', 'comment': 'Vorfaktor prüfen.', 'fix': r'$y = x^2 + C$'});
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final card = _card();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsRepository>.value(
        value: _SettingsWithKey(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: QuestionAnswerView(
              key: ValueKey(card.id),
              card: card,
              isNew: false,
              onComplete: ({Grade? selfGrade, bool? isCorrect}) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-mode-write')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('step-line-0')), 'y = 2x^2 + C');
    await tester.pump();

    // Vor dem Prüfen.
    await tester.ensureVisible(find.byKey(const ValueKey('step-line-chat-0')));
    await tester.tap(find.byKey(const ValueKey('step-line-chat-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Noch nicht geprüft'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('step-chat-suggest-0')));
    await tester.pumpAndSettle();
    expect(sent.last, contains('Der Schritt wurde noch NICHT geprüft.'));
    expect(sent.last, contains('Frage: Was mache ich in diesem Schritt eigentlich?'));
    expect(sent.last, contains('Der besprochene Schritt (Zeile 1): y = 2x^2 + C'));
    expect(find.byKey(const ValueKey('step-chat-msg-1')), findsOneWidget);
    expect(find.textContaining('deren Ableitung'), findsOneWidget);
    // Eigene Frage – das Gespräch geht weiter.
    await tester.enterText(find.byKey(const ValueKey('step-chat-input')), 'Und warum die Konstante C?');
    await tester.tap(find.byKey(const ValueKey('step-chat-send')));
    await tester.pumpAndSettle();
    expect(sent.last, contains('Bisheriges Gespräch über diesen Schritt'));
    expect(find.byKey(const ValueKey('step-chat-msg-3')), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const ValueKey('step-chat-input')))).pop();
    await tester.pumpAndSettle();

    // Nach dem Prüfen (Fehler): andere Vorschläge, Prüfergebnis geht mit.
    await tester.tap(find.byKey(const ValueKey('step-line-check-0')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('step-line-chat-0')));
    await tester.tap(find.byKey(const ValueKey('step-line-chat-0')));
    await tester.pumpAndSettle();
    expect(find.text('Geprüft: Fehler'), findsOneWidget);
    expect(find.byKey(const ValueKey('step-chat-msg-3')), findsOneWidget, reason: 'Verlauf bleibt');
    await tester.tap(find.text('Warum ist das falsch?'));
    await tester.pumpAndSettle();
    expect(sent.last, contains('Prüfergebnis: Fehler – Vorfaktor prüfen.'));
  });
}
