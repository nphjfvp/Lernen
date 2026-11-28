import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/review_log_repository.dart';
import 'package:lernen/services/answer_signals.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';

/// Rechenweg-Karte wie aus PanikImport (Angaben in taskData['panik']).
Flashcard _card({bool verified = true}) => Flashcard(
      id: 'p1',
      moduleId: 'm1',
      front: r'Lösen Sie $y′=x^2y$.',
      back: 'Lösungsweg',
      createdAt: DateTime(2026, 11, 28),
      due: DateTime(2026, 11, 28),
      taskData: {
        'panik': {
          'item': 'dgl-t-1',
          'type': 'DGL-TRENN',
          'kind': 'task',
          'core': true,
          'weight': 'H',
          'verified': verified,
          'answer': r'y=Ce^{x^3/3}',
          'steps': [
            {'title': 'Variablen trennen', 'result': r'\tfrac{dy}y=x^2dx'},
            {'title': 'Beide Seiten integrieren', 'result': r'\ln|y|=\tfrac{x^3}3+\ln|C|'},
            {'title': 'Nach y auflösen', 'result': r'y=Ce^{x^3/3}'},
          ],
        },
      },
    );

void main() {
  late List<({Grade? grade, bool? correct, AnswerSignals? signals})> results;

  Future<void> pump(WidgetTester tester, {bool verified = true}) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    results = [];
    final card = _card(verified: verified);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: QuestionAnswerView(
              key: ValueKey(card.id),
              card: card,
              isNew: false,
              onComplete: ({Grade? selfGrade, bool? isCorrect, AnswerSignals? signals}) =>
                  results.add((grade: selfGrade, correct: isCorrect, signals: signals)),
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  testWidgets('Lösung erst nach dem Rechnen, dann Schritt für Schritt', (tester) async {
    await pump(tester);
    expect(find.textContaining('Auf Papier rechnen'), findsOneWidget);
    expect(find.byKey(const ValueKey('panik-step-0')), findsNothing);
    await tap(tester, 'panik-reveal');
    expect(find.byKey(const ValueKey('panik-step-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('panik-step-1')), findsNothing);
    expect(find.textContaining('Variablen trennen'), findsOneWidget);
    await tap(tester, 'panik-ok');
    expect(find.byKey(const ValueKey('panik-step-1')), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('alles stimmt + „ging leicht“ → richtig und sicher (Gut)', (tester) async {
    await pump(tester);
    await tap(tester, 'panik-reveal');
    for (var i = 0; i < 3; i++) {
      await tap(tester, 'panik-ok');
    }
    await tap(tester, 'panik-easy');
    expect(results, hasLength(1));
    expect(results.single.correct, isTrue);
    expect(results.single.signals!.confidence, AnswerConfidence.sure);
    expect(AnswerSignals.gradeFor(isCorrect: true, signals: results.single.signals!), Grade.good);
  });

  testWidgets('erster Fehler: Ursache wählen, Rest sichtbar, falsch mit Ursache und Schritt', (tester) async {
    await pump(tester);
    await tap(tester, 'panik-reveal');
    await tap(tester, 'panik-ok');
    await tap(tester, 'panik-wrong');
    expect(find.textContaining('Schritt 2'), findsWidgets);
    await tap(tester, 'panik-cause-sign');
    expect(find.byKey(const ValueKey('panik-step-2')), findsOneWidget);
    await tap(tester, 'panik-done');
    expect(results.single.correct, isFalse);
    expect(results.single.signals!.errorCause, ErrorCause.sign);
    expect(results.single.signals!.errorStep, 2);
  });

  testWidgets('„Ich komme nicht weiter“ zeigt alles und zählt als Weiß ich nicht', (tester) async {
    await pump(tester);
    await tap(tester, 'panik-stuck');
    expect(find.byKey(const ValueKey('panik-step-2')), findsOneWidget);
    await tap(tester, 'panik-done');
    expect(results.single.correct, isFalse);
    expect(results.single.signals!.dontKnow, isTrue);
  });

  testWidgets('ungeprüfte Lösung ist sichtbar markiert', (tester) async {
    await pump(tester, verified: false);
    expect(find.text('Lösung ungeprüft'), findsOneWidget);
  });

  test('Fehlerursache und Schritt landen im Antwort-Protokoll', () {
    final entry = ReviewLogEntry.of(
      _card(),
      grade: Grade.again,
      correct: false,
      signals: const AnswerSignals(errorCause: ErrorCause.formula, errorStep: 3),
    );
    final back = ReviewLogEntry.fromMap(entry.toMap());
    expect((back.errorCause, back.errorStep), (ErrorCause.formula, 3));
    expect(ReviewLogEntry.fromMap(ReviewLogEntry.of(_card(), grade: Grade.good).toMap()).errorCause, isNull);
  });
}
