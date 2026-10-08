import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/bom_task.dart';
import 'package:lernen/models/crystal_task.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/gantt_task.dart';
import 'package:lernen/models/step_task.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/flashcards/card_edit_screen.dart';
import 'package:lernen/ui/flashcards/flashcard_list_screen.dart';

Flashcard _card(QuestionType type, {List<QuizOption>? options, List<String>? blanks, String front = 'Frage?'}) =>
    Flashcard(
      id: 'c1',
      moduleId: 'm1',
      front: front,
      back: '',
      createdAt: DateTime(2026, 9, 27),
      due: DateTime(2026, 9, 27),
      type: type,
      options: options,
      blanks: blanks,
    ).copyWithReview(
      due: DateTime(2026, 10, 1),
      stability: 3,
      difficulty: 5,
      elapsedDays: 1,
      scheduledDays: 3,
      reps: 4,
      lapses: 0,
      state: 'review',
      lastReview: DateTime(2026, 9, 27),
      masteryBox: 2,
    );

/// Öffnet den Editor und liefert, was er beim Speichern zurückgibt.
Future<Flashcard? Function()> _open(WidgetTester tester, Flashcard card) async {
  Flashcard? result;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => result = await showCardEditor(context, card),
        child: const Text('Öffnen'),
      ),
    ),
  ));
  await tester.tap(find.text('Öffnen'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  testWidgets('Single-Choice: falsch markierte Lösung korrigieren, Lernstand bleibt', (tester) async {
    final card = _card(QuestionType.singleChoice, options: const [
      QuizOption(text: 'Paris', isCorrect: false),
      QuizOption(text: 'Lyon', isCorrect: true),
    ]);
    final result = await _open(tester, card);

    await tester.tap(find.byKey(const ValueKey('card-edit-correct-0')));
    await tester.enterText(find.byKey(const ValueKey('card-edit-front')), 'Hauptstadt von Frankreich?');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final edited = result()!;
    expect(edited.front, 'Hauptstadt von Frankreich?');
    expect(edited.options!.map((o) => o.isCorrect), [true, false]);
    expect(edited.reps, 4);
    expect(edited.masteryBox, 2);
    expect(edited.type, QuestionType.singleChoice);
  });

  testWidgets('Multiple-Choice ohne richtige Option wird nicht gespeichert', (tester) async {
    final card = _card(QuestionType.multipleChoice, options: const [
      QuizOption(text: 'A', isCorrect: true),
      QuizOption(text: 'B', isCorrect: false),
    ]);
    final result = await _open(tester, card);

    await tester.tap(find.byKey(const ValueKey('card-edit-correct-0')));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Mindestens eine Option als richtig markieren.'), findsOneWidget);
    expect(result(), isNull);
  });

  testWidgets('Lückentext: je "___" ein Lösungsfeld', (tester) async {
    final card = _card(QuestionType.fillBlank, front: 'Die ___ ist das Kraftwerk der Zelle.', blanks: const ['Mitochondrie']);
    final result = await _open(tester, card);

    expect(find.byKey(const ValueKey('card-edit-blank-0')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('card-edit-front')),
      'Die ___ ist das Kraftwerk, der ___ die Steuerzentrale.',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('card-edit-blank-1')), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Für jede Lücke eine Lösung eintragen.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('card-edit-blank-0')), 'Mitochondrie; Mitochondrium');
    await tester.enterText(find.byKey(const ValueKey('card-edit-blank-1')), 'Zellkern');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(result()!.blanks, ['Mitochondrie; Mitochondrium', 'Zellkern']);
  });

  testWidgets('Tabelle: Zelle umschalten, Lösung eintragen, Zeile anhängen', (tester) async {
    final card = Flashcard(
      id: 't1',
      moduleId: 'm1',
      front: 'Einheiten ergänzen',
      back: '',
      createdAt: DateTime(2026, 9, 27),
      due: DateTime(2026, 9, 27),
      type: QuestionType.table,
      tableRows: const [
        [QuestionTableCell(text: 'Größe'), QuestionTableCell(text: 'Einheit')],
        [QuestionTableCell(text: 'Kraft'), QuestionTableCell(text: 'N', given: false)],
      ],
    );
    final result = await _open(tester, card);

    await tester.enterText(find.byKey(const ValueKey('card-edit-table-1-1')), 'Newton; N');
    await tester.tap(find.widgetWithText(TextButton, 'Zeile').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('card-edit-table-2-0')), 'Masse');
    await tester.enterText(find.byKey(const ValueKey('card-edit-table-2-1')), 'kg');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final rows = result()!.tableRows!;
    expect(rows.length, 3);
    expect(rows[1][1].text, 'Newton; N');
    expect(rows[1][1].given, isFalse);
    expect(rows[2].map((c) => c.text), ['Masse', 'kg']);
    // Neue Zeilen: erste Spalte vorgegeben, der Rest zum Ausfüllen.
    expect(rows[2].map((c) => c.given), [true, false]);
  });

  testWidgets('Tabelle ohne auszufüllende Zelle wird nicht gespeichert', (tester) async {
    final card = Flashcard(
      id: 't1',
      moduleId: 'm1',
      front: 'Tabelle',
      back: '',
      createdAt: DateTime(2026, 9, 27),
      due: DateTime(2026, 9, 27),
      type: QuestionType.table,
      tableRows: const [
        [QuestionTableCell(text: 'a'), QuestionTableCell(text: 'b', given: false)],
      ],
    );
    final result = await _open(tester, card);

    await tester.tap(find.byKey(const ValueKey('card-edit-table-toggle-0-1')));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Mindestens eine Zelle zum Ausfüllen (mit Lösung) anlegen.'), findsOneWidget);
    expect(result(), isNull);
  });

  testWidgets('Terminierung bearbeiten: Werte ändern, die App schreibt den Lösungsweg neu', (tester) async {
    final card = _card(QuestionType.gantt, front: 'Terminiere vorwärts.').copyWithContent(taskData: {
      'kind': 'gantt',
      'start': 1,
      'items': [
        {
          'id': 'z',
          'name': 'Zahnrad',
          'operations': [
            {'name': 'Drehen', 'duration': 2},
          ],
        },
      ],
      'questions': [
        {'item': 'z', 'ask': 'end'},
      ],
    });
    final result = await _open(tester, card);
    expect(find.byKey(const ValueKey('gantt-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('card-edit-back')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('gantt-edit-start-inc')));
    await tester.tap(find.byKey(const ValueKey('gantt-edit-start-inc')));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final edited = result()!;
    expect(GanttTask.fromMap(edited.taskData)!.start, 2);
    expect(edited.back, contains('Zahnrad'));
    expect(edited.reps, 4); // Lernstand bleibt
  });

  testWidgets('Rechenweg bearbeiten: erwartete Antwort ändern', (tester) async {
    final card = _card(QuestionType.steps, front: 'Integriere 2x.').copyWithContent(taskData: {
      'kind': 'steps',
      'steps': [
        {
          'title': 'Integrieren',
          'fields': [
            {'label': 'F(x) =', 'answer': 'x^2', 'variables': ['x']},
          ],
        },
      ],
    });
    final result = await _open(tester, card);
    expect(find.byKey(const ValueKey('step-verify')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('step-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('step-edit-answer-0-0')), 'x^2 + C');
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(StepTask.fromMap(result()!.taskData)!.finalField!.answer, 'x^2 + C');
  });

  testWidgets('Kristallgitter bearbeiten: unsichere Indizes werden bestätigt, ohne Erklärung schreibt die App den Lösungsweg', (tester) async {
    final card = _card(QuestionType.crystal, front: 'Zeichne die Richtung ein.').copyWithContent(taskData: {
      'kind': 'crystal',
      'lattice': 'sc',
      'parts': [
        {'kind': 'direction', 'indices': [1, 1, 1], 'uncertain': true},
      ],
    });
    final result = await _open(tester, card);
    expect(find.byKey(const ValueKey('crystal-edit-lattice')), findsOneWidget);
    expect(find.byKey(const ValueKey('crystal-preview')), findsOneWidget);
    await tester.tap(find.text('kfz'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final edited = result()!;
    final task = CrystalTask.fromMap(edited.taskData)!;
    expect(task.lattice, CrystalLattice.fcc);
    expect(task.hasUncertain, isFalse);
    expect(edited.back, contains('Starte bei (0, 0, 0)'));
    expect(edited.reps, 4);
  });

  testWidgets('Stückliste bearbeiten: Baum als Text ändern, die App schreibt die Musterlösung', (tester) async {
    final card = _card(QuestionType.bom, front: 'Erstellen Sie die Mengenübersichtsstückliste.').copyWithContent(taskData: {
      'kind': 'bom',
      'root': {
        'nr': '10',
        'name': 'Tisch',
        'children': [
          {'nr': '20', 'name': 'Bein', 'qty': 4},
        ],
      },
      'parts': [
        {'list': 'overview'},
      ],
    });
    final result = await _open(tester, card);
    expect(find.byKey(const ValueKey('bom-preview')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('bom-edit-outline')), '0; 10; Tisch\n1; 20; Bein; 3\n1; 30; Platte; 1');
    await tester.pump();
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    final edited = result()!;
    expect(BomTask.fromMap(edited.taskData)!.root.children.map((c) => c.number), ['20', '30']);
    expect(edited.back, 'Mengenübersichtsstückliste\n20 | Bein | 3\n30 | Platte | 1');
  });

  testWidgets('Kristallgitter: nicht zeichenbare Ebene wird nicht gespeichert', (tester) async {
    final card = _card(QuestionType.crystal, front: 'Zeichne die Ebene ein.').copyWithContent(taskData: {
      'kind': 'crystal',
      'parts': [
        {'kind': 'plane', 'indices': [1, 2, 3]},
      ],
    });
    final result = await _open(tester, card);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.textContaining('besser „Ebene ablesen“'), findsWidgets);
    expect(result(), isNull);
  });

  group('Kartensuche', () {
    final card = Flashcard(
      id: 'c1',
      moduleId: 'm1',
      front: 'Was macht das Mitochondrium?',
      back: '',
      createdAt: DateTime(2026, 9, 27),
      due: DateTime(2026, 9, 27),
      type: QuestionType.singleChoice,
      options: const [
        QuizOption(text: 'Energie (ATP) bereitstellen', isCorrect: true),
        QuizOption(text: 'Proteine falten', isCorrect: false),
      ],
    );

    test('findet Wörter in Frage und Optionen, unabhängig von Reihenfolge und Schreibweise', () {
      expect(flashcardMatchesQuery(card, ''), isTrue);
      expect(flashcardMatchesQuery(card, 'mitochondrium'), isTrue);
      expect(flashcardMatchesQuery(card, 'atp MITOCHONDRIUM'), isTrue);
      expect(flashcardMatchesQuery(card, 'Zellkern'), isFalse);
    });
  });
}
