import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:provider/provider.dart';

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

Flashcard _card({
  QuestionType type = QuestionType.flashcard,
  String front = 'Frage?',
  String back = 'Antwort',
  List<QuizOption>? options,
  String? correctText,
  List<String>? blanks,
  List<DragPair>? dragPairs,
}) {
  return Flashcard(
    id: 'q1',
    moduleId: 'm1',
    front: front,
    back: back,
    createdAt: DateTime(2026, 1, 1),
    due: DateTime(2026, 1, 1),
    type: type,
    options: options,
    correctText: correctText,
    blanks: blanks,
    dragPairs: dragPairs,
  );
}

Widget _harness(Flashcard card, void Function({Grade? selfGrade, bool? isCorrect}) onComplete) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: QuestionAnswerView(key: ValueKey(card.id), card: card, isNew: false, onComplete: onComplete),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('QuestionAnswerView – flashcard', () {
    testWidgets('zeigt Vorderseite, deckt nach Tippen die Rückseite auf, meldet Selbstbewertung', (tester) async {
      Grade? reportedGrade;
      await tester.pumpWidget(_harness(
        _card(),
        ({selfGrade, isCorrect}) => reportedGrade = selfGrade,
      ));

      expect(find.text('Frage?'), findsOneWidget);
      expect(find.text('Antwort'), findsNothing);

      await tester.tap(find.text('Frage?'));
      await tester.pumpAndSettle();

      expect(find.text('Antwort'), findsOneWidget);
      expect(find.text('Gut'), findsOneWidget);

      await tester.tap(find.text('Gut'));
      await tester.pumpAndSettle();

      expect(reportedGrade, Grade.good);
    });
  });

  group('QuestionAnswerView – single_choice', () {
    testWidgets('richtige Auswahl -> Prüfen -> Weiter meldet isCorrect true', (tester) async {
      bool? reportedCorrect;
      final card = _card(
        type: QuestionType.singleChoice,
        options: const [
          QuizOption(text: 'Paris', isCorrect: true),
          QuizOption(text: 'Lyon', isCorrect: false),
        ],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));

      await tester.tap(find.text('Paris'));
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();

      expect(find.text('Richtig!'), findsOneWidget);

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(reportedCorrect, isTrue);
    });

    testWidgets('falsche Auswahl zeigt die richtige Antwort und meldet isCorrect false', (tester) async {
      bool? reportedCorrect;
      final card = _card(
        type: QuestionType.singleChoice,
        options: const [
          QuizOption(text: 'Paris', isCorrect: true),
          QuizOption(text: 'Lyon', isCorrect: false),
        ],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));

      await tester.tap(find.text('Lyon'));
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();

      expect(find.text('Nicht ganz.'), findsOneWidget);
      expect(find.textContaining('Paris'), findsWidgets);

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(reportedCorrect, isFalse);
    });

    testWidgets('Prüfen-Button ist erst nach einer Auswahl aktiv', (tester) async {
      final card = _card(
        type: QuestionType.singleChoice,
        options: const [
          QuizOption(text: 'Paris', isCorrect: true),
          QuizOption(text: 'Lyon', isCorrect: false),
        ],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) {}));

      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Prüfen'));
      expect(button.onPressed, isNull);
    });
  });

  group('QuestionAnswerView – multiple_choice', () {
    testWidgets('nur die exakt richtige Menge zählt als korrekt', (tester) async {
      bool? reportedCorrect;
      final card = _card(
        type: QuestionType.multipleChoice,
        options: const [
          QuizOption(text: 'A', isCorrect: true),
          QuizOption(text: 'B', isCorrect: false),
          QuizOption(text: 'C', isCorrect: true),
        ],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));

      await tester.tap(find.text('A'));
      await tester.tap(find.text('C'));
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(reportedCorrect, isTrue);
    });
  });

  group('QuestionAnswerView – free_text', () {
    testWidgets('toleriert kleine Tippfehler dank AnswerChecker', (tester) async {
      bool? reportedCorrect;
      final card = _card(type: QuestionType.freeText, correctText: 'Photosynthese');
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));

      await tester.enterText(find.byType(TextField), 'Photosyntese');
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(reportedCorrect, isTrue);
    });
  });

  group('QuestionAnswerView – fill_blank', () {
    testWidgets('alle Lücken müssen stimmen', (tester) async {
      bool? reportedCorrect;
      final card = _card(
        type: QuestionType.fillBlank,
        front: 'Die Hauptstadt von ___ ist ___.',
        blanks: const ['Frankreich', 'Paris'],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'Frankreich');
      await tester.enterText(fields.at(1), 'Berlin');
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(reportedCorrect, isFalse);
    });
  });

  group('QuestionAnswerView – drag_drop', () {
    testWidgets('richtig zugeordnete Paare gelten als korrekt', (tester) async {
      bool? reportedCorrect;
      final card = _card(
        type: QuestionType.dragDrop,
        dragPairs: const [DragPair(source: 'Hund', target: 'Tier')],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));

      final source = find.text('Hund');
      final target = find.text('Tier');
      await tester.drag(source, tester.getCenter(target) - tester.getCenter(source));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(reportedCorrect, isTrue);
    });
  });

  group('QuestionAnswerView – KI-Hilfe', () {
    final choiceCard = _card(
      type: QuestionType.singleChoice,
      options: const [QuizOption(text: 'A', isCorrect: true), QuizOption(text: 'B', isCorrect: false)],
    );

    testWidgets('ohne API-Key gibt es weder Tipp noch Erklärung', (tester) async {
      await tester.pumpWidget(_harness(choiceCard, ({selfGrade, isCorrect}) {}));
      expect(find.text('Tipp'), findsNothing);
      await tester.tap(find.text('B'));
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      expect(find.text('Erklär mir das'), findsNothing);
    });

    testWidgets('mit API-Key: Tipp vor dem Prüfen, Erklärung danach', (tester) async {
      await tester.pumpWidget(ChangeNotifierProvider<SettingsRepository>(
        create: (_) => _SettingsWithKey(),
        child: _harness(choiceCard, ({selfGrade, isCorrect}) {}),
      ));
      expect(find.text('Tipp'), findsOneWidget);
      await tester.tap(find.text('B'));
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      expect(find.text('Tipp'), findsNothing);
      expect(find.text('Erklär mir das'), findsOneWidget);
    });
  });

  group('QuestionAnswerView – Probeklausur-Modus', () {
    testWidgets('gibt ohne Feedback direkt weiter und zeigt keine Hilfe', (tester) async {
      bool? reported;
      final card = _card(
        type: QuestionType.singleChoice,
        options: const [QuizOption(text: 'A', isCorrect: true), QuizOption(text: 'B', isCorrect: false)],
      );
      await tester.pumpWidget(ChangeNotifierProvider<SettingsRepository>(
        create: (_) => _SettingsWithKey(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: QuestionAnswerView(
                    card: card,
                    isNew: false,
                    examMode: true,
                    onComplete: ({selfGrade, isCorrect}) => reported = isCorrect,
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      expect(find.text('Tipp'), findsNothing);
      await tester.tap(find.text('B'));
      await tester.pump();
      await tester.tap(find.text('Antwort abgeben'));
      await tester.pumpAndSettle();
      expect(reported, isFalse);
      expect(find.text('Nicht ganz.'), findsNothing);
    });
  });
}
