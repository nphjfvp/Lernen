import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lecture_walk.dart';
import 'package:lernen/models/worked_solution.dart';

Map<String, dynamic> _step(String title, int page, {List<Map<String, String>> formulas = const []}) => {
  'title': title,
  'say': '$title – siehe Seite $page.',
  'to': 'x = $page',
  'page': page,
  'formulas': formulas,
};

const _rule = {'name': 'Substitutionsregel', 'latex': r"\int f(g(x))g'(x)\,dx = \int f(u)\,du"};

void main() {
  // Konzept auf den Seiten 2, 3 und (verteilt) 7.
  final task = LectureTask.fromMap(
    {
      'title': 'DGL',
      'problem': r"Löse $y' = (x+y)^2$, $y(0) = 0$.",
      'answer': r'$y = \tan x - x$',
      'steps': [
        _step('Substitution wählen', 2, formulas: [_rule]),
        _step('Einsetzen', 4),
        _step('Trennen', 3, formulas: [_rule]),
        _step('Rücksubstitution', 99),
      ],
    },
    pages: [2, 3, 7],
  )!;

  test('Aufgabe: Seiten rasten auf die des Konzepts ein und fallen nie', () {
    expect([for (final s in task.steps) s.page], [2, 7, 7, 7]);
    expect(task.steps.first.formulas.single.name, 'Substitutionsregel');
    expect(LectureTask.fromMap({'problem': '', 'steps': []}), isNull);
    final worked = task.toWorked(id: 'x', moduleId: 'm', fallbackTitle: 'Substitution');
    expect(worked.steps, hasLength(4));
    expect(worked.problem, contains('y(0)'));
  });

  test('Konzepte: verteilte Seiten, aufgeräumt, Seitenangabe', () {
    final concepts = LectureConcept.tidy([
      const LectureConcept(title: 'Variation der Konstanten', pages: [9, 10, 4]),
      LectureConcept.fromMap({
        'title': 'Substitution',
        'pages': [3, 4, 5, 9, 40],
      })!,
      LectureConcept.fromMap({'title': 'Alt', 'from': 6, 'to': 8})!,
      const LectureConcept(title: 'substitution', pages: [1]),
    ], 12);
    expect([for (final c in concepts) c.title], ['Substitution', 'Variation der Konstanten', 'Alt']);
    expect(concepts.first.pages, [3, 4, 5, 9]);
    expect(concepts.first.pagesLabel, 'S. 3–5, 9');
    expect(concepts.last.pages, [6, 7, 8]);
  });

  test('Seite für Seite: Konzepte auf der Seite, Tafel wechselt mit, Formeln ohne Doppelte', () {
    final other = LectureTask.fromMap(
      {
        'problem': 'Andere Aufgabe',
        'steps': [_step('A', 4), _step('B', 5)],
      },
      pages: [4, 5],
    )!;
    var walk = LectureWalk(
      materialId: 'pdf',
      moduleId: 'm',
      title: 'DGL',
      pageCount: 8,
      concepts: const [
        LectureConcept(title: 'Substitution', pages: [2, 3, 7]),
        LectureConcept(title: 'Trennen', pages: [3, 4, 5]),
      ],
      tasks: {0: task, 1: other},
    );
    expect(walk.conceptsOn(1), isEmpty);
    expect(walk.conceptsOn(3), [0, 1]);
    expect(walk.prepared, isTrue);

    walk = walk.withPage(2);
    expect(walk.current, 0);
    expect(walk.revealedCount(0), 1);
    expect(walk.formulas.single.page, 2);
    walk = walk.withPage(3);
    expect(walk.current, 0, reason: 'bleibt beim Konzept, das auch hier erklärt wird');
    walk = walk.withPage(4);
    expect(walk.current, 1, reason: 'hier geht die Aufgabe zu „Trennen“ weiter');
    expect(walk.revealedCount(1), 1);
    walk = walk.withPage(7);
    expect(walk.current, 0);
    expect(walk.revealedCount(0), 4);
    expect(walk.revealedCount(1), 2);
    expect(walk.formulas, hasLength(1), reason: 'dieselbe Formel nur einmal');

    // Zurückblättern deckt nichts wieder zu.
    walk = walk.withPage(2);
    expect(walk.maxPage, 7);
    expect(walk.revealedCount(0), 4);
    expect(walk.withPage(99).finished, isTrue);

    // An der Tafel feiner aufgeteilt: die Teile behalten die Seite.
    final refined = walk.tasks[1]!.withRefined(0, const [
      WorkStep(title: 'A1', to: 'a'),
      WorkStep(title: 'A2', to: 'b'),
    ]);
    expect([for (final s in refined.steps) s.page], [4, 4, 5]);

    final back = LectureWalk.fromMap(
      walk.copyWith(attempts: {0: const LectureAttempt(solved: false, step: 1, explain: 'Hier.')}).toMap(),
    )!;
    expect(back.concepts.first.pages, [2, 3, 7]);
    expect(back.tasks[0]!.steps[1].page, 7);
    expect(back.current, walk.current);
    expect(back.attempts[0]!.explain, 'Hier.');
    expect(LectureWalk.fromMap({...back.toMap(), 'version': 1}), isNull, reason: 'alter Stand wird neu vorbereitet');
  });
}
