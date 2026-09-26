import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

http.Response _chatResponse(Object json) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': jsonEncode(json)},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

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

    final cellCard = _card(
      type: QuestionType.fillBlank,
      front: 'Die ___ liefert ___.',
      blanks: const ['Mitochondrium', 'ATP'],
    );

    Future<void> answerWithAi(WidgetTester tester, Object aiVerdict, List<String> answers,
        {required void Function(bool?) onReported, void Function(String)? onRequest}) async {
      final client = MockClient((request) async {
        onRequest?.call(request.body);
        return _chatResponse(aiVerdict);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(ChangeNotifierProvider<SettingsRepository>(
          create: (_) => _SettingsWithKey(),
          child: _harness(cellCard, ({selfGrade, isCorrect}) => onReported(isCorrect)),
        ));
        final fields = find.byType(TextField);
        for (var i = 0; i < answers.length; i++) {
          await tester.enterText(fields.at(i), answers[i]);
        }
        await tester.pump();
        await tester.tap(find.text('Prüfen'));
        await tester.pumpAndSettle();
      }, () => client);
    }

    testWidgets('KI-Zweitmeinung: anderer richtiger Begriff zählt, Lösung wird angezeigt', (tester) async {
      bool? reported;
      String? request;
      await answerWithAi(
        tester,
        {
          'correct': [true, true],
        },
        ['Mitochondrium', 'Adenosintriphosphat'],
        onReported: (v) => reported = v,
        onRequest: (body) => request = body,
      );

      expect(request, contains('Adenosintriphosphat'));
      expect(find.text('Richtig!'), findsOneWidget);
      expect(find.text('Lösung: ATP'), findsOneWidget); // korrekte Schreibweise sichtbar
      expect(find.text('Lösung: Mitochondrium'), findsNothing); // exakt getroffen
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(reported, isTrue);
    });

    testWidgets('KI kann eine lokal richtige Lücke nicht verwerfen, falsche bleiben falsch', (tester) async {
      bool? reported;
      await answerWithAi(
        tester,
        {
          'correct': [false, false],
        },
        ['Mitochondrium', 'Glukose'],
        onReported: (v) => reported = v,
      );

      expect(find.text('Nicht ganz.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget); // Lücke 1 bleibt richtig
      expect(find.byIcon(Icons.cancel), findsWidgets);
      expect(find.text('Lösung: ATP'), findsOneWidget);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(reported, isFalse);
    });

    testWidgets('alles lokal richtig: keine KI-Anfrage', (tester) async {
      var requests = 0;
      await answerWithAi(
        tester,
        {
          'correct': [false, false],
        },
        ['Mitochondrium', 'atp'],
        onReported: (_) {},
        onRequest: (_) => requests++,
      );
      expect(requests, 0);
      expect(find.text('Richtig!'), findsOneWidget);
    });

    testWidgets('KI nicht erreichbar: das lokale Ergebnis zählt', (tester) async {
      final client = MockClient((request) async => throw http.ClientException('offline'));
      await http.runWithClient(() async {
        await tester.pumpWidget(ChangeNotifierProvider<SettingsRepository>(
          create: (_) => _SettingsWithKey(),
          child: _harness(cellCard, ({selfGrade, isCorrect}) {}),
        ));
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Mitochondrium');
        await tester.enterText(fields.at(1), 'Adenosintriphosphat');
        await tester.pump();
        await tester.tap(find.text('Prüfen'));
        await tester.pumpAndSettle();
      }, () => client);
      expect(find.text('Nicht ganz.'), findsOneWidget);
      expect(find.text('Lösung: ATP'), findsOneWidget);
    });
  });

  group('QuestionAnswerView – drag_drop', () {
    Future<void> dragTo(WidgetTester tester, Finder source, Finder target) async {
      await tester.drag(source, tester.getCenter(target) - tester.getCenter(source));
      await tester.pumpAndSettle();
    }

    testWidgets('richtig zugeordnete Paare gelten als korrekt', (tester) async {
      bool? reportedCorrect;
      final card = _card(
        type: QuestionType.dragDrop,
        dragPairs: const [DragPair(source: 'Hund', target: 'Tier')],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));

      await dragTo(tester, find.text('Hund'), find.text('Tier'));

      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(reportedCorrect, isTrue);
    });

    testWidgets('mehrfach genanntes Ziel: jeder Begriff belegt nur ein Feld, Frage ist lösbar', (tester) async {
      // Der gemeldete Fehler: "Metall" zweimal als Ziel – ein Begriff belegte
      // beide Felder, der Pool wurde nie leer, "Prüfen" blieb gesperrt.
      bool? reportedCorrect;
      final card = _card(
        type: QuestionType.dragDrop,
        dragPairs: const [
          DragPair(source: 'Turbinenschaufel', target: 'Metall'),
          DragPair(source: 'Fahrradrahmen', target: 'Metall'),
          DragPair(source: 'Zahnfüllung', target: 'Keramik'),
        ],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));

      // Als Kategorien angezeigt: jedes Ziel genau einmal.
      expect(find.text('Metall'), findsOneWidget);
      expect(find.text('Kategorien'), findsOneWidget);

      await dragTo(tester, find.text('Turbinenschaufel'), find.text('Metall'));
      await dragTo(tester, find.text('Fahrradrahmen'), find.text('Metall'));
      await dragTo(tester, find.text('Zahnfüllung'), find.text('Keramik'));
      expect(find.text('Turbinenschaufel'), findsOneWidget);

      final check = find.widgetWithText(FilledButton, 'Prüfen');
      expect(tester.widget<FilledButton>(check).onPressed, isNotNull);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(find.text('Richtig!'), findsOneWidget);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(reportedCorrect, isTrue);
    });

    testWidgets('belegtes Ziel: der verdrängte Begriff kommt zurück in den Pool', (tester) async {
      bool? reportedCorrect;
      final card = _card(
        type: QuestionType.dragDrop,
        dragPairs: const [
          DragPair(source: 'Eisen', target: 'Fe'),
          DragPair(source: 'Gold', target: 'Au'),
        ],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));
      await dragTo(tester, find.text('Gold'), find.text('Fe'));
      await dragTo(tester, find.text('Eisen'), find.text('Fe'));
      // "Gold" wurde von "Fe" verdrängt und liegt wieder im Pool.
      await dragTo(tester, find.text('Gold'), find.text('Au'));
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(reportedCorrect, isTrue);
    });

    testWidgets('antippen statt ziehen: Begriff wählen, dann Ziel antippen', (tester) async {
      bool? reportedCorrect;
      final card = _card(
        type: QuestionType.dragDrop,
        dragPairs: const [
          DragPair(source: 'Hund', target: 'Tier'),
          DragPair(source: 'Rose', target: 'Pflanze'),
        ],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));
      await tester.tap(find.text('Hund'));
      await tester.pump();
      await tester.tap(find.text('Tier'));
      await tester.pump();
      await tester.tap(find.text('Rose'));
      await tester.pump();
      await tester.tap(find.text('Pflanze'));
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(reportedCorrect, isTrue);
    });
  });

  group('QuestionAnswerView.optionDisplayOrder', () {
    test('mischt die Optionen, "Alle/Keine der genannten" bleiben am Ende', () {
      const options = [
        QuizOption(text: 'Richtig', isCorrect: true),
        QuizOption(text: 'Falsch 1', isCorrect: false),
        QuizOption(text: 'Falsch 2', isCorrect: false),
        QuizOption(text: 'Alle genannten', isCorrect: false),
      ];
      final seenFirst = <int>{};
      for (var seed = 0; seed < 20; seed++) {
        final order = optionDisplayOrder(options, random: Random(seed));
        expect(order.toSet(), {0, 1, 2, 3});
        expect(order.last, 3);
        seenFirst.add(order.first);
      }
      // Die richtige Option steht nicht immer vorne.
      expect(seenFirst.length, greaterThan(1));
    });
  });

  group('QuestionAnswerView – robuste Anzeige', () {
    testWidgets('Single-Choice ohne richtige Option wird zur Karteikarte', (tester) async {
      Grade? reported;
      final card = _card(
        type: QuestionType.singleChoice,
        back: '',
        options: const [QuizOption(text: 'A', isCorrect: false), QuizOption(text: 'B', isCorrect: false)],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reported = selfGrade));
      expect(find.text('Zum Umdrehen tippen'), findsOneWidget);
      await tester.tap(find.text('Frage?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nochmal'));
      await tester.pumpAndSettle();
      expect(reported, Grade.again);
    });

    testWidgets('Multiple-Choice: Prüfen erst nach einer Auswahl', (tester) async {
      final card = _card(
        type: QuestionType.multipleChoice,
        options: const [QuizOption(text: 'A', isCorrect: true), QuizOption(text: 'B', isCorrect: false)],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) {}));
      final check = find.widgetWithText(FilledButton, 'Prüfen');
      expect(tester.widget<FilledButton>(check).onPressed, isNull);
      await tester.tap(find.text('A'));
      await tester.pump();
      expect(tester.widget<FilledButton>(check).onPressed, isNotNull);
    });

    testWidgets('Lückentext mit leerer Lösung zeigt nur die lösbaren Lücken', (tester) async {
      bool? reportedCorrect;
      final card = _card(type: QuestionType.fillBlank, front: 'Hauptstadt: ___', blanks: const ['Paris', '']);
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reportedCorrect = isCorrect));
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Paris');
      await tester.pump();
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

