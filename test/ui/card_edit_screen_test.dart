import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
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
