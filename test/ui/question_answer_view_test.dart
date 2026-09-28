import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
import 'package:lernen/ui/widgets/relative_image.dart';
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

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), ui.Paint()..color = const ui.Color(0xFF3366CC));
  final image = await recorder.endRecording().toImage(width, height);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
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

    testWidgets('abgelehnte Freitext-Antwort lässt sich als richtig werten, eine richtige nicht', (tester) async {
      final card = _card(type: QuestionType.freeText, correctText: 'Photosynthese');
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) {}));
      await tester.enterText(find.byType(TextField), 'Lichtreaktion');
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Als richtig werten'));
      await tester.pumpAndSettle();
      expect(find.text('Richtig!'), findsOneWidget);
      expect(find.text('Als richtig werten'), findsNothing);
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
      // Nach dem Prüfen kommen Lösung, Erklärung und Lernhilfen dazu.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
      // Sichtbar, dass die KI nicht prüfen konnte – plus Ausweg per Hand.
      expect(find.textContaining('KI-Prüfung fehlgeschlagen'), findsOneWidget);
      expect(find.text('Als richtig werten'), findsOneWidget);
    });

    testWidgets('vertauschte Lücken + Tippfehler: KI wertet alles richtig und begründet je Lücke', (tester) async {
      final card = _card(
        type: QuestionType.fillBlank,
        front: 'Der Kunde bestimmt bei ___ und ___ mit; Werkstoffe haben ___ Eigenschaften.',
        blanks: const ['Entwicklung', 'Produktion', 'definierten'],
      );
      bool? reported;
      final client = MockClient((request) async => _chatResponse({
            'results': [
              {'correct': true, 'note': 'Reihenfolge vertauscht'},
              {'correct': true, 'note': 'Reihenfolge vertauscht'},
              {'correct': true, 'note': 'Tippfehler'},
            ],
          }));
      await http.runWithClient(() async {
        await tester.pumpWidget(ChangeNotifierProvider<SettingsRepository>(
          create: (_) => _SettingsWithKey(),
          child: _harness(card, ({selfGrade, isCorrect}) => reported = isCorrect),
        ));
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Produktion');
        await tester.enterText(fields.at(1), 'Entwicklung');
        await tester.enterText(fields.at(2), 'debinrten');
        await tester.pump();
        await tester.tap(find.text('Prüfen'));
        await tester.pumpAndSettle();
      }, () => client);

      expect(find.text('Richtig!'), findsOneWidget);
      expect(find.text('Von der KI nachgeprüft.'), findsOneWidget);
      expect(find.text('Lösung: definierten · KI: Tippfehler'), findsOneWidget);
      expect(find.text('Lösung: Entwicklung · KI: Reihenfolge vertauscht'), findsOneWidget);
      expect(find.text('Als richtig werten'), findsNothing);
      await tester.scrollUntilVisible(find.text('Weiter'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(reported, isTrue);
    });

    testWidgets('"Als richtig werten" macht eine abgelehnte Antwort richtig', (tester) async {
      bool? reported;
      await tester.pumpWidget(_harness(cellCard, ({selfGrade, isCorrect}) => reported = isCorrect));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Mitochondrium');
      await tester.enterText(fields.at(1), 'Adenosintriphosphat');
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      expect(find.text('Nicht ganz.'), findsOneWidget);

      await tester.tap(find.text('Als richtig werten'));
      await tester.pumpAndSettle();
      expect(find.text('Richtig!'), findsOneWidget);
      expect(find.text('Von dir als richtig gewertet.'), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsNothing);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(reported, isTrue);
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

  group('QuestionAnswerView – Tabelle', () {
    Flashcard tableCard() => Flashcard(
          id: 't1',
          moduleId: 'm1',
          front: 'Ordne die Symbole zu.',
          back: '',
          createdAt: DateTime(2026, 1, 1),
          due: DateTime(2026, 1, 1),
          type: QuestionType.table,
          tableRows: const [
            [QuestionTableCell(text: 'Element'), QuestionTableCell(text: 'Symbol')],
            [QuestionTableCell(text: 'Wasserstoff'), QuestionTableCell(text: 'H', given: false)],
            [QuestionTableCell(text: 'Helium'), QuestionTableCell(text: 'He', given: false)],
            [QuestionTableCell(text: 'Lithium'), QuestionTableCell(text: 'Li', given: false)],
            [QuestionTableCell(text: 'Kohlenstoff'), QuestionTableCell(text: 'C', given: false)],
            [QuestionTableCell(text: 'Natrium'), QuestionTableCell(text: 'Na', given: false)],
          ],
        );

    Future<({Grade? grade, bool? correct})> answer(WidgetTester tester, List<String> answers) async {
      Grade? grade;
      bool? correct;
      await tester.pumpWidget(_harness(tableCard(), ({selfGrade, isCorrect}) {
        grade = selfGrade;
        correct = isCorrect;
      }));
      expect(find.text('Wasserstoff'), findsOneWidget);
      for (var i = 0; i < answers.length; i++) {
        await tester.enterText(find.byKey(ValueKey('table-cell-${i + 1}-1')), answers[i]);
      }
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      return (grade: grade, correct: correct);
    }

    testWidgets('alle Zellen richtig: richtig ohne Abwertung', (tester) async {
      final r = await answer(tester, ['H', 'He', 'Li', 'C', 'Na']);
      expect(r.correct, isTrue);
      expect(r.grade, isNull);
    });

    testWidgets('4 von 5 Zellen: fast richtig, zählt als Schwer', (tester) async {
      final r = await answer(tester, ['H', 'He', 'Li', 'C', 'K']);
      expect(find.textContaining('4 von 5 Zellen richtig'), findsOneWidget);
      expect(r.correct, isTrue);
      expect(r.grade, Grade.hard);
    });

    testWidgets('3 von 5 Zellen: falsch, Lösung wird angezeigt', (tester) async {
      Grade? grade;
      bool? correct;
      await tester.pumpWidget(_harness(tableCard(), ({selfGrade, isCorrect}) {
        grade = selfGrade;
        correct = isCorrect;
      }));
      for (final (i, a) in ['H', 'He', 'Li', 'O', 'K'].indexed) {
        await tester.enterText(find.byKey(ValueKey('table-cell-${i + 1}-1')), a);
      }
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 von 5 Zellen richtig'), findsOneWidget);
      expect(find.text('Lösung: Na'), findsOneWidget);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(correct, isFalse);
      expect(grade, isNull);
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

  group('QuestionAnswerView – Bildfragen', () {
    Future<Flashcard> imageCard(WidgetTester tester, QuestionType type, List<ImageTarget> targets) async {
      final png = (await tester.runAsync(() => _png(200, 100)))!;
      return Flashcard(
        id: 'img',
        moduleId: 'm1',
        front: type == QuestionType.markImage ? 'Wo liegt der Kern?' : 'Beschrifte die Zelle',
        back: type == QuestionType.markImage ? 'in der Mitte' : '',
        createdAt: DateTime(2026, 9, 27),
        due: DateTime(2026, 9, 27),
        type: type,
        imageBase64: base64Encode(png),
        imageTargets: targets,
      );
    }

    Future<void> showImage(WidgetTester tester) async {
      // Bildgröße wird asynchron dekodiert.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
    }

    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(800, 1600);
      binding.platformDispatcher.views.first.devicePixelRatio = 1;
    });
    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });

    testWidgets('Bild beschriften: antippen und Stelle antippen, richtig zugeordnet', (tester) async {
      bool? reported;
      final card = await imageCard(tester, QuestionType.diagramLabel, const [
        ImageTarget(x: 0.25, y: 0.5, label: 'Zellkern'),
        ImageTarget(x: 0.75, y: 0.5, label: 'Mitochondrium'),
      ]);
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reported = isCorrect));
      await showImage(tester);

      expect(find.byKey(const ValueKey('label-zone-0')), findsOneWidget);
      expect(find.text('Prüfen'), findsOneWidget);
      await tester.tap(find.text('Zellkern'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('label-zone-0')));
      await tester.pump();
      expect(find.text('1 · Zellkern'), findsOneWidget);

      await tester.tap(find.text('Mitochondrium'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('label-zone-1')));
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      expect(find.text('Richtig!'), findsOneWidget);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(reported, isTrue);
    });

    testWidgets('Bild beschriften: falsch zugeordnet zeigt die richtige Beschriftung', (tester) async {
      final card = await imageCard(tester, QuestionType.diagramLabel, const [
        ImageTarget(x: 0.25, y: 0.5, label: 'Zellkern'),
        ImageTarget(x: 0.75, y: 0.5, label: 'Mitochondrium'),
      ]);
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) {}));
      await showImage(tester);

      await tester.tap(find.text('Mitochondrium'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('label-zone-0')));
      await tester.pump();
      await tester.tap(find.text('Zellkern'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('label-zone-1')));
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      expect(find.text('Nicht ganz.'), findsOneWidget);
      expect(find.text('Stelle 1: richtig ist „Zellkern“'), findsOneWidget);
    });

    testWidgets('Bild beschriften eintippen: Tippfehler und vertauschte Gruppe zählen', (tester) async {
      bool? reported;
      final card = await imageCard(tester, QuestionType.diagramLabel, const [
        ImageTarget(x: 0.2, y: 0.3, label: 'Arbeit', group: 'Input'),
        ImageTarget(x: 0.2, y: 0.7, label: 'Kapital', group: 'Input'),
        ImageTarget(x: 0.8, y: 0.5, label: 'Produkt'),
      ]);
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reported = isCorrect));
      await showImage(tester);

      await tester.tap(find.text('Eintippen'));
      await tester.pump();
      // Im Eintipp-Modus sind die Beschriftungen nicht vorgegeben.
      expect(find.text('Kapital'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('label-input-0')), 'Kapitall');
      await tester.enterText(find.byKey(const ValueKey('label-input-1')), 'arbeit');
      await tester.enterText(find.byKey(const ValueKey('label-input-2')), 'Produkt');
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      expect(find.text('Richtig!'), findsOneWidget);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(reported, isTrue);
    });

    testWidgets('Bild beschriften eintippen: falsche Stelle zeigt die Lösung, "Als richtig werten" möglich',
        (tester) async {
      bool? reported;
      final card = await imageCard(tester, QuestionType.diagramLabel, const [
        ImageTarget(x: 0.25, y: 0.5, label: 'Zellkern'),
        ImageTarget(x: 0.75, y: 0.5, label: 'Mitochondrium'),
      ]);
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) => reported = isCorrect));
      await showImage(tester);

      await tester.tap(find.text('Eintippen'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('label-input-0')), 'Zellkern');
      await tester.enterText(find.byKey(const ValueKey('label-input-1')), 'Kraftwerk der Zelle');
      await tester.pump();
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      expect(find.text('Nicht ganz.'), findsOneWidget);
      expect(find.text('Richtig: „Mitochondrium“'), findsOneWidget);

      await tester.tap(find.text('Als richtig werten'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(reported, isTrue);
    });

    testWidgets('Bild markieren: Treffer und Fehlschuss', (tester) async {
      for (final (fx, expected) in [(0.5, 'Richtig!'), (0.1, 'Nicht ganz.')]) {
        final card = await imageCard(tester, QuestionType.markImage, const [
          ImageTarget(x: 0.5, y: 0.5, w: 0.2, h: 0.3),
        ]);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) {}));
        await showImage(tester);

        final box = tester.getRect(find.descendant(of: find.byType(RelativeImage), matching: find.byType(Stack)).first);
        await tester.tapAt(Offset(box.left + box.width * fx, box.top + box.height * 0.5));
        await tester.pump();
        expect(find.byKey(const ValueKey('mark-marker')), findsOneWidget);
        await tester.tap(find.text('Prüfen'));
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget);
      }
    });

    testWidgets('ohne Bild wird eine Bildfrage als Karteikarte gezeigt', (tester) async {
      final card = Flashcard(
        id: 'noimg',
        moduleId: 'm1',
        front: 'Wo liegt der Kern?',
        back: 'in der Mitte',
        createdAt: DateTime(2026, 9, 27),
        due: DateTime(2026, 9, 27),
        type: QuestionType.markImage,
        imageTargets: const [ImageTarget(x: 0.5, y: 0.5)],
      );
      await tester.pumpWidget(_harness(card, ({selfGrade, isCorrect}) {}));
      await tester.pump();
      expect(find.text('Prüfen'), findsNothing);
      expect(find.textContaining('Wo liegt der Kern?'), findsOneWidget);
    });

    testWidgets('unnötiges Bild beim Lernen entfernen', (tester) async {
      final png = (await tester.runAsync(() => _png(200, 100)))!;
      final card = Flashcard(
        id: 'rm',
        moduleId: 'm1',
        front: 'Was ist ATP?',
        back: 'Energieträger',
        createdAt: DateTime(2026, 9, 27),
        due: DateTime(2026, 9, 27),
        imageBase64: base64Encode(png),
      );
      var called = false;
      Uint8List? saved = Uint8List(1);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: QuestionAnswerView(
                  card: card,
                  isNew: false,
                  onComplete: ({selfGrade, isCorrect}) {},
                  onImageEdited: (bytes) async {
                    called = true;
                    saved = bytes;
                  },
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.byTooltip('Bild entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
      expect(saved, isNull);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('Bild beim Lernen bearbeiten: abgedecktes Bild wird gemeldet und angezeigt', (tester) async {
      final png = (await tester.runAsync(() => _png(200, 100)))!;
      final card = Flashcard(
        id: 'edit',
        moduleId: 'm1',
        front: 'Was ist markiert?',
        back: 'Zellkern',
        createdAt: DateTime(2026, 9, 27),
        due: DateTime(2026, 9, 27),
        imageBase64: base64Encode(png),
      );
      Uint8List? saved;
      Widget view({bool withCallback = true}) => MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: QuestionAnswerView(
                      card: card,
                      isNew: false,
                      onComplete: ({selfGrade, isCorrect}) {},
                      onImageEdited: withCallback ? (bytes) async => saved = bytes : null,
                    ),
                  ),
                ],
              ),
            ),
          );

      // Ohne Speicher-Callback (z.B. Vorschau) kein Bearbeiten-Knopf.
      await tester.pumpWidget(view(withCallback: false));
      expect(find.byTooltip('Bild bearbeiten (z.B. Antwort abdecken)'), findsNothing);

      await tester.pumpWidget(view());
      // Bild erst dekodieren lassen – vorher hat es keine Größe.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bild bearbeiten (z.B. Antwort abdecken)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Seitenübergang
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      final box = tester.getRect(find
          .descendant(of: find.byKey(const ValueKey('image-editor-canvas')), matching: find.byType(Stack))
          .first);
      await tester.dragFrom(Offset(box.left + box.width * 0.1, box.top + box.height * 0.1),
          Offset(box.width * 0.4, box.height * 0.5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved, isNot(png));
      final shown = tester.widget<Image>(find.byType(Image).first).image as MemoryImage;
      expect(shown.bytes, same(saved));
    });
  });
}
