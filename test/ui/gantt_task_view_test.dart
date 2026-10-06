import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/gantt_task.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/gantt_scheduler.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';

/// Zahnrad (Drehen 1, Fräsen 2) und Welle (Drehen 4) werden zur Baugruppe
/// montiert (2 Tage). Vorwärts ab Tag 1, Liefertermin Tag 10, Tage
/// einschließlich. Lösung: Zahnrad 1–3, Welle 1–4, Montage 5–6 – das Zahnrad
/// liegt 1 Tag.
Map<String, dynamic> _taskData() => {
      'kind': 'gantt',
      'direction': 'forward',
      'counting': 'inclusive',
      'start': 1,
      'due': 10,
      'items': [
        {
          'id': 'z',
          'name': 'Zahnrad',
          'operations': [
            {'name': 'Drehen', 'duration': 1},
            {'name': 'Fräsen', 'duration': 2},
          ],
        },
        {
          'id': 'w',
          'name': 'Welle',
          'operations': [
            {'name': 'Drehen', 'duration': 4},
          ],
        },
        {
          'id': 'b',
          'name': 'Baugruppe',
          'needs': ['z', 'w'],
          'operations': [
            {'name': 'Montage', 'duration': 2},
          ],
        },
      ],
      'questions': [
        {'item': 'b', 'ask': 'start'},
        {'item': 'b', 'ask': 'end'},
        {'item': 'z', 'ask': 'slack'},
      ],
    };

Flashcard _card() => Flashcard(
      id: 'g1',
      moduleId: 'm1',
      front: 'Terminiere die Baugruppe vorwärts.',
      back: '',
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      type: QuestionType.gantt,
      taskData: _taskData(),
    );

void main() {
  late List<({Grade? grade, bool? correct})> results;

  Future<void> pump(WidgetTester tester, {bool examMode = false, double width = 900}) async {
    tester.view.physicalSize = Size(width, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    results = [];
    final card = _card();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: QuestionAnswerView(
                key: ValueKey(card.id),
                card: card,
                isNew: false,
                examMode: examMode,
                onComplete: ({Grade? selfGrade, bool? isCorrect}) => results.add((grade: selfGrade, correct: isCorrect)),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
  }

  /// Sichtbare Tage wie in der Ansicht: Tag 1 bis Liefertermin + 2.
  const firstDay = 1, dayCount = 12;

  Future<void> place(WidgetTester tester, String key, int day) async {
    final track = find.byKey(ValueKey('gantt-track-$key'));
    await tester.ensureVisible(track);
    final rect = tester.getRect(track);
    final cw = rect.width / dayCount;
    await tester.tapAt(Offset(rect.left + (day - firstDay + 0.5) * cw, rect.center.dy));
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  Future<void> answer(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey('gantt-answer-$key')), text);
    await tester.pump();
  }

  test('Musterlösung der Testaufgabe', () {
    final task = GanttTask.fromMap(_taskData())!;
    final plan = GanttScheduler.plan(task);
    expect(plan.opStarts[ganttOpKey('z', 1)], 2);
    expect(plan.opStarts[ganttOpKey('b', 0)], 5);
    expect(plan.answer(const GanttQuestion(itemId: 'z', ask: GanttAsk.slack)), 1);
  });

  testWidgets('Balken setzen mit Sofort-Rückmeldung, Start/Ende aus dem Diagramm, alles richtig = gewusst', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('gantt-mode')), findsOneWidget);
    expect(find.text('0 von 4 Arbeitsgängen eingeplant'), findsOneWidget);

    await place(tester, 'z#0', 1);
    // Überlappt mit dem Drehen davor: sofort rot markiert.
    await place(tester, 'z#1', 1);
    expect(find.byIcon(Icons.cancel), findsWidgets);
    await tap(tester, 'gantt-right');
    expect(find.byIcon(Icons.cancel), findsNothing);

    await place(tester, 'w#0', 1);
    await place(tester, 'b#0', 5);
    expect(find.text('4 von 4 Arbeitsgängen eingeplant'), findsOneWidget);

    await tap(tester, 'gantt-fill');
    expect(find.widgetWithText(TextField, '5'), findsOneWidget);
    expect(find.widgetWithText(TextField, '6'), findsOneWidget);
    await answer(tester, 'z.slack', '1');

    await tap(tester, 'gantt-check');
    expect(find.text('Alles richtig'), findsOneWidget);
    expect(find.byKey(const ValueKey('gantt-how')), findsOneWidget);
    await tap(tester, 'gantt-next');
    expect(results, [(grade: null, correct: true)]);
  });

  testWidgets('Folgefehler: zu spät eingeplante Welle, Montage passt dazu – nach Lösung zeigen nicht gewusst', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Erst am Ende'));
    await tester.pump();

    await place(tester, 'z#0', 1);
    await place(tester, 'z#1', 2);
    await place(tester, 'w#0', 2); // einen Tag zu spät
    await place(tester, 'b#0', 6); // passt zur eigenen Welle
    await answer(tester, 'b.start', '6');
    await answer(tester, 'b.end', '7');
    await answer(tester, 'z.slack', '2');

    await tap(tester, 'gantt-check');
    expect(find.byKey(const ValueKey('gantt-result')), findsOneWidget);
    expect(find.textContaining('Folgefehler:', findRichText: true), findsWidgets);
    expect(find.text('Folgefehler'), findsWidgets); // an den Antworten
    expect(find.byIcon(Icons.arrow_circle_right), findsWidgets); // Montage-Balken: passt zur eigenen Welle
    expect(find.text('Alles richtig'), findsNothing);

    await tap(tester, 'gantt-reveal');
    expect(find.byKey(const ValueKey('gantt-how')), findsOneWidget);
    expect(find.text('richtige Lage'), findsOneWidget);
    expect(find.text('Lösung angesehen – zählt als „Nochmal“.'), findsOneWidget);
    await tap(tester, 'gantt-next');
    expect(results, [(grade: null, correct: false)]);
  });

  testWidgets('mit Tipp gelöst zählt als Schwer, auch nach Üben mit anderen Zahlen', (tester) async {
    await pump(tester);
    await tap(tester, 'gantt-hint');
    expect(find.byKey(const ValueKey('gantt-tip')), findsOneWidget);

    await place(tester, 'z#0', 1);
    await place(tester, 'z#1', 2);
    await place(tester, 'w#0', 1);
    await place(tester, 'b#0', 5);
    await answer(tester, 'b.start', '5');
    await answer(tester, 'b.end', '6');
    await answer(tester, 'z.slack', '1');
    await tap(tester, 'gantt-check');
    expect(find.text('Alles richtig'), findsOneWidget);
    expect(find.textContaining('zählt als „Schwer“'), findsOneWidget);

    await tap(tester, 'gantt-variant');
    expect(find.text('0 von 4 Arbeitsgängen eingeplant'), findsOneWidget);
    await tap(tester, 'gantt-reveal');
    await tap(tester, 'gantt-next');
    // Gewertet wird der erste Durchgang.
    expect(results, [(grade: Grade.hard, correct: true)]);
  });

  testWidgets('Probeklausur: keine Hilfen, Abgabe wertet die Antworten', (tester) async {
    await pump(tester, examMode: true);
    expect(find.byKey(const ValueKey('gantt-mode')), findsNothing);
    expect(find.byKey(const ValueKey('gantt-hint')), findsNothing);
    await answer(tester, 'b.start', '5');
    await answer(tester, 'b.end', '6');
    await answer(tester, 'z.slack', '1');
    await tap(tester, 'gantt-submit');
    expect(results, [(grade: null, correct: true)]);
  });

  testWidgets('breite Ansicht (Desktop): Aufgabe links, Diagramm rechts', (tester) async {
    await pump(tester, width: 1400);
    final chart = tester.getRect(find.byKey(const ValueKey('gantt-chart')));
    final answers = tester.getRect(find.byKey(const ValueKey('gantt-answers')));
    expect(answers.right, lessThan(chart.left));
  });
}
