import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/models/worked_solution.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/visual/calculator_sim.dart';
import 'package:lernen/ui/visual/worked_board.dart';
import 'package:lernen/ui/visual/worked_solution_screen.dart';
import 'package:provider/provider.dart';

class _Cards extends FlashcardRepository {
  @override
  Future<List<Flashcard>> loadModuleCards(String moduleId) async => [
    Flashcard(
      id: 'k1',
      moduleId: moduleId,
      front: 'Was ist ein Integral?',
      back: 'Fläche',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
    ),
    Flashcard(
      id: 'k2',
      moduleId: moduleId,
      front: r'Löse $\ln\left((48x+6)^2\right) = 10$.',
      back: r'$x = \frac{e^5-6}{48}$',
      createdAt: DateTime(2026, 1, 2),
      due: DateTime(2026, 1, 2),
      type: QuestionType.steps,
      taskData: {
        'kind': 'steps',
        'steps': [
          {
            'title': 'Log-Gesetz',
            'prompt': 'Wende es an.',
            'fields': [
              {'label': 'x =', 'answer': '(e^5-6)/48'},
            ],
          },
        ],
      },
    ),
  ];
}

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

const _aiSolution = {
  'title': 'Logarithmus-Gleichung',
  'steps': [
    {
      'title': 'Logarithmusgesetz anwenden',
      'say': r'Eine Hochzahl im ln darf nach vorn: $\ln(a^b) = b\ln a$.',
      'from': r'\ln\left((48x+6)^2\right) = 10',
      'work': r'\focus{\ln\left((48x+6)^2\right)} = 10',
      'to': r'\focus{2\ln(48x+6)} = 10',
      'rule': {'name': 'Logarithmusgesetz', 'formula': r'\ln(a^b) = b\cdot\ln(a)'},
    },
    {
      'title': 'Durch 2 teilen',
      'say': 'Beide Seiten durch 2.',
      'op': ':2',
      'work': r'\del{2}\ln(48x+6) = \add{\frac{10}{2}}',
      'to': r'\ln(48x+6) = 5',
    },
    {
      'title': 'e hoch beide Seiten',
      'say': 'Die Umkehrung von ln ist e hoch.',
      'op': r'e^{(\ldots)}',
      'to': '48x + 6 = e^5',
      'calc': {
        'keys': ['AC', 'SHIFT', 'LN', '5', 'RIGHT', 'EQ'],
        'input': 'e^5',
        'expr': 'e^5',
        'result': '148.4131591',
      },
    },
  ],
  'answer': r'x = \frac{e^5 - 6}{48}',
};

void main() {
  group('Tafel', () {
    test('Markierungen → LaTeX, farbig oder schlicht', () {
      expect(WorkMarkup.toTex(r'3x \add{-5x} = \del{5x}', colored: false), '3x {-5x} = {5x}');
      final colored = WorkMarkup.toTex(r'\focus{\frac{a}{b}} + \del{c}');
      expect(colored, contains(r'\textcolor{#1565C0}{\frac{a}{b}}'));
      expect(colored, contains(r'\textcolor{#C62828}{\cancel{c}}'));
      expect(WorkMarkup.hasMarks(r'\add{x}'), isTrue);
    });

    test('Zeile am Gleichheitszeichen teilen, Klammern beachten', () {
      expect(WorkMarkup.split(r'\ln\left(x=1\right) = 5'), (r'\ln\left(x=1\right)', '=', '5'));
      expect(WorkMarkup.split(r'= 2\ln(48x+6)'), ('', '=', r'2\ln(48x+6)'));
      expect(WorkMarkup.split(r'x \approx 2{,}5'), ('x', r'\approx', '2{,}5'));
      expect(WorkMarkup.split(r'\left(x+1\right)^2'), ('', '', r'\left(x+1\right)^2'));
    });

    test('Ablauf: Ansatz, markiert, neue Zeile – je Schritt', () {
      final s = WorkedSolution.fromAi(
        Map<String, dynamic>.from(_aiSolution),
        id: 'w',
        moduleId: 'm',
        problem: 'p',
        detail: WorkDetail.fine,
        now: DateTime(2026),
      );
      expect(s.steps, hasLength(3));
      expect(s.steps[0].rule?.name, 'Logarithmusgesetz');
      expect(s.steps[2].calc?.keys, hasLength(6));
      final p = WorkPlayback(s.steps);
      expect(p.phasesOf(0), [0, 1, 2]);
      expect(p.phasesOf(2), [0, 2]);
      expect(p.length, 8);
      expect(p.at(4), (1, 1));
      expect(p.startOf(2), 6);
      // Schritt 2, markiert: Ausgangszeile ist die letzte Zeile mit „| :2“.
      final b = p.board(1, 1);
      expect(b.map((l) => l.tex), [r'\ln\left((48x+6)^2\right) = 10', r'\del{2}\ln(48x+6) = \add{\frac{10}{2}}']);
      expect(b.last.op, ':2');
      expect(b.last.colored, isTrue);
      final done = p.board(2, 2);
      expect(done.last.tex, '48x + 6 = e^5');
      expect(done.last.isNew, isTrue);
      expect(done, hasLength(4));
    });
  });

  group('Taschenrechner', () {
    test('Tastennamen der KI', () {
      expect(CalcKeys.normalize('×'), 'MUL');
      expect(CalcKeys.normalize('ln'), 'LN');
      expect(CalcKeys.normalize('shift'), 'SHIFT');
      expect(CalcKeys.byId['FRAC']?.label, 'a/b');
    });
  });

  tearDown(() => WorkedSolutionScreen.aiFactory = null);

  testWidgets('Vorrechnen: Detailgrad wählen, Schritt für Schritt, Taschenrechner, Fragen, feiner', (tester) async {
    tester.view.physicalSize = const Size(1300, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    WorkedSolutionScreen.autoDelay = const Duration(milliseconds: 300);
    final sent = <String>[];
    WorkedSolutionScreen.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        final messages = (jsonDecode(r.body) as Map)['messages'] as List;
        final system = '${messages[0]['content']}';
        final user = '${messages[1]['content']}';
        sent.add(user);
        final Object reply;
        if (system.contains('Tutor')) {
          reply = r'Weil $\ln$ und $e^x$ sich aufheben.';
        } else if (user.contains('feiner werden')) {
          reply = jsonEncode({
            'steps': [
              {'title': 'Faktor 2 sehen', 'say': 'Vor dem ln steht 2.', 'work': r'\focus{2}\ln(48x+6) = 10'},
              {'title': 'Teilen', 'say': 'Durch 2.', 'op': ':2', 'to': r'\ln(48x+6) = 5'},
            ],
          });
        } else {
          reply = jsonEncode(_aiSolution);
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': reply},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsRepository>.value(
        value: _SettingsWithKey(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const WorkedSolutionScreen(moduleId: 'm1', problem: 'Löse ln((48x+6)²) = 10.'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('worked-detail-fine')));
    await tester.pump();
    expect(find.text(WorkDetail.fine.hint), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('worked-start')));
    await tester.pumpAndSettle();
    expect(sent.single, contains('fein'));
    expect(sent.single, contains('Taschenrechner: ja'));

    // Schritt 1: Ansatz mit Regel.
    expect(find.byKey(const ValueKey('work-board')), findsOneWidget);
    expect(find.text('Logarithmusgesetz anwenden'), findsOneWidget);
    expect(find.byKey(const ValueKey('worked-rule-0')), findsOneWidget);
    expect(find.text('Schritt 1 von 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('worked-next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Grün kommt dazu'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('worked-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-1-2')), findsOneWidget, reason: 'neue Zeile an der Tafel');
    await tester.tap(find.byKey(const ValueKey('worked-next')));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 2 von 3'), findsOneWidget);
    expect(find.textContaining('Umformung auf beiden Seiten'), findsOneWidget);

    // Frage zum Schritt.
    await tester.tap(find.byKey(const ValueKey('worked-ask')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('worked-chat-suggest-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('worked-chat-msg-1')), findsOneWidget);
    expect(sent.last, contains('Aktueller Schritt: Durch 2 teilen'));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Schritt feiner: aus einem werden zwei.
    await tester.tap(find.byKey(const ValueKey('worked-refine')));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 2 von 4'), findsOneWidget);
    expect(find.text('Faktor 2 sehen'), findsOneWidget);

    // Bis zum Ende: Taschenrechner drückt Tasten, Ergebnis erscheint.
    await tester.tap(find.byKey(const ValueKey('worked-jump')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('4. e hoch'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calc-sim')), findsOneWidget);
    expect(find.byKey(const ValueKey('calc-seq-5')), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calc-result')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('worked-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('worked-answer')), findsOneWidget);
  });

  testWidgets('Vorrechnen ohne Key: Hinweis statt Absturz', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const WorkedSolutionScreen(moduleId: 'm1', problem: '2x = 4')),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('worked-start')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('worked-start')));
    await tester.pump();
    expect(find.byKey(const ValueKey('worked-error')), findsOneWidget);
  });

  testWidgets('Vorrechnen: vorhandene Aufgabe aus dem Fach wählen', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <String>[];
    WorkedSolutionScreen.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        sent.add('${((jsonDecode(r.body) as Map)['messages'] as List)[1]['content']}');
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': jsonEncode(_aiSolution)},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
          ChangeNotifierProvider<FlashcardRepository>.value(value: _Cards()),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const WorkedSolutionScreen(moduleId: 'm1')),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('worked-pick')));
    await tester.pumpAndSettle();
    // Nur Rechenwege – die Karteikarte erst ohne Filter.
    expect(find.byKey(const ValueKey('worked-pick-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('worked-pick-only-steps')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('worked-pick-1')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('worked-pick-search')), 'löse');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('worked-pick-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('worked-picked')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('worked-problem'))).controller!.text, contains('48x+6'));
    await tester.tap(find.byKey(const ValueKey('worked-start')));
    await tester.pumpAndSettle();
    expect(sent.single, contains('Vorhandene Musterlösung'));
    expect(sent.single, contains('1. Log-Gesetz'));
    expect(find.byKey(const ValueKey('work-board')), findsOneWidget);
  });
}
