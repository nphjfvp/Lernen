import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lecture_walk.dart';

Map<String, dynamic> _step(String title, int page, {List<Map<String, String>> formulas = const []}) => {
  'title': title,
  'say': '$title – siehe Seite $page.',
  'to': 'x = $page',
  'page': page,
  'formulas': formulas,
};

void main() {
  final task = LectureTask.fromMap(
    {
      'title': 'Integral',
      'problem': r'Berechne $\int 2x\cos(x^2)\,dx$.',
      'answer': r'$\sin(x^2) + C$',
      'steps': [
        _step(
          'Substitution wählen',
          2,
          formulas: [
            {'name': 'Substitutionsregel', 'latex': r"\int f(g(x))g'(x)\,dx = \int f(u)\,du"},
          ],
        ),
        _step('Einsetzen', 4),
        _step(
          'Zurück',
          3,
          formulas: [
            {'name': 'Substitutionsregel', 'latex': r"\int f(g(x))g'(x)\,dx = \int f(u)\,du"},
          ],
        ),
        _step('Viel zu spät', 99),
      ],
    },
    from: 2,
    to: 5,
  )!;

  test('Aufgabe: Seiten innerhalb des Themas und nie fallend', () {
    expect([for (final s in task.steps) s.page], [2, 4, 4, 5]);
    expect(task.steps.first.formulas.single.name, 'Substitutionsregel');
    expect(LectureTask.fromMap({'problem': '', 'steps': []}), isNull);
  });

  test('Themen aufräumen: sortiert, in den Seiten, ohne Überlappung', () {
    final topics = LectureTopic.tidy([
      const LectureTopic(title: 'B', from: 6, to: 9),
      const LectureTopic(title: 'A', from: 2, to: 7),
      const LectureTopic(title: 'C', from: 8, to: 40),
      const LectureTopic(title: 'D', from: 3, to: 4),
    ], 12);
    expect([for (final t in topics) '${t.title} ${t.from}-${t.to}'], ['A 2-7', 'B 8-9', 'C 10-12']);
  });

  test('Seite für Seite: Thema, aufgedeckte Schritte, Formelsammlung ohne Doppelte', () {
    var walk = LectureWalk(
      materialId: 'pdf',
      moduleId: 'm',
      title: 'Integration',
      pageCount: 8,
      topics: const [
        LectureTopic(title: 'Substitution', from: 2, to: 5),
        LectureTopic(title: 'Partielle Integration', from: 6, to: 8),
      ],
      tasks: {0: task},
    );
    expect(walk.topicAt(1), -1, reason: 'Titelseite');
    expect(walk.topicAt(3), 0);
    expect(walk.topicAt(7), 1);
    expect(walk.revealedCount(0), 0);

    walk = walk.withPage(2);
    expect(walk.revealedCount(0), 1);
    expect(walk.formulas.single.page, 2);
    walk = walk.withPage(3);
    expect(walk.revealedCount(0), 1, reason: 'Schritt 2 braucht Seite 4');
    walk = walk.withPage(4);
    expect(walk.revealedCount(0), 3);
    expect(walk.formulas, hasLength(1), reason: 'dieselbe Formel nur einmal');

    // Zurückblättern deckt nichts wieder zu.
    walk = walk.withPage(2);
    expect(walk.page, 2);
    expect(walk.maxPage, 4);
    expect(walk.revealedCount(0), 3);
    expect(walk.finished, isFalse);
    expect(walk.withPage(99).finished, isTrue);

    final back = LectureWalk.fromMap(
      walk.copyWith(attempts: {0: const LectureAttempt(solved: false, step: 1, explain: 'Hier.')}).toMap(),
    )!;
    expect(back.topics, hasLength(2));
    expect(back.tasks[0]!.steps, hasLength(4));
    expect(back.tasks[0]!.steps[1].page, 4);
    expect(back.formulas.single.name, 'Substitutionsregel');
    expect(back.maxPage, 4);
    expect(back.attempts[0]!.step, 1);
    expect(back.attempts[0]!.explain, 'Hier.');
  });
}
