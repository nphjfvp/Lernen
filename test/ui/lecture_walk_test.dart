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
import 'package:sembast/sembast_memory.dart';

const _pages = [
  'Integrationsmethoden – Vorlesung 5',
  'Substitution: Idee – innere Funktion u = g(x)',
  'Substitutionsregel und du = g\'(x) dx',
  'Beispiel Substitution, Rücksubstitution',
  'Partielle Integration: Produktregel rückwärts',
  'Partielle Integration: Beispiele',
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
        'formulas': [
          if (i == 0 && formula.isNotEmpty)
            {'name': formula, 'latex': r'\int f(g(x))g(x)\,dx', 'note': 'Kettenregel rückwärts'},
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
    LectureBoardView.phaseDelay = const Duration(milliseconds: 5);
    LectureWalkScreen.loadHook = (_) async => (bytes: null, pageTexts: _pages);
    LectureWalkScreen.aiFactory = () => AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((r) async {
        final messages = (jsonDecode(r.body) as Map)['messages'] as List;
        final system = '${messages[0]['content']}';
        final user = '${messages[1]['content']}';
        asked.add(user);
        if (system.contains('THEMEN')) {
          return _reply({
            'topics': [
              {'title': 'Substitution', 'from': 2, 'to': 4},
              {'title': 'Partielle Integration', 'from': 5, 'to': 6},
            ],
          });
        }
        if (user.contains('AUFTRAG: Erfinde')) {
          return user.contains('Thema: Substitution')
              ? _reply(_task(r'Berechne $\int 2x\cos(x^2)\,dx$.', [2, 3, 4], formula: 'Substitutionsregel'))
              : _reply(_task(r'Berechne $\int x e^x\,dx$.', [5, 6]));
        }
        if (system.contains('Lösungsversuch')) {
          return _reply({
            'solved': false,
            'feedback': 'Beim Ersetzen von dx fehlt der Faktor.',
            'step': 2,
            'explain': r'Aus $u = x^2$ folgt $du = 2x\,dx$ – genau das steht auf Seite 3.',
          });
        }
        return _reply(r'Weil $u = x^2$ die innere Funktion ist.');
      }),
    );
  });

  tearDown(() {
    LectureWalkScreen.loadHook = null;
    LectureWalkScreen.aiFactory = null;
  });

  testWidgets('Vorlesung mit Aufgabe: Seite für Seite weiterrechnen, Formeln, Fragen, selbst lösen, Haken-Seite', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
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

    // Titelseite: Themen erkannt, erstes Thema kommt noch.
    expect(find.textContaining('Blättere weiter'), findsOneWidget);
    expect(find.byKey(const ValueKey('lecture-page-text')), findsOneWidget);

    // Seite 2: neues Thema → Aufgabe, erster Schritt und neue Formel an der Tafel.
    await tester.tap(find.byKey(const ValueKey('lecture-next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Los geht’s'), findsOneWidget);
    expect(find.textContaining('Thema 1/2 · Substitution'), findsOneWidget);
    expect(find.byKey(const ValueKey('lecture-new-formulas')), findsOneWidget);
    expect(find.textContaining('Formelsammlung (1)'), findsOneWidget);

    // Seite 3: weiter mit unserer Aufgabe.
    await tester.tap(find.byKey(const ValueKey('lecture-next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Okay, lass uns mit unserer Aufgabe weitermachen'), findsOneWidget);
    expect(find.textContaining('Schritt 2.'), findsOneWidget);
    expect(find.byKey(const ValueKey('lecture-new-formulas')), findsNothing);

    // Frage zur Formel.
    await tester.ensureVisible(find.byKey(const ValueKey('lecture-formula-ask-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lecture-formula-ask-0')));
    await tester.pumpAndSettle();
    expect(asked.last, contains('Substitutionsregel'));
    expect(find.textContaining('innere Funktion ist'), findsOneWidget);

    // Seite 4: gelöst; Seite 5: neues Thema mit neuer Aufgabe; Seite 6: einmal durch.
    await tester.tap(find.byKey(const ValueKey('lecture-next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Damit ist sie gelöst'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lecture-next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Neues Thema: „Partielle Integration“'), findsOneWidget);
    expect(find.byKey(const ValueKey('lecture-self-solve')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lecture-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lecture-self-solve')), findsOneWidget);

    final saved = (await tester.runAsync(() => repo.load('pdf1')))!;
    expect(saved.tasks.keys, containsAll([0, 1]));
    expect(saved.maxPage, 6);
    expect(saved.formulas.single.name, 'Substitutionsregel');

    // Selbst lösen: Haken bei Schritt 2 → Seite 3, dort genau erklärt.
    await tester.tap(find.byKey(const ValueKey('lecture-self-solve')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('self-topic-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('self-answer')), 'u = x^2, dann sin(u)');
    await tester.tap(find.byKey(const ValueKey('self-check')));
    await tester.pumpAndSettle();
    expect(find.text('Noch nicht ganz.'), findsOneWidget);
    expect(find.text('Zu Seite 3 – dort genau erklären'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('self-jump')));
    await tester.pumpAndSettle();
    expect(find.text('Seite 3/6 · Substitution'), findsOneWidget);
    expect(find.textContaining('Hier hakt es – auf Seite 3'), findsOneWidget);
    expect(find.textContaining('genau das steht auf Seite 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('lecture-visual')), findsOneWidget);
    expect((await tester.runAsync(() => repo.load('pdf1')))!.attempts[0]!.step, 1);
  });

  test('Tafel-Stand übersteht den Weg ins eigene Fenster', () {
    const state = LectureBoardState(
      topicTitle: 'Substitution',
      topicNumber: 1,
      topicCount: 2,
      pageLabel: 'Seite 3/6',
      problem: r'$\int 2x\cos(x^2)\,dx$',
      steps: [WorkStep(title: 'Schritt', to: 'u = x^2')],
      revealed: 1,
      current: 0,
      formulas: [LectureFormula(name: 'Regel', latex: 'a=b', page: 2)],
      freshFormulas: 1,
      coach: 'Weiter!',
      chat: [(user: true, text: 'Warum?')],
      busy: true,
      busyText: 'Moment',
    );
    final back = LectureBoardState.fromMap(jsonDecode(jsonEncode(state.toMap())));
    expect(back.topicTitle, 'Substitution');
    expect(back.steps.single.to, 'u = x^2');
    expect(back.current, 0);
    expect(back.formulas.single.page, 2);
    expect(back.chat.single.text, 'Warum?');
    expect(back.busy, isTrue);
  });
}
