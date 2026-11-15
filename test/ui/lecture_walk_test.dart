import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/lecture_walk.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/worked_solution.dart';
import 'package:lernen/repositories/lecture_walk_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/lecture/lecture_board.dart';
import 'package:lernen/ui/lecture/lecture_walk_screen.dart';
import 'package:lernen/ui/visual/calculator_sim.dart';
import 'package:lernen/ui/visual/worked_solution_screen.dart';
import 'package:sembast/sembast_memory.dart';

const _pages = [
  'Differentialgleichungen – Vorlesung 5',
  'Substitution: Idee u = x + y',
  'Trennung der Variablen und Substitution',
  'Trennen: Integrieren beider Seiten',
  'Substitution: Rücksubstitution, Anfangswert',
  'Trennen: Beispiele',
];

Map<String, dynamic> _task(String problem, List<int> pages, {String formula = ''}) => {
  'title': problem,
  'problem': problem,
  'answer': 'fertig',
  'steps': [
    for (final (i, p) in pages.indexed)
      {
        'title': 'Schritt ${i + 1}',
        'say': 'Auf Seite $p kam genau das – Schritt ${i + 1}.',
        'from': i == 0 ? 'A = 0' : '',
        'to': 'A = ${i + 1}',
        'page': p,
        if (i == 1)
          'calc': {
            'keys': ['2', '×', '3', '='],
            'expr': '2*3',
            'result': '6',
          },
        'formulas': [
          if (i == 0 && formula.isNotEmpty) {'name': formula, 'latex': r'u = x + y', 'note': 'macht die DGL trennbar'},
        ],
      },
  ],
};

http.Response _reply(Object content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content is String ? content : jsonEncode(content)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late List<String> asked;

  setUp(() {
    asked = [];
    WorkedSolutionScreen.autoDelay = const Duration(milliseconds: 20);
    LectureWalkScreen.loadHook = (_) async => (bytes: null, pageTexts: _pages);
    LectureWalkScreen.aiFactory = () => AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((r) async {
        final messages = (jsonDecode(r.body) as Map)['messages'] as List;
        final system = '${messages[0]['content']}';
        final user = '${messages[1]['content']}';
        asked.add(user);
        if (system.contains('KONZEPTE')) {
          return _reply({
            'concepts': [
              {
                'title': 'DGL durch Substitution lösen',
                'goal': 'eine DGL mit u = x + y vollständig lösen',
                'pages': [2, 3, 5],
              },
              {
                'title': 'Trennung der Variablen',
                'pages': [3, 4, 6],
              },
            ],
          });
        }
        if (user.contains('AUFTRAG: Erfinde')) {
          return user.contains('Konzept: DGL durch Substitution')
              ? _reply(_task(r"Löse $y' = (x+y)^2$, $y(0)=0$.", [2, 3, 5], formula: 'Substitution'))
              : _reply(_task(r"Löse $y' = xy$, $y(0)=2$.", [3, 4, 6]));
        }
        if (system.contains('Lösungsversuch')) {
          return _reply({
            'solved': false,
            'feedback': 'Nach dem Einsetzen fehlt die 1 in u\' = 1 + y\'.',
            'step': 2,
            'explain': r"Aus $u = x + y$ folgt $u' = 1 + y'$ – genau das steht auf Seite 3.",
          });
        }
        return _reply(r'Weil $u = x + y$ die DGL trennbar macht.');
      }),
    );
  });

  tearDown(() {
    LectureWalkScreen.loadHook = null;
    LectureWalkScreen.aiFactory = null;
    WorkedSolutionScreen.autoDelay = const Duration(milliseconds: 2800);
  });

  testWidgets('Vorlesung mit Aufgabe: Konzepte vorab, Vorrechnen-Tafel Seite für Seite, Formeln, selbst lösen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('walk_${DateTime.now().microsecondsSinceEpoch}'),
    ))!;
    addTearDown(db.close);
    final repo = LectureWalkRepository(openDatabase: () async => db);
    final material = MaterialItem(
      id: 'pdf1',
      moduleId: 'm1',
      fileName: 'Vorlesung 5.pdf',
      kind: MaterialKind.slide,
      extractedText: '',
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LectureWalkScreen(material: material, repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    // Vorab: Konzepte der ganzen Vorlesung und beide Aufgaben – die Tafel ist noch leer.
    expect(asked.where((u) => u.contains('AUFTRAG: Erfinde')), hasLength(2));
    expect(asked.firstWhere((u) => u.contains('Konzept: DGL')), contains('KEINE Aufgabe'));
    expect(find.textContaining('Alles vorbereitet'), findsOneWidget);
    expect(find.byKey(const ValueKey('lecture-concept-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('lecture-concept-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('worked-waiting')), findsOneWidget);

    // Seite 2: erster Schritt an der Vorrechnen-Tafel, neue Formel.
    await tester.tap(find.byKey(const ValueKey('lecture-next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Okay, lass uns mit unserer Aufgabe zu „DGL durch Substitution lösen“'), findsOneWidget);
    expect(find.byKey(const ValueKey('worked-waiting')), findsNothing);
    expect(find.byKey(const ValueKey('lecture-new-formulas')), findsOneWidget);
    expect(find.text('1. DGL durch Substitution lösen · 1/3'), findsOneWidget);

    // Seite 3: beide Konzepte gehen weiter; Taschenrechner an der Tafel.
    await tester.tap(find.byKey(const ValueKey('lecture-next')));
    await tester.pumpAndSettle();
    expect(find.text('1. DGL durch Substitution lösen · 2/3'), findsOneWidget);
    expect(find.text('2. Trennung der Variablen · 1/3'), findsOneWidget);
    expect(find.byType(CalculatorSim), findsWidgets);

    // Anderes Konzept an die Tafel holen.
    await tester.ensureVisible(find.byKey(const ValueKey('lecture-concept-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lecture-concept-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('worked-1-null')), findsOneWidget);

    // Frage zur Formel.
    await tester.tap(find.byKey(const ValueKey('lecture-formulas')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lecture-formula-ask-0')));
    await tester.pumpAndSettle();
    expect(asked.last, contains('Substitution'));
    expect(find.textContaining('trennbar macht'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lecture-formulas')));
    await tester.pumpAndSettle();

    // Seiten 4–6: einmal durch.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('lecture-next')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('lecture-self-solve')), findsOneWidget);
    final saved = (await tester.runAsync(() => repo.load('pdf1')))!;
    expect(saved.tasks.keys, containsAll([0, 1]));
    expect(saved.maxPage, 6);
    expect(saved.formulas.single.name, 'Substitution');

    // Selbst lösen: Haken bei Schritt 2 → Seite 3, Tafel springt dorthin.
    await tester.tap(find.byKey(const ValueKey('lecture-self-solve')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('self-concept-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('self-answer')), "u = x + y, dann u' = u^2");
    await tester.tap(find.byKey(const ValueKey('self-check')));
    await tester.pumpAndSettle();
    expect(find.text('Noch nicht ganz.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('self-jump')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Seite 3/6'), findsWidgets);
    expect(find.textContaining('Hier hakt es – auf Seite 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('worked-0-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('lecture-visual')), findsOneWidget);
    expect((await tester.runAsync(() => repo.load('pdf1')))!.attempts[0]!.step, 1);
  });

  test('Tafel-Stand übersteht den Weg ins eigene Fenster', () {
    final state = LectureBoardState(
      concepts: const [LectureBoardConcept(title: 'Substitution', pages: 'S. 2–3', revealed: 1, total: 3)],
      current: 0,
      solution: WorkedSolution(
        id: 'x',
        moduleId: 'm',
        problem: 'Aufgabe',
        detail: WorkDetail.normal,
        steps: const [WorkStep(title: 'Schritt', to: 'u = x^2')],
        createdAt: DateTime(2026),
      ),
      revealed: 1,
      focus: 0,
      pageLabel: 'Seite 3/6',
      formulas: const [LectureFormula(name: 'Regel', latex: 'a=b', page: 2)],
      freshFormulas: 1,
      coach: 'Weiter!',
      chat: const [(user: true, text: 'Warum?')],
      busy: true,
      busyText: 'Moment',
    );
    final back = LectureBoardState.fromMap(jsonDecode(jsonEncode(state.toMap())));
    expect(back.concepts.single.total, 3);
    expect(back.solution!.steps.single.to, 'u = x^2');
    expect(back.focus, 0);
    expect(back.formulas.single.page, 2);
    expect(back.chat.single.text, 'Warum?');
    expect(back.busy, isTrue);
  });
}
