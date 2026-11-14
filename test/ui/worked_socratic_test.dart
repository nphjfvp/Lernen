import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/worked_solution.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/visual/worked_board.dart';
import 'package:lernen/ui/visual/worked_solution_screen.dart';
import 'package:provider/provider.dart';

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

class _Cards extends FlashcardRepository {
  final saved = <Flashcard>[];

  @override
  Future<void> saveAll(List<Flashcard> cards) async => saved.addAll(cards);
}

WorkedSolution _separation() => WorkedSolution.fromAi(
  {
    'title': 'Rezept: Trennung der Variablen',
    'steps': [
      {
        'kind': 'focus',
        'title': 'Aufgabe verstehen',
        'say': 'Eine DGL erster Ordnung, die sich in f(x)·g(y) zerlegen lässt.',
        'marks': [
          {'text': r"$y' = f(x)\cdot g(y)$", 'role': 'gegeben'},
          {'text': r'$y(x)$', 'role': 'gesucht'},
        ],
      },
      {
        'title': "y' als Differentialquotient",
        'say': r"Schreib $y'$ als $\frac{dy}{dx}$.",
        'from': r"y' = f(x)\cdot g(y)",
        'work': r"\focus{y'} = f(x)\cdot g(y)",
        'to': r'\focus{\frac{dy}{dx}} = f(x)\cdot g(y)',
      },
      {
        'title': 'Variablen trennen',
        'say': 'Alles mit y nach links, alles mit x nach rechts.',
        'op': r'\cdot \frac{dx}{g(y)}',
        'to': r'\frac{dy}{g(y)} = f(x)\,dx',
      },
    ],
    'answer': r'\int \frac{dy}{g(y)} = \int f(x)\,dx',
  },
  id: 'r1',
  moduleId: 'm1',
  problem: 'Trennung der Variablen',
  detail: WorkDetail.normal,
  now: DateTime(2026),
  general: true,
);

void main() {
  test('Tafel: Analyse, Text und Tabelle als eigene Abschnitte; sokratisch ohne Umformung', () {
    final s = WorkedSolution.fromAi(
      {
        'steps': [
          {
            'kind': 'focus',
            'title': 'Verstehen',
            'marks': [
              {'text': 'Stahl und Alu', 'role': 'gegeben'},
              {'text': 'Vergleich', 'role': 'gesucht'},
            ],
          },
          {
            'kind': 'table',
            'title': 'Dichte',
            'table': {
              'columns': ['Eigenschaft', 'Stahl', 'Alu'],
              'rows': [
                ['Dichte', '7,85', ''],
              ],
              'new': [
                [0, 1],
              ],
            },
          },
          {
            'kind': 'table',
            'title': 'Alu',
            'table': {
              'columns': ['Eigenschaft', 'Stahl', 'Alu'],
              'rows': [
                ['Dichte', '7,85', '2,70'],
              ],
              'new': [
                [0, 2],
              ],
            },
          },
          {'kind': 'text', 'title': 'Fazit', 'content': 'Alu ist leichter.'},
        ],
      },
      id: 'x',
      moduleId: 'm',
      problem: 'Vergleiche Stahl und Aluminium.',
      detail: WorkDetail.normal,
      now: DateTime(2026),
    );
    expect(s.steps.map((e) => e.kind), [WorkKind.focus, WorkKind.table, WorkKind.table, WorkKind.text]);
    expect(WorkedSolution.fromMap(s.toMap())!.steps[1].table!.fresh, {(0, 1)}, reason: 'gespeichert und gelesen');
    final p = WorkPlayback(s.steps);
    expect(p.phasesOf(1), [0, 2]);
    final b = p.blocks(3, 2);
    expect(b.map((e) => e.runtimeType), [FocusBlock, TableBlock, TextBlock], reason: 'Tabelle wächst an einer Stelle');
    expect((b[1] as TableBlock).table.rows.single.last, '2,70');
    expect(p.blocks(1, 0).length, 1, reason: 'Phase 0: neue Zeile noch nicht da');

    final r = WorkPlayback(_separation().steps);
    final ask = r.board(2, -1);
    expect(ask.last.op, isEmpty, reason: 'sokratisch: die Umformung ist noch nicht verraten');
    expect(ask.last.tex, contains(r'\frac{dy}{dx}'));
  });

  test('Tafel-Zeile in antippbare Teile zerlegen', () {
    final chunks = LatexChunks.split(r"y' = y^2 \sin(x)");
    expect(chunks.map((c) => c.tex), ["y'", '=', 'y^2', r'\sin(x)']);
    expect(chunks[1].op, isTrue);
  });

  tearDown(() => WorkedSolutionScreen.aiFactory = null);

  testWidgets('Sokratisch: markieren, Idee prüfen, vorspulen, nicht Gewusstes üben, als Karte speichern', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <String>[];
    var verdict = 'falsch';
    WorkedSolutionScreen.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        final user = '${((jsonDecode(r.body) as Map)['messages'] as List)[1]['content']}';
        sent.add(user);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'verdict': verdict,
                    'feedback': verdict == 'richtig' ? 'Genau: y′ = dy/dx.' : 'Das hilft hier noch nicht.',
                    'hint': verdict == 'richtig' ? '' : 'Wie schreibt man y′ als Bruch?',
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
    final cards = _Cards();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
          ChangeNotifierProvider<FlashcardRepository>.value(value: cards),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: WorkedSolutionScreen(moduleId: 'm1', solution: _separation(), startSocratic: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Schritt 1 (Aufgabe verstehen): weiß ich nicht → vorspulen.
    expect(find.byKey(const ValueKey('worked-ask-panel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('worked-idea-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-focus-0')), findsNothing, reason: 'erst Phase 0');
    await tester.tap(find.byKey(const ValueKey('worked-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-focus-0')), findsOneWidget);

    // Schritt 2: y' markieren, erst falsch, dann richtig.
    await tester.tap(find.byKey(const ValueKey('worked-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('worked-ask-panel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('worked-chunk-0')));
    await tester.enterText(find.byKey(const ValueKey('worked-idea')), 'ableiten');
    await tester.tap(find.byKey(const ValueKey('worked-idea-check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('worked-idea-result')), findsOneWidget);
    expect(find.textContaining('Wie schreibt man'), findsOneWidget);
    expect(sent.last, contains("Die Person hat markiert: y'"));
    expect(sent.last, contains('Ihr Vorschlag: ableiten'));
    verdict = 'richtig';
    await tester.enterText(find.byKey(const ValueKey('worked-idea')), 'wird zu dy/dx');
    await tester.tap(find.byKey(const ValueKey('worked-idea-check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('worked-ask-panel')), findsNothing);
    expect(find.byKey(const ValueKey('worked-praise')), findsOneWidget);

    // Bis zum nächsten Schritt durchgehen, Schritt 3 vorspulen, ans Ende.
    for (var i = 0; i < 3 && find.byKey(const ValueKey('worked-ask-panel')).evaluate().isEmpty; i++) {
      await tester.tap(find.byKey(const ValueKey('worked-next')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('worked-idea-skip')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      if (find.byKey(const ValueKey('worked-socratic-summary')).evaluate().isNotEmpty) break;
      await tester.tap(find.byKey(const ValueKey('worked-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Selbst gewusst: 1 von 3 Schritten'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('worked-practice-unknown')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('worked-ask-panel')), findsOneWidget);
    expect(find.text('Dein Zug – Schritt 1'), findsOneWidget);

    // Als Lernkarte speichern.
    await tester.tap(find.byKey(const ValueKey('worked-save-card')));
    await tester.pumpAndSettle();
    expect(cards.saved.single.front, contains('Rezept: Trennung der Variablen'));
    expect(cards.saved.single.back, contains('2. Variablen trennen'.replaceFirst('2.', '3.')));
    expect(find.byKey(const ValueKey('worked-save-card')), findsNothing, reason: 'schon gespeichert');
  });

  testWidgets('Rezept (allgemein): Aufgabentypen als Vorschlag, Modus geht an die KI', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    WorkedSolutionScreen.taskTypesLoader = (_) async => ['Trennung der Variablen: DGL lösen'];
    addTearDown(() => WorkedSolutionScreen.taskTypesLoader = null);
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
                'message': {'content': jsonEncode(_separation().toMap())},
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
        child: MaterialApp(theme: AppTheme.light, home: const WorkedSolutionScreen(moduleId: 'm1')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('worked-kind-general')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('worked-type-0')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('worked-problem'))).controller!.text, contains('Trennung'));
    expect(find.byKey(const ValueKey('worked-calculator')), findsNothing, reason: 'Rezept ohne Rechner');
    await tester.tap(find.byKey(const ValueKey('worked-start')));
    await tester.pumpAndSettle();
    expect(sent.single, contains('MODUS: ALLGEMEIN'));
    expect(sent.single, contains('Taschenrechner: nein'));
    expect(find.textContaining('Rezept ·'), findsOneWidget);
  });
}
